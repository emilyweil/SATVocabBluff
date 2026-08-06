-- ===========================================
-- VOCAB BLUFF - Word Diversity Across Groups
-- ===========================================
-- Run this ONCE in your Supabase SQL Editor, after
-- migration-daily-challenges.sql has already been applied.
--
-- What this changes:
--   ensure_daily_challenge() previously only avoided repeating a word
--   within the SAME group. If you were in two groups, both could
--   independently pick the same word out of the ~400-word bank early on
--   (low odds per pick, but real). This redefines the function so a new
--   word is also excluded if it's already been used in ANY group that
--   the person who triggers the challenge (the first member to open the
--   app that day) is a member of. In practice this means you won't see
--   a repeated word across your own groups until the entire word bank
--   has been used up by you.
-- ===========================================

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

  if v_progress.last_active_date is not null
     and v_progress.last_active_date < v_today - 1
     and v_progress.current_streak > 0 then
    update public.group_progress
    set current_streak = 0, updated_at = now()
    where group_id = p_group_id
    returning * into v_progress;
  end if;

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
    -- Prefer a word this calling user hasn't seen in ANY of their groups yet
    -- (not just this one), so a person in multiple groups doesn't get the
    -- same word twice early on.
    select id into v_word_id
    from public.words
    where id not in (
      select r.word_id
      from public.rounds r
      join public.group_members gm on gm.group_id = r.group_id
      where gm.user_id = auth.uid() and r.round_type = 'word' and r.word_id is not null
    )
    order by random()
    limit 1;

    if v_word_id is null then
      -- fall back to just avoiding repeats within this specific group
      select id into v_word_id
      from public.words
      where id not in (
        select word_id from public.rounds
        where group_id = p_group_id and round_type = 'word' and word_id is not null
      )
      order by random()
      limit 1;
    end if;

    if v_word_id is null then
      -- word bank fully exhausted everywhere; allow repeats
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
