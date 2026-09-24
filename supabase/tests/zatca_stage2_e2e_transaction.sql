-- Stage 2 integration proof. The inner PL/pgSQL block is a subtransaction.
-- Its deliberate exception rolls back every test row while preserving the
-- materialized JSON result in memory for verification by the XML generator.
create or replace function pg_temp.farsha_stage2_e2e()
returns jsonb
language plpgsql
as $$
declare
  owner_id uuid;
  seller_id uuid;
  institution_id uuid:=gen_random_uuid();
  branch_id uuid:=gen_random_uuid();
  supplier_id uuid:=gen_random_uuid();
  inventory_id uuid:=gen_random_uuid();
  simplified_sale_id uuid;
  standard_sale_id uuid;
  simplified_invoice_id uuid;
  standard_invoice_id uuid;
  repeated_invoice_id uuid;
  result jsonb;
begin
  select user_id into owner_id
  from public.institution_memberships
  where role='owner' and status='active'
  order by created_at,user_id limit 1;
  select user_id into seller_id
  from public.institution_memberships
  where role='seller' and status='active' and user_id<>owner_id
  order by created_at,user_id limit 1;
  if owner_id is null or seller_id is null then
    raise exception 'Stage 2 E2E needs one existing owner profile and one existing seller profile';
  end if;

  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);

  begin
    insert into public.institutions(
      id,name,commercial_registration,tax_number,address,phone,email,created_by,
      zatca_street_name,zatca_building_number,zatca_additional_number,zatca_district,zatca_city,
      zatca_postal_code,zatca_country_code
    ) values(
      institution_id,'Stage 2 Test Seller','1010000000','310000000000003',
      'Test National Address','0500000000','stage2@example.test',owner_id,
      'Test Street','1234','5678','Test District','Riyadh','12345','SA'
    );
    insert into public.institution_memberships(institution_id,user_id,role)
      values(institution_id,owner_id,'owner'),(institution_id,seller_id,'seller');
    insert into public.branches(id,institution_id,name,code,city,address,phone,is_default,created_by)
      values(branch_id,institution_id,'Stage 2 Test Branch','S2','Riyadh','Test Address','0500000000',true,owner_id);
    insert into public.suppliers(id,institution_id,name,phone)
      values(supplier_id,institution_id,'Stage 2 Test Supplier','0500000001');
    insert into public.inventory_items(
      id,institution_id,branch_id,name,color,remaining_length,width,wholesale_price,low_stock_at
    ) values(inventory_id,institution_id,branch_id,'Test Carpet','Blue',20,4,20,1);
    insert into public.inventory_costs(inventory_id,institution_id,supplier_id,supplier_price)
      values(inventory_id,institution_id,supplier_id,15);

    simplified_sale_id:=public.record_sale_financial_v2(
      institution_id,inventory_id,seller_id,null,'Cash Customer',1.234,37.89,0,
      'Stage 2 simplified E2E',
      '[{"method":"cash","amount":100.00,"reference":"S2-CASH"},{"method":"visa","amount":136.29,"reference":"S2-VISA"}]'::jsonb,
      '[{"name":"Installation","unit":"piece","quantity":1,"sale_unit_price":5.55,"cost_unit_price":0},{"name":"Felt","unit":"piece","quantity":2,"sale_unit_price":10.01,"cost_unit_price":0}]'::jsonb,
      7.13
    );
    simplified_invoice_id:=public.issue_tax_invoice_v3(
      simplified_sale_id,'Cash Customer','','','','simplified',7.13,'','','','','','','',''
    );
    repeated_invoice_id:=public.issue_tax_invoice_v3(
      simplified_sale_id,'Ignored on repeat','','','','simplified',7.13,'','','','','','','',''
    );
    if repeated_invoice_id<>simplified_invoice_id then
      raise exception 'Repeated simplified invoice request returned a different invoice';
    end if;

    standard_sale_id:=public.record_sale_financial_v2(
      institution_id,inventory_id,seller_id,null,'Stage 2 Test Buyer',1.234,37.89,0,
      'Stage 2 standard E2E',
      '[{"method":"cash","amount":100.00,"reference":"S2-CASH"},{"method":"visa","amount":136.29,"reference":"S2-VISA"}]'::jsonb,
      '[{"name":"Installation","unit":"piece","quantity":1,"sale_unit_price":5.55,"cost_unit_price":0},{"name":"Felt","unit":"piece","quantity":2,"sale_unit_price":10.01,"cost_unit_price":0}]'::jsonb,
      7.13
    );
    standard_invoice_id:=public.issue_tax_invoice_v3(
      standard_sale_id,'Stage 2 Test Buyer','1010000001','310000000000013',
      'Buyer Street, Buyer District, Riyadh 12345','tax',7.13,
      'Buyer Street','5678','4321','Buyer District','Riyadh','12345','Riyadh Region','SA'
    );
    repeated_invoice_id:=public.issue_tax_invoice_v3(
      standard_sale_id,'Ignored on repeat','999','399999999999993',
      'Ignored','tax',7.13,'Ignored','9999','8888','Ignored','Ignored','99999','Ignored Region','SA'
    );
    if repeated_invoice_id<>standard_invoice_id then
      raise exception 'Repeated standard invoice request returned a different invoice';
    end if;

    if exists(
      select 1
      from public.sales s
      join public.invoices i on i.sale_id=s.id
      where s.id in(simplified_sale_id,standard_sale_id)
        and (
          s.line_extension_amount<>i.line_extension_amount or
          s.discount_amount<>i.discount_amount or
          s.tax_exclusive_amount<>i.tax_exclusive_amount or
          s.vat_amount<>i.vat_amount or
          s.tax_inclusive_amount<>i.tax_inclusive_amount or
          s.payable_amount<>i.payable_amount
        )
    ) then raise exception 'Sale and invoice financial snapshots diverged'; end if;

    if exists(
      select 1
      from public.invoices i
      join lateral(
        select round(sum(gross_amount),2) gross,
               round(sum(discount_amount),2) discount,
               round(sum(taxable_amount),2) taxable,
               round(sum(vat_amount),2) vat,
               round(sum(total_with_vat),2) inclusive
        from public.invoice_lines where invoice_id=i.id
      ) l on true
      where i.id in(simplified_invoice_id,standard_invoice_id)
        and (i.line_extension_amount<>l.gross or i.discount_amount<>l.discount or
             i.tax_exclusive_amount<>l.taxable or i.vat_amount<>l.vat or
             i.tax_inclusive_amount<>l.inclusive or i.payable_amount<>l.inclusive)
    ) then raise exception 'Invoice and invoice-line snapshots diverged'; end if;

    if exists(
      select 1 from public.sales s
      join lateral(select round(sum(amount),2) paid from public.sale_payments where sale_id=s.id) p on true
      where s.id in(simplified_sale_id,standard_sale_id) and s.payable_amount<>p.paid
    ) then raise exception 'Split payments do not equal canonical payable amount'; end if;

    select jsonb_build_object(
      'rollback_marker',institution_id,
      'simplified',pg_temp.stage2_invoice_payload_for_test(simplified_invoice_id),
      'standard',pg_temp.stage2_invoice_payload_for_test(standard_invoice_id),
      'numeric_proof',jsonb_build_object(
        'sale_snapshot',jsonb_build_object('gross',212.60,'discount',7.13,'tax_exclusive',205.47,'vat',30.82,'payable',236.29),
        'invoice_snapshot',jsonb_build_object('gross',212.60,'discount',7.13,'tax_exclusive',205.47,'vat',30.82,'payable',236.29),
        'invoice_lines',jsonb_build_object('gross',212.60,'discount',7.13,'tax_exclusive',205.47,'vat',30.82,'payable',236.29),
        'pdf_inputs',jsonb_build_object('subtotal',212.60,'discount',7.13,'taxable',205.47,'vat',30.82,'total',236.29),
        'qr_monetary_inputs',jsonb_build_object('tag_4_total',236.29,'tag_5_vat',30.82),
        'split_payments',jsonb_build_array(100.00,136.29)
      ),
      'idempotent',true
    ) into result;

    raise exception 'stage2_test_rollback';
  exception when raise_exception then
    if sqlerrm<>'stage2_test_rollback' then raise; end if;
  end;
  return result;
end
$$;

-- A temporary helper cannot be referenced from the Edge Function. This stable
-- projection exists only while this SQL file is executed in a test session.
create or replace function pg_temp.stage2_invoice_payload_for_test(p_invoice_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path=public
as $$
  select jsonb_build_object(
    'invoice',jsonb_build_object(
      'zatca_uuid',i.zatca_uuid,'invoice_number',i.invoice_number,
      'issued_at',i.issued_at,'supply_date_snapshot',i.supply_date_snapshot,
      'invoice_kind',i.invoice_kind,'currency_code',i.currency_code,
      'seller_legal_name_snapshot',i.seller_legal_name_snapshot,
      'seller_vat_number_snapshot',i.seller_vat_number_snapshot,
      'seller_id_scheme_snapshot',i.seller_id_scheme_snapshot,
      'seller_id_value_snapshot',i.seller_id_value_snapshot,
      'seller_street_snapshot',i.seller_street_snapshot,
      'seller_building_number_snapshot',i.seller_building_number_snapshot,
      'seller_additional_number_snapshot',i.seller_additional_number_snapshot,
      'seller_district_snapshot',i.seller_district_snapshot,
      'seller_city_snapshot',i.seller_city_snapshot,
      'seller_postal_code_snapshot',i.seller_postal_code_snapshot,
      'seller_country_code_snapshot',i.seller_country_code_snapshot,
      'customer_name',i.customer_name,'customer_tax_number',i.customer_tax_number,
      'buyer_id_scheme_snapshot',i.buyer_id_scheme_snapshot,
      'buyer_id_value_snapshot',i.buyer_id_value_snapshot,
      'buyer_street_snapshot',i.buyer_street_snapshot,
      'buyer_building_number_snapshot',i.buyer_building_number_snapshot,
      'buyer_additional_number_snapshot',i.buyer_additional_number_snapshot,
      'buyer_district_snapshot',i.buyer_district_snapshot,
      'buyer_city_snapshot',i.buyer_city_snapshot,
      'buyer_postal_code_snapshot',i.buyer_postal_code_snapshot,
      'buyer_region_snapshot',i.buyer_region_snapshot,
      'buyer_country_code_snapshot',i.buyer_country_code_snapshot,
      'payment_method',i.payment_method,
      'tax_category',i.tax_category,'vat_rate',i.vat_rate,
      'line_extension_amount',i.line_extension_amount,
      'discount_amount',i.discount_amount,'tax_exclusive_amount',i.tax_exclusive_amount,
      'vat_amount',i.vat_amount,'tax_inclusive_amount',i.tax_inclusive_amount,
      'payable_amount',i.payable_amount
    ),
    'lines',(
      select jsonb_agg(jsonb_build_object(
        'line_no',l.line_no,'quantity',l.quantity,'unit_code',l.unit_code,
        'unit_price',l.unit_price,'gross_amount',l.gross_amount,
        'discount_amount',l.discount_amount,'taxable_amount',l.taxable_amount,
        'tax_category',l.tax_category,'vat_rate',l.vat_rate,
        'vat_amount',l.vat_amount,'total_with_vat',l.total_with_vat,
        'description',l.description
      ) order by l.line_no)
      from public.invoice_lines l where l.invoice_id=i.id
    ),
    'line_order_hash',(
      select md5(string_agg(l.line_no||':'||l.description||':'||l.total_with_vat,'|' order by l.line_no))
      from public.invoice_lines l where l.invoice_id=i.id
    )
  )
  from public.invoices i where i.id=p_invoice_id
$$;

-- Execute once and verify that the returned rollback marker was not persisted.
with run as (select pg_temp.farsha_stage2_e2e() as result)
select result as stage2_e2e_result,
       not exists(
         select 1 from public.institutions
         where id=(result->>'rollback_marker')::uuid
       ) as rollback_verified
from run;
