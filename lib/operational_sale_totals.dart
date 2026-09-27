double _money(double value) => (value * 100).round() / 100;

/// Presentation-only calculator for the daily sale screen.
///
/// Persisted invoice values still come from the canonical database financial
/// snapshot. This mirrors that contract so the seller sees the correct amount
/// to collect without exposing tax implementation details in daily operations.
class OperationalSaleTotals {
  const OperationalSaleTotals({
    required this.grossAmount,
    required this.discountAmount,
    required this.taxExclusiveAmount,
    required this.vatAmount,
    required this.payableAmount,
    required this.paidAmount,
  });

  final double grossAmount;
  final double discountAmount;
  final double taxExclusiveAmount;
  final double vatAmount;
  final double payableAmount;
  final double paidAmount;

  double get remainingAmount => _money(payableAmount - paidAmount);
  bool get paymentsMatch => remainingAmount.abs() <= .009;

  factory OperationalSaleTotals.calculate({
    required double carpetArea,
    required double carpetUnitPrice,
    double addonSales = 0,
    double discount = 0,
    double paid = 0,
    double vatRate = .15,
  }) {
    final gross = _money(carpetArea * carpetUnitPrice + addonSales);
    final taxExclusive = _money(gross - discount);
    final vat = _money(taxExclusive * vatRate);
    return OperationalSaleTotals(
      grossAmount: gross,
      discountAmount: _money(discount),
      taxExclusiveAmount: taxExclusive,
      vatAmount: vat,
      payableAmount: _money(taxExclusive + vat),
      paidAmount: _money(paid),
    );
  }
}

double sellerCarpetProfit({
  required double carpetArea,
  required double saleUnitPrice,
  required double wholesaleUnitPrice,
  required double totalGross,
  double discount = 0,
}) {
  final carpetGross = _money(carpetArea * saleUnitPrice);
  final carpetDiscount = totalGross == 0
      ? 0.0
      : _money(discount * carpetGross / totalGross);
  final profit =
      carpetGross - carpetDiscount - carpetArea * wholesaleUnitPrice;
  return _money(profit < 0 ? 0.0 : profit);
}

double sellerCommission(double sellerProfit, double commissionRate) =>
    _money(sellerProfit * commissionRate);

double operationalProfit({
  required double taxExclusiveSales,
  required double merchandiseCost,
  double addonCost = 0,
  double driverCost = 0,
  double paymentFees = 0,
}) =>
    _money(
      taxExclusiveSales -
          merchandiseCost -
          addonCost -
          driverCost -
          paymentFees,
    );
