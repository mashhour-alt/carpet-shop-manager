-- Pre-launch SaaS foundation.  This is additive: subscriptions belong to an
-- institution, never to an individual staff member or driver.
create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  trial_days integer not null default 14 check (trial_days >= 0 and trial_days <= 365),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.subscription_plans(code,name,trial_days)
values ('default','الخطة الأساسية',14)
on conflict (code) do nothing;

create table if not exists public.institution_subscriptions (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null unique references public.institutions(id) on delete cascade,
  plan_id uuid references public.subscription_plans(id),
  status text not null default 'trial' check (status in ('trial','active','grace_period','expired','cancelled','suspended')),
  provider text not null default 'manual' check (provider in ('google_play','apple','web','manual')),
  provider_subscription_reference text,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  grace_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider, provider_subscription_reference)
);

create index if not exists institution_subscriptions_entitlement_idx
  on public.institution_subscriptions(institution_id,status,expires_at);

alter table public.subscription_plans enable row level security;
alter table public.institution_subscriptions enable row level security;

create policy subscription_plans_read on public.subscription_plans
  for select to authenticated using (is_active);
create policy institution_subscriptions_owner_read on public.institution_subscriptions
  for select to authenticated using (public.has_institution_role(institution_id,array['owner']::public.institution_role[]));

create or replace function public.create_institution_subscription(p_institution_id uuid,p_plan_code text default 'default')
returns uuid language plpgsql security definer set search_path=public as $$
declare plan public.subscription_plans%rowtype; result_id uuid;
begin
  if not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then
    raise exception 'Only the institution owner can create a subscription';
  end if;
  select * into plan from public.subscription_plans where code=coalesce(nullif(trim(p_plan_code),''),'default') and is_active;
  if not found then raise exception 'Subscription plan is unavailable'; end if;
  insert into public.institution_subscriptions(institution_id,plan_id,status,provider,starts_at,expires_at)
  values(p_institution_id,plan.id,'trial','manual',now(),now() + make_interval(days=>plan.trial_days))
  on conflict(institution_id) do nothing
  returning id into result_id;
  if result_id is null then select id into result_id from public.institution_subscriptions where institution_id=p_institution_id; end if;
  return result_id;
end; $$;

create or replace function public.create_institution_v2(
  p_name text,p_cr text default '',p_tax text default '',p_address text default '',p_phone text default '',p_email text default '',p_plan_code text default 'default'
) returns uuid language plpgsql security definer set search_path=public as $$
declare result_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.profiles where id=auth.uid() and account_kind='institution' and onboarding_mode='owner') then
    raise exception 'Only owner accounts can create institutions';
  end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Institution name is required'; end if;
  insert into public.institutions(name,commercial_registration,tax_number,address,phone,email,created_by)
  values(trim(p_name),trim(coalesce(p_cr,'')),trim(coalesce(p_tax,'')),trim(coalesce(p_address,'')),trim(coalesce(p_phone,'')),trim(coalesce(p_email,'')),auth.uid()) returning id into result_id;
  insert into public.institution_memberships(institution_id,user_id,role) values(result_id,auth.uid(),'owner');
  perform public.create_institution_subscription(result_id,p_plan_code);
  return result_id;
end; $$;

-- Preserve existing clients while giving new onboarding optional legal fields.
create or replace function public.create_institution(p_name text,p_cr text,p_tax text,p_address text,p_phone text,p_email text)
returns uuid language sql security definer set search_path=public as $$
  select public.create_institution_v2(p_name,p_cr,p_tax,p_address,p_phone,p_email,'default')
$$;

create or replace function public.institution_subscription_entitlement(p_institution_id uuid)
returns table(status text,is_entitled boolean,expires_at timestamptz) language sql stable security definer set search_path=public as $$
  select s.status,
    (s.status in ('trial','active','grace_period') and (s.expires_at is null or s.expires_at > now() or (s.grace_ends_at is not null and s.grace_ends_at > now()))) as is_entitled,
    s.expires_at
  from public.institution_subscriptions s
  where s.institution_id=p_institution_id
    and public.is_institution_member(p_institution_id)
$$;

revoke all on table public.subscription_plans,public.institution_subscriptions from public,anon;
grant select on public.subscription_plans,public.institution_subscriptions to authenticated;
grant execute on function public.create_institution_v2(text,text,text,text,text,text,text),public.create_institution_subscription(uuid,text),public.institution_subscription_entitlement(uuid) to authenticated;
