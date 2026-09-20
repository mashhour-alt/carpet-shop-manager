import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_models.dart';

class FarshaRepository {
  FarshaRepository(this.client);

  final SupabaseClient client;

  String get userId => client.auth.currentUser!.id;

  Future<UserProfile> loadProfile() async {
    final row = await client.from('profiles').select().eq('id', userId).single();
    return UserProfile.fromMap(row);
  }

  Future<List<InstitutionMembership>> loadMemberships() async {
    final rows = await client
        .from('institution_memberships')
        .select('institution_id,role,status,institutions(name)')
        .eq('user_id', userId)
        .eq('status', 'active');
    return (rows as List)
        .map((row) => InstitutionMembership.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<String> createInstitution({
    required String name,
    required String commercialRegistration,
    required String taxNumber,
    required String address,
    required String phone,
    required String email,
  }) async {
    final result = await client.rpc('create_institution', params: {
      'p_name': name,
      'p_cr': commercialRegistration,
      'p_tax': taxNumber,
      'p_address': address,
      'p_phone': phone,
      'p_email': email,
    });
    return result as String;
  }

  Future<String> claimInvitation(String code) async {
    final result = await client.rpc(
      'claim_institution_invitation',
      params: {'p_code': code},
    );
    return result as String;
  }

  Future<Map<String, int>> loadInstitutionCounts(String institutionId) async {
    final suppliers = await client
        .from('suppliers')
        .select('id')
        .eq('institution_id', institutionId);
    final inventory = await client
        .from('inventory_items')
        .select('id')
        .eq('institution_id', institutionId);
    final sales = await client
        .from('sales')
        .select('id')
        .eq('institution_id', institutionId);
    return {
      'suppliers': suppliers.length,
      'inventory': inventory.length,
      'sales': sales.length,
    };
  }

  Future<List<Map<String, dynamic>>> loadMembers(String institutionId) async {
    final rows = await client
        .from('institution_memberships')
        .select('user_id,role,status,work_plan,commission_rate,monthly_salary,profiles(full_name,phone)')
        .eq('institution_id', institutionId);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> inviteMember({
    required String institutionId,
    required String phone,
    required InstitutionRole role,
    String workPlan = 'commission',
    double commissionRate = .5,
    double monthlySalary = 0,
  }) async {
    final row = await client
        .from('institution_invitations')
        .insert({
          'institution_id': institutionId,
          'phone': phone,
          'role': role.name,
          'work_plan': workPlan,
          'commission_rate': commissionRate,
          'monthly_salary': monthlySalary,
          'created_by': userId,
        })
        .select('invite_code')
        .single();
    return row['invite_code'] as String;
  }

  Future<String> connectDriver({
    required String institutionId,
    required String phone,
  }) async {
    final result = await client.rpc('connect_driver', params: {
      'p_institution_id': institutionId,
      'p_phone': phone,
    });
    return result as String;
  }

  Future<List<Map<String, dynamic>>> loadConnectedDrivers(String institutionId) async {
    final rows = await client.rpc('list_connected_drivers', params: {
      'p_institution_id': institutionId,
    });
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<DriverTrip>> loadDriverTrips() async {
    final rows = await client
        .from('driver_trips')
        .select('id,trip_date,amount,payment_status,payment_method,institutions(name),profiles!driver_trips_seller_id_fkey(full_name)')
        .eq('driver_id', userId)
        .order('trip_date', ascending: false);
    return (rows as List)
        .map((row) => DriverTrip.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<SupplierRecord>> loadSuppliers(String institutionId) async {
    final rows = await client.from('suppliers').select().eq('institution_id', institutionId).order('name');
    return (rows as List).map((row) => SupplierRecord.fromMap(row as Map<String, dynamic>)).toList();
  }

  Future<void> addSupplier(String institutionId, String name, String phone) async {
    await client.from('suppliers').insert({'institution_id': institutionId, 'name': name.trim(), 'phone': phone.trim()});
  }

  Future<void> paySupplier(String institutionId, String supplierId, double amount) async {
    await client.rpc('record_supplier_payment', params: {
      'p_institution_id': institutionId,
      'p_supplier_id': supplierId,
      'p_amount': amount,
    });
  }

  Future<List<InventoryRecord>> loadInventory(String institutionId) async {
    final rows = await client.from('inventory_items').select().eq('institution_id', institutionId).order('name');
    return (rows as List).map((row) => InventoryRecord.fromMap(row as Map<String, dynamic>)).toList();
  }

  Future<void> addInventory({required String institutionId, required String supplierId, required String name, required String color, required double length, required double supplierPrice, required double wholesalePrice, required double lowStockAt}) async {
    await client.rpc('create_inventory_item', params: {
      'p_institution_id': institutionId,
      'p_supplier_id': supplierId,
      'p_name': name.trim(),
      'p_color': color.trim(),
      'p_length': length,
      'p_supplier_price': supplierPrice,
      'p_wholesale_price': wholesalePrice,
      'p_low_stock_at': lowStockAt,
    });
  }

  Future<List<PersonOption>> loadSellers(String institutionId) async {
    final rows = await client.from('institution_memberships').select('user_id,profiles(full_name,phone)').eq('institution_id', institutionId).eq('role', 'seller').eq('status', 'active');
    return (rows as List).map((row) {
      final profile = row['profiles'] as Map<String, dynamic>;
      return PersonOption(id: row['user_id'] as String, name: profile['full_name'] as String, phone: profile['phone'] as String);
    }).toList();
  }

  Future<List<PersonOption>> loadDriverOptions(String institutionId) async {
    final rows = await loadConnectedDrivers(institutionId);
    return rows.where((row) => row['connection_status'] == 'active' && row['is_available'] == true).map((row) => PersonOption(id: row['driver_id'] as String, name: row['full_name'] as String, phone: row['phone'] as String)).toList();
  }

  Future<void> recordSale({required String institutionId, required String inventoryId, required String sellerId, String? driverId, required String customerName, required double length, required double salePrice, required double installation, String? glueSupplierId, required double glueGallons, required double glueAmount, String? ironSupplierId, required double ironPieces, required double ironAmount, required double driverFee, required String paymentMethod}) async {
    await client.rpc('record_sale', params: {
      'p_institution_id': institutionId,
      'p_inventory_id': inventoryId,
      'p_seller_id': sellerId,
      'p_driver_id': driverId,
      'p_customer_name': customerName.trim(),
      'p_length': length,
      'p_sale_price': salePrice,
      'p_installation': installation,
      'p_glue_supplier_id': glueSupplierId,
      'p_glue_gallons': glueGallons,
      'p_glue_amount': glueAmount,
      'p_iron_supplier_id': ironSupplierId,
      'p_iron_pieces': ironPieces,
      'p_iron_amount': ironAmount,
      'p_driver_fee': driverFee,
      'p_customer_payment': paymentMethod,
    });
  }

  Future<SettlementSummary> loadSettlement(String institutionId, String sellerId, DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final membership = await client.from('institution_memberships').select('work_plan,monthly_salary').eq('institution_id', institutionId).eq('user_id', sellerId).single();
    final sales = await client.from('sales').select('seller_commission').eq('institution_id', institutionId).eq('seller_id', sellerId).gte('created_at', start.toIso8601String()).lt('created_at', end.toIso8601String());
    final ledger = await client.from('seller_ledger').select('kind,amount').eq('institution_id', institutionId).eq('seller_id', sellerId).gte('entry_date', start.toIso8601String().split('T').first).lt('entry_date', end.toIso8601String().split('T').first);
    final commission = (sales as List).fold<double>(0, (sum, row) => sum + (row['seller_commission'] as num).toDouble());
    final totals = <String, double>{};
    for (final row in ledger as List) {
      totals.update(row['kind'] as String, (value) => value + (row['amount'] as num).toDouble(), ifAbsent: () => (row['amount'] as num).toDouble());
    }
    final plan = membership['work_plan'] as String;
    final salary = plan == 'salary' || plan == 'salary_and_commission' ? (membership['monthly_salary'] as num).toDouble() : 0.0;
    return SettlementSummary(salary: salary, commission: plan == 'salary' ? 0 : commission, withdrawals: totals['withdrawal'] ?? 0, expenses: totals['expense'] ?? 0, deductions: totals['deduction'] ?? 0, payments: totals['payment'] ?? 0);
  }

  Future<void> addSellerLedger({required String institutionId, required String sellerId, required String kind, required double amount, String note = ''}) async {
    await client.from('seller_ledger').insert({'institution_id': institutionId, 'seller_id': sellerId, 'kind': kind, 'amount': amount, 'note': note, 'created_by': userId});
  }

  Future<InstitutionSettings> loadInstitutionSettings(String institutionId) async {
    final row = await client.from('institutions').select('visa_fee_rate,tabby_fee_rate,tamara_fee_rate').eq('id', institutionId).single();
    return InstitutionSettings.fromMap(row);
  }

  Future<void> updateInstitutionFees(String institutionId, double visa, double tabby, double tamara) async {
    await client.from('institutions').update({
      'visa_fee_rate': visa / 100,
      'tabby_fee_rate': tabby / 100,
      'tamara_fee_rate': tamara / 100,
    }).eq('id', institutionId);
  }

  Future<void> updateSellerTerms({required String institutionId, required String sellerId, required String workPlan, required double commissionPercent, required double monthlySalary}) async {
    await client.from('institution_memberships').update({
      'work_plan': workPlan,
      'commission_rate': commissionPercent / 100,
      'monthly_salary': monthlySalary,
    }).eq('institution_id', institutionId).eq('user_id', sellerId).eq('role', 'seller');
  }

  Future<List<InstitutionTrip>> loadInstitutionTrips(String institutionId) async {
    final rows = await client.from('driver_trips').select('id,trip_date,amount,payment_status,payment_method,driver:driver_profiles!driver_trips_driver_id_fkey(profiles(full_name)),seller:profiles!driver_trips_seller_id_fkey(full_name)').eq('institution_id', institutionId).order('trip_date', ascending: false);
    return (rows as List).map((row) {
      final driverAccount = row['driver'] as Map<String, dynamic>?;
      final driver = driverAccount?['profiles'] as Map<String, dynamic>?;
      final seller = row['seller'] as Map<String, dynamic>?;
      return InstitutionTrip(
        id: row['id'] as String,
        driverName: driver?['full_name'] as String? ?? 'سائق',
        sellerName: seller?['full_name'] as String? ?? 'بائع',
        date: DateTime.parse(row['trip_date'] as String),
        amount: (row['amount'] as num).toDouble(),
        isPaid: row['payment_status'] == 'paid',
        paymentMethod: row['payment_method'] as String?,
      );
    }).toList();
  }

  Future<void> payDriverTrip(String tripId, String method) async {
    await client.rpc('pay_driver_trip', params: {'p_trip_id': tripId, 'p_method': method});
  }

  Future<InstitutionDocumentDetails> loadInstitutionDocumentDetails(String institutionId) async {
    final row = await client
        .from('institutions')
        .select('name,commercial_registration,tax_number,address,phone,email')
        .eq('id', institutionId)
        .single();
    return InstitutionDocumentDetails.fromMap(row);
  }

  Future<List<QuotationRecord>> loadQuotations(String institutionId) async {
    final rows = await client
        .from('quotations')
        .select('id,customer_name,customer_commercial_registration,customer_tax_number,issue_date,valid_until,notes,subtotal,vat_amount,total,status,quotation_items(inventory_id,item_name,color,length,width,area,price_per_sqm,line_total)')
        .eq('institution_id', institutionId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => QuotationRecord.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<String> createQuotation({
    required String institutionId,
    required String sellerId,
    required String inventoryId,
    required String customerName,
    required String customerCommercialRegistration,
    required String customerTaxNumber,
    required double length,
    required double pricePerSquareMeter,
    required DateTime validUntil,
    String notes = '',
  }) async {
    final result = await client.rpc('create_quotation', params: {
      'p_institution_id': institutionId,
      'p_seller_id': sellerId,
      'p_inventory_id': inventoryId,
      'p_customer_name': customerName.trim(),
      'p_customer_cr': customerCommercialRegistration.trim(),
      'p_customer_tax': customerTaxNumber.trim(),
      'p_length': length,
      'p_price_per_sqm': pricePerSquareMeter,
      'p_valid_until': validUntil.toIso8601String().split('T').first,
      'p_notes': notes.trim(),
    });
    return result as String;
  }

  Future<void> convertQuotationToSale(String quotationId, String paymentMethod) async {
    await client.rpc('convert_quotation_to_sale', params: {
      'p_quotation_id': quotationId,
      'p_payment_method': paymentMethod,
    });
  }

  Future<List<SaleInvoiceCandidate>> loadSalesForInvoicing(String institutionId) async {
    final rows = await client
        .from('sales')
        .select('id,customer_name,total,created_at,inventory_items(name,color),invoices(id)')
        .eq('institution_id', institutionId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => SaleInvoiceCandidate.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<String> issueTaxInvoice({
    required String saleId,
    required String customerName,
    required String customerCommercialRegistration,
    required String customerTaxNumber,
    required String customerAddress,
    required String invoiceKind,
    required double discountAmount,
  }) async {
    final result = await client.rpc('issue_tax_invoice', params: {
      'p_sale_id': saleId,
      'p_customer_name': customerName.trim(),
      'p_customer_cr': customerCommercialRegistration.trim(),
      'p_customer_tax': customerTaxNumber.trim(),
      'p_customer_address': customerAddress.trim(),
      'p_invoice_kind': invoiceKind,
      'p_discount': discountAmount,
    });
    return result as String;
  }

  Future<List<TaxInvoiceRecord>> loadTaxInvoices(String institutionId) async {
    final rows = await client
        .from('invoices')
        .select('id,invoice_number,invoice_kind,seller_name,customer_name,customer_commercial_registration,customer_tax_number,customer_address,item_name,color,length,width,area,price_per_sqm,carpet_amount,installation_amount,glue_gallons,glue_amount,iron_pieces,iron_amount,driver_fee,payment_method,subtotal,discount_amount,taxable_amount,vat_amount,total_with_vat,issued_at')
        .eq('institution_id', institutionId)
        .order('issued_at', ascending: false);
    return (rows as List)
        .map((row) => TaxInvoiceRecord.fromMap(row as Map<String, dynamic>))
        .toList();
  }
}
