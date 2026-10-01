-- Vocab Bluff: shared group confetti
-- Run once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Assumes groups.id is a uuid (the Supabase default). If yours is a bigint, change
-- "group_id uuid" below to "group_id bigint".

create table if not exists public.confetti_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null check (kind in ('visit', 'enter', 'define', 'correct')),
  ref_id text,
  created_at timestamptz not null default now()
);

create index if not exists confetti_events_group_time on public.confetti_events (group_id, created_at desc);
create index if not exists confetti_events_user_kind_ref on public.confetti_events (user_id, kind, ref_id);

alter table public.confetti_events enable row level security;

-- Group members can see their group's confetti
create policy "Members can view group confetti" on public.confetti_events
  for select using (
    exists (select 1 from public.group_members gm
            where gm.group_id = confetti_events.group_id and gm.user_id = auth.uid())
  );

-- Members can add confetti to their own groups, as themselves
create policy "Members can add their own confetti" on public.confetti_events
  for insert with check (
    user_id = auth.uid()
    and exists (select 1 from public.group_members gm
                where gm.group_id = confetti_events.group_id and gm.user_id = auth.uid())
  );

-- Lets everyone see each other's bursts live while the app is open
alter publication supabase_realtime add table public.confetti_events;

-- Optional cleanup of confetti that has fully faded (older than 3 days):
-- delete from public.confetti_events where created_at < now() - interval '3 days';
