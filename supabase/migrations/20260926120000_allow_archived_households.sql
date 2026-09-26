-- Allow historical households to remain auditable without being selected as
-- the active operational household.
alter table public.households
  drop constraint if exists households_classification_check;

alter table public.households
  add constraint households_classification_check
  check (classification in ('operational', 'technical', 'archived'));

comment on column public.households.classification is
  'Application context classification. operational is active, technical is for fixtures, and archived is historical; RLS and RPC authorization remain based exclusively on household membership.';
