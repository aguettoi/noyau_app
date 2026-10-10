-- R2D: traceable reliability indicators, read-only over canonical sources.
begin;
create or replace function public.monthly_close_snapshot(p_household_id uuid, p_month_start date)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_end date:=p_month_start+interval '1 month'; v_open_reconciliations int; v_missing_cash int; v_missing_receipts int; v_compensations int;
 v_total int; v_j0 int; v_j1 int; v_j3 int; v_late int; v_accounts int; v_reconciled int; v_oldest int; v_overdue int;
begin
 if auth.uid() is null or not public.is_household_member(p_household_id) then raise exception 'Household access denied'; end if;
 if p_month_start<>date_trunc('month',p_month_start)::date then raise exception 'Invalid month'; end if;
 select count(*) into v_open_reconciliations from public.account_reconciliation_cases where household_id=p_household_id and status in ('open','partially_resolved','explained_pending');
 select count(*) into v_missing_cash from public.accounts a where a.household_id=p_household_id and a.kind='cash' and a.archived_at is null and not exists(select 1 from public.account_balance_observations o where o.account_id=a.id and o.observed_at>=p_month_start and o.observed_at<v_end);
 select count(*) into v_missing_receipts from public.financial_events e where e.household_id=p_household_id and e.event_type in ('cash_expense','debt_expense') and e.occurred_at>=p_month_start and e.occurred_at<v_end and not exists(select 1 from public.financial_event_attachments a where a.financial_event_id=e.id and a.deleted_at is null);
 select count(*) into v_compensations from public.member_compensation_balances c where c.household_id=p_household_id and c.remaining_amount>0;
 select count(*),count(*) filter(where created_at::date<=occurred_at::date),count(*) filter(where created_at::date<=occurred_at::date+1),count(*) filter(where created_at::date<=occurred_at::date+3),count(*) filter(where created_at::date>occurred_at::date+3)
 into v_total,v_j0,v_j1,v_j3,v_late from public.financial_events where household_id=p_household_id and occurred_at>=p_month_start and occurred_at<v_end;
 select count(*) into v_accounts from public.accounts where household_id=p_household_id and archived_at is null and not is_system;
 select count(distinct account_id) into v_reconciled from public.account_reconciliation_cases where household_id=p_household_id and observed_at>=p_month_start and observed_at<v_end and status='resolved';
 select coalesce(max(current_date-observed_at::date),0) into v_oldest from public.account_reconciliation_cases where household_id=p_household_id and status in ('open','partially_resolved','explained_pending');
 select count(*) into v_overdue from public.obligation_balances where household_id=p_household_id and is_overdue;
 return jsonb_build_object('open_reconciliations',v_open_reconciliations,'missing_cash_inventories',v_missing_cash,'missing_receipts',v_missing_receipts,'open_compensations',v_compensations,'hard_blockers',v_open_reconciliations+v_missing_cash,'warnings',v_missing_receipts+v_compensations+v_overdue,'total_entries',v_total,'j0',v_j0,'j1',v_j1,'j3',v_j3,'late_entries',v_late,'accounts_total',v_accounts,'accounts_reconciled',v_reconciled,'oldest_anomaly_days',v_oldest,'overdue_obligations',v_overdue,'attribution','household_unattributed');
end $$;
commit;
