-- Personal/external trips are deliberately separate from institution driver_trips.
-- They have no institution, branch, sale, account-entry, notification or ledger link.
create table public.driver_personal_trips (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.driver_profiles(user_id) on delete cascade,
  shop_name text not null check (btrim(shop_name) <> ''),
  customer_name text not null default '',
  customer_phone text not null default '',
  location text not null default '',
  trip_at timestamptz not null default now(),
  amount numeric(12,2) not null check (amount > 0),
  payment_status public.payment_status not null default 'unpaid',
  payment_method public.driver_payment_method,
  paid_at timestamptz,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index driver_personal_trips_driver_date_idx
  on public.driver_personal_trips(driver_id, trip_at desc);

alter table public.driver_personal_trips enable row level security;
revoke all on table public.driver_personal_trips from anon, authenticated;
grant select, insert, update on table public.driver_personal_trips to authenticated;

create policy driver_personal_trips_select_own
  on public.driver_personal_trips for select to authenticated
  using (driver_id = (select auth.uid()));

create policy driver_personal_trips_insert_own
  on public.driver_personal_trips for insert to authenticated
  with check (driver_id = (select auth.uid()));

create policy driver_personal_trips_update_own
  on public.driver_personal_trips for update to authenticated
  using (driver_id = (select auth.uid()))
  with check (driver_id = (select auth.uid()));
