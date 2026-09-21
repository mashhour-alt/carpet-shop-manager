-- Farsha account statements, supplier categories, grouped stock support and material custody.
alter table public.suppliers
  add column if not exists categories text[] not null default array['flooring']::text[];

alter table public.seller_ledger
  add column if not exists source_type text not null default '',
  add column if not exists source_id uuid,
  add column if not exists payment_method text not null default '',
  add column if not exists reference text not null default '';

alter table public.addon_types
  add column if not exists behavior text not null default 'customer_addon'
    check (behavior in ('customer_addon','internal_consumable')),
  add column if not exists calculation_basis text not null default 'quantity'
    check (calculation_basis in ('quantity','sale_area')),
  add column if not exists track_stock boolean not null default false,
  add column if not exists stock_quantity numeric(14,3) not null default 0 check (stock_quantity >= 0),
  add column if not exists low_stock_at numeric(14,3) not null default 0 check (low_stock_at >= 0),
  add column if not exists customer_visible boolean not null default true,
  add column if not exists charge_to_seller boolean not null default false;

create table if not exists public.supplier_account_entries (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  entry_type text not null check (entry_type in ('payment','return','adjustment','settlement')),
  balance_effect numeric(14,2) not null check (balance_effect <> 0),
  payment_method text not null default '',
  reference text not null default '',
  note text not null default '',
  source_type text not null default '',
  source_id uuid,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.driver_account_entries (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  driver_id uuid not null references public.driver_profiles(user_id) on delete cascade,
  entry_type text not null check (entry_type in ('payment','adjustment','settlement')),
  balance_effect numeric(14,2) not null check (balance_effect <> 0),
  payment_method text not null default '',
  reference text not null default '',
  note text not null default '',
  source_type text not null default '',
  source_id uuid,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.addon_movements (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  addon_type_id uuid not null references public.addon_types(id) on delete cascade,
  seller_id uuid references public.profiles(id),
  sale_id uuid references public.sales(id),
  movement_type text not null check (movement_type in ('opening','purchase','sale','issue_to_seller','return_from_seller','adjustment','sale_void')),
  quantity_delta numeric(14,3) not null check (quantity_delta <> 0),
  unit_cost_snapshot numeric(12,2) not null default 0 check (unit_cost_snapshot >= 0),
  note text not null default '',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists supplier_account_entries_party_idx on public.supplier_account_entries(institution_id,supplier_id,created_at);
create index if not exists driver_account_entries_party_idx on public.driver_account_entries(institution_id,driver_id,created_at);
create index if not exists addon_movements_item_idx on public.addon_movements(institution_id,addon_type_id,created_at);

alter table public.supplier_account_entries enable row level security;
alter table public.driver_account_entries enable row level security;
alter table public.addon_movements enable row level security;

drop policy if exists supplier_account_entries_read on public.supplier_account_entries;
create policy supplier_account_entries_read on public.supplier_account_entries for select to authenticated
using (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));

drop policy if exists driver_account_entries_read on public.driver_account_entries;
create policy driver_account_entries_read on public.driver_account_entries for select to authenticated
using (driver_id=(select auth.uid()) or public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));

drop policy if exists addon_movements_read on public.addon_movements;
create policy addon_movements_read on public.addon_movements for select to authenticated
using (seller_id=(select auth.uid()) or public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));

grant select on public.supplier_account_entries, public.driver_account_entries, public.addon_movements to authenticated;

create or replace function public.update_supplier_categories(p_institution_id uuid,p_supplier_id uuid,p_categories text[])
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  update public.suppliers set categories=case when coalesce(array_length(p_categories,1),0)=0 then array['flooring']::text[] else p_categories end
  where id=p_supplier_id and institution_id=p_institution_id;
  if not found then raise exception 'Supplier was not found'; end if;
end; $$;
revoke all on function public.update_supplier_categories(uuid,uuid,text[]) from public,anon;
grant execute on function public.update_supplier_categories(uuid,uuid,text[]) to authenticated;

create or replace function public.record_supplier_account_entry(
  p_institution_id uuid,p_supplier_id uuid,p_entry_type text,p_amount numeric,
  p_payment_method text default '',p_reference text default '',p_note text default ''
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_effect numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if p_amount<=0 then raise exception 'Amount must be positive'; end if;
  if p_entry_type not in ('payment','return','adjustment','settlement') then raise exception 'Invalid entry type'; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and institution_id=p_institution_id) then raise exception 'Supplier was not found'; end if;
  v_effect:=case when p_entry_type in ('payment','return','settlement') then -p_amount else p_amount end;
  insert into public.supplier_account_entries(institution_id,supplier_id,entry_type,balance_effect,payment_method,reference,note,created_by)
  values(p_institution_id,p_supplier_id,p_entry_type,v_effect,coalesce(trim(p_payment_method),''),coalesce(trim(p_reference),''),coalesce(trim(p_note),''),auth.uid())
  returning id into v_id;
  if p_entry_type in ('payment','settlement') then
    update public.suppliers set paid_total=paid_total+p_amount where id=p_supplier_id;
  end if;
  return v_id;
end; $$;
revoke all on function public.record_supplier_account_entry(uuid,uuid,text,numeric,text,text,text) from public,anon;
grant execute on function public.record_supplier_account_entry(uuid,uuid,text,numeric,text,text,text) to authenticated;

create or replace function public.record_supplier_payment(p_institution_id uuid,p_supplier_id uuid,p_amount numeric)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.record_supplier_account_entry(p_institution_id,p_supplier_id,'payment',p_amount,'','','');
end; $$;
revoke all on function public.record_supplier_payment(uuid,uuid,numeric) from public,anon;
grant execute on function public.record_supplier_payment(uuid,uuid,numeric) to authenticated;

create or replace function public.record_driver_account_entry(
  p_institution_id uuid,p_driver_id uuid,p_entry_type text,p_amount numeric,
  p_payment_method text default 'cash',p_reference text default '',p_note text default ''
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_effect numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if p_amount<=0 then raise exception 'Amount must be positive'; end if;
  if p_entry_type not in ('payment','adjustment','settlement') then raise exception 'Invalid entry type'; end if;
  if p_payment_method not in ('cash','bank_transfer','') then raise exception 'Invalid driver payment method'; end if;
  if not exists(select 1 from public.institution_driver_connections where institution_id=p_institution_id and driver_id=p_driver_id and status='active') then raise exception 'Driver is not connected'; end if;
  v_effect:=case when p_entry_type in ('payment','settlement') then -p_amount else p_amount end;
  insert into public.driver_account_entries(institution_id,driver_id,entry_type,balance_effect,payment_method,reference,note,created_by)
  values(p_institution_id,p_driver_id,p_entry_type,v_effect,p_payment_method,coalesce(trim(p_reference),''),coalesce(trim(p_note),''),auth.uid())
  returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.record_driver_account_entry(uuid,uuid,text,numeric,text,text,text) from public,anon;
grant execute on function public.record_driver_account_entry(uuid,uuid,text,numeric,text,text,text) to authenticated;

create or replace function public.pay_driver_trip(p_trip_id uuid,p_method public.driver_payment_method)
returns void language plpgsql security definer set search_path=public as $$
declare t public.driver_trips%rowtype;
begin
  select * into t from public.driver_trips where id=p_trip_id for update;
  if not found then raise exception 'Trip was not found'; end if;
  if not public.has_institution_role(t.institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if t.payment_status='paid' then return; end if;
  update public.driver_trips set payment_status='paid',payment_method=p_method,paid_at=now() where id=p_trip_id;
  insert into public.driver_account_entries(institution_id,driver_id,entry_type,balance_effect,payment_method,source_type,source_id,note,created_by)
  values(t.institution_id,t.driver_id,'payment',-t.amount,p_method::text,'trip',t.id,'سداد مشوار',auth.uid());
end; $$;
revoke all on function public.pay_driver_trip(uuid,public.driver_payment_method) from public,anon;
grant execute on function public.pay_driver_trip(uuid,public.driver_payment_method) to authenticated;

create or replace function public.save_addon_type_v2(
  p_institution_id uuid,p_name text,p_unit text,p_sale_price numeric,p_cost_price numeric,p_supplier_id uuid,
  p_behavior text,p_calculation_basis text,p_track_stock boolean,p_opening_stock numeric,p_low_stock_at numeric,
  p_customer_visible boolean,p_charge_to_seller boolean
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_old_stock numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if trim(coalesce(p_name,''))='' or p_sale_price<0 or p_cost_price<0 or p_opening_stock<0 or p_low_stock_at<0 then raise exception 'Invalid add-on values'; end if;
  if p_behavior not in ('customer_addon','internal_consumable') or p_calculation_basis not in ('quantity','sale_area') then raise exception 'Invalid add-on configuration'; end if;
  select stock_quantity into v_old_stock from public.addon_types where institution_id=p_institution_id and name=trim(p_name) for update;
  insert into public.addon_types(institution_id,name,unit,default_sale_price,default_cost_price,supplier_id,is_active,created_by,behavior,calculation_basis,track_stock,stock_quantity,low_stock_at,customer_visible,charge_to_seller)
  values(p_institution_id,trim(p_name),trim(p_unit),p_sale_price,p_cost_price,p_supplier_id,true,auth.uid(),p_behavior,p_calculation_basis,p_track_stock,p_opening_stock,p_low_stock_at,p_customer_visible,p_charge_to_seller)
  on conflict(institution_id,name) do update set unit=excluded.unit,default_sale_price=excluded.default_sale_price,default_cost_price=excluded.default_cost_price,supplier_id=excluded.supplier_id,is_active=true,behavior=excluded.behavior,calculation_basis=excluded.calculation_basis,track_stock=excluded.track_stock,low_stock_at=excluded.low_stock_at,customer_visible=excluded.customer_visible,charge_to_seller=excluded.charge_to_seller
  returning id into v_id;
  if v_old_stock is null and p_track_stock and p_opening_stock>0 then
    insert into public.addon_movements(institution_id,addon_type_id,movement_type,quantity_delta,unit_cost_snapshot,note,created_by)
    values(p_institution_id,v_id,'opening',p_opening_stock,p_cost_price,'رصيد افتتاحي',auth.uid());
  end if;
  return v_id;
end; $$;
revoke all on function public.save_addon_type_v2(uuid,text,text,numeric,numeric,uuid,text,text,boolean,numeric,numeric,boolean,boolean) from public,anon;
grant execute on function public.save_addon_type_v2(uuid,text,text,numeric,numeric,uuid,text,text,boolean,numeric,numeric,boolean,boolean) to authenticated;

create or replace function public.receive_addon_stock(p_institution_id uuid,p_addon_type_id uuid,p_quantity numeric,p_unit_cost numeric,p_note text default '')
returns uuid language plpgsql security definer set search_path=public as $$
declare a public.addon_types%rowtype; v_id uuid;
begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if p_quantity<=0 or p_unit_cost<0 then raise exception 'Invalid quantity or cost'; end if;
  select * into a from public.addon_types where id=p_addon_type_id and institution_id=p_institution_id for update;
  if not found or not a.track_stock then raise exception 'Tracked material was not found'; end if;
  update public.addon_types set stock_quantity=stock_quantity+p_quantity,default_cost_price=p_unit_cost where id=a.id;
  insert into public.addon_movements(institution_id,addon_type_id,movement_type,quantity_delta,unit_cost_snapshot,note,created_by)
  values(p_institution_id,a.id,'purchase',p_quantity,p_unit_cost,coalesce(trim(p_note),''),auth.uid()) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.receive_addon_stock(uuid,uuid,numeric,numeric,text) from public,anon;
grant execute on function public.receive_addon_stock(uuid,uuid,numeric,numeric,text) to authenticated;

create or replace function public.issue_internal_addon(
  p_institution_id uuid,p_addon_type_id uuid,p_seller_id uuid,p_quantity numeric,p_sale_id uuid default null,p_note text default ''
) returns uuid language plpgsql security definer set search_path=public as $$
declare a public.addon_types%rowtype; v_id uuid; v_amount numeric;
begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if p_quantity<=0 then raise exception 'Quantity must be positive'; end if;
  if not exists(select 1 from public.institution_memberships where institution_id=p_institution_id and user_id=p_seller_id and role='seller' and status='active') then raise exception 'Seller was not found'; end if;
  select * into a from public.addon_types where id=p_addon_type_id and institution_id=p_institution_id for update;
  if not found or a.behavior<>'internal_consumable' or not a.track_stock then raise exception 'Internal tracked material was not found'; end if;
  if a.stock_quantity<p_quantity then raise exception 'Insufficient material stock'; end if;
  update public.addon_types set stock_quantity=stock_quantity-p_quantity where id=a.id;
  insert into public.addon_movements(institution_id,addon_type_id,seller_id,sale_id,movement_type,quantity_delta,unit_cost_snapshot,note,created_by)
  values(p_institution_id,a.id,p_seller_id,p_sale_id,'issue_to_seller',-p_quantity,a.default_cost_price,coalesce(trim(p_note),''),auth.uid()) returning id into v_id;
  if a.charge_to_seller then
    v_amount:=round(p_quantity*a.default_cost_price,2);
    if v_amount>0 then
      insert into public.seller_ledger(institution_id,seller_id,kind,amount,note,created_by,source_type,source_id)
      values(p_institution_id,p_seller_id,'expense',v_amount,a.name||' × '||p_quantity::text,auth.uid(),'addon_issue',v_id);
    end if;
  end if;
  return v_id;
end; $$;
revoke all on function public.issue_internal_addon(uuid,uuid,uuid,numeric,uuid,text) from public,anon;
grant execute on function public.issue_internal_addon(uuid,uuid,uuid,numeric,uuid,text) to authenticated;

create or replace function public.seller_account_statement(p_institution_id uuid,p_seller_id uuid,p_from timestamptz,p_to timestamptz)
returns table(event_time timestamptz,event_type text,reference text,description text,amount numeric,created_by_name text,running_balance numeric)
language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid()<>p_seller_id and not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  return query
  with movements as (
    select s.created_at t,'sale_commission'::text typ,s.id::text ref,'عمولة بيع'::text descr,s.seller_commission amt,'النظام'::text actor
    from public.sales s where s.institution_id=p_institution_id and s.seller_id=p_seller_id and s.status='completed' and s.created_at>=p_from and s.created_at<p_to
    union all
    select l.created_at,'seller_'||l.kind::text,coalesce(nullif(l.reference,''),l.id::text),coalesce(nullif(l.note,''),l.kind::text),-l.amount,coalesce(p.full_name,'مستخدم')
    from public.seller_ledger l left join public.profiles p on p.id=l.created_by
    where l.institution_id=p_institution_id and l.seller_id=p_seller_id and l.created_at>=p_from and l.created_at<p_to
  ),
  ordered as (
    select m.*,sum(m.amt) over(order by m.t,m.ref rows between unbounded preceding and current row) bal from movements m
  )
  select t,typ,ref,descr,amt,actor,bal from ordered order by t desc,ref desc;
end; $$;
revoke all on function public.seller_account_statement(uuid,uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.seller_account_statement(uuid,uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.supplier_account_statement(p_institution_id uuid,p_supplier_id uuid,p_from timestamptz,p_to timestamptz)
returns table(event_time timestamptz,event_type text,reference text,description text,amount numeric,created_by_name text,running_balance numeric)
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  return query
  with movements as (
    select d.delivered_at t,'delivery'::text typ,coalesce(nullif(d.reference,''),d.id::text) ref,
      string_agg(i.name_snapshot||' / '||i.color_snapshot||' • '||trim(to_char(i.length,'FM999999990.###'))||' م','، ' order by i.created_at) descr,
      sum(i.length*4*i.unit_cost) amt,coalesce(p.full_name,'مستخدم') actor
    from public.supplier_deliveries d join public.supplier_delivery_items i on i.delivery_id=d.id left join public.profiles p on p.id=d.created_by
    where d.institution_id=p_institution_id and d.supplier_id=p_supplier_id and d.delivered_at>=p_from and d.delivered_at<p_to
    group by d.id,d.delivered_at,d.reference,p.full_name
    union all
    select e.created_at,'supplier_'||e.entry_type,e.id::text,coalesce(nullif(e.note,''),e.entry_type),e.balance_effect,coalesce(p.full_name,'مستخدم')
    from public.supplier_account_entries e left join public.profiles p on p.id=e.created_by
    where e.institution_id=p_institution_id and e.supplier_id=p_supplier_id and e.created_at>=p_from and e.created_at<p_to
  ),
  ordered as(select m.*,sum(m.amt) over(order by m.t,m.ref rows between unbounded preceding and current row) bal from movements m)
  select t,typ,ref,descr,amt,actor,bal from ordered order by t desc,ref desc;
end; $$;
revoke all on function public.supplier_account_statement(uuid,uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.supplier_account_statement(uuid,uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.driver_account_statement(p_institution_id uuid,p_driver_id uuid,p_from timestamptz,p_to timestamptz)
returns table(event_time timestamptz,event_type text,reference text,description text,amount numeric,created_by_name text,running_balance numeric)
language plpgsql stable security definer set search_path=public as $$
begin
  if auth.uid()<>p_driver_id and not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  return query
  with movements as (
    select t.created_at,'trip'::text,t.id::text,coalesce(nullif(s.customer_name,''),'مشوار') descr,t.amount,'النظام'::text actor
    from public.driver_trips t join public.sales s on s.id=t.sale_id
    where t.institution_id=p_institution_id and t.driver_id=p_driver_id and t.created_at>=p_from and t.created_at<p_to
    union all
    select e.created_at,'driver_'||e.entry_type,e.id::text,coalesce(nullif(e.note,''),e.entry_type),e.balance_effect,coalesce(p.full_name,'مستخدم')
    from public.driver_account_entries e left join public.profiles p on p.id=e.created_by
    where e.institution_id=p_institution_id and e.driver_id=p_driver_id and e.created_at>=p_from and e.created_at<p_to
  ),
  ordered as(select m.*,sum(m.amt) over(order by m.t,m.ref rows between unbounded preceding and current row) bal from movements m)
  select t,event_type,reference,description,amount,created_by_name,running_balance from ordered;
end; $$;
revoke all on function public.driver_account_statement(uuid,uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.driver_account_statement(uuid,uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.account_summaries(p_institution_id uuid,p_party text,p_from timestamptz,p_to timestamptz)
returns table(party_id uuid,party_name text,metric_count bigint,gross numeric,paid_or_deducted numeric,balance numeric)
language plpgsql stable security definer set search_path=public as $$
begin
  if p_party='seller' then
    if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
    return query select m.user_id,p.full_name,
      count(s.id),
      coalesce(sum(s.seller_commission) filter(where s.status='completed' and s.created_at>=p_from and s.created_at<p_to),0),
      coalesce((select sum(l.amount) from public.seller_ledger l where l.institution_id=p_institution_id and l.seller_id=m.user_id and l.created_at>=p_from and l.created_at<p_to),0),
      coalesce(sum(s.seller_commission) filter(where s.status='completed' and s.created_at>=p_from and s.created_at<p_to),0)-coalesce((select sum(l.amount) from public.seller_ledger l where l.institution_id=p_institution_id and l.seller_id=m.user_id and l.created_at>=p_from and l.created_at<p_to),0)
    from public.institution_memberships m join public.profiles p on p.id=m.user_id
    left join public.sales s on s.seller_id=m.user_id and s.institution_id=m.institution_id
    where m.institution_id=p_institution_id and m.role='seller' and m.status='active'
    group by m.user_id,p.full_name;
  elsif p_party='driver' then
    if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
    return query select c.driver_id,p.full_name,
      count(t.id) filter(where t.created_at>=p_from and t.created_at<p_to),
      coalesce(sum(t.amount) filter(where t.created_at>=p_from and t.created_at<p_to),0),
      coalesce((select -sum(e.balance_effect) from public.driver_account_entries e where e.institution_id=p_institution_id and e.driver_id=c.driver_id and e.balance_effect<0 and e.created_at>=p_from and e.created_at<p_to),0),
      coalesce(sum(t.amount) filter(where t.created_at>=p_from and t.created_at<p_to),0)+coalesce((select sum(e.balance_effect) from public.driver_account_entries e where e.institution_id=p_institution_id and e.driver_id=c.driver_id and e.created_at>=p_from and e.created_at<p_to),0)
    from public.institution_driver_connections c join public.profiles p on p.id=c.driver_id
    left join public.driver_trips t on t.driver_id=c.driver_id and t.institution_id=c.institution_id
    where c.institution_id=p_institution_id and c.status='active'
    group by c.driver_id,p.full_name;
  elsif p_party='supplier' then
    if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
    return query select s.id,s.name,
      count(distinct d.id) filter(where d.delivered_at>=p_from and d.delivered_at<p_to),
      coalesce((select sum(i.length*4*i.unit_cost) from public.supplier_deliveries d2 join public.supplier_delivery_items i on i.delivery_id=d2.id where d2.institution_id=p_institution_id and d2.supplier_id=s.id and d2.delivered_at>=p_from and d2.delivered_at<p_to),0),
      coalesce((select -sum(e.balance_effect) from public.supplier_account_entries e where e.institution_id=p_institution_id and e.supplier_id=s.id and e.balance_effect<0 and e.created_at>=p_from and e.created_at<p_to),0),
      coalesce((select sum(i.length*4*i.unit_cost) from public.supplier_deliveries d2 join public.supplier_delivery_items i on i.delivery_id=d2.id where d2.institution_id=p_institution_id and d2.supplier_id=s.id and d2.delivered_at>=p_from and d2.delivered_at<p_to),0)+coalesce((select sum(e.balance_effect) from public.supplier_account_entries e where e.institution_id=p_institution_id and e.supplier_id=s.id and e.created_at>=p_from and e.created_at<p_to),0)
    from public.suppliers s left join public.supplier_deliveries d on d.supplier_id=s.id
    where s.institution_id=p_institution_id group by s.id,s.name;
  else raise exception 'Invalid party';
  end if;
end; $$;
revoke all on function public.account_summaries(uuid,text,timestamptz,timestamptz) from public,anon;
grant execute on function public.account_summaries(uuid,text,timestamptz,timestamptz) to authenticated;
