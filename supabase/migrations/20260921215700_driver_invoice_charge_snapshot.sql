alter table public.sales add column if not exists driver_fee_included_in_sale boolean not null default true;
do $$
declare d text;
begin
 select pg_get_functiondef('public.record_sale_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb)'::regprocedure) into d;
 d:=replace(d,'returning id into result_id;','returning id into result_id; update public.sales set driver_fee_included_in_sale=false where id=result_id;');
 execute d;
 select pg_get_functiondef('public.issue_tax_invoice(uuid,text,text,text,text,text,numeric)'::regprocedure) into d;
 d:=replace(d,'sale_row.iron_pieces,sale_row.iron_amount,sale_row.driver_fee,sale_row.customer_payment,','sale_row.iron_pieces,sale_row.iron_amount,case when sale_row.driver_fee_included_in_sale then sale_row.driver_fee else 0 end,sale_row.customer_payment,');
 execute d;
end $$;