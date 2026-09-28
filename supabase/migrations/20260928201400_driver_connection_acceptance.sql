-- Add an acceptance step to the existing many-to-many driver relationship.
-- Existing active connections remain active and no driver account is deleted.
alter type public.membership_status add value if not exists 'pending';

create or replace function public.connect_driver(p_institution_id uuid,p_phone text) returns uuid
language plpgsql security definer set search_path=public as $$
declare result_id uuid; begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  select p.id into result_id from public.profiles p join public.driver_profiles d on d.user_id=p.id where p.account_kind='driver' and p.phone=trim(p_phone);
  if result_id is null then raise exception 'Driver account was not found'; end if;
  insert into public.institution_driver_connections(institution_id,driver_id,status,connected_by)
  values(p_institution_id,result_id,'pending',auth.uid())
  on conflict(institution_id,driver_id) do update set status=case when public.institution_driver_connections.status='active' then 'active' else 'pending' end,connected_by=auth.uid();
  return result_id;
end $$;

create or replace function public.accept_driver_connection(p_institution_id uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  update public.institution_driver_connections set status='active'
  where institution_id=p_institution_id and driver_id=auth.uid() and status='pending';
  if not found then raise exception 'Driver invitation was not found'; end if;
end $$;

create or replace function public.end_driver_connection(p_institution_id uuid,p_driver_id uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.has_institution_role(p_institution_id,array['owner','accountant']::public.institution_role[]) then raise exception 'Insufficient permission'; end if;
  update public.institution_driver_connections set status='suspended'
  where institution_id=p_institution_id and driver_id=p_driver_id;
  if not found then raise exception 'Driver relationship was not found'; end if;
end $$;

create or replace function public.my_driver_connections()
returns table(institution_id uuid,institution_name text,status public.membership_status,created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select c.institution_id,i.name,c.status,c.created_at
  from public.institution_driver_connections c join public.institutions i on i.id=c.institution_id
  where c.driver_id=auth.uid() order by c.created_at desc
$$;

revoke execute on function public.accept_driver_connection(uuid),public.end_driver_connection(uuid,uuid),public.my_driver_connections() from public,anon;
grant execute on function public.accept_driver_connection(uuid),public.end_driver_connection(uuid,uuid),public.my_driver_connections() to authenticated;
