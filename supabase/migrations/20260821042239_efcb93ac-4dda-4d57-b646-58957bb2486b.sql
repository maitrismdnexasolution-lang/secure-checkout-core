-- ============================================================
-- Linter cleanup: revoke direct EXECUTE on SECURITY DEFINER trigger functions
-- (trigger invocation does not check EXECUTE, so revoking is safe) and pin
-- search_path on the remaining mutable-path functions.
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.orders_set_order_number() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.orders_sync_items() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.orders_log_status() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.orders_force_safe_insert_status() FROM PUBLIC, anon, authenticated;

-- Pin search_path on mutable-path functions.
CREATE OR REPLACE FUNCTION public.generate_order_number()
RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $$
declare candidate text;
begin
  loop
    candidate := 'ORD-' || upper(encode(gen_random_bytes(4), 'hex'));
    exit when not exists (select 1 from public.orders where order_number = candidate);
  end loop;
  return candidate;
end;
$$;

CREATE OR REPLACE FUNCTION public.orders_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
begin new.updated_at := now(); return new; end;
$$;

CREATE OR REPLACE FUNCTION public.normalize_order_status(_status text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  select case lower(coalesce(_status, ''))
    when 'pending_payment' then 'placed'
    when 'created' then 'placed'
    when 'paid' then 'payment_confirmed'
    when 'payment_authenticated' then 'payment_confirmed'
    when 'payment_failed' then 'payment_failed'
    when 'confirmed' then 'confirmed'
    when 'canceled' then 'cancelled'
    when '' then 'placed'
    else lower(_status)
  end
$$;

CREATE OR REPLACE FUNCTION public.order_status_rank(_status text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  select case public.normalize_order_status(_status)
    when 'placed' then 0
    when 'payment_confirmed' then 1
    when 'confirmed' then 2
    when 'processing' then 3
    when 'packed' then 4
    when 'shipped' then 5
    when 'out_for_delivery' then 6
    when 'delivered' then 7
    else -1
  end
$$;