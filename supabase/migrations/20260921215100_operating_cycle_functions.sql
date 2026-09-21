
create or replace function public.record_sale_v2(
  p_institution_id uuid,p_inventory_id uuid,p_seller_id uuid,p_driver_id uuid,
  p_customer_name text,p_length numeric,p_sale_price numeric,p_driver_fee numeric,
  p_notes text,p_payments jsonb,p_addons jsonb default '[]'::jsonb
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  item public.inventory_items%rowtype; cost_row public.inventory_costs%rowtype;
  inst public.institutions%rowtype; seller public.institution_memberships%rowtype;
  result_id uuid; payment jsonb; addon jsonb; v_area numeric; v_carpet_total numeric;
  v_addon_sales numeric:=0; v_total numeric; v_paid numeric:=0; v_fee numeric:=0;
  v_method text; v_amount numeric; v_rate numeric; v_reference text;
  v_seller_profit numeric; v_commission numeric; v_primary_method text:='other';
  v_name text; v_unit text; v_qty numeric; v_sale_unit numeric; v_cost_unit numeric;
  v_addon_id uuid; v_supplier_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_institution_role(p_institution_id,array['owner','seller']::public.institution_role[]) then raise exception 'Only owners and sellers can record a sale'; end if;
  if auth.uid()<>p_seller_id and not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then raise exception 'Seller mismatch'; end if;
  if p_length<=0 or p_sale_price<0 or p_driver_fee<0 then raise exception 'Invalid sale values'; end if;
  select * into item from public.inventory_items where id=p_inventory_id and institution_id=p_institution_id for update;
  if not found or item.remaining_length<p_length then raise exception 'Requested length is unavailable'; end if;
  select * into cost_row from public.inventory_costs where inventory_id=item.id;
  if not found then raise exception 'Inventory cost is missing'; end if;
  select * into seller from public.institution_memberships where institution_id=p_institution_id and user_id=p_seller_id and role='seller' and status='active';
  if not found then raise exception 'Seller is not active'; end if;
  if p_driver_id is not null and not exists(select 1 from public.institution_driver_connections where institution_id=p_institution_id and driver_id=p_driver_id and status='active') then raise exception 'Driver is not connected to this institution'; end if;
  select * into inst from public.institutions where id=p_institution_id;
  v_area:=p_length*4; v_carpet_total:=round(v_area*p_sale_price,2);
  for addon in select value from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) loop
    v_qty:=coalesce((addon->>'quantity')::numeric,0); v_sale_unit:=coalesce((addon->>'sale_unit_price')::numeric,0); v_cost_unit:=coalesce((addon->>'cost_unit_price')::numeric,0);
    if v_qty<=0 or v_sale_unit<0 or v_cost_unit<0 then raise exception 'Invalid add-on values'; end if;
    v_addon_sales:=v_addon_sales+round(v_qty*v_sale_unit,2);
  end loop;
  v_total:=round(v_carpet_total+v_addon_sales+p_driver_fee,2);
  if jsonb_typeof(coalesce(p_payments,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_payments,'[]'::jsonb))=0 then raise exception 'At least one payment is required'; end if;
  for payment in select value from jsonb_array_elements(p_payments) loop
    v_method:=coalesce(nullif(trim(payment->>'method'),''),'other');
    if v_method not in ('cash','network','bank_transfer','visa','tamara','tabby','other') then raise exception 'Invalid payment method'; end if;
    v_amount:=coalesce((payment->>'amount')::numeric,0); if v_amount<=0 then raise exception 'Payment amount must be positive'; end if;
    v_paid:=v_paid+v_amount; if v_primary_method='other' then v_primary_method:=v_method; end if;
  end loop;
  if round(v_paid,2)<>round(v_total,2) then raise exception 'Payments must equal sale total. Expected %, received %',v_total,v_paid; end if;
  v_seller_profit:=round(greatest((p_sale_price-item.wholesale_price)*v_area,0),2); v_commission:=round(v_seller_profit*seller.commission_rate,2);
  insert into public.sales(institution_id,inventory_id,seller_id,driver_id,customer_name,length,width,area,sale_price_per_sqm,wholesale_price_snapshot,supplier_unit_cost_snapshot,installation_amount,glue_gallons,glue_amount,iron_pieces,iron_amount,driver_fee,customer_payment,payment_fee,seller_profit,seller_commission,total,notes,status)
  values(p_institution_id,item.id,p_seller_id,p_driver_id,coalesce(trim(p_customer_name),''),p_length,4,v_area,p_sale_price,item.wholesale_price,cost_row.supplier_price,0,0,0,0,0,p_driver_fee,v_primary_method,0,v_seller_profit,v_commission,v_total,coalesce(trim(p_notes),''),'completed') returning id into result_id;
  for addon in select value from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) loop
    v_addon_id:=nullif(addon->>'addon_type_id','')::uuid; v_supplier_id:=nullif(addon->>'supplier_id','')::uuid;
    if v_addon_id is not null then select name,unit into v_name,v_unit from public.addon_types where id=v_addon_id and institution_id=p_institution_id and is_active; if not found then raise exception 'Add-on type is unavailable'; end if;
    else v_name:=trim(coalesce(addon->>'name','')); v_unit:=trim(coalesce(addon->>'unit','piece')); if v_name='' then raise exception 'Add-on name is required'; end if; end if;
    if v_supplier_id is not null and not exists(select 1 from public.suppliers where id=v_supplier_id and institution_id=p_institution_id) then raise exception 'Add-on supplier does not belong to institution'; end if;
    v_qty:=(addon->>'quantity')::numeric; v_sale_unit:=(addon->>'sale_unit_price')::numeric; v_cost_unit:=(addon->>'cost_unit_price')::numeric;
    insert into public.sale_addons(institution_id,sale_id,addon_type_id,name_snapshot,unit_snapshot,quantity,sale_unit_price,cost_unit_price,supplier_id)
    values(p_institution_id,result_id,v_addon_id,v_name,v_unit,v_qty,v_sale_unit,v_cost_unit,v_supplier_id);
  end loop;
  for payment in select value from jsonb_array_elements(p_payments) loop
    v_method:=coalesce(nullif(trim(payment->>'method'),''),'other'); v_amount:=(payment->>'amount')::numeric; v_reference:=coalesce(trim(payment->>'reference'),'');
    v_rate:=case v_method when 'visa' then inst.visa_fee_rate when 'tabby' then inst.tabby_fee_rate when 'tamara' then inst.tamara_fee_rate else 0 end;
    insert into public.sale_payments(institution_id,sale_id,method,amount,reference,fee_rate_snapshot,fee_amount,created_by)
    values(p_institution_id,result_id,v_method,v_amount,v_reference,v_rate,round(v_amount*v_rate,2),auth.uid()); v_fee:=v_fee+round(v_amount*v_rate,2);
  end loop;
  update public.sales set payment_fee=v_fee where id=result_id;
  update public.inventory_items set remaining_length=remaining_length-p_length,last_sold_at=now() where id=item.id;
  insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by)
  values(p_institution_id,item.id,'sale',-p_length,'sale',result_id,'Sale stock deduction',auth.uid());
  if p_driver_id is not null then insert into public.driver_trips(sale_id,institution_id,driver_id,seller_id,amount) values(result_id,p_institution_id,p_driver_id,p_seller_id,p_driver_fee); end if;
  return result_id;
end; $$;
revoke all on function public.record_sale_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb) from public,anon;
grant execute on function public.record_sale_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb) to authenticated;

create or replace function public.void_sale(p_sale_id uuid,p_reason text) returns void
language plpgsql security definer set search_path=public as $$
declare s public.sales%rowtype; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into s from public.sales where id=p_sale_id for update; if not found then raise exception 'Sale was not found'; end if;
 if not public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 if s.status<>'completed' then raise exception 'Only completed sales can be voided'; end if;
 if exists(select 1 from public.invoices where sale_id=s.id) then raise exception 'Issued invoice must be handled before voiding the sale'; end if;
 update public.inventory_items set remaining_length=remaining_length+s.length where id=s.inventory_id;
 insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by)
 values(s.institution_id,s.inventory_id,'sale_void',s.length,'sale',s.id,coalesce(trim(p_reason),''),auth.uid());
 update public.sales set status='voided',reversed_at=now(),reversed_by=auth.uid(),reverse_reason=coalesce(trim(p_reason),'') where id=s.id;
end; $$;
revoke all on function public.void_sale(uuid,text) from public,anon;
grant execute on function public.void_sale(uuid,text) to authenticated;

create or replace function public.operating_summary(p_institution_id uuid,p_from timestamptz,p_to timestamptz)
returns table(sales_amount numeric,total_length numeric,total_area numeric,sale_count bigint,merchandise_cost numeric,addon_cost numeric,driver_cost numeric,payment_fees numeric,gross_profit numeric,cash numeric,network numeric,bank_transfer numeric,visa numeric,tamara numeric,tabby numeric,other numeric)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 return query with ss as(select s.id,s.total,s.length,s.area,s.supplier_unit_cost_snapshot,s.driver_fee from public.sales s where s.institution_id=p_institution_id and s.status='completed' and s.created_at>=p_from and s.created_at<p_to),
 a as(select sa.sale_id,sum(sa.quantity*sa.cost_unit_price) cost from public.sale_addons sa join ss on ss.id=sa.sale_id group by sa.sale_id),
 p as(select sp.sale_id,sum(sp.fee_amount) fees from public.sale_payments sp join ss on ss.id=sp.sale_id group by sp.sale_id),
 methods as(select sp.method,sum(sp.amount) amount from public.sale_payments sp join ss on ss.id=sp.sale_id group by sp.method),
 totals as(select coalesce(sum(ss.total),0) sales_amount,coalesce(sum(ss.length),0) total_length,coalesce(sum(ss.area),0) total_area,count(*) sale_count,coalesce(sum(ss.area*ss.supplier_unit_cost_snapshot),0) merchandise_cost,coalesce(sum(coalesce(a.cost,0)),0) addon_cost,coalesce(sum(ss.driver_fee),0) driver_cost,coalesce(sum(coalesce(p.fees,0)),0) payment_fees from ss left join a on a.sale_id=ss.id left join p on p.sale_id=ss.id)
 select t.sales_amount,t.total_length,t.total_area,t.sale_count,t.merchandise_cost,t.addon_cost,t.driver_cost,t.payment_fees,t.sales_amount-t.merchandise_cost-t.addon_cost-t.driver_cost-t.payment_fees,
 coalesce((select amount from methods where method='cash'),0),coalesce((select amount from methods where method='network'),0),coalesce((select amount from methods where method='bank_transfer'),0),coalesce((select amount from methods where method='visa'),0),coalesce((select amount from methods where method='tamara'),0),coalesce((select amount from methods where method='tabby'),0),coalesce((select amount from methods where method='other'),0) from totals t;
end; $$;
revoke all on function public.operating_summary(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.operating_summary(uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.operating_sales(p_institution_id uuid,p_from timestamptz,p_to timestamptz,p_search text default '')
returns table(sale_id uuid,created_at timestamptz,length numeric,area numeric,item_name text,color text,addons text,payments text,sales_amount numeric,seller_name text,driver_name text,driver_cost numeric,merchandise_cost numeric,addon_cost numeric,payment_fees numeric,total_cost numeric,gross_profit numeric,notes text,status text)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 return query select s.id,s.created_at,s.length,s.area,i.name,i.color,
 coalesce((select string_agg(sa.name_snapshot||' × '||trim(to_char(sa.quantity,'FM999999990.###')),', ' order by sa.created_at) from public.sale_addons sa where sa.sale_id=s.id),''),
 coalesce((select string_agg(sp.method||': '||trim(to_char(sp.amount,'FM999999990.00')),', ' order by sp.paid_at) from public.sale_payments sp where sp.sale_id=s.id),''),
 s.total,coalesce(sel.full_name,'بائع'),coalesce(drv.full_name,''),s.driver_fee,round(s.area*s.supplier_unit_cost_snapshot,2),
 coalesce((select sum(sa.quantity*sa.cost_unit_price) from public.sale_addons sa where sa.sale_id=s.id),0),
 coalesce((select sum(sp.fee_amount) from public.sale_payments sp where sp.sale_id=s.id),0),
 round(s.area*s.supplier_unit_cost_snapshot,2)+coalesce((select sum(sa.quantity*sa.cost_unit_price) from public.sale_addons sa where sa.sale_id=s.id),0)+s.driver_fee+coalesce((select sum(sp.fee_amount) from public.sale_payments sp where sp.sale_id=s.id),0),
 s.total-(round(s.area*s.supplier_unit_cost_snapshot,2)+coalesce((select sum(sa.quantity*sa.cost_unit_price) from public.sale_addons sa where sa.sale_id=s.id),0)+s.driver_fee+coalesce((select sum(sp.fee_amount) from public.sale_payments sp where sp.sale_id=s.id),0)),
 s.notes,s.status from public.sales s join public.inventory_items i on i.id=s.inventory_id join public.profiles sel on sel.id=s.seller_id left join public.profiles drv on drv.id=s.driver_id
 where s.institution_id=p_institution_id and s.created_at>=p_from and s.created_at<p_to
 and(coalesce(trim(p_search),'')='' or s.notes ilike '%'||trim(p_search)||'%' or i.name ilike '%'||trim(p_search)||'%' or i.color ilike '%'||trim(p_search)||'%' or sel.full_name ilike '%'||trim(p_search)||'%')
 order by s.created_at desc;
end; $$;
revoke all on function public.operating_sales(uuid,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.operating_sales(uuid,timestamptz,timestamptz,text) to authenticated;

create or replace function public.seller_performance(p_institution_id uuid,p_seller_id uuid,p_from timestamptz,p_to timestamptz)
returns table(sale_count bigint,total_length numeric,total_area numeric,sales_amount numeric,merchandise_cost numeric,gross_profit numeric,commission numeric,ledger_deductions numeric,net_due numeric)
language plpgsql stable security definer set search_path=public as $$
declare can_finance boolean; begin
 if not public.is_institution_member(p_institution_id) then raise exception 'Insufficient permission'; end if;
 if auth.uid()<>p_seller_id and not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 can_finance:=public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]);
 return query with s as(select * from public.sales where institution_id=p_institution_id and seller_id=p_seller_id and status='completed' and created_at>=p_from and created_at<p_to),
 l as(select coalesce(sum(amount),0) deductions from public.seller_ledger where institution_id=p_institution_id and seller_id=p_seller_id and entry_date>=p_from::date and entry_date<p_to::date),
 x as(select count(*) cnt,coalesce(sum(length),0) len,coalesce(sum(area),0) ar,coalesce(sum(total),0) sales,coalesce(sum(area*supplier_unit_cost_snapshot),0) merch,coalesce(sum(seller_commission),0) comm from s)
 select x.cnt,x.len,x.ar,x.sales,case when can_finance then x.merch else null end,case when can_finance then x.sales-x.merch-coalesce((select sum(driver_fee) from s),0) else null end,x.comm,l.deductions,x.comm-l.deductions from x cross join l;
end; $$;
revoke all on function public.seller_performance(uuid,uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.seller_performance(uuid,uuid,timestamptz,timestamptz) to authenticated;
