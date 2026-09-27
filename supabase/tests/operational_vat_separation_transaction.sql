-- Real database E2E for the daily-operations/VAT boundary.
-- The test uses the production functions and rolls every fixture row back.
create or replace function pg_temp.farsha_operational_vat_e2e()
returns jsonb
language plpgsql
as $$
declare
  owner_id uuid;
  seller_id uuid;
  test_institution_id uuid:=gen_random_uuid();
  test_branch_id uuid:=gen_random_uuid();
  test_supplier_id uuid:=gen_random_uuid();
  test_inventory_id uuid:=gen_random_uuid();
  test_sale_id uuid;
  test_invoice_id uuid;
  repeated_invoice_id uuid;
  before_repeat jsonb;
  after_repeat jsonb;
  summary record;
  sale_row public.sales%rowtype;
  invoice_row public.invoices%rowtype;
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
    raise exception 'Operational E2E needs an existing owner and seller profile';
  end if;

  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);

  begin
    insert into public.institutions(
      id,name,commercial_registration,tax_number,address,phone,email,created_by,
      zatca_street_name,zatca_building_number,zatca_additional_number,
      zatca_district,zatca_city,zatca_postal_code,zatca_country_code
    ) values (
      test_institution_id,'Operational Test Seller','1010000000','310000000000003',
      'Test Address','0500000000','operations@example.test',owner_id,
      'Test Street','1234','5678','Test District','Riyadh','12345','SA'
    );
    insert into public.institution_memberships(institution_id,user_id,role)
      values(test_institution_id,owner_id,'owner'),(test_institution_id,seller_id,'seller');
    update public.institution_memberships m set commission_rate=.10
      where m.institution_id=test_institution_id and m.user_id=seller_id and m.role='seller';
    insert into public.branches(id,institution_id,name,code,city,address,phone,is_default,created_by)
      values(test_branch_id,test_institution_id,'Operational Test Branch','OPS','Riyadh','Test Address','0500000000',true,owner_id);
    insert into public.suppliers(id,institution_id,name,phone)
      values(test_supplier_id,test_institution_id,'Operational Test Supplier','0500000001');
    insert into public.inventory_items(
      id,institution_id,branch_id,name,color,remaining_length,width,
      wholesale_price,low_stock_at
    ) values (
      test_inventory_id,test_institution_id,test_branch_id,'Test Carpet','Blue',20,4,30,1
    );
    insert into public.inventory_costs(inventory_id,institution_id,supplier_id,supplier_price)
      values(test_inventory_id,test_institution_id,test_supplier_id,25);

    test_sale_id:=public.record_sale_financial_v2(
      test_institution_id,test_inventory_id,seller_id,null,'Cash Customer',5,50,0,
      'Operational VAT separation E2E',
      '[{"method":"cash","amount":400,"reference":"OPS-CASH"},{"method":"network","amount":635,"reference":"OPS-NETWORK"}]'::jsonb,
      '[]'::jsonb,100
    );
    select * into sale_row from public.sales where id=test_sale_id;

    if sale_row.line_extension_amount<>1000 or sale_row.discount_amount<>100
      or sale_row.tax_exclusive_amount<>900 or sale_row.vat_amount<>135
      or sale_row.payable_amount<>1035 then
      raise exception 'Canonical sale snapshot does not preserve VAT-exclusive price';
    end if;
    if sale_row.seller_profit<>300 or sale_row.seller_commission<>30 then
      raise exception 'Seller profit or commission includes VAT or has wrong basis';
    end if;
    if (select round(sum(sp.amount),2) from public.sale_payments sp where sp.sale_id=test_sale_id)<>1035 then
      raise exception 'Split payments do not settle final payable';
    end if;

    select * into summary from public.operating_summary(
      test_institution_id,now()-interval '1 minute',now()+interval '1 minute'
    );
    if summary.sales_amount<>900 or summary.gross_profit<>400 then
      raise exception 'Dashboard includes VAT in operational sales or profit';
    end if;

    test_invoice_id:=public.issue_tax_invoice_v3(
      test_sale_id,'Cash Customer','','','','simplified',100,'','','','','','','',''
    );
    select * into invoice_row from public.invoices where id=test_invoice_id;
    if invoice_row.line_extension_amount<>1000 or invoice_row.discount_amount<>100
      or invoice_row.tax_exclusive_amount<>900 or invoice_row.vat_amount<>135
      or invoice_row.payable_amount<>1035 then
      raise exception 'Invoice snapshot diverged from sale snapshot';
    end if;
    if exists(
      select 1 from public.invoice_lines l where l.invoice_id=test_invoice_id
      group by l.invoice_id having round(sum(taxable_amount),2)<>900
        or round(sum(vat_amount),2)<>135 or round(sum(total_with_vat),2)<>1035
    ) then raise exception 'Invoice lines diverged from invoice snapshot'; end if;

    select to_jsonb(i) into before_repeat from public.invoices i where i.id=test_invoice_id;
    repeated_invoice_id:=public.issue_tax_invoice_v3(
      test_sale_id,'Ignored','','','','simplified',100,'','','','','','','',''
    );
    select to_jsonb(i) into after_repeat from public.invoices i where i.id=test_invoice_id;
    if repeated_invoice_id<>test_invoice_id or before_repeat<>after_repeat then
      raise exception 'Reopening an issued invoice changed the historical snapshot';
    end if;

    result:=jsonb_build_object(
      'rollback_marker',test_institution_id,
      'gross_sale',sale_row.line_extension_amount,
      'discount',sale_row.discount_amount,
      'operational_sale',sale_row.tax_exclusive_amount,
      'vat',sale_row.vat_amount,
      'customer_payable',sale_row.payable_amount,
      'dashboard_sales',summary.sales_amount,
      'dashboard_profit',summary.gross_profit,
      'seller_profit',sale_row.seller_profit,
      'seller_commission',sale_row.seller_commission,
      'split_payments',jsonb_build_array(400,635),
      'invoice_idempotent',true
    );
    raise exception 'operational_vat_test_rollback';
  exception when raise_exception then
    if sqlerrm<>'operational_vat_test_rollback' then raise; end if;
  end;
  return result;
end
$$;

with run as (select pg_temp.farsha_operational_vat_e2e() result)
select result as operational_vat_e2e_result,
  not exists(
    select 1 from public.institutions
    where id=(result->>'rollback_marker')::uuid
  ) as rollback_verified
from run;
