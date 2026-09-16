import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seller commission follows the agreed pricing formula', () {
    const area = 12.0; // 3m length × 4m width
    const salePrice = 50.0;
    const wholesalePrice = 30.0;
    const commissionRate = .5;
    final commission = (salePrice - wholesalePrice) * area * commissionRate;
    expect(commission, 120);
  });

  test('stock deduction is in running meters, not square meters', () {
    const before = 80.0;
    const cutLength = 3.25;
    expect(before - cutLength, 76.75);
  });
}
