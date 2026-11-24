-- Legacy RPCs superseded by v2/v3 versions. The app no longer calls them,
-- and create_institution bypassed the subscription onboarding flow.
revoke execute on function public.create_institution(text,text,text,text,text,text) from public, anon, authenticated;
revoke execute on function public.issue_tax_invoice(uuid,text,text,text,text,text,numeric) from public, anon, authenticated;
revoke execute on function public.issue_tax_invoice_v2(uuid,text,text,text,text,text,numeric,text,text,text,text,text,text) from public, anon, authenticated;
revoke execute on function public.create_quotation(uuid,uuid,uuid,text,text,text,numeric,numeric,date,text) from public, anon, authenticated;
revoke execute on function public.record_sale_v2(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,text,jsonb,jsonb) from public, anon, authenticated;
