alter table public.invoices add column if not exists supply_date_snapshot date;
create or replace function public.capture_invoice_zatca_snapshot() returns trigger language plpgsql security definer set search_path=public as $$
declare inst public.institutions%rowtype;br public.branches%rowtype;sale_supply_date date;begin
select * into inst from public.institutions where id=new.institution_id;select * into br from public.branches where id=new.branch_id and institution_id=new.institution_id;select created_at::date into sale_supply_date from public.sales where id=new.sale_id and institution_id=new.institution_id;
new.zatca_uuid:=coalesce(new.zatca_uuid,gen_random_uuid());new.supply_date_snapshot:=coalesce(new.supply_date_snapshot,sale_supply_date);new.seller_legal_name_snapshot:=inst.name;new.seller_vat_number_snapshot:=inst.tax_number;new.seller_id_scheme_snapshot:=case when nullif(trim(inst.commercial_registration),'') is null then null else 'CRN' end;new.seller_id_value_snapshot:=nullif(trim(inst.commercial_registration),'');
new.seller_street_snapshot:=coalesce(nullif(trim(br.zatca_street_name),''),nullif(trim(inst.zatca_street_name),''));new.seller_building_number_snapshot:=coalesce(nullif(trim(br.zatca_building_number),''),nullif(trim(inst.zatca_building_number),''));new.seller_district_snapshot:=coalesce(nullif(trim(br.zatca_district),''),nullif(trim(inst.zatca_district),''));new.seller_city_snapshot:=coalesce(nullif(trim(br.zatca_city),''),nullif(trim(inst.zatca_city),''));new.seller_postal_code_snapshot:=coalesce(nullif(trim(br.zatca_postal_code),''),nullif(trim(inst.zatca_postal_code),''));new.seller_country_code_snapshot:=coalesce(nullif(trim(br.zatca_country_code),''),nullif(trim(inst.zatca_country_code),''),'SA');
new.buyer_id_scheme_snapshot:=case when nullif(trim(new.customer_commercial_registration),'') is null then null else 'CRN' end;new.buyer_id_value_snapshot:=nullif(trim(new.customer_commercial_registration),'');return new;end$$;
revoke all on function public.capture_invoice_zatca_snapshot() from public,anon,authenticated;
create or replace function public.prevent_invoice_zatca_snapshot_mutation() returns trigger language plpgsql set search_path=public as $$
begin if old.zatca_uuid is distinct from new.zatca_uuid or old.supply_date_snapshot is distinct from new.supply_date_snapshot or old.seller_legal_name_snapshot is distinct from new.seller_legal_name_snapshot or old.seller_vat_number_snapshot is distinct from new.seller_vat_number_snapshot or old.seller_id_scheme_snapshot is distinct from new.seller_id_scheme_snapshot or old.seller_id_value_snapshot is distinct from new.seller_id_value_snapshot or old.seller_street_snapshot is distinct from new.seller_street_snapshot or old.seller_building_number_snapshot is distinct from new.seller_building_number_snapshot or old.seller_district_snapshot is distinct from new.seller_district_snapshot or old.seller_city_snapshot is distinct from new.seller_city_snapshot or old.seller_postal_code_snapshot is distinct from new.seller_postal_code_snapshot or old.seller_country_code_snapshot is distinct from new.seller_country_code_snapshot or old.buyer_id_scheme_snapshot is distinct from new.buyer_id_scheme_snapshot or old.buyer_id_value_snapshot is distinct from new.buyer_id_value_snapshot or old.buyer_street_snapshot is distinct from new.buyer_street_snapshot or old.buyer_building_number_snapshot is distinct from new.buyer_building_number_snapshot or old.buyer_district_snapshot is distinct from new.buyer_district_snapshot or old.buyer_city_snapshot is distinct from new.buyer_city_snapshot or old.buyer_postal_code_snapshot is distinct from new.buyer_postal_code_snapshot or old.buyer_country_code_snapshot is distinct from new.buyer_country_code_snapshot then raise exception 'ZATCA invoice party snapshot is immutable';end if;
if old.xml_content is not null and(old.xml_content is distinct from new.xml_content or old.xml_standard_version is distinct from new.xml_standard_version or old.xml_generator_version is distinct from new.xml_generator_version or old.xml_generated_at is distinct from new.xml_generated_at)then raise exception 'Generated invoice XML is immutable';end if;return new;end$$;
revoke all on function public.prevent_invoice_zatca_snapshot_mutation() from public,anon,authenticated;

-- Standard tax invoices require a structured buyer address. Keep the legacy
-- RPC for simplified invoices, and expose an explicit v2 RPC so old clients
-- cannot silently issue a standard invoice whose immutable snapshot is
-- missing mandatory address fields.
create or replace function public.issue_tax_invoice_v2(
  p_sale_id uuid,
  p_customer_name text default '',
  p_customer_cr text default '',
  p_customer_tax text default '',
  p_customer_address text default '',
  p_invoice_kind text default 'simplified',
  p_discount numeric default 0,
  p_buyer_street text default '',
  p_buyer_building_number text default '',
  p_buyer_district text default '',
  p_buyer_city text default '',
  p_buyer_postal_code text default '',
  p_buyer_country_code text default ''
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.sales%rowtype;
  rid uuid;
  num bigint;
  carpet numeric;
  gross numeric;
  discount numeric;
  taxable numeric;
  vat numeric;
  totalvat numeric;
  ln int:=0;
  r record;
  line_discount numeric;
  allocated numeric:=0;
  line_count int;
  buyer_country text:=upper(trim(coalesce(p_buyer_country_code,'')));
  full_buyer_address text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_invoice_kind not in('simplified','tax') then raise exception 'Invalid invoice kind'; end if;
  select * into s from public.sales where id=p_sale_id for update;
  if not found then raise exception 'Sale not found'; end if;
  if s.status<>'completed' then raise exception 'Only completed sales can be invoiced'; end if;
  if not((s.seller_id=auth.uid()) or(public.can_access_branch(s.branch_id) and public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]))) then
    raise exception 'Insufficient permission';
  end if;
  select id into rid from public.invoices where sale_id=s.id;
  if found then return rid; end if;

  discount:=round(coalesce(p_discount,0),2);
  carpet:=round(s.area*s.sale_price_per_sqm,2);
  select round(carpet+coalesce(sum(round(sa.quantity*sa.sale_unit_price,2)),0),2),count(*)+1
    into gross,line_count from public.sale_addons sa where sa.sale_id=s.id;
  if discount<0 or discount>gross then raise exception 'Discount must be between zero and invoice gross amount'; end if;

  if p_invoice_kind='tax' then
    if nullif(trim(coalesce(p_customer_name,'')),'') is null then raise exception 'Buyer legal name is required for a standard tax invoice'; end if;
    if trim(coalesce(p_customer_tax,'')) !~ '^3[0-9]{13}3$' then raise exception 'Buyer VAT number must be 15 digits and start/end with 3'; end if;
    if nullif(trim(coalesce(p_customer_address,'')),'') is null then raise exception 'Buyer display address is required for a standard tax invoice'; end if;
    if nullif(trim(coalesce(p_buyer_street,'')),'') is null then raise exception 'Buyer street name is required for a standard tax invoice'; end if;
    if nullif(trim(coalesce(p_buyer_city,'')),'') is null then raise exception 'Buyer city is required for a standard tax invoice'; end if;
    if buyer_country !~ '^[A-Z]{2}$' then raise exception 'Buyer country code must contain two letters'; end if;
    if buyer_country='SA' then
      if trim(coalesce(p_buyer_building_number,'')) !~ '^[0-9]{4}$' then raise exception 'Saudi buyer building number must contain 4 digits'; end if;
      if nullif(trim(coalesce(p_buyer_district,'')),'') is null then raise exception 'Saudi buyer district is required'; end if;
      if trim(coalesce(p_buyer_postal_code,'')) !~ '^[0-9]{5}$' then raise exception 'Saudi buyer postal code must contain 5 digits'; end if;
    end if;
  else
    buyer_country:=null;
  end if;

  full_buyer_address:=coalesce(
    nullif(trim(coalesce(p_customer_address,'')),''),
    nullif(concat_ws(', ',nullif(trim(p_buyer_street),''),nullif(trim(p_buyer_district),''),nullif(trim(p_buyer_city),''),nullif(trim(p_buyer_postal_code),''),nullif(buyer_country,'')),'')
  );
  taxable:=round(gross-discount,2);
  vat:=round(taxable*.15,2);
  totalvat:=taxable+vat;

  insert into public.invoice_counters(institution_id,next_number) values(s.institution_id,2)
  on conflict(institution_id) do update set next_number=public.invoice_counters.next_number+1
  returning next_number-1 into num;

  insert into public.invoices(
    institution_id,branch_id,sale_id,invoice_number,seller_id,customer_name,
    customer_commercial_registration,customer_tax_number,item_name,color,length,width,area,
    price_per_sqm,carpet_amount,installation_amount,glue_gallons,glue_amount,iron_pieces,
    iron_amount,driver_fee,payment_method,subtotal,vat_rate,vat_amount,total_with_vat,
    created_by,invoice_kind,customer_address,seller_name,discount_amount,taxable_amount,
    payment_summary,addons_summary,addons_amount,currency_code,tax_category,
    financial_snapshot_version,line_extension_amount,tax_exclusive_amount,
    tax_inclusive_amount,payable_amount,buyer_street_snapshot,
    buyer_building_number_snapshot,buyer_district_snapshot,buyer_city_snapshot,
    buyer_postal_code_snapshot,buyer_country_code_snapshot
  )
  select
    s.institution_id,s.branch_id,s.id,num,s.seller_id,
    coalesce(nullif(trim(p_customer_name),''),nullif(trim(s.customer_name),''),'عميل نقدي'),
    trim(coalesce(p_customer_cr,'')),trim(coalesce(p_customer_tax,'')),iv.name,iv.color,
    s.length,s.width,s.area,s.sale_price_per_sqm,carpet,0,0,0,0,0,s.driver_fee,
    s.customer_payment::text,gross,.15,vat,totalvat,auth.uid(),p_invoice_kind,
    coalesce(full_buyer_address,''),coalesce(pr.full_name,''),discount,taxable,
    (select string_agg(method||': '||amount,' / ' order by paid_at,id) from public.sale_payments where sale_id=s.id),
    (select string_agg(name_snapshot||' × '||quantity,' / ' order by created_at,id) from public.sale_addons where sale_id=s.id),
    gross-carpet,'SAR','S',2,gross,taxable,totalvat,totalvat,
    case when p_invoice_kind='tax' then trim(p_buyer_street) end,
    case when p_invoice_kind='tax' then nullif(trim(p_buyer_building_number),'') end,
    case when p_invoice_kind='tax' then nullif(trim(p_buyer_district),'') end,
    case when p_invoice_kind='tax' then trim(p_buyer_city) end,
    case when p_invoice_kind='tax' then nullif(trim(p_buyer_postal_code),'') end,
    case when p_invoice_kind='tax' then buyer_country end
  from public.inventory_items iv
  left join public.profiles pr on pr.id=s.seller_id
  where iv.id=s.inventory_id
  returning id into rid;

  ln:=1;
  line_discount:=case when line_count=1 then discount when gross=0 then 0 else round(discount*carpet/gross,2) end;
  allocated:=line_discount;
  insert into public.invoice_lines(
    invoice_id,line_no,source_kind,source_id,description,quantity,unit_code,unit_price,
    gross_amount,discount_amount,taxable_amount,tax_category,vat_rate,vat_amount,total_with_vat
  )
  select rid,ln,'carpet',iv.id,iv.name||' - '||iv.color,s.area,'MTK',s.sale_price_per_sqm,
    carpet,line_discount,carpet-line_discount,'S',.15,
    round((carpet-line_discount)*.15,2),
    (carpet-line_discount)+round((carpet-line_discount)*.15,2)
  from public.inventory_items iv where iv.id=s.inventory_id;

  for r in select sa.* from public.sale_addons sa where sa.sale_id=s.id order by sa.created_at,sa.id loop
    ln:=ln+1;
    line_discount:=case when ln=line_count then discount-allocated when gross=0 then 0 else round(discount*round(r.quantity*r.sale_unit_price,2)/gross,2) end;
    allocated:=allocated+line_discount;
    insert into public.invoice_lines(
      invoice_id,line_no,source_kind,source_id,description,quantity,unit_code,unit_price,
      gross_amount,discount_amount,taxable_amount,tax_category,vat_rate,vat_amount,total_with_vat
    ) values(
      rid,ln,'addon',r.id,r.name_snapshot,r.quantity,'PCE',r.sale_unit_price,
      round(r.quantity*r.sale_unit_price,2),line_discount,
      round(r.quantity*r.sale_unit_price,2)-line_discount,'S',.15,
      round((round(r.quantity*r.sale_unit_price,2)-line_discount)*.15,2),
      (round(r.quantity*r.sale_unit_price,2)-line_discount)+round((round(r.quantity*r.sale_unit_price,2)-line_discount)*.15,2)
    );
  end loop;

  if (select round(sum(gross_amount),2) from public.invoice_lines where invoice_id=rid)<>gross
    or (select round(sum(discount_amount),2) from public.invoice_lines where invoice_id=rid)<>discount
    or (select round(sum(taxable_amount),2) from public.invoice_lines where invoice_id=rid)<>taxable then
    raise exception 'Invoice snapshot line allocation mismatch';
  end if;
  update public.invoice_lines
    set vat_amount=vat_amount+(vat-(select sum(vat_amount) from public.invoice_lines where invoice_id=rid)),
        total_with_vat=taxable_amount+vat_amount+(vat-(select sum(vat_amount) from public.invoice_lines where invoice_id=rid))
    where invoice_id=rid and line_no=line_count;
  if (select round(sum(vat_amount),2) from public.invoice_lines where invoice_id=rid)<>vat
    or (select round(sum(total_with_vat),2) from public.invoice_lines where invoice_id=rid)<>totalvat then
    raise exception 'Invoice snapshot VAT mismatch';
  end if;
  return rid;
end
$$;

revoke all on function public.issue_tax_invoice_v2(uuid,text,text,text,text,text,numeric,text,text,text,text,text,text) from public,anon;
grant execute on function public.issue_tax_invoice_v2(uuid,text,text,text,text,text,numeric,text,text,text,text,text,text) to authenticated;

create or replace function public.issue_tax_invoice(
  p_sale_id uuid,
  p_customer_name text default '',
  p_customer_cr text default '',
  p_customer_tax text default '',
  p_customer_address text default '',
  p_invoice_kind text default 'simplified',
  p_discount numeric default 0
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
begin
  if p_invoice_kind='tax' then
    raise exception 'Structured buyer address is required. Update the app and use issue_tax_invoice_v2.';
  end if;
  return public.issue_tax_invoice_v2(
    p_sale_id,p_customer_name,p_customer_cr,p_customer_tax,p_customer_address,
    p_invoice_kind,p_discount,'','','','','',''
  );
end
$$;

revoke all on function public.issue_tax_invoice(uuid,text,text,text,text,text,numeric) from public,anon;
grant execute on function public.issue_tax_invoice(uuid,text,text,text,text,text,numeric) to authenticated;
