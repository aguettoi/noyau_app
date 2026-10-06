-- F2C: searchable canonical history, daily reversals, and private evidence.
begin;

alter table public.financial_events drop constraint if exists financial_events_event_type_check;
alter table public.financial_events add constraint financial_events_event_type_check check (event_type in (
  'cash_expense','cash_income','debt_expense','debt_settlement','income_receivable',
  'receivable_settlement','recovery_receivable','recovery_settlement','budget_allocation',
  'account_transfer','envelope_transfer','debt_writeoff','income_receivable_writeoff',
  'recovery_writeoff','recovery_reversal','debt_settlement_reversal',
  'receivable_settlement_reversal','recovery_settlement_reversal','debt_writeoff_reversal',
  'income_receivable_writeoff_reversal','recovery_writeoff_reversal','account_opening',
  'envelope_opening','obligation_opening','daily_reversal'
));

alter table public.financial_transactions drop constraint if exists financial_transactions_type_check;
alter table public.financial_transactions add constraint financial_transactions_type_check check (type in (
  'allocation','expense','transfer','adjustment','recovery','income','opening_balance',
  'correction','debt_expense','debt_settlement','income_receivable',
  'receivable_settlement','recovery_receivable','recovery_settlement',
  'debt_writeoff','income_receivable_writeoff','recovery_writeoff','recovery_reversal',
  'debt_settlement_reversal','receivable_settlement_reversal','recovery_settlement_reversal',
  'debt_writeoff_reversal','income_receivable_writeoff_reversal','recovery_writeoff_reversal','reversal'
));

create table public.daily_operation_reversals (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id),
  original_event_id uuid not null references public.financial_events(id),
  reversal_event_id uuid not null unique references public.financial_events(id),
  reason_code text not null check (reason_code in (
    'wrong_amount','wrong_account','wrong_envelope','duplicate','cancelled','other'
  )),
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (original_event_id)
);
create index daily_operation_reversals_household_idx
  on public.daily_operation_reversals(household_id, created_at desc);
alter table public.daily_operation_reversals enable row level security;
revoke all on table public.daily_operation_reversals from public, anon;
grant select on table public.daily_operation_reversals to authenticated;
create policy daily_operation_reversals_member_read on public.daily_operation_reversals
  for select to authenticated using (public.is_household_member(household_id));
create trigger daily_operation_reversals_immutable before update or delete
  on public.daily_operation_reversals for each row
  execute function public.prevent_financial_event_mutation();

create or replace function public.reverse_daily_financial_event(
  p_household_id uuid,
  p_original_event_id uuid,
  p_occurred_at timestamptz,
  p_reason_code text,
  p_reason text,
  p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path = public, auth as $$
declare
  v_original public.financial_events%rowtype;
  v_original_tx public.financial_transactions%rowtype;
  v_reversal_event_id uuid;
  v_reversal_tx_id uuid;
  v_group_id uuid := gen_random_uuid();
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_reason_code not in ('wrong_amount','wrong_account','wrong_envelope','duplicate','cancelled','other')
     or char_length(trim(coalesce(p_reason,''))) not between 1 and 500 then
    raise exception 'A valid reversal reason is required';
  end if;
  select * into v_original from public.financial_events
    where id = p_original_event_id and household_id = p_household_id for update;
  if not found then raise exception 'Original FinancialEvent does not belong to household'; end if;
  if v_original.event_type not in ('cash_expense','cash_income','account_transfer','envelope_transfer') then
    raise exception 'This FinancialEvent type cannot be reversed from the daily workflow';
  end if;
  if exists (select 1 from public.daily_operation_reversals where original_event_id = p_original_event_id) then
    select reversal_event_id into v_reversal_event_id from public.daily_operation_reversals
      where original_event_id = p_original_event_id;
    if exists (select 1 from public.financial_events where id = v_reversal_event_id
      and idempotency_key = p_idempotency_key) then return v_reversal_event_id; end if;
    raise exception 'FinancialEvent was already reversed';
  end if;
  v_reversal_event_id := public.create_or_get_financial_event(
    p_household_id, 'daily_reversal', coalesce(p_occurred_at, now()),
    'Annulation — ' || v_original.description, trim(p_reason), p_idempotency_key
  );
  if exists (select 1 from public.daily_operation_reversals where reversal_event_id = v_reversal_event_id) then
    return v_reversal_event_id;
  end if;

  select * into v_original_tx from public.financial_transactions
    where event_id = p_original_event_id and household_id = p_household_id;
  if found then
    insert into public.financial_transactions(
      household_id,event_id,type,occurred_at,reason,description,amount,currency_code,
      source_account_id,destination_account_id,notes,created_by,validated_at
    ) values (
      p_household_id,v_reversal_event_id,'reversal',coalesce(p_occurred_at,now()),
      trim(p_reason),'Annulation — '||v_original.description,v_original_tx.amount,
      coalesce(v_original_tx.currency_code,'MAD'),v_original_tx.destination_account_id,
      v_original_tx.source_account_id,trim(p_reason),auth.uid(),now()
    ) returning id into v_reversal_tx_id;
    insert into public.financial_transaction_lines(
      transaction_id,account_id,envelope_id,member_id,amount,debit,credit,occurred_at
    ) select v_reversal_tx_id,account_id,envelope_id,member_id,-amount,credit,debit,
      coalesce(p_occurred_at,now())
      from public.financial_transaction_lines where transaction_id = v_original_tx.id;
    insert into public.financial_audit_events(household_id,transaction_id,action,reason,actor_id)
      values (p_household_id,v_reversal_tx_id,'reversed',trim(p_reason),auth.uid());
  end if;

  insert into public.envelope_movements(
    household_id,event_id,envelope_id,financial_transaction_id,movement_group_id,
    movement_type,direction,amount,occurred_at,description,reversal_of,created_by
  ) select p_household_id,v_reversal_event_id,envelope_id,v_reversal_tx_id,v_group_id,
    'reversal',case direction when 'inflow' then 'outflow' else 'inflow' end,amount,
    coalesce(p_occurred_at,now()),'Annulation — '||description,id,auth.uid()
    from public.envelope_movements where event_id = p_original_event_id;

  insert into public.daily_operation_reversals(
    household_id,original_event_id,reversal_event_id,reason_code,reason,created_by
  ) values (p_household_id,p_original_event_id,v_reversal_event_id,p_reason_code,trim(p_reason),auth.uid());
  return v_reversal_event_id;
end $$;
revoke all on function public.reverse_daily_financial_event(uuid,uuid,timestamptz,text,text,uuid)
  from public, anon;
grant execute on function public.reverse_daily_financial_event(uuid,uuid,timestamptz,text,text,uuid)
  to authenticated;

create table public.financial_event_attachments (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id),
  financial_event_id uuid not null references public.financial_events(id),
  storage_path text not null unique,
  original_filename text not null check (char_length(original_filename) between 1 and 255),
  mime_type text not null check (mime_type in ('image/jpeg','image/png','image/webp','application/pdf')),
  file_size bigint not null check (file_size > 0 and file_size <= 10485760),
  uploaded_at timestamptz not null default now(),
  uploaded_by uuid not null references auth.users(id),
  deleted_at timestamptz,
  deleted_by uuid references auth.users(id),
  constraint financial_event_attachments_path_check
    check (storage_path = household_id::text||'/'||financial_event_id::text||'/'||id::text)
);
create index financial_event_attachments_event_idx
  on public.financial_event_attachments(financial_event_id, uploaded_at desc);
alter table public.financial_event_attachments enable row level security;
revoke all on table public.financial_event_attachments from public, anon;
grant select on table public.financial_event_attachments to authenticated;
create policy financial_event_attachments_member_read on public.financial_event_attachments
  for select to authenticated using (public.is_household_member(household_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('financial-evidence','financial-evidence',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.register_financial_event_attachment(
  p_household_id uuid,p_financial_event_id uuid,p_original_filename text,
  p_mime_type text,p_file_size bigint,p_attachment_id uuid
) returns text language plpgsql security definer set search_path=public,auth as $$
declare v_path text;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if not exists(select 1 from public.financial_events where id=p_financial_event_id and household_id=p_household_id) then
    raise exception 'FinancialEvent does not belong to household'; end if;
  if p_mime_type not in ('image/jpeg','image/png','image/webp','application/pdf') then raise exception 'Unsupported attachment type'; end if;
  if p_file_size <= 0 or p_file_size > 10485760 then raise exception 'Attachment exceeds the 10 MB limit'; end if;
  v_path := p_household_id::text||'/'||p_financial_event_id::text||'/'||p_attachment_id::text;
  insert into public.financial_event_attachments(id,household_id,financial_event_id,storage_path,
    original_filename,mime_type,file_size,uploaded_by)
  values(p_attachment_id,p_household_id,p_financial_event_id,v_path,trim(p_original_filename),p_mime_type,p_file_size,auth.uid());
  return v_path;
end $$;

create or replace function public.soft_delete_financial_event_attachment(p_attachment_id uuid)
returns text language plpgsql security definer set search_path=public,auth as $$
declare v_path text;
begin
  update public.financial_event_attachments set deleted_at=now(),deleted_by=auth.uid()
  where id=p_attachment_id and deleted_at is null and public.is_household_member(household_id)
  returning storage_path into v_path;
  if v_path is null then raise exception 'Attachment not found or access denied'; end if;
  return v_path;
end $$;
revoke all on function public.register_financial_event_attachment(uuid,uuid,text,text,bigint,uuid),
  public.soft_delete_financial_event_attachment(uuid) from public,anon;
grant execute on function public.register_financial_event_attachment(uuid,uuid,text,text,bigint,uuid),
  public.soft_delete_financial_event_attachment(uuid) to authenticated;

drop policy if exists financial_evidence_select on storage.objects;
create policy financial_evidence_select on storage.objects for select to authenticated using (
  bucket_id='financial-evidence' and exists(select 1 from public.financial_event_attachments a
    where a.storage_path=name and a.deleted_at is null and public.is_household_member(a.household_id))
);
drop policy if exists financial_evidence_insert on storage.objects;
create policy financial_evidence_insert on storage.objects for insert to authenticated with check (
  bucket_id='financial-evidence' and exists(select 1 from public.financial_event_attachments a
    where a.storage_path=name and a.deleted_at is null and a.uploaded_by=auth.uid()
      and public.is_household_member(a.household_id))
);
drop policy if exists financial_evidence_delete on storage.objects;
create policy financial_evidence_delete on storage.objects for delete to authenticated using (
  bucket_id='financial-evidence' and exists(select 1 from public.financial_event_attachments a
    where a.storage_path=name and a.deleted_by=auth.uid() and a.deleted_at is not null
      and public.is_household_member(a.household_id))
);

create or replace view public.financial_event_history
with (security_invoker = true) as
select
  e.id as event_id,
  e.household_id,
  e.event_type,
  e.occurred_at,
  e.description,
  e.notes,
  e.created_by,
  e.created_at,
  coalesce(t.id,e.id) as transaction_id,
  coalesce(t.amount,(select max(em.amount) from public.envelope_movements em where em.event_id=e.id),0) as amount,
  t.source_account_id,
  sa.name as source_account_name,
  t.destination_account_id,
  da.name as destination_account_name,
  pc.actual_payment_method_id,
  pm.label as actual_payment_method_name,
  pc.recommendation_snapshot,
  (select jsonb_agg(distinct jsonb_build_object('id',em.envelope_id,'name',env.name))
     from public.envelope_movements em
     join public.envelopes env on env.id=em.envelope_id
    where em.event_id=e.id) as envelopes,
  dor.original_event_id,
  dor.reversal_event_id,
  dor.reason_code as reversal_reason_code,
  dor.reason as reversal_reason,
  exists(select 1 from public.daily_operation_reversals r where r.original_event_id=e.id) as is_reversed,
  exists(select 1 from public.daily_operation_reversals r where r.reversal_event_id=e.id) as is_reversal,
  (select jsonb_agg(jsonb_build_object(
      'id',a.id,'filename',a.original_filename,'mime_type',a.mime_type,
      'file_size',a.file_size,'uploaded_at',a.uploaded_at,
      'uploaded_by',a.uploaded_by,'storage_path',a.storage_path
    ) order by a.uploaded_at desc)
   from public.financial_event_attachments a
   where a.financial_event_id=e.id and a.deleted_at is null) as attachments
from public.financial_events e
left join public.financial_transactions t on t.event_id=e.id
left join public.accounts sa on sa.id=t.source_account_id
left join public.accounts da on da.id=t.destination_account_id
left join public.expense_payment_contexts pc on pc.event_id=e.id
left join public.payment_methods pm on pm.id=pc.actual_payment_method_id
left join public.daily_operation_reversals dor
  on dor.original_event_id=e.id or dor.reversal_event_id=e.id;

revoke all on public.financial_event_history from public,anon;
grant select on public.financial_event_history to authenticated;

create or replace function public.search_financial_event_history(
  p_household_id uuid,
  p_query text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_account_id uuid default null,
  p_envelope_id uuid default null,
  p_payment_method_id uuid default null,
  p_event_type text default null,
  p_reversal_state text default null,
  p_limit integer default 50,
  p_offset integer default 0
) returns setof public.financial_event_history
language sql security invoker set search_path=public stable as $$
  select h.* from public.financial_event_history h
  where h.household_id=p_household_id
    and public.is_household_member(h.household_id)
    and (nullif(trim(p_query),'') is null or h.description ilike '%'||trim(p_query)||'%'
      or h.event_id::text ilike '%'||trim(p_query)||'%')
    and (p_from is null or h.occurred_at>=p_from)
    and (p_to is null or h.occurred_at<p_to)
    and (p_account_id is null or h.source_account_id=p_account_id or h.destination_account_id=p_account_id)
    and (p_envelope_id is null or exists(select 1 from jsonb_array_elements(coalesce(h.envelopes,'[]')) x where x->>'id'=p_envelope_id::text))
    and (p_payment_method_id is null or h.actual_payment_method_id=p_payment_method_id)
    and (p_event_type is null or h.event_type=p_event_type)
    and (p_reversal_state is null or (p_reversal_state='reversed' and h.is_reversed)
      or (p_reversal_state='reversal' and h.is_reversal)
      or (p_reversal_state='active' and not h.is_reversed and not h.is_reversal))
  order by h.occurred_at desc,h.created_at desc
  limit greatest(1,least(coalesce(p_limit,50),100)) offset greatest(coalesce(p_offset,0),0)
$$;
revoke all on function public.search_financial_event_history(uuid,text,timestamptz,timestamptz,uuid,uuid,uuid,text,text,integer,integer)
  from public,anon;
grant execute on function public.search_financial_event_history(uuid,text,timestamptz,timestamptz,uuid,uuid,uuid,text,text,integer,integer)
  to authenticated;

create index if not exists financial_events_household_occurred_search_idx
  on public.financial_events(household_id,occurred_at desc,created_at desc);
create index if not exists financial_events_description_lower_idx
  on public.financial_events(household_id,lower(description));

commit;
