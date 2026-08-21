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
