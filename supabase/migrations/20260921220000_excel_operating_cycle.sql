-- Extend Farsha with the real Excel operating cycle without replacing existing features.
-- Backward compatible: legacy sale/invoice columns remain available.

alter table public.sales
  alter column customer_payment type text using customer_payment::text;

alter table public.invoices
  alter column payment_method type text using payment_method::text;

alter table public.sales
  add column if not exists notes text not null default '',
  add column if not exists supplier_unit_cost_snapshot numeric(12,2),
  add column if not exists status text not null default 'completed',
  add column if not exists collection_status text not null default 'paid',
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid references public.profiles(id),
  add column if not exists reverse_reason text not null default '';

alter table public.sales drop constraint if exists sales_status_check;
alter table public.sales add constraint sales_status_check
  check (status in ('completed','voided','returned'));
alter table public.sales drop constraint if exists sales_collection_status_check;
alter table public.sales add constraint sales_collection_status_check
  check (collection_status in ('unpaid','partial','paid'));

update public.sales s
set supplier_unit_cost_snapshot = ic.supplier_price
from public.inventory_costs ic
where ic.inventory_id = s.inventory_id
  and s.supplier_unit_cost_snapshot is null;
update public.sales set supplier_unit_cost_snapshot = 0
where supplier_unit_cost_snapshot is null;
alter table public.sales
  alter column supplier_unit_cost_snapshot set default 0,
  alter column supplier_unit_cost_snapshot set not null;

alter table public.invoices
  add column if not exists payment_summary text not null default '',
  add column if not exists addons_summary text not null default '',
  add column if not exists addons_amount numeric(14,2) not null default 0;

create table if not exists public.addon_types (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null,
  unit text not null default 'piece',
  default_sale_price numeric(12,2) not null default 0 check (default_sale_price >= 0),
  default_cost_price numeric(12,2) not null default 0 check (default_cost_price >= 0),
  supplier_id uuid references public.suppliers(id),
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(institution_id,name)
);

create table if not exists public.sale_addons (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  addon_type_id uuid references public.addon_types(id),
  name_snapshot text not null,
  unit_snapshot text not null,
  quantity numeric(12,3) not null check (quantity > 0),
  sale_unit_price numeric(12,2) not null default 0 check (sale_unit_price >= 0),
  cost_unit_price numeric(12,2) not null default 0 check (cost_unit_price >= 0),
  supplier_id uuid references public.suppliers(id),
  created_at timestamptz not null default now()
);

create table if not exists public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  method text not null check (method in ('cash','network','bank_transfer','visa','tamara','tabby','other')),
  amount numeric(14,2) not null check (amount > 0),
  reference text not null default '',
  fee_rate_snapshot numeric(7,6) not null default 0 check (fee_rate_snapshot between 0 and 1),
  fee_amount numeric(14,2) not null default 0 check (fee_amount >= 0),
  paid_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id)
);

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  inventory_id uuid not null references public.inventory_items(id) on delete cascade,
  movement_type text not null check (movement_type in ('opening','purchase','sale','sale_void','sale_return','adjustment')),
  length_delta numeric(12,3) not null check (length_delta <> 0),
  source_type text not null default '',
  source_id uuid,
  note text not null default '',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_deliveries (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id),
  reference text not null default '',
  notes text not null default '',
  delivered_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_delivery_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  delivery_id uuid not null references public.supplier_deliveries(id) on delete cascade,
  inventory_id uuid not null references public.inventory_items(id),
  name_snapshot text not null,
  color_snapshot text not null,
  length numeric(12,3) not null check (length > 0),
  width numeric(5,2) not null default 4 check (width = 4),
  unit_cost numeric(12,2) not null check (unit_cost >= 0),
  wholesale_price numeric(12,2) not null check (wholesale_price >= unit_cost),
  created_at timestamptz not null default now()
);

create index if not exists sale_payments_sale_idx on public.sale_payments(sale_id,paid_at);
create index if not exists sale_payments_institution_method_idx on public.sale_payments(institution_id,method,paid_at);
create index if not exists sale_addons_sale_idx on public.sale_addons(sale_id);
create index if not exists sale_addons_institution_idx on public.sale_addons(institution_id);
create index if not exists inventory_movements_inventory_idx on public.inventory_movements(inventory_id,created_at desc);
create unique index if not exists inventory_movements_source_unique
  on public.inventory_movements(movement_type,source_id)
  where source_id is not null and movement_type in ('sale','sale_void','sale_return');
create index if not exists supplier_deliveries_supplier_idx on public.supplier_deliveries(supplier_id,delivered_at desc);
create index if not exists supplier_delivery_items_delivery_idx on public.supplier_delivery_items(delivery_id);
create index if not exists sales_status_created_idx on public.sales(institution_id,status,created_at desc);

alter table public.addon_types enable row level security;
alter table public.sale_addons enable row level security;
alter table public.sale_payments enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.supplier_deliveries enable row level security;
alter table public.supplier_delivery_items enable row level security;

revoke all on table public.addon_types, public.sale_addons, public.sale_payments,
  public.inventory_movements, public.supplier_deliveries, public.supplier_delivery_items
from anon, authenticated;
grant select on table public.addon_types, public.sale_addons, public.sale_payments,
  public.inventory_movements, public.supplier_deliveries, public.supplier_delivery_items
to authenticated;
grant all on table public.addon_types, public.sale_addons, public.sale_payments,
  public.inventory_movements, public.supplier_deliveries, public.supplier_delivery_items
to service_role;

drop policy if exists addon_types_read on public.addon_types;
create policy addon_types_read on public.addon_types for select to authenticated
using (public.is_institution_member(institution_id));
drop policy if exists addon_types_manage on public.addon_types;
create policy addon_types_manage on public.addon_types for all to authenticated
using (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]))
with check (
  created_by=(select auth.uid()) and
  public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])
);

drop policy if exists sale_addons_read on public.sale_addons;
create policy sale_addons_read on public.sale_addons for select to authenticated
using (exists (
  select 1 from public.sales s where s.id=sale_id and
  (s.seller_id=(select auth.uid()) or public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]))
));

drop policy if exists sale_payments_read on public.sale_payments;
create policy sale_payments_read on public.sale_payments for select to authenticated
using (exists (
  select 1 from public.sales s where s.id=sale_id and
  (s.seller_id=(select auth.uid()) or public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]))
));

drop policy if exists inventory_movements_read on public.inventory_movements;
create policy inventory_movements_read on public.inventory_movements for select to authenticated
using (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
drop policy if exists supplier_deliveries_read on public.supplier_deliveries;
create policy supplier_deliveries_read on public.supplier_deliveries for select to authenticated
using (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
drop policy if exists supplier_delivery_items_read on public.supplier_delivery_items;
create policy supplier_delivery_items_read on public.supplier_delivery_items for select to authenticated
using (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));

insert into public.addon_types(institution_id,name,unit,created_by)
select i.id, seed.name, seed.unit, i.created_by
from public.institutions i
cross join (values ('تركيب','job'),('لباد','sqm'),('حديد','piece'),('غراء','gallon')) seed(name,unit)
on conflict(institution_id,name) do nothing;

insert into public.sale_payments(institution_id,sale_id,method,amount,fee_amount,fee_rate_snapshot,paid_at,created_by)
select s.institution_id,s.id,s.customer_payment,s.total,s.payment_fee,
  case when s.total>0 then least(greatest(s.payment_fee/s.total,0),1) else 0 end,
  s.created_at,s.seller_id
from public.sales s
where s.status='completed' and s.total>0
  and s.customer_payment in ('cash','network','bank_transfer','visa','tamara','tabby','other')
  and not exists (select 1 from public.sale_payments p where p.sale_id=s.id);

insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by,created_at)
select s.institution_id,s.inventory_id,'sale',-s.length,'legacy_sale',s.id,'Backfilled from pre-ledger sale',s.seller_id,s.created_at
from public.sales s
where not exists (select 1 from public.inventory_movements m where m.movement_type='sale' and m.source_id=s.id);

create or replace function public.record_operating_sale(
  p_institution_id uuid, p_inventory_id uuid, p_seller_id uuid, p_driver_id uuid,
  p_customer_name text, p_length numeric, p_sale_price numeric, p_driver_fee numeric,
  p_notes text, p_addons jsonb default '[]'::jsonb, p_payments jsonb default '[]'::jsonb
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  item public.inventory_items%rowtype;
  cost_row public.inventory_costs%rowtype;
  inst public.institutions%rowtype;
  seller public.institution_memberships%rowtype;
  result_id uuid;
  a jsonb; pay jsonb;
  v_area numeric; v_carpet_sale numeric; v_addon_sale numeric:=0; v_total numeric;
  v_profit_for_seller numeric; v_commission numeric; v_paid numeric:=0;
  v_method text; v_amount numeric; v_rate numeric; v_fee numeric; v_total_fee numeric:=0;
  v_status text; v_name text; v_unit text; v_qty numeric; v_sale_unit numeric; v_cost_unit numeric; v_supplier uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_institution_role(p_institution_id,array['owner','seller']::public.institution_role[]) then
    raise exception 'Only owners and sellers can record a sale';
  end if;
  if auth.uid()<>p_seller_id and not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then
    raise exception 'Seller mismatch';
  end if;
  if p_length<=0 or p_sale_price<0 or p_driver_fee<0 then raise exception 'Invalid sale values'; end if;

  select * into item from public.inventory_items
  where id=p_inventory_id and institution_id=p_institution_id for update;
  if not found or item.remaining_length<p_length then raise exception 'Requested length is unavailable'; end if;
  select * into cost_row from public.inventory_costs
  where inventory_id=p_inventory_id and institution_id=p_institution_id;
  if not found then raise exception 'Inventory supplier cost is missing'; end if;
  select * into seller from public.institution_memberships
  where institution_id=p_institution_id and user_id=p_seller_id and role='seller' and status='active';
  if not found then raise exception 'Seller is not active'; end if;
  if p_driver_id is not null and not exists(
    select 1 from public.institution_driver_connections
    where institution_id=p_institution_id and driver_id=p_driver_id and status='active'
  ) then raise exception 'Driver is not connected to this institution'; end if;
  select * into inst from public.institutions where id=p_institution_id;

  v_area:=round(p_length*4,3);
  v_carpet_sale:=round(v_area*p_sale_price,2);

  for a in select value from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) loop
    v_name:=trim(coalesce(a->>'name',''));
    v_unit:=trim(coalesce(a->>'unit','piece'));
    v_qty:=coalesce((a->>'quantity')::numeric,0);
    v_sale_unit:=coalesce((a->>'sale_unit_price')::numeric,0);
    v_cost_unit:=coalesce((a->>'cost_unit_price')::numeric,0);
    v_supplier:=nullif(a->>'supplier_id','')::uuid;
    if v_name='' or v_qty<=0 or v_sale_unit<0 or v_cost_unit<0 then raise exception 'Invalid add-on'; end if;
    v_addon_sale:=v_addon_sale+round(v_qty*v_sale_unit,2);
  end loop;
  v_total:=round(v_carpet_sale+v_addon_sale+p_driver_fee,2);

  for pay in select value from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
    v_method:=coalesce(pay->>'method','');
    v_amount:=coalesce((pay->>'amount')::numeric,0);
    if v_method not in ('cash','network','bank_transfer','visa','tamara','tabby','other') or v_amount<=0 then
      raise exception 'Invalid payment';
    end if;
    v_paid:=v_paid+v_amount;
  end loop;
  if round(v_paid,2)>v_total then raise exception 'Payments exceed sale total'; end if;
  v_status:=case when round(v_paid,2)=0 then 'unpaid' when round(v_paid,2)<v_total then 'partial' else 'paid' end;

  v_profit_for_seller:=round(greatest((p_sale_price-item.wholesale_price)*v_area,0),2);
  v_commission:=round(v_profit_for_seller*seller.commission_rate,2);

  insert into public.sales(
    institution_id,inventory_id,seller_id,driver_id,customer_name,length,width,area,sale_price_per_sqm,
    wholesale_price_snapshot,supplier_unit_cost_snapshot,installation_amount,glue_gallons,glue_amount,
    iron_pieces,iron_amount,driver_fee,customer_payment,payment_fee,seller_profit,seller_commission,total,
    notes,status,collection_status
  ) values (
    p_institution_id,p_inventory_id,p_seller_id,p_driver_id,coalesce(trim(p_customer_name),''),
    p_length,4,v_area,p_sale_price,item.wholesale_price,cost_row.supplier_price,0,0,0,0,0,p_driver_fee,
    case when jsonb_array_length(coalesce(p_payments,'[]'::jsonb))=1 then coalesce(p_payments->0->>'method','cash')
         when jsonb_array_length(coalesce(p_payments,'[]'::jsonb))>1 then 'split' else 'unpaid' end,
    0,v_profit_for_seller,v_commission,v_total,coalesce(trim(p_notes),''),'completed',v_status
  ) returning id into result_id;

  for a in select value from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) loop
    v_name:=trim(coalesce(a->>'name','')); v_unit:=trim(coalesce(a->>'unit','piece'));
    v_qty:=coalesce((a->>'quantity')::numeric,0); v_sale_unit:=coalesce((a->>'sale_unit_price')::numeric,0);
    v_cost_unit:=coalesce((a->>'cost_unit_price')::numeric,0); v_supplier:=nullif(a->>'supplier_id','')::uuid;
    insert into public.sale_addons(institution_id,sale_id,addon_type_id,name_snapshot,unit_snapshot,quantity,sale_unit_price,cost_unit_price,supplier_id)
    values(p_institution_id,result_id,nullif(a->>'addon_type_id','')::uuid,v_name,v_unit,v_qty,v_sale_unit,v_cost_unit,v_supplier);
  end loop;

  for pay in select value from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
    v_method:=pay->>'method'; v_amount:=(pay->>'amount')::numeric;
    v_rate:=case v_method when 'visa' then inst.visa_fee_rate when 'tabby' then inst.tabby_fee_rate when 'tamara' then inst.tamara_fee_rate else 0 end;
    v_fee:=round(v_amount*v_rate,2); v_total_fee:=v_total_fee+v_fee;
    insert into public.sale_payments(institution_id,sale_id,method,amount,reference,fee_rate_snapshot,fee_amount,created_by)
    values(p_institution_id,result_id,v_method,v_amount,coalesce(pay->>'reference',''),v_rate,v_fee,auth.uid());
  end loop;
  update public.sales set payment_fee=round(v_total_fee,2) where id=result_id;

  update public.inventory_items set remaining_length=remaining_length-p_length,last_sold_at=now()
  where id=p_inventory_id;
  insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by)
  values(p_institution_id,p_inventory_id,'sale',-p_length,'sale',result_id,coalesce(trim(p_notes),''),auth.uid());

  if p_driver_id is not null then
    insert into public.driver_trips(sale_id,institution_id,driver_id,seller_id,amount)
    values(result_id,p_institution_id,p_driver_id,p_seller_id,p_driver_fee);
  end if;
  return result_id;
end; $$;

revoke all on function public.record_operating_sale(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb) from public,anon;
grant execute on function public.record_operating_sale(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb) to authenticated;

create or replace function public.add_sale_payment(
  p_sale_id uuid,p_method text,p_amount numeric,p_reference text default ''
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare s public.sales%rowtype; inst public.institutions%rowtype; v_paid numeric; v_rate numeric:=0; v_fee numeric; result_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into s from public.sales where id=p_sale_id for update;
  if not found or s.status<>'completed' then raise exception 'Sale is not available'; end if;
  if s.seller_id<>auth.uid() and not public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]) then
    raise exception 'Insufficient permission';
  end if;
  if p_method not in ('cash','network','bank_transfer','visa','tamara','tabby','other') or p_amount<=0 then raise exception 'Invalid payment'; end if;
  select coalesce(sum(amount),0) into v_paid from public.sale_payments where sale_id=s.id;
  if round(v_paid+p_amount,2)>s.total then raise exception 'Payment exceeds remaining balance'; end if;
  select * into inst from public.institutions where id=s.institution_id;
  v_rate:=case p_method when 'visa' then inst.visa_fee_rate when 'tabby' then inst.tabby_fee_rate when 'tamara' then inst.tamara_fee_rate else 0 end;
  v_fee:=round(p_amount*v_rate,2);
  insert into public.sale_payments(institution_id,sale_id,method,amount,reference,fee_rate_snapshot,fee_amount,created_by)
  values(s.institution_id,s.id,p_method,p_amount,coalesce(trim(p_reference),''),v_rate,v_fee,auth.uid()) returning id into result_id;
  update public.sales set
    payment_fee=(select coalesce(sum(fee_amount),0) from public.sale_payments where sale_id=s.id),
    collection_status=case when round(v_paid+p_amount,2)=s.total then 'paid' else 'partial' end,
    customer_payment=case when (select count(*) from public.sale_payments where sale_id=s.id)>1 then 'split' else p_method end
  where id=s.id;
  return result_id;
end; $$;
revoke all on function public.add_sale_payment(uuid,text,numeric,text) from public,anon;
grant execute on function public.add_sale_payment(uuid,text,numeric,text) to authenticated;

create or replace function public.reverse_sale(p_sale_id uuid,p_reason text,p_returned boolean default false)
returns void language plpgsql security definer set search_path=public
as $$
declare s public.sales%rowtype; v_type text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into s from public.sales where id=p_sale_id for update;
  if not found or s.status<>'completed' then raise exception 'Sale is not reversible'; end if;
  if not public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Reason is required'; end if;
  v_type:=case when p_returned then 'sale_return' else 'sale_void' end;
  update public.inventory_items set remaining_length=remaining_length+s.length where id=s.inventory_id;
  insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by)
  values(s.institution_id,s.inventory_id,v_type,s.length,'sale',s.id,trim(p_reason),auth.uid());
  update public.sales set status=case when p_returned then 'returned' else 'voided' end,reversed_at=now(),reversed_by=auth.uid(),reverse_reason=trim(p_reason)
  where id=s.id;
end; $$;
revoke all on function public.reverse_sale(uuid,text,boolean) from public,anon;
grant execute on function public.reverse_sale(uuid,text,boolean) to authenticated;

create or replace function public.get_operating_report(
  p_institution_id uuid,p_from timestamptz,p_to timestamptz,p_seller_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare v_role public.institution_role; v_seller uuid; v_can_cost boolean; result jsonb;
begin
  if auth.uid() is null or not public.is_institution_member(p_institution_id) then raise exception 'Insufficient permission'; end if;
  select role into v_role from public.institution_memberships
  where institution_id=p_institution_id and user_id=auth.uid() and status='active';
  v_seller:=case when v_role='seller' then auth.uid() else p_seller_id end;
  v_can_cost:=v_role in ('owner','accountant');

  with scoped as (
    select s.*,i.name item_name,i.color,
      p.full_name seller_name,
      coalesce(dp.full_name,'') driver_name,
      coalesce((select sum(sa.quantity*sa.sale_unit_price) from public.sale_addons sa where sa.sale_id=s.id),0) addon_sales,
      coalesce((select sum(sa.quantity*sa.cost_unit_price) from public.sale_addons sa where sa.sale_id=s.id),0) addon_cost,
      coalesce((select sum(sp.amount) from public.sale_payments sp where sp.sale_id=s.id),0) paid_amount,
      coalesce((select sum(sp.fee_amount) from public.sale_payments sp where sp.sale_id=s.id),0) payment_fees,
      coalesce((select string_agg(sp.method||':'||to_char(sp.amount,'FM999999990.00'),', ' order by sp.paid_at) from public.sale_payments sp where sp.sale_id=s.id),'') payment_summary
    from public.sales s
    join public.inventory_items i on i.id=s.inventory_id
    join public.profiles p on p.id=s.seller_id
    left join public.profiles dp on dp.id=s.driver_id
    where s.institution_id=p_institution_id and s.created_at>=p_from and s.created_at<p_to
      and s.status='completed' and (v_seller is null or s.seller_id=v_seller)
  ), enriched as (
    select *,
      round(area*supplier_unit_cost_snapshot,2) merchandise_cost,
      round(area*supplier_unit_cost_snapshot+addon_cost+driver_fee+payment_fees,2) operating_cost,
      round(total-(area*supplier_unit_cost_snapshot+addon_cost+driver_fee+payment_fees),2) operating_profit
    from scoped
  )
  select jsonb_build_object(
    'summary',coalesce((select jsonb_build_object(
      'sales_amount',coalesce(sum(total),0),'length',coalesce(sum(length),0),'area',coalesce(sum(area),0),
      'sales_count',count(*),'merchandise_cost',case when v_can_cost then coalesce(sum(merchandise_cost),0) else null end,
      'driver_cost',coalesce(sum(driver_fee),0),'addon_cost',case when v_can_cost then coalesce(sum(addon_cost),0) else null end,
      'payment_fees',case when v_can_cost then coalesce(sum(payment_fees),0) else null end,
      'total_cost',case when v_can_cost then coalesce(sum(operating_cost),0) else null end,
      'gross_profit',case when v_can_cost then coalesce(sum(operating_profit),0) else null end,
      'seller_commission',coalesce(sum(seller_commission),0)
    ) from enriched),'{}'::jsonb),
    'payments',coalesce((select jsonb_agg(x order by x->>'method') from (
      select jsonb_build_object('method',sp.method,'amount',sum(sp.amount),'count',count(distinct sp.sale_id)) x
      from public.sale_payments sp join enriched e on e.id=sp.sale_id group by sp.method
    ) q),'[]'::jsonb),
    'sales',coalesce((select jsonb_agg(jsonb_build_object(
      'id',id,'created_at',created_at,'length',length,'area',area,'item',item_name,'color',color,
      'seller',seller_name,'driver',driver_name,'driver_cost',driver_fee,'sales_amount',total,
      'paid_amount',paid_amount,'collection_status',collection_status,'payments',payment_summary,
      'merchandise_cost',case when v_can_cost then merchandise_cost else null end,
      'addon_cost',case when v_can_cost then addon_cost else null end,
      'total_cost',case when v_can_cost then operating_cost else null end,
      'profit',case when v_can_cost then operating_profit else null end,
      'seller_commission',seller_commission,'notes',notes
    ) order by created_at desc) from enriched),'[]'::jsonb),
    'sellers',coalesce((select jsonb_agg(row_to_json(q)) from (
      select seller_id,seller_name,count(*) sales_count,sum(length) length,sum(area) area,sum(total) sales_amount,
        case when v_can_cost then sum(operating_cost) else null end total_cost,
        case when v_can_cost then sum(operating_profit) else null end profit,
        sum(seller_commission) commission
      from enriched group by seller_id,seller_name order by sum(total) desc
    ) q),'[]'::jsonb),
    'drivers',coalesce((select jsonb_agg(row_to_json(q)) from (
      select driver_id,driver_name,count(*) filter(where driver_id is not null) trips,sum(driver_fee) total
      from enriched where driver_id is not null group by driver_id,driver_name order by sum(driver_fee) desc
    ) q),'[]'::jsonb)
  ) into result;
  return result;
end; $$;
revoke all on function public.get_operating_report(uuid,timestamptz,timestamptz,uuid) from public,anon;
grant execute on function public.get_operating_report(uuid,timestamptz,timestamptz,uuid) to authenticated;
