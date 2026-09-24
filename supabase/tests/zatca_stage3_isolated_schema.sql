-- Disposable PostgreSQL schema used only by CI to exercise the Stage 3
-- migration and real concurrent connections without touching Supabase.
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;

create type public.institution_role as enum ('owner','accountant','seller');
create table public.profiles(id uuid primary key);
create table public.institutions(id uuid primary key);
create table public.branches(
  id uuid primary key,
  institution_id uuid not null references public.institutions(id)
);
create table public.invoices(
  id uuid primary key,
  institution_id uuid not null references public.institutions(id),
  branch_id uuid not null references public.branches(id),
  issued_at timestamptz not null,
  invoice_kind text not null check(invoice_kind in('simplified','tax')),
  seller_id uuid not null references public.profiles(id)
);

create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
create function public.has_institution_role(uuid,public.institution_role[])
returns boolean language sql stable as $$ select true $$;
create function public.can_access_branch(uuid)
returns boolean language sql stable as $$ select true $$;
