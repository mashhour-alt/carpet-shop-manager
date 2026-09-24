-- Stage 3 transactional proof. Every test row is rolled back.
begin;

do $$
declare
  v_owner uuid;
  v_seller uuid;
  v_institution uuid:=gen_random_uuid();
  v_branch uuid:=gen_random_uuid();
  v_supplier uuid:=gen_random_uuid();
  v_inventory uuid:=gen_random_uuid();
  v_sale_one uuid;
  v_sale_two uuid;
  v_invoice_one uuid;
  v_invoice_two uuid;
  v_egs uuid:=gen_random_uuid();
  v_other_egs uuid:=gen_random_uuid();
  v_certificate uuid:=gen_random_uuid();
  v_first record;
  v_retry record;
  v_standard record;
  v_final record;
  v_final_retry record;
  v_signing_time timestamptz:=date_trunc('second',now());
  v_initial_pih text:='NWZlY2ViNjZmZmM4NmYzOGQ5NTI3ODZjNmQ2OTZjNzljMmRiYzIzOWRkNGU5MWI0NjcyOWQ3M2EyN2ZiNTdlOQ==';
  v_business_hash text:=repeat('A',43)||'=';
  v_standard_business_hash text:=repeat('B',43)||'=';
  v_invoice_hash text:=repeat('C',43)||'=';
  v_properties_hash text:=repeat('D',43)||'=';
  v_signature text:=repeat('E',86)||'==';
begin
  select user_id into v_owner
  from public.institution_memberships
  where role='owner' and status='active'
  order by created_at,user_id limit 1;
  select user_id into v_seller
  from public.institution_memberships
  where role='seller' and status='active' and user_id<>v_owner
  order by created_at,user_id limit 1;
  if v_owner is null or v_seller is null then
    raise exception 'Stage 3 DB test needs one owner and one seller profile';
  end if;

  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);

  insert into public.institutions(
    id,name,commercial_registration,tax_number,address,phone,email,created_by,
    zatca_street_name,zatca_building_number,zatca_additional_number,zatca_district,zatca_city,
    zatca_postal_code,zatca_country_code
  ) values(
    v_institution,'Stage 3 Test Seller','1010000000','310000000000003',
    'Test National Address','0500000000','stage3@example.test',v_owner,
    'Test Street','1234','5678','Test District','Riyadh','12345','SA'
  );
  insert into public.institution_memberships(institution_id,user_id,role)
    values(v_institution,v_owner,'owner'),(v_institution,v_seller,'seller');
  insert into public.branches(id,institution_id,name,code,city,address,phone,is_default,created_by)
    values(v_branch,v_institution,'Stage 3 Test Branch','S3','Riyadh','Test Address','0500000000',true,v_owner);
  insert into public.suppliers(id,institution_id,name,phone)
    values(v_supplier,v_institution,'Stage 3 Test Supplier','0500000001');
  insert into public.inventory_items(
    id,institution_id,branch_id,name,color,remaining_length,width,wholesale_price,low_stock_at
  ) values(v_inventory,v_institution,v_branch,'Test Carpet','Blue',20,4,20,1);
  insert into public.inventory_costs(inventory_id,institution_id,supplier_id,supplier_price)
    values(v_inventory,v_institution,v_supplier,15);

  v_sale_one:=public.record_sale_financial_v2(
    v_institution,v_inventory,v_seller,null,'Cash Customer',1.234,37.89,0,
    'Stage 3 simplified security test',
    '[{"method":"cash","amount":236.29,"reference":"S3-CASH"}]'::jsonb,
    '[{"name":"Installation","unit":"piece","quantity":1,"sale_unit_price":5.55,"cost_unit_price":0},{"name":"Felt","unit":"piece","quantity":2,"sale_unit_price":10.01,"cost_unit_price":0}]'::jsonb,
    7.13
  );
  v_invoice_one:=public.issue_tax_invoice_v3(
    v_sale_one,'Cash Customer','','','','simplified',7.13,'','','','','','','',''
  );

  v_sale_two:=public.record_sale_financial_v2(
    v_institution,v_inventory,v_seller,null,'Stage 3 Test Buyer',1.234,37.89,0,
    'Stage 3 standard security test',
    '[{"method":"cash","amount":236.29,"reference":"S3-CASH-2"}]'::jsonb,
    '[{"name":"Installation","unit":"piece","quantity":1,"sale_unit_price":5.55,"cost_unit_price":0},{"name":"Felt","unit":"piece","quantity":2,"sale_unit_price":10.01,"cost_unit_price":0}]'::jsonb,
    7.13
  );
  v_invoice_two:=public.issue_tax_invoice_v3(
    v_sale_two,'Stage 3 Test Buyer','1010000001','310000000000013',
    'Buyer Street, Buyer District, Riyadh 12345','tax',7.13,
    'Buyer Street','5678','4321','Buyer District','Riyadh','12345','Riyadh Region','SA'
  );

  insert into public.zatca_egs_units(
    id,institution_id,unit_name,common_name,egs_serial_number,location,industry,
    invoice_type_map,environment,status,security_activation_at,signer_provider,
    signer_key_reference,created_by
  ) values(
    v_egs,v_institution,'Stage 3 Test EGS','stage3-test-egs',
    '1-FARSHA-TEST|2-UNIT|3-0001','TEST-RIYADH-ONLY','Carpet retail test fixture',
    '1100','compliance','active',now()-interval '1 hour','test-non-exportable-provider',
    'test-key-reference-not-key-material',v_owner
  );
  insert into public.zatca_egs_branch_assignments(egs_id,branch_id,assigned_by)
    values(v_egs,v_branch,v_owner);
  insert into public.zatca_egs_certificates(
    id,egs_id,environment,status,certificate_identifier,issuer_name,serial_number,
    certificate_chain,public_key_p1363_base64,zatca_ca_signature_p1363_base64,
    valid_from,valid_until
  ) values(
    v_certificate,v_egs,'compliance','active','stage3-test-csid',
    'C=SA,O=Farsha Test Only,CN=Stage3 Test CSID','424242',
    '[{"der_base64":"VEVTVA==","issuer_name":"Test issuer","serial_number":"424242"}]'::jsonb,
    repeat('F',86)||'==',repeat('G',86)||'==',now()-interval '1 day',now()+interval '1 day'
  );

  -- A distinct EGS cannot claim an invoice merely because it belongs to the
  -- same institution. Future activation is also rejected without backfill.
  insert into public.zatca_egs_units(
    id,institution_id,unit_name,common_name,egs_serial_number,location,industry,
    invoice_type_map,environment,status,security_activation_at,signer_provider,
    signer_key_reference,created_by
  ) values(
    v_other_egs,v_institution,'Other Stage 3 Test EGS','stage3-test-egs-2',
    '1-FARSHA-TEST|2-UNIT|3-0002','TEST-JEDDAH-ONLY','Carpet retail test fixture',
    '1100','compliance','active',now()+interval '1 hour','test-provider','other-test-key-ref',v_owner
  );
  begin
    perform public.reserve_zatca_issuance(v_invoice_one,v_other_egs,v_business_hash,'future-activation-test');
    raise exception 'Expected historical cutover rejection';
  exception when others then
    if sqlerrm='Expected historical cutover rejection' then raise; end if;
    if position('predates EGS security activation' in sqlerrm)=0 then raise; end if;
  end;
  update public.zatca_egs_units set security_activation_at=now()-interval '1 hour' where id=v_other_egs;
  begin
    perform public.reserve_zatca_issuance(v_invoice_one,v_other_egs,v_business_hash,'wrong-egs-test');
    raise exception 'Expected EGS branch assignment rejection';
  exception when others then
    if sqlerrm='Expected EGS branch assignment rejection' then raise; end if;
    if position('not assigned to this EGS' in sqlerrm)=0 then raise; end if;
  end;

  select * into v_first
  from public.reserve_zatca_issuance(v_invoice_one,v_egs,v_business_hash,'reserve-first');
  if v_first.icv<>1 or v_first.previous_invoice_hash<>v_initial_pih or v_first.idempotent then
    raise exception 'First EGS reservation did not return ICV=1 and official initial PIH';
  end if;

  if public.record_zatca_issuance_failure(v_first.reservation_token,'TEST_SIGNER_TIMEOUT','retry-failure')<>1 then
    raise exception 'Retry failure count did not increment';
  end if;
  if exists(
    select 1 from public.zatca_egs_units
    where id=v_egs and (last_committed_icv<>0 or last_invoice_hash<>v_initial_pih)
  ) then
    raise exception 'Failed signing consumed an ICV or changed PIH';
  end if;

  select * into v_retry
  from public.reserve_zatca_issuance(v_invoice_one,v_egs,v_business_hash,'reserve-retry');
  if not v_retry.idempotent or v_retry.reservation_token<>v_first.reservation_token or
     v_retry.icv<>v_first.icv or v_retry.previous_invoice_hash<>v_first.previous_invoice_hash then
    raise exception 'Retry changed reserved identity, ICV or PIH';
  end if;

  select * into v_final
  from public.finalize_zatca_issuance(
    v_first.reservation_token,v_certificate,'simplified_reporting',v_invoice_hash,
    v_properties_hash,v_signature,'VEVTVFFS',
    '<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2">TEST</Invoice>',
    v_signing_time,'stage3-db-test','finalize-first'
  );
  if v_final.idempotent or v_final.icv<>1 or v_final.invoice_hash<>v_invoice_hash then
    raise exception 'First atomic finalization returned unexpected values';
  end if;
  if exists(
    select 1 from public.zatca_egs_units
    where id=v_egs and (last_committed_icv<>1 or last_invoice_hash<>v_invoice_hash)
  ) then
    raise exception 'Atomic finalization did not advance the exact EGS chain head';
  end if;

  select * into v_final_retry
  from public.finalize_zatca_issuance(
    v_first.reservation_token,v_certificate,'simplified_reporting',v_invoice_hash,
    v_properties_hash,v_signature,'VEVTVFFS',
    '<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2">TEST</Invoice>',
    v_signing_time,'stage3-db-test','finalize-retry'
  );
  if not v_final_retry.idempotent or v_final_retry.icv<>v_final.icv then
    raise exception 'Exact finalization retry was not idempotent';
  end if;
  begin
    perform public.finalize_zatca_issuance(
      v_first.reservation_token,v_certificate,'simplified_reporting',repeat('Z',43)||'=',
      v_properties_hash,v_signature,'VEVTVFFS',
      '<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2">TEST</Invoice>',
      v_signing_time,'stage3-db-test','tampered-retry'
    );
    raise exception 'Expected immutable finalization mismatch rejection';
  exception when others then
    if sqlerrm='Expected immutable finalization mismatch rejection' then raise; end if;
    if position('does not match immutable final result' in sqlerrm)=0 then raise; end if;
  end;

  -- Standard invoices reserve the next chain identity for future clearance,
  -- but the local simplified-reporting workflow is forbidden.
  select * into v_standard
  from public.reserve_zatca_issuance(v_invoice_two,v_egs,v_standard_business_hash,'standard-reserve');
  if v_standard.icv<>2 or v_standard.previous_invoice_hash<>v_invoice_hash then
    raise exception 'Standard reservation did not chain to the simplified invoice';
  end if;
  begin
    perform public.finalize_zatca_issuance(
      v_standard.reservation_token,v_certificate,'simplified_reporting',repeat('H',43)||'=',
      v_properties_hash,v_signature,'VEVTVFFS','<Invoice>STANDARD</Invoice>',
      v_signing_time,'stage3-db-test','standard-wrong-workflow'
    );
    raise exception 'Expected standard local workflow rejection';
  exception when others then
    if sqlerrm='Expected standard local workflow rejection' then raise; end if;
    if position('does not match invoice kind' in sqlerrm)=0 then raise; end if;
  end;
  if exists(
    select 1 from public.zatca_egs_units
    where id=v_egs and (last_committed_icv<>1 or last_invoice_hash<>v_invoice_hash)
  ) then
    raise exception 'Rejected standard flow changed EGS chain head';
  end if;

  begin
    update public.zatca_egs_units set last_committed_icv=99 where id=v_egs;
    raise exception 'Expected direct chain-head mutation rejection';
  exception when others then
    if sqlerrm='Expected direct chain-head mutation rejection' then raise; end if;
    if position('atomic finalization' in sqlerrm)=0 then raise; end if;
  end;
  begin
    update public.zatca_invoice_security_states set invoice_hash=repeat('I',43)||'='
    where invoice_id=v_invoice_one;
    raise exception 'Expected immutable security-state rejection';
  exception when others then
    if sqlerrm='Expected immutable security-state rejection' then raise; end if;
    if position('immutable' in sqlerrm)=0 then raise; end if;
  end;

  if (select count(*) from public.zatca_security_audit_events where egs_id=v_egs)<>4 then
    raise exception 'Expected reserve, failure, finalize and second reserve audit events';
  end if;
  if exists(
    select 1 from public.zatca_security_audit_events
    where egs_id=v_egs and event_data::text ~* '(private.?key|otp|binary.?secret|oauth.?secret)'
  ) then
    raise exception 'Audit metadata contains prohibited secret-shaped data';
  end if;
end
$$;

rollback;
