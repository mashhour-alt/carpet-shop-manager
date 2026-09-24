-- Stage 3: server-side ZATCA security state. This migration does not provision
-- production credentials and does not call reporting or clearance APIs.

create type public.zatca_egs_status as enum ('draft','active','suspended','revoked');
create type public.zatca_certificate_environment as enum ('compliance','production');
create type public.zatca_certificate_status as enum ('pending','active','expired','revoked');
create type public.zatca_issuance_status as enum ('pending','completed');
create type public.zatca_security_workflow as enum ('simplified_reporting','standard_clearance');

create table public.zatca_egs_units(
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete restrict,
  unit_name text not null check(length(trim(unit_name)) between 1 and 120),
  common_name text not null check(length(trim(common_name)) between 1 and 200),
  egs_serial_number text not null check(egs_serial_number ~ '^1-[^|]+\|2-[^|]+\|3-[^|]+$'),
  location text not null check(length(trim(location)) between 1 and 200),
  industry text not null check(length(trim(industry)) between 1 and 200),
  invoice_type_map text not null check(invoice_type_map ~ '^[01]{4}$' and invoice_type_map <> '0000'),
  environment public.zatca_certificate_environment not null default 'compliance',
  status public.zatca_egs_status not null default 'draft',
  security_activation_at timestamptz,
  signer_provider text check(signer_provider is null or length(trim(signer_provider)) between 1 and 80),
  signer_key_reference text check(signer_key_reference is null or length(trim(signer_key_reference)) between 1 and 500),
  last_committed_icv bigint not null default 0 check(last_committed_icv >= 0),
  last_invoice_hash text not null default 'NWZlY2ViNjZmZmM4NmYzOGQ5NTI3ODZjNmQ2OTZjNzljMmRiYzIzOWRkNGU5MWI0NjcyOWQ3M2EyN2ZiNTdlOQ=='
    check(length(last_invoice_hash) in (44,88) and last_invoice_hash ~ '^[A-Za-z0-9+/]+={0,2}$'),
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(institution_id,egs_serial_number,environment),
  check(
    status <> 'active' or
    (security_activation_at is not null and signer_provider is not null and signer_key_reference is not null)
  )
);

comment on column public.zatca_egs_units.signer_key_reference is
  'Opaque identifier for a non-exportable key held by an external HSM/KMS/security module; never key material.';
comment on column public.zatca_egs_units.security_activation_at is
  'Explicit cutover only. Historical invoices are never silently inserted into a new ICV/PIH chain.';

create table public.zatca_egs_branch_assignments(
  id uuid primary key default gen_random_uuid(),
  egs_id uuid not null references public.zatca_egs_units(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  active boolean not null default true,
  assigned_at timestamptz not null default now(),
  assigned_by uuid references public.profiles(id) on delete restrict,
  unique(egs_id,branch_id)
);

create unique index zatca_one_active_egs_per_branch_idx
  on public.zatca_egs_branch_assignments(branch_id) where active;
create index zatca_egs_branch_assignments_egs_idx
  on public.zatca_egs_branch_assignments(egs_id,active);

create table public.zatca_egs_certificates(
  id uuid primary key default gen_random_uuid(),
  egs_id uuid not null references public.zatca_egs_units(id) on delete restrict,
  environment public.zatca_certificate_environment not null,
  status public.zatca_certificate_status not null default 'pending',
  certificate_identifier text not null unique check(length(trim(certificate_identifier)) between 1 and 200),
  issuer_name text not null check(length(trim(issuer_name)) between 1 and 500),
  serial_number text not null check(length(trim(serial_number)) between 1 and 200),
  certificate_chain jsonb not null
    check(jsonb_typeof(certificate_chain)='array' and jsonb_array_length(certificate_chain)>0),
  public_key_p1363_base64 text not null
    check(length(public_key_p1363_base64)=88 and public_key_p1363_base64 ~ '^[A-Za-z0-9+/]+={0,2}$'),
  zatca_ca_signature_p1363_base64 text
    check(zatca_ca_signature_p1363_base64 is null or
      (length(zatca_ca_signature_p1363_base64)=88 and zatca_ca_signature_p1363_base64 ~ '^[A-Za-z0-9+/]+={0,2}$')),
  oauth_secret_reference text
    check(oauth_secret_reference is null or length(trim(oauth_secret_reference)) between 1 and 500),
  valid_from timestamptz not null,
  valid_until timestamptz not null,
  issued_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check(valid_until>valid_from),
  check((status='revoked')=(revoked_at is not null))
);

comment on column public.zatca_egs_certificates.oauth_secret_reference is
  'Opaque secret-manager reference only. OTP, binary secret and private key material are forbidden here.';
comment on column public.zatca_egs_certificates.certificate_chain is
  'Public leaf-first array of {der_base64,issuer_name,serial_number}; never private key material.';

create index zatca_egs_certificates_egs_status_idx
  on public.zatca_egs_certificates(egs_id,status,valid_until);
create unique index zatca_one_active_certificate_per_egs_environment_idx
  on public.zatca_egs_certificates(egs_id,environment) where status='active';

create table public.zatca_issuance_reservations(
  id uuid primary key default gen_random_uuid(),
  reservation_token uuid not null unique default gen_random_uuid(),
  invoice_id uuid not null unique references public.invoices(id) on delete restrict,
  egs_id uuid not null references public.zatca_egs_units(id) on delete restrict,
  icv bigint not null check(icv>0),
  previous_invoice_hash text not null
    check(length(previous_invoice_hash) in (44,88) and previous_invoice_hash ~ '^[A-Za-z0-9+/]+={0,2}$'),
  business_xml_sha256 text not null
    check(length(business_xml_sha256)=44 and business_xml_sha256 ~ '^[A-Za-z0-9+/]{43}=$'),
  status public.zatca_issuance_status not null default 'pending',
  failure_count integer not null default 0 check(failure_count>=0),
  last_failure_code text check(last_failure_code is null or length(last_failure_code)<=120),
  last_failure_at timestamptz,
  reserved_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(egs_id,icv),
  check((status='completed')=(completed_at is not null))
);

create unique index zatca_one_pending_issuance_per_egs_idx
  on public.zatca_issuance_reservations(egs_id) where status='pending';
create index zatca_issuance_reservations_egs_status_idx
  on public.zatca_issuance_reservations(egs_id,status,reserved_at);

create table public.zatca_invoice_security_states(
  invoice_id uuid primary key references public.invoices(id) on delete restrict,
  reservation_id uuid not null unique references public.zatca_issuance_reservations(id) on delete restrict,
  egs_id uuid not null references public.zatca_egs_units(id) on delete restrict,
  certificate_id uuid not null references public.zatca_egs_certificates(id) on delete restrict,
  workflow public.zatca_security_workflow not null,
  icv bigint not null check(icv>0),
  previous_invoice_hash text not null
    check(length(previous_invoice_hash) in (44,88) and previous_invoice_hash ~ '^[A-Za-z0-9+/]+={0,2}$'),
  business_xml_sha256 text not null
    check(length(business_xml_sha256)=44 and business_xml_sha256 ~ '^[A-Za-z0-9+/]{43}=$'),
  invoice_hash text not null
    check(length(invoice_hash)=44 and invoice_hash ~ '^[A-Za-z0-9+/]{43}=$'),
  signed_properties_digest text not null
    check(length(signed_properties_digest)=44 and signed_properties_digest ~ '^[A-Za-z0-9+/]{43}=$'),
  signature_value text not null
    check(length(signature_value)=88 and signature_value ~ '^[A-Za-z0-9+/]+={0,2}$'),
  qr_code text not null check(length(qr_code) between 1 and 700),
  signed_xml text not null check(length(signed_xml)>0),
  signing_time timestamptz not null,
  security_standard_version text not null default 'ZATCA Security Features 1.2',
  generator_version text not null check(length(trim(generator_version)) between 1 and 80),
  created_at timestamptz not null default now(),
  unique(egs_id,icv)
);

create index zatca_invoice_security_states_egs_created_idx
  on public.zatca_invoice_security_states(egs_id,created_at desc);
create index zatca_invoice_security_states_certificate_idx
  on public.zatca_invoice_security_states(certificate_id);

create table public.zatca_security_audit_events(
  id bigint generated always as identity primary key,
  institution_id uuid not null references public.institutions(id) on delete restrict,
  egs_id uuid references public.zatca_egs_units(id) on delete restrict,
  invoice_id uuid references public.invoices(id) on delete restrict,
  certificate_id uuid references public.zatca_egs_certificates(id) on delete restrict,
  event_type text not null check(event_type in(
    'issuance_reserved','issuance_retry_failed','issuance_finalized'
  )),
  event_data jsonb not null default '{}'::jsonb check(jsonb_typeof(event_data)='object'),
  actor_user_id uuid references public.profiles(id) on delete restrict,
  request_id text check(request_id is null or length(request_id)<=200),
  created_at timestamptz not null default now()
);

create index zatca_security_audit_institution_created_idx
  on public.zatca_security_audit_events(institution_id,created_at desc);
create index zatca_security_audit_egs_created_idx
  on public.zatca_security_audit_events(egs_id,created_at desc);
create index zatca_security_audit_invoice_idx
  on public.zatca_security_audit_events(invoice_id);

create or replace function public.validate_zatca_egs_branch_assignment()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_egs_institution uuid;
  v_branch_institution uuid;
begin
  select institution_id into v_egs_institution from public.zatca_egs_units where id=new.egs_id;
  select institution_id into v_branch_institution from public.branches where id=new.branch_id;
  if v_egs_institution is null or v_branch_institution is null or v_egs_institution<>v_branch_institution then
    raise exception 'EGS and branch must belong to the same institution';
  end if;
  return new;
end
$$;

revoke all on function public.validate_zatca_egs_branch_assignment() from public,anon,authenticated;
create trigger validate_zatca_egs_branch_assignment
before insert or update on public.zatca_egs_branch_assignments
for each row execute function public.validate_zatca_egs_branch_assignment();

create or replace function public.protect_zatca_egs_chain_head()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if (old.last_committed_icv is distinct from new.last_committed_icv or
      old.last_invoice_hash is distinct from new.last_invoice_hash) and
     coalesce(current_setting('farsha.zatca_chain_write',true),'')<>'on' then
    raise exception 'EGS ICV/PIH chain head may only be changed by atomic finalization';
  end if;
  return new;
end
$$;

revoke all on function public.protect_zatca_egs_chain_head() from public,anon,authenticated;
create trigger protect_zatca_egs_chain_head
before update on public.zatca_egs_units
for each row execute function public.protect_zatca_egs_chain_head();

create or replace function public.protect_zatca_reservation_mutation()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if coalesce(current_setting('farsha.zatca_reservation_write',true),'')<>'on' then
    raise exception 'ZATCA issuance reservation may only be changed by the issuance service';
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$$;

revoke all on function public.protect_zatca_reservation_mutation() from public,anon,authenticated;
create trigger protect_zatca_reservation_mutation
before update or delete on public.zatca_issuance_reservations
for each row execute function public.protect_zatca_reservation_mutation();

create or replace function public.reject_zatca_immutable_mutation()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  raise exception 'Final ZATCA security and audit records are immutable';
end
$$;

revoke all on function public.reject_zatca_immutable_mutation() from public,anon,authenticated;
create trigger zatca_security_state_immutable
before update or delete on public.zatca_invoice_security_states
for each row execute function public.reject_zatca_immutable_mutation();
create trigger zatca_security_audit_immutable
before update or delete on public.zatca_security_audit_events
for each row execute function public.reject_zatca_immutable_mutation();

create or replace function public.reserve_zatca_issuance(
  p_invoice_id uuid,
  p_egs_id uuid,
  p_business_xml_sha256 text,
  p_request_id text default null
) returns table(
  reservation_id uuid,
  reservation_token uuid,
  icv bigint,
  previous_invoice_hash text,
  issuance_status public.zatca_issuance_status,
  idempotent boolean
)
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_egs public.zatca_egs_units%rowtype;
  v_invoice public.invoices%rowtype;
  v_existing public.zatca_issuance_reservations%rowtype;
  v_pending_invoice uuid;
begin
  if p_business_xml_sha256 is null or p_business_xml_sha256 !~ '^[A-Za-z0-9+/]{43}=$' then
    raise exception 'Business XML SHA-256 must be a 32-byte Base64 digest';
  end if;

  select * into v_egs from public.zatca_egs_units where id=p_egs_id for update;
  if not found then raise exception 'EGS unit was not found'; end if;
  if v_egs.status<>'active' then raise exception 'EGS unit is not active'; end if;
  if v_egs.security_activation_at is null then raise exception 'EGS security activation time is missing'; end if;
  if v_egs.signer_provider is null or v_egs.signer_key_reference is null then
    raise exception 'EGS non-exportable signer is not configured';
  end if;

  select * into v_invoice from public.invoices where id=p_invoice_id;
  if not found then raise exception 'Invoice was not found'; end if;
  if v_invoice.institution_id<>v_egs.institution_id then
    raise exception 'Invoice and EGS must belong to the same institution';
  end if;
  if v_invoice.issued_at<v_egs.security_activation_at then
    raise exception 'Historical invoice predates EGS security activation';
  end if;
  if not exists(
    select 1 from public.zatca_egs_branch_assignments a
    where a.egs_id=p_egs_id and a.branch_id=v_invoice.branch_id and a.active
  ) then
    raise exception 'Invoice branch is not assigned to this EGS';
  end if;

  select * into v_existing
  from public.zatca_issuance_reservations
  where invoice_id=p_invoice_id;
  if found then
    if v_existing.egs_id<>p_egs_id or v_existing.business_xml_sha256<>p_business_xml_sha256 then
      raise exception 'Invoice already has a reservation with different immutable input';
    end if;
    return query select v_existing.id,v_existing.reservation_token,v_existing.icv,
      v_existing.previous_invoice_hash,v_existing.status,true;
    return;
  end if;

  select invoice_id into v_pending_invoice
  from public.zatca_issuance_reservations
  where egs_id=p_egs_id and status='pending';
  if found then
    raise exception 'EGS issuance is already pending for invoice %',v_pending_invoice;
  end if;

  insert into public.zatca_issuance_reservations(
    invoice_id,egs_id,icv,previous_invoice_hash,business_xml_sha256
  ) values(
    p_invoice_id,p_egs_id,v_egs.last_committed_icv+1,v_egs.last_invoice_hash,p_business_xml_sha256
  ) returning * into v_existing;

  insert into public.zatca_security_audit_events(
    institution_id,egs_id,invoice_id,event_type,event_data,actor_user_id,request_id
  ) values(
    v_egs.institution_id,p_egs_id,p_invoice_id,'issuance_reserved',
    jsonb_build_object('icv',v_existing.icv,'previous_invoice_hash',v_existing.previous_invoice_hash),
    auth.uid(),left(p_request_id,200)
  );

  return query select v_existing.id,v_existing.reservation_token,v_existing.icv,
    v_existing.previous_invoice_hash,v_existing.status,false;
end
$$;

create or replace function public.record_zatca_issuance_failure(
  p_reservation_token uuid,
  p_failure_code text,
  p_request_id text default null
) returns integer
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_reservation public.zatca_issuance_reservations%rowtype;
  v_institution_id uuid;
begin
  if p_failure_code is null or length(trim(p_failure_code)) not between 1 and 120 then
    raise exception 'Failure code must contain 1-120 characters';
  end if;
  select * into v_reservation from public.zatca_issuance_reservations
  where reservation_token=p_reservation_token for update;
  if not found then raise exception 'Issuance reservation was not found'; end if;
  if v_reservation.status<>'pending' then raise exception 'Completed issuance cannot be marked failed'; end if;
  select institution_id into v_institution_id from public.zatca_egs_units where id=v_reservation.egs_id;
  perform set_config('farsha.zatca_reservation_write','on',true);
  update public.zatca_issuance_reservations
  set failure_count=failure_count+1,last_failure_code=trim(p_failure_code),last_failure_at=now()
  where id=v_reservation.id returning failure_count into v_reservation.failure_count;
  perform set_config('farsha.zatca_reservation_write','off',true);
  insert into public.zatca_security_audit_events(
    institution_id,egs_id,invoice_id,event_type,event_data,actor_user_id,request_id
  ) values(
    v_institution_id,v_reservation.egs_id,v_reservation.invoice_id,'issuance_retry_failed',
    jsonb_build_object('icv',v_reservation.icv,'failure_code',trim(p_failure_code),
      'failure_count',v_reservation.failure_count),auth.uid(),left(p_request_id,200)
  );
  return v_reservation.failure_count;
end
$$;

create or replace function public.finalize_zatca_issuance(
  p_reservation_token uuid,
  p_certificate_id uuid,
  p_workflow public.zatca_security_workflow,
  p_invoice_hash text,
  p_signed_properties_digest text,
  p_signature_value text,
  p_qr_code text,
  p_signed_xml text,
  p_signing_time timestamptz,
  p_generator_version text,
  p_request_id text default null
) returns table(
  invoice_id uuid,
  egs_id uuid,
  icv bigint,
  invoice_hash text,
  idempotent boolean
)
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_reservation public.zatca_issuance_reservations%rowtype;
  v_egs public.zatca_egs_units%rowtype;
  v_invoice public.invoices%rowtype;
  v_certificate public.zatca_egs_certificates%rowtype;
  v_final public.zatca_invoice_security_states%rowtype;
begin
  if p_invoice_hash !~ '^[A-Za-z0-9+/]{43}=$' or
     p_signed_properties_digest !~ '^[A-Za-z0-9+/]{43}=$' then
    raise exception 'Invoice and SignedProperties hashes must be 32-byte Base64 digests';
  end if;
  if p_signature_value is null or length(p_signature_value)<>88 or
     p_signature_value !~ '^[A-Za-z0-9+/]+={0,2}$' then
    raise exception 'SignatureValue must be a 64-byte Base64 IEEE P1363 signature';
  end if;
  if p_qr_code is null or length(p_qr_code) not between 1 and 700 then
    raise exception 'QR payload must contain 1-700 characters';
  end if;
  if p_signed_xml is null or length(p_signed_xml)=0 then raise exception 'Signed XML is required'; end if;
  if p_signing_time is null then raise exception 'Signing time is required'; end if;
  if p_generator_version is null or length(trim(p_generator_version)) not between 1 and 80 then
    raise exception 'Generator version is required';
  end if;

  select r.* into v_reservation from public.zatca_issuance_reservations r
  where r.reservation_token=p_reservation_token for update;
  if not found then raise exception 'Issuance reservation was not found'; end if;
  select e.* into v_egs from public.zatca_egs_units e
  where e.id=v_reservation.egs_id for update;
  select i.* into v_invoice from public.invoices i where i.id=v_reservation.invoice_id;

  if v_reservation.status='completed' then
    select s.* into v_final from public.zatca_invoice_security_states s
    where s.reservation_id=v_reservation.id;
    if v_final.certificate_id is distinct from p_certificate_id or
       v_final.workflow is distinct from p_workflow or
       v_final.invoice_hash is distinct from p_invoice_hash or
       v_final.signed_properties_digest is distinct from p_signed_properties_digest or
       v_final.signature_value is distinct from p_signature_value or
       v_final.qr_code is distinct from p_qr_code or
       v_final.signed_xml is distinct from p_signed_xml or
       v_final.signing_time is distinct from p_signing_time or
       v_final.generator_version is distinct from trim(p_generator_version) then
      raise exception 'Completed issuance retry does not match immutable final result';
    end if;
    return query select v_final.invoice_id,v_final.egs_id,v_final.icv,v_final.invoice_hash,true;
    return;
  end if;

  if v_egs.last_committed_icv+1<>v_reservation.icv or
     v_egs.last_invoice_hash<>v_reservation.previous_invoice_hash then
    raise exception 'EGS chain head no longer matches the reservation';
  end if;
  if (v_invoice.invoice_kind='simplified' and p_workflow<>'simplified_reporting') or
     (v_invoice.invoice_kind='tax' and p_workflow<>'standard_clearance') then
    raise exception 'Security workflow does not match invoice kind';
  end if;

  select c.* into v_certificate from public.zatca_egs_certificates c
  where c.id=p_certificate_id and c.egs_id=v_egs.id;
  if not found then raise exception 'Certificate does not belong to the reserved EGS'; end if;
  if v_certificate.status<>'active' or v_certificate.environment<>v_egs.environment or
     p_signing_time<v_certificate.valid_from or p_signing_time>=v_certificate.valid_until then
    raise exception 'Certificate is not active and valid for this EGS environment/signing time';
  end if;
  if p_workflow='simplified_reporting' and v_certificate.zatca_ca_signature_p1363_base64 is null then
    raise exception 'Simplified invoice certificate is missing ZATCA CA public-key signature';
  end if;

  insert into public.zatca_invoice_security_states(
    invoice_id,reservation_id,egs_id,certificate_id,workflow,icv,previous_invoice_hash,
    business_xml_sha256,invoice_hash,signed_properties_digest,signature_value,qr_code,
    signed_xml,signing_time,generator_version
  ) values(
    v_invoice.id,v_reservation.id,v_egs.id,p_certificate_id,p_workflow,v_reservation.icv,
    v_reservation.previous_invoice_hash,v_reservation.business_xml_sha256,p_invoice_hash,
    p_signed_properties_digest,p_signature_value,p_qr_code,p_signed_xml,p_signing_time,
    trim(p_generator_version)
  ) returning * into v_final;

  perform set_config('farsha.zatca_chain_write','on',true);
  update public.zatca_egs_units
  set last_committed_icv=v_reservation.icv,last_invoice_hash=p_invoice_hash,updated_at=now()
  where id=v_egs.id;
  perform set_config('farsha.zatca_chain_write','off',true);
  perform set_config('farsha.zatca_reservation_write','on',true);
  update public.zatca_issuance_reservations
  set status='completed',completed_at=now()
  where id=v_reservation.id;
  perform set_config('farsha.zatca_reservation_write','off',true);

  insert into public.zatca_security_audit_events(
    institution_id,egs_id,invoice_id,certificate_id,event_type,event_data,actor_user_id,request_id
  ) values(
    v_egs.institution_id,v_egs.id,v_invoice.id,p_certificate_id,'issuance_finalized',
    jsonb_build_object('icv',v_reservation.icv,'invoice_hash',p_invoice_hash,
      'workflow',p_workflow,'generator_version',trim(p_generator_version)),
    auth.uid(),left(p_request_id,200)
  );

  return query select v_final.invoice_id,v_final.egs_id,v_final.icv,v_final.invoice_hash,false;
end
$$;

revoke all on function public.reserve_zatca_issuance(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.record_zatca_issuance_failure(uuid,text,text) from public,anon,authenticated;
revoke all on function public.finalize_zatca_issuance(
  uuid,uuid,public.zatca_security_workflow,text,text,text,text,text,timestamptz,text,text
) from public,anon,authenticated;
grant execute on function public.reserve_zatca_issuance(uuid,uuid,text,text) to service_role;
grant execute on function public.record_zatca_issuance_failure(uuid,text,text) to service_role;
grant execute on function public.finalize_zatca_issuance(
  uuid,uuid,public.zatca_security_workflow,text,text,text,text,text,timestamptz,text,text
) to service_role;

alter table public.zatca_egs_units enable row level security;
alter table public.zatca_egs_branch_assignments enable row level security;
alter table public.zatca_egs_certificates enable row level security;
alter table public.zatca_issuance_reservations enable row level security;
alter table public.zatca_invoice_security_states enable row level security;
alter table public.zatca_security_audit_events enable row level security;

revoke all on table public.zatca_egs_units,public.zatca_egs_branch_assignments,
  public.zatca_egs_certificates,public.zatca_issuance_reservations,
  public.zatca_invoice_security_states,public.zatca_security_audit_events
from public,anon,authenticated;
grant all on table public.zatca_egs_units,public.zatca_egs_branch_assignments,
  public.zatca_egs_certificates,public.zatca_issuance_reservations,
  public.zatca_invoice_security_states,public.zatca_security_audit_events
to service_role;
grant usage,select on sequence public.zatca_security_audit_events_id_seq to service_role;

grant select on table public.zatca_egs_units,public.zatca_egs_branch_assignments,
  public.zatca_egs_certificates,public.zatca_invoice_security_states,
  public.zatca_security_audit_events to authenticated;

create policy zatca_egs_units_owner_read on public.zatca_egs_units
for select to authenticated using(
  public.has_institution_role(institution_id,array['owner']::public.institution_role[])
);
create policy zatca_egs_branch_assignments_owner_read on public.zatca_egs_branch_assignments
for select to authenticated using(exists(
  select 1 from public.zatca_egs_units e
  where e.id=zatca_egs_branch_assignments.egs_id and
    public.has_institution_role(e.institution_id,array['owner']::public.institution_role[])
));
create policy zatca_egs_certificates_owner_read on public.zatca_egs_certificates
for select to authenticated using(exists(
  select 1 from public.zatca_egs_units e
  where e.id=zatca_egs_certificates.egs_id and
    public.has_institution_role(e.institution_id,array['owner']::public.institution_role[])
));
create policy zatca_invoice_security_state_read on public.zatca_invoice_security_states
for select to authenticated using(exists(
  select 1 from public.invoices i
  where i.id=zatca_invoice_security_states.invoice_id and (
    (i.seller_id=(select auth.uid()) and public.can_access_branch(i.branch_id)) or
    (public.can_access_branch(i.branch_id) and public.has_institution_role(
      i.institution_id,array['owner','accountant']::public.institution_role[]
    ))
  )
));
create policy zatca_security_audit_owner_read on public.zatca_security_audit_events
for select to authenticated using(
  public.has_institution_role(institution_id,array['owner']::public.institution_role[])
);
