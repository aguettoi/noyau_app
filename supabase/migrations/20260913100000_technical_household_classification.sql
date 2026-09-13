-- Context classification only: it is never an authorization mechanism.
alter table public.households
  add column classification text not null default 'operational';

alter table public.households
  add constraint households_classification_check
  check (classification in ('operational', 'technical'));

comment on column public.households.classification is
  'Application context classification. RLS and RPC authorization remain based exclusively on household membership.';
