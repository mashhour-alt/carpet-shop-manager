drop trigger if exists invoice_lines_no_update on public.invoice_lines;
drop function if exists public.prevent_invoice_line_mutation();
-- Authenticated clients only have SELECT on invoice_lines. Financial lines are created
-- inside issue_tax_invoice(); there is intentionally no UPDATE/DELETE grant or RPC.
