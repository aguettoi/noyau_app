begin;

alter table public.shopping_item_history
  drop constraint shopping_item_history_action_check;

alter table public.shopping_item_history
  add constraint shopping_item_history_action_check
  check (
    action in (
      'created',
      'updated',
      'member_priority_set',
      'member_priority_cleared',
      'cancelled',
      'archived'
    )
  );

commit;
