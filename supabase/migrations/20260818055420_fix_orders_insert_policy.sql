-- ============================================================================
-- SECURITY FIX: lock down direct INSERT on public.orders
-- ----------------------------------------------------------------------------
-- Previously "Users create own orders" only checked `auth.uid() = user_id`.
-- Because Supabase's anon key + a user's own JWT are always available in the
-- browser, ANY authenticated user could call `supabase.from('orders').insert()`
-- directly (bypassing the create-razorpay-order / verify-razorpay-payment
-- functions entirely) and set status/payment_status to 'PAID' themselves,
-- creating a fully-fraudulent "paid" order with no real payment.
--
-- The real order-creation path (create-razorpay-order edge function) already
-- uses the service_role key and is unaffected by this policy. This fix only
-- restricts what a normal authenticated client is allowed to insert directly,
-- forcing every order to start in a safe, unpaid state. Marking an order PAID
-- is only ever done by the payment-verification / webhook functions (service
-- role) or by admins (existing "Admins update orders" policy), never by a
-- plain INSERT from the browser.
-- ============================================================================

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
-- Only service-role (which bypasses RLS and triggers checks below are skipped
-- for service_role via `is_service_role`) and the admin RPCs can move status
-- forward after creation.
create or replace function public.orders_force_safe_insert_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- service_role writes (edge functions) are trusted and left untouched.
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
