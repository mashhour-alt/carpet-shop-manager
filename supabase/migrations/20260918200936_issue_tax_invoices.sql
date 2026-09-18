-- Optional tax invoices created from completed sales.
create table public.invoice_counters (
  institution_id uuid primary key references public.institutions(id) on delete cascade,
  next_number bigint not null default 1 check (next_number > 0)
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  sale_id uuid not null unique references public.sales(id),
  invoice_number bigint not null,
  seller_id uuid not null references public.profiles(id),
  customer_name text not null,
  customer_commercial_registration text not null default '',
  customer_tax_number text not null default '',
  item_name text not null,
  color text not null,
  length numeric(12,3) not null check (length > 0),
  width numeric(5,2) not null default 4 check (width = 4),
  area numeric(14,3) not null check (area > 0),
  price_per_sqm numeric(12,2) not null check (price_per_sqm >= 0),
  carpet_amount numeric(14,2) not null check (carpet_amount >= 0),
  installation_amount numeric(12,2) not null default 0,
  glue_gallons numeric(12,3) not null default 0,
  glue_amount numeric(12,2) not null default 0,
  iron_pieces numeric(12,3) not null default 0,
  iron_amount numeric(12,2) not null default 0,
  driver_fee numeric(12,2) not null default 0,
  payment_method public.customer_payment_method not null,
  subtotal numeric(14,2) not null check (subtotal >= 0),
  vat_rate numeric(5,4) not null default .15 check (vat_rate = .15),
  vat_amount numeric(14,2) not null check (vat_amount >= 0),
  total_with_vat numeric(14,2) not null check (total_with_vat >= 0),
  issued_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id),
  unique (institution_id, invoice_number)
);

create index invoices_institution_issued_idx on public.invoices(institution_id, issued_at desc);
create index invoices_seller_issued_idx on public.invoices(seller_id, issued_at desc);
create index invoices_created_by_idx on public.invoices(created_by);

alter table public.invoice_counters enable row level security;
alter table public.invoices enable row level security;

revoke all on table public.invoice_counters, public.invoices from anon, authenticated;
grant select on table public.invoices to authenticated;
grant all on table public.invoice_counters, public.invoices to service_role;

create policy invoices_read on public.invoices for select to authenticated using (
  seller_id = (select auth.uid()) or
  public.has_institution_role(institution_id, array['owner','accountant']::public.institution_role[])
);

create or replace function public.issue_tax_invoice(
  p_sale_id uuid,
  p_customer_name text default '',
  p_customer_cr text default '',
  p_customer_tax text default ''
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  sale_row public.sales%rowtype;
  item_row public.inventory_items%rowtype;
  result_id uuid;
  next_no bigint;
  carpet_total numeric;
  vat_total numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select * into sale_row from public.sales where id = p_sale_id for update;
  if not found then raise exception 'Sale was not found'; end if;
  if sale_row.seller_id <> auth.uid() and
     not public.has_institution_role(sale_row.institution_id, array['owner','accountant']::public.institution_role[]) then
    raise exception 'Insufficient permission';
  end if;

  select id into result_id from public.invoices where sale_id = p_sale_id;
  if found then return result_id; end if;

  select * into item_row from public.inventory_items where id = sale_row.inventory_id;
  if not found then raise exception 'Inventory item was not found'; end if;

  insert into public.invoice_counters(institution_id,next_number)
  values(sale_row.institution_id,1)
  on conflict(institution_id) do nothing;
  select next_number into next_no from public.invoice_counters
  where institution_id = sale_row.institution_id for update;
  update public.invoice_counters set next_number = next_number + 1
  where institution_id = sale_row.institution_id;

  carpet_total := round(sale_row.area * sale_row.sale_price_per_sqm, 2);
  vat_total := round(sale_row.total * .15, 2);
  insert into public.invoices(
    institution_id,sale_id,invoice_number,seller_id,customer_name,
    customer_commercial_registration,customer_tax_number,item_name,color,length,width,area,
    price_per_sqm,carpet_amount,installation_amount,glue_gallons,glue_amount,
    iron_pieces,iron_amount,driver_fee,payment_method,subtotal,vat_amount,total_with_vat,created_by
  ) values (
    sale_row.institution_id,sale_row.id,next_no,sale_row.seller_id,
    coalesce(nullif(trim(p_customer_name),''),nullif(trim(sale_row.customer_name),''),'عميل نقدي'),
    trim(coalesce(p_customer_cr,'')),trim(coalesce(p_customer_tax,'')),item_row.name,item_row.color,
    sale_row.length,sale_row.width,sale_row.area,sale_row.sale_price_per_sqm,carpet_total,
    sale_row.installation_amount,sale_row.glue_gallons,sale_row.glue_amount,
    sale_row.iron_pieces,sale_row.iron_amount,sale_row.driver_fee,sale_row.customer_payment,
    sale_row.total,vat_total,sale_row.total+vat_total,auth.uid()
  ) returning id into result_id;
  return result_id;
end; $$;

revoke all on function public.issue_tax_invoice(uuid,text,text,text) from public, anon;
grant execute on function public.issue_tax_invoice(uuid,text,text,text) to authenticated;
