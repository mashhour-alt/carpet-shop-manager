insert into public.profiles(id) values('00000000-0000-4000-8000-000000000001');
insert into public.institutions(id) values('00000000-0000-4000-8000-000000000002');
insert into public.branches(id,institution_id) values
  ('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000002'),
  ('00000000-0000-4000-8000-000000000013','00000000-0000-4000-8000-000000000002');
insert into public.invoices(id,institution_id,branch_id,issued_at,invoice_kind,seller_id) values
  ('00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003',now(),'simplified','00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003',now(),'tax','00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000014','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000013',now(),'simplified','00000000-0000-4000-8000-000000000001');

insert into public.zatca_egs_units(
  id,institution_id,unit_name,common_name,egs_serial_number,location,industry,
  invoice_type_map,environment,status,security_activation_at,signer_provider,
  signer_key_reference,created_by
) values
  ('00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000002',
   'Branch A Test EGS','branch-a-test-egs','1-TEST|2-UNIT|3-0001','TEST-A','Test',
   '1100','compliance','active',now()-interval '1 hour','test-provider','test-ref-a',
   '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000016','00000000-0000-4000-8000-000000000002',
   'Branch B Test EGS','branch-b-test-egs','1-TEST|2-UNIT|3-0002','TEST-B','Test',
   '1100','compliance','active',now()-interval '1 hour','test-provider','test-ref-b',
   '00000000-0000-4000-8000-000000000001');
insert into public.zatca_egs_branch_assignments(egs_id,branch_id,assigned_by) values
  ('00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000016','00000000-0000-4000-8000-000000000013','00000000-0000-4000-8000-000000000001');
insert into public.zatca_egs_certificates(
  id,egs_id,environment,status,certificate_identifier,issuer_name,serial_number,
  certificate_chain,public_key_p1363_base64,zatca_ca_signature_p1363_base64,
  valid_from,valid_until
) values(
  '00000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-000000000006',
  'compliance','active','ci-test-csid','CI test issuer','1',
  '[{"der_base64":"VEVTVA==","issuer_name":"CI test issuer","serial_number":"1"}]',
  repeat('F',86)||'==',repeat('G',86)||'==',now()-interval '1 day',now()+interval '1 day'
);
