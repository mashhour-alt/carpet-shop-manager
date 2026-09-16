-- Farsha: multi-device, multi-tenant cloud foundation.
create extension if not exists pgcrypto;

create type public.account_kind as enum ('institution', 'driver');
create type public.institution_role as enum ('owner', 'accountant', 'seller');
create type public.work_plan as enum ('commission', 'salary', 'salary_and_commission');
create type public.membership_status as enum ('active', 'suspended');
create type public.invitation_status as enum ('pending', 'claimed', 'cancelled', 'expired');
create type public.customer_payment_method as enum ('cash', 'network', 'visa', 'tabby', 'tamara');
create type public.driver_payment_method as enum ('cash', 'bank_transfer');
create type public.payment_status as enum ('unpaid', 'paid');
create type public.ledger_kind as enum ('withdrawal', 'expense', 'deduction', 'payment');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text not null unique,
  account_kind public.account_kind not null,
  onboarding_mode text not null check (onboarding_mode in ('owner','staff','driver')),
  photo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.driver_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  is_available boolean not null default true,
  bank_name text,
  iban text,
  created_at timestamptz not null default now()
);

create table public.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  logo_url text,
  commercial_registration text not null,
  tax_number text not null,
  address text not null,
  phone text not null,
  email text not null,
  visa_fee_rate numeric(7,6) not null default 0 check (visa_fee_rate between 0 and 1),
  tabby_fee_rate numeric(7,6) not null default 0 check (tabby_fee_rate between 0 and 1),
  tamara_fee_rate numeric(7,6) not null default 0 check (tamara_fee_rate between 0 and 1),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.institution_memberships (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.institution_role not null,
  status public.membership_status not null default 'active',
  work_plan public.work_plan not null default 'commission',
  commission_rate numeric(7,6) not null default 0.5 check (commission_rate between 0 and 1),
  monthly_salary numeric(12,2) not null default 0 check (monthly_salary >= 0),
  created_at timestamptz not null default now(),
  primary key (institution_id, user_id)
);

-- A driver is independent and never becomes an institution member. This table
-- only authorizes an institution to assign trips to that driver's account.
create table public.institution_driver_connections (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  driver_id uuid not null references public.driver_profiles(user_id) on delete cascade,
  status public.membership_status not null default 'active',
  connected_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (institution_id, driver_id)
);

create table public.institution_invitations (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  phone text not null,
  role public.institution_role not null check (role <> 'owner'),
  work_plan public.work_plan not null default 'commission',
  commission_rate numeric(7,6) not null default 0.5 check (commission_rate between 0 and 1),
  monthly_salary numeric(12,2) not null default 0 check (monthly_salary >= 0),
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 8)),
  status public.invitation_status not null default 'pending',
  expires_at timestamptz not null default (now() + interval '14 days'),
  created_by uuid not null references public.profiles(id),
  claimed_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null,
  phone text not null,
  purchases_total numeric(14,2) not null default 0,
  paid_total numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null,
  color text not null,
  remaining_length numeric(12,3) not null check (remaining_length >= 0),
  width numeric(5,2) not null default 4 check (width = 4),
  wholesale_price numeric(12,2) not null check (wholesale_price >= 0),
  image_url text,
  low_stock_at numeric(12,3) not null default 10 check (low_stock_at >= 0),
  last_sold_at timestamptz,
  created_at timestamptz not null default now(),
  unique (institution_id, name, color)
);

-- Sellers cannot access supplier identity or cost because both live separately.
create table public.inventory_costs (
  inventory_id uuid primary key references public.inventory_items(id) on delete cascade,
  institution_id uuid not null references public.institutions(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id),
  supplier_price numeric(12,2) not null check (supplier_price >= 0),
  updated_at timestamptz not null default now()
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  inventory_id uuid not null references public.inventory_items(id),
  seller_id uuid not null references public.profiles(id),
  driver_id uuid references public.driver_profiles(user_id),
  customer_name text not null default '',
  length numeric(12,3) not null check (length > 0),
  width numeric(5,2) not null default 4 check (width = 4),
  area numeric(14,3) not null check (area > 0),
  sale_price_per_sqm numeric(12,2) not null check (sale_price_per_sqm >= 0),
  wholesale_price_snapshot numeric(12,2) not null,
  installation_amount numeric(12,2) not null default 0,
  glue_gallons numeric(12,3) not null default 0,
  glue_amount numeric(12,2) not null default 0,
  iron_pieces numeric(12,3) not null default 0,
  iron_amount numeric(12,2) not null default 0,
  driver_fee numeric(12,2) not null default 0,
  customer_payment public.customer_payment_method not null,
  payment_fee numeric(12,2) not null default 0,
  seller_profit numeric(14,2) not null,
  seller_commission numeric(14,2) not null,
  total numeric(14,2) not null,
  created_at timestamptz not null default now()
);

create table public.driver_trips (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null unique references public.sales(id) on delete cascade,
  institution_id uuid not null references public.institutions(id) on delete cascade,
  driver_id uuid not null references public.driver_profiles(user_id),
  seller_id uuid not null references public.profiles(id),
  trip_date date not null default current_date,
  amount numeric(12,2) not null check (amount >= 0),
  payment_status public.payment_status not null default 'unpaid',
  payment_method public.driver_payment_method,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.seller_ledger (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  seller_id uuid not null references public.profiles(id),
  kind public.ledger_kind not null,
  amount numeric(12,2) not null check (amount > 0),
  note text not null default '',
  entry_date date not null default current_date,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index memberships_user_active_idx on public.institution_memberships(user_id, status, institution_id);
create index driver_connections_driver_idx on public.institution_driver_connections(driver_id, status, institution_id);
create index invitations_institution_status_idx on public.institution_invitations(institution_id, status);
create index invitations_phone_status_idx on public.institution_invitations(phone, status);
create index suppliers_institution_idx on public.suppliers(institution_id);
create index inventory_institution_name_idx on public.inventory_items(institution_id, name);
create index inventory_costs_institution_idx on public.inventory_costs(institution_id);
create index inventory_costs_supplier_idx on public.inventory_costs(supplier_id);
create index sales_institution_created_idx on public.sales(institution_id, created_at desc);
create index sales_seller_created_idx on public.sales(seller_id, created_at desc);
create index sales_inventory_idx on public.sales(inventory_id);
create index sales_driver_idx on public.sales(driver_id) where driver_id is not null;
create index trips_driver_date_idx on public.driver_trips(driver_id, trip_date desc);
create index trips_institution_date_idx on public.driver_trips(institution_id, trip_date desc);
create index trips_seller_idx on public.driver_trips(seller_id);
create index ledger_seller_date_idx on public.seller_ledger(seller_id, entry_date desc);
create index ledger_institution_date_idx on public.seller_ledger(institution_id, entry_date desc);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public
as $$
declare kind public.account_kind;
begin
  kind := coalesce((new.raw_user_meta_data ->> 'account_kind')::public.account_kind, 'institution');
  insert into public.profiles(id, full_name, phone, account_kind, onboarding_mode)
  values(new.id, coalesce(nullif(new.raw_user_meta_data ->> 'full_name',''),'مستخدم فرشة'),
    coalesce(nullif(new.phone,''),nullif(new.raw_user_meta_data ->> 'phone',''),new.id::text), kind,
    case when kind='driver' then 'driver' else coalesce(nullif(new.raw_user_meta_data ->> 'onboarding_mode',''),'staff') end);
  if kind='driver' then insert into public.driver_profiles(user_id) values(new.id); end if;
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_institution_member(p_id uuid) returns boolean
language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.institution_memberships m where m.institution_id=p_id and m.user_id=(select auth.uid()) and m.status='active') $$;

create or replace function public.has_institution_role(p_id uuid,p_roles public.institution_role[]) returns boolean
language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.institution_memberships m where m.institution_id=p_id and m.user_id=(select auth.uid()) and m.status='active' and m.role=any(p_roles)) $$;

create or replace function public.create_institution(p_name text,p_cr text,p_tax text,p_address text,p_phone text,p_email text)
returns uuid language plpgsql security definer set search_path=public
as $$ declare result_id uuid; begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.profiles where id=auth.uid() and account_kind='institution' and onboarding_mode='owner') then
    raise exception 'Only owner accounts can create institutions';
  end if;
  insert into public.institutions(name,commercial_registration,tax_number,address,phone,email,created_by)
  values(trim(p_name),trim(p_cr),trim(p_tax),trim(p_address),trim(p_phone),trim(p_email),auth.uid()) returning id into result_id;
  insert into public.institution_memberships(institution_id,user_id,role) values(result_id,auth.uid(),'owner');
  return result_id;
end; $$;

create or replace function public.claim_institution_invitation(p_code text) returns uuid
language plpgsql security definer set search_path=public
as $$ declare i public.institution_invitations%rowtype; user_phone text; begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select phone into user_phone from public.profiles where id=auth.uid();
  select * into i from public.institution_invitations where invite_code=upper(trim(p_code)) and status='pending' and expires_at>now() for update;
  if not found then raise exception 'Invitation is invalid or expired'; end if;
  if i.phone<>user_phone then raise exception 'Invitation phone does not match this account'; end if;
  insert into public.institution_memberships(institution_id,user_id,role,work_plan,commission_rate,monthly_salary)
  values(i.institution_id,auth.uid(),i.role,i.work_plan,i.commission_rate,i.monthly_salary)
  on conflict(institution_id,user_id) do update set role=excluded.role,status='active',work_plan=excluded.work_plan,
    commission_rate=excluded.commission_rate,monthly_salary=excluded.monthly_salary;
  update public.institution_invitations set status='claimed',claimed_by=auth.uid() where id=i.id;
  return i.institution_id;
end; $$;

create or replace function public.connect_driver(p_institution_id uuid,p_phone text) returns uuid
language plpgsql security definer set search_path=public
as $$ declare result_id uuid; begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then
    raise exception 'Insufficient permission';
  end if;
  select p.id into result_id from public.profiles p
  join public.driver_profiles d on d.user_id=p.id
  where p.account_kind='driver' and p.phone=trim(p_phone);
  if result_id is null then raise exception 'Driver account was not found'; end if;
  insert into public.institution_driver_connections(institution_id,driver_id,connected_by)
  values(p_institution_id,result_id,auth.uid())
  on conflict(institution_id,driver_id) do update set status='active',connected_by=auth.uid();
  return result_id;
end; $$;

create or replace function public.list_connected_drivers(p_institution_id uuid)
returns table(driver_id uuid,full_name text,phone text,is_available boolean,connection_status public.membership_status)
language plpgsql stable security definer set search_path=public
as $$ begin
  if not public.is_institution_member(p_institution_id) then raise exception 'Insufficient permission'; end if;
  return query select dc.driver_id,p.full_name,p.phone,d.is_available,dc.status
  from public.institution_driver_connections dc
  join public.driver_profiles d on d.user_id=dc.driver_id
  join public.profiles p on p.id=dc.driver_id
  where dc.institution_id=p_institution_id
  order by p.full_name;
end; $$;

create or replace function public.create_inventory_item(p_institution_id uuid,p_supplier_id uuid,p_name text,p_color text,
  p_length numeric,p_supplier_price numeric,p_wholesale_price numeric,p_low_stock_at numeric default 10) returns uuid
language plpgsql security definer set search_path=public
as $$ declare result_id uuid; begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if p_wholesale_price<p_supplier_price then raise exception 'Wholesale price cannot be below supplier price'; end if;
  insert into public.inventory_items(institution_id,name,color,remaining_length,wholesale_price,low_stock_at)
  values(p_institution_id,trim(p_name),trim(p_color),p_length,p_wholesale_price,p_low_stock_at) returning id into result_id;
  insert into public.inventory_costs(inventory_id,institution_id,supplier_id,supplier_price)
  values(result_id,p_institution_id,p_supplier_id,p_supplier_price);
  return result_id;
end; $$;

create or replace function public.record_sale(p_institution_id uuid,p_inventory_id uuid,p_seller_id uuid,p_driver_id uuid,
  p_customer_name text,p_length numeric,p_sale_price numeric,p_installation numeric,p_glue_gallons numeric,p_glue_amount numeric,
  p_iron_pieces numeric,p_iron_amount numeric,p_driver_fee numeric,p_customer_payment public.customer_payment_method) returns uuid
language plpgsql security definer set search_path=public
as $$ declare item public.inventory_items%rowtype; inst public.institutions%rowtype; seller public.institution_memberships%rowtype;
  result_id uuid; v_area numeric; v_rate numeric:=0; v_fee numeric; v_profit numeric; v_commission numeric; v_total numeric; begin
  if not public.has_institution_role(p_institution_id,array['owner','seller']::public.institution_role[]) then raise exception 'Only owners and sellers can record a sale'; end if;
  if auth.uid()<>p_seller_id and not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then raise exception 'Seller mismatch'; end if;
  select * into item from public.inventory_items where id=p_inventory_id and institution_id=p_institution_id for update;
  if not found or item.remaining_length<p_length then raise exception 'Requested length is unavailable'; end if;
  select * into seller from public.institution_memberships where institution_id=p_institution_id and user_id=p_seller_id and role='seller' and status='active';
  if not found then raise exception 'Seller is not active'; end if;
  if p_driver_id is not null and not exists(select 1 from public.institution_driver_connections
    where institution_id=p_institution_id and driver_id=p_driver_id and status='active') then
    raise exception 'Driver is not connected to this institution';
  end if;
  select * into inst from public.institutions where id=p_institution_id;
  v_area:=p_length*4; v_total:=v_area*p_sale_price+p_installation+p_glue_amount+p_iron_amount+p_driver_fee;
  v_rate:=case p_customer_payment when 'visa' then inst.visa_fee_rate when 'tabby' then inst.tabby_fee_rate when 'tamara' then inst.tamara_fee_rate else 0 end;
  v_fee:=v_total*v_rate; v_profit:=(p_sale_price-item.wholesale_price)*v_area; v_commission:=greatest(v_profit,0)*seller.commission_rate;
  insert into public.sales(institution_id,inventory_id,seller_id,driver_id,customer_name,length,area,sale_price_per_sqm,
    wholesale_price_snapshot,installation_amount,glue_gallons,glue_amount,iron_pieces,iron_amount,driver_fee,customer_payment,
    payment_fee,seller_profit,seller_commission,total)
  values(p_institution_id,p_inventory_id,p_seller_id,p_driver_id,coalesce(trim(p_customer_name),''),p_length,v_area,p_sale_price,
    item.wholesale_price,p_installation,p_glue_gallons,p_glue_amount,p_iron_pieces,p_iron_amount,p_driver_fee,p_customer_payment,
    v_fee,v_profit,v_commission,v_total) returning id into result_id;
  update public.inventory_items set remaining_length=remaining_length-p_length,last_sold_at=now() where id=p_inventory_id;
  if p_driver_id is not null then insert into public.driver_trips(sale_id,institution_id,driver_id,seller_id,amount)
    values(result_id,p_institution_id,p_driver_id,p_seller_id,p_driver_fee); end if;
  return result_id;
end; $$;

alter table public.profiles enable row level security;
alter table public.driver_profiles enable row level security;
alter table public.institutions enable row level security;
alter table public.institution_memberships enable row level security;
alter table public.institution_driver_connections enable row level security;
alter table public.institution_invitations enable row level security;
alter table public.suppliers enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_costs enable row level security;
alter table public.sales enable row level security;
alter table public.driver_trips enable row level security;
alter table public.seller_ledger enable row level security;

revoke all on table public.profiles,public.driver_profiles,public.institutions,public.institution_memberships,public.institution_driver_connections,
  public.institution_invitations,public.suppliers,public.inventory_items,public.inventory_costs,public.sales,
  public.driver_trips,public.seller_ledger from anon,authenticated;
grant select on public.profiles,public.institutions,public.institution_memberships,public.institution_driver_connections to authenticated;
grant update(full_name,photo_url) on public.profiles to authenticated;
grant select(user_id,is_available) on public.driver_profiles to authenticated;
grant update(is_available,bank_name,iban) on public.driver_profiles to authenticated;
grant update on public.institutions,public.institution_memberships,public.institution_driver_connections to authenticated;
grant select,insert,update on public.institution_invitations to authenticated;
grant select,insert,update,delete on public.suppliers,public.inventory_items,public.inventory_costs,public.seller_ledger to authenticated;
grant select on public.sales to authenticated;
grant select,update on public.driver_trips to authenticated;
grant all on table public.profiles,public.driver_profiles,public.institutions,public.institution_memberships,public.institution_driver_connections,
  public.institution_invitations,public.suppliers,public.inventory_items,public.inventory_costs,public.sales,
  public.driver_trips,public.seller_ledger to service_role;

create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()) or exists(
  select 1 from public.institution_memberships me join public.institution_memberships them using(institution_id)
  where me.user_id=(select auth.uid()) and them.user_id=profiles.id and me.status='active') or exists(
  select 1 from public.institution_memberships me join public.institution_driver_connections dc using(institution_id)
  where me.user_id=(select auth.uid()) and me.status='active' and dc.status='active' and dc.driver_id=profiles.id) or exists(
  select 1 from public.driver_trips t where t.driver_id=(select auth.uid()) and t.seller_id=profiles.id));
create policy profiles_update_self on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy drivers_read on public.driver_profiles for select to authenticated using(user_id=(select auth.uid()) or exists(
  select 1 from public.institution_driver_connections dc where dc.driver_id=driver_profiles.user_id
  and dc.status='active' and public.is_institution_member(dc.institution_id)));
create policy drivers_update_self on public.driver_profiles for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy institutions_read on public.institutions for select to authenticated using(public.is_institution_member(id));
create policy institutions_read_driver on public.institutions for select to authenticated using(exists(
  select 1 from public.driver_trips t where t.institution_id=institutions.id and t.driver_id=(select auth.uid())));
create policy institutions_update on public.institutions for update to authenticated using(public.has_institution_role(id,array['owner','accountant']::public.institution_role[])) with check(public.has_institution_role(id,array['owner','accountant']::public.institution_role[]));
create policy memberships_read on public.institution_memberships for select to authenticated using(user_id=(select auth.uid()) or public.is_institution_member(institution_id));
create policy memberships_update on public.institution_memberships for update to authenticated using(public.has_institution_role(institution_id,array['owner']::public.institution_role[])) with check(public.has_institution_role(institution_id,array['owner']::public.institution_role[]));
create policy driver_connections_read on public.institution_driver_connections for select to authenticated using(
  driver_id=(select auth.uid()) or public.is_institution_member(institution_id));
create policy driver_connections_update on public.institution_driver_connections for update to authenticated using(
  public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])) with check(
  public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy invitations_read on public.institution_invitations for select to authenticated using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy invitations_insert on public.institution_invitations for insert to authenticated with check(created_by=(select auth.uid()) and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy invitations_update on public.institution_invitations for update to authenticated using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])) with check(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy suppliers_manage on public.suppliers for all to authenticated using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])) with check(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy inventory_read on public.inventory_items for select to authenticated using(public.is_institution_member(institution_id));
create policy inventory_manage on public.inventory_items for all to authenticated using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])) with check(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy costs_manage on public.inventory_costs for all to authenticated using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])) with check(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy sales_read on public.sales for select to authenticated using(seller_id=(select auth.uid()) or public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy trips_read on public.driver_trips for select to authenticated using(driver_id=(select auth.uid()) or seller_id=(select auth.uid()) or public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy trips_update on public.driver_trips for update to authenticated using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])) with check(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy ledger_read on public.seller_ledger for select to authenticated using(seller_id=(select auth.uid()) or public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy ledger_manage on public.seller_ledger for all to authenticated using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])) with check(created_by=(select auth.uid()) and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));

revoke execute on function public.handle_new_user() from public,anon,authenticated;
revoke execute on function public.is_institution_member(uuid) from public,anon;
revoke execute on function public.has_institution_role(uuid,public.institution_role[]) from public,anon;
revoke execute on function public.create_institution(text,text,text,text,text,text) from public,anon;
revoke execute on function public.claim_institution_invitation(text) from public,anon;
revoke execute on function public.connect_driver(uuid,text) from public,anon;
revoke execute on function public.list_connected_drivers(uuid) from public,anon;
revoke execute on function public.create_inventory_item(uuid,uuid,text,text,numeric,numeric,numeric,numeric) from public,anon;
revoke execute on function public.record_sale(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,public.customer_payment_method) from public,anon;
grant execute on function public.is_institution_member(uuid),public.has_institution_role(uuid,public.institution_role[]),
  public.create_institution(text,text,text,text,text,text),public.claim_institution_invitation(text),
  public.connect_driver(uuid,text),
  public.list_connected_drivers(uuid),
  public.create_inventory_item(uuid,uuid,text,text,numeric,numeric,numeric,numeric),
  public.record_sale(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,public.customer_payment_method) to authenticated;
