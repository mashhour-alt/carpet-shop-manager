-- ZATCA Stage 1: canonical immutable invoice financial snapshot.
-- PDF/QR/XML must consume this persisted snapshot; never recalculate from live sale rows.
create table if not exists public.invoice_lines (
  id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id) on delete restrict,
  line_no integer not null check(line_no>0), source_kind text not null check(source_kind in('carpet','addon','installation','glue','iron','delivery')),
  source_id uuid, description text not null, quantity numeric(14,3) not null check(quantity>0), unit_code text not null default 'PCE',
  unit_price numeric(14,2) not null check(unit_price>=0), gross_amount numeric(14,2) not null check(gross_amount>=0),
  discount_amount numeric(14,2) not null default 0 check(discount_amount>=0), taxable_amount numeric(14,2) not null check(taxable_amount>=0),
  tax_category text not null default 'S', vat_rate numeric(7,4) not null default .15 check(vat_rate>=0),
  vat_amount numeric(14,2) not null check(vat_amount>=0), total_with_vat numeric(14,2) not null check(total_with_vat>=0),
  created_at timestamptz not null default now(), unique(invoice_id,line_no));
alter table public.invoice_lines enable row level security;
revoke all on table public.invoice_lines from anon,authenticated; grant select on table public.invoice_lines to authenticated; grant all on table public.invoice_lines to service_role;
create policy invoice_lines_read on public.invoice_lines for select to authenticated using(exists(select 1 from public.invoices i where i.id=invoice_id and(i.seller_id=(select auth.uid()) or(public.can_access_branch(i.branch_id) and public.has_institution_role(i.institution_id,array['owner','accountant']::public.institution_role[])))));
alter table public.invoices add column if not exists currency_code text not null default 'SAR', add column if not exists tax_category text not null default 'S',
 add column if not exists financial_snapshot_version integer not null default 1, add column if not exists line_extension_amount numeric(14,2),
 add column if not exists tax_exclusive_amount numeric(14,2), add column if not exists tax_inclusive_amount numeric(14,2), add column if not exists payable_amount numeric(14,2);
update public.invoices set line_extension_amount=coalesce(line_extension_amount,subtotal),tax_exclusive_amount=coalesce(tax_exclusive_amount,taxable_amount),tax_inclusive_amount=coalesce(tax_inclusive_amount,total_with_vat),payable_amount=coalesce(payable_amount,total_with_vat)
where line_extension_amount is null or tax_exclusive_amount is null or tax_inclusive_amount is null or payable_amount is null;
alter table public.invoices alter column line_extension_amount set not null,alter column tax_exclusive_amount set not null,alter column tax_inclusive_amount set not null,alter column payable_amount set not null;
create or replace function public.prevent_invoice_financial_mutation() returns trigger language plpgsql set search_path=public as $$begin
 if row(old.invoice_number,old.sale_id,old.branch_id,old.subtotal,old.discount_amount,old.taxable_amount,old.vat_rate,old.vat_amount,old.total_with_vat,old.line_extension_amount,old.tax_exclusive_amount,old.tax_inclusive_amount,old.payable_amount) is distinct from row(new.invoice_number,new.sale_id,new.branch_id,new.subtotal,new.discount_amount,new.taxable_amount,new.vat_rate,new.vat_amount,new.total_with_vat,new.line_extension_amount,new.tax_exclusive_amount,new.tax_inclusive_amount,new.payable_amount) then raise exception 'Issued invoice financial snapshot is immutable';end if;return new;end$$;
create trigger invoices_financial_immutable before update on public.invoices for each row execute function public.prevent_invoice_financial_mutation();
create or replace function public.prevent_invoice_line_mutation() returns trigger language plpgsql set search_path=public as $$begin raise exception 'Issued invoice lines are immutable';end$$;
create trigger invoice_lines_no_update before update or delete on public.invoice_lines for each row execute function public.prevent_invoice_line_mutation();
create or replace function public.issue_tax_invoice(p_sale_id uuid,p_customer_name text default '',p_customer_cr text default '',p_customer_tax text default '',p_customer_address text default '',p_invoice_kind text default 'simplified',p_discount numeric default 0)
returns uuid language plpgsql security definer set search_path=public as $$
declare s public.sales%rowtype;rid uuid;num bigint;carpet numeric;gross numeric;discount numeric;taxable numeric;vat numeric;totalvat numeric;ln int:=0;r record;line_discount numeric;allocated numeric:=0;line_count int;
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;if p_invoice_kind not in('simplified','tax') then raise exception 'Invalid invoice kind';end if;
 select * into s from public.sales where id=p_sale_id for update;if not found then raise exception 'Sale not found';end if;if s.status<>'completed' then raise exception 'Only completed sales can be invoiced';end if;
 if not((s.seller_id=auth.uid()) or(public.can_access_branch(s.branch_id) and public.has_institution_role(s.institution_id,array['owner','accountant']::public.institution_role[]))) then raise exception 'Insufficient permission';end if;
 select id into rid from public.invoices where sale_id=s.id;if found then return rid;end if;
 discount:=round(coalesce(p_discount,0),2);carpet:=round(s.area*s.sale_price_per_sqm,2);
 select round(carpet+coalesce(sum(round(sa.quantity*sa.sale_unit_price,2)),0),2),count(*)+1 into gross,line_count from public.sale_addons sa where sa.sale_id=s.id;
 if discount<0 or discount>gross then raise exception 'Discount must be between zero and invoice gross amount';end if;
 if p_invoice_kind='tax' and(nullif(trim(coalesce(p_customer_name,'')),'') is null or nullif(trim(coalesce(p_customer_tax,'')),'') is null or nullif(trim(coalesce(p_customer_address,'')),'') is null) then raise exception 'Buyer name, VAT number and address are required for a tax invoice';end if;
 taxable:=round(gross-discount,2);vat:=round(taxable*.15,2);totalvat:=taxable+vat;
 insert into public.invoice_counters(institution_id,next_number) values(s.institution_id,2) on conflict(institution_id) do update set next_number=public.invoice_counters.next_number+1 returning next_number-1 into num;
 insert into public.invoices(institution_id,branch_id,sale_id,invoice_number,seller_id,customer_name,customer_commercial_registration,customer_tax_number,item_name,color,length,width,area,price_per_sqm,carpet_amount,installation_amount,glue_gallons,glue_amount,iron_pieces,iron_amount,driver_fee,payment_method,subtotal,vat_rate,vat_amount,total_with_vat,created_by,invoice_kind,customer_address,seller_name,discount_amount,taxable_amount,payment_summary,addons_summary,addons_amount,currency_code,tax_category,financial_snapshot_version,line_extension_amount,tax_exclusive_amount,tax_inclusive_amount,payable_amount)
 select s.institution_id,s.branch_id,s.id,num,s.seller_id,coalesce(nullif(trim(p_customer_name),''),nullif(trim(s.customer_name),''),'عميل نقدي'),trim(coalesce(p_customer_cr,'')),trim(coalesce(p_customer_tax,'')),iv.name,iv.color,s.length,s.width,s.area,s.sale_price_per_sqm,carpet,0,0,0,0,0,s.driver_fee,s.customer_payment::text,gross,.15,vat,totalvat,auth.uid(),p_invoice_kind,trim(coalesce(p_customer_address,'')),coalesce(pr.full_name,''),discount,taxable,(select string_agg(method||': '||amount,' / ' order by paid_at) from public.sale_payments where sale_id=s.id),(select string_agg(name_snapshot||' × '||quantity,' / ' order by created_at) from public.sale_addons where sale_id=s.id),gross-carpet,'SAR','S',2,gross,taxable,totalvat,totalvat from public.inventory_items iv left join public.profiles pr on pr.id=s.seller_id where iv.id=s.inventory_id returning id into rid;
 ln:=1;line_discount:=case when line_count=1 then discount when gross=0 then 0 else round(discount*carpet/gross,2) end;allocated:=line_discount;
 insert into public.invoice_lines(invoice_id,line_no,source_kind,source_id,description,quantity,unit_code,unit_price,gross_amount,discount_amount,taxable_amount,tax_category,vat_rate,vat_amount,total_with_vat)
 select rid,ln,'carpet',iv.id,iv.name||' - '||iv.color,s.area,'MTK',s.sale_price_per_sqm,carpet,line_discount,carpet-line_discount,'S',.15,round((carpet-line_discount)*.15,2),(carpet-line_discount)+round((carpet-line_discount)*.15,2) from public.inventory_items iv where iv.id=s.inventory_id;
 for r in select sa.* from public.sale_addons sa where sa.sale_id=s.id order by sa.created_at,sa.id loop ln:=ln+1;
   line_discount:=case when ln=line_count then discount-allocated when gross=0 then 0 else round(discount*round(r.quantity*r.sale_unit_price,2)/gross,2) end;allocated:=allocated+line_discount;
   insert into public.invoice_lines(invoice_id,line_no,source_kind,source_id,description,quantity,unit_code,unit_price,gross_amount,discount_amount,taxable_amount,tax_category,vat_rate,vat_amount,total_with_vat)
   values(rid,ln,'addon',r.id,r.name_snapshot,r.quantity,'PCE',r.sale_unit_price,round(r.quantity*r.sale_unit_price,2),line_discount,round(r.quantity*r.sale_unit_price,2)-line_discount,'S',.15,round((round(r.quantity*r.sale_unit_price,2)-line_discount)*.15,2),(round(r.quantity*r.sale_unit_price,2)-line_discount)+round((round(r.quantity*r.sale_unit_price,2)-line_discount)*.15,2));end loop;
 if (select round(sum(gross_amount),2) from public.invoice_lines where invoice_id=rid)<>gross or(select round(sum(discount_amount),2) from public.invoice_lines where invoice_id=rid)<>discount or(select round(sum(taxable_amount),2) from public.invoice_lines where invoice_id=rid)<>taxable then raise exception 'Invoice snapshot line allocation mismatch';end if;
 update public.invoice_lines set vat_amount=vat_amount+(vat-(select sum(vat_amount) from public.invoice_lines where invoice_id=rid)),total_with_vat=taxable_amount+vat_amount+(vat-(select sum(vat_amount) from public.invoice_lines where invoice_id=rid)) where invoice_id=rid and line_no=line_count;
 if (select round(sum(vat_amount),2) from public.invoice_lines where invoice_id=rid)<>vat or(select round(sum(total_with_vat),2) from public.invoice_lines where invoice_id=rid)<>totalvat then raise exception 'Invoice snapshot VAT mismatch';end if;return rid;
end$$;
revoke all on function public.issue_tax_invoice(uuid,text,text,text,text,text,numeric) from public,anon;grant execute on function public.issue_tax_invoice(uuid,text,text,text,text,text,numeric) to authenticated;
