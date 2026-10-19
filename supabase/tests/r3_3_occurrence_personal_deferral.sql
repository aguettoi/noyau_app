-- Isolated Auth fixtures; all changes, including scheduler cycles, are rolled back.
begin;
do $$
declare
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  h uuid; other_h uuid; intention uuid:=gen_random_uuid(); occurrence uuid:=gen_random_uuid();
  fixture_event uuid:=gen_random_uuid(); replay_key uuid:=gen_random_uuid();
  day_key text:='r3.1:'||occurrence||':day'; source_key text:='reminder-source:r3_1_occurrence:'||occurrence;
  after_key text:='r3.1:'||occurrence||':after'; before_counts jsonb; after_counts jsonb;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  select '00000000-0000-0000-0000-000000000000',u,'authenticated','authenticated',u||'@r33-rollback.test','',now(),'{}','{}',now(),now()
  from unnest(array[a,b,c,outsider]) u;
  insert into public.households(name,classification) values('R33 deferral rollback','technical') returning id into h;
  insert into public.households(name,classification) values('R33 other rollback','technical') returning id into other_h;
  insert into public.household_members(household_id,user_id,role) values(h,a,'owner'),(other_h,outsider,'owner');
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  insert into public.recurring_financial_intentions(id,household_id,economic_type,label,expected_amount,frequency,starts_on,next_occurrence_on,anchor_day,idempotency_key,created_by)
  values(intention,h,'expense','R33 rollback occurrence',1,'monthly',current_date-3,current_date-3,1,gen_random_uuid(),a);
  insert into public.expected_financial_occurrences(id,household_id,intention_id,expected_on,economic_type,label,expected_amount,currency_code,certainty)
  values(occurrence,h,intention,current_date-3,'expense','R33 rollback occurrence',1,'MAD','certain');
  -- Financial fixture used only to exercise the realized view; no reminder creates it.
  insert into public.financial_events(id,household_id,event_type,description,occurred_at,created_by)
  values(fixture_event,h,'cash_expense','R33 realized fixture',now(),a);
  select jsonb_build_array((select count(*) from financial_events),(select count(*) from financial_transactions),
    (select count(*) from financial_transaction_lines),(select count(*) from envelope_movements),
    (select count(*) from obligations)) into before_counts;
  insert into public.financial_reminders(household_id,source_kind,source_id,dedupe_key,due_at,timezone,priority,title,detail,action_type)
  values(h,'r3_1_occurrence',occurrence,day_key,now()-interval '2 days','Africa/Casablanca','normal','day','fixture','open_occurrence');

  execute 'set local role authenticated';
  if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'Obsolete DAY visible while scheduler is delayed'; end if;
  begin
    perform public.act_on_financial_reminder(h,day_key,'snoozed',now()-interval '1 second',gen_random_uuid());
    raise exception 'Past snooze accepted';
  exception when others then if sqlerrm<>'A future snooze date is required' then raise; end if; end;
  perform public.act_on_financial_reminder(h,day_key,'snoozed',now()+interval '3 hours',replay_key);
  perform public.act_on_financial_reminder(h,day_key,'snoozed',now()+interval '3 hours',replay_key);
  if (select count(*) from public.reminder_action_audit where idempotency_key=replay_key)<>1 then raise exception 'Audit retry duplicated'; end if;
  if not exists(select 1 from public.user_alert_states where alert_key=source_key and snoozed_until>now()) then raise exception 'Source not persisted'; end if;
  execute 'reset role';
  perform private.materialize_financial_reminders(now());
  perform private.materialize_financial_reminders(now());
  perform private.materialize_financial_reminders(now());
  if (select count(*) from public.financial_reminders where household_id=h)<>3 then raise exception 'Scheduler duplicate phases'; end if;
  if (select count(*) from public.financial_reminders where household_id=h and status='active')<>1 then raise exception 'Old phase resurrected'; end if;
  -- An older phase arriving after AFTER is immediately obsolete.
  delete from public.financial_reminders where household_id=h and dedupe_key='r3.1:'||occurrence||':before';
  insert into public.financial_reminders(household_id,source_kind,source_id,dedupe_key,due_at,timezone,priority,title,detail,action_type)
  values(h,'r3_1_occurrence',occurrence,'r3.1:'||occurrence||':before',now()-interval '10 days','Africa/Casablanca','normal','old','fixture','open_occurrence');
  if (select count(*) from public.financial_reminders where household_id=h and status='active')<>1 then raise exception 'Arrival order resurrected old phase'; end if;
  execute 'set local role authenticated';
  if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'After bypasses snooze on refresh/reopen'; end if;
  -- Reading a phase does not clear the occurrence deferral.
  perform public.act_on_financial_reminder(h,after_key,'read',null,gen_random_uuid());
  if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'Read cleared snooze'; end if;
  execute 'reset role';
  insert into public.household_members(household_id,user_id,role) values(h,b,'member');
  perform set_config('request.jwt.claim.sub',b::text,true);
  execute 'set local role authenticated';
  if (select count(*) from public.visible_financial_reminders(h))<>1 then raise exception 'User A snoozed user B'; end if;
  if exists(select 1 from public.user_alert_states where user_id=a) then raise exception 'Personal state RLS'; end if;
  begin
    insert into public.user_alert_states(household_id,user_id,alert_key,snoozed_until,last_action)
    values(h,a,source_key,now()+interval '1 day','snoozed');
    raise exception 'Other user state write accepted';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  insert into public.household_members(household_id,user_id,role) values(h,c,'member');
  perform set_config('request.jwt.claim.sub',c::text,true);
  execute 'set local role authenticated';
  if (select count(*) from public.visible_financial_reminders(h))<>1 then raise exception 'N member visibility'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'Cross-household read'; end if;
  begin
    perform public.act_on_financial_reminder(h,after_key,'not_yet',now()+interval '1 hour',gen_random_uuid());
    raise exception 'Cross-household write accepted';
  exception when others then if sqlerrm='Cross-household write accepted' then raise; end if; end;
  execute 'reset role';

  -- Simulate expiration solely on rolled-back fixture state, without changing time.
  update public.user_alert_states set snoozed_until=now()-interval '1 second' where household_id=h and user_id=a and alert_key=source_key;
  perform set_config('request.jwt.claim.sub',a::text,true);
  execute 'set local role authenticated';
  if (select count(*) from public.visible_financial_reminders(h) where dedupe_key=after_key)<>1 then raise exception 'Current phase not restored'; end if;
  if exists(select 1 from public.visible_financial_reminders(h) where dedupe_key=day_key) then raise exception 'DAY resurrected'; end if;
  perform public.act_on_financial_reminder(h,day_key,'not_yet',now()+interval '2 hours',gen_random_uuid());
  if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'Not yet bypassed'; end if;
  execute 'reset role';
  -- Re-materialize AFTER following a DAY 'not yet' action.
  delete from public.financial_reminders where household_id=h and dedupe_key=after_key;
  update public.financial_reminders set status='active' where household_id=h and dedupe_key=day_key;
  perform private.materialize_financial_reminders(now());
  execute 'set local role authenticated';
  if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'Scheduler bypassed not yet'; end if;
  execute 'reset role';
  update public.user_alert_states set snoozed_until=now()-interval '1 second' where household_id=h and user_id=a and alert_key=source_key;
  -- Phase-only dismissal does not transfer between phases/users.
  execute 'set local role authenticated';
  perform public.act_on_financial_reminder(h,day_key,'dismissed',null,gen_random_uuid());
  if (select count(*) from public.visible_financial_reminders(h))<>1 then raise exception 'Dismiss propagated'; end if;
  execute 'reset role';

  -- No new reminder for ignored/realized sources, including immediately on read.
  execute 'set local role authenticated';
  perform public.act_on_financial_reminder(h,after_key,'snoozed',now()+interval '3 hours',gen_random_uuid());
  execute 'reset role';
  update public.expected_financial_occurrences set ignored_at=now(),ignored_by=a,ignore_reason='rollback' where id=occurrence;
  execute 'set local role authenticated';
  if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'Ignored reminder visible'; end if;
  execute 'reset role';
  perform private.materialize_financial_reminders(now());
  if exists(select 1 from public.financial_reminders where household_id=h and status='active') then raise exception 'Ignored not resolved'; end if;
  update public.expected_financial_occurrences set ignored_at=null,ignored_by=null,ignore_reason=null where id=occurrence;
  update public.financial_reminders set status='active' where household_id=h and dedupe_key=after_key;
  insert into public.expected_financial_occurrence_matches(household_id,occurrence_id,financial_event_id,matched_amount,decision,decided_by,decided_at,idempotency_key,created_by)
  values(h,occurrence,fixture_event,1,'confirmed',a,now(),gen_random_uuid(),a);
  execute 'set local role authenticated';
  if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'Realized reminder visible'; end if;
  execute 'reset role';
  perform private.materialize_financial_reminders(now());
  if exists(select 1 from public.financial_reminders where household_id=h and status='active') then raise exception 'Realized not resolved'; end if;
  update public.user_alert_states set snoozed_until=now()-interval '1 second' where household_id=h and user_id=a and alert_key=source_key;
  execute 'set local role authenticated';
  if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'Realized returned after expiration'; end if;
  execute 'reset role';
  delete from public.expected_financial_occurrence_matches where occurrence_id=occurrence;
  -- Zero-day rule offsets can make phases simultaneous; AFTER still wins.
  delete from public.financial_reminders where household_id=h;
  insert into public.financial_reminders(household_id,source_kind,source_id,dedupe_key,due_at,timezone,priority,title,detail,action_type)
  select h,'r3_1_occurrence',occurrence,'r3.1:'||occurrence||':'||phase,now()-interval '1 hour',
    'Africa/Casablanca','normal',phase,'fixture','open_occurrence'
  from unnest(array['after','day','before']) phase;
  if (select count(*) from public.financial_reminders where household_id=h and status='active')<>1
    or not exists(select 1 from public.financial_reminders where household_id=h and dedupe_key=after_key and status='active')
    then raise exception 'Equal-time phases not ordered'; end if;
  update public.financial_reminders set status='active' where household_id=h and dedupe_key=after_key;
  for replay_key in select gen_random_uuid() from generate_series(1,2) loop
    update public.recurring_financial_intentions set status=case when status='active' then 'suspended' else 'stopped' end where id=intention;
    execute 'set local role authenticated';
    if exists(select 1 from public.visible_financial_reminders(h)) then raise exception 'Suspended/stopped visible'; end if;
    execute 'reset role';
    perform private.materialize_financial_reminders(now());
  end loop;
  select jsonb_build_array((select count(*) from financial_events),(select count(*) from financial_transactions),
    (select count(*) from financial_transaction_lines),(select count(*) from envelope_movements),
    (select count(*) from obligations)) into after_counts;
  if before_counts<>after_counts then raise exception 'Financial writes: % / %',before_counts,after_counts; end if;
end $$;
rollback;
