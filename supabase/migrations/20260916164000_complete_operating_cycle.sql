create or replace function public.create_inventory_item(p_institution_id uuid,p_supplier_id uuid,p_name text,p_color text,
  p_length numeric,p_supplier_price numeric,p_wholesale_price numeric,p_low_stock_at numeric default 10) returns uuid
language plpgsql security definer set search_path=public
as $$ declare result_id uuid; begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if p_length<=0 or p_supplier_price<0 or p_wholesale_price<p_supplier_price then raise exception 'Invalid inventory values'; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and institution_id=p_institution_id) then raise exception 'Supplier mismatch'; end if;
  insert into public.inventory_items(institution_id,name,color,remaining_length,wholesale_price,low_stock_at)
  values(p_institution_id,trim(p_name),trim(p_color),p_length,p_wholesale_price,p_low_stock_at) returning id into result_id;
  insert into public.inventory_costs(inventory_id,institution_id,supplier_id,supplier_price)
  values(result_id,p_institution_id,p_supplier_id,p_supplier_price);
  update public.suppliers set purchases_total=purchases_total+(p_length*4*p_supplier_price) where id=p_supplier_id;
  return result_id;
end; $$;

create or replace function public.record_supplier_payment(p_institution_id uuid,p_supplier_id uuid,p_amount numeric) returns void
language plpgsql security definer set search_path=public
as $$ begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if p_amount<=0 then raise exception 'Payment must be positive'; end if;
  update public.suppliers set paid_total=paid_total+p_amount where id=p_supplier_id and institution_id=p_institution_id;
  if not found then raise exception 'Supplier was not found'; end if;
end; $$;

revoke execute on function public.record_supplier_payment(uuid,uuid,numeric) from public,anon;
grant execute on function public.record_supplier_payment(uuid,uuid,numeric) to authenticated;
