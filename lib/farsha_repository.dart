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

  Future<void> updateSupplierCategories(String institutionId,String supplierId,List<String> categories) async => client.rpc('update_supplier_categories',params:{'p_institution_id':institutionId,'p_supplier_id':supplierId,'p_categories':categories});
  Future<void> recordSupplierAccountEntry({required String institutionId,required String supplierId,required String type,required double amount,String method='',String reference='',String note='',String? branchId}) async => client.rpc('record_supplier_account_entry',params:{'p_institution_id':institutionId,'p_supplier_id':supplierId,'p_entry_type':type,'p_amount':amount,'p_payment_method':method,'p_reference':reference,'p_note':note,'p_branch_id':branchId});
  Future<void> recordDriverAccountEntry({required String institutionId,required String driverId,required String type,required double amount,String method='cash',String reference='',String note='',String? branchId}) async => client.rpc('record_driver_account_entry',params:{'p_institution_id':institutionId,'p_driver_id':driverId,'p_entry_type':type,'p_amount':amount,'p_payment_method':method,'p_reference':reference,'p_note':note,'p_branch_id':branchId});
  Future<List<AccountSummaryRecord>> loadAccountSummaries(String institutionId,String party,DateTime from,DateTime to) async {final rows=await client.rpc('account_summaries',params:{'p_institution_id':institutionId,'p_party':party,'p_from':from.toIso8601String(),'p_to':to.toIso8601String()});return (rows as List).map((e)=>AccountSummaryRecord.fromMap(e as Map<String,dynamic>)).toList();}
  Future<List<AccountMovementRecord>> loadAccountStatement(String institutionId,String party,String partyId,DateTime from,DateTime to) async {final fn=switch(party){'seller'=>'seller_account_statement','driver'=>'driver_account_statement',_=>'supplier_account_statement'};final key=switch(party){'seller'=>'p_seller_id','driver'=>'p_driver_id',_=>'p_supplier_id'};final rows=await client.rpc(fn,params:{'p_institution_id':institutionId,key:partyId,'p_from':from.toIso8601String(),'p_to':to.toIso8601String()});return (rows as List).map((e)=>AccountMovementRecord.fromMap(e as Map<String,dynamic>)).toList();}
  Future<void> saveAddonTypeV2({required String institutionId,required String name,required String unit,required double salePrice,required double costPrice,String? supplierId,required String behavior,required String calculationBasis,required bool trackStock,required double openingStock,required double lowStockAt,required bool customerVisible,required bool chargeToSeller}) async => client.rpc('save_addon_type_v2',params:{'p_institution_id':institutionId,'p_name':name,'p_unit':unit,'p_sale_price':salePrice,'p_cost_price':costPrice,'p_supplier_id':supplierId,'p_behavior':behavior,'p_calculation_basis':calculationBasis,'p_track_stock':trackStock,'p_opening_stock':openingStock,'p_low_stock_at':lowStockAt,'p_customer_visible':customerVisible,'p_charge_to_seller':chargeToSeller});
  Future<void> receiveAddonStock(String institutionId,String addonId,double quantity,double cost,String note) async => client.rpc('receive_addon_stock',params:{'p_institution_id':institutionId,'p_addon_type_id':addonId,'p_quantity':quantity,'p_unit_cost':cost,'p_note':note});
  Future<void> issueInternalAddon(String institutionId,String addonId,String sellerId,double quantity,String note) async => client.rpc('issue_internal_addon',params:{'p_institution_id':institutionId,'p_addon_type_id':addonId,'p_seller_id':sellerId,'p_quantity':quantity,'p_sale_id':null,'p_note':note});

  Future<List<InventoryRecord>> loadInventory(String institutionId) async {
    final rows = await client.from('inventory_items').select('*,branches(name)').eq('institution_id', institutionId).order('name');
    return (rows as List).map((row) => InventoryRecord.fromMap(row as Map<String, dynamic>)).toList();
  }

  Future<void> addInventory({required String institutionId, required String supplierId, required String name, required String color, required double length, required double supplierPrice, required double wholesalePrice, required double lowStockAt, String? branchId}) async {
    await client.rpc('create_inventory_item', params: {
      'p_institution_id': institutionId,
      'p_supplier_id': supplierId,
      'p_name': name.trim(),
      'p_color': color.trim(),
      'p_length': length,
      'p_supplier_price': supplierPrice,
      'p_wholesale_price': wholesalePrice,
      'p_low_stock_at': lowStockAt,
      'p_branch_id': branchId,
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
        .select('id,invoice_number,invoice_kind,seller_name,customer_name,customer_commercial_registration,customer_tax_number,customer_address,item_name,color,length,width,area,price_per_sqm,carpet_amount,installation_amount,glue_gallons,glue_amount,iron_pieces,iron_amount,driver_fee,payment_method,payment_summary,addons_summary,addons_amount,subtotal,discount_amount,taxable_amount,vat_amount,total_with_vat,issued_at')
        .eq('institution_id', institutionId)
        .order('issued_at', ascending: false);
    return (rows as List)
        .map((row) => TaxInvoiceRecord.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<AddonTypeRecord>> loadAddonTypes(String institutionId) async {
    final rows=await client.from('addon_types').select().eq('institution_id',institutionId).eq('is_active',true).order('name');
    return (rows as List).map((e)=>AddonTypeRecord.fromMap(e as Map<String,dynamic>)).toList();
  }

  Future<String> recordSaleV2({required String institutionId,required String inventoryId,required String sellerId,String? driverId,required String customerName,required double length,required double salePrice,required double driverFee,required String notes,required List<SalePaymentInput> payments,required List<SaleAddonInput> addons}) async {
    final result=await client.rpc('record_sale_v2',params:{
      'p_institution_id':institutionId,'p_inventory_id':inventoryId,'p_seller_id':sellerId,'p_driver_id':driverId,
      'p_customer_name':customerName.trim(),'p_length':length,'p_sale_price':salePrice,'p_driver_fee':driverFee,'p_notes':notes.trim(),
      'p_payments':payments.map((e)=>e.toMap()).toList(),'p_addons':addons.map((e)=>e.toMap()).toList(),
    });
    return result as String;
  }

  Future<OperatingSummary> loadOperatingSummary(String institutionId,DateTime from,DateTime to) async {
    final rows=await client.rpc('operating_summary',params:{'p_institution_id':institutionId,'p_from':from.toIso8601String(),'p_to':to.toIso8601String()});
    return OperatingSummary.fromMap((rows as List).first as Map<String,dynamic>);
  }

  Future<List<OperatingSaleRecord>> loadOperatingSales(String institutionId,DateTime from,DateTime to,{String search=''}) async {
    final rows=await client.rpc('operating_sales',params:{'p_institution_id':institutionId,'p_from':from.toIso8601String(),'p_to':to.toIso8601String(),'p_search':search});
    return (rows as List).map((e)=>OperatingSaleRecord.fromMap(e as Map<String,dynamic>)).toList();
  }

  Future<void> voidSale(String saleId,String reason) async {
    await client.rpc('void_sale',params:{'p_sale_id':saleId,'p_reason':reason.trim()});
  }

  Future<SellerPerformanceRecord> loadSellerPerformance(String institutionId,String sellerId,DateTime from,DateTime to) async {
    final rows=await client.rpc('seller_performance',params:{'p_institution_id':institutionId,'p_seller_id':sellerId,'p_from':from.toIso8601String(),'p_to':to.toIso8601String()});
    return SellerPerformanceRecord.fromMap((rows as List).first as Map<String,dynamic>);
  }

  Future<List<Map<String,dynamic>>> loadPaymentReport(String institutionId,DateTime from,DateTime to) async {
    final rows=await client.from('sale_payments').select('method,amount,sale_id,paid_at').eq('institution_id',institutionId).gte('paid_at',from.toIso8601String()).lt('paid_at',to.toIso8601String()).order('paid_at',ascending:false);
    return List<Map<String,dynamic>>.from(rows);
  }

  Future<void> recordSupplierDelivery({required String institutionId,required String supplierId,required String inventoryId,required double length,required double unitCost,required double wholesalePrice,String reference='',String notes=''}) async {
    await client.rpc('record_supplier_delivery',params:{'p_institution_id':institutionId,'p_supplier_id':supplierId,'p_inventory_id':inventoryId,'p_length':length,'p_unit_cost':unitCost,'p_wholesale_price':wholesalePrice,'p_reference':reference.trim(),'p_notes':notes.trim()});
  }
  Future<List<Map<String,dynamic>>> loadSupplierDeliveries(String institutionId,String supplierId) async {
    final rows=await client.from('supplier_deliveries').select('id,reference,notes,delivered_at,supplier_delivery_items(name_snapshot,color_snapshot,length,unit_cost,wholesale_price)').eq('institution_id',institutionId).eq('supplier_id',supplierId).order('delivered_at',ascending:false);
    return List<Map<String,dynamic>>.from(rows);
  }

  Future<void> saveAddonType({required String institutionId,required String name,required String unit,required double salePrice,required double costPrice,String? supplierId}) async {
    await client.rpc('save_addon_type',params:{'p_institution_id':institutionId,'p_name':name.trim(),'p_unit':unit.trim(),'p_sale_price':salePrice,'p_cost_price':costPrice,'p_supplier_id':supplierId});
  }

  Future<List<InstitutionTrip>> loadInstitutionTripsRange(String institutionId,DateTime from,DateTime to) async {
    final rows=await client.from('driver_trips').select('id,trip_date,amount,payment_status,payment_method,driver:driver_profiles!driver_trips_driver_id_fkey(profiles(full_name)),seller:profiles!driver_trips_seller_id_fkey(full_name)').eq('institution_id',institutionId).gte('trip_date',from.toIso8601String().split('T').first).lt('trip_date',to.toIso8601String().split('T').first).order('trip_date',ascending:false);
    return (rows as List).map((row){final da=row['driver'] as Map<String,dynamic>?;final dp=da?['profiles'] as Map<String,dynamic>?;final sp=row['seller'] as Map<String,dynamic>?;return InstitutionTrip(id:row['id'] as String,driverName:dp?['full_name'] as String? ?? 'سائق',sellerName:sp?['full_name'] as String? ?? 'بائع',date:DateTime.parse(row['trip_date'] as String),amount:(row['amount'] as num).toDouble(),isPaid:row['payment_status']=='paid',paymentMethod:row['payment_method'] as String?);}).toList();
  }


  Future<List<BranchRecord>> loadBranches(String institutionId) async {
    final rows=await client.from('branches').select().eq('institution_id',institutionId).order('created_at');
    return (rows as List).map((e)=>BranchRecord.fromMap(e as Map<String,dynamic>)).toList();
  }
  Future<String> createBranch({required String institutionId,required String name,required String code,String city='',String address='',String phone='',DateTime? openedOn,String notes=''}) async =>
    await client.rpc('create_branch',params:{'p_institution_id':institutionId,'p_name':name,'p_code':code,'p_city':city,'p_address':address,'p_phone':phone,'p_opened_on':openedOn?.toIso8601String().substring(0,10),'p_notes':notes}) as String;
  Future<void> setBranchStatus(String branchId,String status,{String notes=''}) async=>client.rpc('set_branch_status',params:{'p_branch_id':branchId,'p_status':status,'p_notes':notes});
  Future<void> setBranchAccess({required String branchId,required String userId,required bool view,required bool sell,required bool inventory,required bool viewFinancials,required bool manageFinancials,required bool reports}) async=>client.rpc('set_branch_access',params:{'p_branch_id':branchId,'p_user_id':userId,'p_can_view':view,'p_can_sell':sell,'p_inventory':inventory,'p_view_financials':viewFinancials,'p_manage_financials':manageFinancials,'p_reports':reports});
  Future<String> transferInventory(String inventoryId,String toBranchId,double quantity,String note) async=>await client.rpc('transfer_inventory',params:{'p_from_inventory_id':inventoryId,'p_to_branch_id':toBranchId,'p_quantity':quantity,'p_note':note}) as String;
  Future<List<PartnerRecord>> loadPartners(String institutionId) async {final rows=await client.from('partners').select('*,partner_scopes(id,scope,branch_id,effective_from,effective_to,partner_entitlement_history(percentage,effective_from,effective_to))').eq('institution_id',institutionId).order('created_at');return (rows as List).map((e)=>PartnerRecord.fromMap(e as Map<String,dynamic>)).toList();}
  Future<String> addPartner({required String institutionId,String? userId,required String name,String phone='',required String relationship,required String scope,String? branchId,required double percentage,required DateTime effectiveFrom,String notes=''}) async=>await client.rpc('add_partner',params:{'p_institution_id':institutionId,'p_user_id':userId,'p_name':name,'p_phone':phone,'p_relationship':relationship,'p_scope':scope,'p_branch_id':branchId,'p_percentage':percentage,'p_effective_from':effectiveFrom.toIso8601String().substring(0,10),'p_notes':notes}) as String;
  Future<List<BranchReportRecord>> loadBranchReport(String institutionId,DateTime from,DateTime to) async {final rows=await client.rpc('branch_report',params:{'p_institution_id':institutionId,'p_from':from.toIso8601String(),'p_to':to.toIso8601String()});return (rows as List).map((e)=>BranchReportRecord.fromMap(e as Map<String,dynamic>)).toList();}
  Future<void> recordExpense({required String institutionId,String? branchId,required String category,required double amount,String method='',String reference='',String notes='',DateTime? date}) async=>client.rpc('record_expense',params:{'p_institution_id':institutionId,'p_branch_id':branchId,'p_category':category,'p_amount':amount,'p_method':method,'p_reference':reference,'p_notes':notes,'p_date':(date??DateTime.now()).toIso8601String().substring(0,10)});
  Future<bool> hasActiveAccountant(String institutionId) async {
    final rows = await client.from('institution_memberships').select('user_id').eq('institution_id', institutionId).eq('role', 'accountant').eq('status', 'active').limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<OperatingSummary> loadBranchOperatingSummary(String institutionId, String? branchId, DateTime from, DateTime to) async {
    if (branchId == null) return loadOperatingSummary(institutionId, from, to);
    final rows = await client.rpc('branch_operating_summary', params: {
      'p_institution_id': institutionId,
      'p_branch_id': branchId,
      'p_from': from.toIso8601String(),
      'p_to': to.toIso8601String(),
    });
    final row = (rows as List).first as Map<String, dynamic>;
    final payments = Map<String, dynamic>.from((row['payments'] as Map?) ?? const {});
    return OperatingSummary(
      salesAmount: (row['sales_amount'] as num).toDouble(),
      totalLength: (row['total_length'] as num).toDouble(),
      totalArea: (row['total_area'] as num).toDouble(),
      saleCount: (row['sale_count'] as num).toInt(),
      merchandiseCost: (row['merchandise_cost'] as num).toDouble(),
      addonCost: 0,
      driverCost: (row['driver_cost'] as num).toDouble(),
      paymentFees: 0,
      grossProfit: (row['gross_profit'] as num).toDouble(),
      payments: {for (final k in ['cash','network','bank_transfer','visa','tamara','tabby','other']) k: (payments[k] as num?)?.toDouble() ?? 0},
    );
  }

  Future<List<OperatingSaleRecord>> loadDashboardSales(String institutionId, DateTime from, DateTime to, {String? branchId, String? sellerId}) async {
    var rows = await loadOperatingSales(institutionId, from, to);
    if (branchId != null) {
      final allowed = await client.from('sales').select('id').eq('institution_id', institutionId).eq('branch_id', branchId).gte('created_at', from.toIso8601String()).lt('created_at', to.toIso8601String());
      final ids = (allowed as List).map((e) => e['id'] as String).toSet();
      rows = rows.where((x) => ids.contains(x.id)).toList();
    }
    if (sellerId != null) {
      final own = await client.from('sales').select('id').eq('institution_id', institutionId).eq('seller_id', sellerId).gte('created_at', from.toIso8601String()).lt('created_at', to.toIso8601String());
      final ids = (own as List).map((e) => e['id'] as String).toSet();
      rows = rows.where((x) => ids.contains(x.id)).toList();
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> loadRecentActivity(String institutionId, {String? branchId, int limit = 8}) async {
    var query = client.from('sales').select('id,customer_name,total,created_at,branch_id,profiles!sales_seller_id_fkey(full_name)').eq('institution_id', institutionId).eq('status', 'completed');
    if (branchId != null) query = query.eq('branch_id', branchId);
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadExpenses(String institutionId, DateTime from, DateTime to, {String? branchId}) async {
    var query = client.from('expenses').select('id,branch_id,expense_date,category,amount,payment_method,reference,notes,created_at').eq('institution_id', institutionId).gte('expense_date', from.toIso8601String().substring(0,10)).lt('expense_date', to.toIso8601String().substring(0,10));
    if (branchId != null) query = query.eq('branch_id', branchId);
    final rows = await query.order('expense_date', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadPartnerStatement(String institutionId, String partnerId, DateTime from, DateTime to, {String? branchId}) async {
    final rows = await client.rpc('partner_statement', params: {
      'p_institution_id': institutionId,
      'p_partner_id': partnerId,
      'p_from': from.toIso8601String(),
      'p_to': to.toIso8601String(),
      'p_branch_id': branchId,
    });
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>?> loadMyPartnerContext(String institutionId) async {
    final rows = await client.from('partners').select('id,display_name,relationship_type,status,partner_scopes(id,scope,branch_id,effective_from,effective_to,partner_entitlement_history(percentage,effective_from,effective_to))').eq('institution_id', institutionId).eq('user_id', userId).eq('status', 'active').limit(1);
    return (rows as List).isEmpty ? null : Map<String, dynamic>.from(rows.first as Map);
  }

  Future<List<BranchRecord>> loadAccessibleBranches(String institutionId) async => loadBranches(institutionId);

}
