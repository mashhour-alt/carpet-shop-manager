import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'models.dart';

class ShopDatabase {
  ShopDatabase._(); static final instance = ShopDatabase._(); Database? _db;
  Future<Database> get db async => _db ??= await openDatabase(join(await getDatabasesPath(), 'carpet_shop_manager.db'), version: 1, onCreate: _create);
  Future<void> _create(Database d, int v) async {
    await d.execute('CREATE TABLE institutions(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,commercial_registration TEXT NOT NULL,tax_number TEXT NOT NULL,address TEXT NOT NULL,phone TEXT NOT NULL,email TEXT NOT NULL,logo_path TEXT,visa_fee REAL NOT NULL DEFAULT 0,tabby_fee REAL NOT NULL DEFAULT 0,tamara_fee REAL NOT NULL DEFAULT 0)');
    await d.execute('CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT,institution_id INTEGER NOT NULL,name TEXT NOT NULL,phone TEXT NOT NULL,role TEXT NOT NULL,photo_path TEXT,work_plan TEXT NOT NULL,commission_rate REAL NOT NULL,salary REAL NOT NULL)');
    await d.execute('CREATE TABLE suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT,institution_id INTEGER NOT NULL,name TEXT NOT NULL,phone TEXT NOT NULL)');
    await d.execute('CREATE TABLE inventory(id INTEGER PRIMARY KEY AUTOINCREMENT,institution_id INTEGER NOT NULL,supplier_id INTEGER NOT NULL,name TEXT NOT NULL,color TEXT NOT NULL,length REAL NOT NULL,width REAL NOT NULL DEFAULT 4,supplier_price REAL NOT NULL,wholesale_price REAL NOT NULL,image_path TEXT,low_stock_at REAL NOT NULL DEFAULT 10,created_at TEXT NOT NULL)');
    await d.execute('CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT,institution_id INTEGER NOT NULL,inventory_id INTEGER NOT NULL,seller_id INTEGER NOT NULL,driver_id INTEGER,customer_name TEXT NOT NULL,length REAL NOT NULL,width REAL NOT NULL,sale_price REAL NOT NULL,installation REAL NOT NULL,glue_gallons REAL NOT NULL,glue_cost REAL NOT NULL,iron_pieces REAL NOT NULL,iron_cost REAL NOT NULL,driver_fee REAL NOT NULL,customer_payment TEXT NOT NULL,driver_payment TEXT NOT NULL,payment_fee REAL NOT NULL,created_at TEXT NOT NULL)');
    await d.execute('CREATE TABLE ledger(id INTEGER PRIMARY KEY AUTOINCREMENT,institution_id INTEGER NOT NULL,user_id INTEGER NOT NULL,kind TEXT NOT NULL,amount REAL NOT NULL,note TEXT NOT NULL,created_at TEXT NOT NULL)');
  }
  Future<int> addInstitution(Institution x) async => (await db).insert('institutions', x.toMap()..remove('id'));
  Future<List<Institution>> institutions() async => (await db).query('institutions').then((r)=>r.map(Institution.fromMap).toList());
  Future<int> addUser(AppUser x) async => (await db).insert('users',x.toMap()..remove('id'));
  Future<List<AppUser>> users(int inst, {UserRole? role}) async { final r=await (await db).query('users',where: role==null?'institution_id=?':'institution_id=? AND role=?',whereArgs:role==null?[inst]:[inst,role.name]); return r.map(AppUser.fromMap).toList(); }
  Future<int> addSupplier(Supplier x) async => (await db).insert('suppliers',x.toMap()..remove('id'));
  Future<List<Supplier>> suppliers(int inst) async => (await db).query('suppliers',where:'institution_id=?',whereArgs:[inst]).then((r)=>r.map(Supplier.fromMap).toList());
  Future<int> addInventory(InventoryItem x) async => (await db).insert('inventory',x.toMap()..remove('id'));
  Future<List<InventoryItem>> inventory(int inst) async => (await db).query('inventory',where:'institution_id=?',whereArgs:[inst],orderBy:'name').then((r)=>r.map(InventoryItem.fromMap).toList());
  Future<void> addSale(Sale sale) async { final d=await db; await d.transaction((txn) async { final row=(await txn.query('inventory',columns:['length'],where:'id=?',whereArgs:[sale.inventoryId])).single; final available=(row['length'] as num).toDouble(); if(sale.length>available) throw StateError('الطول المطلوب غير متاح'); await txn.insert('sales',sale.toMap()..remove('id')); await txn.update('inventory',{'length':available-sale.length},where:'id=?',whereArgs:[sale.inventoryId]); }); }
  Future<List<Sale>> sales(int inst) async => (await db).query('sales',where:'institution_id=?',whereArgs:[inst],orderBy:'created_at DESC').then((r)=>r.map(Sale.fromMap).toList());
  Future<int> addLedger(LedgerEntry x) async => (await db).insert('ledger',x.toMap()..remove('id'));
  Future<List<LedgerEntry>> ledger(int inst,int user) async => (await db).query('ledger',where:'institution_id=? AND user_id=?',whereArgs:[inst,user]).then((r)=>r.map(LedgerEntry.fromMap).toList());
}
