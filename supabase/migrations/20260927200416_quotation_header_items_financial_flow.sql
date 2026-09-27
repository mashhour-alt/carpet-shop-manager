-- Repair quotation RPC drift without changing historical quotations, sales, or invoices.
-- A quotation is a header plus quotation_items; inventory_id belongs only to each item.
-- Quotations remain non-reserving and do not create invoice/ZATCA artifacts.

alter table public.quotations
  add column if not exists discount_amount numeric(12,2) not null default 0
    check (discount_amount >= 0),
  add column if not exists addons jsonb not null default '[]'::jsonb
    check (jsonb_typeof(addons) = 'array');

create or replace function public.create_quotation_v2(
  p_institution_id uuid,
  p_seller_id uuid,
  p_inventory_id uuid,
  p_customer_name text,
  p_customer_cr text,
  p_customer_tax text,
  p_length numeric,
  p_price_per_sqm numeric,
  p_valid_until date,
  p_notes text default '',
  p_addons jsonb default '[]'::jsonb,
  p_discount numeric default 0
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  inv public.inventory_items%rowtype;
  addon jsonb;
  addon_type public.addon_types%rowtype;
  result_id uuid;
  normalized_addons jsonb := '[]'::jsonb;
  v_area numeric;
  v_addon_total numeric := 0;
  v_quantity numeric;
  v_sale_unit_price numeric;
  v_subtotal numeric;
  v_discount numeric := round(coalesce(p_discount, 0), 2);
  v_vat numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if trim(coalesce(p_customer_name,'')) = '' or p_length <= 0 or p_price_per_sqm < 0 then
    raise exception 'Invalid quotation data';
  end if;
  if p_valid_until < current_date then raise exception 'Quotation expiry cannot be in the past'; end if;
  if jsonb_typeof(coalesce(p_addons, '[]'::jsonb)) <> 'array' then
    raise exception 'Quotation add-ons must be an array';
  end if;

  select * into inv from public.inventory_items
  where id = p_inventory_id and institution_id = p_institution_id;
  if not found then raise exception 'Inventory not found'; end if;
  if not public.can_manage_branch(inv.branch_id, 'sell') then
    raise exception 'Insufficient branch permission';
  end if;
  if auth.uid() <> p_seller_id and not public.has_institution_role(
    p_institution_id, array['owner']::public.institution_role[]
  ) then raise exception 'Seller mismatch'; end if;
  if not exists (
    select 1 from public.institution_memberships
    where institution_id = p_institution_id and user_id = p_seller_id
      and role = 'seller' and status = 'active'
  ) then raise exception 'Seller is not active'; end if;

  v_area := round(p_length * 4, 3);
  for addon in select value from jsonb_array_elements(coalesce(p_addons, '[]'::jsonb)) loop
    select * into addon_type from public.addon_types
    where id = nullif(addon->>'addon_type_id','')::uuid
      and institution_id = p_institution_id and is_active and behavior = 'customer_addon';
    if not found then raise exception 'Add-on unavailable'; end if;
    v_quantity := case when addon_type.calculation_basis = 'sale_area'
      then v_area else coalesce((addon->>'quantity')::numeric, 0) end;
    v_sale_unit_price := coalesce((addon->>'sale_unit_price')::numeric, 0);
    if v_quantity <= 0 or v_sale_unit_price < 0 then raise exception 'Invalid add-on values'; end if;
    normalized_addons := normalized_addons || jsonb_build_array(jsonb_build_object(
      'addon_type_id', addon_type.id,
      'name', addon_type.name,
      'unit', addon_type.unit,
      'quantity', v_quantity,
      'sale_unit_price', v_sale_unit_price,
      'cost_unit_price', addon_type.default_cost_price,
      'supplier_id', addon_type.supplier_id
    ));
    v_addon_total := v_addon_total + round(v_quantity * v_sale_unit_price, 2);
  end loop;

  v_subtotal := round(v_area * p_price_per_sqm + v_addon_total, 2);
  if v_discount < 0 or v_discount > v_subtotal then raise exception 'Invalid discount'; end if;
  v_subtotal := round(v_subtotal - v_discount, 2);
  v_vat := round(v_subtotal * .15, 2);

  insert into public.quotations(
    institution_id, branch_id, seller_id, customer_name,
    customer_commercial_registration, customer_tax_number, valid_until, notes,
    subtotal, discount_amount, vat_amount, total, addons, created_by
  ) values (
    p_institution_id, inv.branch_id, p_seller_id, trim(p_customer_name),
    trim(coalesce(p_customer_cr,'')), trim(coalesce(p_customer_tax,'')), p_valid_until,
    trim(coalesce(p_notes,'')), v_subtotal, v_discount, v_vat, v_subtotal + v_vat,
    normalized_addons, auth.uid()
  ) returning id into result_id;

  insert into public.quotation_items(
    quotation_id, inventory_id, item_name, color, length, width, area,
    price_per_sqm, line_total
  ) values (
    result_id, inv.id, inv.name, inv.color, p_length, 4, v_area,
    p_price_per_sqm, round(v_area * p_price_per_sqm, 2)
  );
  return result_id;
end $$;

-- Keep the existing Flutter RPC signature available while routing it to the
-- header/items implementation. This is the direct repair for the 42703 error.
create or replace function public.create_quotation(
  p_institution_id uuid, p_seller_id uuid, p_inventory_id uuid,
  p_customer_name text, p_customer_cr text, p_customer_tax text,
  p_length numeric, p_price_per_sqm numeric, p_valid_until date,
  p_notes text default ''
) returns uuid
language sql security definer set search_path=public as $$
  select public.create_quotation_v2(
    p_institution_id, p_seller_id, p_inventory_id, p_customer_name, p_customer_cr,
    p_customer_tax, p_length, p_price_per_sqm, p_valid_until, p_notes,
    '[]'::jsonb, 0
  )
$$;

create or replace function public.convert_quotation_to_sale(
  p_quotation_id uuid,
  p_payment_method public.customer_payment_method
) returns uuid[]
language plpgsql security definer set search_path=public as $$
declare
  q public.quotations%rowtype;
  qi public.quotation_items%rowtype;
  sale_id uuid;
begin
  select * into q from public.quotations where id = p_quotation_id for update;
  if not found then raise exception 'Quotation was not found'; end if;
  if q.status <> 'draft' then raise exception 'Quotation is not available for conversion'; end if;
  if not public.has_institution_role(q.institution_id, array['owner','seller']::public.institution_role[]) then
    raise exception 'Only owners and sellers can convert a quotation';
  end if;
  if auth.uid() <> q.seller_id and not public.has_institution_role(
    q.institution_id, array['owner']::public.institution_role[]
  ) then raise exception 'Seller mismatch'; end if;

  select * into qi from public.quotation_items
  where quotation_id = q.id order by id limit 1;
  if not found then raise exception 'Quotation has no inventory item'; end if;
  if exists (select 1 from public.quotation_items where quotation_id = q.id offset 1) then
    raise exception 'Multi-item legacy quotations require separate sales';
  end if;

  sale_id := public.record_sale_financial_v2(
    q.institution_id, qi.inventory_id, q.seller_id, null, q.customer_name,
    qi.length, qi.price_per_sqm, 0,
    trim(coalesce(q.notes,'')) || case when q.customer_commercial_registration <> ''
      then E'\nQuotation CR: ' || q.customer_commercial_registration else '' end ||
      case when q.customer_tax_number <> '' then E'\nQuotation Tax: ' || q.customer_tax_number else '' end,
    jsonb_build_array(jsonb_build_object('method', p_payment_method::text, 'amount', q.total, 'reference', 'quotation:' || q.id::text)),
    q.addons, q.discount_amount
  );
  insert into public.quotation_sales(quotation_id, sale_id) values (q.id, sale_id);
  update public.quotations set status = 'converted', converted_at = now() where id = q.id;
  return array[sale_id];
end $$;

revoke all on function public.create_quotation_v2(uuid,uuid,uuid,text,text,text,numeric,numeric,date,text,jsonb,numeric) from public, anon;
grant execute on function public.create_quotation_v2(uuid,uuid,uuid,text,text,text,numeric,numeric,date,text,jsonb,numeric) to authenticated;
revoke all on function public.create_quotation(uuid,uuid,uuid,text,text,text,numeric,numeric,date,text) from public, anon;
grant execute on function public.create_quotation(uuid,uuid,uuid,text,text,text,numeric,numeric,date,text) to authenticated;
revoke all on function public.convert_quotation_to_sale(uuid,public.customer_payment_method) from public, anon;
grant execute on function public.convert_quotation_to_sale(uuid,public.customer_payment_method) to authenticated;
