-- Farsha quotation lifecycle. Quotations never reserve or deduct stock.
create type public.quotation_status as enum ('draft', 'converted', 'cancelled', 'expired');

create table public.quotations (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  seller_id uuid not null references public.profiles(id),
  customer_name text not null,
  customer_commercial_registration text not null default '',
  customer_tax_number text not null default '',
  issue_date date not null default current_date,
  valid_until date not null default (current_date + 14),
  notes text not null default '',
  subtotal numeric(12,2) not null check (subtotal >= 0),
  vat_rate numeric(5,4) not null default .15 check (vat_rate = .15),
  vat_amount numeric(12,2) not null check (vat_amount >= 0),
  total numeric(12,2) not null check (total >= 0),
  status public.quotation_status not null default 'draft',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  converted_at timestamptz
);

create table public.quotation_items (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.quotations(id) on delete cascade,
  inventory_id uuid not null references public.inventory_items(id),
  item_name text not null,
  color text not null,
  length numeric(12,3) not null check (length > 0),
  width numeric(12,3) not null default 4 check (width = 4),
  area numeric(12,3) not null check (area > 0),
  price_per_sqm numeric(12,2) not null check (price_per_sqm >= 0),
  line_total numeric(12,2) not null check (line_total >= 0)
);

create table public.quotation_sales (
  quotation_id uuid not null references public.quotations(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  primary key (quotation_id, sale_id)
);

create index quotations_institution_created_idx on public.quotations(institution_id, created_at desc);
create index quotations_seller_created_idx on public.quotations(seller_id, created_at desc);
create index quotation_items_quote_idx on public.quotation_items(quotation_id);
create index quotation_items_inventory_idx on public.quotation_items(inventory_id);
create index quotation_sales_sale_idx on public.quotation_sales(sale_id);

alter table public.quotations enable row level security;
alter table public.quotation_items enable row level security;
alter table public.quotation_sales enable row level security;

revoke all on table public.quotations, public.quotation_items, public.quotation_sales from anon, authenticated;
grant select on table public.quotations, public.quotation_items, public.quotation_sales to authenticated;
grant all on table public.quotations, public.quotation_items, public.quotation_sales to service_role;

create policy quotations_read on public.quotations for select to authenticated using (
  seller_id = (select auth.uid()) or
  public.has_institution_role(institution_id, array['owner','accountant']::public.institution_role[])
);
create policy quotation_items_read on public.quotation_items for select to authenticated using (
  exists (select 1 from public.quotations q where q.id = quotation_items.quotation_id and (
    q.seller_id = (select auth.uid()) or
    public.has_institution_role(q.institution_id, array['owner','accountant']::public.institution_role[])
  ))
);
create policy quotation_sales_read on public.quotation_sales for select to authenticated using (
  exists (select 1 from public.quotations q where q.id = quotation_sales.quotation_id and (
    q.seller_id = (select auth.uid()) or
    public.has_institution_role(q.institution_id, array['owner','accountant']::public.institution_role[])
  ))
);

create or replace function public.create_quotation(
  p_institution_id uuid,
  p_seller_id uuid,
  p_inventory_id uuid,
  p_customer_name text,
  p_customer_cr text,
  p_customer_tax text,
  p_length numeric,
  p_price_per_sqm numeric,
  p_valid_until date,
  p_notes text default ''
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  item public.inventory_items%rowtype;
  result_id uuid;
  v_area numeric;
  v_subtotal numeric;
  v_vat numeric;
begin
  if not public.has_institution_role(p_institution_id, array['owner','accountant','seller']::public.institution_role[]) then
    raise exception 'Insufficient permission';
  end if;
  if auth.uid() <> p_seller_id and not public.has_institution_role(p_institution_id, array['owner','accountant']::public.institution_role[]) then
    raise exception 'Seller mismatch';
  end if;
  if not exists(select 1 from public.institution_memberships where institution_id=p_institution_id and user_id=p_seller_id and role='seller' and status='active') then
    raise exception 'Seller is not active';
  end if;
  if trim(coalesce(p_customer_name,'')) = '' or p_length <= 0 or p_price_per_sqm < 0 then
    raise exception 'Invalid quotation data';
  end if;
  select * into item from public.inventory_items where id=p_inventory_id and institution_id=p_institution_id;
  if not found then raise exception 'Inventory item was not found'; end if;
  v_area := p_length * 4;
  v_subtotal := round(v_area * p_price_per_sqm, 2);
  v_vat := round(v_subtotal * .15, 2);
  insert into public.quotations(institution_id,seller_id,customer_name,customer_commercial_registration,
    customer_tax_number,valid_until,notes,subtotal,vat_amount,total,created_by)
  values(p_institution_id,p_seller_id,trim(p_customer_name),trim(coalesce(p_customer_cr,'')),
    trim(coalesce(p_customer_tax,'')),p_valid_until,trim(coalesce(p_notes,'')),v_subtotal,v_vat,v_subtotal+v_vat,auth.uid())
  returning id into result_id;
  insert into public.quotation_items(quotation_id,inventory_id,item_name,color,length,area,price_per_sqm,line_total)
  values(result_id,item.id,item.name,item.color,p_length,v_area,p_price_per_sqm,v_subtotal);
  return result_id;
end; $$;

create or replace function public.convert_quotation_to_sale(
  p_quotation_id uuid,
  p_payment_method public.customer_payment_method
) returns uuid[]
language plpgsql security definer set search_path = public
as $$
declare
  q public.quotations%rowtype;
  qi public.quotation_items%rowtype;
  sale_id uuid;
  sale_ids uuid[] := array[]::uuid[];
begin
  select * into q from public.quotations where id=p_quotation_id for update;
  if not found then raise exception 'Quotation was not found'; end if;
  if q.status <> 'draft' then raise exception 'Quotation is not available for conversion'; end if;
  if not public.has_institution_role(q.institution_id, array['owner','seller']::public.institution_role[]) then
    raise exception 'Only owners and sellers can convert a quotation';
  end if;
  if auth.uid() <> q.seller_id and not public.has_institution_role(q.institution_id, array['owner']::public.institution_role[]) then
    raise exception 'Seller mismatch';
  end if;
  for qi in select * from public.quotation_items where quotation_id=q.id order by id loop
    sale_id := public.record_sale(q.institution_id, qi.inventory_id, q.seller_id, null, q.customer_name,
      qi.length, qi.price_per_sqm, 0, null, 0, 0, null, 0, 0, 0, p_payment_method);
    insert into public.quotation_sales(quotation_id,sale_id) values(q.id,sale_id);
    sale_ids := array_append(sale_ids,sale_id);
  end loop;
  update public.quotations set status='converted',converted_at=now() where id=q.id;
  return sale_ids;
end; $$;

revoke all on function public.create_quotation(uuid,uuid,uuid,text,text,text,numeric,numeric,date,text) from public, anon;
revoke all on function public.convert_quotation_to_sale(uuid,public.customer_payment_method) from public, anon;
grant execute on function public.create_quotation(uuid,uuid,uuid,text,text,text,numeric,numeric,date,text) to authenticated;
grant execute on function public.convert_quotation_to_sale(uuid,public.customer_payment_method) to authenticated;
