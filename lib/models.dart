enum UserRole { owner, accountant, seller, driver }

extension UserRoleText on UserRole {
  String get title => switch (this) {
    UserRole.owner => 'صاحب المؤسسة', UserRole.accountant => 'المحاسب',
    UserRole.seller => 'البائع', UserRole.driver => 'السائق',
  };
  static UserRole fromDb(String value) => UserRole.values.firstWhere((e) => e.name == value);
}

enum WorkPlan { commission, salary, salaryAndCommission }
extension WorkPlanText on WorkPlan {
  String get title => switch (this) {
    WorkPlan.commission => 'عمولة فقط', WorkPlan.salary => 'راتب فقط',
    WorkPlan.salaryAndCommission => 'راتب + عمولة',
  };
  static WorkPlan fromDb(String value) => WorkPlan.values.firstWhere((e) => e.name == value);
}

class Institution {
  Institution({required this.id, required this.name, required this.commercialRegistration, required this.taxNumber, required this.address, required this.phone, required this.email, this.logoPath, this.visaFee = 0, this.tabbyFee = 0, this.tamaraFee = 0});
  final int? id; final String name, commercialRegistration, taxNumber, address, phone, email; final String? logoPath; final double visaFee, tabbyFee, tamaraFee;
  Map<String, Object?> toMap() => {'id': id, 'name': name, 'commercial_registration': commercialRegistration, 'tax_number': taxNumber, 'address': address, 'phone': phone, 'email': email, 'logo_path': logoPath, 'visa_fee': visaFee, 'tabby_fee': tabbyFee, 'tamara_fee': tamaraFee};
  factory Institution.fromMap(Map<String, Object?> m) => Institution(id: m['id'] as int, name: m['name'] as String, commercialRegistration: m['commercial_registration'] as String, taxNumber: m['tax_number'] as String, address: m['address'] as String, phone: m['phone'] as String, email: m['email'] as String, logoPath: m['logo_path'] as String?, visaFee: (m['visa_fee'] as num).toDouble(), tabbyFee: (m['tabby_fee'] as num).toDouble(), tamaraFee: (m['tamara_fee'] as num).toDouble());
}

class AppUser {
  AppUser({required this.id, required this.institutionId, required this.name, required this.phone, required this.role, this.photoPath, this.workPlan = WorkPlan.commission, this.commissionRate = .5, this.salary = 0});
  final int? id, institutionId; final String name, phone; final UserRole role; final String? photoPath; final WorkPlan workPlan; final double commissionRate, salary;
  Map<String, Object?> toMap() => {'id': id, 'institution_id': institutionId, 'name': name, 'phone': phone, 'role': role.name, 'photo_path': photoPath, 'work_plan': workPlan.name, 'commission_rate': commissionRate, 'salary': salary};
  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(id: m['id'] as int, institutionId: m['institution_id'] as int, name: m['name'] as String, phone: m['phone'] as String, role: UserRoleText.fromDb(m['role'] as String), photoPath: m['photo_path'] as String?, workPlan: WorkPlanText.fromDb(m['work_plan'] as String), commissionRate: (m['commission_rate'] as num).toDouble(), salary: (m['salary'] as num).toDouble());
}

class Supplier { Supplier({required this.id, required this.institutionId, required this.name, required this.phone}); final int? id, institutionId; final String name, phone; Map<String,Object?> toMap()=>{'id':id,'institution_id':institutionId,'name':name,'phone':phone}; factory Supplier.fromMap(Map<String,Object?> m)=>Supplier(id:m['id'] as int,institutionId:m['institution_id'] as int,name:m['name'] as String,phone:m['phone'] as String); }

class InventoryItem {
  InventoryItem({required this.id, required this.institutionId, required this.supplierId, required this.name, required this.color, required this.length, this.width = 4, required this.supplierPrice, required this.wholesalePrice, this.imagePath, this.lowStockAt = 10, required this.createdAt});
  final int? id, institutionId, supplierId; final String name, color; final double length, width, supplierPrice, wholesalePrice, lowStockAt; final String? imagePath; final DateTime createdAt;
  double get margin => wholesalePrice - supplierPrice;
  Map<String,Object?> toMap()=>{'id':id,'institution_id':institutionId,'supplier_id':supplierId,'name':name,'color':color,'length':length,'width':width,'supplier_price':supplierPrice,'wholesale_price':wholesalePrice,'image_path':imagePath,'low_stock_at':lowStockAt,'created_at':createdAt.toIso8601String()};
  factory InventoryItem.fromMap(Map<String,Object?> m)=>InventoryItem(id:m['id'] as int,institutionId:m['institution_id'] as int,supplierId:m['supplier_id'] as int,name:m['name'] as String,color:m['color'] as String,length:(m['length'] as num).toDouble(),width:(m['width'] as num).toDouble(),supplierPrice:(m['supplier_price'] as num).toDouble(),wholesalePrice:(m['wholesale_price'] as num).toDouble(),imagePath:m['image_path'] as String?,lowStockAt:(m['low_stock_at'] as num).toDouble(),createdAt:DateTime.parse(m['created_at'] as String));
}

class Sale {
  Sale({required this.id, required this.institutionId, required this.inventoryId, required this.sellerId, this.driverId, required this.customerName, required this.length, required this.width, required this.salePrice, required this.installation, required this.glueGallons, required this.glueCost, required this.ironPieces, required this.ironCost, required this.driverFee, required this.customerPayment, required this.driverPayment, required this.paymentFee, required this.createdAt});
  final int? id, institutionId, inventoryId, sellerId, driverId; final String customerName, customerPayment, driverPayment; final double length,width,salePrice,installation,glueGallons,glueCost,ironPieces,ironCost,driverFee,paymentFee; final DateTime createdAt;
  double get area=>length*width; double get carpetTotal=>area*salePrice; double get total=>carpetTotal+installation+glueCost+ironCost+driverFee; 
  Map<String,Object?> toMap()=>{'id':id,'institution_id':institutionId,'inventory_id':inventoryId,'seller_id':sellerId,'driver_id':driverId,'customer_name':customerName,'length':length,'width':width,'sale_price':salePrice,'installation':installation,'glue_gallons':glueGallons,'glue_cost':glueCost,'iron_pieces':ironPieces,'iron_cost':ironCost,'driver_fee':driverFee,'customer_payment':customerPayment,'driver_payment':driverPayment,'payment_fee':paymentFee,'created_at':createdAt.toIso8601String()};
  factory Sale.fromMap(Map<String,Object?> m)=>Sale(id:m['id'] as int,institutionId:m['institution_id'] as int,inventoryId:m['inventory_id'] as int,sellerId:m['seller_id'] as int,driverId:m['driver_id'] as int?,customerName:m['customer_name'] as String,length:(m['length'] as num).toDouble(),width:(m['width'] as num).toDouble(),salePrice:(m['sale_price'] as num).toDouble(),installation:(m['installation'] as num).toDouble(),glueGallons:(m['glue_gallons'] as num).toDouble(),glueCost:(m['glue_cost'] as num).toDouble(),ironPieces:(m['iron_pieces'] as num).toDouble(),ironCost:(m['iron_cost'] as num).toDouble(),driverFee:(m['driver_fee'] as num).toDouble(),customerPayment:m['customer_payment'] as String,driverPayment:m['driver_payment'] as String,paymentFee:(m['payment_fee'] as num).toDouble(),createdAt:DateTime.parse(m['created_at'] as String));
}

class LedgerEntry { LedgerEntry({required this.id,required this.institutionId,required this.userId,required this.kind,required this.amount,required this.note,required this.createdAt}); final int? id,institutionId,userId; final String kind,note; final double amount; final DateTime createdAt; Map<String,Object?> toMap()=>{'id':id,'institution_id':institutionId,'user_id':userId,'kind':kind,'amount':amount,'note':note,'created_at':createdAt.toIso8601String()}; factory LedgerEntry.fromMap(Map<String,Object?> m)=>LedgerEntry(id:m['id'] as int,institutionId:m['institution_id'] as int,userId:m['user_id'] as int,kind:m['kind'] as String,amount:(m['amount'] as num).toDouble(),note:m['note'] as String,createdAt:DateTime.parse(m['created_at'] as String)); }
