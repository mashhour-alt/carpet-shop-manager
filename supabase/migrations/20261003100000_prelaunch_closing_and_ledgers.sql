-- Release-candidate ledger correctness and non-destructive month-end snapshots.
-- No historical invoice, sale, or stock record is updated by this migration.

create unique index if not exists addon_movements_sale_source_once
  on public.addon_movements(addon_type_id,sale_id,movement_type)
  where sale_id is not null and movement_type in ('sale','sale_void');

create table if not exists public.monthly_closing_snapshots (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  month_start date not null,
  snapshot jsonb not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(institution_id,month_start)
);
alter table public.monthly_closing_snapshots enable row level security;
revoke all on public.monthly_closing_snapshots from anon, authenticated;
grant select on public.monthly_closing_snapshots to authenticated;
drop policy if exists monthly_closing_snapshots_read on public.monthly_closing_snapshots;
create policy monthly_closing_snapshots_read on public.monthly_closing_snapshots for select to authenticated
using (public.has_institution_role(institution_id,array['owner','accountant']::public.institution_role[]));

create or replace function public.account_summaries(
  p_institution_id uuid,p_party text,p_from timestamptz,p_to timestamptz
) returns table(party_id uuid,party_name text,metric_count bigint,gross numeric,paid_or_deducted numeric,balance numeric)
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if p_party='seller' then
    return query
    select m.user_id,p.full_name,
      count(s.id) filter(where s.status='completed' and s.created_at>=p_from and s.created_at<p_to),
      coalesce(sum(s.seller_commission) filter(where s.status='completed' and s.created_at>=p_from and s.created_at<p_to),0),
      coalesce((select sum(l.amount) from public.seller_ledger l where l.institution_id=p_institution_id and l.seller_id=m.user_id and l.created_at>=p_from and l.created_at<p_to),0),
      coalesce((select sum(s2.seller_commission) from public.sales s2 where s2.institution_id=p_institution_id and s2.seller_id=m.user_id and s2.status='completed' and s2.created_at<p_to),0)
      - coalesce((select sum(l2.amount) from public.seller_ledger l2 where l2.institution_id=p_institution_id and l2.seller_id=m.user_id and l2.created_at<p_to),0)
    from public.institution_memberships m join public.profiles p on p.id=m.user_id
    left join public.sales s on s.institution_id=m.institution_id and s.seller_id=m.user_id
    where m.institution_id=p_institution_id and m.role='seller' and m.status='active' group by m.user_id,p.full_name;
  elsif p_party='driver' then
    return query
    select c.driver_id,p.full_name,
      count(t.id) filter(where t.created_at>=p_from and t.created_at<p_to),
      coalesce(sum(t.amount) filter(where t.created_at>=p_from and t.created_at<p_to),0),
      coalesce((select -sum(e.balance_effect) from public.driver_account_entries e where e.institution_id=p_institution_id and e.driver_id=c.driver_id and e.balance_effect<0 and e.created_at>=p_from and e.created_at<p_to),0),
      coalesce((select sum(t2.amount) from public.driver_trips t2 join public.sales s2 on s2.id=t2.sale_id and s2.status='completed' where t2.institution_id=p_institution_id and t2.driver_id=c.driver_id and t2.created_at<p_to),0)
      + coalesce((select sum(e2.balance_effect) from public.driver_account_entries e2 where e2.institution_id=p_institution_id and e2.driver_id=c.driver_id and e2.created_at<p_to),0)
    from public.institution_driver_connections c join public.profiles p on p.id=c.driver_id
    left join public.driver_trips t on t.institution_id=c.institution_id and t.driver_id=c.driver_id
    where c.institution_id=p_institution_id and c.status='active' group by c.driver_id,p.full_name;
  elsif p_party='supplier' then
    return query
    select s.id,s.name,
      count(distinct d.id) filter(where d.delivered_at>=p_from and d.delivered_at<p_to),
      coalesce((select sum(i.length*4*i.unit_cost) from public.supplier_deliveries d1 join public.supplier_delivery_items i on i.delivery_id=d1.id where d1.institution_id=p_institution_id and d1.supplier_id=s.id and d1.delivered_at>=p_from and d1.delivered_at<p_to),0),
      coalesce((select -sum(e.balance_effect) from public.supplier_account_entries e where e.institution_id=p_institution_id and e.supplier_id=s.id and e.balance_effect<0 and e.created_at>=p_from and e.created_at<p_to),0),
      coalesce((select sum(i2.length*4*i2.unit_cost) from public.supplier_deliveries d2 join public.supplier_delivery_items i2 on i2.delivery_id=d2.id where d2.institution_id=p_institution_id and d2.supplier_id=s.id and d2.delivered_at<p_to),0)
      + coalesce((select sum(e2.balance_effect) from public.supplier_account_entries e2 where e2.institution_id=p_institution_id and e2.supplier_id=s.id and e2.created_at<p_to),0)
    from public.suppliers s left join public.supplier_deliveries d on d.supplier_id=s.id
    where s.institution_id=p_institution_id group by s.id,s.name;
  else raise exception 'Invalid party'; end if;
end $$;
revoke all on function public.account_summaries(uuid,text,timestamptz,timestamptz) from public,anon;
grant execute on function public.account_summaries(uuid,text,timestamptz,timestamptz) to authenticated;

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
    'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',party_id,'name',party_name,'gross',gross,'paid',paid_or_deducted,'balance',balance)) from public.account_summaries(p_institution_id,'supplier',v_from,v_to)),'[]'::jsonb),
    'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',party_id,'name',party_name,'gross',gross,'paid',paid_or_deducted,'balance',balance)) from public.account_summaries(p_institution_id,'driver',v_from,v_to)),'[]'::jsonb),
    'sellers',coalesce((select jsonb_agg(jsonb_build_object('id',party_id,'name',party_name,'gross',gross,'deducted',paid_or_deducted,'balance',balance)) from public.account_summaries(p_institution_id,'seller',v_from,v_to)),'[]'::jsonb),
    'branches',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'sales',coalesce(sum(s.tax_exclusive_amount),0),'profit',coalesce(sum(s.seller_profit),0))) from public.branches b left join public.sales s on s.branch_id=b.id and s.status='completed' and s.created_at>=v_from and s.created_at<v_to where b.institution_id=p_institution_id group by b.id,b.name),'[]'::jsonb)
  ) into result;
  return result;
end $$;
revoke all on function public.monthly_owner_report(uuid,date) from public,anon;
grant execute on function public.monthly_owner_report(uuid,date) to authenticated;

create or replace function public.close_month(p_institution_id uuid,p_month_start date)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_snapshot jsonb;
begin
  if not public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  v_snapshot:=public.monthly_owner_report(p_institution_id,p_month_start);
  insert into public.monthly_closing_snapshots(institution_id,month_start,snapshot,created_by)
  values(p_institution_id,p_month_start,v_snapshot,auth.uid())
  on conflict(institution_id,month_start) do update set snapshot=monthly_closing_snapshots.snapshot
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.close_month(uuid,date) from public,anon;
grant execute on function public.close_month(uuid,date) to authenticated;
