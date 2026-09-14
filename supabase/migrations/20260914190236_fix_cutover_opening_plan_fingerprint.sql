-- The B1 orchestrator executes with search_path=public.  pgcrypto lives in
-- extensions, so expose the one text-to-bytea bridge needed by the immutable
-- plan checksum without changing the already-applied B1 function body.
begin;

create or replace function public.digest(p_data text, p_algorithm text)
returns bytea
language sql immutable strict security invoker
set search_path = extensions, pg_catalog
as $$
  select extensions.digest(convert_to(p_data, 'UTF8'), p_algorithm);
$$;

revoke all on function public.digest(text,text) from public, anon;
grant execute on function public.digest(text,text) to authenticated;

commit;
