-- Isolated transactional verification for personal/external driver trips.
create extension if not exists pgcrypto;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

drop table if exists public.driver_personal_trips;
drop table if exists public.driver_profiles;
drop type if exists public.driver_payment_method;
drop type if exists public.payment_status;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
create type public.payment_status as enum ('unpaid','paid');
create type public.driver_payment_method as enum ('cash','bank_transfer');
create table public.driver_profiles (user_id uuid primary key);
create table public.driver_personal_trips (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.driver_profiles(user_id),
  shop_name text not null check (btrim(shop_name) <> ''),
  customer_name text not null default '', customer_phone text not null default '', location text not null default '',
  trip_at timestamptz not null default now(), amount numeric(12,2) not null check (amount > 0),
  payment_status public.payment_status not null default 'unpaid', payment_method public.driver_payment_method,
  paid_at timestamptz, notes text not null default '', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.driver_personal_trips enable row level security;
revoke all on public.driver_personal_trips from public;
grant select, insert, update on public.driver_personal_trips to authenticated;
create policy driver_personal_trips_select_own on public.driver_personal_trips for select to authenticated using (driver_id=(select auth.uid()));
create policy driver_personal_trips_insert_own on public.driver_personal_trips for insert to authenticated with check (driver_id=(select auth.uid()));
create policy driver_personal_trips_update_own on public.driver_personal_trips for update to authenticated using (driver_id=(select auth.uid())) with check (driver_id=(select auth.uid()));

insert into public.driver_profiles values
  ('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002');

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
do $$
declare driver_a uuid := '10000000-0000-4000-8000-000000000001'; driver_b uuid := '10000000-0000-4000-8000-000000000002'; owner uuid := '10000000-0000-4000-8000-000000000003'; trip_id uuid; count_seen int; denied boolean;
begin
  insert into public.driver_personal_trips(driver_id,shop_name,amount,customer_name,trip_at)
    values(driver_a,'محل خارجي',75,'عميل خارجي','2026-10-04T10:00:00Z') returning id into trip_id;
  select count(*) into count_seen from public.driver_personal_trips;
  if count_seen <> 1 then raise exception 'Driver cannot see own external trip'; end if;
  update public.driver_personal_trips set payment_status='paid',payment_method='cash',paid_at=now() where id=trip_id;
  if not exists(select 1 from public.driver_personal_trips where id=trip_id and payment_status='paid' and amount=75) then raise exception 'Paid/remaining update failed'; end if;
  perform set_config('request.jwt.claim.sub', driver_b::text, false);
  select count(*) into count_seen from public.driver_personal_trips;
  if count_seen <> 0 then raise exception 'Another driver can read external trip'; end if;
  denied := false;
  begin insert into public.driver_personal_trips(driver_id,shop_name,amount) values(driver_a,'محل مسروق',10); exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Another driver can insert for driver A'; end if;
  perform set_config('request.jwt.claim.sub', owner::text, false);
  select count(*) into count_seen from public.driver_personal_trips;
  if count_seen <> 0 then raise exception 'Institution user can read unrelated external trip'; end if;
  raise notice 'PASS personal driver trip create/read/update/payment and driver/institution isolation';
end $$;
rollback;
