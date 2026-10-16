begin;

-- Future structural recommendations only. This migration never writes the
-- current account x envelope matrix, GL, FinancialEvents, or envelope ledger.
do $$
declare
  v_household uuid;
  v_actor uuid;
  v_item record;
  v_target_account uuid;
  v_previous_account uuid;
  v_previous_method uuid;
  v_previous_kind text;
  v_previous_definition jsonb;
  v_updated public.envelopes%rowtype;
begin
  select id into v_household
  from public.households
  where name = 'FINANCIEL PILOTE — FOYER RÉEL'
    and classification = 'operational';
  if v_household is null then
    raise exception 'R2.12.1 pilot household not found';
  end if;

  select user_id into v_actor
  from public.household_members
  where household_id = v_household and role = 'owner'
  order by created_at
  limit 1;
  if v_actor is null then
    raise exception 'R2.12.1 pilot owner not found';
  end if;

  create temporary table r2_12_1_expected(
    envelope_name text primary key,
    account_name text,
    recommendation_kind text not null
  ) on commit drop;
  insert into r2_12_1_expected values
    ('Traite maison','Islamique / Arreda Ibrahim','single_account'),
    ('Traite normale','Islamique / Arreda Ibrahim','single_account'),
    ('TSC','Islamique / Arreda Ibrahim','single_account'),
    ('Syndic','Islamique / Arreda Ibrahim','single_account'),
    ('Eau elec abonnement','Islamique / Arreda Ibrahim','single_account'),
    ('Mouton','Islamique / Arreda Ibrahim','single_account'),
    ('Ecole Niece','Islamique / Arreda Ibrahim','single_account'),
    ('Parrents','Islamique / Arreda Ibrahim','single_account'),
    ('Parrents Nora','Banque Nora','single_account'),
    ('Traite voiture','Banque Nora','single_account'),
    ('Wifi','Banque Nora','single_account'),
    ('Besoin perso','Banque Nora','single_account'),
    ('Nourriture','Espèces maison','single_account'),
    ('Habits',null,'scenario_split'),
    ('Imprévus','Islamique / Arreda Ibrahim','single_account'),
    ('Voyages','Islamique / Arreda Ibrahim','single_account'),
    ('Sorties WE','AWB Ibrahim','single_account'),
    ('Fêtes religieuses','AWB Ibrahim','single_account'),
    ('Navette','Espèces maison','single_account'),
    ('Epargne','Islamique / Arreda Ibrahim','single_account'),
    ('Reste epargne (primes Ibrahim et Nora)',null,'member_beneficiary'),
    ('Vidange','Banque Nora','single_account'),
    ('Entretien','Banque Nora','single_account'),
    ('Assurance','Banque Nora','single_account'),
    ('Vignette','Banque Nora','single_account');

  if (select count(*) from r2_12_1_expected) <> 25 then
    raise exception 'R2.12.1 expected inventory mismatch';
  end if;
  if exists (
    select 1 from r2_12_1_expected x
    left join public.envelopes e
      on e.household_id = v_household
     and e.name = x.envelope_name
     and e.archived_at is null
    where e.id is null
  ) then
    raise exception 'R2.12.1 envelope mapping incomplete';
  end if;
  if exists (
    select 1 from r2_12_1_expected x
    left join public.accounts a
      on a.household_id = v_household
     and a.name = x.account_name
     and a.archived_at is null
     and not a.is_system
    where x.account_name is not null and a.id is null
  ) then
    raise exception 'R2.12.1 account mapping incomplete';
  end if;

  for v_item in
    select e.id, e.recommended_account_id, e.recommended_payment_method_id,
      e.recommendation_kind, e.recommendation_definition,
      x.account_name, x.recommendation_kind expected_kind
    from r2_12_1_expected x
    join public.envelopes e
      on e.household_id = v_household
     and e.name = x.envelope_name
     and e.archived_at is null
    where x.envelope_name in ('Voyages', 'Vignette')
    order by x.envelope_name
  loop
    select id into v_target_account
    from public.accounts
    where household_id = v_household
      and name = v_item.account_name
      and archived_at is null
      and not is_system;

    if v_item.recommended_account_id is distinct from v_target_account
       or v_item.recommendation_kind is distinct from v_item.expected_kind then
      v_previous_account := v_item.recommended_account_id;
      v_previous_method := v_item.recommended_payment_method_id;
      v_previous_kind := v_item.recommendation_kind;
      v_previous_definition := v_item.recommendation_definition;

      update public.envelopes
      set recommended_account_id = v_target_account,
          recommended_payment_method_id = case
            when recommended_payment_method_id is null then null
            when exists (
              select 1 from public.payment_methods pm
              where pm.id = recommended_payment_method_id
                and pm.household_id = v_household
                and pm.active
                and pm.archived_at is null
                and (pm.account_id is null or pm.account_id = v_target_account)
            ) then recommended_payment_method_id
            else null
          end,
          recommendation_kind = v_item.expected_kind,
          recommendation_definition = coalesce(recommendation_definition, '{}'::jsonb)
            || jsonb_build_object(
              'source', 'user_confirmed_r2_12_1',
              'historical_position_proof', false
            )
      where id = v_item.id
      returning * into v_updated;

      insert into public.envelope_recommendation_events(
        household_id,envelope_id,previous_account_id,account_id,
        previous_payment_method_id,payment_method_id,actor_user_id,
        previous_recommendation_kind,recommendation_kind,
        previous_recommendation_definition,recommendation_definition,
        change_source
      ) values (
        v_household,v_updated.id,v_previous_account,
        v_updated.recommended_account_id,v_previous_method,
        v_updated.recommended_payment_method_id,v_actor,v_previous_kind,
        v_updated.recommendation_kind,v_previous_definition,
        v_updated.recommendation_definition,
        'r2_12_1_user_confirmed_correction'
      );
    end if;
  end loop;

  if exists (
    select 1 from r2_12_1_expected x
    join public.envelopes e
      on e.household_id = v_household
     and e.name = x.envelope_name
     and e.archived_at is null
    left join public.accounts a on a.id = e.recommended_account_id
    where e.recommendation_kind is distinct from x.recommendation_kind
       or (x.account_name is null and e.recommended_account_id is not null)
       or (x.account_name is not null and a.name is distinct from x.account_name)
  ) then
    raise exception 'R2.12.1 canonical structural recommendation audit failed';
  end if;
end $$;

commit;
