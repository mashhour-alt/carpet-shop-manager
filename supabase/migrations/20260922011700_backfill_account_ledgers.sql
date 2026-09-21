-- Preserve historical supplier and driver payments in the new ledgers.
insert into public.supplier_account_entries(institution_id,supplier_id,entry_type,balance_effect,payment_method,reference,note,created_by,created_at)
select s.institution_id,s.id,'payment',-s.paid_total,'','legacy','رصيد مدفوع سابق قبل كشف الحساب',i.owner_id,s.created_at
from public.suppliers s join public.institutions i on i.id=s.institution_id
where s.paid_total>0 and not exists(select 1 from public.supplier_account_entries e where e.supplier_id=s.id);

insert into public.driver_account_entries(institution_id,driver_id,entry_type,balance_effect,payment_method,reference,note,source_type,source_id,created_by,created_at)
select t.institution_id,t.driver_id,'payment',-t.amount,coalesce(t.payment_method::text,''),'legacy','سداد مشوار سابق','trip',t.id,i.owner_id,coalesce(t.paid_at,t.created_at)
from public.driver_trips t join public.institutions i on i.id=t.institution_id
where t.payment_status='paid' and not exists(select 1 from public.driver_account_entries e where e.source_type='trip' and e.source_id=t.id);