-- Keeps public profile data in sync with every authenticated Supabase user.
alter table public.profiles
  alter column display_name drop not null,
  add column if not exists email text;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email, created_at)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), '')
    ),
    new.email,
    new.created_at
  )
  on conflict (id) do update
  set
    display_name = coalesce(public.profiles.display_name, excluded.display_name),
    email = coalesce(public.profiles.email, excluded.email);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Repairs only missing profiles for users who existed before this trigger.
insert into public.profiles (id, display_name, email, created_at)
select
  users.id,
  coalesce(
    nullif(trim(users.raw_user_meta_data ->> 'display_name'), ''),
    nullif(trim(users.raw_user_meta_data ->> 'full_name'), '')
  ),
  users.email,
  users.created_at
from auth.users users
on conflict (id) do update
set
  display_name = coalesce(public.profiles.display_name, excluded.display_name),
  email = coalesce(public.profiles.email, excluded.email);
