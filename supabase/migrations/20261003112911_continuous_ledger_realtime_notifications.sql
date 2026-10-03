-- One read model over existing canonical source rows; no copied balances or opening entries.
create or replace function public.account_branch_visible(p_institution_id uuid,p_branch_id uuid)
returns boolean language sql stable security invoker set search_path=public as $$
 select public.has_institution_role(p_institution_id,array['owner']::public.institution_role[])
 or (public.has_institution_role(p_institution_id,array['accountant']::public.institution_role[])
 and (p_branch_id is null or exists(select 1 from public.institution_branch_access a
 where a.institution_id=p_institution_id and a.branch_id=p_branch_id and a.user_id=auth.uid() and a.can_view and a.can_view_financials)))
$$;
revoke all on function public.account_branch_visible(uuid,uuid) from public,anon;
grant execute on function public.account_branch_visible(uuid,uuid) to authenticated;

create or replace function public.account_movements(p_institution_id uuid,p_party text,p_party_id uuid)
returns table(movement_id uuid,event_time timestamptz,event_type text,reference text,description text,amount numeric,created_by_name text,branch_id uuid)
language plpgsql stable security definer set search_path=public as $$
declare manager boolean; personal boolean;
begin
 manager:=public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]);
 personal:=auth.uid()=p_party_id and (
 (p_party='seller' and public.has_institution_role(p_institution_id,array['seller']::public.institution_role[])) or
 (p_party='driver' and exists(select 1 from public.institution_driver_connections c where c.institution_id=p_institution_id and c.driver_id=auth.uid() and c.status='active')));
 if auth.uid() is null or not (manager or personal) then raise exception 'Insufficient permission'; end if;
 if p_party='seller' then
 return query
 select s.id,s.created_at,'sale_commission'::text,s.id::text,'عمولة بيع'::text,s.seller_commission,'النظام'::text,s.branch_id
 from public.sales s where s.institution_id=p_institution_id and s.seller_id=p_party_id and s.status='completed'
 and ((personal and (s.branch_id is null or public.can_access_branch(s.branch_id))) or (manager and public.account_branch_visible(s.institution_id,s.branch_id)))
 union all
 select l.id,l.created_at,'seller_'||l.kind::text,l.reference,coalesce(nullif(l.note,''),l.kind::text),-l.amount,coalesce(p.full_name,'مستخدم'),l.branch_id
 from public.seller_ledger l left join public.profiles p on p.id=l.created_by
 where l.institution_id=p_institution_id and l.seller_id=p_party_id
 and ((personal and (l.branch_id is null or public.can_access_branch(l.branch_id))) or (manager and public.account_branch_visible(l.institution_id,l.branch_id)));
 elsif p_party='driver' then
 return query
 select t.id,t.created_at,'trip'::text,t.sale_id::text,'مشوار'::text,t.amount,'النظام'::text,t.branch_id
 from public.driver_trips t join public.sales s on s.id=t.sale_id and s.institution_id=t.institution_id
 where t.institution_id=p_institution_id and t.driver_id=p_party_id and s.status='completed'
 and (personal or (manager and public.account_branch_visible(t.institution_id,t.branch_id)))
 union all
 select e.id,e.created_at,'driver_'||e.entry_type,e.reference,coalesce(nullif(e.note,''),e.entry_type),e.balance_effect,coalesce(p.full_name,'مستخدم'),e.branch_id
 from public.driver_account_entries e left join public.profiles p on p.id=e.created_by
 where e.institution_id=p_institution_id and e.driver_id=p_party_id
 and (personal or (manager and public.account_branch_visible(e.institution_id,e.branch_id)));
 elsif p_party='supplier' then
 return query
 select d.id,d.delivered_at,'delivery'::text,d.reference,'توريد'::text,sum(i.length*4*i.unit_cost),coalesce(p.full_name,'مستخدم'),d.branch_id
 from public.supplier_deliveries d join public.supplier_delivery_items i on i.delivery_id=d.id left join public.profiles p on p.id=d.created_by
 where d.institution_id=p_institution_id and d.supplier_id=p_party_id and public.account_branch_visible(d.institution_id,d.branch_id)
 group by d.id,d.delivered_at,d.reference,p.full_name,d.branch_id
 union all
 select e.id,e.created_at,'supplier_'||e.entry_type,e.reference,coalesce(nullif(e.note,''),e.entry_type),e.balance_effect,coalesce(p.full_name,'مستخدم'),e.branch_id
 from public.supplier_account_entries e left join public.profiles p on p.id=e.created_by
 where e.institution_id=p_institution_id and e.supplier_id=p_party_id and public.account_branch_visible(e.institution_id,e.branch_id);
 else raise exception 'Invalid party'; end if;
end $$;
revoke all on function public.account_movements(uuid,text,uuid) from public,anon;
grant execute on function public.account_movements(uuid,text,uuid) to authenticated;

create or replace function public.account_ledger(p_institution_id uuid,p_party text,p_party_id uuid,p_from timestamptz,p_to timestamptz)
returns jsonb language sql stable security invoker set search_path=public as $$
 with movements as materialized (select * from public.account_movements(p_institution_id,p_party,p_party_id)),
 ordered as(select m.*,sum(amount) over(order by event_time,event_type,movement_id rows unbounded preceding) running_balance from movements m)
 select jsonb_build_object(
 'current_balance',coalesce((select sum(amount) from movements),0),
 'opening_balance',coalesce((select sum(amount) from movements where event_time<p_from),0),
 'closing_balance',coalesce((select sum(amount) from movements where event_time<p_to),0),
 'gross',coalesce((select sum(amount) from movements where event_time>=p_from and event_time<p_to and amount>0),0),
 'paid',coalesce((select -sum(amount) from movements where event_time>=p_from and event_time<p_to and amount<0),0),
 'movements',coalesce((select jsonb_agg(to_jsonb(o) order by event_time desc,event_type desc,movement_id desc) from ordered o where event_time>=p_from and event_time<p_to),'[]'::jsonb))
$$;
revoke all on function public.account_ledger(uuid,text,uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.account_ledger(uuid,text,uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.seller_account_statement(p_institution_id uuid,p_seller_id uuid,p_from timestamptz,p_to timestamptz)
returns table(event_time timestamptz,event_type text,reference text,description text,amount numeric,created_by_name text,running_balance numeric)
language sql stable security invoker set search_path=public as $$
 with ordered as(select m.*,sum(m.amount) over(order by m.event_time,m.event_type,m.movement_id rows unbounded preceding) balance
 from public.account_movements(p_institution_id,'seller',p_seller_id) m)
 select o.event_time,o.event_type,coalesce(nullif(o.reference,''),o.movement_id::text),o.description,o.amount,o.created_by_name,o.balance
 from ordered o where o.event_time>=p_from and o.event_time<p_to order by o.event_time desc,o.event_type desc,o.movement_id desc
$$;

create or replace function public.driver_account_statement(p_institution_id uuid,p_driver_id uuid,p_from timestamptz,p_to timestamptz)
returns table(event_time timestamptz,event_type text,reference text,description text,amount numeric,created_by_name text,running_balance numeric)
language sql stable security invoker set search_path=public as $$
 with ordered as(select m.*,sum(m.amount) over(order by m.event_time,m.event_type,m.movement_id rows unbounded preceding) balance
 from public.account_movements(p_institution_id,'driver',p_driver_id) m)
 select o.event_time,o.event_type,coalesce(nullif(o.reference,''),o.movement_id::text),o.description,o.amount,o.created_by_name,o.balance
 from ordered o where o.event_time>=p_from and o.event_time<p_to order by o.event_time desc,o.event_type desc,o.movement_id desc
$$;

create or replace function public.supplier_account_statement(p_institution_id uuid,p_supplier_id uuid,p_from timestamptz,p_to timestamptz)
returns table(event_time timestamptz,event_type text,reference text,description text,amount numeric,created_by_name text,running_balance numeric)
language sql stable security invoker set search_path=public as $$
 with ordered as(select m.*,sum(m.amount) over(order by m.event_time,m.event_type,m.movement_id rows unbounded preceding) balance
 from public.account_movements(p_institution_id,'supplier',p_supplier_id) m)
 select o.event_time,o.event_type,coalesce(nullif(o.reference,''),o.movement_id::text),o.description,o.amount,o.created_by_name,o.balance
 from ordered o where o.event_time>=p_from and o.event_time<p_to order by o.event_time desc,o.event_type desc,o.movement_id desc
$$;

create or replace function public.account_summaries(p_institution_id uuid,p_party text,p_from timestamptz,p_to timestamptz)
returns table(party_id uuid,party_name text,metric_count bigint,gross numeric,paid_or_deducted numeric,balance numeric)
language plpgsql stable security invoker set search_path=public as $$
begin
 if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission';end if;
 return query with parties as (
 select m.user_id id,p.full_name name from public.institution_memberships m join public.profiles p on p.id=m.user_id where p_party='seller' and m.institution_id=p_institution_id and m.role='seller'
 union select c.driver_id,p.full_name from public.institution_driver_connections c join public.profiles p on p.id=c.driver_id where p_party='driver' and c.institution_id=p_institution_id
 union select s.id,s.name from public.suppliers s where p_party='supplier' and s.institution_id=p_institution_id)
 select p.id,p.name,count(m.movement_id) filter(where m.event_type in ('sale_commission','trip','delivery') and m.event_time>=p_from and m.event_time<p_to),
 coalesce(sum(m.amount) filter(where m.amount>0 and m.event_time>=p_from and m.event_time<p_to),0),
 coalesce(-sum(m.amount) filter(where m.amount<0 and m.event_time>=p_from and m.event_time<p_to),0),coalesce(sum(m.amount),0)
 from parties p left join lateral public.account_movements(p_institution_id,p_party,p.id) m on true group by p.id,p.name;
end $$;

-- Remove permissive legacy policies: permissive SELECT policies combine with OR.
drop policy if exists ledger_manage on public.seller_ledger;
drop policy if exists ledger_read on public.seller_ledger;
drop policy if exists seller_ledger_read on public.seller_ledger;
create policy seller_ledger_read on public.seller_ledger for select to authenticated using(
 public.account_branch_visible(institution_id,branch_id) or
 (seller_id=auth.uid() and public.has_institution_role(institution_id,array['seller']::public.institution_role[]) and (branch_id is null or public.can_access_branch(branch_id))));
create policy seller_ledger_insert on public.seller_ledger for insert to authenticated with check(
 created_by=auth.uid() and public.account_branch_visible(institution_id,branch_id)
 and (branch_id is null or public.can_manage_branch(branch_id,'financials'))
 and exists(select 1 from public.institution_memberships m where m.institution_id=seller_ledger.institution_id and m.user_id=seller_ledger.seller_id and m.role='seller'));
-- Historical financial rows are append-only for API users; corrections are new movements.
revoke update,delete on public.seller_ledger from authenticated;

create or replace function public.active_driver_account(p_institution_id uuid,p_driver_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select auth.uid()=p_driver_id and exists(select 1 from public.institution_driver_connections c where c.institution_id=p_institution_id and c.driver_id=p_driver_id and c.status='active')
$$;
revoke all on function public.active_driver_account(uuid,uuid) from public,anon;
grant execute on function public.active_driver_account(uuid,uuid) to authenticated;
drop policy if exists driver_account_entries_read on public.driver_account_entries;
create policy driver_account_entries_read on public.driver_account_entries for select to authenticated using(public.active_driver_account(institution_id,driver_id) or public.account_branch_visible(institution_id,branch_id));
drop policy if exists trips_read on public.driver_trips;
create policy trips_read on public.driver_trips for select to authenticated using(public.active_driver_account(institution_id,driver_id) or public.account_branch_visible(institution_id,branch_id) or (seller_id=auth.uid() and public.has_institution_role(institution_id,array['seller']::public.institution_role[]) and public.can_access_branch(branch_id)));

-- Durable, recipient-scoped events also invalidate account views. Never a second ledger.
create table public.account_notifications(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.institutions(id),
 branch_id uuid references public.branches(id), recipient_id uuid not null references public.profiles(id),
 event_table text not null,event_id uuid not null,event_kind text not null,title text not null,
 created_at timestamptz not null default now(),read_at timestamptz,
 unique(recipient_id,event_table,event_id,event_kind)
);
alter table public.account_notifications enable row level security;
revoke all on public.account_notifications from public,anon,authenticated;
grant select on public.account_notifications to authenticated;
grant update(read_at) on public.account_notifications to authenticated;
create policy account_notifications_read on public.account_notifications for select to authenticated using(
 recipient_id=auth.uid() and (public.account_branch_visible(institution_id,branch_id)
 or (public.has_institution_role(institution_id,array['seller']::public.institution_role[]) and (branch_id is null or public.can_access_branch(branch_id)))
 or public.active_driver_account(institution_id,recipient_id)));
create policy account_notifications_read_mark on public.account_notifications for update to authenticated using(recipient_id=auth.uid()) with check(recipient_id=auth.uid());
create index account_notifications_recipient_time on public.account_notifications(recipient_id,created_at desc);

create or replace function public.notify_account_event() returns trigger language plpgsql security definer set search_path=public as $$
declare affected uuid; v_event_kind text:='created'; v_title text:='حركة مالية جديدة';
begin
 if tg_table_name='sales' then
   if tg_op='UPDATE' and new.status is not distinct from old.status then return new;end if;
   if new.status='completed' then v_event_kind:='completed';v_title:='تم تسجيل بيعة ناجحة';else v_event_kind:=new.status::text;v_title:='تم تحديث حالة البيع';end if;
   affected:=new.seller_id;
 elsif tg_table_name='seller_ledger' then affected:=new.seller_id;
 elsif tg_table_name in ('driver_account_entries','driver_trips') then affected:=new.driver_id;
 end if;
 insert into public.account_notifications(institution_id,branch_id,recipient_id,event_table,event_id,event_kind,title)
 select new.institution_id,new.branch_id,r.user_id,tg_table_name,new.id,v_event_kind,v_title from (
 select m.user_id from public.institution_memberships m where m.institution_id=new.institution_id and m.status='active' and
 (m.role='owner' or (m.role='accountant' and (new.branch_id is null or exists(select 1 from public.institution_branch_access a where a.institution_id=new.institution_id and a.branch_id=new.branch_id and a.user_id=m.user_id and a.can_view and a.can_view_financials))))
 union select affected where affected is not null
 union select (to_jsonb(new)->>'driver_id')::uuid where tg_table_name='sales' and to_jsonb(new)->>'driver_id' is not null
 ) r on conflict(recipient_id,event_table,event_id,event_kind) do nothing;
 return new;
end $$;
revoke all on function public.notify_account_event() from public,anon,authenticated;
create trigger notify_seller_ledger after insert on public.seller_ledger for each row execute function public.notify_account_event();
create trigger notify_driver_account_entries after insert on public.driver_account_entries for each row execute function public.notify_account_event();
create trigger notify_supplier_account_entries after insert on public.supplier_account_entries for each row execute function public.notify_account_event();
create trigger notify_driver_trips after insert on public.driver_trips for each row execute function public.notify_account_event();
create trigger notify_supplier_deliveries after insert on public.supplier_deliveries for each row execute function public.notify_account_event();
create trigger notify_sales after insert or update of status on public.sales for each row execute function public.notify_account_event();
alter publication supabase_realtime add table public.account_notifications;
create or replace function public.monthly_owner_report(p_institution_id uuid,p_month_start date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_from timestamptz:=p_month_start::timestamptz; v_to timestamptz:=(p_month_start+interval '1 month')::timestamptz; result jsonb;
begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if date_trunc('month',p_month_start)::date<>p_month_start then raise exception 'month_start must be first day of month'; end if;
  select jsonb_build_object(
    'month_start',p_month_start,
    'sales',coalesce((select jsonb_build_object('count',count(*),'operational_sales',sum(coalesce(tax_exclusive_amount,total)),'vat',sum(coalesce(vat_amount,0)),'payable',sum(coalesce(payable_amount,total)),'profit',sum(seller_profit)) from public.sales where institution_id=p_institution_id and status='completed' and created_at>=v_from and created_at<v_to),'{}'::jsonb),
    'payments',coalesce((select jsonb_object_agg(method,amount) from (select method,sum(amount) amount from public.sale_payments where institution_id=p_institution_id and paid_at>=v_from and paid_at<v_to group by method) q),'{}'::jsonb),
    'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',party_id,'name',party_name,'gross',gross,'paid',paid_or_deducted,'balance',balance)) from (select a.party_id,a.party_name,a.gross,a.paid_or_deducted,(public.account_ledger(p_institution_id,'supplier',a.party_id,v_from,v_to)->>'closing_balance')::numeric balance from public.account_summaries(p_institution_id,'supplier',v_from,v_to) a) summary),'[]'::jsonb),
    'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',party_id,'name',party_name,'gross',gross,'paid',paid_or_deducted,'balance',balance)) from (select a.party_id,a.party_name,a.gross,a.paid_or_deducted,(public.account_ledger(p_institution_id,'driver',a.party_id,v_from,v_to)->>'closing_balance')::numeric balance from public.account_summaries(p_institution_id,'driver',v_from,v_to) a) summary),'[]'::jsonb),
    'sellers',coalesce((select jsonb_agg(jsonb_build_object('id',party_id,'name',party_name,'gross',gross,'deducted',paid_or_deducted,'balance',balance)) from (select a.party_id,a.party_name,a.gross,a.paid_or_deducted,(public.account_ledger(p_institution_id,'seller',a.party_id,v_from,v_to)->>'closing_balance')::numeric balance from public.account_summaries(p_institution_id,'seller',v_from,v_to) a) summary),'[]'::jsonb),
    'branches',coalesce((select jsonb_agg(to_jsonb(q)) from (select b.id,b.name,coalesce(sum(s.tax_exclusive_amount),0) sales,coalesce(sum(s.seller_profit),0) profit from public.branches b left join public.sales s on s.branch_id=b.id and s.status='completed' and s.created_at>=v_from and s.created_at<v_to where b.institution_id=p_institution_id and public.account_branch_visible(b.institution_id,b.id) group by b.id,b.name) q),'[]'::jsonb)
  ) into result;
  return result;
end $$;
revoke all on function public.monthly_owner_report(uuid,date) from public,anon;
grant execute on function public.monthly_owner_report(uuid,date) to authenticated;


-- Payment is a single canonical entry, with per-trip locking for concurrent retries.
create or replace function public.pay_driver_trip(p_trip_id uuid,p_method public.driver_payment_method)
returns void language plpgsql security definer set search_path=public as $$
declare t public.driver_trips%rowtype;
begin
 select * into t from public.driver_trips where id=p_trip_id for update;
 if not found then raise exception 'Trip not found';end if;
 if auth.uid() is null or not public.has_institution_role(t.institution_id,array['owner','accountant']::public.institution_role[]) or not public.can_manage_branch(t.branch_id,'financials') then raise exception 'Insufficient branch permission';end if;
 if t.payment_status='paid' or exists(select 1 from public.driver_account_entries e where e.institution_id=t.institution_id and e.source_type='trip_payment' and e.source_id=t.id) then return;end if;
 update public.driver_trips set payment_status='paid',payment_method=p_method,paid_at=now() where id=p_trip_id;
 insert into public.driver_account_entries(institution_id,branch_id,driver_id,entry_type,balance_effect,payment_method,source_type,source_id,note,created_by)
 values(t.institution_id,t.branch_id,t.driver_id,'payment',-abs(t.amount),p_method::text,'trip_payment',t.id,'Trip payment',auth.uid());
end $$;

-- Validate relationships even for legacy definer RPC write paths.
create or replace function public.validate_account_relationship() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if new.branch_id is not null and not exists(select 1 from public.branches b where b.id=new.branch_id and b.institution_id=new.institution_id) then raise exception 'Branch institution mismatch';end if;
 if tg_table_name='seller_ledger' and not exists(select 1 from public.institution_memberships m where m.institution_id=new.institution_id and m.user_id=(to_jsonb(new)->>'seller_id')::uuid and m.role='seller') then raise exception 'Seller institution mismatch';end if;
 if tg_table_name='driver_account_entries' and not exists(select 1 from public.institution_driver_connections c where c.institution_id=new.institution_id and c.driver_id=(to_jsonb(new)->>'driver_id')::uuid and c.status='active') then raise exception 'Driver relationship inactive';end if;
 if tg_table_name='supplier_account_entries' and not exists(select 1 from public.suppliers s where s.institution_id=new.institution_id and s.id=(to_jsonb(new)->>'supplier_id')::uuid) then raise exception 'Supplier institution mismatch';end if;
 return new;
end $$;
revoke all on function public.validate_account_relationship() from public,anon,authenticated;
create trigger validate_seller_ledger before insert on public.seller_ledger for each row execute function public.validate_account_relationship();
create trigger validate_driver_entry before insert on public.driver_account_entries for each row execute function public.validate_account_relationship();
create trigger validate_supplier_entry before insert on public.supplier_account_entries for each row execute function public.validate_account_relationship();
