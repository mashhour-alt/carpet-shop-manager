# Farsha Stage 2 — ZATCA UBL mapping

Scope: UBL XML generation only. No signing, certificates, CSID, PIH/hash chain, reporting or clearance.

Official references reviewed:
- ZATCA Electronic Invoice Data Dictionary — 19 May 2023.
- ZATCA Electronic Invoice XML Implementation Standard — 19 May 2023.
- OASIS UBL 2.1 normative Invoice XSD.

Core mapping:
| Farsha immutable snapshot | UBL 2.1 |
|---|---|
| invoice_number | cbc:ID |
| zatca_uuid | cbc:UUID |
| issued_at | cbc:IssueDate + cbc:IssueTime |
| invoice_kind simplified | cbc:InvoiceTypeCode 388, name 0200000 |
| invoice_kind tax | cbc:InvoiceTypeCode 388, name 0100000 |
| currency_code | cbc:DocumentCurrencyCode |
| seller snapshots | cac:AccountingSupplierParty |
| buyer snapshots | cac:AccountingCustomerParty |
| invoice_lines.line_no | cac:InvoiceLine/cbc:ID |
| quantity + unit_code | cbc:InvoicedQuantity |
| taxable_amount | InvoiceLine/cbc:LineExtensionAmount |
| discount_amount | InvoiceLine/cac:AllowanceCharge |
| description | cac:Item/cbc:Name |
| tax_category + vat_rate | cac:ClassifiedTaxCategory |
| unit_price | cac:Price/cbc:PriceAmount |
| vat_amount | cac:TaxTotal/cbc:TaxAmount |
| tax_exclusive_amount | cac:LegalMonetaryTotal/cbc:LineExtensionAmount and cbc:TaxExclusiveAmount |
| tax_inclusive_amount | cac:LegalMonetaryTotal/cbc:TaxInclusiveAmount |
| payable_amount | cac:LegalMonetaryTotal/cbc:PayableAmount |

Farsha Stage-1 line_extension_amount is the pre-discount gross control total. UBL InvoiceLine/LegalMonetaryTotal LineExtensionAmount is mapped from the immutable net taxable line amounts; the Farsha gross remains a parity guard and is not reinterpreted or modified.

Structured seller address is mandatory for generator input. Standard invoices additionally require structured buyer address snapshots. Missing required data blocks generation; values are never fabricated.

Deferred to Stage 3+ where required by ZATCA security/integration rules: ICV, PIH, invoice hash, cryptographic signature, certificate/CSID material, QR cryptographic tags, Reporting/Clearance.
