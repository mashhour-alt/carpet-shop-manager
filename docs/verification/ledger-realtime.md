# Ledger / realtime verification — release remains OPEN

Base: `457eb284be37f0e11147b48b02c4afd8f14654f7`.
Branch: `fix/continuous-ledger-realtime`.

## Causes and implementation

The old statement functions filtered out prior movements before computing the
window sum. The detail UI used that period's first row as the current balance
(and displayed zero for an empty period). Account summaries also capped balances
at the selected period end. Accounts' settlements link opened SalesSettlementPage.
There were no realtime publication tables or durable notification records.
Legacy permissive seller-ledger policies also bypassed branch filtering.

The existing sales, seller_ledger, driver_trips, driver_account_entries,
supplier_deliveries/items and supplier_account_entries remain canonical sources.
`private.account_movements` assembles their authorized rows without copying them.
The public invoker wrapper and `account_ledger` derive current, opening, closing
and per-movement running balances from that same history. Ordering uses event
time, type and source UUID. Date filters only restrict displayed movements and
period totals; current balance remains unfiltered. No monthly opening entries
are inserted. Existing sale cancellation and financial sign conventions are
preserved; no salary accrual rules have been invented.

Monthly closing continues to save an idempotent period-end snapshot. Source
movements and invoices are retained. Historical report balances use the period
end rather than today's balance. Branch totals and snapshot permissions were
corrected to respect financial access.

Financial/sale triggers insert recipient-scoped notifications in the same
transaction as the source event. A unique recipient/source/event constraint
prevents duplicate notifications. The only realtime publication added is
account_notifications; RLS controls delivery. One shared authenticated channel
per repository invalidates active account pages, notification badges and driver
views. Reconnect and app resume refresh data; page disposal removes listeners.
Successful sales notify the owner and authorized accountants. Notifications
reference the source UUID and contain no bank details.

Accounts now opens financial statements instead of the sales form. The sales
workflow itself is unchanged. Drivers can open a continuous statement per active
institution. OS/background push is NOT CONFIGURED. A live two-device websocket
session and Android runtime have NOT been verified.

## Applied migrations

- 20261003112911_continuous_ledger_realtime_notifications.sql
- 20261003113734_ledger_scope_hardening.sql

These are new migrations; no historical migrations were recreated. The first
application included rollback-only numeric self-tests. API financial rows are
append-only. Trip payments lock the trip and detect already-paid/source entries
before creating another payment. Privileged history assembly is in a private
schema; exposed read wrappers use security invoker.

## Database checks on the connected schema

All synthetic scenario data used rollback transactions. Existing regression
scripts additionally have explicit outer BEGIN/ROLLBACK to guarantee cleanup.

| Check | Result |
|---|---|
| 500 - 100; next month opening/current 400 | PASS |
| Next entitlement +200 => 600; payment 700 => -100 | PASS |
| 288 - 400 => -112 | PASS |
| Empty historical period preserves current balance | PASS |
| Owner and seller see the same canonical payment UUID | PASS |
| One notification per affected recipient/source | PASS |
| Sale notifications to owner and authorized accountant | PASS |
| Repeat monthly closing retains movements/sales and one snapshot | PASS |
| Institution, seller and accountant branch isolation | PASS |
| Suspended driver A cannot read A; active B remains accessible | PASS |
| Notification isolation and prohibited financial edits | PASS |
| Driver directory excludes bank/IBAN fields | PASS |
| Operational VAT / split-payment / invoice parity regression | PASS |
| Quotation header/items -> sale -> invoice regression | PASS |
| ZATCA stage 2 financial snapshots, invoice_lines, PDF/QR inputs | PASS |
| ZATCA stage 3 database security regression | PASS |
| Materials 100 - 20 => 80 | FAIL: actual 100, zero sale movements |

## Release blocker: existing material stock regression

`materials_100_20_transaction.sql` fails before reversal testing: the completed
sale leaves stock at 100 instead of 80 and records zero material sale movements.
The earlier prelaunch test (10 - 2) also fails. The baseline
record_sale_financial_v2 function contains neither stock_quantity updates nor
addon_movements inserts. This task does not change that function or redesign
materials. Reversal/double-reversal requirements cannot be claimed PASS.

Full regression is therefore NOT PASS and this release must NOT be marked CLOSED.
Salary entitlements without a historical accrual source and existing adjustment
sign conventions remain business-rule ambiguities, preserved rather than guessed.

## Flutter / CI evidence

The added widget tests cover negative balances after an event, an empty period,
listener disposal and Accounts navigation. Flutter analyze/test, backend
Deno/security/UBL/XSD/concurrency tests and Android release build are executed by
Build Android Release APK for this branch. Consult the exact final Actions run;
a green build is not a substitute for the failed material regression above.
The artifact contains app-release.apk and its SHA-256 file.

Runtime Android = NOT AVAILABLE.
