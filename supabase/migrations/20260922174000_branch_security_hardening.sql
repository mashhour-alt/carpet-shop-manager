-- Tighten branch/partner RLS and legacy RPCs after multi-branch rollout.
create or replace function public.create_quotation(p_institution_id uuid,p_seller_id uuid,p_inventory_id uuid,p_customer_name text,p_customer_cr text,p_customer_tax text,p_length numeric,p_price_per_sqm numeric,p_valid_until date,p_notes text default '')
returns uuid language plpgsql security definer set search_path=public as $$declare inv public.inventory_items%rowtype;q uuid;begin
 select * into inv from public.inventory_items where id=p_inventory_id and institution_id=p_institution_id;if not found then raise exception 'Inventory not found';end if;
 if not public.can_manage_branch(inv.branch_id,'sell') then raise exception 'Insufficient branch permission';end if;
 if auth.uid()<>p_seller_id and not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then raise exception 'Seller mismatch';end if;
 insert into public.quotations(institution_id,branch_id,seller_id,inventory_id,customer_name,customer_commercial_registration,customer_tax_number,length,width,area,price_per_sqm,vat_rate,valid_until,notes)
 values(p_institution_id,inv.branch_id,p_seller_id,p_inventory_id,trim(p_customer_name),trim(p_customer_cr),trim(p_customer_tax),p_length,4,p_length*4,p_price_per_sqm,.15,p_valid_until,trim(p_notes)) returning id into q;return q;end$$;
revoke all on function public.create_quotation(uuid,uuid,uuid,text,text,text,numeric,numeric,date,text) from public,anon;grant execute on function public.create_quotation(uuid,uuid,uuid,text,text,text,numeric,numeric,date,text) to authenticated;

create or replace function public.pay_driver_trip(p_trip_id uuid,p_method public.driver_payment_method)
returns void language plpgsql security definer set search_path=public as $$declare t public.driver_trips%rowtype;begin
 select * into t from public.driver_trips where id=p_trip_id for update;if not found then raise exception 'Trip not found';end if;
 if not public.can_manage_branch(t.branch_id,'financials') then raise exception 'Insufficient branch permission';end if;
 update public.driver_trips set paid=true,payment_method=p_method,paid_at=now() where id=p_trip_id;
 insert into public.driver_account_entries(institution_id,branch_id,driver_id,entry_type,balance_effect,payment_method,reference,note,source_type,source_id,created_by)
 values(t.institution_id,t.branch_id,t.driver_id,'payment',-abs(t.amount),p_method::text,'','Trip payment','trip_payment',t.id,auth.uid());end$$;
revoke all on function public.pay_driver_trip(uuid,public.driver_payment_method) from public,anon;grant execute on function public.pay_driver_trip(uuid,public.driver_payment_method) to authenticated;

drop policy if exists supplier_deliveries_read on public.supplier_deliveries;
create policy supplier_deliveries_read on public.supplier_deliveries for select to authenticated using(public.can_access_branch(branch_id) and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));
drop policy if exists inventory_movements_read on public.inventory_movements;
create policy inventory_movements_read on public.inventory_movements for select to authenticated using(public.can_access_branch(branch_id));
drop policy if exists seller_ledger_read on public.seller_ledger;
create policy seller_ledger_read on public.seller_ledger for select to authenticated using((user_id=(select auth.uid()) and (branch_id is null or public.can_access_branch(branch_id))) or (branch_id is not null and public.can_access_branch(branch_id) and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])));
drop policy if exists supplier_account_entries_read on public.supplier_account_entries;
create policy supplier_account_entries_read on public.supplier_account_entries for select to authenticated using(public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]) and (branch_id is null or public.can_access_branch(branch_id)));
drop policy if exists driver_account_entries_read on public.driver_account_entries;
create policy driver_account_entries_read on public.driver_account_entries for select to authenticated using(driver_id=(select auth.uid()) or (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]) and (branch_id is null or public.can_access_branch(branch_id))));
drop policy if exists addon_movements_read on public.addon_movements;
create policy addon_movements_read on public.addon_movements for select to authenticated using((seller_id=(select auth.uid()) and (branch_id is null or public.can_access_branch(branch_id))) or (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]) and (branch_id is null or public.can_access_branch(branch_id))));

create or replace function public.partner_can_access_branch(p_branch_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.branches b join public.partners p on p.institution_id=b.institution_id and p.user_id=(select auth.uid()) and p.status='active'
 join public.partner_scopes ps on ps.partner_id=p.id
 where b.id=p_branch_id and current_date between ps.effective_from and coalesce(ps.effective_to,'infinity'::date)
 and (ps.scope='institution' or ps.branch_id=b.id))
$$;
revoke all on function public.partner_can_access_branch(uuid) from public,anon;grant execute on function public.partner_can_access_branch(uuid) to authenticated;

create or replace function public.can_access_branch(p_branch_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.branches b join public.institution_memberships m on m.institution_id=b.institution_id where b.id=p_branch_id and m.user_id=(select auth.uid()) and m.status='active' and m.role='owner')
 or exists(select 1 from public.institution_branch_access a where a.branch_id=p_branch_id and a.user_id=(select auth.uid()) and a.can_view)
 or public.partner_can_access_branch(p_branch_id)
$$;
revoke all on function public.can_access_branch(uuid) from public,anon;grant execute on function public.can_access_branch(uuid) to authenticated;

drop policy if exists sales_read on public.sales;
create policy sales_read on public.sales for select to authenticated using((seller_id=(select auth.uid()) and public.can_access_branch(branch_id)) or (public.can_access_branch(branch_id) and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])) or (public.partner_can_access_branch(branch_id) and exists(select 1 from public.institution_branch_access a where a.branch_id=sales.branch_id and a.user_id=(select auth.uid()) and a.can_view_financials)));
