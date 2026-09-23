alter table public.sales add column if not exists financial_snapshot_version integer not null default 1, add column if not exists currency_code text not null default 'SAR', add column if not exists tax_category text not null default 'S', add column if not exists vat_rate numeric(7,4) not null default .15, add column if not exists line_extension_amount numeric(14,2), add column if not exists discount_amount numeric(14,2) not null default 0, add column if not exists tax_exclusive_amount numeric(14,2), add column if not exists vat_amount numeric(14,2), add column if not exists tax_inclusive_amount numeric(14,2), add column if not exists payable_amount numeric(14,2);
update public.sales set line_extension_amount=coalesce(line_extension_amount,total),tax_exclusive_amount=coalesce(tax_exclusive_amount,total),vat_amount=coalesce(vat_amount,0),tax_inclusive_amount=coalesce(tax_inclusive_amount,total),payable_amount=coalesce(payable_amount,total) where line_extension_amount is null or tax_exclusive_amount is null or vat_amount is null or tax_inclusive_amount is null or payable_amount is null;

create or replace function public.record_sale_financial_v2(p_institution_id uuid,p_inventory_id uuid,p_seller_id uuid,p_driver_id uuid,p_customer_name text,p_length numeric,p_sale_price numeric,p_driver_fee numeric,p_notes text,p_payments jsonb,p_addons jsonb default '[]'::jsonb,p_discount numeric default 0) returns uuid language plpgsql security definer set search_path=public as $$
declare gross numeric:=0;taxable numeric;vat numeric;payable numeric;paid numeric:=0;legacy_payments jsonb;rid uuid;p jsonb;inst public.institutions%rowtype;fee numeric:=0;rate numeric;
begin
 select round(p_length*4*p_sale_price+coalesce(sum(round(coalesce((x->>'quantity')::numeric,0)*coalesce((x->>'sale_unit_price')::numeric,0),2)),0),2) into gross from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) x;
 if p_discount<0 or p_discount>gross then raise exception 'Invalid discount';end if;
 taxable:=round(gross-p_discount,2);vat:=round(taxable*.15,2);payable:=taxable+vat;
 select coalesce(sum((x->>'amount')::numeric),0) into paid from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) x;
 if round(paid,2)<>payable then raise exception 'Payments must equal canonical payable amount including VAT';end if;
 legacy_payments:=jsonb_build_array(jsonb_build_object('method','other','amount',gross,'reference','canonical-sale-bootstrap'));
 rid:=public.record_sale_v2(p_institution_id,p_inventory_id,p_seller_id,p_driver_id,p_customer_name,p_length,p_sale_price,p_driver_fee,p_notes,legacy_payments,p_addons);
 delete from public.sale_payments where sale_id=rid;select * into inst from public.institutions where id=p_institution_id;
 for p in select value from jsonb_array_elements(p_payments) loop
  rate:=case p->>'method' when 'visa' then inst.visa_fee_rate when 'tabby' then inst.tabby_fee_rate when 'tamara' then inst.tamara_fee_rate else 0 end;
  insert into public.sale_payments(institution_id,sale_id,method,amount,reference,fee_rate_snapshot,fee_amount,created_by) values(p_institution_id,rid,p->>'method',(p->>'amount')::numeric,coalesce(p->>'reference',''),rate,round((p->>'amount')::numeric*rate,2),auth.uid());fee:=fee+round((p->>'amount')::numeric*rate,2);
 end loop;
 update public.sales set financial_snapshot_version=2,currency_code='SAR',tax_category='S',vat_rate=.15,line_extension_amount=gross,discount_amount=p_discount,tax_exclusive_amount=taxable,vat_amount=vat,tax_inclusive_amount=payable,payable_amount=payable,payment_fee=fee,customer_payment=coalesce((p_payments->0->>'method'),'other') where id=rid;return rid;
end$$;
revoke all on function public.record_sale_financial_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb,numeric) from public,anon;
grant execute on function public.record_sale_financial_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb,numeric) to authenticated;

create or replace function public.enforce_invoice_sale_snapshot_parity() returns trigger language plpgsql set search_path=public as $$
declare s public.sales%rowtype;paid numeric;begin select * into s from public.sales where id=new.sale_id;
if s.financial_snapshot_version>=2 then
 if abs(new.line_extension_amount-s.line_extension_amount)>.009 or abs(new.discount_amount-s.discount_amount)>.009 or abs(new.tax_exclusive_amount-s.tax_exclusive_amount)>.009 or abs(new.vat_amount-s.vat_amount)>.009 or abs(new.payable_amount-s.payable_amount)>.009 then raise exception 'Invoice totals must equal sale canonical financial snapshot';end if;
 select round(coalesce(sum(amount),0),2) into paid from public.sale_payments where sale_id=s.id;if paid<>s.payable_amount then raise exception 'Sale payments must equal canonical payable amount';end if;end if;return new;end$$;
drop trigger if exists invoice_sale_snapshot_parity on public.invoices;
create trigger invoice_sale_snapshot_parity before insert on public.invoices for each row execute function public.enforce_invoice_sale_snapshot_parity();
