-- RUN THIS ONCE in the Supabase SQL editor of project pufjmaztcvuazhfiyanu.
-- Payment hardening: verified-payment bookkeeping + tamper-proof payment fields.
-- Additive and idempotent. No data is removed; the only dropped policy is the
-- admin UPDATE policy, recreated immediately with an explicit WITH CHECK.

-- 1. Payment bookkeeping columns.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'INR',
  ADD COLUMN IF NOT EXISTS payment_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS verification_status text;

-- 2. Uniqueness so a Razorpay order/payment can never be recorded twice.
CREATE UNIQUE INDEX IF NOT EXISTS orders_razorpay_order_id_key
  ON public.orders (razorpay_order_id) WHERE razorpay_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS orders_payment_id_key
  ON public.orders (payment_id) WHERE payment_id IS NOT NULL;

-- 3. Payment fields may only be written by trusted backend code (service_role).
--    Admins keep full control of fulfilment fields (status, tracking, notes).
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

-- 4. Admin UPDATE policy gets an explicit WITH CHECK (previously USING only).
DROP POLICY IF EXISTS "Admins update orders" ON public.orders;
CREATE POLICY "Admins update orders" ON public.orders
  FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- 5. payment_events (idempotency ledger) — ensure it exists with the same shape
--    the webhook writes, and index the reconciliation lookup.
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
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins view payment events" ON public.payment_events;
CREATE POLICY "Admins view payment events" ON public.payment_events
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));

CREATE INDEX IF NOT EXISTS payment_events_order_idx
  ON public.payment_events (razorpay_order_id);
