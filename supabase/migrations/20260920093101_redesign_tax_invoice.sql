-- Extend issued invoice snapshots for the Saudi tax invoice layout.
alter table public.invoices
  add column invoice_kind text not null default 'simplified'
    check (invoice_kind in ('simplified', 'tax')),
  add column customer_address text not null default '',
  add column seller_name text not null default '',
  add column discount_amount numeric(14,2) not null default 0
    check (discount_amount >= 0),
  add column taxable_amount numeric(14,2) not null default 0
    check (taxable_amount >= 0);

update public.invoices i
set seller_name = coalesce(nullif(trim(p.full_name), ''), 'بائع'),
    taxable_amount = greatest(i.subtotal - i.discount_amount, 0)
from public.profiles p
where p.id = i.seller_id;

drop function if exists public.issue_tax_invoice(uuid,text,text,text);

create function public.issue_tax_invoice(
  p_sale_id uuid,
  p_customer_name text default '',
  p_customer_cr text default '',
  p_customer_tax text default '',
  p_customer_address text default '',
  p_invoice_kind text default 'simplified',
  p_discount numeric default 0
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  sale_row public.sales%rowtype;
  item_row public.inventory_items%rowtype;
  seller_row public.profiles%rowtype;
  result_id uuid;
  next_no bigint;
  carpet_total numeric;
  taxable_total numeric;
  vat_total numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_invoice_kind not in ('simplified', 'tax') then
    raise exception 'Invalid invoice kind';
  end if;

  select * into sale_row from public.sales where id = p_sale_id for update;
  if not found then raise exception 'Sale was not found'; end if;
  if sale_row.seller_id <> auth.uid() and
     not public.has_institution_role(
       sale_row.institution_id,
       array['owner','accountant']::public.institution_role[]
     ) then
    raise exception 'Insufficient permission';
  end if;

  select id into result_id from public.invoices where sale_id = p_sale_id;
  if found then return result_id; end if;

  select * into item_row from public.inventory_items where id = sale_row.inventory_id;
  if not found then raise exception 'Inventory item was not found'; end if;
  select * into seller_row from public.profiles where id = sale_row.seller_id;
  if not found then raise exception 'Seller was not found'; end if;

  if coalesce(p_discount, 0) < 0 or coalesce(p_discount, 0) > sale_row.total then
    raise exception 'Discount must be between zero and the sale subtotal';
  end if;
  if p_invoice_kind = 'tax' and (
    nullif(trim(coalesce(p_customer_name, '')), '') is null or
    nullif(trim(coalesce(p_customer_tax, '')), '') is null or
    nullif(trim(coalesce(p_customer_address, '')), '') is null
  ) then
    raise exception 'Buyer name, VAT number and address are required for a tax invoice';
  end if;

  insert into public.invoice_counters(institution_id,next_number)
  values(sale_row.institution_id,1)
  on conflict(institution_id) do nothing;
  select next_number into next_no from public.invoice_counters
  where institution_id = sale_row.institution_id for update;
  update public.invoice_counters set next_number = next_number + 1
  where institution_id = sale_row.institution_id;

  carpet_total := round(sale_row.area * sale_row.sale_price_per_sqm, 2);
  taxable_total := round(sale_row.total - coalesce(p_discount, 0), 2);
  vat_total := round(taxable_total * .15, 2);

  insert into public.invoices(
    institution_id,sale_id,invoice_number,invoice_kind,seller_id,seller_name,
    customer_name,customer_commercial_registration,customer_tax_number,customer_address,
    item_name,color,length,width,area,price_per_sqm,carpet_amount,installation_amount,
    glue_gallons,glue_amount,iron_pieces,iron_amount,driver_fee,payment_method,
    subtotal,discount_amount,taxable_amount,vat_amount,total_with_vat,created_by
  ) values (
    sale_row.institution_id,sale_row.id,next_no,p_invoice_kind,sale_row.seller_id,
    coalesce(nullif(trim(seller_row.full_name),''),'بائع'),
    coalesce(nullif(trim(p_customer_name),''),nullif(trim(sale_row.customer_name),''),'عميل نقدي'),
    trim(coalesce(p_customer_cr,'')),trim(coalesce(p_customer_tax,'')),
    trim(coalesce(p_customer_address,'')),item_row.name,item_row.color,
    sale_row.length,sale_row.width,sale_row.area,sale_row.sale_price_per_sqm,carpet_total,
    sale_row.installation_amount,sale_row.glue_gallons,sale_row.glue_amount,
    sale_row.iron_pieces,sale_row.iron_amount,sale_row.driver_fee,sale_row.customer_payment,
    sale_row.total,round(coalesce(p_discount,0),2),taxable_total,vat_total,
    taxable_total+vat_total,auth.uid()
  ) returning id into result_id;
  return result_id;
end; $$;

revoke all on function public.issue_tax_invoice(uuid,text,text,text,text,text,numeric)
  from public, anon;
grant execute on function public.issue_tax_invoice(uuid,text,text,text,text,text,numeric)
  to authenticated;
