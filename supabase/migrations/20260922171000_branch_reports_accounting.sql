-- Branch-aware operating RPCs and management functions.
create or replace function public.branch_operating_summary(p_institution_id uuid,p_branch_id uuid,p_from timestamptz,p_to timestamptz)
returns table(sale_count bigint,total_length numeric,total_area numeric,sales_amount numeric,merchandise_cost numeric,driver_cost numeric,gross_profit numeric,payments jsonb,expenses numeric)
language plpgsql stable security definer set search_path=public as $$ begin
 if not public.is_institution_member(p_institution_id) then raise exception 'Insufficient permission'; end if;
 if p_branch_id is not null and not public.can_access_branch(p_branch_id) then raise exception 'Branch access denied'; end if;
 return query with allowed_sales as (
  select s.* from public.sales s where s.institution_id=p_institution_id and s.status='completed' and s.created_at>=p_from and s.created_at<p_to and
   ((p_branch_id is not null and s.branch_id=p_branch_id and public.can_access_branch(s.branch_id)) or (p_branch_id is null and public.can_access_branch(s.branch_id)))
 ), pay as (
  select coalesce(jsonb_object_agg(method,total),'{}'::jsonb) j from (select sp.method,sum(sp.amount) total from public.sale_payments sp join allowed_sales s on s.id=sp.sale_id group by sp.method) x
 ), ex as (
  select coalesce(sum(e.amount),0) total from public.expenses e where e.institution_id=p_institution_id and e.expense_date>=p_from::date and e.expense_date<p_to::date and
  ((p_branch_id is null and (e.branch_id is null or public.can_access_branch(e.branch_id))) or e.branch_id=p_branch_id)
 )
 select count(s.id),coalesce(sum(s.length),0),coalesce(sum(s.area),0),coalesce(sum(s.total),0),
 coalesce(sum(s.area*s.supplier_unit_cost_snapshot + (select coalesce(sum(sa.quantity*sa.cost_unit_price),0) from public.sale_addons sa where sa.sale_id=s.id)),0),
 coalesce(sum(s.driver_fee),0),
 coalesce(sum(s.total-(s.area*s.supplier_unit_cost_snapshot)-(select coalesce(sum(sa.quantity*sa.cost_unit_price),0) from public.sale_addons sa where sa.sale_id=s.id)-s.driver_fee-s.payment_fee),0),
 (select j from pay),(select total from ex) from allowed_sales s;
end $$;
revoke all on function public.branch_operating_summary(uuid,uuid,timestamptz,timestamptz) from public,anon;grant execute on function public.branch_operating_summary(uuid,uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.branch_report(p_institution_id uuid,p_from timestamptz,p_to timestamptz)
returns table(branch_id uuid,branch_name text,sales numeric,cost numeric,profit numeric,expenses numeric,length_sold numeric,area_sold numeric,sale_count bigint)
language plpgsql stable security definer set search_path=public as $$ begin
 if not public.is_institution_member(p_institution_id) then raise exception 'Insufficient permission'; end if;
 return query select b.id,b.name,coalesce(sum(s.total),0),
 coalesce(sum(s.area*s.supplier_unit_cost_snapshot+(select coalesce(sum(sa.quantity*sa.cost_unit_price),0) from public.sale_addons sa where sa.sale_id=s.id)),0),
 coalesce(sum(s.total-s.area*s.supplier_unit_cost_snapshot-(select coalesce(sum(sa.quantity*sa.cost_unit_price),0) from public.sale_addons sa where sa.sale_id=s.id)-s.driver_fee-s.payment_fee),0),
 coalesce((select sum(e.amount) from public.expenses e where e.branch_id=b.id and e.expense_date>=p_from::date and e.expense_date<p_to::date),0),
 coalesce(sum(s.length),0),coalesce(sum(s.area),0),count(s.id)
 from public.branches b left join public.sales s on s.branch_id=b.id and s.status='completed' and s.created_at>=p_from and s.created_at<p_to
 where b.institution_id=p_institution_id and public.can_access_branch(b.id) group by b.id,b.name order by b.name;
end $$;
revoke all on function public.branch_report(uuid,timestamptz,timestamptz) from public,anon;grant execute on function public.branch_report(uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.record_expense(p_institution_id uuid,p_branch_id uuid,p_category text,p_amount numeric,p_method text,p_reference text,p_notes text,p_date date)
returns uuid language plpgsql security definer set search_path=public as $$ declare rid uuid;begin
 if p_branch_id is null then if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission';end if;
 elsif not public.can_manage_branch(p_branch_id,'financials') then raise exception 'Insufficient branch permission';end if;
 insert into public.expenses(institution_id,branch_id,expense_date,category,amount,payment_method,reference,notes,created_by) values(p_institution_id,p_branch_id,coalesce(p_date,current_date),trim(p_category),p_amount,coalesce(p_method,''),coalesce(p_reference,''),coalesce(p_notes,''),auth.uid()) returning id into rid;
 insert into public.audit_log(institution_id,branch_id,actor_id,action,entity_type,entity_id,new_value) values(p_institution_id,p_branch_id,auth.uid(),'expense_recorded','expense',rid,jsonb_build_object('category',p_category,'amount',p_amount));return rid;end$$;
revoke all on function public.record_expense(uuid,uuid,text,numeric,text,text,text,date) from public,anon;grant execute on function public.record_expense(uuid,uuid,text,numeric,text,text,text,date) to authenticated;

create or replace function public.partner_statement(p_institution_id uuid,p_partner_id uuid,p_from timestamptz,p_to timestamptz,p_branch_id uuid default null)
returns table(event_time timestamptz,kind text,branch_name text,reference text,description text,amount numeric,running_balance numeric)
language plpgsql stable security definer set search_path=public as $$begin
 if not(public.has_institution_role(p_institution_id,array['owner']::public.institution_role[]) or exists(select 1 from public.partners p where p.id=p_partner_id and p.institution_id=p_institution_id and p.user_id=auth.uid())) then raise exception 'Insufficient permission';end if;
 return query select x.created_at,x.kind::text,coalesce(b.name,'مستوى المؤسسة'),x.reference,x.notes,x.amount,sum(x.amount) over(order by x.created_at,x.id)
 from public.partner_ledger x left join public.branches b on b.id=x.branch_id where x.institution_id=p_institution_id and x.partner_id=p_partner_id and x.created_at>=p_from and x.created_at<p_to and (p_branch_id is null or x.branch_id=p_branch_id) order by x.created_at desc;end$$;
revoke all on function public.partner_statement(uuid,uuid,timestamptz,timestamptz,uuid) from public,anon;grant execute on function public.partner_statement(uuid,uuid,timestamptz,timestamptz,uuid) to authenticated;

create or replace function public.validate_partner_scope_total(p_partner_scope_id uuid,p_effective_date date)
returns numeric language plpgsql stable security definer set search_path=public as $$declare ps public.partner_scopes%rowtype;total numeric;begin
 select * into ps from public.partner_scopes where id=p_partner_scope_id;if not public.has_institution_role(ps.institution_id,array['owner']::public.institution_role[]) then raise exception 'Insufficient permission';end if;
 select coalesce(sum(h.percentage),0) into total from public.partner_scopes x join public.partner_entitlement_history h on h.partner_scope_id=x.id join public.partners p on p.id=x.partner_id where x.institution_id=ps.institution_id and x.scope=ps.scope and x.branch_id is not distinct from ps.branch_id and h.effective_from<=p_effective_date and (h.effective_to is null or h.effective_to>=p_effective_date) and p.status='active';return total;end$$;
revoke all on function public.validate_partner_scope_total(uuid,date) from public,anon;grant execute on function public.validate_partner_scope_total(uuid,date) to authenticated;
