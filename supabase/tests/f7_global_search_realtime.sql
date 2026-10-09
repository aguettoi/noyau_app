begin;
do $$
declare owner_a uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  household_a uuid; household_b uuid; result_count integer;
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
   ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','f7-owner@example.test','',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f7-outsider@example.test','',now(),'{}','{}',now(),now());
  insert into public.households(name,classification) values('F7 rollback A','technical') returning id into household_a;
  insert into public.households(name,classification) values('F7 rollback B','technical') returning id into household_b;
  insert into public.household_members(household_id,user_id,role) values(household_a,owner_a,'owner'),(household_b,outsider,'owner');
  insert into public.household_tasks(household_id,title,idempotency_key,created_by)
    values(household_a,'Recherche F7 unique',gen_random_uuid(),owner_a);

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  execute 'set local role authenticated';
  select count(*) into result_count from public.search_household_global(household_a,'F7 unique',20,0);
  if result_count<>1 then raise exception 'Own household search failed'; end if;
  if (select count(*) from public.search_household_global(household_a,'',20,0))<>0 then raise exception 'Empty query returned rows'; end if;

  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin
    perform public.search_household_global(household_a,'F7 unique',20,0);
    raise exception 'Cross household search allowed';
  exception when others then if sqlerrm='Cross household search allowed' then raise; end if; end;
  execute 'reset role';

  if (select count(*) from public.financial_events where household_id=household_a)<>0 then raise exception 'Search created financial event'; end if;
end $$;
rollback;
