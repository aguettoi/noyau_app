-- Authenticated, transactional F3.1 matrix. Leaves no durable fixture.
begin;
do $$
declare
  owner_a uuid:=gen_random_uuid(); member_a uuid:=gen_random_uuid(); member_b uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  h_a uuid; h_b uuid; a1 uuid; a2 uuid; e1 uuid; expense uuid; transfer uuid; compensation uuid; action_id uuid;
  observation uuid; adjustment uuid; reversal uuid;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
   ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','f31-owner-a@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',member_a,'authenticated','authenticated','f31-member-a@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',member_b,'authenticated','authenticated','f31-member-b@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f31-outsider@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('F3.1 A rollback','technical') returning id into h_a;
  insert into public.households(name,classification) values('F3.1 B rollback','technical') returning id into h_b;
  insert into public.household_members(household_id,user_id,role) values(h_a,owner_a,'owner'),(h_a,member_a,'member'),(h_b,member_b,'owner');
  insert into public.accounts(household_id,name,kind) values(h_a,'A debtor','bank') returning id into a1;
  insert into public.accounts(household_id,name,kind) values(h_a,'A creditor','bank') returning id into a2;
  insert into public.envelopes(household_id,name) values(h_a,'F3 allocation') returning id into e1;
  perform set_config('request.jwt.claim.role','authenticated',true); perform set_config('request.jwt.claim.sub',owner_a::text,true); execute 'set local role authenticated';
  expense:=public.create_cash_expense_event(h_a,now(),'F3 source',300,a2,jsonb_build_array(jsonb_build_object('envelope_id',e1,'amount',300)),null,gen_random_uuid());
  compensation:=public.create_member_compensation(h_a,expense,member_a,owner_a,300,'Test',e1,a2,a1,null,null,'f3100000-0000-4000-8000-000000000001');
  if public.create_member_compensation(h_a,expense,member_a,owner_a,300,'Test',e1,a2,a1,null,null,'f3100000-0000-4000-8000-000000000001')<>compensation then raise exception 'Compensation replay failed'; end if;
  begin perform public.create_member_compensation(h_a,expense,owner_a,owner_a,10,'Bad',e1,a2,a1,null,null,gen_random_uuid()); raise exception 'Same member accepted'; exception when others then if sqlerrm='Same member accepted' then raise; end if; end;
  begin perform public.create_member_compensation(h_b,expense,member_b,owner_a,10,'Cross',null,null,null,null,null,gen_random_uuid()); raise exception 'Cross source accepted'; exception when others then if sqlerrm='Cross source accepted' then raise; end if; end;
  perform set_config('request.jwt.claim.sub',member_a::text,true);
  transfer:=public.create_account_transfer_event(h_a,now(),'F3 transfer',100,a1,a2,null,'f3100000-0000-4000-8000-000000000002');
  action_id:=public.record_member_compensation_action(compensation,'transfer_declared',100,transfer,'Canonical', '[]', 'f3100000-0000-4000-8000-000000000003');
  if public.record_member_compensation_action(compensation,'transfer_declared',100,transfer,'Canonical','[]','f3100000-0000-4000-8000-000000000003')<>action_id then raise exception 'Transfer replay failed'; end if;
  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  perform public.record_member_compensation_action(compensation,'receipt_confirmed',100,null,'Received','[]','f3100000-0000-4000-8000-000000000004');
  if (select remaining_amount from public.member_compensation_balances where id=compensation)<>200 then raise exception 'Partial balance failed'; end if;
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin perform public.record_member_compensation_action(compensation,'abandoned',200,null,'Cross','[]',gen_random_uuid()); raise exception 'Outsider accepted'; exception when others then if sqlerrm='Outsider accepted' then raise; end if; end;
  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  select public.record_account_balance_observation(a1,now(),200,'F3 observation') into observation;
  adjustment:=public.regularize_account_reconciliation(observation,100,'unexplained','F3 adjustment',jsonb_build_array(jsonb_build_object('envelope_id',e1,'amount',100)),now(),'f3100000-0000-4000-8000-000000000005');
  reversal:=public.reverse_reconciliation_regularization(adjustment,now(),'F3 reverse','f3100000-0000-4000-8000-000000000006');
  if public.reverse_reconciliation_regularization(adjustment,now(),'F3 reverse','f3100000-0000-4000-8000-000000000006')<>reversal then raise exception 'Reversal replay failed'; end if;
  if (select coalesce(sum(l.debit-l.credit),0) from public.financial_transactions t join public.financial_transaction_lines l on l.transaction_id=t.id where t.event_id in(adjustment,reversal) and l.account_id=a1)<>0 then raise exception 'GL reversal mismatch'; end if;
  if (select coalesce(sum(case direction when 'inflow' then amount else -amount end),0) from public.envelope_movements where event_id in(adjustment,reversal))<>0 then raise exception 'Envelope reversal mismatch'; end if;
end $$;
rollback;
