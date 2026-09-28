-- SECURITY: PostgreSQL grants EXECUTE to PUBLIC by default. Restrict the new
-- SECURITY DEFINER onboarding/subscription RPCs to authenticated users only.
revoke execute on function public.create_institution_v2(text,text,text,text,text,text,text) from public, anon;
revoke execute on function public.create_institution_subscription(uuid,text) from public, anon;
revoke execute on function public.institution_subscription_entitlement(uuid) from public, anon;
grant execute on function public.create_institution_v2(text,text,text,text,text,text,text) to authenticated;
grant execute on function public.create_institution_subscription(uuid,text) to authenticated;
grant execute on function public.institution_subscription_entitlement(uuid) to authenticated;
