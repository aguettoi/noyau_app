-- Preserve the immutable cancellation audit when a cancelled item is archived.
begin;

alter table public.shopping_items
  drop constraint if exists shopping_items_cancellation_audit_check,
  add constraint shopping_items_cancellation_audit_check check (
    (status = 'cancelled' and cancelled_by is not null and cancelled_at is not null)
    or (status = 'archived')
    or (status not in ('cancelled', 'archived')
      and cancelled_by is null and cancelled_at is null and cancellation_reason is null)
  );

commit;
