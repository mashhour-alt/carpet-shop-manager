-- Preserve the existing sale branch on its inventory reversal.
create or replace function public.void_sale(p_sale_id uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$
declare s public.sales%rowtype; a record; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if; select * into s from public.sales where id=p_sale_id for update; if not found then raise exception 'Sale was not found'; end if;
 if not public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if; if s.status='voided' then return; end if; if s.status<>'completed' then raise exception 'Only completed sales can be voided'; end if; if exists(select 1 from public.invoices where sale_id=s.id) then raise exception 'Issued invoice must be handled before voiding the sale'; end if;
 update public.inventory_items set remaining_length=remaining_length+s.length where id=s.inventory_id; insert into public.inventory_movements(institution_id,branch_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by) values(s.institution_id,s.branch_id,s.inventory_id,'sale_void',s.length,'sale',s.id,coalesce(trim(p_reason),''),auth.uid());
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
