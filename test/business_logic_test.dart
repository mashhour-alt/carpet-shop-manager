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

  test('payment provider fee uses the institution percentage', () {
    const saleTotal = 2400.0;
    const visaRate = 0.025;
    expect(saleTotal * visaRate, 60);
  });

  test('monthly settlement subtracts withdrawals and payments', () {
    const salary = 2000.0;
    const commissions = 850.0;
    const withdrawals = 300.0;
    const deductions = 50.0;
    const payments = 1000.0;
    expect(salary + commissions - withdrawals - deductions - payments, 1500);
  });
}
