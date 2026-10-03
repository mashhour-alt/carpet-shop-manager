-- Keep privileged row assembly off the exposed schema. Public API stays invoker-only.
create schema if not exists private;
revoke all on schema private from public,anon;
grant usage on schema private to authenticated;
alter function public.account_movements(uuid,text,uuid) set schema private;
create function public.account_movements(p_institution_id uuid,p_party text,p_party_id uuid)
returns table(movement_id uuid,event_time timestamptz,event_type text,reference text,description text,amount numeric,created_by_name text,branch_id uuid)
language sql stable security invoker set search_path=public as $$
 select * from private.account_movements(p_institution_id,p_party,p_party_id)
$$;
revoke all on function public.account_movements(uuid,text,uuid) from public,anon;
grant execute on function public.account_movements(uuid,text,uuid) to authenticated;
alter function public.active_driver_account(uuid,uuid) set schema private;
create function public.active_driver_account(p_institution_id uuid,p_driver_id uuid)
returns boolean language sql stable security invoker set search_path=public as $$
 select private.active_driver_account(p_institution_id,p_driver_id)
$$;
revoke all on function public.active_driver_account(uuid,uuid) from public,anon;
grant execute on function public.active_driver_account(uuid,uuid) to authenticated;

-- Branch-specific supplier callers use the same history and deterministic ordering.
create or replace function public.supplier_account_statement_branch(p_institution_id uuid,p_supplier_id uuid,p_from timestamptz,p_to timestamptz,p_branch_id uuid default null)
returns table(event_time timestamptz,event_type text,reference text,description text,amount numeric,created_by_name text,running_balance numeric)
language sql stable security invoker set search_path=public as $$
 with ordered as(select m.*,sum(m.amount) over(order by m.event_time,m.event_type,m.movement_id rows unbounded preceding) balance
 from public.account_movements(p_institution_id,'supplier',p_supplier_id) m where p_branch_id is null or m.branch_id=p_branch_id)
 select o.event_time,o.event_type,coalesce(nullif(o.reference,''),o.movement_id::text),o.description,o.amount,o.created_by_name,o.balance
 from ordered o where o.event_time>=p_from and o.event_time<p_to order by o.event_time desc,o.event_type desc,o.movement_id desc
$$;

-- Full-institution snapshots must not expose branches an accountant cannot read.
drop policy monthly_closing_snapshots_read on public.monthly_closing_snapshots;
create policy monthly_closing_snapshots_read on public.monthly_closing_snapshots for select to authenticated using(
 public.has_institution_role(institution_id,array['owner']::public.institution_role[]) or
 (public.has_institution_role(institution_id,array['accountant']::public.institution_role[]) and not exists(
 select 1 from public.branches b where b.institution_id=monthly_closing_snapshots.institution_id and not public.account_branch_visible(b.institution_id,b.id))));

create or replace function public.monthly_owner_report(p_institution_id uuid,p_month_start date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_from timestamptz:=p_month_start::timestamptz; v_to timestamptz:=(p_month_start+interval '1 month')::timestamptz; result jsonb;
begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  if date_trunc('month',p_month_start)::date<>p_month_start then raise exception 'month_start must be first day of month'; end if;
  select jsonb_build_object(
    'month_start',p_month_start,
    'sales',coalesce((select jsonb_build_object('count',count(*),'operational_sales',sum(coalesce(tax_exclusive_amount,total)),'vat',sum(coalesce(vat_amount,0)),'payable',sum(coalesce(payable_amount,total)),'profit',sum(seller_profit)) from public.sales where institution_id=p_institution_id and public.account_branch_visible(institution_id,branch_id) and status='completed' and created_at>=v_from and created_at<v_to),'{}'::jsonb),
    'payments',coalesce((select jsonb_object_agg(method,amount) from (select method,sum(amount) amount from public.sale_payments where institution_id=p_institution_id and exists(select 1 from public.sales s where s.id=sale_payments.sale_id and public.account_branch_visible(s.institution_id,s.branch_id)) and paid_at>=v_from and paid_at<v_to group by method) q),'{}'::jsonb),
    'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',party_id,'name',party_name,'gross',gross,'paid',paid_or_deducted,'balance',balance)) from (select a.party_id,a.party_name,a.gross,a.paid_or_deducted,(public.account_ledger(p_institution_id,'supplier',a.party_id,v_from,v_to)->>'closing_balance')::numeric balance from public.account_summaries(p_institution_id,'supplier',v_from,v_to) a) summary),'[]'::jsonb),
    'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',party_id,'name',party_name,'gross',gross,'paid',paid_or_deducted,'balance',balance)) from (select a.party_id,a.party_name,a.gross,a.paid_or_deducted,(public.account_ledger(p_institution_id,'driver',a.party_id,v_from,v_to)->>'closing_balance')::numeric balance from public.account_summaries(p_institution_id,'driver',v_from,v_to) a) summary),'[]'::jsonb),
    'sellers',coalesce((select jsonb_agg(jsonb_build_object('id',party_id,'name',party_name,'gross',gross,'deducted',paid_or_deducted,'balance',balance)) from (select a.party_id,a.party_name,a.gross,a.paid_or_deducted,(public.account_ledger(p_institution_id,'seller',a.party_id,v_from,v_to)->>'closing_balance')::numeric balance from public.account_summaries(p_institution_id,'seller',v_from,v_to) a) summary),'[]'::jsonb),
    'branches',coalesce((select jsonb_agg(to_jsonb(q)) from (select b.id,b.name,coalesce(sum(s.tax_exclusive_amount),0) sales,coalesce(sum(s.seller_profit),0) profit from public.branches b left join public.sales s on s.branch_id=b.id and s.status='completed' and s.created_at>=v_from and s.created_at<v_to where b.institution_id=p_institution_id and public.account_branch_visible(b.institution_id,b.id) group by b.id,b.name) q),'[]'::jsonb)
  ) into result;
  return result;
end $$;
revoke all on function public.monthly_owner_report(uuid,date) from public,anon;
grant execute on function public.monthly_owner_report(uuid,date) to authenticated;


