# Excel operating-cycle gap analysis

Source reviewed: the April daily-operations workbook supplied by the user (30 daily sheets + monthly total) and the current Flutter/Supabase codebase.

## What the workbook actually models

Each daily sheet uses the same operational columns:

- running length (المقاس)
- square metres (متر2 = length × 4)
- carpet/item
- additions
- cash
- network
- Tamara
- additional cost/iron
- sales total
- seller
- net result
- driver
- driver amount
- capital cost per m²
- total cost/result input
- notes

The workbook contains 112 real sale rows. Split payment is a real workflow: 26 rows use more than one payment method. The monthly total sheet aggregates length, m², sales, profit/loss, cash, network, Tamara, and driver totals.

## Gap analysis

### Already implemented

- institution accounts and multi-tenant Supabase model
- owner / accountant / seller / independent driver roles
- RLS-backed membership model
- inventory tracked by running metres with fixed 4m width
- supplier cost and seller wholesale price
- automatic stock deduction on sale
- seller commission / salary / monthly settlement
- driver trip ledger and cash/bank-transfer settlement
- suppliers
- quotations
- Saudi tax invoice and QR workflow

### Implemented but needs extension

- sales currently keep one customer payment method; must support payment rows
- sale cost/profit exists partly through wholesale/seller commission, but operating cost is not exposed as a single auditable calculation
- installation/glue/iron are fixed fields; additions must become configurable line items
- dashboard is count-based, not daily operational
- supplier balance exists, but detailed deliveries and delivery items are missing
- seller settlement exists but seller performance report is incomplete
- driver ledger exists but lacks unified date-filtered reporting
- invoices snapshot one payment method and need a non-destructive split-payment summary

### Missing

- split payment table with amount/date/reference/fee snapshot
- configurable add-on catalog and sale add-on lines
- sale notes with search
- sale status / void / return audit trail
- inventory movement ledger for sale/reversal/purchase/adjustment
- daily sales ledger
- unified date filter
- payment-method report
- seller performance report
- driver performance report
- monthly operating report + PDF/XLSX export
- supplier delivery ledger
- dashboard KPIs derived from the same report source

## Database approach

Do not replace existing tables. Add backward-compatible tables and snapshots:

- sale_payments
- addon_types
- sale_addons
- inventory_movements
- supplier_deliveries
- supplier_delivery_items

Extend sales with notes/status/cost snapshot and void metadata. Backfill existing sales with one payment row based on the legacy payment method.

All new rows include institution_id and RLS. Reporting is exposed through guarded RPCs so seller reports are automatically restricted to the signed-in seller and institution financial cost fields remain unavailable to sellers.

## Calculation source of truth

- length and area come from sales (area = length × 4)
- merchandise cost = area × supplier unit-cost snapshot
- add-on sales/cost come from sale_addons
- driver cost = driver trip/sale driver fee
- payment fees = sum(sale_payments.fee_amount)
- paid amount = sum(sale_payments.amount)
- sales amount = the sale total
- gross operating profit = sales amount - merchandise cost - add-on cost - driver cost - payment fees
- seller commission remains the existing commission calculation and is never mixed with institution operating profit

Dashboards and detail reports use the same RPC/source so totals must reconcile exactly.
