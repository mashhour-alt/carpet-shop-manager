import 'package:farsha/operational_sale_totals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('20 m² × 50 SAR is a 1,000 SAR VAT-exclusive sale', () {
    final totals = OperationalSaleTotals.calculate(
      carpetArea: 20,
      carpetUnitPrice: 50,
      paid: 1150,
    );

    expect(totals.grossAmount, 1000);
    expect(totals.taxExclusiveAmount, 1000);
    expect(totals.vatAmount, 150);
    expect(totals.payableAmount, 1150);
    expect(totals.paymentsMatch, isTrue);
  });

  test('discount is applied before VAT without changing entered unit price', () {
    final totals = OperationalSaleTotals.calculate(
      carpetArea: 20,
      carpetUnitPrice: 50,
      discount: 100,
    );

    expect(totals.grossAmount, 1000);
    expect(totals.taxExclusiveAmount, 900);
    expect(totals.vatAmount, 135);
    expect(totals.payableAmount, 1035);
  });

  test('carpet, felt, installation and delivery share one canonical total', () {
    final totals = OperationalSaleTotals.calculate(
      carpetArea: 20,
      carpetUnitPrice: 50,
      addonSales: 200 + 75 + 25,
      discount: 50,
    );

    expect(totals.grossAmount, 1300);
    expect(totals.taxExclusiveAmount, 1250);
    expect(totals.vatAmount, 187.50);
    expect(totals.payableAmount, 1437.50);
  });

  test('split payments must settle final customer payable', () {
    final totals = OperationalSaleTotals.calculate(
      carpetArea: 20,
      carpetUnitPrice: 50,
      paid: 400 + 750,
    );

    expect(totals.payableAmount, 1150);
    expect(totals.paidAmount, 1150);
    expect(totals.remainingAmount, 0);
    expect(totals.paymentsMatch, isTrue);
  });

  test('seller profit and commission exclude VAT and include discount share', () {
    final profit = sellerCarpetProfit(
      carpetArea: 20,
      saleUnitPrice: 50,
      wholesaleUnitPrice: 30,
      totalGross: 1000,
      discount: 100,
    );

    expect(profit, 300);
    expect(sellerCommission(profit, .10), 30);
  });

  test('dashboard profit uses VAT-exclusive operational revenue', () {
    final profit = operationalProfit(
      taxExclusiveSales: 1000,
      merchandiseCost: 600,
      addonCost: 50,
      driverCost: 25,
      paymentFees: 10,
    );

    expect(profit, 315);
  });
}
