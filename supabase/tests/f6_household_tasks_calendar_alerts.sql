begin;
do $$
declare
  owner_a uuid:=gen_random_uuid(); member_a uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  household_a uuid; household_b uuid; v_task_id uuid; first_key uuid:=gen_random_uuid();
  before_events bigint; before_tx bigint; before_moves bigint;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
   ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','f6-owner@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',member_a,'authenticated','authenticated','f6-member@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f6-outsider@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('F6 rollback A','technical') returning id into household_a;
  insert into public.households(name,classification) values('F6 rollback B','technical') returning id into household_b;
  insert into public.household_members(household_id,user_id,role) values(household_a,owner_a,'owner'),(household_a,member_a,'member'),(household_b,outsider,'owner');
  select count(*) into before_events from public.financial_events where household_id=household_a;
  select count(*) into before_tx from public.financial_transactions where household_id=household_a;
  select count(*) into before_moves from public.envelope_movements where household_id=household_a;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  execute 'set local role authenticated';
  insert into public.household_tasks(household_id,title,assignee_user_id,due_date,priority,recurrence,idempotency_key,created_by)
    values(household_a,'F6 recurring',member_a,date '2026-01-31','high','monthly',gen_random_uuid(),owner_a) returning id into v_task_id;
  perform public.complete_household_task(v_task_id,'completed','done',first_key);
  perform public.complete_household_task(v_task_id,'completed','retry',first_key);
  if (select count(*) from public.household_task_occurrences where task_id=v_task_id)<>1 then raise exception 'Completion replay duplicated'; end if;
  if (select due_date from public.household_tasks where id=v_task_id)<>date '2026-02-28' then raise exception 'Month end recurrence invalid'; end if;
  insert into public.user_alert_states(household_id,user_id,alert_key,read_at) values(household_a,owner_a,'task:test',now());
  insert into public.notification_preferences(household_id,user_id,category,native_enabled) values(household_a,owner_a,'tasks',false);

  perform set_config('request.jwt.claim.sub',outsider::text,true);
  if (select count(*) from public.household_tasks where household_id=household_a)<>0 then raise exception 'Cross household read allowed'; end if;
  begin
    insert into public.household_tasks(household_id,title,idempotency_key,created_by) values(household_a,'Cross',gen_random_uuid(),outsider);
    raise exception 'Cross household write allowed';
  exception when others then if sqlerrm='Cross household write allowed' then raise; end if; end;
  execute 'reset role';

  if (select count(*) from public.financial_events where household_id=household_a)<>before_events then raise exception 'F6 created FinancialEvent'; end if;
  if (select count(*) from public.financial_transactions where household_id=household_a)<>before_tx then raise exception 'F6 created transaction'; end if;
  if (select count(*) from public.envelope_movements where household_id=household_a)<>before_moves then raise exception 'F6 created envelope movement'; end if;
end $$;
rollback;
