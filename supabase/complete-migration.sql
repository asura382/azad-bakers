-- AZAD BAKERS — FINAL CONSOLIDATED DATABASE MIGRATION
-- Run this ONE script in Supabase SQL Editor.
-- It reconciles the earlier schema, order system, security policies, storage, and realtime.
-- Safe to re-run.
--
-- After this succeeds, do NOT run older schema/RPC scripts again.

create extension if not exists pgcrypto;

-- Core tables ---------------------------------------------------------------

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 120),
  category text not null default 'Bakery' check (char_length(category) between 1 and 60),
  description text not null default '',
  price numeric(10,2) not null check (price >= 0),
  image_url text not null default '',
  badge text not null default '',
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.store_settings (
  id boolean primary key default true check (id),
  bakery_name text not null default 'Azad Bakers',
  phone text not null default '+91 87087 37685',
  whatsapp text not null default '918708737685',
  maps_url text not null default '',
  address text not null default '',
  hours text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null check (char_length(customer_name) between 1 and 120),
  customer_phone text not null check (char_length(customer_phone) between 5 and 30),
  items jsonb not null check (jsonb_typeof(items) = 'array'),
  total numeric(10,2) not null check (total >= 0),
  status text not null default 'pending'
    check (status in ('pending','confirmed','ready','completed','cancelled')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  order_type text not null default 'delivery'
    check (order_type in ('delivery','pickup')),
  address text not null default '',
  landmark text not null default '',
  preferred_date date,
  preferred_time text not null default ''
);

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner')),
  created_at timestamptz not null default now()
);

-- Reconcile older orders tables that do not have the new fields.
alter table public.orders
  add column if not exists order_type text not null default 'delivery';
alter table public.orders
  add column if not exists address text not null default '';
alter table public.orders
  add column if not exists landmark text not null default '';
alter table public.orders
  add column if not exists preferred_date date;
alter table public.orders
  add column if not exists preferred_time text not null default '';

-- Updated-at triggers ------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists products_updated_at on public.products;
create trigger products_updated_at
before update on public.products
for each row execute function public.set_updated_at();

drop trigger if exists settings_updated_at on public.store_settings;
create trigger settings_updated_at
before update on public.store_settings
for each row execute function public.set_updated_at();

-- Owner function ------------------------------------------------------------

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.admin_users
    where user_id = auth.uid()
      and role = 'owner'
  );
$$;

revoke all on function public.is_owner() from public;
grant execute on function public.is_owner() to authenticated;

-- RLS -----------------------------------------------------------------------

alter table public.products enable row level security;
alter table public.store_settings enable row level security;
alter table public.orders enable row level security;
alter table public.admin_users enable row level security;

-- Remove known old/unsafe policy names.
do $$
declare p record;
begin
  for p in
    select policyname, tablename
    from pg_policies
    where schemaname='public'
      and tablename in ('products','store_settings','orders','admin_users')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- Public catalogue: active rows only.
create policy "products_public_select_active"
on public.products
for select
to anon, authenticated
using (active = true);

-- Owner catalogue management.
create policy "products_owner_select_all"
on public.products
for select
to authenticated
using (public.is_owner());

create policy "products_owner_insert"
on public.products
for insert
to authenticated
with check (public.is_owner());

create policy "products_owner_update"
on public.products
for update
to authenticated
using (public.is_owner())
with check (public.is_owner());

create policy "products_owner_delete"
on public.products
for delete
to authenticated
using (public.is_owner());

-- Store settings: public read, owner write.
create policy "settings_public_select"
on public.store_settings
for select
to anon, authenticated
using (true);

create policy "settings_owner_insert"
on public.store_settings
for insert
to authenticated
with check (public.is_owner());

create policy "settings_owner_update"
on public.store_settings
for update
to authenticated
using (public.is_owner())
with check (public.is_owner());

-- Orders: owner only via the table API. Public checkout uses the RPC below.
create policy "orders_owner_select"
on public.orders
for select
to authenticated
using (public.is_owner());

create policy "orders_owner_update"
on public.orders
for update
to authenticated
using (public.is_owner())
with check (public.is_owner());

create policy "orders_owner_delete"
on public.orders
for delete
to authenticated
using (public.is_owner());

-- admin_users is intentionally not exposed to browser roles.
-- No SELECT/INSERT/UPDATE/DELETE policies are created for it.

-- Grants / Data API ---------------------------------------------------------

grant usage on schema public to anon, authenticated;

grant select on table public.products to anon, authenticated;
grant select, insert, update, delete on table public.products to authenticated;

grant select on table public.store_settings to anon, authenticated;
grant insert, update on table public.store_settings to authenticated;

grant select, update, delete on table public.orders to authenticated;

-- Online order RPC ----------------------------------------------------------

drop function if exists public.create_order(text,text,jsonb,text);
drop function if exists public.create_order(text,text,jsonb,text,text,text,date,text,text);

create or replace function public.create_order(
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_order_type text default 'delivery',
  p_address text default '',
  p_landmark text default '',
  p_preferred_date date default null,
  p_preferred_time text default '',
  p_notes text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item jsonb;
  v_product_id uuid;
  v_quantity integer;
  v_unit_price numeric(10,2);
  v_product_name text;
  v_total numeric(10,2) := 0;
  v_canonical_items jsonb := '[]'::jsonb;
  v_order_id uuid;
  v_count integer := 0;
  v_order_type text := lower(btrim(coalesce(p_order_type,'delivery')));
  v_address text := left(btrim(coalesce(p_address,'')),250);
  v_landmark text := left(btrim(coalesce(p_landmark,'')),120);
  v_preferred_time text := left(btrim(coalesce(p_preferred_time,'')),40);
  v_notes text := left(btrim(coalesce(p_notes,'')),500);
begin
  p_customer_name := btrim(coalesce(p_customer_name,''));
  p_customer_phone := btrim(coalesce(p_customer_phone,''));

  if char_length(p_customer_name) < 2 or char_length(p_customer_name) > 120 then
    raise exception 'Please enter a valid name.';
  end if;

  if p_customer_phone !~ '^[0-9+() -]{7,20}$' then
    raise exception 'Please enter a valid mobile number.';
  end if;

  if v_order_type not in ('delivery','pickup') then
    raise exception 'Please choose a valid order type.';
  end if;

  if v_order_type = 'delivery' and char_length(v_address) < 5 then
    raise exception 'A delivery address is required.';
  end if;

  if p_preferred_date is not null and p_preferred_date < current_date then
    raise exception 'Preferred date cannot be in the past.';
  end if;

  if v_preferred_time = '' then
    v_preferred_time := 'As soon as possible';
  end if;

  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'Invalid order items.';
  end if;

  v_count := jsonb_array_length(p_items);

  if v_count < 1 or v_count > 20 then
    raise exception 'An order must contain between 1 and 20 different products.';
  end if;

  if (
    select count(*)
    from public.orders o
    where o.customer_phone = p_customer_phone
      and o.created_at > now() - interval '10 minutes'
      and o.status in ('pending','confirmed','ready')
  ) >= 5 then
    raise exception 'Too many recent orders. Please wait a few minutes and try again.';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if coalesce(v_item->>'product_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'Invalid product.';
    end if;

    begin
      v_product_id := (v_item->>'product_id')::uuid;
      v_quantity := (v_item->>'quantity')::integer;
    exception when others then
      raise exception 'Invalid product or quantity.';
    end;

    if v_quantity < 1 or v_quantity > 20 then
      raise exception 'Quantity must be between 1 and 20.';
    end if;

    select p.name, p.price
      into v_product_name, v_unit_price
      from public.products p
      where p.id = v_product_id and p.active = true;

    if not found then
      raise exception 'One of the selected products is no longer available.';
    end if;

    v_total := v_total + (v_unit_price * v_quantity);

    v_canonical_items := v_canonical_items || jsonb_build_array(
      jsonb_build_object(
        'product_id', v_product_id,
        'name', v_product_name,
        'quantity', v_quantity,
        'unit_price', v_unit_price
      )
    );
  end loop;

  insert into public.orders (
    customer_name, customer_phone, items, total, status, notes,
    order_type, address, landmark, preferred_date, preferred_time
  )
  values (
    p_customer_name, p_customer_phone, v_canonical_items, v_total, 'pending', v_notes,
    v_order_type, v_address, v_landmark, p_preferred_date, v_preferred_time
  )
  returning id into v_order_id;

  return jsonb_build_object(
    'order_id', v_order_id,
    'total', v_total,
    'status', 'pending'
  );
end;
$$;

revoke all on function public.create_order(text,text,jsonb,text,text,text,date,text,text) from public;
grant execute on function public.create_order(text,text,jsonb,text,text,text,date,text,text) to anon, authenticated;

-- Store defaults ------------------------------------------------------------

insert into public.store_settings (id, bakery_name, phone, whatsapp, maps_url, address, hours)
values (
  true,
  'Azad Bakers',
  '+91 87087 37685',
  '918708737685',
  'https://www.google.com/maps/place/Azad+Bakers/@28.877015,76.9119885,18.13z/data=!4m6!3m5!1s0x390da3ecdee145ad:0x339a911858c6a19e!8m2!3d28.8786748!4d76.9141671!16s%2Fg%2F11y1ftwzww?entry=ttu&g_ep=EgoyMDI2MDkwOS4wIKXMDSoASAFQAw%3D%3D',
  'Main Thana Kalan Road, Chowk, Kharkhoda, Sonipat, Haryana 131402',
  'Mon–Sat: 7:00 AM – 10:00 PM; Sun: 7:00 AM – 10:30 PM'
)
on conflict (id) do nothing;

-- Storage -------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('product-images','product-images',true)
on conflict (id) do update set public=true;

do $$
declare p record;
begin
  for p in
    select policyname
    from pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname in (
        'Public can read product images',
        'Owner can upload product images',
        'Owner can update product images',
        'Owner can delete product images'
      )
  loop
    execute format('drop policy if exists %I on storage.objects', p.policyname);
  end loop;
end $$;

create policy "Public can read product images"
on storage.objects
for select
to anon, authenticated
using (bucket_id='product-images');

create policy "Owner can upload product images"
on storage.objects
for insert
to authenticated
with check (bucket_id='product-images' and public.is_owner());

create policy "Owner can update product images"
on storage.objects
for update
to authenticated
using (bucket_id='product-images' and public.is_owner())
with check (bucket_id='product-images' and public.is_owner());

create policy "Owner can delete product images"
on storage.objects
for delete
to authenticated
using (bucket_id='product-images' and public.is_owner());

-- Realtime ------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
exception when undefined_object then
  null;
end $$;

notify pgrst, 'reload schema';

-- NOTE: create the test/owner account in Authentication and then run:
-- insert into public.admin_users (user_id, role)
-- values ('YOUR_AUTH_USER_UUID', 'owner')
-- on conflict (user_id) do update set role='owner';
