begin;
do $$
declare
 owner_a uuid:=gen_random_uuid(); member_a uuid:=gen_random_uuid(); member_a2 uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 household_a uuid; household_b uuid; period_id uuid; first_events bigint; first_periods bigint; denied boolean:=false;
begin
 insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
 ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','r2-owner@example.test','',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000',member_a,'authenticated','authenticated','r2-member@example.test','',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000',member_a2,'authenticated','authenticated','r2-member2@example.test','',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','r2-outsider@example.test','',now(),'{}','{}',now(),now());
 insert into public.households(name,classification) values('R2 rollback A','technical') returning id into household_a;
 insert into public.households(name,classification) values('R2 rollback B','technical') returning id into household_b;
 insert into public.household_members(household_id,user_id,role) values(household_a,owner_a,'owner'),(household_a,member_a,'member'),(household_a,member_a2,'member'),(household_b,outsider,'owner');
 perform set_config('request.jwt.claim.role','authenticated',true); perform set_config('request.jwt.claim.sub',owner_a::text,true); execute 'set local role authenticated';
 if (public.monthly_close_snapshot(household_a,date '2026-10-01')->>'hard_blockers')::int<>0 then raise exception 'Empty technical household should be closable'; end if;
 period_id:=public.close_monthly_period(household_a,date '2026-10-01',false,null,gen_random_uuid());
 select count(*) into first_periods from public.monthly_close_periods where household_id=household_a;
 select count(*) into first_events from public.monthly_close_events where household_id=household_a;
 perform public.close_monthly_period(household_a,date '2026-10-01',false,null,gen_random_uuid());
 if (select count(*) from public.monthly_close_periods where household_id=household_a)<>first_periods or (select count(*) from public.monthly_close_events where household_id=household_a)<>first_events then raise exception 'Double close duplicated state or audit'; end if;
 begin perform public.reopen_monthly_period(period_id,'',gen_random_uuid()); raise exception 'Empty reopen reason accepted'; exception when others then if sqlerrm='Empty reopen reason accepted' then raise; end if; end;
 perform public.reopen_monthly_period(period_id,'Correction démontrée',gen_random_uuid());
 perform set_config('request.jwt.claim.sub',member_a::text,true);
 begin perform public.reopen_monthly_period(period_id,'Member attempt',gen_random_uuid()); raise exception 'Member reopened month'; exception when others then if sqlerrm='Member reopened month' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 begin perform public.monthly_close_snapshot(household_a,date '2026-10-01'); exception when others then denied:=true; end;
 if not denied then raise exception 'Cross-household snapshot allowed'; end if;
 if (select count(*) from public.monthly_close_periods where household_id=household_a)<>0 then raise exception 'RLS exposed foreign periods'; end if;
 execute 'reset role';
 if (select count(*) from public.household_members where household_id=household_a)<>3 then raise exception 'N-member fixture invalid'; end if;
 if exists(select 1 from public.financial_events where household_id=household_a) or exists(select 1 from public.financial_transactions where household_id=household_a) or exists(select 1 from public.envelope_movements where household_id=household_a) then raise exception 'R2 created financial writes'; end if;
end $$;
rollback;
