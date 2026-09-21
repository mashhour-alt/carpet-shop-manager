create or replace function public.enforce_addon_cost_snapshot() returns trigger
language plpgsql set search_path=public as $$
declare t public.addon_types%rowtype;
begin
 if new.addon_type_id is not null then
  select * into t from public.addon_types where id=new.addon_type_id and institution_id=new.institution_id;
  if not found then raise exception 'Invalid add-on type'; end if;
  new.name_snapshot:=t.name;
  new.unit_snapshot:=t.unit;
  new.cost_unit_price:=t.default_cost_price;
  if new.supplier_id is null then new.supplier_id:=t.supplier_id; end if;
 end if;
 return new;
end; $$;
drop trigger if exists enforce_addon_cost_snapshot on public.sale_addons;
create trigger enforce_addon_cost_snapshot before insert or update on public.sale_addons
for each row execute function public.enforce_addon_cost_snapshot();