# New backend setup — Supabase `oqxmqlbwiwdlvdmfpvmf` + Razorpay live

The app code is already pointed at the new project. These are the steps you must
run yourself in the Supabase dashboard / CLI, because the project is external
and cannot be administered from Lovable.

Public (browser-safe) values already wired in code, `.env` and `netlify.toml`:

- URL: `https://oqxmqlbwiwdlvdmfpvmf.supabase.co`
- Publishable key: `sb_publishable_U-v6O0G6WfCQCOzyBQxxdA_tHAiJGGt`

---

## 1. Create the database schema

Open **Supabase → SQL Editor** on the new project, paste the whole contents of:

```
db/setup/full_schema.sql
```

and run it once, top to bottom. It is the ordered concatenation of every file in
`supabase/migrations/` plus `db/manual/2026-08-19_payment_hardening.sql`, so it
recreates the exact existing data model: `profiles`, `user_roles` + `has_role()`,
`products` (with the existing product/price seed rows), `orders`, `order_items`,
`order_status_history` / tracking, `reviews`, `wishlists`, `visitor_leads`,
`payment_events`, storage buckets, all RLS policies, triggers and grants.

CLI alternative (same result, keeps migration history):

```bash
supabase link --project-ref oqxmqlbwiwdlvdmfpvmf
supabase db push
# then run db/manual/2026-08-19_payment_hardening.sql once in the SQL editor
```

## 2. Auth configuration

**Authentication → Providers → Email**: enable Email/Password.
For the existing signup flow to work without an inbox round-trip, keep
"Confirm email" set the same way as on the old project (it was off).

**Authentication → URL Configuration**: set Site URL to your production domain
and add it (plus the Lovable preview domain) to Redirect URLs.

Admin: the `handle_new_user()` trigger auto-grants the `admin` role to
`astrowithhrishi@gmail.com` on sign-up. Register that email once through the
normal sign-up form on the new project to recreate the admin account. No admin
credentials exist anywhere in the frontend.

## 3. Deploy the Edge Functions

```bash
supabase functions deploy create-razorpay-order --project-ref oqxmqlbwiwdlvdmfpvmf
supabase functions deploy verify-razorpay-payment --project-ref oqxmqlbwiwdlvdmfpvmf
supabase functions deploy razorpay-webhook --project-ref oqxmqlbwiwdlvdmfpvmf
```

`supabase/config.toml` already sets `verify_jwt = false` for all three (the
functions validate the bearer token in code; the webhook authenticates by HMAC).

## 4. Server-side secrets (never in frontend code)

Supabase → **Edge Functions → Secrets**:

| Secret | Value |
| --- | --- |
| `RAZORPAY_KEY_ID` | your live `rzp_live_...` key id |
| `RAZORPAY_KEY_SECRET` | your live key secret |
| `RAZORPAY_WEBHOOK_SECRET` | the webhook secret you set in Razorpay |

`SUPABASE_URL`, `SUPABASE_ANON_KEY`/`SUPABASE_PUBLISHABLE_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` are injected into Edge Functions automatically.

If you also keep the Netlify functions live, set the same three Razorpay values
plus `SUPABASE_SERVICE_ROLE_KEY` in **Netlify → Site settings → Environment
variables** (never in `netlify.toml`).

## 5. Razorpay webhook

Razorpay Dashboard → Settings → Webhooks → Add:

- URL (Supabase): `https://oqxmqlbwiwdlvdmfpvmf.supabase.co/functions/v1/razorpay-webhook`
- URL (Netlify alternative): `https://<your-domain>/.netlify/functions/razorpay-webhook`
- Secret: the same value stored as `RAZORPAY_WEBHOOK_SECRET`
- Events: `payment.captured`, `payment.failed`, `refund.created`, `refund.processed`

Replays are safe: every event is inserted into `payment_events` with a unique
`event_id`, and a duplicate returns 200 without touching the order.

## 6. Payment security model (unchanged, preserved)

- The browser never declares a payment paid. `verify-razorpay-payment` checks the
  HMAC signature against the **server-stored** `razorpay_order_id`, then re-fetches
  the payment from Razorpay's API, captures it if it is only authorized, and
  compares the amount with the stored order total before marking it paid.
- The `trg_orders_protect_payment_fields` trigger reverts any attempt by an
  `anon`/`authenticated` session (including admins) to write `payment_status`,
  `status` money fields, `payment_id`, `transaction_id`, `paid_at`, totals or
  `user_id`. Only `service_role` (the functions) can set them.
- Unique indexes on `razorpay_order_id` and `payment_id` block double-recording.
