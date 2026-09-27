import 'package:farsha/cloud_models.dart';
import 'package:farsha/operational_sale_totals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quotation uses a VAT-exclusive entered carpet price', () {
    final totals = OperationalSaleTotals.calculate(
      carpetArea: 20,
      carpetUnitPrice: 50,
    );

    expect(totals.taxExclusiveAmount, 1000);
    expect(totals.vatAmount, 150);
    expect(totals.payableAmount, 1150);
  });

  test('quotation add-ons and discount use the same final payable rule as sale', () {
    final totals = OperationalSaleTotals.calculate(
      carpetArea: 20,
      carpetUnitPrice: 50,
      addonSales: 100 + 75 + 25,
      discount: 50,
    );

    expect(totals.grossAmount, 1200);
    expect(totals.taxExclusiveAmount, 1150);
    expect(totals.vatAmount, 172.5);
    expect(totals.payableAmount, 1322.5);
  });

  test('saved quotation reopens with header item, add-on, and discount snapshots', () {
    final quote = QuotationRecord.fromMap({
      'id': '00000000-0000-0000-0000-000000000001',
      'customer_name': 'Test customer',
      'customer_commercial_registration': '',
      'customer_tax_number': '',
      'issue_date': '2026-09-27',
      'valid_until': '2026-10-11',
      'notes': 'Test note',
      'subtotal': 1150,
      'discount_amount': 50,
      'vat_amount': 172.5,
      'total': 1322.5,
      'status': 'draft',
      'addons': [
        {
          'addon_type_id': '00000000-0000-0000-0000-000000000002',
          'name': 'Installation',
          'unit': 'job',
          'quantity': 1,
          'sale_unit_price': 100,
          'cost_unit_price': 40,
          'supplier_id': null,
        },
      ],
      'quotation_items': [
        {
          'inventory_id': '00000000-0000-0000-0000-000000000003',
          'item_name': 'Carpet',
          'color': 'Blue',
          'length': 5,
          'width': 4,
          'area': 20,
          'price_per_sqm': 50,
          'line_total': 1000,
        },
      ],
    });

    expect(quote.items.single.lineTotal, 1000);
    expect(quote.addons.single.saleTotal, 100);
    expect(quote.discountAmount, 50);
    expect(quote.total, 1322.5);
  });
}
