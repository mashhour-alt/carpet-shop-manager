# فرشة | FARSHA

Flutter Android application for Saudi carpet-shop operations.

The production architecture uses Supabase Auth and PostgreSQL. There is no
device-only database fallback: owners, accountants, sellers and independent
drivers sign in from their own phones and see only data allowed by PostgreSQL
Row Level Security.

## Implemented first operating cycle

1. Create institution and payment-fee settings.
2. Create separate owner, accountant and seller accounts and invite them to an institution.
3. Create suppliers.
4. Add inventory by item, colour, supplier, available length, supplier cost and seller wholesale price.
5. Record a sale with 4m default width, calculated area, payment method, driver trip, glue and iron consumption.
6. Deduct the sold running length in the same SQLite transaction.
7. Calculate seller commission from the wholesale/sale-price difference.
8. Connect one independent driver account to multiple institutions and show its account separately for each institution.
9. Show monthly seller settlement and record withdrawals, expenses, deductions and payments.

## Supabase setup

Apply `supabase/migrations/20260916105727_farsha_core.sql` to a Supabase
project. The migration creates the tenant model, atomic stock deduction and
sale calculation functions, and RLS policies.

Build with these compile-time values:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Only the publishable client key belongs in the Android app. Never add a secret
or service-role key to Flutter or GitHub source.

## Build

GitHub Actions reads the two values from repository variables, then builds an
installable release APK when a GitHub Release is published or from **Actions →
Build Android Release APK → Run workflow**. The output is attached as the
`farsha-release-apk` artifact.
