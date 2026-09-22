-- Multi-Branch + Partners extension. Additive/backfill migration; no production reset.
create type public.branch_status as enum ('active','inactive','closed');
create type public.partner_relationship_type as enum ('owner','financial_partner','administrative_partner','authorized_manager');
create type public.partnership_scope as enum ('institution','branch');
create type public.partner_ledger_kind as enum ('entitlement','distribution','withdrawal','settlement','adjustment');
create type public.stock_transfer_status as enum ('draft','approved','cancelled');

create table public.branches(
 id uuid primary key default gen_random_uuid(),
 institution_id uuid not null references public.institutions(id) on delete restrict,
 name text not null, code text not null, city text not null default '', address text not null default '',
 phone text not null default '', opened_on date, status public.branch_status not null default 'active',
 notes text not null default '', is_default boolean not null default false,
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), unique(institution_id,code)
);
create unique index branches_one_default_idx on public.branches(institution_id) where is_default;

insert into public.branches(institution_id,name,code,city,address,phone,opened_on,status,notes,is_default,created_by,created_at)
select i.id,'الفرع الرئيسي','MAIN','',i.address,i.phone,i.created_at::date,'active','تم إنشاؤه تلقائيًا عند تفعيل نظام الفروع',true,i.created_by,i.created_at
from public.institutions i where not exists(select 1 from public.branches b where b.institution_id=i.id);

create table public.institution_branch_access(
 institution_id uuid not null references public.institutions(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 can_view boolean not null default true, can_sell boolean not null default false,
 can_manage_inventory boolean not null default false, can_view_financials boolean not null default false,
 can_manage_financials boolean not null default false, can_manage_reports boolean not null default false,
 granted_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 primary key(branch_id,user_id)
);
insert into public.institution_branch_access(institution_id,branch_id,user_id,can_view,can_sell,can_manage_inventory,can_view_financials,can_manage_financials,can_manage_reports,granted_by)
select m.institution_id,b.id,m.user_id,true,m.role in('owner','seller'),m.role in('owner','accountant'),m.role in('owner','accountant'),m.role in('owner','accountant'),m.role in('owner','accountant'),i.created_by
from public.institution_memberships m join public.branches b on b.institution_id=m.institution_id and b.is_default
join public.institutions i on i.id=m.institution_id where m.status='active'
on conflict do nothing;

create or replace function public.can_access_branch(p_branch_id uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.branches b join public.institution_memberships m on m.institution_id=b.institution_id
  where b.id=p_branch_id and m.user_id=(select auth.uid()) and m.status='active' and m.role='owner')
 or exists(select 1 from public.institution_branch_access a where a.branch_id=p_branch_id and a.user_id=(select auth.uid()) and a.can_view)
$$;
revoke all on function public.can_access_branch(uuid) from public,anon; grant execute on function public.can_access_branch(uuid) to authenticated;

create or replace function public.can_manage_branch(p_branch_id uuid,p_capability text) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.branches b join public.institution_memberships m on m.institution_id=b.institution_id
  where b.id=p_branch_id and m.user_id=(select auth.uid()) and m.status='active' and m.role='owner')
 or exists(select 1 from public.institution_branch_access a where a.branch_id=p_branch_id and a.user_id=(select auth.uid()) and
  case p_capability when 'sell' then a.can_sell when 'inventory' then a.can_manage_inventory when 'financials' then a.can_manage_financials
  when 'reports' then a.can_manage_reports else a.can_view end)
$$;
revoke all on function public.can_manage_branch(uuid,text) from public,anon; grant execute on function public.can_manage_branch(uuid,text) to authenticated;

alter table public.inventory_items add column branch_id uuid references public.branches(id);
alter table public.sales add column branch_id uuid references public.branches(id);
alter table public.quotations add column branch_id uuid references public.branches(id);
alter table public.invoices add column branch_id uuid references public.branches(id);
alter table public.supplier_deliveries add column branch_id uuid references public.branches(id);
alter table public.seller_ledger add column branch_id uuid references public.branches(id);
alter table public.driver_trips add column branch_id uuid references public.branches(id);
alter table public.inventory_movements add column branch_id uuid references public.branches(id);
alter table public.addon_movements add column branch_id uuid references public.branches(id);
alter table public.supplier_account_entries add column branch_id uuid references public.branches(id);
alter table public.driver_account_entries add column branch_id uuid references public.branches(id);

update public.inventory_items x set branch_id=b.id from public.branches b where b.institution_id=x.institution_id and b.is_default and x.branch_id is null;
update public.sales x set branch_id=b.id from public.branches b where b.institution_id=x.institution_id and b.is_default and x.branch_id is null;
update public.quotations x set branch_id=b.id from public.branches b where b.institution_id=x.institution_id and b.is_default and x.branch_id is null;
update public.invoices x set branch_id=coalesce((select s.branch_id from public.sales s where s.id=x.sale_id),b.id) from public.branches b where b.institution_id=x.institution_id and b.is_default and x.branch_id is null;
update public.supplier_deliveries x set branch_id=b.id from public.branches b where b.institution_id=x.institution_id and b.is_default and x.branch_id is null;
update public.seller_ledger x set branch_id=coalesce((select s.branch_id from public.sales s where x.source_type='sale' and s.id=x.source_id),b.id) from public.branches b where b.institution_id=x.institution_id and b.is_default and x.branch_id is null;
update public.driver_trips x set branch_id=coalesce((select s.branch_id from public.sales s where s.id=x.sale_id),b.id) from public.branches b where b.institution_id=x.institution_id and b.is_default and x.branch_id is null;
update public.inventory_movements x set branch_id=coalesce((select ii.branch_id from public.inventory_items ii where ii.id=x.inventory_id),b.id) from public.branches b where b.institution_id=x.institution_id and b.is_default and x.branch_id is null;
update public.addon_movements x set branch_id=coalesce((select s.branch_id from public.sales s where s.id=x.sale_id),b.id) from public.branches b where b.institution_id=x.institution_id and b.is_default and x.branch_id is null;
update public.supplier_account_entries x set branch_id=coalesce(d.branch_id,null) from public.supplier_deliveries d where x.source_type='delivery' and x.source_id=d.id and x.branch_id is null;
update public.driver_account_entries x set branch_id=t.branch_id from public.driver_trips t where x.source_type='trip' and x.source_id=t.id and x.branch_id is null;

alter table public.inventory_items alter column branch_id set not null;
alter table public.sales alter column branch_id set not null;
alter table public.quotations alter column branch_id set not null;
alter table public.invoices alter column branch_id set not null;
alter table public.supplier_deliveries alter column branch_id set not null;
alter table public.driver_trips alter column branch_id set not null;
alter table public.inventory_movements alter column branch_id set not null;

alter table public.inventory_items drop constraint if exists inventory_items_institution_id_name_color_key;
create unique index inventory_branch_name_color_uidx on public.inventory_items(branch_id,name,color);
create index sales_branch_created_idx on public.sales(branch_id,created_at desc);
create index quotations_branch_created_idx on public.quotations(branch_id,created_at desc);
create index invoices_branch_issued_idx on public.invoices(branch_id,issued_at desc);
create index deliveries_branch_date_idx on public.supplier_deliveries(branch_id,delivered_at desc);
create index trips_branch_date_idx on public.driver_trips(branch_id,trip_date desc);
create index seller_ledger_branch_date_idx on public.seller_ledger(branch_id,entry_date desc);

create table public.addon_branch_stock(
 branch_id uuid not null references public.branches(id) on delete restrict,
 addon_type_id uuid not null references public.addon_types(id) on delete restrict,
 institution_id uuid not null references public.institutions(id) on delete cascade,
 quantity numeric(14,3) not null default 0 check(quantity>=0), low_stock_at numeric(14,3) not null default 0,
 updated_at timestamptz not null default now(), primary key(branch_id,addon_type_id)
);
insert into public.addon_branch_stock(branch_id,addon_type_id,institution_id,quantity,low_stock_at)
select b.id,a.id,a.institution_id,a.stock_quantity,a.low_stock_at from public.addon_types a join public.branches b on b.institution_id=a.institution_id and b.is_default
where a.track_stock on conflict do nothing;

create table public.stock_transfers(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete restrict,
 from_branch_id uuid not null references public.branches(id) on delete restrict, to_branch_id uuid not null references public.branches(id) on delete restrict,
 source_inventory_id uuid not null references public.inventory_items(id) on delete restrict, target_inventory_id uuid references public.inventory_items(id) on delete restrict,
 quantity numeric(12,3) not null check(quantity>0), status public.stock_transfer_status not null default 'approved',
 note text not null default '', created_by uuid not null references public.profiles(id), approved_by uuid references public.profiles(id),
 created_at timestamptz not null default now(), approved_at timestamptz, check(from_branch_id<>to_branch_id)
);

create table public.expenses(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete restrict,
 branch_id uuid references public.branches(id) on delete restrict, expense_date date not null default current_date,
 category text not null, amount numeric(14,2) not null check(amount>0), payment_method text not null default '',
 reference text not null default '', notes text not null default '', created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);

create table public.partners(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete restrict,
 user_id uuid references public.profiles(id) on delete set null, display_name text not null, phone text not null default '',
 relationship_type public.partner_relationship_type not null, status public.membership_status not null default 'active',
 started_on date not null default current_date, ended_on date, notes text not null default '',
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create unique index partners_institution_user_active_uidx on public.partners(institution_id,user_id) where user_id is not null and status='active';

create table public.partner_scopes(
 id uuid primary key default gen_random_uuid(), partner_id uuid not null references public.partners(id) on delete restrict,
 institution_id uuid not null references public.institutions(id) on delete restrict, scope public.partnership_scope not null,
 branch_id uuid references public.branches(id) on delete restrict, effective_from date not null, effective_to date,
 notes text not null default '', created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 check((scope='institution' and branch_id is null) or (scope='branch' and branch_id is not null)),
 check(effective_to is null or effective_to>=effective_from)
);
create table public.partner_entitlement_history(
 id uuid primary key default gen_random_uuid(), partner_scope_id uuid not null references public.partner_scopes(id) on delete restrict,
 percentage numeric(7,4) not null check(percentage between 0 and 100), effective_from date not null, effective_to date,
 reason text not null default '', changed_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 check(effective_to is null or effective_to>=effective_from)
);
create table public.partner_ledger(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete restrict,
 partner_id uuid not null references public.partners(id) on delete restrict, branch_id uuid references public.branches(id) on delete restrict,
 kind public.partner_ledger_kind not null, amount numeric(14,2) not null check(amount<>0), reference text not null default '',
 notes text not null default '', source_type text not null default '', source_id uuid,
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);

create table public.audit_log(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id) on delete restrict,
 branch_id uuid references public.branches(id) on delete restrict, actor_id uuid not null references public.profiles(id),
 action text not null, entity_type text not null, entity_id uuid, previous_value jsonb, new_value jsonb,
 created_at timestamptz not null default now()
);

alter table public.branches enable row level security; alter table public.institution_branch_access enable row level security;
alter table public.addon_branch_stock enable row level security; alter table public.stock_transfers enable row level security;
alter table public.expenses enable row level security; alter table public.partners enable row level security;
alter table public.partner_scopes enable row level security; alter table public.partner_entitlement_history enable row level security;
alter table public.partner_ledger enable row level security; alter table public.audit_log enable row level security;

grant select on public.branches,public.institution_branch_access,public.addon_branch_stock,public.stock_transfers,public.expenses,public.partners,public.partner_scopes,public.partner_entitlement_history,public.partner_ledger,public.audit_log to authenticated;

create policy branches_read on public.branches for select to authenticated using(public.can_access_branch(id));
create policy branch_access_self_or_owner on public.institution_branch_access for select to authenticated using(user_id=(select auth.uid()) or public.has_institution_role(institution_id,array['owner']::public.institution_role[]));
create policy addon_branch_stock_read on public.addon_branch_stock for select to authenticated using(public.can_access_branch(branch_id));
create policy stock_transfers_read on public.stock_transfers for select to authenticated using(public.can_access_branch(from_branch_id) or public.can_access_branch(to_branch_id));
create policy expenses_read on public.expenses for select to authenticated using((branch_id is null and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])) or (branch_id is not null and public.can_access_branch(branch_id) and (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]) or exists(select 1 from public.institution_branch_access a where a.branch_id=expenses.branch_id and a.user_id=(select auth.uid()) and a.can_view_financials))));
create policy partners_read on public.partners for select to authenticated using(public.has_institution_role(institution_id,array['owner']::public.institution_role[]) or user_id=(select auth.uid()));
create policy partner_scopes_read on public.partner_scopes for select to authenticated using(public.has_institution_role(institution_id,array['owner']::public.institution_role[]) or exists(select 1 from public.partners p where p.id=partner_id and p.user_id=(select auth.uid())));
create policy partner_entitlements_read on public.partner_entitlement_history for select to authenticated using(exists(select 1 from public.partner_scopes ps join public.partners p on p.id=ps.partner_id where ps.id=partner_scope_id and (public.has_institution_role(ps.institution_id,array['owner']::public.institution_role[]) or p.user_id=(select auth.uid()))));
create policy partner_ledger_read on public.partner_ledger for select to authenticated using(public.has_institution_role(institution_id,array['owner']::public.institution_role[]) or exists(select 1 from public.partners p where p.id=partner_id and p.user_id=(select auth.uid())));
create policy audit_read_owner on public.audit_log for select to authenticated using(public.has_institution_role(institution_id,array['owner']::public.institution_role[]));

drop policy if exists inventory_read on public.inventory_items;
create policy inventory_read on public.inventory_items for select to authenticated using(public.can_access_branch(branch_id));
drop policy if exists inventory_manage on public.inventory_items;
create policy inventory_manage on public.inventory_items for all to authenticated using(public.can_manage_branch(branch_id,'inventory')) with check(public.can_manage_branch(branch_id,'inventory'));
drop policy if exists sales_read on public.sales;
create policy sales_read on public.sales for select to authenticated using((seller_id=(select auth.uid()) and public.can_access_branch(branch_id)) or (public.can_access_branch(branch_id) and (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]) or exists(select 1 from public.partners p where p.institution_id=sales.institution_id and p.user_id=(select auth.uid()) and p.status='active'))));
drop policy if exists quotations_read on public.quotations;
create policy quotations_read on public.quotations for select to authenticated using((seller_id=(select auth.uid()) and public.can_access_branch(branch_id)) or (public.can_access_branch(branch_id) and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])));
drop policy if exists invoices_read on public.invoices;
create policy invoices_read on public.invoices for select to authenticated using((seller_id=(select auth.uid()) and public.can_access_branch(branch_id)) or (public.can_access_branch(branch_id) and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])));
drop policy if exists trips_read on public.driver_trips;
create policy trips_read on public.driver_trips for select to authenticated using(driver_id=(select auth.uid()) or (seller_id=(select auth.uid()) and public.can_access_branch(branch_id)) or (public.can_access_branch(branch_id) and public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[])));

create or replace function public.create_branch(p_institution_id uuid,p_name text,p_code text,p_city text,p_address text,p_phone text,p_opened_on date,p_notes text)
returns uuid language plpgsql security definer set search_path=public as $$ declare v uuid; begin
 if not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 insert into public.branches(institution_id,name,code,city,address,phone,opened_on,notes,created_by) values(p_institution_id,trim(p_name),upper(trim(p_code)),trim(p_city),trim(p_address),trim(p_phone),p_opened_on,coalesce(p_notes,''),auth.uid()) returning id into v;
 insert into public.institution_branch_access(institution_id,branch_id,user_id,can_view,can_sell,can_manage_inventory,can_view_financials,can_manage_financials,can_manage_reports,granted_by)
 select p_institution_id,v,m.user_id,true,m.role in('owner','seller'),m.role in('owner','accountant'),m.role in('owner','accountant'),m.role in('owner','accountant'),m.role in('owner','accountant'),auth.uid()
 from public.institution_memberships m where m.institution_id=p_institution_id and m.status='active' and m.role='owner';
 insert into public.audit_log(institution_id,branch_id,actor_id,action,entity_type,entity_id,new_value) values(p_institution_id,v,auth.uid(),'branch_created','branch',v,jsonb_build_object('name',p_name,'code',p_code));
 return v; end $$;
revoke all on function public.create_branch(uuid,text,text,text,text,text,date,text) from public,anon; grant execute on function public.create_branch(uuid,text,text,text,text,text,date,text) to authenticated;

create or replace function public.set_branch_status(p_branch_id uuid,p_status public.branch_status,p_notes text default '')
returns void language plpgsql security definer set search_path=public as $$ declare b public.branches%rowtype; begin
 select * into b from public.branches where id=p_branch_id for update; if not found then raise exception 'Branch not found'; end if;
 if not public.has_institution_role(b.institution_id,array['owner']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 if b.is_default and p_status<>'active' and not exists(select 1 from public.branches x where x.institution_id=b.institution_id and x.id<>b.id and x.status='active') then raise exception 'Cannot close the only active branch'; end if;
 update public.branches set status=p_status,notes=case when trim(coalesce(p_notes,''))='' then notes else p_notes end,updated_at=now() where id=p_branch_id;
 insert into public.audit_log(institution_id,branch_id,actor_id,action,entity_type,entity_id,previous_value,new_value) values(b.institution_id,b.id,auth.uid(),'branch_status_changed','branch',b.id,jsonb_build_object('status',b.status),jsonb_build_object('status',p_status));
 end $$;
revoke all on function public.set_branch_status(uuid,public.branch_status,text) from public,anon; grant execute on function public.set_branch_status(uuid,public.branch_status,text) to authenticated;

create or replace function public.set_branch_access(p_branch_id uuid,p_user_id uuid,p_can_view boolean,p_can_sell boolean,p_inventory boolean,p_view_financials boolean,p_manage_financials boolean,p_reports boolean)
returns void language plpgsql security definer set search_path=public as $$ declare b public.branches%rowtype; old jsonb; begin
 select * into b from public.branches where id=p_branch_id; if not public.has_institution_role(b.institution_id,array['owner']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 select to_jsonb(a) into old from public.institution_branch_access a where a.branch_id=p_branch_id and a.user_id=p_user_id;
 insert into public.institution_branch_access(institution_id,branch_id,user_id,can_view,can_sell,can_manage_inventory,can_view_financials,can_manage_financials,can_manage_reports,granted_by)
 values(b.institution_id,p_branch_id,p_user_id,p_can_view,p_can_sell,p_inventory,p_view_financials,p_manage_financials,p_reports,auth.uid())
 on conflict(branch_id,user_id) do update set can_view=excluded.can_view,can_sell=excluded.can_sell,can_manage_inventory=excluded.can_manage_inventory,can_view_financials=excluded.can_view_financials,can_manage_financials=excluded.can_manage_financials,can_manage_reports=excluded.can_manage_reports,granted_by=auth.uid();
 insert into public.audit_log(institution_id,branch_id,actor_id,action,entity_type,entity_id,previous_value,new_value) values(b.institution_id,b.id,auth.uid(),'branch_permissions_changed','branch_access',p_user_id,old,jsonb_build_object('can_view',p_can_view,'can_sell',p_can_sell,'inventory',p_inventory,'view_financials',p_view_financials,'manage_financials',p_manage_financials,'reports',p_reports));
 end $$;
revoke all on function public.set_branch_access(uuid,uuid,boolean,boolean,boolean,boolean,boolean,boolean) from public,anon; grant execute on function public.set_branch_access(uuid,uuid,boolean,boolean,boolean,boolean,boolean,boolean) to authenticated;

create or replace function public.transfer_inventory(p_from_inventory_id uuid,p_to_branch_id uuid,p_quantity numeric,p_note text default '')
returns uuid language plpgsql security definer set search_path=public as $$ declare src public.inventory_items%rowtype; target uuid; t uuid; begin
 select * into src from public.inventory_items where id=p_from_inventory_id for update; if not found then raise exception 'Inventory not found'; end if;
 if not public.can_manage_branch(src.branch_id,'inventory') or not public.can_manage_branch(p_to_branch_id,'inventory') then raise exception 'Insufficient branch permission'; end if;
 if p_quantity<=0 or src.remaining_length<p_quantity then raise exception 'Insufficient stock'; end if;
 if src.branch_id=p_to_branch_id then raise exception 'Branches must differ'; end if;
 select id into target from public.inventory_items where branch_id=p_to_branch_id and name=src.name and color=src.color for update;
 if target is null then insert into public.inventory_items(institution_id,branch_id,name,color,remaining_length,width,wholesale_price,image_url,low_stock_at) values(src.institution_id,p_to_branch_id,src.name,src.color,0,src.width,src.wholesale_price,src.image_url,src.low_stock_at) returning id into target;
  insert into public.inventory_costs(inventory_id,institution_id,supplier_id,supplier_price) select target,institution_id,supplier_id,supplier_price from public.inventory_costs where inventory_id=src.id;
 end if;
 insert into public.stock_transfers(institution_id,from_branch_id,to_branch_id,source_inventory_id,target_inventory_id,quantity,status,note,created_by,approved_by,approved_at) values(src.institution_id,src.branch_id,p_to_branch_id,src.id,target,p_quantity,'approved',coalesce(p_note,''),auth.uid(),auth.uid(),now()) returning id into t;
 update public.inventory_items set remaining_length=remaining_length-p_quantity where id=src.id; update public.inventory_items set remaining_length=remaining_length+p_quantity where id=target;
 insert into public.inventory_movements(institution_id,branch_id,inventory_id,movement_type,length_delta,source_type,source_id,note,created_by) values(src.institution_id,src.branch_id,src.id,'transfer_out',-p_quantity,'stock_transfer',t,p_note,auth.uid()),(src.institution_id,p_to_branch_id,target,'transfer_in',p_quantity,'stock_transfer',t,p_note,auth.uid());
 insert into public.audit_log(institution_id,actor_id,action,entity_type,entity_id,new_value) values(src.institution_id,auth.uid(),'stock_transfer','stock_transfer',t,jsonb_build_object('from_branch',src.branch_id,'to_branch',p_to_branch_id,'quantity',p_quantity,'item',src.name,'color',src.color));
 return t; end $$;
revoke all on function public.transfer_inventory(uuid,uuid,numeric,text) from public,anon; grant execute on function public.transfer_inventory(uuid,uuid,numeric,text) to authenticated;

create or replace function public.add_partner(p_institution_id uuid,p_user_id uuid,p_name text,p_phone text,p_relationship public.partner_relationship_type,p_scope public.partnership_scope,p_branch_id uuid,p_percentage numeric,p_effective_from date,p_notes text)
returns uuid language plpgsql security definer set search_path=public as $$ declare pid uuid; sid uuid; begin
 if not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 if p_scope='branch' and (p_branch_id is null or not exists(select 1 from public.branches where id=p_branch_id and institution_id=p_institution_id)) then raise exception 'Invalid branch'; end if;
 insert into public.partners(institution_id,user_id,display_name,phone,relationship_type,started_on,notes,created_by) values(p_institution_id,p_user_id,trim(p_name),coalesce(p_phone,''),p_relationship,p_effective_from,coalesce(p_notes,''),auth.uid()) returning id into pid;
 insert into public.partner_scopes(partner_id,institution_id,scope,branch_id,effective_from,notes,created_by) values(pid,p_institution_id,p_scope,case when p_scope='branch' then p_branch_id else null end,p_effective_from,p_notes,auth.uid()) returning id into sid;
 insert into public.partner_entitlement_history(partner_scope_id,percentage,effective_from,reason,changed_by) values(sid,p_percentage,p_effective_from,'Initial entitlement',auth.uid());
 insert into public.audit_log(institution_id,branch_id,actor_id,action,entity_type,entity_id,new_value) values(p_institution_id,p_branch_id,auth.uid(),'partner_added','partner',pid,jsonb_build_object('name',p_name,'relationship',p_relationship,'scope',p_scope,'percentage',p_percentage,'effective_from',p_effective_from));
 return pid; end $$;
revoke all on function public.add_partner(uuid,uuid,text,text,public.partner_relationship_type,public.partnership_scope,uuid,numeric,date,text) from public,anon; grant execute on function public.add_partner(uuid,uuid,text,text,public.partner_relationship_type,public.partnership_scope,uuid,numeric,date,text) to authenticated;

create or replace function public.change_partner_percentage(p_partner_scope_id uuid,p_percentage numeric,p_effective_from date,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$ declare ps public.partner_scopes%rowtype; prev public.partner_entitlement_history%rowtype; rid uuid; total numeric; begin
 select * into ps from public.partner_scopes where id=p_partner_scope_id; if not public.has_institution_role(ps.institution_id,array['owner']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 if p_percentage<0 or p_percentage>100 then raise exception 'Invalid percentage'; end if;
 select * into prev from public.partner_entitlement_history where partner_scope_id=ps.id and effective_to is null order by effective_from desc limit 1 for update;
 if found and p_effective_from<=prev.effective_from then raise exception 'Effective date must be after current period start'; end if;
 if found then update public.partner_entitlement_history set effective_to=p_effective_from-1 where id=prev.id; end if;
 select coalesce(sum(h.percentage),0) into total from public.partner_scopes x join public.partner_entitlement_history h on h.partner_scope_id=x.id join public.partners p on p.id=x.partner_id where x.institution_id=ps.institution_id and x.id<>ps.id and x.scope=ps.scope and x.branch_id is not distinct from ps.branch_id and h.effective_from<=p_effective_from and (h.effective_to is null or h.effective_to>=p_effective_from) and p.status='active';
 if total+p_percentage>100 then raise exception 'Active entitlement percentages exceed 100%%'; end if;
 insert into public.partner_entitlement_history(partner_scope_id,percentage,effective_from,reason,changed_by) values(ps.id,p_percentage,p_effective_from,p_reason,auth.uid()) returning id into rid;
 insert into public.audit_log(institution_id,branch_id,actor_id,action,entity_type,entity_id,previous_value,new_value) values(ps.institution_id,ps.branch_id,auth.uid(),'partner_percentage_changed','partner_scope',ps.id,case when found then jsonb_build_object('percentage',prev.percentage,'effective_from',prev.effective_from) else null end,jsonb_build_object('percentage',p_percentage,'effective_from',p_effective_from,'reason',p_reason));
 return rid; end $$;
revoke all on function public.change_partner_percentage(uuid,numeric,date,text) from public,anon; grant execute on function public.change_partner_percentage(uuid,numeric,date,text) to authenticated;

create or replace function public.record_partner_ledger(p_partner_id uuid,p_branch_id uuid,p_kind public.partner_ledger_kind,p_amount numeric,p_reference text,p_notes text)
returns uuid language plpgsql security definer set search_path=public as $$ declare p public.partners%rowtype; rid uuid; begin
 select * into p from public.partners where id=p_partner_id; if not public.has_institution_role(p.institution_id,array['owner']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 if p_kind='entitlement' and p_amount<0 then raise exception 'Entitlement must be positive'; end if;
 insert into public.partner_ledger(institution_id,partner_id,branch_id,kind,amount,reference,notes,created_by) values(p.institution_id,p.id,p_branch_id,p_kind,case when p_kind='entitlement' then abs(p_amount) else -abs(p_amount) end,coalesce(p_reference,''),coalesce(p_notes,''),auth.uid()) returning id into rid;
 insert into public.audit_log(institution_id,branch_id,actor_id,action,entity_type,entity_id,new_value) values(p.institution_id,p_branch_id,auth.uid(),'partner_ledger_entry','partner_ledger',rid,jsonb_build_object('kind',p_kind,'amount',p_amount,'reference',p_reference));
 return rid; end $$;
revoke all on function public.record_partner_ledger(uuid,uuid,public.partner_ledger_kind,numeric,text,text) from public,anon; grant execute on function public.record_partner_ledger(uuid,uuid,public.partner_ledger_kind,numeric,text,text) to authenticated;

create or replace function public.end_partnership(p_partner_id uuid,p_end_date date,p_notes text)
returns void language plpgsql security definer set search_path=public as $$ declare p public.partners%rowtype; begin
 select * into p from public.partners where id=p_partner_id for update; if not public.has_institution_role(p.institution_id,array['owner']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
 update public.partners set status='suspended',ended_on=p_end_date,notes=concat_ws(E'\n',notes,p_notes) where id=p.id;
 update public.partner_scopes set effective_to=p_end_date where partner_id=p.id and (effective_to is null or effective_to>p_end_date);
 update public.partner_entitlement_history h set effective_to=p_end_date from public.partner_scopes ps where ps.id=h.partner_scope_id and ps.partner_id=p.id and (h.effective_to is null or h.effective_to>p_end_date);
 insert into public.audit_log(institution_id,actor_id,action,entity_type,entity_id,new_value) values(p.institution_id,auth.uid(),'partnership_ended','partner',p.id,jsonb_build_object('ended_on',p_end_date,'notes',p_notes)); end $$;
revoke all on function public.end_partnership(uuid,date,text) from public,anon; grant execute on function public.end_partnership(uuid,date,text) to authenticated;

create index branch_access_user_idx on public.institution_branch_access(user_id,branch_id);
create index partner_scopes_branch_idx on public.partner_scopes(branch_id,effective_from,effective_to);
create index partner_ledger_partner_date_idx on public.partner_ledger(partner_id,created_at desc);
create index expenses_branch_date_idx on public.expenses(branch_id,expense_date desc);
create index audit_institution_date_idx on public.audit_log(institution_id,created_at desc);
