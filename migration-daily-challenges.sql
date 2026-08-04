-- ===========================================
-- VOCAB BLUFF - Daily Challenges & Streaks Migration
-- ===========================================
-- Run this ONCE in your Supabase SQL Editor, after the original
-- supabase-schema.sql has already been applied.
--
-- What this adds:
--   1. rounds.round_type / round_date / review_round_ids
--      -> a round is now either 'word' (the bluff game) or 'review'
--         (a cumulative test of the last 7 words)
--   2. group_progress
--      -> one row per group tracking streaks + where they are in the
--         7-word cycle
--   3. review_completions
--      -> tracks which members have finished a given weekly review
--   4. ensure_daily_challenge(group_id)
--      -> call this whenever a group screen loads. Idempotent: creates
--         today's word round or review round if one doesn't exist yet,
--         does nothing otherwise.
--   5. complete_challenge(group_id, round_id)
--      -> call this once a round is fully completed (all members
--         submitted+voted, or all members finished the review).
--         Advances the streak / cycle bookkeeping.
-- ===========================================

-- ===========================================
-- 1. ROUNDS: distinguish word rounds from review rounds
-- ===========================================

alter table public.rounds add column if not exists round_type text not null default 'word' check (round_type in ('word', 'review'));
alter table public.rounds add column if not exists round_date date;
alter table public.rounds add column if not exists review_round_ids uuid[];

-- backfill round_date for any existing rows from when they were created
update public.rounds set round_date = created_at::date where round_date is null;

alter table public.rounds alter column round_date set default current_date;
alter table public.rounds alter column round_date set not null;

create index if not exists rounds_group_date_idx on public.rounds(group_id, round_date);

-- ===========================================
-- 2. GROUP PROGRESS (streaks + cycle position)
-- ===========================================

create table if not exists public.group_progress (
  group_id uuid primary key references public.groups(id) on delete cascade,
  words_completed int not null default 0,   -- cumulative word-rounds completed
  cycle_count int not null default 0,       -- how many weekly reviews completed
  review_due boolean not null default false,-- true once the 7th word of a cycle is done, until the review is completed
  current_streak int not null default 0,
  longest_streak int not null default 0,
  last_active_date date,                    -- last calendar day the group fully completed a challenge
  updated_at timestamp with time zone default now()
);

alter table public.group_progress enable row level security;

create policy "Members can view group progress" on public.group_progress for select using (
  exists (select 1 from public.group_members where group_members.group_id = group_progress.group_id and group_members.user_id = auth.uid())
);
-- No direct insert/update policy for regular users: all writes happen inside
-- the SECURITY DEFINER functions below.

-- ===========================================
-- 3. REVIEW COMPLETIONS (per-member completion of a weekly review round)
-- ===========================================

create table if not exists public.review_completions (
  id uuid default uuid_generate_v4() primary key,
  round_id uuid references public.rounds(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  score int not null default 0,
  total int not null default 0,
  completed_at timestamp with time zone default now(),
  unique(round_id, user_id)
);

alter table public.review_completions enable row level security;

create policy "Members can view review completions" on public.review_completions for select using (
  exists (
    select 1 from public.rounds r
    join public.group_members gm on gm.group_id = r.group_id
    where r.id = review_completions.round_id and gm.user_id = auth.uid()
  )
);
create policy "Users can record own review completion" on public.review_completions for insert with check (auth.uid() = user_id);

-- ===========================================
-- 4. ensure_daily_challenge(group_id)
-- ===========================================
-- Called by any client when a group screen loads. Idempotent per calendar day.

create or replace function public.ensure_daily_challenge(p_group_id uuid)
returns public.rounds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := current_date;
  v_progress public.group_progress;
  v_round public.rounds;
  v_word_id uuid;
  v_review_ids uuid[];
begin
  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid()
  ) then
    raise exception 'not a member of this group';
  end if;

  insert into public.group_progress (group_id)
  values (p_group_id)
  on conflict (group_id) do nothing;

  select * into v_progress from public.group_progress where group_id = p_group_id for update;

  -- if the group missed a whole day, visibly break the streak right away
  -- (it will also get recomputed on next completion, but this makes the
  -- UI correct as soon as someone reopens the app)
  if v_progress.last_active_date is not null
     and v_progress.last_active_date < v_today - 1
     and v_progress.current_streak > 0 then
    update public.group_progress
    set current_streak = 0, updated_at = now()
    where group_id = p_group_id
    returning * into v_progress;
  end if;

  -- already have a challenge for today?
  select * into v_round from public.rounds
  where group_id = p_group_id and round_date = v_today
  order by created_at desc
  limit 1;

  if found then
    return v_round;
  end if;

  if v_progress.review_due then
    select array_agg(id) into v_review_ids
    from (
      select id from public.rounds
      where group_id = p_group_id and round_type = 'word'
      order by created_at desc
      limit 7
    ) recent;

    insert into public.rounds (group_id, word_id, phase, round_type, round_date, review_round_ids)
    values (p_group_id, null, 'results', 'review', v_today, v_review_ids)
    returning * into v_round;
  else
    select id into v_word_id
    from public.words
    where id not in (
      select word_id from public.rounds
      where group_id = p_group_id and round_type = 'word' and word_id is not null
    )
    order by random()
    limit 1;

    if v_word_id is null then
      -- exhausted the word bank for this group; allow repeats
      select id into v_word_id from public.words order by random() limit 1;
    end if;

    insert into public.rounds (group_id, word_id, phase, round_type, round_date)
    values (p_group_id, v_word_id, 'submitting', 'word', v_today)
    returning * into v_round;
  end if;

  return v_round;
end;
$$;

grant execute on function public.ensure_daily_challenge(uuid) to authenticated;

-- ===========================================
-- 5. complete_challenge(group_id, round_id)
-- ===========================================
-- Called once a round is fully completed by the group. Advances the
-- streak and, for word rounds, tracks progress toward the next review.

create or replace function public.complete_challenge(p_group_id uuid, p_round_id uuid)
returns public.group_progress
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := current_date;
  v_progress public.group_progress;
  v_round public.rounds;
  v_new_streak int;
  v_new_words_completed int;
  v_review_due boolean;
  v_new_cycle_count int;
begin
  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid()
  ) then
    raise exception 'not a member of this group';
  end if;

  select * into v_round from public.rounds where id = p_round_id and group_id = p_group_id;
  if not found then
    raise exception 'round not found';
  end if;

  insert into public.group_progress (group_id)
  values (p_group_id)
  on conflict (group_id) do nothing;

  select * into v_progress from public.group_progress where group_id = p_group_id for update;

  -- already recorded a completion today, don't double-count
  if v_progress.last_active_date = v_today then
    return v_progress;
  end if;

  if v_progress.last_active_date = v_today - 1 then
    v_new_streak := v_progress.current_streak + 1;
  else
    v_new_streak := 1;
  end if;

  v_new_words_completed := v_progress.words_completed;
  v_review_due := v_progress.review_due;
  v_new_cycle_count := v_progress.cycle_count;

  if v_round.round_type = 'word' then
    v_new_words_completed := v_new_words_completed + 1;
    if v_new_words_completed % 7 = 0 then
      v_review_due := true;
    end if;
  elsif v_round.round_type = 'review' then
    v_review_due := false;
    v_new_cycle_count := v_new_cycle_count + 1;
  end if;

  update public.group_progress
  set
    current_streak = v_new_streak,
    longest_streak = greatest(v_progress.longest_streak, v_new_streak),
    last_active_date = v_today,
    words_completed = v_new_words_completed,
    review_due = v_review_due,
    cycle_count = v_new_cycle_count,
    updated_at = now()
  where group_id = p_group_id
  returning * into v_progress;

  return v_progress;
end;
$$;

grant execute on function public.complete_challenge(uuid, uuid) to authenticated;
