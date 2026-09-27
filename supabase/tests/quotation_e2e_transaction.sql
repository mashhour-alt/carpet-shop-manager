-- Real production-schema quotation E2E. Every fixture row is rolled back.
create or replace function pg_temp.farsha_quotation_e2e()
returns jsonb
language plpgsql
as $$
declare
  owner_id uuid;
  test_seller_id uuid;
  test_institution_id uuid := gen_random_uuid();
  test_branch_id uuid := gen_random_uuid();
  test_supplier_id uuid := gen_random_uuid();
  test_inventory_id uuid := gen_random_uuid();
  test_felt_id uuid := gen_random_uuid();
  test_install_id uuid := gen_random_uuid();
  test_delivery_id uuid := gen_random_uuid();
  test_quotation_id uuid;
  test_sale_id uuid;
  test_invoice_id uuid;
  repeated_invoice_id uuid;
  before_stock numeric;
  historical_invoice_fingerprint text;
  final_historical_invoice_fingerprint text;
  result jsonb;
begin
  select user_id into owner_id from public.institution_memberships
    where role='owner' and status='active' order by created_at,user_id limit 1;
  select user_id into test_seller_id from public.institution_memberships
    where role='seller' and status='active' and user_id<>owner_id order by created_at,user_id limit 1;
  if owner_id is null or test_seller_id is null then
    raise exception 'Quotation E2E needs an existing owner and seller profile';
  end if;
  select coalesce(md5(string_agg(id::text || ':' || coalesce(xml_content,''), ',' order by id)), '')
    into historical_invoice_fingerprint from public.invoices;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub',owner_id,'role','authenticated')::text, true);

  begin
    insert into public.institutions(
      id,name,commercial_registration,tax_number,address,phone,email,created_by,
      zatca_street_name,zatca_building_number,zatca_additional_number,
      zatca_district,zatca_city,zatca_postal_code,zatca_country_code
    ) values (
      test_institution_id,'Quotation Test Seller','1010000000','310000000000003',
      'Test Address','0500000000','quotation@example.test',owner_id,
      'Test Street','1234','5678','Test District','Riyadh','12345','SA'
    );
    insert into public.institution_memberships(institution_id,user_id,role)
      values(test_institution_id,owner_id,'owner'),(test_institution_id,test_seller_id,'seller');
    update public.institution_memberships m set commission_rate=.10
      where m.institution_id=test_institution_id and m.user_id=test_seller_id and m.role='seller';
    insert into public.branches(id,institution_id,name,code,city,address,phone,is_default,created_by)
      values(test_branch_id,test_institution_id,'Quotation Test Branch','QT','Riyadh','Test Address','0500000000',true,owner_id);
    insert into public.suppliers(id,institution_id,name,phone)
      values(test_supplier_id,test_institution_id,'Quotation Test Supplier','0500000001');
    insert into public.inventory_items(
      id,institution_id,branch_id,name,color,remaining_length,width,wholesale_price,low_stock_at
    ) values(test_inventory_id,test_institution_id,test_branch_id,'Test Carpet','Blue',20,4,30,1);
    insert into public.inventory_costs(inventory_id,institution_id,supplier_id,supplier_price)
      values(test_inventory_id,test_institution_id,test_supplier_id,25);
    insert into public.addon_types(id,institution_id,name,unit,default_sale_price,default_cost_price,created_by)
      values
        (test_felt_id,test_institution_id,'Felt','m2',5,2,owner_id),
        (test_install_id,test_institution_id,'Installation','job',100,40,owner_id),
        (test_delivery_id,test_institution_id,'Delivery','trip',50,20,owner_id);
    select remaining_length into before_stock from public.inventory_items where id=test_inventory_id;

    test_quotation_id := public.create_quotation_v2(
      test_institution_id,test_seller_id,test_inventory_id,'Quotation Buyer','1010000001','310000000000013',
      5,50,current_date+14,'Carpet + felt + installation + delivery',
      jsonb_build_array(
        jsonb_build_object('addon_type_id',test_felt_id,'quantity',20,'sale_unit_price',5),
        jsonb_build_object('addon_type_id',test_install_id,'quantity',1,'sale_unit_price',100),
        jsonb_build_object('addon_type_id',test_delivery_id,'quantity',1,'sale_unit_price',50)
      ),100
    );
    if (select remaining_length from public.inventory_items where id=test_inventory_id) <> before_stock then
      raise exception 'Creating a quotation deducted inventory';
    end if;
    if not exists (
      select 1 from public.quotations q join public.quotation_items qi on qi.quotation_id=q.id
      where q.id=test_quotation_id and qi.inventory_id=test_inventory_id and q.subtotal=1150
        and q.discount_amount=100 and q.vat_amount=172.50 and q.total=1322.50
        and jsonb_array_length(q.addons)=3 and q.status='draft'
    ) then raise exception 'Quotation header/items or VAT-exclusive totals are incorrect'; end if;
    if exists(select 1 from public.quotation_sales qs where qs.quotation_id=test_quotation_id)
      or exists(select 1 from public.invoices i where i.sale_id in (select qs.sale_id from public.quotation_sales qs where qs.quotation_id=test_quotation_id)) then
      raise exception 'Quotation created invoice or sale artifacts';
    end if;

    select (public.convert_quotation_to_sale(test_quotation_id,'cash'))[1] into test_sale_id;
    if (select remaining_length from public.inventory_items where id=test_inventory_id) <> 15 then
      raise exception 'Quotation conversion did not deduct exactly the sold length';
    end if;
    if not exists(
      select 1 from public.sales s where s.id=test_sale_id and s.line_extension_amount=1250
        and s.discount_amount=100 and s.tax_exclusive_amount=1150 and s.vat_amount=172.50
        and s.payable_amount=1322.50 and s.seller_profit=320 and s.seller_commission=32
    ) then raise exception 'Converted sale financial snapshot is incorrect'; end if;
    if (select round(sum(sp.amount),2) from public.sale_payments sp where sp.sale_id=test_sale_id) <> 1322.50 then
      raise exception 'Quotation conversion payment does not equal final customer payable';
    end if;
    if (select count(*) from public.sale_addons sa where sa.sale_id=test_sale_id) <> 3
      or not exists(select 1 from public.quotations q where q.id=test_quotation_id and q.status='converted') then
      raise exception 'Quotation add-ons or lifecycle status did not transfer';
    end if;

    test_invoice_id := public.issue_tax_invoice_v3(
      test_sale_id,'Quotation Buyer','','','','simplified',100,'','','','','','','',''
    );
    repeated_invoice_id := public.issue_tax_invoice_v3(
      test_sale_id,'Ignored','','','','simplified',100,'','','','','','','',''
    );
    if repeated_invoice_id <> test_invoice_id then raise exception 'Sale invoice is not idempotent'; end if;
    if exists(
      select 1 from public.sales s join public.invoices i on i.sale_id=s.id
      where s.id=test_sale_id and (s.line_extension_amount<>i.line_extension_amount
        or s.discount_amount<>i.discount_amount or s.tax_exclusive_amount<>i.tax_exclusive_amount
        or s.vat_amount<>i.vat_amount or s.payable_amount<>i.payable_amount)
    ) then raise exception 'Sale and invoice snapshots diverged'; end if;
    if exists(
      select 1 from public.invoice_lines il where il.invoice_id=test_invoice_id
      group by il.invoice_id having round(sum(il.gross_amount),2)<>1250
        or round(sum(discount_amount),2)<>100 or round(sum(taxable_amount),2)<>1150
        or round(sum(vat_amount),2)<>172.50 or round(sum(total_with_vat),2)<>1322.50
    ) then raise exception 'Invoice lines diverged from quotation/sale totals'; end if;

    result := jsonb_build_object(
      'rollback_marker', test_institution_id,
      'quotation_created', true,
      'reopened_header_items', true,
      'inventory_before_quote', before_stock,
      'inventory_after_conversion', 15,
      'gross', 1250, 'discount', 100, 'tax_exclusive', 1150,
      'vat', 172.50, 'customer_payable', 1322.50,
      'seller_profit', 320, 'seller_commission', 32,
      'invoice_idempotent', true, 'no_zatca_on_quote_creation', true
    );
    raise exception 'quotation_e2e_rollback';
  exception when raise_exception then
    if sqlerrm <> 'quotation_e2e_rollback' then raise; end if;
  end;
  select coalesce(md5(string_agg(id::text || ':' || coalesce(xml_content,''), ',' order by id)), '')
    into final_historical_invoice_fingerprint from public.invoices;
  if final_historical_invoice_fingerprint <> historical_invoice_fingerprint then
    raise exception 'Historical invoices changed during quotation test';
  end if;
  return result;
end
$$;

with run as (select pg_temp.farsha_quotation_e2e() result)
select result as quotation_e2e_result,
  not exists(select 1 from public.institutions where id=(result->>'rollback_marker')::uuid) as rollback_verified
from run;
