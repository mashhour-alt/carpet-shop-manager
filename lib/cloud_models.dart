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

class InstitutionSettings {
  const InstitutionSettings({required this.visaFeePercent, required this.tabbyFeePercent, required this.tamaraFeePercent});
  final double visaFeePercent;
  final double tabbyFeePercent;
  final double tamaraFeePercent;

  factory InstitutionSettings.fromMap(Map<String, dynamic> map) => InstitutionSettings(
        visaFeePercent: (map['visa_fee_rate'] as num).toDouble() * 100,
        tabbyFeePercent: (map['tabby_fee_rate'] as num).toDouble() * 100,
        tamaraFeePercent: (map['tamara_fee_rate'] as num).toDouble() * 100,
      );
}

class InstitutionTrip {
  const InstitutionTrip({required this.id, required this.driverName, required this.sellerName, required this.date, required this.amount, required this.isPaid, this.paymentMethod});
  final String id;
  final String driverName;
  final String sellerName;
  final DateTime date;
  final double amount;
  final bool isPaid;
  final String? paymentMethod;
}

class InstitutionDocumentDetails {
  const InstitutionDocumentDetails({
    required this.name,
    required this.commercialRegistration,
    required this.taxNumber,
    required this.address,
    required this.phone,
    required this.email,
  });

  final String name;
  final String commercialRegistration;
  final String taxNumber;
  final String address;
  final String phone;
  final String email;

  factory InstitutionDocumentDetails.fromMap(Map<String, dynamic> map) => InstitutionDocumentDetails(
        name: map['name'] as String,
        commercialRegistration: map['commercial_registration'] as String,
        taxNumber: map['tax_number'] as String,
        address: map['address'] as String,
        phone: map['phone'] as String,
        email: map['email'] as String,
      );
}

class QuotationItemRecord {
  const QuotationItemRecord({
    required this.inventoryId,
    required this.name,
    required this.color,
    required this.length,
    required this.width,
    required this.area,
    required this.pricePerSquareMeter,
    required this.lineTotal,
  });

  final String inventoryId;
  final String name;
  final String color;
  final double length;
  final double width;
  final double area;
  final double pricePerSquareMeter;
  final double lineTotal;

  factory QuotationItemRecord.fromMap(Map<String, dynamic> map) => QuotationItemRecord(
        inventoryId: map['inventory_id'] as String,
        name: map['item_name'] as String,
        color: map['color'] as String,
        length: (map['length'] as num).toDouble(),
        width: (map['width'] as num).toDouble(),
        area: (map['area'] as num).toDouble(),
        pricePerSquareMeter: (map['price_per_sqm'] as num).toDouble(),
        lineTotal: (map['line_total'] as num).toDouble(),
      );
}

class QuotationRecord {
  const QuotationRecord({
    required this.id,
    required this.customerName,
    required this.customerCommercialRegistration,
    required this.customerTaxNumber,
    required this.issueDate,
    required this.validUntil,
    required this.notes,
    required this.subtotal,
    required this.vatAmount,
    required this.total,
    required this.status,
    required this.items,
  });

  final String id;
  final String customerName;
  final String customerCommercialRegistration;
  final String customerTaxNumber;
  final DateTime issueDate;
  final DateTime validUntil;
  final String notes;
  final double subtotal;
  final double vatAmount;
  final double total;
  final String status;
  final List<QuotationItemRecord> items;

  factory QuotationRecord.fromMap(Map<String, dynamic> map) => QuotationRecord(
        id: map['id'] as String,
        customerName: map['customer_name'] as String,
        customerCommercialRegistration: map['customer_commercial_registration'] as String,
        customerTaxNumber: map['customer_tax_number'] as String,
        issueDate: DateTime.parse(map['issue_date'] as String),
        validUntil: DateTime.parse(map['valid_until'] as String),
        notes: map['notes'] as String,
        subtotal: (map['subtotal'] as num).toDouble(),
        vatAmount: (map['vat_amount'] as num).toDouble(),
        total: (map['total'] as num).toDouble(),
        status: map['status'] as String,
        items: (map['quotation_items'] as List)
            .map((item) => QuotationItemRecord.fromMap(item as Map<String, dynamic>))
            .toList(),
      );
}

class SaleInvoiceCandidate {
  const SaleInvoiceCandidate({
    required this.id,
    required this.customerName,
    required this.itemName,
    required this.color,
    required this.createdAt,
    required this.total,
    this.invoiceId,
  });

  final String id;
  final String customerName;
  final String itemName;
  final String color;
  final DateTime createdAt;
  final double total;
  final String? invoiceId;
  bool get hasInvoice => invoiceId != null;

  factory SaleInvoiceCandidate.fromMap(Map<String, dynamic> map) {
    final item = map['inventory_items'] as Map<String, dynamic>;
    final invoiceRelation = map['invoices'];
    String? invoiceId;
    if (invoiceRelation is Map<String, dynamic>) {
      invoiceId = invoiceRelation['id'] as String?;
    } else if (invoiceRelation is List && invoiceRelation.isNotEmpty) {
      invoiceId = (invoiceRelation.first as Map<String, dynamic>)['id'] as String?;
    }
    return SaleInvoiceCandidate(
      id: map['id'] as String,
      customerName: map['customer_name'] as String,
      itemName: item['name'] as String,
      color: item['color'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      total: (map['total'] as num).toDouble(),
      invoiceId: invoiceId,
    );
  }
}

class TaxInvoiceRecord {
  const TaxInvoiceRecord({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceKind,
    required this.sellerName,
    required this.customerName,
    required this.customerCommercialRegistration,
    required this.customerTaxNumber,
    required this.customerAddress,
    required this.itemName,
    required this.color,
    required this.length,
    required this.width,
    required this.area,
    required this.pricePerSquareMeter,
    required this.carpetAmount,
    required this.installationAmount,
    required this.glueGallons,
    required this.glueAmount,
    required this.ironPieces,
    required this.ironAmount,
    required this.driverFee,
    required this.paymentMethod,
    required this.paymentSummary,
    required this.addonsSummary,
    required this.addonsAmount,
    required this.subtotal,
    required this.discountAmount,
    required this.taxableAmount,
    required this.vatAmount,
    required this.totalWithVat,
    required this.issuedAt,
  });

  final String id;
  final int invoiceNumber;
  final String invoiceKind;
  final String sellerName;
  final String customerName;
  final String customerCommercialRegistration;
  final String customerTaxNumber;
  final String customerAddress;
  final String itemName;
  final String color;
  final double length;
  final double width;
  final double area;
  final double pricePerSquareMeter;
  final double carpetAmount;
  final double installationAmount;
  final double glueGallons;
  final double glueAmount;
  final double ironPieces;
  final double ironAmount;
  final double driverFee;
  final String paymentMethod;
  final String paymentSummary;
  final String addonsSummary;
  final double addonsAmount;
  final double subtotal;
  final double discountAmount;
  final double taxableAmount;
  final double vatAmount;
  final double totalWithVat;
  final DateTime issuedAt;

  factory TaxInvoiceRecord.fromMap(Map<String, dynamic> map) => TaxInvoiceRecord(
        id: map['id'] as String,
        invoiceNumber: (map['invoice_number'] as num).toInt(),
        invoiceKind: map['invoice_kind'] as String,
        sellerName: map['seller_name'] as String,
        customerName: map['customer_name'] as String,
        customerCommercialRegistration: map['customer_commercial_registration'] as String,
        customerTaxNumber: map['customer_tax_number'] as String,
        customerAddress: map['customer_address'] as String,
        itemName: map['item_name'] as String,
        color: map['color'] as String,
        length: (map['length'] as num).toDouble(),
        width: (map['width'] as num).toDouble(),
        area: (map['area'] as num).toDouble(),
        pricePerSquareMeter: (map['price_per_sqm'] as num).toDouble(),
        carpetAmount: (map['carpet_amount'] as num).toDouble(),
        installationAmount: (map['installation_amount'] as num).toDouble(),
        glueGallons: (map['glue_gallons'] as num).toDouble(),
        glueAmount: (map['glue_amount'] as num).toDouble(),
        ironPieces: (map['iron_pieces'] as num).toDouble(),
        ironAmount: (map['iron_amount'] as num).toDouble(),
        driverFee: (map['driver_fee'] as num).toDouble(),
        paymentMethod: map['payment_method'] as String,
        paymentSummary: map['payment_summary'] as String? ?? '',
        addonsSummary: map['addons_summary'] as String? ?? '',
        addonsAmount: (map['addons_amount'] as num?)?.toDouble() ?? 0,
        subtotal: (map['subtotal'] as num).toDouble(),
        discountAmount: (map['discount_amount'] as num).toDouble(),
        taxableAmount: (map['taxable_amount'] as num).toDouble(),
        vatAmount: (map['vat_amount'] as num).toDouble(),
        totalWithVat: (map['total_with_vat'] as num).toDouble(),
        issuedAt: DateTime.parse(map['issued_at'] as String),
      );
}

class AddonTypeRecord {
  const AddonTypeRecord({required this.id, required this.name, required this.unit, required this.defaultSalePrice, required this.defaultCostPrice});
  final String id; final String name; final String unit; final double defaultSalePrice; final double defaultCostPrice;
  factory AddonTypeRecord.fromMap(Map<String,dynamic> m)=>AddonTypeRecord(
    id:m['id'] as String,name:m['name'] as String,unit:m['unit'] as String,
    defaultSalePrice:(m['default_sale_price'] as num).toDouble(),defaultCostPrice:(m['default_cost_price'] as num).toDouble());
}

class SalePaymentInput {
  const SalePaymentInput({required this.method,required this.amount,this.reference=''});
  final String method; final double amount; final String reference;
  Map<String,dynamic> toMap()=>{'method':method,'amount':amount,'reference':reference};
}

class SaleAddonInput {
  const SaleAddonInput({required this.addonTypeId,required this.name,required this.unit,required this.quantity,required this.saleUnitPrice,required this.costUnitPrice,this.supplierId});
  final String? addonTypeId; final String name; final String unit; final double quantity; final double saleUnitPrice; final double costUnitPrice; final String? supplierId;
  Map<String,dynamic> toMap()=>{'addon_type_id':addonTypeId,'name':name,'unit':unit,'quantity':quantity,'sale_unit_price':saleUnitPrice,'cost_unit_price':costUnitPrice,'supplier_id':supplierId};
  double get saleTotal=>quantity*saleUnitPrice;
}

class OperatingSummary {
  const OperatingSummary({required this.salesAmount,required this.totalLength,required this.totalArea,required this.saleCount,required this.merchandiseCost,required this.addonCost,required this.driverCost,required this.paymentFees,required this.grossProfit,required this.payments});
  final double salesAmount,totalLength,totalArea,merchandiseCost,addonCost,driverCost,paymentFees,grossProfit; final int saleCount; final Map<String,double> payments;
  factory OperatingSummary.fromMap(Map<String,dynamic> m)=>OperatingSummary(
    salesAmount:(m['sales_amount'] as num).toDouble(),totalLength:(m['total_length'] as num).toDouble(),totalArea:(m['total_area'] as num).toDouble(),saleCount:(m['sale_count'] as num).toInt(),
    merchandiseCost:(m['merchandise_cost'] as num).toDouble(),addonCost:(m['addon_cost'] as num).toDouble(),driverCost:(m['driver_cost'] as num).toDouble(),paymentFees:(m['payment_fees'] as num).toDouble(),grossProfit:(m['gross_profit'] as num).toDouble(),
    payments:{for(final k in ['cash','network','bank_transfer','visa','tamara','tabby','other']) k:(m[k] as num).toDouble()});
}

class OperatingSaleRecord {
  const OperatingSaleRecord({required this.id,required this.createdAt,required this.length,required this.area,required this.itemName,required this.color,required this.addons,required this.payments,required this.salesAmount,required this.sellerName,required this.driverName,required this.driverCost,required this.merchandiseCost,required this.addonCost,required this.paymentFees,required this.totalCost,required this.grossProfit,required this.notes,required this.status});
  final String id,itemName,color,addons,payments,sellerName,driverName,notes,status; final DateTime createdAt; final double length,area,salesAmount,driverCost,merchandiseCost,addonCost,paymentFees,totalCost,grossProfit;
  factory OperatingSaleRecord.fromMap(Map<String,dynamic> m)=>OperatingSaleRecord(
    id:m['sale_id'] as String,createdAt:DateTime.parse(m['created_at'] as String),length:(m['length'] as num).toDouble(),area:(m['area'] as num).toDouble(),itemName:m['item_name'] as String,color:m['color'] as String,addons:m['addons'] as String,payments:m['payments'] as String,salesAmount:(m['sales_amount'] as num).toDouble(),sellerName:m['seller_name'] as String,driverName:m['driver_name'] as String,driverCost:(m['driver_cost'] as num).toDouble(),merchandiseCost:(m['merchandise_cost'] as num).toDouble(),addonCost:(m['addon_cost'] as num).toDouble(),paymentFees:(m['payment_fees'] as num).toDouble(),totalCost:(m['total_cost'] as num).toDouble(),grossProfit:(m['gross_profit'] as num).toDouble(),notes:m['notes'] as String,status:m['status'] as String);
}


class SellerPerformanceRecord {
  const SellerPerformanceRecord({required this.saleCount,required this.totalLength,required this.totalArea,required this.salesAmount,required this.merchandiseCost,required this.grossProfit,required this.commission,required this.ledgerDeductions,required this.netDue});
  final int saleCount; final double totalLength,totalArea,salesAmount,commission,ledgerDeductions,netDue; final double? merchandiseCost,grossProfit;
  factory SellerPerformanceRecord.fromMap(Map<String,dynamic> m)=>SellerPerformanceRecord(saleCount:(m['sale_count'] as num).toInt(),totalLength:(m['total_length'] as num).toDouble(),totalArea:(m['total_area'] as num).toDouble(),salesAmount:(m['sales_amount'] as num).toDouble(),merchandiseCost:(m['merchandise_cost'] as num?)?.toDouble(),grossProfit:(m['gross_profit'] as num?)?.toDouble(),commission:(m['commission'] as num).toDouble(),ledgerDeductions:(m['ledger_deductions'] as num).toDouble(),netDue:(m['net_due'] as num).toDouble());
}
