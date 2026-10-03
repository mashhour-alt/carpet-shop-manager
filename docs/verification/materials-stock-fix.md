# Canonical materials stock fix

Base: `95fd68ddd323b85f5ac4b5f38eef27cdfd5e4c1a`.

## Root cause and scope

The branch-aware replacement of `record_sale_v2` retained `sale_addons` snapshots but omitted the stock update and sale movement previously present in the material integration. The canonical `record_sale_financial_v2` delegated to that implementation without consuming materials. The old void implementation also omitted the now-required inventory movement branch and restored materials from current configuration instead of a recorded deduction.

Only the canonical sale/void paths change. There is no historical stock backfill, unit conversion, pricing, VAT, quotation, ledger, notification, role, branch authorization, monthly closing, invoice or ZATCA logic change. Existing explicit internal-consumable issuance remains unchanged; a sale does not infer gallons from area or automatically reverse `issue_to_seller` movements.

## Files and functions

- `supabase/migrations/20261003170904_canonical_material_stock_once.sql`: new internal `private.consume_sale_materials(uuid)`; one call added to `public.record_sale_financial_v2`; `public.void_sale` reverses recorded sale movements and returns harmlessly for an already voided sale after authorization.
- `supabase/migrations/20261003171032_material_void_existing_branch.sql`: carries the existing sale branch into the inventory reversal required by the current schema.
- `supabase/tests/materials_canonical_transaction.sql`: scenarios A–E plus fractional quantities, repeated lines, different units, existing area basis, untracked materials, internal issuance, shortage rollback, historical undeducted sales and helper permissions.
- `supabase/tests/materials_100_20_transaction.sql` and `supabase/tests/prelaunch_closing_transaction.sql`: qualify the existing `account_summaries.balance` test column to resolve a latent PL/pgSQL variable ambiguity exposed after materials began passing. Assertions and ledger functions are unchanged.
- This verification document.

Both migrations have been applied to the connected Farsha project. All other public function definitions have the same aggregate fingerprint before and after: `c6abc98c75f0d922c562a8cb01475c98`.

## Exactly-once boundary

Persisted `sale_addons.quantity` is the source of consumption, grouped by material. Row locks serialize processing of the same canonical sale and shared stock. The existing unique `(addon_type_id,sale_id,movement_type)` index is retained. Stock changes only when the corresponding movement is newly inserted; an insufficient balance aborts the whole sale transaction. Void restores the recorded negative movement even if tracking was later disabled. A historical sale with no deduction movement creates no material reversal.

Idempotency is by canonical **sale ID**. Retrying material processing for that ID or voiding that ID cannot change stock twice. Quotation conversion retains its existing row lock and rejects a repeat conversion. The existing create-sale RPC has no client request key: two separate successful create calls still represent two distinct sales. This fix does not introduce payload-based deduplication that could suppress legitimate sales.

## Connected database regression (2026-10-03)

All scripts run with explicit outer BEGIN/ROLLBACK; no fixture data is retained.

| Test | Result |
| --- | --- |
| A: stock 100, sale 20 | PASS: 80, one sale movement, canonical sale ID |
| B: void sale | PASS: 100, one sale_void movement |
| C: replay same sale processing and repeat void | PASS: no duplicate deduction or reversal |
| D: quotation only | PASS: stock unchanged |
| E: quotation conversion and retry | PASS: one sale and one deduction; repeat conversion rejected |
| Extended material cases | PASS |
| materials_100_20_transaction.sql | PASS |
| prelaunch_closing_transaction.sql | PASS |
| continuous_ledger_transaction.sql | PASS |
| ledger_rls_transaction.sql | PASS |
| operational_vat_separation_transaction.sql | PASS |
| quotation_e2e_transaction.sql | PASS |
| zatca_stage2_e2e_transaction.sql | PASS |
| zatca_stage3_security_transaction.sql | PASS |

Coverage includes cumulative ledger, notification uniqueness, RLS, month-close preservation, quotation/inventory, materials, split payments, invoice idempotency, financial snapshots, invoice_lines, PDF and QR monetary input parity, and protected invoice/security state. PDF visual output and device-to-device Realtime delivery are not established by SQL tests. The Realtime publication remains unchanged (`account_notifications`).

## Release verification

The existing full Android release workflow must pass on the resulting commit, including Deno/security, UBL/XSD, CSR, concurrency/ICV/PIH, Flutter analysis/tests, release build and `farsha-release-apk` publication. The final delivery report records the CI run, exact commit, artifact ID and independently checked APK SHA-256.

Android device/emulator runtime validation is unavailable in this workspace and must not be reported as passed. No application Dart code, existing CI workflow or protected feature implementation is changed by this patch.
