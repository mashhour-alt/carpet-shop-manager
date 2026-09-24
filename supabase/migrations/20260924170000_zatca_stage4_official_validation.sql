-- Stage 4 official-validation corrections. This migration is additive: it
-- neither backfills nor recalculates any historical invoice.
alter table public.institutions
  add column if not exists zatca_additional_number text;
alter table public.branches
  add column if not exists zatca_additional_number text;
alter table public.invoices
  add column if not exists seller_additional_number_snapshot text,
  add column if not exists buyer_additional_number_snapshot text,
  add column if not exists buyer_region_snapshot text;

create or replace function public.capture_invoice_zatca_snapshot() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  inst public.institutions%rowtype;
  br public.branches%rowtype;
  sale_supply_date date;
begin
  select * into inst from public.institutions where id=new.institution_id;
  select * into br from public.branches where id=new.branch_id and institution_id=new.institution_id;
  select created_at::date into sale_supply_date from public.sales where id=new.sale_id and institution_id=new.institution_id;
  new.zatca_uuid:=coalesce(new.zatca_uuid,gen_random_uuid());
  new.supply_date_snapshot:=coalesce(new.supply_date_snapshot,sale_supply_date);
  new.seller_legal_name_snapshot:=inst.name;
  new.seller_vat_number_snapshot:=inst.tax_number;
  new.seller_id_scheme_snapshot:=case when nullif(trim(inst.commercial_registration),'') is null then null else 'CRN' end;
  new.seller_id_value_snapshot:=nullif(trim(inst.commercial_registration),'');
  new.seller_street_snapshot:=coalesce(nullif(trim(br.zatca_street_name),''),nullif(trim(inst.zatca_street_name),''));
  new.seller_building_number_snapshot:=coalesce(nullif(trim(br.zatca_building_number),''),nullif(trim(inst.zatca_building_number),''));
  new.seller_additional_number_snapshot:=coalesce(nullif(trim(br.zatca_additional_number),''),nullif(trim(inst.zatca_additional_number),''));
  new.seller_district_snapshot:=coalesce(nullif(trim(br.zatca_district),''),nullif(trim(inst.zatca_district),''));
  new.seller_city_snapshot:=coalesce(nullif(trim(br.zatca_city),''),nullif(trim(inst.zatca_city),''));
  new.seller_postal_code_snapshot:=coalesce(nullif(trim(br.zatca_postal_code),''),nullif(trim(inst.zatca_postal_code),''));
  new.seller_country_code_snapshot:=coalesce(nullif(trim(br.zatca_country_code),''),nullif(trim(inst.zatca_country_code),''),'SA');
  new.buyer_id_scheme_snapshot:=case when nullif(trim(new.customer_commercial_registration),'') is null then null else 'CRN' end;
  new.buyer_id_value_snapshot:=nullif(trim(new.customer_commercial_registration),'');
  new.buyer_additional_number_snapshot:=case when new.invoice_kind='tax'
    then nullif(current_setting('farsha.buyer_additional_number',true),'') end;
  new.buyer_region_snapshot:=case when new.invoice_kind='tax'
    then nullif(current_setting('farsha.buyer_region',true),'') end;
  return new;
end$$;
revoke all on function public.capture_invoice_zatca_snapshot() from public,anon,authenticated;

create or replace function public.prevent_invoice_zatca_snapshot_mutation() returns trigger
language plpgsql set search_path=public as $$
begin
  if old.zatca_uuid is distinct from new.zatca_uuid
    or old.supply_date_snapshot is distinct from new.supply_date_snapshot
    or old.seller_legal_name_snapshot is distinct from new.seller_legal_name_snapshot
    or old.seller_vat_number_snapshot is distinct from new.seller_vat_number_snapshot
    or old.seller_id_scheme_snapshot is distinct from new.seller_id_scheme_snapshot
    or old.seller_id_value_snapshot is distinct from new.seller_id_value_snapshot
    or old.seller_street_snapshot is distinct from new.seller_street_snapshot
    or old.seller_building_number_snapshot is distinct from new.seller_building_number_snapshot
    or old.seller_additional_number_snapshot is distinct from new.seller_additional_number_snapshot
    or old.seller_district_snapshot is distinct from new.seller_district_snapshot
    or old.seller_city_snapshot is distinct from new.seller_city_snapshot
    or old.seller_postal_code_snapshot is distinct from new.seller_postal_code_snapshot
    or old.seller_country_code_snapshot is distinct from new.seller_country_code_snapshot
    or old.buyer_id_scheme_snapshot is distinct from new.buyer_id_scheme_snapshot
    or old.buyer_id_value_snapshot is distinct from new.buyer_id_value_snapshot
    or old.buyer_street_snapshot is distinct from new.buyer_street_snapshot
    or old.buyer_building_number_snapshot is distinct from new.buyer_building_number_snapshot
    or old.buyer_additional_number_snapshot is distinct from new.buyer_additional_number_snapshot
    or old.buyer_region_snapshot is distinct from new.buyer_region_snapshot
    or old.buyer_district_snapshot is distinct from new.buyer_district_snapshot
    or old.buyer_city_snapshot is distinct from new.buyer_city_snapshot
    or old.buyer_postal_code_snapshot is distinct from new.buyer_postal_code_snapshot
    or old.buyer_country_code_snapshot is distinct from new.buyer_country_code_snapshot then
    raise exception 'ZATCA invoice party snapshot is immutable';
  end if;
  if old.xml_content is not null and (
    old.xml_content is distinct from new.xml_content
    or old.xml_standard_version is distinct from new.xml_standard_version
    or old.xml_generator_version is distinct from new.xml_generator_version
    or old.xml_generated_at is distinct from new.xml_generated_at
  ) then
    raise exception 'Generated invoice XML is immutable';
  end if;
  return new;
end$$;
revoke all on function public.prevent_invoice_zatca_snapshot_mutation() from public,anon,authenticated;

-- v3 carries KSA-23 (the four-digit National Address additional number)
-- without breaking the existing v2 RPC. The transaction-local value is read
-- by the existing BEFORE INSERT snapshot trigger and cannot leak to another
-- request/connection.
create or replace function public.issue_tax_invoice_v3(
  p_sale_id uuid,
  p_customer_name text default '',
  p_customer_cr text default '',
  p_customer_tax text default '',
  p_customer_address text default '',
  p_invoice_kind text default 'simplified',
  p_discount numeric default 0,
  p_buyer_street text default '',
  p_buyer_building_number text default '',
  p_buyer_additional_number text default '',
  p_buyer_district text default '',
  p_buyer_city text default '',
  p_buyer_postal_code text default '',
  p_buyer_region text default '',
  p_buyer_country_code text default ''
) returns uuid
language plpgsql security definer set search_path=public as $$
begin
  if p_invoice_kind='tax' and upper(trim(coalesce(p_buyer_country_code,'')))='SA'
    and trim(coalesce(p_buyer_additional_number,'')) !~ '^[0-9]{4}$' then
    raise exception 'Saudi buyer additional number must contain 4 digits';
  end if;
  perform set_config(
    'farsha.buyer_additional_number',
    case when p_invoice_kind='tax' then trim(coalesce(p_buyer_additional_number,'')) else '' end,
    true
  );
  perform set_config(
    'farsha.buyer_region',
    case when p_invoice_kind='tax' then trim(coalesce(p_buyer_region,'')) else '' end,
    true
  );
  return public.issue_tax_invoice_v2(
    p_sale_id,p_customer_name,p_customer_cr,p_customer_tax,p_customer_address,
    p_invoice_kind,p_discount,p_buyer_street,p_buyer_building_number,
    p_buyer_district,p_buyer_city,p_buyer_postal_code,p_buyer_country_code
  );
end$$;

revoke all on function public.issue_tax_invoice_v3(uuid,text,text,text,text,text,numeric,text,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.issue_tax_invoice_v3(uuid,text,text,text,text,text,numeric,text,text,text,text,text,text,text,text) to authenticated;
