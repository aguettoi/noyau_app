-- F8 1/2/N membership matrix. All fixtures are transactional.
begin;

do $$
declare
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  h uuid; h2 uuid; source_event uuid; source_tx uuid; compensation uuid;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
   ('00000000-0000-0000-0000-000000000000',a,'authenticated','authenticated','f8-a@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',b,'authenticated','authenticated','f8-b@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',c,'authenticated','authenticated','f8-c@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f8-out@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('F8 cardinality rollback','technical') returning id into h;
  insert into public.households(name,classification) values('F8 other rollback','technical') returning id into h2;
  insert into public.household_members(household_id,user_id,role) values
    (h,a,'owner'),(h,b,'member'),(h,c,'member'),(h2,outsider,'owner');

  if (select count(*) from public.household_members where household_id=h and inactive_at is null)<>3 then
    raise exception 'Three active members were not retained';
  end if;

  insert into public.financial_events(household_id,event_type,description,occurred_at,idempotency_key,created_by)
  values(h,'cash_expense','F8 rollback expense',now(),gen_random_uuid(),a) returning id into source_event;
  insert into public.financial_transactions(household_id,event_id,type,occurred_at,reason,description,amount,created_by,validated_at)
  values(h,source_event,'expense',now(),'F8 rollback','F8 rollback',300,a,now()) returning id into source_tx;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',a::text,true);
  execute 'set local role authenticated';
  compensation:=public.create_member_compensation(
    h,source_event,b,c,100,'Subset B to C',null,null,null,null,null,gen_random_uuid()
  );
  if compensation is null then raise exception 'Compensation in three-member household failed'; end if;

  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin
    perform public.create_member_compensation(
      h,source_event,b,c,50,'Cross household',null,null,null,null,null,gen_random_uuid()
    );
    raise exception 'Cross-household compensation accepted';
  exception when others then
    if sqlerrm='Cross-household compensation accepted' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub',a::text,true);
  perform public.remove_household_member(h,b);
  if not exists(select 1 from public.household_members where household_id=h and user_id=b and inactive_at is not null) then
    raise exception 'Former member history row was deleted';
  end if;
  if not exists(select 1 from public.member_compensations where id=compensation and debtor_user_id=b) then
    raise exception 'Former member compensation history was lost';
  end if;
  begin
    insert into public.household_tasks(
      household_id,title,assignee_user_id,idempotency_key,created_by
    ) values(h,'Inactive assignee must fail',b,gen_random_uuid(),a);
    raise exception 'Inactive member accepted for new task';
  exception when others then
    if sqlerrm='Inactive member accepted for new task' then raise; end if;
    if sqlerrm not like 'Inactive or cross-household member reference:%' then raise; end if;
  end;

  perform public.remove_household_member(h,c);
  if (select count(*) from public.household_members where household_id=h and inactive_at is null)<>1 then
    raise exception 'Household did not safely transition from three to one member';
  end if;
  if not public.is_household_member(h) then raise exception 'Remaining member lost household access'; end if;

  perform set_config('request.jwt.claim.sub',b::text,true);
  if public.is_household_member(h) then raise exception 'Inactive member retained operational access'; end if;
end $$;

rollback;
