alter table public.sales add column glue_supplier_id uuid references public.suppliers(id);
alter table public.sales add column iron_supplier_id uuid references public.suppliers(id);
create index sales_glue_supplier_idx on public.sales(glue_supplier_id) where glue_supplier_id is not null;
create index sales_iron_supplier_idx on public.sales(iron_supplier_id) where iron_supplier_id is not null;

drop function public.record_sale(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,public.customer_payment_method);

create function public.record_sale(p_institution_id uuid,p_inventory_id uuid,p_seller_id uuid,p_driver_id uuid,
  p_customer_name text,p_length numeric,p_sale_price numeric,p_installation numeric,
  p_glue_supplier_id uuid,p_glue_gallons numeric,p_glue_amount numeric,
  p_iron_supplier_id uuid,p_iron_pieces numeric,p_iron_amount numeric,
  p_driver_fee numeric,p_customer_payment public.customer_payment_method) returns uuid
language plpgsql security definer set search_path=public
as $$ declare item public.inventory_items%rowtype; inst public.institutions%rowtype; seller public.institution_memberships%rowtype;
  result_id uuid; v_area numeric; v_rate numeric:=0; v_fee numeric; v_profit numeric; v_commission numeric; v_total numeric; begin
  if not public.has_institution_role(p_institution_id,array['owner','seller']::public.institution_role[]) then raise exception 'Only owners and sellers can record a sale'; end if;
  if auth.uid()<>p_seller_id and not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then raise exception 'Seller mismatch'; end if;
  if p_length<=0 or p_sale_price<0 or p_installation<0 or p_glue_gallons<0 or p_glue_amount<0 or p_iron_pieces<0 or p_iron_amount<0 or p_driver_fee<0 then raise exception 'Invalid sale values'; end if;
  select * into item from public.inventory_items where id=p_inventory_id and institution_id=p_institution_id for update;
  if not found or item.remaining_length<p_length then raise exception 'Requested length is unavailable'; end if;
  select * into seller from public.institution_memberships where institution_id=p_institution_id and user_id=p_seller_id and role='seller' and status='active';
  if not found then raise exception 'Seller is not active'; end if;
  if p_driver_id is not null and not exists(select 1 from public.institution_driver_connections where institution_id=p_institution_id and driver_id=p_driver_id and status='active') then raise exception 'Driver is not connected to this institution'; end if;
  if p_glue_gallons>0 and (p_glue_supplier_id is null or not exists(select 1 from public.suppliers where id=p_glue_supplier_id and institution_id=p_institution_id)) then raise exception 'Glue supplier is required'; end if;
  if p_iron_pieces>0 and (p_iron_supplier_id is null or not exists(select 1 from public.suppliers where id=p_iron_supplier_id and institution_id=p_institution_id)) then raise exception 'Iron supplier is required'; end if;
  select * into inst from public.institutions where id=p_institution_id;
  v_area:=p_length*4; v_total:=v_area*p_sale_price+p_installation+p_glue_amount+p_iron_amount+p_driver_fee;
  v_rate:=case p_customer_payment when 'visa' then inst.visa_fee_rate when 'tabby' then inst.tabby_fee_rate when 'tamara' then inst.tamara_fee_rate else 0 end;
  v_fee:=v_total*v_rate; v_profit:=(p_sale_price-item.wholesale_price)*v_area; v_commission:=greatest(v_profit,0)*seller.commission_rate;
  insert into public.sales(institution_id,inventory_id,seller_id,driver_id,customer_name,length,area,sale_price_per_sqm,
    wholesale_price_snapshot,installation_amount,glue_supplier_id,glue_gallons,glue_amount,iron_supplier_id,iron_pieces,iron_amount,
    driver_fee,customer_payment,payment_fee,seller_profit,seller_commission,total)
  values(p_institution_id,p_inventory_id,p_seller_id,p_driver_id,coalesce(trim(p_customer_name),''),p_length,v_area,p_sale_price,
    item.wholesale_price,p_installation,p_glue_supplier_id,p_glue_gallons,p_glue_amount,p_iron_supplier_id,p_iron_pieces,p_iron_amount,
    p_driver_fee,p_customer_payment,v_fee,v_profit,v_commission,v_total) returning id into result_id;
  update public.inventory_items set remaining_length=remaining_length-p_length,last_sold_at=now() where id=p_inventory_id;
  if p_driver_id is not null then insert into public.driver_trips(sale_id,institution_id,driver_id,seller_id,amount)
    values(result_id,p_institution_id,p_driver_id,p_seller_id,p_driver_fee); end if;
  return result_id;
end; $$;

create or replace function public.pay_driver_trip(p_trip_id uuid,p_method public.driver_payment_method) returns void
language plpgsql security definer set search_path=public
as $$ declare institution uuid; begin
  select institution_id into institution from public.driver_trips where id=p_trip_id for update;
  if institution is null then raise exception 'Trip was not found'; end if;
  if not public.has_institution_role(institution,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  update public.driver_trips set payment_status='paid',payment_method=p_method,paid_at=now() where id=p_trip_id;
end; $$;

create policy suppliers_read_members on public.suppliers for select to authenticated using(public.is_institution_member(institution_id));

revoke execute on function public.record_sale(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,uuid,numeric,numeric,uuid,numeric,numeric,numeric,public.customer_payment_method) from public,anon;
revoke execute on function public.pay_driver_trip(uuid,public.driver_payment_method) from public,anon;
grant execute on function public.record_sale(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,uuid,numeric,numeric,uuid,numeric,numeric,numeric,public.customer_payment_method) to authenticated;
grant execute on function public.pay_driver_trip(uuid,public.driver_payment_method) to authenticated;
