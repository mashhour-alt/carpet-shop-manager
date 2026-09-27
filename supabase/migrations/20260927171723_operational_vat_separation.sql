-- Keep daily operational reporting VAT-exclusive while preserving the canonical
-- invoice snapshot, payment payable amount, and all issued historical invoices.
-- This migration only replaces functions. It performs no historical data update.

create or replace function public.record_sale_financial_v2(
  p_institution_id uuid,
  p_inventory_id uuid,
  p_seller_id uuid,
  p_driver_id uuid,
  p_customer_name text,
  p_length numeric,
  p_sale_price numeric,
  p_driver_fee numeric,
  p_notes text,
  p_payments jsonb,
  p_addons jsonb default '[]'::jsonb,
  p_discount numeric default 0
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  gross numeric:=0;
  discount numeric:=round(coalesce(p_discount,0),2);
  taxable numeric;
  vat numeric;
  payable numeric;
  paid numeric:=0;
  legacy_payments jsonb;
  rid uuid;
  payment jsonb;
  inst public.institutions%rowtype;
  fee numeric:=0;
  rate numeric;
  carpet_gross numeric;
  carpet_discount numeric;
  merchandise_wholesale numeric;
  commission_rate numeric;
  calculated_seller_profit numeric;
begin
  select round(
    p_length*4*p_sale_price +
    coalesce(sum(round(coalesce((x->>'quantity')::numeric,0)*coalesce((x->>'sale_unit_price')::numeric,0),2)),0),
    2
  ) into gross
  from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) x;

  if discount<0 or discount>gross then raise exception 'Invalid discount'; end if;
  taxable:=round(gross-discount,2);
  vat:=round(taxable*.15,2);
  payable:=taxable+vat;

  select coalesce(sum((x->>'amount')::numeric),0) into paid
  from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) x;
  if round(paid,2)<>payable then
    raise exception 'Payments must equal canonical payable amount including VAT';
  end if;

  legacy_payments:=jsonb_build_array(jsonb_build_object(
    'method','other','amount',gross,'reference','canonical-sale-bootstrap'
  ));
  rid:=public.record_sale_v2(
    p_institution_id,p_inventory_id,p_seller_id,p_driver_id,p_customer_name,
    p_length,p_sale_price,p_driver_fee,p_notes,legacy_payments,p_addons
  );

  delete from public.sale_payments where sale_id=rid;
  select * into inst from public.institutions where id=p_institution_id;
  for payment in select value from jsonb_array_elements(p_payments) loop
    rate:=case payment->>'method'
      when 'visa' then inst.visa_fee_rate
      when 'tabby' then inst.tabby_fee_rate
      when 'tamara' then inst.tamara_fee_rate
      else 0
    end;
    insert into public.sale_payments(
      institution_id,sale_id,method,amount,reference,
      fee_rate_snapshot,fee_amount,created_by
    ) values (
      p_institution_id,rid,payment->>'method',(payment->>'amount')::numeric,
      coalesce(payment->>'reference',''),rate,
      round((payment->>'amount')::numeric*rate,2),auth.uid()
    );
    fee:=fee+round((payment->>'amount')::numeric*rate,2);
  end loop;

  select round(s.area*s.wholesale_price_snapshot,2),coalesce(m.commission_rate,0)
    into merchandise_wholesale,commission_rate
  from public.sales s
  left join public.institution_memberships m
    on m.institution_id=s.institution_id and m.user_id=s.seller_id
      and m.role='seller' and m.status='active'
  where s.id=rid;

  carpet_gross:=round(p_length*4*p_sale_price,2);
  carpet_discount:=case when gross=0 then 0
    else round(discount*carpet_gross/gross,2) end;
  calculated_seller_profit:=round(greatest(
    carpet_gross-carpet_discount-coalesce(merchandise_wholesale,0),0
  ),2);

  update public.sales set
    financial_snapshot_version=2,
    currency_code='SAR',
    tax_category='S',
    vat_rate=.15,
    line_extension_amount=gross,
    discount_amount=discount,
    tax_exclusive_amount=taxable,
    vat_amount=vat,
    tax_inclusive_amount=payable,
    payable_amount=payable,
    payment_fee=fee,
    seller_profit=calculated_seller_profit,
    seller_commission=round(calculated_seller_profit*commission_rate,2),
    customer_payment=coalesce((p_payments->0->>'method'),'other')
  where id=rid;
  return rid;
end $$;
revoke all on function public.record_sale_financial_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb,numeric) from public,anon;
grant execute on function public.record_sale_financial_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb,numeric) to authenticated;

create or replace function public.operating_summary(
  p_institution_id uuid,p_from timestamptz,p_to timestamptz
) returns table(
  sales_amount numeric,total_length numeric,total_area numeric,sale_count bigint,
  merchandise_cost numeric,addon_cost numeric,driver_cost numeric,
  payment_fees numeric,gross_profit numeric,cash numeric,network numeric,
  bank_transfer numeric,visa numeric,tamara numeric,tabby numeric,other numeric
) language plpgsql stable security definer set search_path=public as $$
begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then
    raise exception 'Insufficient permission';
  end if;
  return query with ss as (
    select s.id,coalesce(s.tax_exclusive_amount,s.total) operational_sales,
      s.length,s.area,s.supplier_unit_cost_snapshot,s.driver_fee
    from public.sales s
    where s.institution_id=p_institution_id and s.status='completed'
      and s.created_at>=p_from and s.created_at<p_to
  ), a as (
    select sa.sale_id,sum(sa.quantity*sa.cost_unit_price) cost
    from public.sale_addons sa join ss on ss.id=sa.sale_id group by sa.sale_id
  ), p as (
    select sp.sale_id,sum(sp.fee_amount) fees
    from public.sale_payments sp join ss on ss.id=sp.sale_id group by sp.sale_id
  ), methods as (
    select sp.method,sum(sp.amount) amount
    from public.sale_payments sp join ss on ss.id=sp.sale_id group by sp.method
  ), totals as (
    select coalesce(sum(ss.operational_sales),0) sales_amount,
      coalesce(sum(ss.length),0) total_length,coalesce(sum(ss.area),0) total_area,
      count(*) sale_count,
      coalesce(sum(ss.area*ss.supplier_unit_cost_snapshot),0) merchandise_cost,
      coalesce(sum(coalesce(a.cost,0)),0) addon_cost,
      coalesce(sum(ss.driver_fee),0) driver_cost,
      coalesce(sum(coalesce(p.fees,0)),0) payment_fees
    from ss left join a on a.sale_id=ss.id left join p on p.sale_id=ss.id
  )
  select t.sales_amount,t.total_length,t.total_area,t.sale_count,
    t.merchandise_cost,t.addon_cost,t.driver_cost,t.payment_fees,
    t.sales_amount-t.merchandise_cost-t.addon_cost-t.driver_cost-t.payment_fees,
    coalesce((select amount from methods where method='cash'),0),
    coalesce((select amount from methods where method='network'),0),
    coalesce((select amount from methods where method='bank_transfer'),0),
    coalesce((select amount from methods where method='visa'),0),
    coalesce((select amount from methods where method='tamara'),0),
    coalesce((select amount from methods where method='tabby'),0),
    coalesce((select amount from methods where method='other'),0)
  from totals t;
end $$;
revoke all on function public.operating_summary(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.operating_summary(uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.operating_sales(
  p_institution_id uuid,p_from timestamptz,p_to timestamptz,p_search text default ''
) returns table(
  sale_id uuid,created_at timestamptz,length numeric,area numeric,item_name text,
  color text,addons text,payments text,sales_amount numeric,seller_name text,
  driver_name text,driver_cost numeric,merchandise_cost numeric,addon_cost numeric,
  payment_fees numeric,total_cost numeric,gross_profit numeric,notes text,status text
) language plpgsql stable security definer set search_path=public as $$
begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then
    raise exception 'Insufficient permission';
  end if;
  return query select s.id,s.created_at,s.length,s.area,i.name,i.color,
    coalesce((select string_agg(sa.name_snapshot||' × '||trim(to_char(sa.quantity,'FM999999990.###')),', ' order by sa.created_at) from public.sale_addons sa where sa.sale_id=s.id),''),
    coalesce((select string_agg(sp.method||': '||trim(to_char(sp.amount,'FM999999990.00')),', ' order by sp.paid_at) from public.sale_payments sp where sp.sale_id=s.id),''),
    coalesce(s.tax_exclusive_amount,s.total),coalesce(sel.full_name,'بائع'),
    coalesce(drv.full_name,''),s.driver_fee,round(s.area*s.supplier_unit_cost_snapshot,2),
    coalesce((select sum(sa.quantity*sa.cost_unit_price) from public.sale_addons sa where sa.sale_id=s.id),0),
    coalesce((select sum(sp.fee_amount) from public.sale_payments sp where sp.sale_id=s.id),0),
    round(s.area*s.supplier_unit_cost_snapshot,2)+coalesce((select sum(sa.quantity*sa.cost_unit_price) from public.sale_addons sa where sa.sale_id=s.id),0)+s.driver_fee+coalesce((select sum(sp.fee_amount) from public.sale_payments sp where sp.sale_id=s.id),0),
    coalesce(s.tax_exclusive_amount,s.total)-(round(s.area*s.supplier_unit_cost_snapshot,2)+coalesce((select sum(sa.quantity*sa.cost_unit_price) from public.sale_addons sa where sa.sale_id=s.id),0)+s.driver_fee+coalesce((select sum(sp.fee_amount) from public.sale_payments sp where sp.sale_id=s.id),0)),
    s.notes,s.status
  from public.sales s
  join public.inventory_items i on i.id=s.inventory_id
  join public.profiles sel on sel.id=s.seller_id
  left join public.profiles drv on drv.id=s.driver_id
  where s.institution_id=p_institution_id and s.created_at>=p_from and s.created_at<p_to
    and (coalesce(trim(p_search),'')='' or s.notes ilike '%'||trim(p_search)||'%'
      or i.name ilike '%'||trim(p_search)||'%' or i.color ilike '%'||trim(p_search)||'%'
      or sel.full_name ilike '%'||trim(p_search)||'%')
  order by s.created_at desc;
end $$;
revoke all on function public.operating_sales(uuid,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.operating_sales(uuid,timestamptz,timestamptz,text) to authenticated;

create or replace function public.seller_performance(
  p_institution_id uuid,p_seller_id uuid,p_from timestamptz,p_to timestamptz
) returns table(
  sale_count bigint,total_length numeric,total_area numeric,sales_amount numeric,
  merchandise_cost numeric,gross_profit numeric,commission numeric,
  ledger_deductions numeric,net_due numeric
) language plpgsql stable security definer set search_path=public as $$
declare can_finance boolean;
begin
  if not public.is_institution_member(p_institution_id) then raise exception 'Insufficient permission'; end if;
  if auth.uid()<>p_seller_id and not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then
    raise exception 'Insufficient permission';
  end if;
  can_finance:=public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]);
  return query with s as (
    select * from public.sales where institution_id=p_institution_id
      and seller_id=p_seller_id and status='completed'
      and created_at>=p_from and created_at<p_to
  ), l as (
    select coalesce(sum(amount),0) deductions from public.seller_ledger
    where institution_id=p_institution_id and seller_id=p_seller_id
      and entry_date>=p_from::date and entry_date<p_to::date
  ), x as (
    select count(*) cnt,coalesce(sum(length),0) len,coalesce(sum(area),0) ar,
      coalesce(sum(coalesce(tax_exclusive_amount,total)),0) sales,
      coalesce(sum(area*supplier_unit_cost_snapshot),0) merch,
      coalesce(sum(seller_commission),0) comm from s
  )
  select x.cnt,x.len,x.ar,x.sales,
    case when can_finance then x.merch else null end,
    case when can_finance then x.sales-x.merch-coalesce((select sum(driver_fee) from s),0) else null end,
    x.comm,l.deductions,x.comm-l.deductions from x cross join l;
end $$;
revoke all on function public.seller_performance(uuid,uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.seller_performance(uuid,uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.branch_operating_summary(
  p_institution_id uuid,p_branch_id uuid,p_from timestamptz,p_to timestamptz
) returns table(
  sale_count bigint,total_length numeric,total_area numeric,sales_amount numeric,
  merchandise_cost numeric,driver_cost numeric,gross_profit numeric,
  payments jsonb,expenses numeric
) language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_institution_member(p_institution_id) then raise exception 'Insufficient permission'; end if;
  if p_branch_id is not null and not public.can_access_branch(p_branch_id) then raise exception 'Branch access denied'; end if;
  return query with allowed_sales as (
    select s.* from public.sales s
    where s.institution_id=p_institution_id and s.status='completed'
      and s.created_at>=p_from and s.created_at<p_to
      and ((p_branch_id is not null and s.branch_id=p_branch_id and public.can_access_branch(s.branch_id))
        or (p_branch_id is null and public.can_access_branch(s.branch_id)))
  ), pay as (
    select coalesce(jsonb_object_agg(method,total),'{}'::jsonb) j
    from (select sp.method,sum(sp.amount) total from public.sale_payments sp
      join allowed_sales s on s.id=sp.sale_id group by sp.method) x
  ), ex as (
    select coalesce(sum(e.amount),0) total from public.expenses e
    where e.institution_id=p_institution_id and e.expense_date>=p_from::date
      and e.expense_date<p_to::date
      and ((p_branch_id is null and (e.branch_id is null or public.can_access_branch(e.branch_id)))
        or e.branch_id=p_branch_id)
  )
  select count(s.id),coalesce(sum(s.length),0),coalesce(sum(s.area),0),
    coalesce(sum(coalesce(s.tax_exclusive_amount,s.total)),0),
    coalesce(sum(s.area*s.supplier_unit_cost_snapshot+(select coalesce(sum(sa.quantity*sa.cost_unit_price),0) from public.sale_addons sa where sa.sale_id=s.id)),0),
    coalesce(sum(s.driver_fee),0),
    coalesce(sum(coalesce(s.tax_exclusive_amount,s.total)-(s.area*s.supplier_unit_cost_snapshot)-(select coalesce(sum(sa.quantity*sa.cost_unit_price),0) from public.sale_addons sa where sa.sale_id=s.id)-s.driver_fee-s.payment_fee),0),
    (select j from pay),(select total from ex)
  from allowed_sales s;
end $$;
revoke all on function public.branch_operating_summary(uuid,uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.branch_operating_summary(uuid,uuid,timestamptz,timestamptz) to authenticated;

create or replace function public.branch_report(
  p_institution_id uuid,p_from timestamptz,p_to timestamptz
) returns table(
  branch_id uuid,branch_name text,sales numeric,cost numeric,profit numeric,
  expenses numeric,length_sold numeric,area_sold numeric,sale_count bigint
) language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_institution_member(p_institution_id) then raise exception 'Insufficient permission'; end if;
  return query select b.id,b.name,
    coalesce(sum(coalesce(s.tax_exclusive_amount,s.total)),0),
    coalesce(sum(s.area*s.supplier_unit_cost_snapshot+(select coalesce(sum(sa.quantity*sa.cost_unit_price),0) from public.sale_addons sa where sa.sale_id=s.id)),0),
    coalesce(sum(coalesce(s.tax_exclusive_amount,s.total)-s.area*s.supplier_unit_cost_snapshot-(select coalesce(sum(sa.quantity*sa.cost_unit_price),0) from public.sale_addons sa where sa.sale_id=s.id)-s.driver_fee-s.payment_fee),0),
    coalesce((select sum(e.amount) from public.expenses e where e.branch_id=b.id and e.expense_date>=p_from::date and e.expense_date<p_to::date),0),
    coalesce(sum(s.length),0),coalesce(sum(s.area),0),count(s.id)
  from public.branches b
  left join public.sales s on s.branch_id=b.id and s.status='completed'
    and s.created_at>=p_from and s.created_at<p_to
  where b.institution_id=p_institution_id and public.can_access_branch(b.id)
  group by b.id,b.name order by b.name;
end $$;
revoke all on function public.branch_report(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.branch_report(uuid,timestamptz,timestamptz) to authenticated;

-- A carpet-only sale has no add-on rows. Preserve the immutable invoice shape
-- by storing the existing empty-summary representation instead of NULL.
create or replace function public.normalize_empty_invoice_summaries()
returns trigger language plpgsql set search_path=public as $$
begin
  new.addons_summary:=coalesce(new.addons_summary,'');
  return new;
end $$;
revoke all on function public.normalize_empty_invoice_summaries() from public,anon,authenticated;

drop trigger if exists normalize_empty_invoice_summaries on public.invoices;
create trigger normalize_empty_invoice_summaries
before insert on public.invoices
for each row execute function public.normalize_empty_invoice_summaries();
