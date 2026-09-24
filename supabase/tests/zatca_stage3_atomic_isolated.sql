do $$
declare
  v_token uuid;
  v_signing_time timestamptz:=date_trunc('second',now());
  v_result record;
  v_initial_pih text:='NWZlY2ViNjZmZmM4NmYzOGQ5NTI3ODZjNmQ2OTZjNzljMmRiYzIzOWRkNGU5MWI0NjcyOWQ3M2EyN2ZiNTdlOQ==';
begin
  select reservation_token into v_token
  from public.zatca_issuance_reservations
  where egs_id='00000000-0000-4000-8000-000000000006';
  if v_token is null then raise exception 'Concurrent winner reservation is missing'; end if;

  if public.record_zatca_issuance_failure(v_token,'CI_TEST_TIMEOUT','ci-failure')<>1 then
    raise exception 'Failure count did not increment';
  end if;
  if exists(
    select 1 from public.zatca_egs_units
    where id='00000000-0000-4000-8000-000000000006'
      and (last_committed_icv<>0 or last_invoice_hash<>v_initial_pih)
  ) then raise exception 'Failure consumed ICV or changed PIH'; end if;

  select * into v_result from public.finalize_zatca_issuance(
    v_token,'00000000-0000-4000-8000-000000000007','simplified_reporting',
    repeat('C',43)||'=',repeat('D',43)||'=',repeat('E',86)||'==','VEVTVFFS',
    '<Invoice>CI TEST</Invoice>',v_signing_time,'stage3-ci-db-test','ci-finalize'
  );
  if v_result.idempotent or v_result.icv<>1 then raise exception 'Finalization failed'; end if;

  select * into v_result from public.finalize_zatca_issuance(
    v_token,'00000000-0000-4000-8000-000000000007','simplified_reporting',
    repeat('C',43)||'=',repeat('D',43)||'=',repeat('E',86)||'==','VEVTVFFS',
    '<Invoice>CI TEST</Invoice>',v_signing_time,'stage3-ci-db-test','ci-finalize-retry'
  );
  if not v_result.idempotent then raise exception 'Finalization retry was not idempotent'; end if;

  select * into v_result from public.reserve_zatca_issuance(
    '00000000-0000-4000-8000-000000000005',
    '00000000-0000-4000-8000-000000000006',repeat('B',43)||'=','ci-standard'
  );
  if v_result.icv<>2 or v_result.previous_invoice_hash<>(repeat('C',43)||'=') then
    raise exception 'Second invoice did not inherit first invoice hash';
  end if;
  begin
    perform public.finalize_zatca_issuance(
      v_result.reservation_token,'00000000-0000-4000-8000-000000000007',
      'simplified_reporting',repeat('H',43)||'=',repeat('D',43)||'=',
      repeat('E',86)||'==','VEVTVFFS','<Invoice>STANDARD</Invoice>',
      v_signing_time,'stage3-ci-db-test','ci-wrong-standard-flow'
    );
    raise exception 'Expected standard local workflow rejection';
  exception when others then
    if sqlerrm='Expected standard local workflow rejection' then raise; end if;
    if position('does not match invoice kind' in sqlerrm)=0 then raise; end if;
  end;

  select * into v_result from public.reserve_zatca_issuance(
    '00000000-0000-4000-8000-000000000014',
    '00000000-0000-4000-8000-000000000016',repeat('I',43)||'=','ci-branch-b'
  );
  if v_result.icv<>1 or v_result.previous_invoice_hash<>v_initial_pih then
    raise exception 'Branch B / EGS B chain was not isolated';
  end if;
end
$$;

select
  (select count(*) from public.zatca_issuance_reservations
    where egs_id='00000000-0000-4000-8000-000000000006' and icv=1) as race_winners,
  (select last_committed_icv from public.zatca_egs_units
    where id='00000000-0000-4000-8000-000000000006') as branch_a_committed_icv,
  (select icv from public.zatca_issuance_reservations
    where egs_id='00000000-0000-4000-8000-000000000016') as branch_b_first_icv,
  (select count(*) from public.zatca_security_audit_events) as audit_events;
