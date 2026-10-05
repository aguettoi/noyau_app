-- F2A: payment method catalog and envelope recommendations.
-- Configuration only: no financial events, postings or movements.
create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  account_id uuid,
  holder_user_id uuid,
  method_type text not null check (method_type in ('bank_card','cash','bank_transfer','other')),
  label text not null check (char_length(trim(label)) between 1 and 80),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id),
  archived_at timestamptz,
  constraint payment_methods_id_household_unique unique (id, household_id),
  constraint payment_methods_account_household_fk foreign key (account_id, household_id)
    references public.accounts(id, household_id),
  constraint payment_methods_holder_household_fk foreign key (household_id, holder_user_id)
    references public.household_members(household_id, user_id)
);

alter table public.envelopes
  add column if not exists recommended_account_id uuid,
  add column if not exists recommended_payment_method_id uuid;

alter table public.envelopes
  drop constraint if exists envelopes_recommended_account_household_fk,
  drop constraint if exists envelopes_recommended_payment_method_household_fk;
alter table public.envelopes
  add constraint envelopes_recommended_account_household_fk
    foreign key (recommended_account_id, household_id)
    references public.accounts(id, household_id),
  add constraint envelopes_recommended_payment_method_household_fk
    foreign key (recommended_payment_method_id, household_id)
    references public.payment_methods(id, household_id);

alter table public.payment_methods enable row level security;
create policy payment_methods_select_member on public.payment_methods for select using
  (exists (select 1 from public.household_members hm where hm.household_id = payment_methods.household_id and hm.user_id = auth.uid()));
create policy payment_methods_insert_member on public.payment_methods for insert with check
  (created_by = auth.uid() and exists (select 1 from public.household_members hm where hm.household_id = payment_methods.household_id and hm.user_id = auth.uid()));
create policy payment_methods_update_member on public.payment_methods for update using
  (exists (select 1 from public.household_members hm where hm.household_id = payment_methods.household_id and hm.user_id = auth.uid()));

create or replace function public.create_payment_method(
  p_household_id uuid, p_account_id uuid, p_holder_user_id uuid,
  p_method_type text, p_label text
) returns public.payment_methods
language plpgsql security definer set search_path = public, auth as $$
declare v public.payment_methods;
begin
  if not exists (select 1 from public.household_members where household_id=p_household_id and user_id=auth.uid()) then raise exception 'Household access denied'; end if;
  if p_account_id is not null and not exists (select 1 from public.accounts where id=p_account_id and household_id=p_household_id) then raise exception 'Account household mismatch'; end if;
  if p_holder_user_id is not null and not exists (select 1 from public.household_members where household_id=p_household_id and user_id=p_holder_user_id) then raise exception 'Holder household mismatch'; end if;
  insert into public.payment_methods(household_id,account_id,holder_user_id,method_type,label,created_by)
  values(p_household_id,p_account_id,p_holder_user_id,p_method_type,trim(p_label),auth.uid()) returning * into v;
  return v;
end; $$;

create or replace function public.update_payment_method(
  p_id uuid, p_account_id uuid, p_holder_user_id uuid,
  p_method_type text, p_label text, p_active boolean
) returns public.payment_methods
language plpgsql security definer set search_path = public, auth as $$
declare v public.payment_methods;
begin
  if not exists (select 1 from public.payment_methods pm join public.household_members hm on hm.household_id=pm.household_id where pm.id=p_id and hm.user_id=auth.uid()) then raise exception 'Payment method access denied'; end if;
  if p_account_id is not null and not exists (select 1 from public.accounts a join public.payment_methods pm on pm.household_id=a.household_id where a.id=p_account_id and pm.id=p_id) then raise exception 'Account household mismatch'; end if;
  update public.payment_methods set account_id=p_account_id, holder_user_id=p_holder_user_id, method_type=p_method_type, label=trim(p_label), active=p_active, archived_at=case when p_active then null else coalesce(archived_at,now()) end where id=p_id returning * into v;
  return v;
end; $$;

create or replace function public.set_envelope_recommendation(
  p_envelope_id uuid, p_account_id uuid, p_payment_method_id uuid
) returns public.envelopes
language plpgsql security definer set search_path = public, auth as $$
declare v public.envelopes; v_household uuid;
begin
  select household_id into v_household from public.envelopes where id=p_envelope_id;
  if v_household is null or not exists (select 1 from public.household_members where household_id=v_household and user_id=auth.uid()) then raise exception 'Envelope access denied'; end if;
  if p_account_id is not null and not exists (select 1 from public.accounts where id=p_account_id and household_id=v_household) then raise exception 'Account household mismatch'; end if;
  if p_payment_method_id is not null and not exists (select 1 from public.payment_methods where id=p_payment_method_id and household_id=v_household and active) then raise exception 'Payment method household mismatch or inactive'; end if;
  if p_payment_method_id is not null and p_account_id is not null and exists (select 1 from public.payment_methods where id=p_payment_method_id and account_id is not null and account_id <> p_account_id) then raise exception 'Recommendation account mismatch'; end if;
  update public.envelopes set recommended_account_id=p_account_id, recommended_payment_method_id=p_payment_method_id where id=p_envelope_id returning * into v;
  return v;
end; $$;

revoke all on function public.create_payment_method(uuid,uuid,uuid,text,text) from public, anon;
revoke all on function public.update_payment_method(uuid,uuid,uuid,text,text,boolean) from public, anon;
revoke all on function public.set_envelope_recommendation(uuid,uuid,uuid) from public, anon;
grant execute on function public.create_payment_method(uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.update_payment_method(uuid,uuid,uuid,text,text,boolean) to authenticated;
grant execute on function public.set_envelope_recommendation(uuid,uuid,uuid) to authenticated;
