create index institutions_created_by_idx on public.institutions(created_by);
create index driver_connections_connected_by_idx on public.institution_driver_connections(connected_by);
create index invitations_created_by_idx on public.institution_invitations(created_by);
create index invitations_claimed_by_idx on public.institution_invitations(claimed_by) where claimed_by is not null;
create index seller_ledger_created_by_idx on public.seller_ledger(created_by);
