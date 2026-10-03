-- Materials only: use persisted sale quantities without changing pricing or units.
-- Existing unique index addon_movements_sale_source_once is the final backstop.
-- No historical stock backfill: only newly completed canonical sales consume stock.
create or replace function private.consume_sale_materials(p_sale_id uuid)
returns void language plpgsql set search_path=public as $$
declare
  s public.sales%rowtype;
  a record;
  movement_id uuid;
begin
  select * into s from public.sales where id=p_sale_id for update;
  if not found or s.status<>'completed' then
    raise exception 'Completed sale required for material consumption';
  end if;
  -- Lock each material in stable order; aggregate repeated lines to one movement.
  for a in
    select at.id, at.track_stock, at.name,
      sum(sa.quantity) as quantity,
      round(sum(sa.quantity*sa.cost_unit_price)/sum(sa.quantity),2) as unit_cost
    from public.sale_addons sa join public.addon_types at
      on at.id=sa.addon_type_id and at.institution_id=s.institution_id
    where sa.sale_id=s.id and sa.institution_id=s.institution_id
    group by at.id order by at.id
  loop
    perform 1 from public.addon_types where id=a.id for update;
    if not (select track_stock from public.addon_types where id=a.id) then continue; end if;
    insert into public.addon_movements(
      institution_id,branch_id,addon_type_id,seller_id,sale_id,movement_type,
      quantity_delta,unit_cost_snapshot,note,created_by
    ) values (
      s.institution_id,s.branch_id,a.id,s.seller_id,s.id,'sale',
      -a.quantity,a.unit_cost,'Sale material consumption',auth.uid()
    ) on conflict (addon_type_id,sale_id,movement_type)
      where sale_id is not null and movement_type in ('sale','sale_void')
      do nothing returning id into movement_id;
    if movement_id is not null then
      update public.addon_types set stock_quantity=stock_quantity-a.quantity
        where id=a.id and institution_id=s.institution_id and stock_quantity>=a.quantity;
      if not found then raise exception 'Insufficient add-on stock: %',a.name; end if;
    end if;
  end loop;
end $$;
-- Internal-only helper: invoked with the existing canonical function's authority.
revoke all on function private.consume_sale_materials(uuid) from public,anon,authenticated;

create or replace function public.record_sale_financial_v2(
  p_institution_id uuid,
  p_inventory_id uuid,
  p_seller_id uuid,
  p_driver_id uuid,
  p_customer_name text,
  p_length numeric,
  p_sale_price numeric,
  p_driver_fee numeric,
  p_notes text,
  p_payments jsonb,
  p_addons jsonb default '[]'::jsonb,
  p_discount numeric default 0
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  gross numeric:=0;
  discount numeric:=round(coalesce(p_discount,0),2);
  taxable numeric;
  vat numeric;
  payable numeric;
  paid numeric:=0;
  legacy_payments jsonb;
  rid uuid;
  payment jsonb;
  inst public.institutions%rowtype;
  fee numeric:=0;
  rate numeric;
  carpet_gross numeric;
  carpet_discount numeric;
  merchandise_wholesale numeric;
  commission_rate numeric;
  calculated_seller_profit numeric;
begin
  select round(
    p_length*4*p_sale_price +
    coalesce(sum(round(coalesce((x->>'quantity')::numeric,0)*coalesce((x->>'sale_unit_price')::numeric,0),2)),0),
    2
  ) into gross
  from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) x;

  if discount<0 or discount>gross then raise exception 'Invalid discount'; end if;
  taxable:=round(gross-discount,2);
  vat:=round(taxable*.15,2);
  payable:=taxable+vat;

  select coalesce(sum((x->>'amount')::numeric),0) into paid
  from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) x;
  if round(paid,2)<>payable then
    raise exception 'Payments must equal canonical payable amount including VAT';
  end if;

  legacy_payments:=jsonb_build_array(jsonb_build_object(
    'method','other','amount',gross,'reference','canonical-sale-bootstrap'
  ));
  rid:=public.record_sale_v2(
    p_institution_id,p_inventory_id,p_seller_id,p_driver_id,p_customer_name,
    p_length,p_sale_price,p_driver_fee,p_notes,legacy_payments,p_addons
  );

  delete from public.sale_payments where sale_id=rid;
  select * into inst from public.institutions where id=p_institution_id;
  for payment in select value from jsonb_array_elements(p_payments) loop
    rate:=case payment->>'method'
      when 'visa' then inst.visa_fee_rate
      when 'tabby' then inst.tabby_fee_rate
      when 'tamara' then inst.tamara_fee_rate
      else 0
    end;
    insert into public.sale_payments(
      institution_id,sale_id,method,amount,reference,
      fee_rate_snapshot,fee_amount,created_by
    ) values (
      p_institution_id,rid,payment->>'method',(payment->>'amount')::numeric,
      coalesce(payment->>'reference',''),rate,
      round((payment->>'amount')::numeric*rate,2),auth.uid()
    );
    fee:=fee+round((payment->>'amount')::numeric*rate,2);
  end loop;

  select round(s.area*s.wholesale_price_snapshot,2),coalesce(m.commission_rate,0)
    into merchandise_wholesale,commission_rate
  from public.sales s
  left join public.institution_memberships m
    on m.institution_id=s.institution_id and m.user_id=s.seller_id
      and m.role='seller' and m.status='active'
  where s.id=rid;

  carpet_gross:=round(p_length*4*p_sale_price,2);
  carpet_discount:=case when gross=0 then 0
    else round(discount*carpet_gross/gross,2) end;
  calculated_seller_profit:=round(greatest(
    carpet_gross-carpet_discount-coalesce(merchandise_wholesale,0),0
  ),2);

  update public.sales set
    financial_snapshot_version=2,
    currency_code='SAR',
    tax_category='S',
    vat_rate=.15,
    line_extension_amount=gross,
    discount_amount=discount,
    tax_exclusive_amount=taxable,
    vat_amount=vat,
    tax_inclusive_amount=payable,
    payable_amount=payable,
    payment_fee=fee,
    seller_profit=calculated_seller_profit,
    seller_commission=round(calculated_seller_profit*commission_rate,2),
    customer_payment=coalesce((p_payments->0->>'method'),'other')
  where id=rid;
  perform private.consume_sale_materials(rid);
  return rid;
end $$;
revoke all on function public.record_sale_financial_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb,numeric) from public,anon;
grant execute on function public.record_sale_financial_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb,numeric) to authenticated;

create or replace function public.void_sale(p_sale_id uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$
declare s public.sales%rowtype; a record; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if; select * into s from public.sales where id=p_sale_id for update; if not found then raise exception 'Sale was not found'; end if;
 if not public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if; if s.status='voided' then return; end if; if s.status<>'completed' then raise exception 'Only completed sales can be voided'; end if; if exists(select 1 from public.invoices where sale_id=s.id) then raise exception 'Issued invoice must be handled before voiding the sale'; end if;
 update public.inventory_items set remaining_length=remaining_length+s.length where id=s.inventory_id; insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by) values(s.institution_id,s.inventory_id,'sale_void',s.length,'sale',s.id,coalesce(trim(p_reason),''),auth.uid());
 -- Reverse only recorded deductions, even if tracking was subsequently disabled.
 -- Legacy sales without a sale movement must not manufacture stock on cancellation.
 for a in select * from public.addon_movements
   where sale_id=s.id and institution_id=s.institution_id and movement_type='sale'
   order by addon_type_id
 loop
   perform 1 from public.addon_types where id=a.addon_type_id for update;
   insert into public.addon_movements(
     institution_id,branch_id,addon_type_id,seller_id,sale_id,movement_type,
     quantity_delta,unit_cost_snapshot,note,created_by
   ) values (
     s.institution_id,s.branch_id,a.addon_type_id,s.seller_id,s.id,'sale_void',
     -a.quantity_delta,a.unit_cost_snapshot,coalesce(trim(p_reason),''),auth.uid()
   ) on conflict (addon_type_id,sale_id,movement_type)
     where sale_id is not null and movement_type in ('sale','sale_void') do nothing;
   if found then
     update public.addon_types set stock_quantity=stock_quantity-a.quantity_delta
       where id=a.addon_type_id and institution_id=s.institution_id;
   end if;
 end loop;
 update public.sales set status='voided',reversed_at=now(),reversed_by=auth.uid(),reverse_reason=coalesce(trim(p_reason),'') where id=s.id;
end; $$;
revoke all on function public.void_sale(uuid,text) from public,anon;grant execute on function public.void_sale(uuid,text) to authenticated;
