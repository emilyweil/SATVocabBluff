-- Vocab Bluff: shared group confetti + shared raking
-- Run in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Safe to run more than once, and safe to run even if you ran an earlier version.
-- Assumes groups.id is a uuid (the Supabase default). If yours is a bigint, change
-- both "group_id uuid" lines below to "group_id bigint".

-- ---------- Confetti bursts ----------
create table if not exists public.confetti_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null,
  ref_id text,
  created_at timestamptz not null default now()
);
alter table public.confetti_events drop constraint if exists confetti_events_kind_check;
alter table public.confetti_events add constraint confetti_events_kind_check
  check (kind in ('visit', 'enter', 'define', 'correct', 'review'));

create index if not exists confetti_events_group_time on public.confetti_events (group_id, created_at desc);
create index if not exists confetti_events_user_kind_ref on public.confetti_events (user_id, kind, ref_id);

-- ---------- Rake strokes (where raked pieces ended up) ----------
create table if not exists public.confetti_rakes (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  moves jsonb not null,  -- [[event_id, piece_index, x, y], ...]
  created_at timestamptz not null default now()
);
create index if not exists confetti_rakes_group_time on public.confetti_rakes (group_id, created_at);

-- ---------- Only members of a group can see or add its confetti ----------
alter table public.confetti_events enable row level security;
alter table public.confetti_rakes enable row level security;

drop policy if exists "Members can view group confetti" on public.confetti_events;
create policy "Members can view group confetti" on public.confetti_events
  for select using (exists (select 1 from public.group_members gm
                            where gm.group_id = confetti_events.group_id and gm.user_id = auth.uid()));

drop policy if exists "Members can add their own confetti" on public.confetti_events;
create policy "Members can add their own confetti" on public.confetti_events
  for insert with check (user_id = auth.uid()
                         and exists (select 1 from public.group_members gm
                                     where gm.group_id = confetti_events.group_id and gm.user_id = auth.uid()));

drop policy if exists "Members can view group rakes" on public.confetti_rakes;
create policy "Members can view group rakes" on public.confetti_rakes
  for select using (exists (select 1 from public.group_members gm
                            where gm.group_id = confetti_rakes.group_id and gm.user_id = auth.uid()));

drop policy if exists "Members can add their own rakes" on public.confetti_rakes;
create policy "Members can add their own rakes" on public.confetti_rakes
  for insert with check (user_id = auth.uid()
                         and exists (select 1 from public.group_members gm
                                     where gm.group_id = confetti_rakes.group_id and gm.user_id = auth.uid()));

-- ---------- Live updates (bursts and raking appear for others in real time) ----------
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'confetti_events') then
    alter publication supabase_realtime add table public.confetti_events;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'confetti_rakes') then
    alter publication supabase_realtime add table public.confetti_rakes;
  end if;
end $$;

-- Optional cleanup of fully faded confetti (older than 3 days):
-- delete from public.confetti_events where created_at < now() - interval '3 days';
-- delete from public.confetti_rakes  where created_at < now() - interval '3 days';
