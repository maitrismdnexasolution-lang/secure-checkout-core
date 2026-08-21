-- ============================================================
-- 20260818055420_fix_orders_insert_policy.sql
-- ============================================================
-- SECURITY FIX: lock down direct INSERT on public.orders.
-- Previously "Users create own orders" only checked auth.uid() = user_id, so ANY
-- authenticated user could insert a fully-fraudulent "paid" order directly.
-- The real order-creation path (create-razorpay-order edge function) uses the
-- service_role key and is unaffected. This forces every browser-created order
-- to start in a safe, unpaid state.

drop policy if exists "Users create own orders" on public.orders;

create policy "Users create own orders"
  on public.orders
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and coalesce(status, 'PENDING_PAYMENT') in ('PENDING_PAYMENT', 'pending')
    and coalesce(payment_status, 'pending') = 'pending'
    and payment_id is null
    and transaction_id is null
    and paid_at is null
  );

-- Belt-and-braces: even if a future policy change slips up, this trigger
-- guarantees a row can never be inserted as already paid/shipped/etc.
-- service_role writes (edge functions) are trusted and left untouched.
create or replace function public.orders_force_safe_insert_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() = 'service_role' then
    return new;
  end if;

  new.status := coalesce(nullif(new.status, ''), 'PENDING_PAYMENT');
  new.payment_status := coalesce(nullif(new.payment_status, ''), 'pending');

  if new.status not in ('PENDING_PAYMENT', 'pending') then
    new.status := 'PENDING_PAYMENT';
  end if;
  if new.payment_status <> 'pending' then
    new.payment_status := 'pending';
  end if;

  new.payment_id := null;
  new.transaction_id := null;
  new.paid_at := null;

  return new;
end;
$$;

drop trigger if exists trg_orders_force_safe_insert_status on public.orders;
create trigger trg_orders_force_safe_insert_status
  before insert on public.orders
  for each row execute function public.orders_force_safe_insert_status();


-- ============================================================
-- 20260819105728_14cd1198 + 2026-08-19_payment_hardening (consolidated)
-- ============================================================
-- Payment bookkeeping columns + tamper-proof payment fields.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'INR',
  ADD COLUMN IF NOT EXISTS payment_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS verification_status text;

CREATE UNIQUE INDEX IF NOT EXISTS orders_razorpay_order_id_key
  ON public.orders (razorpay_order_id) WHERE razorpay_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS orders_payment_id_key
  ON public.orders (payment_id) WHERE payment_id IS NOT NULL;

-- Payment fields may only be written by trusted backend code (service_role).
-- Admins keep full control of fulfilment fields (status, tracking, notes).
CREATE OR REPLACE FUNCTION public.orders_protect_payment_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  v_role := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );

  -- Trusted server contexts: Netlify/edge functions (service_role) and direct DB access.
  IF v_role = 'service_role' OR v_role = '' THEN
    RETURN NEW;
  END IF;

  -- Anything reaching the table through the browser (anon/authenticated, including
  -- admins) can never change money or payment-verification state.
  NEW.payment_status       := OLD.payment_status;
  NEW.payment_id           := OLD.payment_id;
  NEW.razorpay_order_id    := OLD.razorpay_order_id;
  NEW.transaction_id       := OLD.transaction_id;
  NEW.paid_at              := OLD.paid_at;
  NEW.payment_verified_at  := OLD.payment_verified_at;
  NEW.verification_status  := OLD.verification_status;
  NEW.subtotal             := OLD.subtotal;
  NEW.discount             := OLD.discount;
  NEW.shipping             := OLD.shipping;
  NEW.total                := OLD.total;
  NEW.currency             := OLD.currency;
  NEW.user_id              := OLD.user_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_protect_payment_fields ON public.orders;
CREATE TRIGGER trg_orders_protect_payment_fields
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.orders_protect_payment_fields();

-- Admin UPDATE policy gets an explicit WITH CHECK (previously USING only).
DROP POLICY IF EXISTS "Admins update orders" ON public.orders;
CREATE POLICY "Admins update orders" ON public.orders
  FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- payment_events (idempotency ledger) — ensure it exists with the shape the
-- webhook writes, and index the reconciliation lookup.
CREATE TABLE IF NOT EXISTS public.payment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL UNIQUE,
  event_type text NOT NULL,
  payment_id text,
  razorpay_order_id text,
  payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.payment_events TO service_role;
GRANT SELECT ON public.payment_events TO authenticated;
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins view payment events" ON public.payment_events;
CREATE POLICY "Admins view payment events" ON public.payment_events
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));

CREATE INDEX IF NOT EXISTS payment_events_order_idx
  ON public.payment_events (razorpay_order_id);

-- ============================================================
-- 20260819105803_7f634b54 — function privilege hardening
-- ============================================================
REVOKE ALL ON FUNCTION public.orders_protect_payment_fields() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;