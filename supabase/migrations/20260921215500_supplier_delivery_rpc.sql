create or replace function public.record_supplier_delivery(p_institution_id uuid,p_supplier_id uuid,p_inventory_id uuid,p_length numeric,p_unit_cost numeric,p_wholesale_price numeric,p_reference text default '',p_notes text default '') returns uuid
language plpgsql security definer set search_path=public as $$
declare item public.inventory_items%rowtype; delivery_id uuid; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 if p_length<=0 or p_unit_cost<0 or p_wholesale_price<p_unit_cost then raise exception 'Invalid delivery values'; end if;
 select * into item from public.inventory_items where id=p_inventory_id and institution_id=p_institution_id for update;
 if not found then raise exception 'Inventory item was not found'; end if;
 if not exists(select 1 from public.suppliers where id=p_supplier_id and institution_id=p_institution_id) then raise exception 'Supplier was not found'; end if;
 insert into public.supplier_deliveries(institution_id,supplier_id,reference,notes,created_by) values(p_institution_id,p_supplier_id,coalesce(trim(p_reference),''),coalesce(trim(p_notes),''),auth.uid()) returning id into delivery_id;
 insert into public.supplier_delivery_items(institution_id,delivery_id,inventory_id,name_snapshot,color_snapshot,length,unit_cost,wholesale_price)
 values(p_institution_id,delivery_id,item.id,item.name,item.color,p_length,p_unit_cost,p_wholesale_price);
 update public.inventory_items set remaining_length=remaining_length+p_length,wholesale_price=p_wholesale_price where id=item.id;
 update public.inventory_costs set supplier_id=p_supplier_id,supplier_price=p_unit_cost,updated_at=now() where inventory_id=item.id;
 update public.suppliers set purchases_total=purchases_total+round(p_length*4*p_unit_cost,2) where id=p_supplier_id;
 insert into public.inventory_movements(institution_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by)
 values(p_institution_id,item.id,'purchase',p_length,'supplier_delivery',delivery_id,coalesce(trim(p_reference),''),auth.uid());
 return delivery_id;
end; $$;
revoke all on function public.record_supplier_delivery(uuid,uuid,uuid,numeric,numeric,numeric,text,text) from public,anon;
grant execute on function public.record_supplier_delivery(uuid,uuid,uuid,numeric,numeric,numeric,text,text) to authenticated;