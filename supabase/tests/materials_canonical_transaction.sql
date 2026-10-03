-- E2E release-candidate regression. Every fixture row is rolled back.
begin;
do $$
declare owner_id uuid; seller_id uuid; iid uuid:=gen_random_uuid(); bid uuid:=gen_random_uuid(); sid uuid:=gen_random_uuid(); inv uuid:=gen_random_uuid(); addon uuid:=gen_random_uuid(); sale uuid; report jsonb; test_balance numeric; quote_id uuid; quote_sale uuid; extra_sale uuid; iron uuid:=gen_random_uuid(); glue uuid:=gen_random_uuid(); untracked uuid:=gen_random_uuid(); before_sales bigint; rejected boolean;
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
  insert into public.addon_types(id,institution_id,name,unit,default_sale_price,default_cost_price,is_active,created_by,behavior,calculation_basis,track_stock,stock_quantity,customer_visible) values(addon,iid,'RC Felt','m2',10,4,true,owner_id,'customer_addon','quantity',true,100,true);
  -- A: canonical sale consumes the exact persisted quantity.
  sale:=public.record_sale_financial_v2(iid,inv,seller_id,null,'Materials A',1,50,0,'',
    '[{"method":"cash","amount":460}]',
    jsonb_build_array(jsonb_build_object('addon_type_id',addon,'quantity',20,'sale_unit_price',10,'cost_unit_price',4)),0);
  if (select stock_quantity from public.addon_types where id=addon)<>80
    or (select count(*) from public.addon_movements where sale_id=sale and addon_type_id=addon and movement_type='sale' and quantity_delta=-20)<>1
    then raise exception 'A: 100 - 20 = 80 / canonical movement failed'; end if;
  -- C: replay processing of the SAME canonical sale identity, including multiple retries.
  perform private.consume_sale_materials(sale);
  perform private.consume_sale_materials(sale);
  if (select stock_quantity from public.addon_types where id=addon)<>80
    or (select count(*) from public.addon_movements where sale_id=sale and movement_type='sale')<>1
    then raise exception 'C: duplicate deduction'; end if;
  -- B/C: restoration follows the original movement even after a metadata change.
  update public.addon_types set track_stock=false where id=addon;
  perform public.void_sale(sale,'Materials B');
  perform public.void_sale(sale,'Retry B');
  perform public.void_sale(sale,'Retry B again');
  if (select stock_quantity from public.addon_types where id=addon)<>100
    or (select count(*) from public.addon_movements where sale_id=sale and movement_type='sale_void' and quantity_delta=20)<>1
    or (select count(*) from public.inventory_movements where source_id=sale and movement_type='sale_void')<>1
    or (select remaining_length from public.inventory_items where id=inv)<>10
    then raise exception 'B/C: reversal not exactly once'; end if;
  update public.addon_types set track_stock=true where id=addon;
  -- D: draft quote is inert for materials.
  quote_id:=public.create_quotation_v2(iid,seller_id,inv,'Material Quote','','',1,50,current_date+14,'',
    jsonb_build_array(jsonb_build_object('addon_type_id',addon,'quantity',20,'sale_unit_price',10,'cost_unit_price',4)),0);
  if (select stock_quantity from public.addon_types where id=addon)<>100
    or (select count(*) from public.addon_movements where addon_type_id=addon)<>2
    then raise exception 'D: quotation deducted stock'; end if;
  -- E: conversion uses the unchanged canonical quotation path once.
  quote_sale:=(public.convert_quotation_to_sale(quote_id,'cash'))[1];
  perform private.consume_sale_materials(quote_sale);
  rejected:=false;
  begin
    perform public.convert_quotation_to_sale(quote_id,'cash');
  exception when raise_exception then
    if sqlerrm not like '%not available%' then raise; end if;
    rejected:=true;
  end;
  if not rejected or (select stock_quantity from public.addon_types where id=addon)<>80
    or (select count(*) from public.quotation_sales where quotation_id=quote_id)<>1
    or (select count(*) from public.addon_movements where sale_id=quote_sale and movement_type='sale' and quantity_delta=-20)<>1
    then raise exception 'E: quotation conversion not exactly once'; end if;
  perform public.void_sale(quote_sale,'Fixture reset');
  -- Repeated lines aggregate into one movement; different units keep their quantities.
  insert into public.addon_types(id,institution_id,name,unit,default_sale_price,default_cost_price,is_active,created_by,behavior,calculation_basis,track_stock,stock_quantity,customer_visible,charge_to_seller)
    values(iron,iid,'Iron','piece',0,2,true,owner_id,'customer_addon','quantity',true,100,true,false),
      (glue,iid,'Glue','gallon',0,3,true,owner_id,'internal_consumable','quantity',true,100,false,false),
      (untracked,iid,'Installation','job',0,0,true,owner_id,'customer_addon','quantity',false,0,true,false);
  extra_sale:=public.record_sale_financial_v2(iid,inv,seller_id,null,'Mixed units',1,50,0,'',
    '[{"method":"cash","amount":230}]',jsonb_build_array(
      jsonb_build_object('addon_type_id',addon,'quantity',7.125,'sale_unit_price',0,'cost_unit_price',4),
      jsonb_build_object('addon_type_id',addon,'quantity',12.875,'sale_unit_price',0,'cost_unit_price',4),
      jsonb_build_object('addon_type_id',iron,'quantity',2,'sale_unit_price',0,'cost_unit_price',2),
      jsonb_build_object('addon_type_id',untracked,'quantity',1,'sale_unit_price',0,'cost_unit_price',0)
    ),0);
  if (select stock_quantity from public.addon_types where id=addon)<>80
    or (select stock_quantity from public.addon_types where id=iron)<>98
    or (select stock_quantity from public.addon_types where id=glue)<>100
    or (select count(*) from public.addon_movements where sale_id=extra_sale and movement_type='sale')<>2
    then raise exception 'Repeated lines / units / untracked behavior failed'; end if;
  -- Existing internal-consumable issuance remains explicit, with no invented conversion.
  perform public.issue_internal_addon(iid,glue,seller_id,1.250,extra_sale,'Existing internal issue');
  perform private.consume_sale_materials(extra_sale);
  perform public.void_sale(extra_sale,'Mixed units void');
  if (select stock_quantity from public.addon_types where id=addon)<>100
    or (select stock_quantity from public.addon_types where id=iron)<>100
    or (select stock_quantity from public.addon_types where id=glue)<>98.750
    or (select count(*) from public.addon_movements where addon_type_id=glue and movement_type='issue_to_seller' and quantity_delta=-1.250)<>1
    then raise exception 'Existing internal consumable behavior changed'; end if;
  -- Existing sale_area calculation is consumed from the snapshot (4 m2 here).
  update public.addon_types set calculation_basis='sale_area' where id=addon;
  extra_sale:=public.record_sale_financial_v2(iid,inv,seller_id,null,'Area basis',1,50,0,'',
    '[{"method":"cash","amount":230}]',jsonb_build_array(
      jsonb_build_object('addon_type_id',addon,'quantity',4,'sale_unit_price',0,'cost_unit_price',4)),0);
  if (select stock_quantity from public.addon_types where id=addon)<>96 then raise exception 'Existing area basis changed'; end if;
  perform public.void_sale(extra_sale,'Area reset');
  update public.addon_types set calculation_basis='quantity' where id=addon;
  -- Insufficient material must roll back the entire sale, carpet and movements.
  select count(*) into before_sales from public.sales where institution_id=iid;
  rejected:=false;
  begin
    perform public.record_sale_financial_v2(iid,inv,seller_id,null,'Too much',1,50,0,'',
      '[{"method":"cash","amount":230}]',jsonb_build_array(
        jsonb_build_object('addon_type_id',addon,'quantity',101,'sale_unit_price',0,'cost_unit_price',4)),0);
  exception when raise_exception then
    if sqlerrm not like 'Insufficient add-on stock:%' then raise; end if;
    rejected:=true;
  end;
  if not rejected or (select count(*) from public.sales where institution_id=iid)<>before_sales
    or (select stock_quantity from public.addon_types where id=addon)<>100
    or (select remaining_length from public.inventory_items where id=inv)<>10
    then raise exception 'Insufficient material is not atomic'; end if;
  -- Historical undeducted sale: void cannot create material stock.
  extra_sale:=public.record_sale_v2(iid,inv,seller_id,null,'Legacy undeducted',1,50,0,'',
    '[{"method":"cash","amount":200}]',jsonb_build_array(
      jsonb_build_object('addon_type_id',addon,'quantity',20,'sale_unit_price',0,'cost_unit_price',4)));
  perform public.void_sale(extra_sale,'No material movement to reverse');
  if (select stock_quantity from public.addon_types where id=addon)<>100
    or exists(select 1 from public.addon_movements where sale_id=extra_sale)
    then raise exception 'Legacy undeducted sale manufactured stock'; end if;
  if has_function_privilege('authenticated','private.consume_sale_materials(uuid)','EXECUTE')
    or has_function_privilege('anon','private.consume_sale_materials(uuid)','EXECUTE')
    then raise exception 'Internal stock helper exposed to API clients'; end if;
end $$;
select 'PASS' as materials_a_b_c_d_e,
  '100 -> 80 -> 100; one sale and reversal; same-sale replay; quote conversion; fractional and mixed units; internal issuance; atomic shortage; legacy void' as coverage;
rollback;
