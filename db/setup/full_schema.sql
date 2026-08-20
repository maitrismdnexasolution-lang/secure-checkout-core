-- CONSOLIDATED SCHEMA FOR THE NEW SUPABASE PROJECT (oqxmqlbwiwdlvdmfpvmf)
-- Generated from supabase/migrations/* in original order + payment hardening.
-- Run once, top to bottom, in the Supabase SQL editor of the NEW project.


-- ============================================================
-- 20260613055805_14a944e6-5e69-43db-87e9-1d22e50201a5.sql
-- ============================================================

-- ============ ROLES ============
CREATE TYPE public.app_role AS ENUM ('admin', 'user');

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL DEFAULT 'user',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE POLICY "Users view own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins view all roles" ON public.user_roles FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins manage roles" ON public.user_roles FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- ============ PROFILES ============
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text,
  phone text,
  email text,
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "Admins view all profiles" ON public.profiles FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

-- Trigger for auto-profile + default user role on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', ''));
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'user');
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Generic updated_at trigger
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

-- ============ PRODUCTS ============
CREATE TABLE public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  price numeric(10,2) NOT NULL,
  image_url text,
  category text,
  stock integer NOT NULL DEFAULT 100,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.products TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated;
GRANT ALL ON public.products TO service_role;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views active products" ON public.products FOR SELECT USING (active = true OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "Admins manage products" ON public.products FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
CREATE TRIGGER products_updated BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============ ORDERS ============
CREATE TABLE public.orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  customer_name text NOT NULL,
  customer_phone text NOT NULL,
  customer_email text,
  address text NOT NULL,
  items jsonb NOT NULL,
  subtotal numeric(10,2) NOT NULL,
  total numeric(10,2) NOT NULL,
  status text NOT NULL DEFAULT 'pending', -- pending, paid, shipped, delivered, cancelled
  payment_id text,
  razorpay_order_id text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated;
GRANT ALL ON public.orders TO service_role;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own orders" ON public.orders FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users create own orders" ON public.orders FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins view all orders" ON public.orders FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin'));
CREATE POLICY "Admins update orders" ON public.orders FOR UPDATE TO authenticated USING (public.has_role(auth.uid(),'admin'));
CREATE TRIGGER orders_updated BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============ APPOINTMENTS ============
CREATE TABLE public.appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  name text NOT NULL,
  phone text NOT NULL,
  email text,
  service text NOT NULL,
  appointment_date date NOT NULL,
  appointment_time text NOT NULL,
  message text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.appointments TO anon, authenticated;
GRANT UPDATE ON public.appointments TO authenticated;
GRANT ALL ON public.appointments TO service_role;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone creates appointment" ON public.appointments FOR INSERT WITH CHECK (true);
CREATE POLICY "Users view own appointments" ON public.appointments FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins manage appointments" ON public.appointments FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- ============ BLOG ============
CREATE TABLE public.blog_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  excerpt text,
  content text NOT NULL,
  cover_url text,
  published boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.blog_posts TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.blog_posts TO authenticated;
GRANT ALL ON public.blog_posts TO service_role;
ALTER TABLE public.blog_posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views published" ON public.blog_posts FOR SELECT USING (published = true OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "Admins manage blog" ON public.blog_posts FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
CREATE TRIGGER blog_updated BEFORE UPDATE ON public.blog_posts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============ GALLERY ============
CREATE TABLE public.gallery_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  image_url text NOT NULL,
  caption text,
  category text NOT NULL DEFAULT 'events', -- events, clients, spiritual, photos
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.gallery_items TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.gallery_items TO authenticated;
GRANT ALL ON public.gallery_items TO service_role;
ALTER TABLE public.gallery_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views gallery" ON public.gallery_items FOR SELECT USING (true);
CREATE POLICY "Admins manage gallery" ON public.gallery_items FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- ============ VIDEOS ============
CREATE TABLE public.videos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  youtube_id text NOT NULL,
  title text NOT NULL,
  description text,
  category text NOT NULL DEFAULT 'general',
  video_type text NOT NULL DEFAULT 'video', -- video, short
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.videos TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.videos TO authenticated;
GRANT ALL ON public.videos TO service_role;
ALTER TABLE public.videos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views videos" ON public.videos FOR SELECT USING (true);
CREATE POLICY "Admins manage videos" ON public.videos FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- ============ TESTIMONIALS ============
CREATE TABLE public.testimonials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_name text NOT NULL,
  location text,
  rating integer NOT NULL DEFAULT 5,
  message text NOT NULL,
  avatar_url text,
  featured boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.testimonials TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.testimonials TO authenticated;
GRANT ALL ON public.testimonials TO service_role;
ALTER TABLE public.testimonials ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views testimonials" ON public.testimonials FOR SELECT USING (true);
CREATE POLICY "Admins manage testimonials" ON public.testimonials FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- ============ CONTACT ============
CREATE TABLE public.contact_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL,
  phone text,
  subject text,
  message text NOT NULL,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT INSERT ON public.contact_messages TO anon, authenticated;
GRANT SELECT, UPDATE, DELETE ON public.contact_messages TO authenticated;
GRANT ALL ON public.contact_messages TO service_role;
ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone sends message" ON public.contact_messages FOR INSERT WITH CHECK (true);
CREATE POLICY "Admins view messages" ON public.contact_messages FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin'));
CREATE POLICY "Admins update messages" ON public.contact_messages FOR UPDATE TO authenticated USING (public.has_role(auth.uid(),'admin'));

-- ============ SEED DATA ============
INSERT INTO public.products (name, description, price, image_url, category, stock) VALUES
('Natural Rudraksha Mala (108 Beads)', 'Authentic 5-mukhi Rudraksha mala for meditation & peace. Energized with Vedic mantras.', 1999, 'https://images.unsplash.com/photo-1611042553365-9b101441c135?w=800', 'mala', 50),
('Yellow Sapphire (Pukhraj) - Certified', 'Lab-certified natural yellow sapphire 5.25 ratti. Boosts wisdom, wealth & Jupiter energies.', 12500, 'https://images.unsplash.com/photo-1599643478518-a784e5dc4c8f?w=800', 'gemstone', 10),
('Sphatik (Crystal) Shree Yantra', 'Hand-carved natural crystal Shree Yantra for prosperity and positive vibrations.', 3499, 'https://images.unsplash.com/photo-1610375461246-83df859d849d?w=800', 'yantra', 25),
('Personalized Kundli Report (PDF)', 'In-depth 40-page Vedic birth chart analysis with predictions & remedies.', 999, 'https://images.unsplash.com/photo-1518622358385-8ea7d0794bf6?w=800', 'report', 999),
('Red Coral (Moonga) - Certified', 'Natural Italian red coral 6 ratti for Mars strengthening and courage.', 8999, 'https://images.unsplash.com/photo-1573408301185-9146fe634ad0?w=800', 'gemstone', 15),
('Parad (Mercury) Shivling', 'Sacred Parad Shivling for spiritual healing & wealth attraction.', 5499, 'https://images.unsplash.com/photo-1604608672516-f1b9b1d1f1b1?w=800', 'spiritual', 20);

INSERT INTO public.testimonials (client_name, location, rating, message) VALUES
('Priya Sharma', 'Mumbai', 5, 'Hrishi ji ki predictions amazing thi! Career me jo bola wahi hua. Bahut accurate aur trustworthy.'),
('Rajesh Patel', 'Ahmedabad', 5, 'Marriage consultation se hamari shadi smoothly hui. Vastu guidance bhi bahut helpful tha.'),
('Anjali Mehta', 'Surat', 5, 'Best astrologer I have consulted. Genuine, kind and the remedies actually work!'),
('Vikram Singh', 'Delhi', 5, 'Business astrology ne mera business 3x growth diya. Highly recommended.'),
('Sneha Reddy', 'Hyderabad', 5, 'Numerology session was eye-opening. My name correction changed my luck completely.'),
('Amit Joshi', 'Pune', 5, 'Kundli reading was so detailed and precise. Worth every rupee.');

INSERT INTO public.blog_posts (slug, title, excerpt, content, cover_url) VALUES
('mercury-retrograde-2026', 'Mercury Retrograde 2026: What to Expect', 'Understand how Mercury retrograde affects communication, travel & decisions.', '# Mercury Retrograde 2026

Mercury retrograde is one of the most discussed astrological phenomena. In 2026, it occurs four times...

## What it means
When Mercury appears to move backward, communication, technology and travel can get disrupted.

## Remedies
- Wear an emerald
- Chant "Om Budhaya Namah" 108 times daily
- Donate green items on Wednesdays', 'https://images.unsplash.com/photo-1532968961962-8a0cb3a2d4f5?w=1200'),
('power-of-rudraksha', 'The Hidden Power of Rudraksha Beads', 'Discover the spiritual & scientific benefits of wearing Rudraksha.', '# The Power of Rudraksha

Rudraksha beads have been revered for thousands of years...

## Benefits
- Reduces stress & anxiety
- Balances blood pressure
- Enhances meditation
- Removes negative energies', 'https://images.unsplash.com/photo-1611042553365-9b101441c135?w=1200'),
('vastu-tips-home', '7 Vastu Tips for a Prosperous Home', 'Simple Vastu adjustments that bring wealth and harmony.', '# Vastu Tips

Your home directly affects your destiny. Apply these tips...

1. Main door should face North or East
2. Kitchen in South-East
3. Master bedroom in South-West
4. No mirrors facing the bed
5. Keep North-East corner clean & open
6. Avoid clutter under stairs
7. Place a money plant in South-East', 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=1200');

INSERT INTO public.gallery_items (image_url, caption, category) VALUES
('https://images.unsplash.com/photo-1518622358385-8ea7d0794bf6?w=800', 'Vedic Pooja Ceremony', 'spiritual'),
('https://images.unsplash.com/photo-1604608672516-9c2f2c2e1234?w=800', 'Live Astrology Event', 'events'),
('https://images.unsplash.com/photo-1532968961962-8a0cb3a2d4f5?w=800', 'Cosmic Energy Session', 'spiritual'),
('https://images.unsplash.com/photo-1543946207-39bd91e70ca7?w=800', 'Happy Client Consultation', 'clients'),
('https://images.unsplash.com/photo-1606327054536-e37e655d4f4d?w=800', 'Workshop in Ahmedabad', 'events'),
('https://images.unsplash.com/photo-1610375461246-83df859d849d?w=800', 'Crystal Healing Setup', 'spiritual'),
('https://images.unsplash.com/photo-1611042553365-9b101441c135?w=800', 'Sacred Rudraksha Collection', 'photos'),
('https://images.unsplash.com/photo-1573408301185-9146fe634ad0?w=800', 'Gemstone Ceremony', 'events');

INSERT INTO public.videos (youtube_id, title, description, category, video_type) VALUES
('dQw4w9WgXcQ', 'Daily Horoscope - Today''s Cosmic Energy', 'Quick daily reading for all 12 zodiac signs', 'horoscope', 'video'),
('jNQXAC9IVRw', 'How to Read Your Kundli', 'Beginner''s guide to understanding your birth chart', 'education', 'video'),
('9bZkp7q19f0', 'Powerful Mantras for Wealth', 'Chant these mantras for prosperity', 'mantra', 'short'),
('kJQP7kiw5Fk', 'Vastu Tips for Bedroom', 'Quick Vastu hacks for better sleep & love', 'vastu', 'short'),
('L_jWHffIx5E', 'Rudraksha Benefits Explained', 'Science meets spirituality', 'education', 'video'),
('fJ9rUzIMcZQ', 'Mercury Retrograde Survival Guide', '5 things to do during Mercury retrograde', 'horoscope', 'short');



-- ============================================================
-- 20260613055841_6d39c433-1a5b-4733-ae50-69b523db1f5e.sql
-- ============================================================

ALTER FUNCTION public.set_updated_at() SET search_path = public;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;



-- ============================================================
-- 20260613055909_ce974d6f-e666-4e61-973f-cec4138d0c08.sql
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated, public;



-- ============================================================
-- 20260630064033_20250130_create_visitor_leads.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS visitor_leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  mobile_number TEXT NOT NULL,
  email TEXT,
  city TEXT,
  interested_service TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE visitor_leads ENABLE ROW LEVEL SECURITY;

-- Policies for authenticated users (admin)
CREATE POLICY "select_visitor_leads" ON visitor_leads FOR SELECT
  TO authenticated USING (true);
CREATE POLICY "insert_visitor_leads" ON visitor_leads FOR INSERT
  TO anon, authenticated WITH CHECK (true);

-- Index for common queries
CREATE INDEX idx_visitor_leads_created_at ON visitor_leads(created_at DESC);
CREATE INDEX idx_visitor_leads_service ON visitor_leads(interested_service);
CREATE INDEX idx_visitor_leads_city ON visitor_leads(city);



-- ============================================================
-- 20260706031120_0f7836c4-3afa-428d-a9f1-8839d85f89b1.sql
-- ============================================================

GRANT SELECT ON public.products TO anon, authenticated;
GRANT ALL ON public.products TO service_role;



-- ============================================================
-- 20260706031230_5e1116b5-03f3-4139-9476-4a34d718ce45.sql
-- ============================================================

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

REVOKE ALL ON SCHEMA private FROM public, anon, authenticated;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION private.has_role(uuid, public.app_role) FROM public, anon;
GRANT EXECUTE ON FUNCTION private.has_role(uuid, public.app_role) TO authenticated, service_role;

DROP POLICY IF EXISTS "Admins view all roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins manage roles" ON public.user_roles;
CREATE POLICY "Admins view all roles" ON public.user_roles FOR SELECT TO authenticated USING (private.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins manage roles" ON public.user_roles FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admins view all profiles" ON public.profiles;
CREATE POLICY "Admins view all profiles" ON public.profiles FOR SELECT TO authenticated USING (private.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Anyone views active products" ON public.products;
DROP POLICY IF EXISTS "Admins manage products" ON public.products;
CREATE POLICY "Anyone views active products" ON public.products FOR SELECT TO public USING (active = true);
CREATE POLICY "Admins manage products" ON public.products FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admins view all orders" ON public.orders;
DROP POLICY IF EXISTS "Admins update orders" ON public.orders;
CREATE POLICY "Admins view all orders" ON public.orders FOR SELECT TO authenticated USING (private.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins update orders" ON public.orders FOR UPDATE TO authenticated USING (private.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admins manage appointments" ON public.appointments;
DROP POLICY IF EXISTS "Anyone creates appointment" ON public.appointments;
CREATE POLICY "Anyone creates appointment" ON public.appointments FOR INSERT TO public WITH CHECK (
  length(trim(name)) >= 2
  AND length(trim(phone)) >= 8
  AND length(trim(service)) >= 2
  AND length(trim(appointment_time)) >= 2
  AND appointment_date IS NOT NULL
);
CREATE POLICY "Admins manage appointments" ON public.appointments FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Anyone views published" ON public.blog_posts;
DROP POLICY IF EXISTS "Admins manage blog" ON public.blog_posts;
CREATE POLICY "Anyone views published" ON public.blog_posts FOR SELECT TO public USING (published = true);
CREATE POLICY "Admins manage blog" ON public.blog_posts FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admins manage gallery" ON public.gallery_items;
CREATE POLICY "Admins manage gallery" ON public.gallery_items FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admins manage videos" ON public.videos;
CREATE POLICY "Admins manage videos" ON public.videos FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admins manage testimonials" ON public.testimonials;
CREATE POLICY "Admins manage testimonials" ON public.testimonials FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admins view messages" ON public.contact_messages;
DROP POLICY IF EXISTS "Admins update messages" ON public.contact_messages;
DROP POLICY IF EXISTS "Anyone sends message" ON public.contact_messages;
CREATE POLICY "Anyone sends message" ON public.contact_messages FOR INSERT TO public WITH CHECK (
  length(trim(name)) >= 2
  AND length(trim(email)) >= 5
  AND position('@' in email) > 1
  AND length(trim(message)) >= 10
);
CREATE POLICY "Admins view messages" ON public.contact_messages FOR SELECT TO authenticated USING (private.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins update messages" ON public.contact_messages FOR UPDATE TO authenticated USING (private.has_role(auth.uid(), 'admin'));

REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM public, anon, authenticated;



-- ============================================================
-- 20260723113520_34d12fb1-8e2b-4824-8b18-d68602dc4b97.sql
-- ============================================================

-- Seed admin user and lock down access
DO $$
DECLARE
  new_user_id uuid;
BEGIN
  SELECT id INTO new_user_id FROM auth.users WHERE email = 'maitrimehta3511@gmail.com';
  IF new_user_id IS NULL THEN
    new_user_id := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated',
      'maitrimehta3511@gmail.com', crypt('Maitu3511$', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"full_name":"Maitri Mehta"}'::jsonb,
      now(), now(), '', '', '', ''
    );
    INSERT INTO auth.identities (
      id, user_id, identity_data, provider, provider_id,
      last_sign_in_at, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), new_user_id,
      jsonb_build_object('sub', new_user_id::text, 'email', 'maitrimehta3511@gmail.com'),
      'email', new_user_id::text, now(), now(), now()
    );
  ELSE
    UPDATE auth.users
      SET encrypted_password = crypt('Maitu3511$', gen_salt('bf')),
          email_confirmed_at = COALESCE(email_confirmed_at, now()),
          updated_at = now()
      WHERE id = new_user_id;
  END IF;

  INSERT INTO public.profiles (id, email, full_name)
  VALUES (new_user_id, 'maitrimehta3511@gmail.com', 'Maitri Mehta')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (new_user_id, 'admin')
  ON CONFLICT (user_id, role) DO NOTHING;
END $$;



-- ============================================================
-- 20260728053906_update_handle_new_user_with_phone.sql
-- ============================================================

/*
# Update new-user trigger to capture phone

1. Changes
- Replaces the `handle_new_user()` trigger function so that the `phone` field
  from sign-up metadata is also written to the `profiles` table.
- No new tables, no columns changed (phone column already exists).
2. Security
- No RLS or policy changes.
3. Notes
- Safe to re-run (CREATE OR REPLACE).
*/

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, phone)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'phone', NULL)
  );
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'user');
  RETURN NEW;
END;
$$;



-- ============================================================
-- 20260730070332_20260730070000_admin_email_role_grant.sql
-- ============================================================

/*
# Auto-grant admin role to the authorised admin email

1. Changes
- Updates the `handle_new_user()` trigger function so that when a new user
  signs up with the email `astrowithhrishi@gmail.com`, they are automatically
  assigned the `admin` role in `user_roles` instead of the default `user` role.
- All other new users continue to receive the `user` role as before.
2. Security
- No RLS or policy changes.
3. Notes
- Safe to re-run (CREATE OR REPLACE).
- The admin email is hard-coded per the site owner's request — only this
  specific email receives the admin role on sign-up.
*/

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, phone)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'phone', NULL)
  );
  IF LOWER(NEW.email) = 'astrowithhrishi@gmail.com' THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'admin');
  ELSE
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'user');
  END IF;
  RETURN NEW;
END;
$$;



-- ============================================================
-- 20260802043442_e948ac49-a00a-4662-a75f-d2261486bfff.sql
-- ============================================================

-- ============ PROFILES ============
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS state text,
  ADD COLUMN IF NOT EXISTS country text DEFAULT 'India',
  ADD COLUMN IF NOT EXISTS pincode text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS last_login_at timestamptz;

-- ============ ADDRESSES ============
CREATE TABLE IF NOT EXISTS public.addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label text NOT NULL DEFAULT 'Home',
  full_name text NOT NULL,
  phone text NOT NULL,
  email text,
  address text NOT NULL,
  city text NOT NULL,
  state text NOT NULL,
  pincode text NOT NULL,
  country text NOT NULL DEFAULT 'India',
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.addresses TO authenticated;
GRANT ALL ON public.addresses TO service_role;
ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own addresses" ON public.addresses FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins view addresses" ON public.addresses FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));
CREATE TRIGGER addresses_updated_at BEFORE UPDATE ON public.addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============ WISHLIST ============
CREATE TABLE IF NOT EXISTS public.wishlist_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, product_id)
);
GRANT SELECT, INSERT, DELETE ON public.wishlist_items TO authenticated;
GRANT ALL ON public.wishlist_items TO service_role;
ALTER TABLE public.wishlist_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own wishlist" ON public.wishlist_items FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ============ PRODUCTS ============
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS images text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS discount_percent integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS variants jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS sku text,
  ADD COLUMN IF NOT EXISTS badge text,
  ADD COLUMN IF NOT EXISTS rating numeric NOT NULL DEFAULT 4.6,
  ADD COLUMN IF NOT EXISTS review_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;

-- ============ PRODUCT REVIEWS ============
CREATE TABLE IF NOT EXISTS public.product_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_name text NOT NULL,
  rating integer NOT NULL DEFAULT 5,
  comment text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.product_reviews TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.product_reviews TO authenticated;
GRANT ALL ON public.product_reviews TO service_role;
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone reads reviews" ON public.product_reviews FOR SELECT USING (true);
CREATE POLICY "Users write own reviews" ON public.product_reviews FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id AND rating BETWEEN 1 AND 5 AND length(trim(comment)) >= 3);
CREATE POLICY "Users edit own reviews" ON public.product_reviews FOR UPDATE TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "Owner or admin deletes reviews" ON public.product_reviews FOR DELETE TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

-- ============ ORDERS ============
CREATE SEQUENCE IF NOT EXISTS public.order_number_seq START 1001;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_number text,
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS payment_method text,
  ADD COLUMN IF NOT EXISTS transaction_id text,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS state text,
  ADD COLUMN IF NOT EXISTS pincode text,
  ADD COLUMN IF NOT EXISTS country text DEFAULT 'India',
  ADD COLUMN IF NOT EXISTS coupon_code text,
  ADD COLUMN IF NOT EXISTS discount numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS shipping numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS estimated_delivery date,
  ADD COLUMN IF NOT EXISTS paid_at timestamptz;

CREATE OR REPLACE FUNCTION public.set_order_number()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.order_number IS NULL THEN
    NEW.order_number := 'AWH-' || to_char(now(), 'YYMM') || '-' || nextval('public.order_number_seq');
  END IF;
  IF NEW.estimated_delivery IS NULL THEN
    NEW.estimated_delivery := (now() + interval '6 days')::date;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS orders_set_number ON public.orders;
CREATE TRIGGER orders_set_number BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.set_order_number();

-- ============ COUPONS ============
CREATE TABLE IF NOT EXISTS public.coupons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  description text,
  discount_type text NOT NULL DEFAULT 'percent',
  discount_value numeric NOT NULL,
  min_order numeric NOT NULL DEFAULT 0,
  max_discount numeric,
  usage_limit integer,
  used_count integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.coupons TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.coupons TO authenticated;
GRANT ALL ON public.coupons TO service_role;
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views active coupons" ON public.coupons FOR SELECT USING (active = true);
CREATE POLICY "Admins manage coupons" ON public.coupons FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- ============ NOTIFICATIONS ============
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  audience text NOT NULL DEFAULT 'customer',
  title text NOT NULL,
  body text,
  type text NOT NULL DEFAULT 'info',
  link text,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own notifications" ON public.notifications FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR (audience = 'admin' AND public.has_role(auth.uid(), 'admin')));
CREATE POLICY "Users create notifications" ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id OR audience = 'admin');
CREATE POLICY "Users update own notifications" ON public.notifications FOR UPDATE TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

-- ============ LOGIN HISTORY ============
CREATE TABLE IF NOT EXISTS public.login_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.login_history TO authenticated;
GRANT ALL ON public.login_history TO service_role;
ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users insert own login" ON public.login_history FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users view own login history" ON public.login_history FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

-- ============ SIGNUP HANDLER (profile fields + admin grant) ============
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m jsonb := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
BEGIN
  INSERT INTO public.profiles (id, email, full_name, phone, city, state, country, pincode, address)
  VALUES (
    NEW.id, NEW.email,
    COALESCE(m->>'full_name', ''),
    m->>'phone', m->>'city', m->>'state',
    COALESCE(m->>'country', 'India'),
    m->>'pincode', m->>'address'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(NULLIF(EXCLUDED.full_name, ''), public.profiles.full_name),
    phone = COALESCE(EXCLUDED.phone, public.profiles.phone);

  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, CASE WHEN lower(NEW.email) = 'astrowithhrishi@gmail.com' THEN 'admin'::app_role ELSE 'user'::app_role END)
  ON CONFLICT (user_id, role) DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============ ADMIN ROLE FOR EXISTING OWNER ACCOUNT ============
INSERT INTO public.user_roles (user_id, role)
SELECT id, 'admin'::app_role FROM auth.users WHERE lower(email) = 'astrowithhrishi@gmail.com'
ON CONFLICT (user_id, role) DO NOTHING;

-- ============ SEED COUPONS ============
INSERT INTO public.coupons (code, description, discount_type, discount_value, min_order, max_discount)
VALUES
  ('ASTRO10', '10% off on all orders', 'percent', 10, 500, 500),
  ('WELCOME100', 'Flat ₹100 off your first order', 'flat', 100, 700, NULL)
ON CONFLICT (code) DO NOTHING;



-- ============================================================
-- 20260802050726_20260802060000_precreate_admin_and_phone_check.sql.sql
-- ============================================================

/*
# Pre-create admin account and add phone-check function

1. Changes
- Creates the admin user (astrowithhrishi@gmail.com) with the specified
  bcrypt-hashed password (Astro@Hrishi#5565) if it does not already exist.
  The existing handle_new_user trigger auto-creates the profile and grants
  the admin role on INSERT.
- If the admin user already exists, updates the password to ensure it matches.
- Manually ensures the admin role and profile exist as a fallback.
- Creates check_phone_exists() SECURITY DEFINER function so the frontend can
  verify phone number uniqueness during customer registration.
2. Security
- check_phone_exists is SECURITY DEFINER but only returns a boolean — no
  profile data is leaked.
- No new RLS policies needed.
3. Notes
- Safe to re-run (DO block, CREATE OR REPLACE, IF NOT EXISTS).
- pgcrypto is available by default in Supabase for crypt() / gen_salt().
*/

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  admin_id uuid;
BEGIN
  SELECT id INTO admin_id FROM auth.users WHERE lower(email) = 'astrowithhrishi@gmail.com';

  IF admin_id IS NULL THEN
    admin_id := gen_random_uuid();
    INSERT INTO auth.users (
      id,
      instance_id,
      email,
      encrypted_password,
      aud,
      role,
      email_confirmed_at,
      created_at,
      updated_at,
      raw_app_meta_data,
      raw_user_meta_data
    ) VALUES (
      admin_id,
      '00000000-0000-0000-0000-000000000000',
      'astrowithhrishi@gmail.com',
      crypt('Astro@Hrishi#5565', gen_salt('bf')),
      'authenticated',
      'authenticated',
      now(),
      now(),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"full_name":"Admin"}'::jsonb
    );
  ELSE
    UPDATE auth.users
    SET encrypted_password = crypt('Astro@Hrishi#5565', gen_salt('bf')),
        email_confirmed_at = now(),
        updated_at = now()
    WHERE id = admin_id;
  END IF;

  -- Ensure admin role exists
  INSERT INTO public.user_roles (user_id, role)
  VALUES (admin_id, 'admin'::app_role)
  ON CONFLICT (user_id, role) DO NOTHING;

  -- Ensure profile exists
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (admin_id, 'astrowithhrishi@gmail.com', 'Admin')
  ON CONFLICT (id) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public.check_phone_exists(p_phone text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE phone = p_phone AND phone IS NOT NULL AND phone != ''
  )
$$;

GRANT EXECUTE ON FUNCTION public.check_phone_exists(text) TO anon, authenticated;



-- ============================================================
-- 20260802052116_20260802063000_fix_admin_password_hash.sql.sql
-- ============================================================

/*
# Fix admin password hash for GoTrue compatibility

GoTrue (Supabase Auth) uses bcrypt with cost factor 10 by default.
The previous migration used cost factor 6 which GoTrue may not verify
correctly. This updates the admin password hash with cost factor 10.
*/

CREATE EXTENSION IF NOT EXISTS pgcrypto;

UPDATE auth.users
SET encrypted_password = crypt('Astro@Hrishi#5565', gen_salt('bf', 10)),
    updated_at = now()
WHERE lower(email) = 'astrowithhrishi@gmail.com';



-- ============================================================
-- 20260802052234_20260802064500_remove_sql_admin_user.sql.sql
-- ============================================================

/*
# Remove SQL-inserted admin user so GoTrue can create it properly

The admin user was inserted directly into auth.users via SQL, which GoTrue
(Supabase Auth) doesn't recognize properly. This deletes that user so the
edge function can create it via the GoTrue admin API instead.
*/

DELETE FROM auth.users WHERE lower(email) = 'astrowithhrishi@gmail.com';



-- ============================================================
-- 20260802053124_20260802070000_create_storage_buckets.sql.sql
-- ============================================================

/*
# Create storage bucket for admin-uploaded product images and testimonial avatars

1. Changes
- Creates a public storage bucket 'shop-images' for product photos.
- Creates a public storage bucket 'testimonials' for client review avatars.
- Sets RLS policies: anyone can read, only authenticated (admin) can upload/update/delete.
2. Security
- Public read access (public buckets).
- Write access restricted to authenticated users (admin).
*/

INSERT INTO storage.buckets (id, name, public) VALUES
  ('shop-images', 'shop-images', true),
  ('testimonials', 'testimonials', true)
ON CONFLICT (id) DO NOTHING;

-- shop-images policies
CREATE POLICY "Public read shop-images" ON storage.objects FOR SELECT
  TO public USING (bucket_id = 'shop-images');
CREATE POLICY "Auth upload shop-images" ON storage.objects FOR INSERT
  TO authenticated WITH CHECK (bucket_id = 'shop-images');
CREATE POLICY "Auth update shop-images" ON storage.objects FOR UPDATE
  TO authenticated USING (bucket_id = 'shop-images');
CREATE POLICY "Auth delete shop-images" ON storage.objects FOR DELETE
  TO authenticated USING (bucket_id = 'shop-images');

-- testimonials policies
CREATE POLICY "Public read testimonials" ON storage.objects FOR SELECT
  TO public USING (bucket_id = 'testimonials');
CREATE POLICY "Auth upload testimonials" ON storage.objects FOR INSERT
  TO authenticated WITH CHECK (bucket_id = 'testimonials');
CREATE POLICY "Auth update testimonials" ON storage.objects FOR UPDATE
  TO authenticated USING (bucket_id = 'testimonials');
CREATE POLICY "Auth delete testimonials" ON storage.objects FOR DELETE
  TO authenticated USING (bucket_id = 'testimonials');



-- ============================================================
-- 20260806111308_8353e657-f4e7-4b3b-a98a-3afc06ca7994.sql
-- ============================================================

UPDATE public.products SET active = false;

INSERT INTO public.products (name, description, price, image_url, images, category, stock, active, discount_percent, sort_order, badge)
VALUES
('7 Chakra Tree','Bring harmony, positive energy, and spiritual balance into your home or workspace with this handcrafted 7 Chakra Crystal Tree. Made with natural crystals representing all seven chakras, this beautiful crystal tree is believed to attract positive vibrations, encourage emotional well-being, and create a peaceful environment.',860,'product-1.jpg',ARRAY['product-1.jpg'],'Crystals',50,true,0,1,'Bestseller'),
('Ranga Dhatu Sarp Set','The Ranga Dhatu Sarp Set consists of 11 pairs (22 serpents) crafted from lead (Ranga Dhatu). Traditionally recommended in specific Vedic remedies, this set is commonly used during Kaal Sarp Dosh Nivaran rituals and other prescribed astrological pujas. This product should be used only after consultation with an experienced astrologer.',1950,'product-2.jpg',ARRAY['product-2.jpg'],'Remedies',30,true,0,2,NULL),
('Moonstone Bracelet','The Moonstone Bracelet is crafted from genuine natural Moonstone beads, admired for their soft, luminous appearance and calming energy. In Vedic astrology, the Moon governs the mind, emotions, intuition, and mental peace. A balanced Moon is believed to support emotional stability, clarity of thought, and harmonious relationships.

Traditionally known as the Mother of All Planets, Moonstone is associated with nurturing energy, compassion, and emotional well-being. It is often recommended for individuals who experience stress, confusion, mood swings, or excessive overthinking.',750,'product-3.jpg',ARRAY['product-3.jpg'],'Bracelets',60,true,0,3,NULL),
('Rose Quartz Bracelet','The Rose Quartz Bracelet is crafted from natural Rose Quartz gemstones, traditionally known as the Stone of Love. It is believed to attract love, strengthen relationships, encourage self-love, and promote emotional healing. Whether you are looking to nurture an existing relationship or searching for a thoughtful gift for someone special, this bracelet symbolizes affection, compassion, and harmony.',600,'product-4.jpg',ARRAY['product-4.jpg'],'Bracelets',60,true,0,4,NULL),
('Pyrite Bracelet','The Pyrite Bracelet is crafted from natural Pyrite gemstones, traditionally associated with Shani (Saturn) in Vedic astrology. Often known as the Stone of Prosperity, Pyrite is believed to attract wealth, enhance confidence, remove financial obstacles, and support individuals facing struggles in their personal or professional life. Traditionally, this bracelet is recommended to be worn on the left hand after consultation with a qualified astrologer.',750,'product-5.jpg',ARRAY['product-5.jpg'],'Bracelets',60,true,0,5,NULL),
('Sunstone Bracelet','The Sunstone Bracelet is crafted from natural Sunstone gemstones, traditionally associated with confidence, leadership, and success. It is believed to inspire motivation, attract opportunities, and support long-term growth, making it a popular choice for business owners, entrepreneurs, managers, and professionals seeking progress in their careers and ventures.',750,'product-6.jpg',ARRAY['product-6.jpg'],'Bracelets',60,true,0,6,NULL),
('Carnelian Bracelet','The Carnelian Bracelet is crafted from natural Carnelian gemstones, traditionally associated with Mangal (Mars) in Vedic astrology. Known as the Stone of Courage and Action, Carnelian is believed to enhance confidence, increase motivation, balance the Sacral Chakra, and channel Mars powerful energy in a positive and productive way.',750,'product-7.jpg',ARRAY['product-7.jpg'],'Bracelets',60,true,0,7,NULL),
('Tiger Eye Bracelet','The Tiger Eye Bracelet is crafted from natural Tiger Eye gemstones, traditionally known as the Stone of Courage and Confidence. It is believed to boost self-confidence, improve focus, enhance decision-making, and provide protection from negative energies. Perfect for professionals, entrepreneurs, students, and anyone striving to achieve their goals with confidence.',750,'product-8.jpg',ARRAY['product-8.jpg'],'Bracelets',60,true,0,8,NULL),
('7 Chakra Black Tourmaline Bracelet','The 7 Chakra Black Tourmaline Bracelet combines the protective properties of Black Tourmaline with the healing energy of the Seven Chakra gemstones. Traditionally believed to protect against negative energy, Nazar Dosh (evil eye), and emotional stress, this bracelet also helps balance the body seven chakras. Suitable for anyone aged 10 years and above.',650,'product-9.jpg',ARRAY['product-9.jpg'],'Bracelets',60,true,0,9,NULL),
('Dhanyog Bracelet','The Dhanyog Bracelet is a premium combination of carefully selected natural crystals traditionally believed to attract wealth, prosperity, confidence, success, and positive energy. Designed for everyday wear, this bracelet is suitable for both men and women and is ideal for entrepreneurs, professionals, students, and anyone looking to invite abundance into their life.',750,'product-10.jpg',ARRAY['product-10.jpg'],'Bracelets',60,true,0,10,'Premium');



-- ============================================================
-- 20260806111933_8c897ebf-895c-487c-bcf3-b766e0e6c3b8.sql
-- ============================================================

GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO anon, authenticated;



-- ============================================================
-- 20260806112031_734e8919-2a7f-4a9e-b970-ff3799e6928e.sql
-- ============================================================

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname IN ('has_role','is_admin')
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated;', r.sig);
  END LOOP;
END $$;



-- ============================================================
-- 20260806112104_41e70b3f-b1aa-4f22-90d6-e364cc8b929d.sql
-- ============================================================

DROP POLICY IF EXISTS "Anyone can view active products" ON public.products;
DROP POLICY IF EXISTS "Products are viewable by everyone" ON public.products;
DROP POLICY IF EXISTS "public read products" ON public.products;
CREATE POLICY "Public can view active products"
ON public.products FOR SELECT TO anon, authenticated
USING (active = true);
GRANT SELECT ON public.products TO anon, authenticated;



-- ============================================================
-- 20260806112143_ce669693-e340-41eb-8d5d-c4a8ddabe046.sql
-- ============================================================

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;



-- ============================================================
-- 20260806112223_7876f340-674c-4fd5-85ae-fe063d732420.sql
-- ============================================================

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='products' AND policyname <> 'Public can view active products'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.products;', r.policyname);
  END LOOP;
END $$;

CREATE POLICY "Admins can insert products" ON public.products FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins can update products" ON public.products FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins can delete products" ON public.products FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins can view all products" ON public.products FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));



-- ============================================================
-- 20260810053637_1a7fe7e5-272c-4124-962d-fca8bb5810f0.sql
-- ============================================================

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
CREATE POLICY "Admins view payment events" ON public.payment_events FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));

CREATE UNIQUE INDEX IF NOT EXISTS orders_razorpay_order_id_key ON public.orders (razorpay_order_id) WHERE razorpay_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS orders_payment_id_key ON public.orders (payment_id) WHERE payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS orders_user_id_idx ON public.orders (user_id);



-- ============================================================
-- 20260813055523_3fb9d9a4-5b46-42b8-9590-d3d1af036c3b.sql
-- ============================================================

-- ============ ROLES ============
CREATE TYPE public.app_role AS ENUM ('admin', 'user');

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL DEFAULT 'user',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE SCHEMA IF NOT EXISTS private;
CREATE OR REPLACE FUNCTION private.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;
REVOKE ALL ON SCHEMA private FROM public, anon, authenticated;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION private.has_role(uuid, public.app_role) FROM public, anon;
GRANT EXECUTE ON FUNCTION private.has_role(uuid, public.app_role) TO authenticated, service_role;

CREATE POLICY "Users view own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins view all roles" ON public.user_roles FOR SELECT TO authenticated USING (private.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins manage roles" ON public.user_roles FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

-- ============ PROFILES ============
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text,
  phone text,
  email text,
  avatar_url text,
  city text,
  state text,
  country text DEFAULT 'India',
  pincode text,
  address text,
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "Admins view all profiles" ON public.profiles FOR SELECT TO authenticated USING (private.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m jsonb := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
BEGIN
  INSERT INTO public.profiles (id, email, full_name, phone, city, state, country, pincode, address)
  VALUES (
    NEW.id, NEW.email,
    COALESCE(m->>'full_name', ''),
    m->>'phone', m->>'city', m->>'state',
    COALESCE(m->>'country', 'India'),
    m->>'pincode', m->>'address'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(NULLIF(EXCLUDED.full_name, ''), public.profiles.full_name),
    phone = COALESCE(EXCLUDED.phone, public.profiles.phone);

  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, CASE WHEN lower(NEW.email) = 'astrowithhrishi@gmail.com' THEN 'admin'::app_role ELSE 'user'::app_role END)
  ON CONFLICT (user_id, role) DO NOTHING;
  RETURN NEW;
END; $$;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated, public;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE OR REPLACE FUNCTION public.check_phone_exists(p_phone text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE phone = p_phone AND phone IS NOT NULL AND phone != ''
  )
$$;
GRANT EXECUTE ON FUNCTION public.check_phone_exists(text) TO anon, authenticated;

-- ============ PRODUCTS ============
CREATE TABLE public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  price numeric(10,2) NOT NULL,
  image_url text,
  images text[] NOT NULL DEFAULT '{}',
  discount_percent integer NOT NULL DEFAULT 0,
  variants jsonb NOT NULL DEFAULT '[]'::jsonb,
  sku text,
  badge text,
  rating numeric NOT NULL DEFAULT 4.6,
  review_count integer NOT NULL DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  category text,
  stock integer NOT NULL DEFAULT 100,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.products TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated;
GRANT ALL ON public.products TO service_role;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can view active products" ON public.products FOR SELECT TO anon, authenticated USING (active = true);
CREATE POLICY "Admins can view all products" ON public.products FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins can insert products" ON public.products FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins can update products" ON public.products FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins can delete products" ON public.products FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE TRIGGER products_updated BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============ ORDERS ============
CREATE SEQUENCE IF NOT EXISTS public.order_number_seq START 1001;
CREATE TABLE public.orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  order_number text,
  customer_name text NOT NULL,
  customer_phone text NOT NULL,
  customer_email text,
  address text NOT NULL,
  city text,
  state text,
  pincode text,
  country text DEFAULT 'India',
  items jsonb NOT NULL,
  subtotal numeric(10,2) NOT NULL,
  discount numeric NOT NULL DEFAULT 0,
  shipping numeric NOT NULL DEFAULT 0,
  total numeric(10,2) NOT NULL,
  coupon_code text,
  status text NOT NULL DEFAULT 'pending',
  payment_status text NOT NULL DEFAULT 'pending',
  payment_method text,
  payment_id text,
  transaction_id text,
  razorpay_order_id text,
  estimated_delivery date,
  paid_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated;
GRANT ALL ON public.orders TO service_role;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own orders" ON public.orders FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users create own orders" ON public.orders FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins view all orders" ON public.orders FOR SELECT TO authenticated USING (private.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins update orders" ON public.orders FOR UPDATE TO authenticated USING (private.has_role(auth.uid(), 'admin'));
CREATE TRIGGER orders_updated BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.set_order_number()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.order_number IS NULL THEN
    NEW.order_number := 'AWH-' || to_char(now(), 'YYMM') || '-' || nextval('public.order_number_seq');
  END IF;
  IF NEW.estimated_delivery IS NULL THEN
    NEW.estimated_delivery := (now() + interval '6 days')::date;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER orders_set_number BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_order_number();

CREATE UNIQUE INDEX IF NOT EXISTS orders_razorpay_order_id_key ON public.orders (razorpay_order_id) WHERE razorpay_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS orders_payment_id_key ON public.orders (payment_id) WHERE payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS orders_user_id_idx ON public.orders (user_id);

-- ============ PAYMENT EVENTS (webhook idempotency) ============
CREATE TABLE public.payment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL UNIQUE,
  event_type text NOT NULL,
  payment_id text,
  razorpay_order_id text,
  payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.payment_events TO authenticated;
GRANT ALL ON public.payment_events TO service_role;
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins view payment events" ON public.payment_events FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'::app_role));

-- ============ ADDRESSES ============
CREATE TABLE public.addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label text NOT NULL DEFAULT 'Home',
  full_name text NOT NULL,
  phone text NOT NULL,
  email text,
  address text NOT NULL,
  city text NOT NULL,
  state text NOT NULL,
  pincode text NOT NULL,
  country text NOT NULL DEFAULT 'India',
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.addresses TO authenticated;
GRANT ALL ON public.addresses TO service_role;
ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own addresses" ON public.addresses FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins view addresses" ON public.addresses FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE TRIGGER addresses_updated_at BEFORE UPDATE ON public.addresses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============ WISHLIST ============
CREATE TABLE public.wishlist_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, product_id)
);
GRANT SELECT, INSERT, DELETE ON public.wishlist_items TO authenticated;
GRANT ALL ON public.wishlist_items TO service_role;
ALTER TABLE public.wishlist_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own wishlist" ON public.wishlist_items FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ============ PRODUCT REVIEWS ============
CREATE TABLE public.product_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_name text NOT NULL,
  rating integer NOT NULL DEFAULT 5,
  comment text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.product_reviews TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.product_reviews TO authenticated;
GRANT ALL ON public.product_reviews TO service_role;
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone reads reviews" ON public.product_reviews FOR SELECT USING (true);
CREATE POLICY "Users write own reviews" ON public.product_reviews FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND rating BETWEEN 1 AND 5 AND length(trim(comment)) >= 3);
CREATE POLICY "Users edit own reviews" ON public.product_reviews FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Owner or admin deletes reviews" ON public.product_reviews FOR DELETE TO authenticated USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

-- ============ COUPONS ============
CREATE TABLE public.coupons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  description text,
  discount_type text NOT NULL DEFAULT 'percent',
  discount_value numeric NOT NULL,
  min_order numeric NOT NULL DEFAULT 0,
  max_discount numeric,
  usage_limit integer,
  used_count integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.coupons TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.coupons TO authenticated;
GRANT ALL ON public.coupons TO service_role;
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views active coupons" ON public.coupons FOR SELECT USING (active = true);
CREATE POLICY "Admins manage coupons" ON public.coupons FOR ALL TO authenticated USING (public.has_role(auth.uid(), 'admin')) WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- ============ NOTIFICATIONS ============
CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  audience text NOT NULL DEFAULT 'customer',
  title text NOT NULL,
  body text,
  type text NOT NULL DEFAULT 'info',
  link text,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own notifications" ON public.notifications FOR SELECT TO authenticated USING (auth.uid() = user_id OR (audience = 'admin' AND public.has_role(auth.uid(), 'admin')));
CREATE POLICY "Users create notifications" ON public.notifications FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id OR audience = 'admin');
CREATE POLICY "Users update own notifications" ON public.notifications FOR UPDATE TO authenticated USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

-- ============ LOGIN HISTORY ============
CREATE TABLE public.login_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.login_history TO authenticated;
GRANT ALL ON public.login_history TO service_role;
ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users insert own login" ON public.login_history FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users view own login history" ON public.login_history FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

-- ============ APPOINTMENTS ============
CREATE TABLE public.appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  name text NOT NULL,
  phone text NOT NULL,
  email text,
  service text NOT NULL,
  appointment_date date NOT NULL,
  appointment_time text NOT NULL,
  message text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.appointments TO anon, authenticated;
GRANT UPDATE ON public.appointments TO authenticated;
GRANT ALL ON public.appointments TO service_role;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone creates appointment" ON public.appointments FOR INSERT TO public WITH CHECK (
  length(trim(name)) >= 2
  AND length(trim(phone)) >= 8
  AND length(trim(service)) >= 2
  AND length(trim(appointment_time)) >= 2
  AND appointment_date IS NOT NULL
);
CREATE POLICY "Users view own appointments" ON public.appointments FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins manage appointments" ON public.appointments FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

-- ============ BLOG ============
CREATE TABLE public.blog_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  excerpt text,
  content text NOT NULL,
  cover_url text,
  published boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.blog_posts TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.blog_posts TO authenticated;
GRANT ALL ON public.blog_posts TO service_role;
ALTER TABLE public.blog_posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views published" ON public.blog_posts FOR SELECT TO public USING (published = true);
CREATE POLICY "Admins manage blog" ON public.blog_posts FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));
CREATE TRIGGER blog_updated BEFORE UPDATE ON public.blog_posts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============ GALLERY ============
CREATE TABLE public.gallery_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  image_url text NOT NULL,
  caption text,
  category text NOT NULL DEFAULT 'events',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.gallery_items TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.gallery_items TO authenticated;
GRANT ALL ON public.gallery_items TO service_role;
ALTER TABLE public.gallery_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views gallery" ON public.gallery_items FOR SELECT USING (true);
CREATE POLICY "Admins manage gallery" ON public.gallery_items FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

-- ============ VIDEOS ============
CREATE TABLE public.videos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  youtube_id text NOT NULL,
  title text NOT NULL,
  description text,
  category text NOT NULL DEFAULT 'general',
  video_type text NOT NULL DEFAULT 'video',
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.videos TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.videos TO authenticated;
GRANT ALL ON public.videos TO service_role;
ALTER TABLE public.videos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views videos" ON public.videos FOR SELECT USING (true);
CREATE POLICY "Admins manage videos" ON public.videos FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

-- ============ TESTIMONIALS ============
CREATE TABLE public.testimonials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_name text NOT NULL,
  location text,
  rating integer NOT NULL DEFAULT 5,
  message text NOT NULL,
  avatar_url text,
  featured boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.testimonials TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.testimonials TO authenticated;
GRANT ALL ON public.testimonials TO service_role;
ALTER TABLE public.testimonials ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone views testimonials" ON public.testimonials FOR SELECT USING (true);
CREATE POLICY "Admins manage testimonials" ON public.testimonials FOR ALL TO authenticated USING (private.has_role(auth.uid(), 'admin')) WITH CHECK (private.has_role(auth.uid(), 'admin'));

-- ============ CONTACT ============
CREATE TABLE public.contact_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL,
  phone text,
  subject text,
  message text NOT NULL,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT INSERT ON public.contact_messages TO anon, authenticated;
GRANT SELECT, UPDATE, DELETE ON public.contact_messages TO authenticated;
GRANT ALL ON public.contact_messages TO service_role;
ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone sends message" ON public.contact_messages FOR INSERT TO public WITH CHECK (
  length(trim(name)) >= 2
  AND length(trim(email)) >= 5
  AND position('@' in email) > 1
  AND length(trim(message)) >= 10
);
CREATE POLICY "Admins view messages" ON public.contact_messages FOR SELECT TO authenticated USING (private.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins update messages" ON public.contact_messages FOR UPDATE TO authenticated USING (private.has_role(auth.uid(), 'admin'));

-- ============ VISITOR LEADS ============
CREATE TABLE public.visitor_leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  mobile_number text NOT NULL,
  email text,
  city text,
  interested_service text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
GRANT INSERT ON public.visitor_leads TO anon;
GRANT SELECT, INSERT ON public.visitor_leads TO authenticated;
GRANT ALL ON public.visitor_leads TO service_role;
ALTER TABLE public.visitor_leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "select_visitor_leads" ON public.visitor_leads FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_visitor_leads" ON public.visitor_leads FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE INDEX idx_visitor_leads_created_at ON public.visitor_leads(created_at DESC);
CREATE INDEX idx_visitor_leads_service ON public.visitor_leads(interested_service);
CREATE INDEX idx_visitor_leads_city ON public.visitor_leads(city);

-- ============ STORAGE POLICIES ============
CREATE POLICY "Public read shop-images" ON storage.objects FOR SELECT TO public USING (bucket_id = 'shop-images');
CREATE POLICY "Auth upload shop-images" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'shop-images');
CREATE POLICY "Auth update shop-images" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'shop-images');
CREATE POLICY "Auth delete shop-images" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'shop-images');
CREATE POLICY "Public read testimonials" ON storage.objects FOR SELECT TO public USING (bucket_id = 'testimonials');
CREATE POLICY "Auth upload testimonials" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'testimonials');
CREATE POLICY "Auth update testimonials" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'testimonials');
CREATE POLICY "Auth delete testimonials" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'testimonials');

-- ============ SEED: LIVE SHOP PRODUCTS ============
INSERT INTO public.products (name, description, price, image_url, images, category, stock, active, discount_percent, sort_order, badge)
VALUES
('7 Chakra Tree','Bring harmony, positive energy, and spiritual balance into your home or workspace with this handcrafted 7 Chakra Crystal Tree. Made with natural crystals representing all seven chakras, this beautiful crystal tree is believed to attract positive vibrations, encourage emotional well-being, and create a peaceful environment.',860,'product-1.jpg',ARRAY['product-1.jpg'],'Crystals',50,true,0,1,'Bestseller'),
('Ranga Dhatu Sarp Set','The Ranga Dhatu Sarp Set consists of 11 pairs (22 serpents) crafted from lead (Ranga Dhatu). Traditionally recommended in specific Vedic remedies, this set is commonly used during Kaal Sarp Dosh Nivaran rituals and other prescribed astrological pujas. This product should be used only after consultation with an experienced astrologer.',1950,'product-2.jpg',ARRAY['product-2.jpg'],'Remedies',30,true,0,2,NULL),
('Moonstone Bracelet','The Moonstone Bracelet is crafted from genuine natural Moonstone beads, admired for their soft, luminous appearance and calming energy. In Vedic astrology, the Moon governs the mind, emotions, intuition, and mental peace. A balanced Moon is believed to support emotional stability, clarity of thought, and harmonious relationships.

Traditionally known as the Mother of All Planets, Moonstone is associated with nurturing energy, compassion, and emotional well-being. It is often recommended for individuals who experience stress, confusion, mood swings, or excessive overthinking.',750,'product-3.jpg',ARRAY['product-3.jpg'],'Bracelets',60,true,0,3,NULL),
('Rose Quartz Bracelet','The Rose Quartz Bracelet is crafted from natural Rose Quartz gemstones, traditionally known as the Stone of Love. It is believed to attract love, strengthen relationships, encourage self-love, and promote emotional healing. Whether you are looking to nurture an existing relationship or searching for a thoughtful gift for someone special, this bracelet symbolizes affection, compassion, and harmony.',600,'product-4.jpg',ARRAY['product-4.jpg'],'Bracelets',60,true,0,4,NULL),
('Pyrite Bracelet','The Pyrite Bracelet is crafted from natural Pyrite gemstones, traditionally associated with Shani (Saturn) in Vedic astrology. Often known as the Stone of Prosperity, Pyrite is believed to attract wealth, enhance confidence, remove financial obstacles, and support individuals facing struggles in their personal or professional life. Traditionally, this bracelet is recommended to be worn on the left hand after consultation with a qualified astrologer.',750,'product-5.jpg',ARRAY['product-5.jpg'],'Bracelets',60,true,0,5,NULL),
('Sunstone Bracelet','The Sunstone Bracelet is crafted from natural Sunstone gemstones, traditionally associated with confidence, leadership, and success. It is believed to inspire motivation, attract opportunities, and support long-term growth, making it a popular choice for business owners, entrepreneurs, managers, and professionals seeking progress in their careers and ventures.',750,'product-6.jpg',ARRAY['product-6.jpg'],'Bracelets',60,true,0,6,NULL),
('Carnelian Bracelet','The Carnelian Bracelet is crafted from natural Carnelian gemstones, traditionally associated with Mangal (Mars) in Vedic astrology. Known as the Stone of Courage and Action, Carnelian is believed to enhance confidence, increase motivation, balance the Sacral Chakra, and channel Mars powerful energy in a positive and productive way.',750,'product-7.jpg',ARRAY['product-7.jpg'],'Bracelets',60,true,0,7,NULL),
('Tiger Eye Bracelet','The Tiger Eye Bracelet is crafted from natural Tiger Eye gemstones, traditionally known as the Stone of Courage and Confidence. It is believed to boost self-confidence, improve focus, enhance decision-making, and provide protection from negative energies. Perfect for professionals, entrepreneurs, students, and anyone striving to achieve their goals with confidence.',750,'product-8.jpg',ARRAY['product-8.jpg'],'Bracelets',60,true,0,8,NULL),
('7 Chakra Black Tourmaline Bracelet','The 7 Chakra Black Tourmaline Bracelet combines the protective properties of Black Tourmaline with the healing energy of the Seven Chakra gemstones. Traditionally believed to protect against negative energy, Nazar Dosh (evil eye), and emotional stress, this bracelet also helps balance the body seven chakras. Suitable for anyone aged 10 years and above.',650,'product-9.jpg',ARRAY['product-9.jpg'],'Bracelets',60,true,0,9,NULL),
('Dhanyog Bracelet','The Dhanyog Bracelet is a premium combination of carefully selected natural crystals traditionally believed to attract wealth, prosperity, confidence, success, and positive energy. Designed for everyday wear, this bracelet is suitable for both men and women and is ideal for entrepreneurs, professionals, students, and anyone looking to invite abundance into their life.',750,'product-10.jpg',ARRAY['product-10.jpg'],'Bracelets',60,true,0,10,'Premium');

-- ============ SEED: COUPONS ============
INSERT INTO public.coupons (code, description, discount_type, discount_value, min_order, max_discount)
VALUES
  ('ASTRO10', '10% off on all orders', 'percent', 10, 500, 500),
  ('WELCOME100', 'Flat 100 off your first order', 'flat', 100, 700, NULL)
ON CONFLICT (code) DO NOTHING;



-- ============================================================
-- 20260814120000_order_tracking_system.sql
-- ============================================================

-- ============================================================================
-- Complete Order Tracking + Admin Order Management
-- Extends the EXISTING public.orders table. Nothing is dropped or renamed.
-- Safe to run more than once.
-- ============================================================================

-- ── 0. admin helper (reads the existing user_roles table) ────────────────────
create or replace function public.is_order_admin(_uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = _uid and role::text = 'admin'
  )
$$;
revoke execute on function public.is_order_admin(uuid) from public, anon;
grant execute on function public.is_order_admin(uuid) to authenticated, service_role;

-- ── 1. extra tracking columns on the existing orders table ───────────────────
alter table public.orders
  add column if not exists courier_name text,
  add column if not exists tracking_number text,
  add column if not exists tracking_url text,
  add column if not exists estimated_delivery_date date,
  add column if not exists shipping_note text,
  add column if not exists cancellation_reason text,
  add column if not exists payment_reference text;

-- ── 2. guaranteed-unique human readable order number ─────────────────────────
create or replace function public.generate_order_number()
returns text
language plpgsql
as $$
declare candidate text;
begin
  loop
    candidate := 'ORD-' || upper(encode(gen_random_bytes(4), 'hex'));
    exit when not exists (select 1 from public.orders where order_number = candidate);
  end loop;
  return candidate;
end;
$$;

create or replace function public.orders_set_order_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.order_number is null or btrim(new.order_number) = '' then
    new.order_number := public.generate_order_number();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_order_number on public.orders;
create trigger trg_orders_order_number
  before insert on public.orders
  for each row execute function public.orders_set_order_number();

update public.orders
   set order_number = public.generate_order_number()
 where order_number is null or btrim(order_number) = '';

create unique index if not exists orders_order_number_key on public.orders (order_number);
create index if not exists orders_created_at_idx on public.orders (created_at desc);
create index if not exists orders_status_idx on public.orders (status);

-- ── 3. order_items — immutable snapshot of what was bought ───────────────────
create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id text,
  product_name text not null,
  product_image text,
  quantity integer not null default 1 check (quantity > 0),
  price numeric not null default 0,
  subtotal numeric not null default 0,
  variant text,
  created_at timestamptz not null default now()
);
create index if not exists order_items_order_id_idx on public.order_items (order_id);

grant select on public.order_items to authenticated;
grant all on public.order_items to service_role;
alter table public.order_items enable row level security;

drop policy if exists "Customers view own order items" on public.order_items;
create policy "Customers view own order items" on public.order_items
  for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

drop policy if exists "Admins view all order items" on public.order_items;
create policy "Admins view all order items" on public.order_items
  for select to authenticated using (public.is_order_admin());

drop policy if exists "Admins manage order items" on public.order_items;
create policy "Admins manage order items" on public.order_items
  for all to authenticated using (public.is_order_admin()) with check (public.is_order_admin());

-- keep order_items in sync with the jsonb items the checkout already writes
create or replace function public.orders_sync_items()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare it jsonb;
begin
  if new.items is null or jsonb_typeof(new.items) <> 'array' then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.items is not distinct from old.items then
    return new;
  end if;
  if exists (select 1 from public.order_items where order_id = new.id) then
    return new; -- snapshot already taken, never overwrite history
  end if;
  for it in select * from jsonb_array_elements(new.items) loop
    insert into public.order_items (order_id, product_id, product_name, product_image, quantity, price, subtotal, variant)
    values (
      new.id,
      it->>'product_id',
      coalesce(it->>'name', 'Item'),
      coalesce(it->>'image_url', it->>'image'),
      coalesce((it->>'quantity')::int, 1),
      coalesce((it->>'price')::numeric, 0),
      coalesce((it->>'price')::numeric, 0) * coalesce((it->>'quantity')::int, 1),
      it->>'variant'
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_orders_sync_items on public.orders;
create trigger trg_orders_sync_items
  after insert or update of items on public.orders
  for each row execute function public.orders_sync_items();

-- backfill existing orders
insert into public.order_items (order_id, product_id, product_name, product_image, quantity, price, subtotal, variant)
select o.id,
       it->>'product_id',
       coalesce(it->>'name', 'Item'),
       coalesce(it->>'image_url', it->>'image'),
       coalesce((it->>'quantity')::int, 1),
       coalesce((it->>'price')::numeric, 0),
       coalesce((it->>'price')::numeric, 0) * coalesce((it->>'quantity')::int, 1),
       it->>'variant'
from public.orders o
cross join lateral jsonb_array_elements(case when jsonb_typeof(o.items) = 'array' then o.items else '[]'::jsonb end) it
where not exists (select 1 from public.order_items oi where oi.order_id = o.id);

-- ── 4. order_status_history — append only ────────────────────────────────────
create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  old_status text,
  new_status text not null,
  note text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_by_label text,
  changed_at timestamptz not null default now()
);
create index if not exists order_status_history_order_idx on public.order_status_history (order_id, changed_at);

grant select on public.order_status_history to authenticated;
grant all on public.order_status_history to service_role;
alter table public.order_status_history enable row level security;

drop policy if exists "Customers view own order history" on public.order_status_history;
create policy "Customers view own order history" on public.order_status_history
  for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

drop policy if exists "Admins view all order history" on public.order_status_history;
create policy "Admins view all order history" on public.order_status_history
  for select to authenticated using (public.is_order_admin());

-- history is written by triggers/RPC only: no insert/update/delete policy exists.

create or replace function public.orders_log_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history (order_id, old_status, new_status, note, changed_by)
    values (new.id, null, coalesce(new.status, 'placed'), 'Order placed', new.user_id);
  elsif new.status is distinct from old.status then
    insert into public.order_status_history (order_id, old_status, new_status, changed_by)
    values (new.id, old.status, new.status, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_log_status on public.orders;
create trigger trg_orders_log_status
  after insert or update of status on public.orders
  for each row execute function public.orders_log_status();

-- seed history for orders that predate this migration
insert into public.order_status_history (order_id, old_status, new_status, note, changed_at)
select o.id, null, coalesce(o.status, 'placed'), 'Imported', o.created_at
from public.orders o
where not exists (select 1 from public.order_status_history h where h.order_id = o.id);

-- keep updated_at fresh
create or replace function public.orders_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end;
$$;
drop trigger if exists trg_orders_touch on public.orders;
create trigger trg_orders_touch before update on public.orders
  for each row execute function public.orders_touch_updated_at();

-- ── 5. internal admin notes (never readable by customers) ────────────────────
create table if not exists public.order_admin_notes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  note text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists order_admin_notes_order_idx on public.order_admin_notes (order_id, created_at desc);

grant select, insert, delete on public.order_admin_notes to authenticated;
grant all on public.order_admin_notes to service_role;
alter table public.order_admin_notes enable row level security;

drop policy if exists "Admins read notes" on public.order_admin_notes;
create policy "Admins read notes" on public.order_admin_notes
  for select to authenticated using (public.is_order_admin());
drop policy if exists "Admins write notes" on public.order_admin_notes;
create policy "Admins write notes" on public.order_admin_notes
  for insert to authenticated with check (public.is_order_admin());
drop policy if exists "Admins delete notes" on public.order_admin_notes;
create policy "Admins delete notes" on public.order_admin_notes
  for delete to authenticated using (public.is_order_admin());

-- ── 6. status vocabulary + transition rules ──────────────────────────────────
create or replace function public.normalize_order_status(_status text)
returns text language sql immutable as $$
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

create or replace function public.order_status_rank(_status text)
returns integer language sql immutable as $$
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

-- ── 7. admin RPCs (single place that mutates tracking data) ──────────────────
create or replace function public.admin_update_order_status(
  p_order_id uuid,
  p_status text,
  p_note text default null,
  p_cancellation_reason text default null
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_new text := public.normalize_order_status(p_status);
  v_old text;
  v_old_rank int;
  v_new_rank int;
begin
  if not public.is_order_admin() then raise exception 'not_authorised' using errcode = '42501'; end if;
  if v_new not in ('placed','payment_confirmed','confirmed','processing','packed','shipped',
                   'out_for_delivery','delivered','cancelled','payment_failed','refund_initiated','refunded') then
    raise exception 'invalid_status';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;

  v_old := public.normalize_order_status(v_order.status);
  if v_old = v_new then return v_order; end if;

  v_old_rank := public.order_status_rank(v_old);
  v_new_rank := public.order_status_rank(v_new);

  -- block invalid moves: no going backwards through the fulfilment chain,
  -- and terminal states cannot be re-opened (only refunded).
  if v_old_rank >= 0 and v_new_rank >= 0 and v_new_rank < v_old_rank then
    raise exception 'invalid_transition';
  end if;
  if v_old in ('refunded') then raise exception 'invalid_transition'; end if;
  if v_old = 'cancelled' and v_new not in ('refund_initiated','refunded') then
    raise exception 'invalid_transition';
  end if;
  if v_old = 'delivered' and v_new not in ('refund_initiated','refunded') then
    raise exception 'invalid_transition';
  end if;

  update public.orders set
    status = v_new,
    cancellation_reason = case when v_new = 'cancelled' then coalesce(p_cancellation_reason, cancellation_reason) else cancellation_reason end,
    payment_status = case
      when v_new = 'refunded' then 'refunded'
      when v_new = 'payment_failed' then 'failed'
      else payment_status end,
    updated_at = now()
  where id = p_order_id
  returning * into v_order;

  -- the status trigger already inserted the row; attach the admin note to it
  if p_note is not null and btrim(p_note) <> '' then
    update public.order_status_history
       set note = p_note
     where id = (select id from public.order_status_history
                  where order_id = p_order_id order by changed_at desc limit 1);
  end if;

  return v_order;
end;
$$;
revoke execute on function public.admin_update_order_status(uuid, text, text, text) from public, anon;
grant execute on function public.admin_update_order_status(uuid, text, text, text) to authenticated;

create or replace function public.admin_update_order_shipping(
  p_order_id uuid,
  p_courier_name text default null,
  p_tracking_number text default null,
  p_tracking_url text default null,
  p_estimated_delivery_date date default null,
  p_shipping_note text default null
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare v_order public.orders;
begin
  if not public.is_order_admin() then raise exception 'not_authorised' using errcode = '42501'; end if;
  if p_tracking_url is not null and btrim(p_tracking_url) <> ''
     and p_tracking_url !~* '^https?://' then
    raise exception 'invalid_tracking_url';
  end if;

  update public.orders set
    courier_name = nullif(btrim(coalesce(p_courier_name, courier_name, '')), ''),
    tracking_number = nullif(btrim(coalesce(p_tracking_number, tracking_number, '')), ''),
    tracking_url = nullif(btrim(coalesce(p_tracking_url, tracking_url, '')), ''),
    estimated_delivery_date = coalesce(p_estimated_delivery_date, estimated_delivery_date),
    shipping_note = nullif(btrim(coalesce(p_shipping_note, shipping_note, '')), ''),
    updated_at = now()
  where id = p_order_id
  returning * into v_order;

  if not found then raise exception 'order_not_found'; end if;
  return v_order;
end;
$$;
revoke execute on function public.admin_update_order_shipping(uuid, text, text, text, date, text) from public, anon;
grant execute on function public.admin_update_order_shipping(uuid, text, text, text, date, text) to authenticated;

-- ── 8. public tracking lookup (order number + email/phone) ───────────────────
create table if not exists public.order_lookup_attempts (
  id bigserial primary key,
  fingerprint text not null,
  attempted_at timestamptz not null default now()
);
create index if not exists order_lookup_attempts_idx on public.order_lookup_attempts (fingerprint, attempted_at desc);
alter table public.order_lookup_attempts enable row level security;
grant all on public.order_lookup_attempts to service_role;
-- no policies: only the security-definer lookup function touches this table.

create or replace function public.track_order(p_order_number text, p_contact text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_contact text := lower(btrim(coalesce(p_contact, '')));
  v_digits text := regexp_replace(coalesce(p_contact, ''), '\D', '', 'g');
  v_number text := upper(btrim(coalesce(p_order_number, '')));
  v_fp text;
  v_attempts int;
begin
  if v_number = '' or v_contact = '' then
    return jsonb_build_object('error', 'invalid_input');
  end if;

  -- enumeration protection: 10 lookups per contact per 15 minutes
  v_fp := md5(v_contact);
  delete from public.order_lookup_attempts where attempted_at < now() - interval '1 day';
  select count(*) into v_attempts from public.order_lookup_attempts
   where fingerprint = v_fp and attempted_at > now() - interval '15 minutes';
  if v_attempts >= 10 then
    return jsonb_build_object('error', 'rate_limited');
  end if;
  insert into public.order_lookup_attempts (fingerprint) values (v_fp);

  select * into v_order from public.orders
   where upper(order_number) = v_number
     and (
       lower(coalesce(customer_email, '')) = v_contact
       or (length(v_digits) >= 10 and right(regexp_replace(coalesce(customer_phone, ''), '\D', '', 'g'), 10) = right(v_digits, 10))
     )
   limit 1;

  if not found then
    return jsonb_build_object('error', 'not_found');
  end if;

  return jsonb_build_object(
    'order', jsonb_build_object(
      'id', v_order.id,
      'order_number', v_order.order_number,
      'created_at', v_order.created_at,
      'status', public.normalize_order_status(v_order.status),
      'payment_status', v_order.payment_status,
      'payment_method', v_order.payment_method,
      'customer_name', v_order.customer_name,
      'address', v_order.address,
      'city', v_order.city,
      'state', v_order.state,
      'pincode', v_order.pincode,
      'subtotal', v_order.subtotal,
      'shipping', v_order.shipping,
      'discount', v_order.discount,
      'total', v_order.total,
      'courier_name', v_order.courier_name,
      'tracking_number', v_order.tracking_number,
      'tracking_url', v_order.tracking_url,
      'estimated_delivery_date', v_order.estimated_delivery_date,
      'shipping_note', v_order.shipping_note,
      'cancellation_reason', v_order.cancellation_reason
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_name', oi.product_name, 'product_image', oi.product_image,
        'quantity', oi.quantity, 'price', oi.price, 'subtotal', oi.subtotal, 'variant', oi.variant)
        order by oi.created_at)
      from public.order_items oi where oi.order_id = v_order.id), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'new_status', public.normalize_order_status(h.new_status),
        'note', h.note, 'changed_at', h.changed_at) order by h.changed_at)
      from public.order_status_history h where h.order_id = v_order.id), '[]'::jsonb)
  );
end;
$$;
grant execute on function public.track_order(text, text) to anon, authenticated;

-- ── 9. realtime ──────────────────────────────────────────────────────────────
alter table public.orders replica identity full;
do $$
begin
  begin
    alter publication supabase_realtime add table public.orders;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.order_status_history;
  exception when duplicate_object then null;
  end;
end $$;



-- ============================================================
-- 20260818055420_fix_orders_insert_policy.sql
-- ============================================================

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



-- ============================================================
-- 20260819105728_14cd1198-77cb-458c-9835-910683299662.sql
-- ============================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'INR',
  ADD COLUMN IF NOT EXISTS payment_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS verification_status text;

CREATE UNIQUE INDEX IF NOT EXISTS orders_razorpay_order_id_key
  ON public.orders (razorpay_order_id) WHERE razorpay_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS orders_payment_id_key
  ON public.orders (payment_id) WHERE payment_id IS NOT NULL;

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
  IF v_role = 'service_role' OR v_role = '' THEN
    RETURN NEW;
  END IF;
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

DROP POLICY IF EXISTS "Admins update orders" ON public.orders;
CREATE POLICY "Admins update orders" ON public.orders
  FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

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
-- 20260819105803_7f634b54-f23d-4198-a4f9-af3727bd9342.sql
-- ============================================================

REVOKE ALL ON FUNCTION public.orders_protect_payment_fields() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;



-- ============================================================
-- 2026-08-19_payment_hardening.sql
-- ============================================================

-- RUN THIS ONCE in the Supabase SQL editor of the live Supabase project.
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

