create or replace function public.save_addon_type(p_institution_id uuid,p_name text,p_unit text,p_sale_price numeric,p_cost_price numeric,p_supplier_id uuid default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare result_id uuid; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 if trim(coalesce(p_name,''))='' or trim(coalesce(p_unit,''))='' or p_sale_price<0 or p_cost_price<0 then raise exception 'Invalid add-on values'; end if;
 if p_supplier_id is not null and not exists(select 1 from public.suppliers where id=p_supplier_id and institution_id=p_institution_id) then raise exception 'Supplier was not found'; end if;
 insert into public.addon_types(institution_id,name,unit,default_sale_price,default_cost_price,supplier_id,created_by)
 values(p_institution_id,trim(p_name),trim(p_unit),p_sale_price,p_cost_price,p_supplier_id,auth.uid())
 on conflict(institution_id,name) do update set unit=excluded.unit,default_sale_price=excluded.default_sale_price,default_cost_price=excluded.default_cost_price,supplier_id=excluded.supplier_id,is_active=true
 returning id into result_id; return result_id;
end; $$;
revoke all on function public.save_addon_type(uuid,text,text,numeric,numeric,uuid) from public,anon;
grant execute on function public.save_addon_type(uuid,text,text,numeric,numeric,uuid) to authenticated;