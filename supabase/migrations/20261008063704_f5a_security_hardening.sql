begin;
alter function public.f5a_append_only() set search_path = public;
revoke all on function public.f5a_append_only() from public,anon,authenticated;
commit;
