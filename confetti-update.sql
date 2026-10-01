-- Only needed if you ALREADY ran confetti.sql before this update.
-- Allows the new 'review' confetti (correct answers in the Review test).
alter table public.confetti_events drop constraint if exists confetti_events_kind_check;
alter table public.confetti_events add constraint confetti_events_kind_check
  check (kind in ('visit', 'enter', 'define', 'correct', 'review'));
