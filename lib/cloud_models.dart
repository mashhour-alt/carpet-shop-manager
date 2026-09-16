enum AccountKind { institution, driver }

enum InstitutionRole { owner, accountant, seller }

extension InstitutionRoleLabel on InstitutionRole {
  String get label => switch (this) {
        InstitutionRole.owner => 'صاحب المؤسسة',
        InstitutionRole.accountant => 'المحاسب',
        InstitutionRole.seller => 'البائع',
      };

  static InstitutionRole parse(String value) =>
      InstitutionRole.values.firstWhere((role) => role.name == value);
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.accountKind,
    required this.onboardingMode,
  });

  final String id;
  final String fullName;
  final String phone;
  final AccountKind accountKind;
  final String onboardingMode;

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        id: map['id'] as String,
        fullName: map['full_name'] as String,
        phone: map['phone'] as String,
        accountKind: AccountKind.values.firstWhere(
          (kind) => kind.name == map['account_kind'],
        ),
        onboardingMode: map['onboarding_mode'] as String,
      );
}

class InstitutionMembership {
  const InstitutionMembership({
    required this.institutionId,
    required this.institutionName,
    required this.role,
    required this.status,
  });

  final String institutionId;
  final String institutionName;
  final InstitutionRole role;
  final String status;

  factory InstitutionMembership.fromMap(Map<String, dynamic> map) {
    final institution = map['institutions'] as Map<String, dynamic>;
    return InstitutionMembership(
      institutionId: map['institution_id'] as String,
      institutionName: institution['name'] as String,
      role: InstitutionRoleLabel.parse(map['role'] as String),
      status: map['status'] as String,
    );
  }
}

class DriverTrip {
  const DriverTrip({
    required this.id,
    required this.institutionName,
    required this.sellerName,
    required this.date,
    required this.amount,
    required this.paymentStatus,
    required this.paymentMethod,
  });

  final String id;
  final String institutionName;
  final String sellerName;
  final DateTime date;
  final double amount;
  final String paymentStatus;
  final String? paymentMethod;

  factory DriverTrip.fromMap(Map<String, dynamic> map) {
    final institution = map['institutions'] as Map<String, dynamic>?;
    final seller = map['profiles'] as Map<String, dynamic>?;
    return DriverTrip(
      id: map['id'] as String,
      institutionName: institution?['name'] as String? ?? 'مؤسسة',
      sellerName: seller?['full_name'] as String? ?? 'بائع',
      date: DateTime.parse(map['trip_date'] as String),
      amount: (map['amount'] as num).toDouble(),
      paymentStatus: map['payment_status'] as String,
      paymentMethod: map['payment_method'] as String?,
    );
  }
}

class SupplierRecord {
  const SupplierRecord({required this.id, required this.name, required this.phone, required this.purchases, required this.paid});
  final String id;
  final String name;
  final String phone;
  final double purchases;
  final double paid;
  double get remaining => purchases - paid;

  factory SupplierRecord.fromMap(Map<String, dynamic> map) => SupplierRecord(
        id: map['id'] as String,
        name: map['name'] as String,
        phone: map['phone'] as String,
        purchases: (map['purchases_total'] as num).toDouble(),
        paid: (map['paid_total'] as num).toDouble(),
      );
}

class InventoryRecord {
  const InventoryRecord({required this.id, required this.name, required this.color, required this.remainingLength, required this.wholesalePrice, required this.lowStockAt});
  final String id;
  final String name;
  final String color;
  final double remainingLength;
  final double wholesalePrice;
  final double lowStockAt;
  bool get isLow => remainingLength <= lowStockAt;

  factory InventoryRecord.fromMap(Map<String, dynamic> map) => InventoryRecord(
        id: map['id'] as String,
        name: map['name'] as String,
        color: map['color'] as String,
        remainingLength: (map['remaining_length'] as num).toDouble(),
        wholesalePrice: (map['wholesale_price'] as num).toDouble(),
        lowStockAt: (map['low_stock_at'] as num).toDouble(),
      );
}

class PersonOption {
  const PersonOption({required this.id, required this.name, this.phone = ''});
  final String id;
  final String name;
  final String phone;
}

class SettlementSummary {
  const SettlementSummary({required this.salary, required this.commission, required this.withdrawals, required this.expenses, required this.deductions, required this.payments});
  final double salary;
  final double commission;
  final double withdrawals;
  final double expenses;
  final double deductions;
  final double payments;
  double get net => salary + commission - withdrawals - expenses - deductions - payments;
}
