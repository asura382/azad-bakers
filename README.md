# Azad Bakers — Final Client Build

## Run locally
Serve the `azad-bakers-v2` folder over HTTP. Do not use a `file://` URL for the final test.

From the `azad-bakers-v2` folder:
`python -m http.server 5500`

Customer storefront:
`http://localhost:5500/public/`

Owner dashboard:
`http://localhost:5500/admin/`

## Supabase — one canonical migration
Run **only**:

`supabase/complete-migration.sql`

Run it once in Supabase SQL Editor after the project and owner Auth user exist.

The migration creates/reconciles:
- products
- store_settings
- orders
- admin_users
- RLS policies
- API grants
- secure `create_order()` RPC
- product image storage
- realtime publication for orders

It is designed to preserve existing product/order/admin data and is safe to re-run for the same project.

After creating an Auth user, register the owner with the commented `admin_users` INSERT at the bottom if it is not already present.

## Optional demo data
`supabase/seed-demo.sql` is optional and is for development/testing only. Do not run it for the final client catalogue.

## Customer ordering
Customers can order multiple products in one checkout, choose quantity, choose home delivery or pickup, enter mobile/address/date/time/notes, and submit directly to Supabase. Normal product checkout does not use WhatsApp.

WhatsApp remains available only for direct contact/custom-cake enquiries.

## Owner capabilities
- Real Supabase Auth login
- Owner-only product management
- Add/edit/delete products
- Change prices
- Publish/hide products
- Upload product images
- Store settings
- Orders with customer/delivery details
- Status workflow
- Live order updates / optional browser notifications

## Security notes
- Publishable Supabase key only in browser code.
- No service-role/secret key in frontend files.
- Public catalogue is read-only.
- Public orders are created through the `create_order()` RPC; there is no public `INSERT` policy on `orders`.
- The RPC validates product IDs/quantities and calculates totals from current database prices.
- Owner writes require `is_owner()` + RLS.
