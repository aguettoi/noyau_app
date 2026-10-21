-- A SECURITY DEFINER snapshot bypasses table RLS. Until a redacted
-- envelope-aware projection exists, refuse the entire derived snapshot to a
-- member who cannot read every account feeding it. This prevents residual
-- reconstruction from household/envelope totals.
create function private.has_unreadable_household_account(
  p_household_id uuid,p_user_id uuid
) returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.accounts a
    where a.household_id=p_household_id and a.archived_at is null
      and not a.is_system
      and not private.can_read_account_balance(a.id,p_user_id)
  );
$$;
revoke all on function private.has_unreadable_household_account(uuid,uuid)
  from public,anon;
grant execute on function private.has_unreadable_household_account(uuid,uuid)
  to authenticated;

create or replace function public.envelope_account_position_snapshot(p_household_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_accounts jsonb; v_envelopes jsonb; v_positions jsonb; v_account_gap numeric; v_envelope_gap numeric; v_fingerprint text;
begin
  if not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
  if private.has_unreadable_household_account(p_household_id,auth.uid()) then
    return jsonb_build_object('restricted',true,'reason','private_account');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('account_id',x.id,'name',x.name,'kind',x.kind,'canonical',x.canonical,'allocated',x.allocated,'gap',x.canonical-x.allocated) order by x.name),'[]'::jsonb),
         coalesce(sum(abs(x.canonical-x.allocated)),0)
  into v_accounts,v_account_gap from (
    select a.id,a.name,a.kind,coalesce(b.theoretical_balance,0)::numeric(14,2) canonical,
           coalesce(sum(p.amount),0)::numeric(14,2) allocated
    from public.accounts a left join public.account_ledger_balances b on b.account_id=a.id
    left join public.envelope_account_current_positions p on p.account_id=a.id and p.household_id=a.household_id
    where a.household_id=p_household_id and a.archived_at is null and not a.is_system
    group by a.id,a.name,a.kind,b.theoretical_balance
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('envelope_id',x.id,'name',x.name,'system',x.is_system,'canonical',x.canonical,'allocated',x.allocated,'gap',x.canonical-x.allocated) order by x.is_system,x.name),'[]'::jsonb),
         coalesce(sum(abs(x.canonical-x.allocated)),0)
  into v_envelopes,v_envelope_gap from (
    select e.id,e.name,e.is_system,coalesce(b.balance,0)::numeric(14,2) canonical,
           coalesce(sum(p.amount),0)::numeric(14,2) allocated
    from public.envelopes e left join public.envelope_ledger_balances b on b.envelope_id=e.id
    left join public.envelope_account_current_positions p on p.envelope_id=e.id and p.household_id=e.household_id
    where e.household_id=p_household_id and e.archived_at is null
    group by e.id,e.name,e.is_system,b.balance
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('account_id',account_id,'envelope_id',envelope_id,'amount',amount) order by account_id,envelope_id),'[]'::jsonb)
  into v_positions from public.envelope_account_current_positions where household_id=p_household_id;
  v_fingerprint:=md5(v_accounts::text||v_envelopes::text||v_positions::text);
  return jsonb_build_object('reliable',v_account_gap=0 and v_envelope_gap=0,'account_gap',v_account_gap,'envelope_gap',v_envelope_gap,'accounts',v_accounts,'envelopes',v_envelopes,'positions',v_positions,'fingerprint',v_fingerprint);
end $$;
