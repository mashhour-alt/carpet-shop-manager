-- E2E release-candidate regression. Every fixture row is rolled back.
begin;
do $$
declare owner_id uuid; seller_id uuid; iid uuid:=gen_random_uuid(); bid uuid:=gen_random_uuid(); sid uuid:=gen_random_uuid(); inv uuid:=gen_random_uuid(); addon uuid:=gen_random_uuid(); sale uuid; report jsonb; balance numeric;
begin
  select user_id into owner_id from public.institution_memberships where role='owner' and status='active' order by created_at limit 1;
  select user_id into seller_id from public.institution_memberships where role='seller' and status='active' and user_id<>owner_id order by created_at limit 1;
  if owner_id is null or seller_id is null then raise exception 'requires an existing owner and seller'; end if;
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  insert into public.institutions(id,name,commercial_registration,tax_number,address,phone,email,created_by) values(iid,'RC Test','1010000000','310000000000003','Test','0500000000','rc@example.test',owner_id);
  insert into public.institution_memberships(institution_id,user_id,role,commission_rate) values(iid,owner_id,'owner',0),(iid,seller_id,'seller',.10);
  insert into public.branches(id,institution_id,name,code,city,address,phone,is_default,created_by) values(bid,iid,'RC','RC','Riyadh','Test','0500000000',true,owner_id);
  insert into public.suppliers(id,institution_id,name,phone) values(sid,iid,'RC Supplier','0500000001');
  insert into public.inventory_items(id,institution_id,branch_id,name,color,remaining_length,width,wholesale_price,low_stock_at) values(inv,iid,bid,'RC Carpet','Blue',10,4,30,1);
  insert into public.inventory_costs(inventory_id,institution_id,supplier_id,supplier_price) values(inv,iid,sid,25);
  insert into public.addon_types(id,institution_id,name,unit,default_sale_price,default_cost_price,is_active,created_by,behavior,calculation_basis,track_stock,stock_quantity,customer_visible) values(addon,iid,'RC Felt','m2',10,4,true,owner_id,'customer_addon','quantity',true,10,true);
  sale:=public.record_sale_financial_v2(iid,inv,seller_id,null,'RC Customer',1,50,0,'',jsonb_build_array(jsonb_build_object('method','cash','amount',253)),jsonb_build_array(jsonb_build_object('addon_type_id',addon,'quantity',2,'sale_unit_price',10,'cost_unit_price',4)),0);
  if (select stock_quantity from public.addon_types where id=addon)<>8 or (select count(*) from public.addon_movements where sale_id=sale and movement_type='sale')<>1 then raise exception 'material was not deducted exactly once'; end if;
  perform public.void_sale(sale,'RC cancellation');
  if (select stock_quantity from public.addon_types where id=addon)<>10 or (select count(*) from public.addon_movements where sale_id=sale and movement_type='sale_void')<>1 then raise exception 'material cancellation did not reverse exactly once'; end if;
  insert into public.seller_ledger(institution_id,branch_id,seller_id,kind,amount,note,created_by) values(iid,bid,seller_id,'withdrawal',20,'RC payment',owner_id);
  select balance into balance from public.account_summaries(iid,'seller',date_trunc('month',now()),date_trunc('month',now())+interval '1 month') where party_id=seller_id;
  if balance<>-20 then raise exception 'cumulative balance is not showing overpayment: %',balance; end if;
  report:=public.monthly_owner_report(iid,date_trunc('month',current_date)::date);
  if report is null then raise exception 'monthly report missing'; end if;
  perform public.close_month(iid,date_trunc('month',current_date)::date);
  if (select count(*) from public.monthly_closing_snapshots where institution_id=iid)<>1 or (select count(*) from public.sales where id=sale)<>1 then raise exception 'closing is destructive or snapshot missing'; end if;
end $$;
rollback;
