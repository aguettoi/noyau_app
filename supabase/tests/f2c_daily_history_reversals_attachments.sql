begin;
do $$
declare
  actor uuid; h uuid; other_h uuid; a1 uuid; a2 uuid; e1 uuid; e2 uuid;
  expense uuid; income_full uuid; income_partial uuid; account_transfer uuid; envelope_transfer uuid;
  reversal uuid; replay uuid; before_count int; attachment uuid:=gen_random_uuid(); path text;
begin
  select user_id into actor from public.household_members order by created_at limit 1;
  if actor is null then raise exception 'No test actor'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  insert into public.households(name,classification) values('SQL TEST F2C rollback','technical') returning id into h;
  insert into public.households(name,classification) values('SQL TEST F2C other rollback','technical') returning id into other_h;
  insert into public.household_members(household_id,user_id,role) values(h,actor,'owner');
  insert into public.accounts(household_id,name,kind) values(h,'F2C A','bank') returning id into a1;
  insert into public.accounts(household_id,name,kind) values(h,'F2C B','bank') returning id into a2;
  insert into public.envelopes(household_id,name) values(h,'F2C E1') returning id into e1;
  insert into public.envelopes(household_id,name) values(h,'F2C E2') returning id into e2;

  execute 'set local role authenticated';

  expense:=public.create_cash_expense_event(h,'2026-10-02 12:00+00','Expense',100,a1,
    jsonb_build_array(jsonb_build_object('envelope_id',e1,'amount',100)),null,gen_random_uuid());
  income_full:=public.create_cash_income_event(h,'2026-10-03 12:00+00','Income full',100,a1,
    jsonb_build_array(jsonb_build_object('envelope_id',e1,'amount',100)),null,gen_random_uuid());
  income_partial:=public.create_cash_income_event(h,'2026-10-04 12:00+00','Income partial',100,a1,
    jsonb_build_array(jsonb_build_object('envelope_id',e1,'amount',40)),null,gen_random_uuid());
  account_transfer:=public.create_account_transfer_event(h,now(),'Transfer account',25,a1,a2,null,gen_random_uuid());
  envelope_transfer:=public.create_envelope_transfer_event(h,now(),'Transfer envelope',10,e1,e2,null,gen_random_uuid());

  reversal:=public.reverse_daily_financial_event(h,expense,'2026-10-05 12:00+00','wrong_amount','Erreur test',
    'f2c00000-0000-4000-8000-000000000001');
  replay:=public.reverse_daily_financial_event(h,expense,'2026-10-05 12:00+00','wrong_amount','Erreur test',
    'f2c00000-0000-4000-8000-000000000001');
  if reversal<>replay then raise exception 'Replay not idempotent'; end if;
  if (select count(*) from public.daily_operation_reversals where original_event_id=expense)<>1 then raise exception 'Double reversal'; end if;
  if (select coalesce(sum(l.amount),0) from public.financial_transaction_lines l join public.financial_transactions t on t.id=l.transaction_id where t.event_id in(expense,reversal))<>0 then raise exception 'Expense GL not restored'; end if;
  if (select coalesce(sum(case direction when 'inflow' then amount else -amount end),0) from public.envelope_movements where event_id in(expense,reversal))<>0 then raise exception 'Expense envelope not restored'; end if;
  if (select occurred_at from public.financial_events where id=expense)<>'2026-10-02 12:00+00' then raise exception 'Economic date changed'; end if;
  begin perform public.reverse_daily_financial_event(h,expense,now(),'other','Second',gen_random_uuid()); raise exception 'Double reversal accepted'; exception when others then if sqlerrm='Double reversal accepted' then raise; end if; end;
  begin perform public.reverse_daily_financial_event(other_h,income_full,now(),'other','Cross',gen_random_uuid()); raise exception 'Cross household accepted'; exception when others then if sqlerrm='Cross household accepted' then raise; end if; end;

  -- Every daily type can be reversed and income allocations, including the
  -- À répartir remainder, are inverted from their original movements.
  perform public.reverse_daily_financial_event(h,income_full,now(),'cancelled','Test',gen_random_uuid());
  perform public.reverse_daily_financial_event(h,income_partial,now(),'cancelled','Test',gen_random_uuid());
  perform public.reverse_daily_financial_event(h,account_transfer,now(),'cancelled','Test',gen_random_uuid());
  perform public.reverse_daily_financial_event(h,envelope_transfer,now(),'cancelled','Test',gen_random_uuid());

  path:=public.register_financial_event_attachment(h,expense,'preuve.pdf','application/pdf',100,attachment);
  if path<>h::text||'/'||expense::text||'/'||attachment::text then raise exception 'Unsafe attachment path'; end if;
  begin perform public.register_financial_event_attachment(h,expense,'bad.exe','application/octet-stream',10,gen_random_uuid()); raise exception 'Bad MIME accepted'; exception when others then if sqlerrm='Bad MIME accepted' then raise; end if; end;
  begin perform public.register_financial_event_attachment(h,expense,'huge.pdf','application/pdf',10485761,gen_random_uuid()); raise exception 'Huge file accepted'; exception when others then if sqlerrm='Huge file accepted' then raise; end if; end;
  begin perform public.register_financial_event_attachment(other_h,expense,'cross.pdf','application/pdf',10,gen_random_uuid()); raise exception 'Cross attachment accepted'; exception when others then if sqlerrm='Cross attachment accepted' then raise; end if; end;
  if (select count(*) from public.financial_event_attachments where financial_event_id=expense)<>1 then raise exception 'Attachment missing after reversal'; end if;
  perform public.soft_delete_financial_event_attachment(attachment);
  if (select deleted_at is null from public.financial_event_attachments where id=attachment) then raise exception 'Soft delete failed'; end if;

  if (select count(*) from public.search_financial_event_history(h,'Expense',null,null,a1,e1,null,'cash_expense','reversed',50,0))<>1 then raise exception 'History search/filter failed'; end if;
end $$;
rollback;
