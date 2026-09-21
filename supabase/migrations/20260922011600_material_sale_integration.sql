-- Extend sale add-ons with stock-aware customer materials and sale-area quantities.
create or replace function public.record_sale_v2(
  p_institution_id uuid,p_inventory_id uuid,p_seller_id uuid,p_driver_id uuid,
  p_customer_name text,p_length numeric,p_sale_price numeric,p_driver_fee numeric,
  p_notes text,p_payments jsonb,p_addons jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare
 item public.inventory_items%rowtype; cost_row public.inventory_costs%rowtype; inst public.institutions%rowtype; seller public.institution_memberships%rowtype;
 result_id uuid; payment jsonb; addon jsonb; v_area numeric; v_carpet_total numeric; v_addon_sales numeric:=0; v_total numeric; v_paid numeric:=0; v_fee numeric:=0;
 v_method text; v_amount numeric; v_rate numeric; v_reference text; v_seller_profit numeric; v_commission numeric; v_primary_method text:='other';
 v_name text; v_unit text; v_qty numeric; v_sale_unit numeric; v_cost_unit numeric; v_addon_id uuid; v_supplier_id uuid; a public.addon_types%rowtype;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.has_institution_role(p_institution_id,array['owner','seller']::public.institution_role[]) then raise exception 'Only owners and sellers can record a sale'; end if;
 if auth.uid()<>p_seller_id and not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then raise exception 'Seller mismatch'; end if;
 if p_length<=0 or p_sale_price<0 or p_driver_fee<0 then raise exception 'Invalid sale values'; end if;
 select * into item from public.inventory_items where id=p_inventory_id and institution_id=p_institution_id for update;
 if not found or item.remaining_length<p_length then raise exception 'Requested length is unavailable'; end if;
 select * into cost_row from public.inventory_costs where inventory_id=item.id; if not found then raise exception 'Inventory cost is missing'; end if;
 select * into seller from public.institution_memberships where institution_id=p_institution_id and user_id=p_seller_id and role='seller' and status='active'; if not found then raise exception 'Seller is not active'; end if;
 if p_driver_id is not null and not exists(select 1 from public.institution_driver_connections where institution_id=p_institution_id and driver_id=p_driver_id and status='active') then raise exception 'Driver is not connected to this institution'; end if;
 select * into inst from public.institutions where id=p_institution_id;
 v_area:=p_length*4; v_carpet_total:=round(v_area*p_sale_price,2);
 for addon in select value from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) loop
   v_addon_id:=nullif(addon->>'addon_type_id','')::uuid;
   if v_addon_id is not null then
     select * into a from public.addon_types where id=v_addon_id and institution_id=p_institution_id and is_active for update;
     if not found or a.behavior<>'customer_addon' then raise exception 'Add-on type is unavailable for customer sale'; end if;
     v_qty:=case when a.calculation_basis='sale_area' then v_area else coalesce((addon->>'quantity')::numeric,0) end;
   else v_qty:=coalesce((addon->>'quantity')::numeric,0); end if;
   v_sale_unit:=coalesce((addon->>'sale_unit_price')::numeric,0); v_cost_unit:=coalesce((addon->>'cost_unit_price')::numeric,0);
   if v_qty<=0 or v_sale_unit<0 or v_cost_unit<0 then raise exception 'Invalid add-on values'; end if;
   if v_addon_id is not null and a.track_stock and a.stock_quantity<v_qty then raise exception 'Insufficient add-on stock: %',a.name; end if;
   v_addon_sales:=v_addon_sales+round(v_qty*v_sale_unit,2);
 end loop;
 v_total:=round(v_carpet_total+v_addon_sales,2);
 if jsonb_typeof(coalesce(p_payments,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_payments,'[]'::jsonb))=0 then raise exception 'At least one payment is required'; end if;
 for payment in select value from jsonb_array_elements(p_payments) loop
   v_method:=coalesce(nullif(trim(payment->>'method'),''),'other'); if v_method not in ('cash','network','bank_transfer','visa','tamara','tabby','other') then raise exception 'Invalid payment method'; end if;
   v_amount:=coalesce((payment->>'amount')::numeric,0); if v_amount<=0 then raise exception 'Payment amount must be positive'; end if; v_paid:=v_paid+v_amount; if v_primary_method='other' then v_primary_method:=v_method; end if;
 end loop;
 if round(v_paid,2)<>round(v_total,2) then raise exception 'Payments must equal sale total. Expected %, received %',v_total,v_paid; end if;
 v_seller_profit:=round(greatest((p_sale_price-item.wholesale_price)*v_area,0),2); v_commission:=round(v_seller_profit*seller.commission_rate,2);
 insert into public.sales(institution_id,inventory_id,seller_id,driver_id,customer_name,length,width,area,sale_price_per_sqm,wholesale_price_snapshot,supplier_unit_cost_snapshot,installation_amount,glue_gallons,glue_amount,iron_pieces,iron_amount,driver_fee,customer_payment,payment_fee,seller_profit,seller_commission,total,notes,status)
 values(p_institution_id,item.id,p_seller_id,p_driver_id,coalesce(trim(p_customer_name),''),p_length,4,v_area,p_sale_price,item.wholesale_price,cost_row.supplier_price,0,0,0,0,0,p_driver_fee,v_primary_method,0,v_seller_profit,v_commission,v_total,coalesce(trim(p_notes),''),'completed') returning id into result_id;
 for addon in select value from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) loop
   v_addon_id:=nullif(addon->>'addon_type_id','')::uuid; v_supplier_id:=nullif(addon->>'supplier_id','')::uuid;
   if v_addon_id is not null then select * into a from public.addon_types where id=v_addon_id and institution_id=p_institution_id and is_active for update; v_name:=a.name;v_unit:=a.unit;v_qty:=case when a.calculation_basis='sale_area' then v_area else (addon->>'quantity')::numeric end;
   else v_name:=trim(coalesce(addon->>'name',''));v_unit:=trim(coalesce(addon->>'unit','piece'));v_qty:=(addon->>'quantity')::numeric; end if;
   v_sale_unit:=(addon->>'sale_unit_price')::numeric;v_cost_unit:=(addon->>'cost_unit_price')::numeric;
   insert into public.sale_addons(institution_id,sale_id,addon_type_id,name_snapshot,unit_snapshot,quantity,sale_unit_price,cost_unit_price,supplier_id) values(p_institution_id,result_id,v_addon_id,v_name,v_unit,v_qty,v_sale_unit,v_cost_unit,v_supplier_id);
   if v_addon_id is not null and a.track_stock then update public.addon_types set stock_quantity=stock_quantity-v_qty where id=a.id; insert into public.addon_movements(institution_id,addon_type_id,seller_id,sale_id,movement_type,quantity_delta,unit_cost_snapshot,note,created_by) values(p_institution_id,a.id,p_seller_id,result_id,'sale',-v_qty,v_cost_unit,'استهلاك بيع',auth.uid()); end if;
 end loop;
 for payment in select value from jsonb_array_elements(p_payments) loop v_method:=coalesce(nullif(trim(payment->>'method'),''),'other');v_amount:=(payment->>'amount')::numeric;v_reference:=coalesce(trim(payment->>'reference'),'');v_rate:=case v_method when 'visa' then inst.visa_fee_rate when 'tabby' then inst.tabby_fee_rate when 'tamara' then inst.tamara_fee_rate else 0 end;insert into public.sale_payments(institution_id,sale_id,method,amount,reference,fee_rate_snapshot,fee_amount,created_by) values(p_institution_id,result_id,v_method,v_amount,v_reference,v_rate,round(v_amount*v_rate,2),auth.uid());v_fee:=v_fee+round(v_amount*v_rate,2);end loop;
 update public.sales set payment_fee=v_fee where id=result_id; update public.inventory_items set remaining_length=remaining_length-p_length,last_sold_at=now() where id=item.id;
 insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by) values(p_institution_id,item.id,'sale',-p_length,'sale',result_id,'Sale stock deduction',auth.uid());
 if p_driver_id is not null then insert into public.driver_trips(sale_id,institution_id,driver_id,seller_id,amount) values(result_id,p_institution_id,p_driver_id,p_seller_id,p_driver_fee); end if; return result_id;
end; $$;
revoke all on function public.record_sale_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb) from public,anon; grant execute on function public.record_sale_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb) to authenticated;

create or replace function public.void_sale(p_sale_id uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$
declare s public.sales%rowtype; a record; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if; select * into s from public.sales where id=p_sale_id for update; if not found then raise exception 'Sale was not found'; end if;
 if not public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if; if s.status<>'completed' then raise exception 'Only completed sales can be voided'; end if; if exists(select 1 from public.invoices where sale_id=s.id) then raise exception 'Issued invoice must be handled before voiding the sale'; end if;
 update public.inventory_items set remaining_length=remaining_length+s.length where id=s.inventory_id; insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by) values(s.institution_id,s.inventory_id,'sale_void',s.length,'sale',s.id,coalesce(trim(p_reason),''),auth.uid());
 for a in select sa.addon_type_id,sa.quantity,sa.cost_unit_price from public.sale_addons sa join public.addon_types at on at.id=sa.addon_type_id where sa.sale_id=s.id and at.track_stock loop update public.addon_types set stock_quantity=stock_quantity+a.quantity where id=a.addon_type_id; insert into public.addon_movements(institution_id,addon_type_id,seller_id,sale_id,movement_type,quantity_delta,unit_cost_snapshot,note,created_by) values(s.institution_id,a.addon_type_id,s.seller_id,s.id,'sale_void',a.quantity,a.cost_unit_price,coalesce(trim(p_reason),''),auth.uid()); end loop;
 update public.sales set status='voided',reversed_at=now(),reversed_by=auth.uid(),reverse_reason=coalesce(trim(p_reason),'') where id=s.id;
end; $$;
revoke all on function public.void_sale(uuid,text) from public,anon;grant execute on function public.void_sale(uuid,text) to authenticated;
