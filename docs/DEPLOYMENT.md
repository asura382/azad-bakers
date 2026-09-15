# Azad Bakers — Supabase-connected deployment

## Current architecture

- `public/` is the customer storefront.
- `admin/` is the owner dashboard.
- `public/config.js` contains the Supabase project URL and publishable browser key.
- `supabase/schema.sql` creates the tables + RLS.
- `supabase/api-grants.sql` explicitly grants only the Data API roles needed because automatic exposure of new tables was disabled.
- `supabase/seed-demo.sql` is optional demo catalogue seed data.

## Security

The publishable key is designed for browser/client code. Supabase's security model relies on Row Level Security to constrain what that client can access. Never place an `sb_secret_...` key, legacy `service_role` key, database password, or other privileged credential in `public/` or `admin/`.

The owner dashboard authenticates with Supabase Auth and then calls `is_owner()` before showing the app. Product/settings writes are protected by RLS and the `admin_users` allow-list.

The public storefront only selects active products and public store settings.

## Order security

The current customer checkout deliberately continues to use WhatsApp. There is no public database INSERT policy for `orders`. This avoids trusting browser-supplied totals. A future database order flow should use a server-side/Edge Function that validates product IDs, quantities, prices and the final total before insertion.

## Required one-time setup

1. Run `schema.sql` (already completed in the project).
2. Run `api-grants.sql` so the Data API can access only the intended tables/operations.
3. Run `storage-migration.sql` once to create the product image bucket and storage RLS policies.
4. Your test owner Auth account is already created. Its UUID was registered in `admin_users`.
5. Optionally run `seed-demo.sql` or add products from the dashboard.
6. Serve the project over HTTP/HTTPS. For local preview use a local server rather than `file://` when testing Auth/network behaviour.

## Admin login

The admin uses Supabase Auth email/password. An account is accepted only if its UUID exists in `public.admin_users` with role `owner`.

## Production hardening before client handoff

- Replace the test email with the bakery owner's email and delete the test account.
- Use a unique strong password and enable MFA for the owner if practical.
- Restrict Supabase Storage uploads to image MIME types and reasonable sizes when photo uploads are added.
- Keep order creation server-side if orders move into the database.
- Add rate limiting / abuse protection to any public order endpoint.
- Keep HTTPS enabled on the custom domain.
- Keep backups/exports of the catalogue.


## Online website orders

Run `supabase/online-order-rpc.sql` after the base schema and API grants.

Customer orders are submitted through the `create_order` RPC. The function:
- validates the customer name and phone number;
- accepts product IDs/quantities only;
- looks up current active products and prices server-side;
- calculates the total server-side;
- stores a canonical item snapshot;
- rate-limits repeated orders from the same phone number;
- inserts a pending order without granting anonymous INSERT access to `public.orders`.

The admin dashboard polls the orders table every 15 seconds while the owner is signed in.

The old WhatsApp checkout is no longer used for product orders. WhatsApp remains available only as a contact/custom-cake enquiry path.


## Direct online ordering V2

Run `supabase/online-order-rpc.sql` after the original schema and API grants.

This migration adds:
- delivery vs pickup;
- delivery address and landmark;
- preferred date/time;
- multi-product orders;
- server-side total calculation;
- server-side product/price validation;
- basic anti-spam protection;
- Supabase Realtime publication for order events.

The customer storefront no longer uses WhatsApp for product checkout.

The owner dashboard listens for `orders` table changes and refreshes automatically. Browser notifications are optional and can be enabled from the dashboard.

Before production:
- configure a proper bot/rate-limit layer if the public site receives substantial traffic;
- consider an Edge Function if you need stronger abuse controls or external notifications;
- restrict admin access to intended owner accounts;
- use only Supabase Storage for product images if possible;
- periodically back up/export the product catalogue.
