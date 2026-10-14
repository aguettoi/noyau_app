-- R2.9: source-backed preview for the initial account x envelope matrix.
-- Evidence is analytical metadata only: no GL, FinancialEvent or envelope
-- movement is created by this migration.

alter table public.envelope_account_position_entries
  add column if not exists provenance text not null default 'human_input'
    check (provenance in ('source_proof','balancing_deduction','human_confirmation','human_input')),
  add column if not exists provenance_reference text;

create table public.envelope_account_initial_evidence (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  account_id uuid not null references public.accounts(id) on delete restrict,
  envelope_id uuid not null references public.envelopes(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  evidence_kind text not null check (evidence_kind in ('source_proof','human_confirmation')),
  source_fingerprint text not null,
  source_reference text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (household_id,account_id,envelope_id,source_fingerprint)
);

create index envelope_account_initial_evidence_household_idx
  on public.envelope_account_initial_evidence(household_id,envelope_id,account_id);

alter table public.envelope_account_initial_evidence enable row level security;
revoke all on public.envelope_account_initial_evidence from public,anon;
grant select on public.envelope_account_initial_evidence to authenticated;
create policy envelope_account_initial_evidence_read
  on public.envelope_account_initial_evidence for select to authenticated
  using (public.is_household_member(household_id));

-- Certified pilot evidence. Names are resolved inside the household and the
-- insert only runs when the exact certified C3 fingerprint is present.
with certified as (
  select r.household_id,r.actor_id,r.source_fingerprint
  from public.cutover_opening_runs r
  where r.source_fingerprint='f3cbc99e335586d5628791017e5fd8119430a03d32674ba1d11f284157c8f8bc'
    and r.status='completed'
), evidence(account_name,envelope_name,amount,evidence_kind,source_reference) as (
  values
    ('Espèces maison','Nourriture',2416.00,'source_proof','Enveloppes!D29 + regroupement espèces D8'),
    ('Espèces maison','Navette',2753.50,'source_proof','Enveloppes!D35 + regroupement espèces D8'),
    ('Banque Nora','Traite voiture',5000.00,'source_proof','Regroupement compte Nora D6'),
    ('Banque Nora','Wifi',625.80,'source_proof','Regroupement compte Nora D6'),
    ('Banque Nora','Besoin perso',520.48,'source_proof','Regroupement compte Nora D6'),
    ('Banque Nora','Habits',761.17,'source_proof','Enveloppes!S30 et regroupement compte Nora D6'),
    ('Banque Nora','Reste epargne (primes Ibrahim et Nora)',16446.47,'source_proof','Enveloppes!D37 et regroupement compte Nora D6'),
    ('Islamique / Arreda Ibrahim','Epargne',18548.56,'human_confirmation','Confirmation métier R2.9 du 2026-10-13')
)
insert into public.envelope_account_initial_evidence(
  household_id,account_id,envelope_id,amount,evidence_kind,
  source_fingerprint,source_reference,created_by
)
select c.household_id,a.id,e.id,v.amount,v.evidence_kind,
       c.source_fingerprint,v.source_reference,c.actor_id
from certified c,evidence v,public.accounts a,public.envelopes e
where a.household_id=c.household_id and a.name=v.account_name and a.archived_at is null
  and e.household_id=c.household_id and e.name=v.envelope_name and e.archived_at is null
on conflict do nothing;

create or replace function public.envelope_account_initial_position_preview(p_household_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_positions jsonb; v_fingerprint text;
begin
  if not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'account_id',account_id,'envelope_id',envelope_id,'amount',amount,
           'evidence_kind',evidence_kind,'source_reference',source_reference
         ) order by envelope_id,account_id),'[]'::jsonb),max(source_fingerprint)
    into v_positions,v_fingerprint
  from public.envelope_account_initial_evidence
  where household_id=p_household_id;
  return jsonb_build_object(
    'positions',v_positions,
    'source_fingerprint',coalesce(v_fingerprint,''),
    'financial_writes',0
  );
end $$;

create or replace function public.set_envelope_account_position_snapshot(
  p_household_id uuid,p_positions jsonb,p_note text,p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_role text; v_batch uuid; v_item jsonb; v_account uuid; v_envelope uuid; v_amount numeric; v_current numeric; v_delta numeric; v_check jsonb; v_provenance text; v_reference text;
begin
  select role into v_role from public.household_members where household_id=p_household_id and user_id=auth.uid();
  if v_role <> 'owner' then raise exception 'Only an OWNER can initialise the position matrix'; end if;
  if p_positions is null or jsonb_typeof(p_positions)<>'array' then raise exception 'Positions must be an array'; end if;
  perform pg_advisory_xact_lock(hashtextextended('r2-initial-position:'||p_household_id::text,0));
  select id into v_batch from public.envelope_account_position_batches where household_id=p_household_id and idempotency_key=p_idempotency_key;
  if v_batch is not null then return v_batch; end if;
  if exists(select 1 from public.envelope_account_position_batches where household_id=p_household_id and batch_kind='explicit_snapshot') then
    raise exception 'The initial position matrix already exists';
  end if;
  create temporary table if not exists pg_temp.r2_positions(account_id uuid,envelope_id uuid,amount numeric(14,2),provenance text,provenance_reference text,primary key(account_id,envelope_id)) on commit drop;
  truncate pg_temp.r2_positions;
  for v_item in select value from jsonb_array_elements(p_positions) loop
    v_account:=(v_item->>'account_id')::uuid; v_envelope:=(v_item->>'envelope_id')::uuid; v_amount:=(v_item->>'amount')::numeric;
    v_provenance:=coalesce(nullif(v_item->>'provenance',''),'humanInput');
    v_provenance:=case v_provenance when 'sourceProof' then 'source_proof' when 'balancingDeduction' then 'balancing_deduction' when 'humanConfirmation' then 'human_confirmation' when 'humanInput' then 'human_input' else v_provenance end;
    v_reference:=nullif(trim(v_item->>'provenance_reference'),'');
    if v_amount < 0 then raise exception 'A current position cannot be negative'; end if;
    if v_provenance not in ('source_proof','balancing_deduction','human_confirmation','human_input') then raise exception 'Invalid provenance'; end if;
    if v_provenance<>'human_input' and v_reference is null then raise exception 'Provenance reference is required'; end if;
    if not exists(select 1 from public.accounts where id=v_account and household_id=p_household_id and archived_at is null and not is_system) then raise exception 'Invalid account'; end if;
    if not exists(select 1 from public.envelopes where id=v_envelope and household_id=p_household_id and archived_at is null) then raise exception 'Invalid envelope'; end if;
    if v_provenance in ('source_proof','human_confirmation') and not exists(
      select 1 from public.envelope_account_initial_evidence x
      where x.household_id=p_household_id and x.account_id=v_account and x.envelope_id=v_envelope
        and x.amount=v_amount and x.evidence_kind=v_provenance and x.source_reference=v_reference
    ) then raise exception 'Unverified source evidence'; end if;
    insert into pg_temp.r2_positions values(v_account,v_envelope,v_amount,v_provenance,v_reference);
  end loop;
  if exists(select 1 from public.accounts a left join public.account_ledger_balances b on b.account_id=a.id left join (select account_id,sum(amount) amount from pg_temp.r2_positions group by account_id) p on p.account_id=a.id where a.household_id=p_household_id and a.archived_at is null and not a.is_system and coalesce(p.amount,0)<>coalesce(b.theoretical_balance,0)) then raise exception 'Snapshot does not reconcile account balances'; end if;
  if exists(select 1 from public.envelopes e left join public.envelope_ledger_balances b on b.envelope_id=e.id left join (select envelope_id,sum(amount) amount from pg_temp.r2_positions group by envelope_id) p on p.envelope_id=e.id where e.household_id=p_household_id and e.archived_at is null and coalesce(p.amount,0)<>coalesce(b.balance,0)) then raise exception 'Snapshot does not reconcile envelope balances'; end if;
  insert into public.envelope_account_position_batches(household_id,batch_kind,idempotency_key,note,created_by) values(p_household_id,'explicit_snapshot',p_idempotency_key,nullif(trim(p_note),''),auth.uid()) returning id into v_batch;
  for v_account,v_envelope,v_amount,v_provenance,v_reference in select account_id,envelope_id,amount,provenance,provenance_reference from pg_temp.r2_positions loop
    v_current:=0;
    select coalesce(amount,0) into v_current from public.envelope_account_current_positions where household_id=p_household_id and account_id=v_account and envelope_id=v_envelope;
    v_delta:=v_amount-coalesce(v_current,0);
    if v_delta<>0 then
      insert into public.envelope_account_position_entries(household_id,batch_id,account_id,envelope_id,amount,provenance,provenance_reference,created_by)
      values(p_household_id,v_batch,v_account,v_envelope,v_delta,v_provenance,v_reference,auth.uid());
    end if;
  end loop;
  v_check:=public.envelope_account_position_snapshot(p_household_id);
  if not (v_check->>'reliable')::boolean then raise exception 'Snapshot invariant failed'; end if;
  return v_batch;
end $$;

revoke all on function public.envelope_account_initial_position_preview(uuid) from public,anon;
grant execute on function public.envelope_account_initial_position_preview(uuid) to authenticated;
