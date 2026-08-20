# Project Guardian — Security Fixes

Ye zip sirf **badle hue / naye files** contain karta hai. Apne repo me same
folder path pe drop kar dena.

## 1. `supabase/migrations/20260818055420_fix_orders_insert_policy.sql` (NEW FILE)

**Problem:** `orders` table ki INSERT RLS policy sirf `auth.uid() = user_id`
check karti thi. Isse koi bhi logged-in user browser console se seedha
`supabase.from('orders').insert({..., status:'PAID', payment_status:'paid'})`
call karke **bina payment kiye fake "PAID" order** bana sakta tha.

**Fix:**
- INSERT policy ab `status`, `payment_status` ko sirf unpaid default values
  tak restrict karti hai.
- Ek `BEFORE INSERT` trigger bhi add kiya hai jo har non-service-role insert
  ke liye `status`, `payment_status`, `payment_id`, `transaction_id`,
  `paid_at` ko forcibly safe/unpaid state me reset kar deta hai — chahe
  policy me future me koi mistake ho jaye, ye ek extra safety layer hai.
- Service role (edge functions jo real payment verify karte hain) is
  restriction se untouched hai — wahi ab bhi order ko "PAID" mark kar sakta
  hai, jaisa hona chahiye.

**Apply kaise kare:**
```bash
supabase db push
# ya Supabase Dashboard > SQL Editor me is file ka content run kar do
```

## 2. `supabase/functions/verify-razorpay-payment/index.ts` (MODIFIED)

**Problem:** Line ~128 par `json(409, {...})` call tha, lekin file ke apne
`json(body, status=200)` helper ka argument order ulta hai. Isse jab
Razorpay payment "authorized" hota tha but "captured" nahi hota tha
(edge-case), tab response galat/crash ho sakta tha.

**Fix:** Arguments sahi order me kar diye: `json({...}, 409)`.

**Apply kaise kare:**
```bash
supabase functions deploy verify-razorpay-payment
```

---

Dono fixes deploy karne ke baad payment flow pehle jaisa hi kaam karega
(customer ko koi difference dikhega nahi) — bas backend ab safe hai aur
fake/free "paid" orders create nahi ho sakte.
