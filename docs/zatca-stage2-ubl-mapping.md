# Farsha Stage 2 - ZATCA UBL mapping

Official references: ZATCA Electronic Invoice XML Implementation Standard and Electronic Invoice Data Dictionary. Security Features are intentionally not implemented in Stage 2.

| Farsha immutable snapshot | UBL 2.1 / ZATCA XML |
|---|---|
| invoice_number | cbc:ID |
| zatca_uuid | cbc:UUID |
| issued_at | cbc:IssueDate + cbc:IssueTime |
| invoice_kind simplified | cbc:InvoiceTypeCode 388, name=0200000 |
| invoice_kind tax | cbc:InvoiceTypeCode 388, name=0100000 |
| currency_code | cbc:DocumentCurrencyCode and currencyID |
| seller snapshot | cac:AccountingSupplierParty |
| buyer snapshot | cac:AccountingCustomerParty |
| line_no | cac:InvoiceLine/cbc:ID |
| quantity + unit_code | cbc:InvoicedQuantity |
| taxable_amount | InvoiceLine/cbc:LineExtensionAmount |
| line discount_amount | InvoiceLine/cac:AllowanceCharge, ChargeIndicator=false |
| description | cac:Item/cbc:Name |
| tax_category + vat_rate | cac:ClassifiedTaxCategory |
| unit_price | cac:Price/cbc:PriceAmount |
| vat_amount | cac:TaxTotal/cbc:TaxAmount |
| tax_exclusive_amount | TaxSubtotal/TaxableAmount and LegalMonetaryTotal/TaxExclusiveAmount |
| tax_inclusive_amount | LegalMonetaryTotal/TaxInclusiveAmount |
| payable_amount | LegalMonetaryTotal/PayableAmount |

## Stage 1 to UBL semantic mapping

Farsha Stage 1 line_extension_amount is the pre-discount internal gross. ZATCA/UBL LineExtensionAmount is the line net amount excluding VAT. The generator therefore maps immutable invoice_lines.taxable_amount to UBL InvoiceLine/LineExtensionAmount and does not recalculate it. This prevents double-counting discounts already allocated to invoice lines.

## Deliberately out of Stage 2

No signature, certificate, CSID, PIH, ICV, invoice hash, Reporting API, Clearance API, or production credential logic is implemented here.
