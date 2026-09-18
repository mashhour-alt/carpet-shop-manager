-- Counter rows are internal implementation details of issue_tax_invoice().
-- Keep an explicit deny policy so client roles can never read or mutate them.
create policy invoice_counters_no_client_access
on public.invoice_counters
as restrictive
for all
to authenticated
using (false)
with check (false);
