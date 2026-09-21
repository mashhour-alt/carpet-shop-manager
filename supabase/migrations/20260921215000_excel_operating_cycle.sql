-- Farsha operating-cycle expansion based on the real daily Excel workflow.
-- Backward compatible: existing sales, invoices, inventory and supplier tables remain.

alter table public.sales
  alter column customer_payment type text using customer_payment::text;

alter table public.invoices
  alter column payment_method type text using payment_method::text;

alter table public.sales
  add column if not exists notes text not null default '',
  add column if not exists supplier_unit_cost_snapshot numeric(12,2),
  add column if not exists status text not null default 'completed',
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid references public.profiles(id),
  add column if not exists reverse_reason text not null default '';

alter table public.sales drop constraint if exists sales_status_check;
alter table public.sales add constraint sales_status_check
  check (status in ('completed','voided','returned'));

update public.sales s
set supplier_unit_cost_snapshot = ic.supplier_price
from public.inventory_costs ic
where ic.inventory_id=s.inventory_id and s.supplier_unit_cost_snapshot is null;
update public.sales set supplier_unit_cost_snapshot=0 where supplier_unit_cost_snapshot is null;
alter table public.sales alter column supplier_unit_cost_snapshot set default 0;
alter table public.sales alter column supplier_unit_cost_snapshot set not null;

alter table public.invoices
  add column if not exists payment_summary text not null default '',
  add column if not exists addons_summary text not null default '',
  add column if not exists addons_amount numeric(14,2) not null default 0;

create table public.addon_types (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null,
  unit text not null default 'piece',
  default_sale_price numeric(12,2) not null default 0 check(default_sale_price>=0),
  default_cost_price numeric(12,2) not null default 0 check(default_cost_price>=0),
  supplier_id uuid references public.suppliers(id),
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(institution_id,name)
);

create table public.sale_addons (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  addon_type_id uuid references public.addon_types(id),
  name_snapshot text not null,
  unit_snapshot text not null,
  quantity numeric(12,3) not null check(quantity>0),
  sale_unit_price numeric(12,2) not null default 0 check(sale_unit_price>=0),
  cost_unit_price numeric(12,2) not null default 0 check(cost_unit_price>=0),
  supplier_id uuid references public.suppliers(id),
  created_at timestamptz not null default now()
);

create table public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  method text not null check(method in ('cash','network','bank_transfer','visa','tamara','tabby','other')),
  amount numeric(14,2) not null check(amount>0),
  reference text not null default '',
  fee_rate_snapshot numeric(7,6) not null default 0 check(fee_rate_snapshot between 0 and 1),
  fee_amount numeric(14,2) not null default 0 check(fee_amount>=0),
  paid_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id)
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  inventory_id uuid not null references public.inventory_items(id) on delete cascade,
  movement_type text not null check(movement_type in ('opening','purchase','sale','sale_void','sale_return','adjustment')),
  length_delta numeric(12,3) not null check(length_delta<>0),
  source_type text not null default '',
  source_id uuid,
  note text not null default '',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create unique index inventory_movements_source_unique
  on public.inventory_movements(movement_type,source_id)
  where source_id is not null and movement_type in ('sale','sale_void','sale_return');

create table public.supplier_deliveries (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id),
  reference text not null default '',
  notes text not null default '',
  delivered_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.supplier_delivery_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  delivery_id uuid not null references public.supplier_deliveries(id) on delete cascade,
  inventory_id uuid not null references public.inventory_items(id),
  name_snapshot text not null,
  color_snapshot text not null,
  length numeric(12,3) not null check(length>0),
  width numeric(5,2) not null default 4 check(width=4),
  unit_cost numeric(12,2) not null check(unit_cost>=0),
  wholesale_price numeric(12,2) not null check(wholesale_price>=unit_cost),
  created_at timestamptz not null default now()
);

create index sale_payments_sale_idx on public.sale_payments(sale_id,paid_at);
create index sale_payments_institution_method_idx on public.sale_payments(institution_id,method,paid_at);
create index sale_addons_sale_idx on public.sale_addons(sale_id);
create index sale_addons_institution_idx on public.sale_addons(institution_id);
create index inventory_movements_inventory_idx on public.inventory_movements(inventory_id,created_at desc);
create index supplier_deliveries_supplier_idx on public.supplier_deliveries(supplier_id,delivered_at desc);
create index supplier_delivery_items_delivery_idx on public.supplier_delivery_items(delivery_id);
create index sales_status_created_idx on public.sales(institution_id,status,created_at desc);

alter table public.addon_types enable row level security;
alter table public.sale_addons enable row level security;
alter table public.sale_payments enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.supplier_deliveries enable row level security;
alter table public.supplier_delivery_items enable row level security;

revoke all on table public.addon_types,public.sale_addons,public.sale_payments,
 public.inventory_movements,public.supplier_deliveries,public.supplier_delivery_items from anon,authenticated;
grant select on table public.addon_types,public.sale_addons,public.sale_payments,
 public.inventory_movements,public.supplier_deliveries,public.supplier_delivery_items to authenticated;

create policy addon_types_read on public.addon_types for select to authenticated
 using(public.is_institution_member(institution_id));
create policy addon_types_manage on public.addon_types for all to authenticated
 using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]))
 with check(created_by=(select auth.uid()) and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy sale_addons_read on public.sale_addons for select to authenticated
 using(exists(select 1 from public.sales s where s.id=sale_id and
   (s.seller_id=(select auth.uid()) or public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]))));
create policy sale_payments_read on public.sale_payments for select to authenticated
 using(exists(select 1 from public.sales s where s.id=sale_id and
   (s.seller_id=(select auth.uid()) or public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]))));
create policy inventory_movements_read on public.inventory_movements for select to authenticated
 using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy supplier_deliveries_read on public.supplier_deliveries for select to authenticated
 using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
create policy supplier_delivery_items_read on public.supplier_delivery_items for select to authenticated
 using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));

insert into public.addon_types(institution_id,name,unit,created_by)
select i.id,x.name,x.unit,i.created_by from public.institutions i
cross join(values('تركيب','job'),('لباد','sqm'),('حديد','piece'),('غراء','gallon')) x(name,unit)
on conflict(institution_id,name) do nothing;

insert into public.sale_payments(institution_id,sale_id,method,amount,fee_amount,fee_rate_snapshot,paid_at,created_by)
select s.institution_id,s.id,s.customer_payment,s.total,s.payment_fee,
 case when s.total>0 then least(greatest(s.payment_fee/s.total,0),1) else 0 end,s.created_at,s.seller_id
from public.sales s
where s.status='completed' and s.total>0
and not exists(select 1 from public.sale_payments p where p.sale_id=s.id);

insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by,created_at)
select s.institution_id,s.inventory_id,'sale',-s.length,'legacy_sale',s.id,'Backfilled from pre-ledger sale',s.seller_id,s.created_at
from public.sales s
where not exists(select 1 from public.inventory_movements m where m.movement_type='sale' and m.source_id=s.id);
