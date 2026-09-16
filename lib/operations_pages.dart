import 'package:flutter/material.dart';

import 'cloud_models.dart';
import 'farsha_repository.dart';

double _number(TextEditingController controller) => double.tryParse(controller.text.trim()) ?? 0;

class InstitutionOperationsPage extends StatefulWidget {
  const InstitutionOperationsPage({super.key, required this.membership, required this.repository});
  final InstitutionMembership membership;
  final FarshaRepository repository;

  @override
  State<InstitutionOperationsPage> createState() => _InstitutionOperationsPageState();
}

class _InstitutionOperationsPageState extends State<InstitutionOperationsPage> {
  late Future<List<SupplierRecord>> _suppliers = widget.repository.loadSuppliers(widget.membership.institutionId);
  late Future<List<InventoryRecord>> _inventory = widget.repository.loadInventory(widget.membership.institutionId);

  bool get canManage => widget.membership.role != InstitutionRole.seller;

  void _reload() => setState(() {
        _suppliers = widget.repository.loadSuppliers(widget.membership.institutionId);
        _inventory = widget.repository.loadInventory(widget.membership.institutionId);
      });

  Future<void> _addSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController(text: '+966');
    final save = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('مورد جديد'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 10),
        TextField(controller: phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    ));
    final supplierName = name.text.trim();
    final supplierPhone = phone.text.trim();
    name.dispose(); phone.dispose();
    if (save != true || supplierName.isEmpty) return;
    await widget.repository.addSupplier(widget.membership.institutionId, supplierName, supplierPhone);
    _reload();
  }

  Future<void> _addInventory(List<SupplierRecord> suppliers) async {
    if (suppliers.isEmpty) return _show('أضف موردًا أولًا');
    final name = TextEditingController(); final color = TextEditingController();
    final length = TextEditingController(); final supplierPrice = TextEditingController();
    final wholesale = TextEditingController(); final low = TextEditingController(text: '10');
    var supplierId = suppliers.first.id;
    final save = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('إضافة رول موكيت'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: supplierId, decoration: const InputDecoration(labelText: 'المورد'), items: suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(), onChanged: (v) => setDialogState(() => supplierId = v!)),
        const SizedBox(height: 10), TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم القطعة')),
        const SizedBox(height: 10), TextField(controller: color, decoration: const InputDecoration(labelText: 'اللون')),
        const SizedBox(height: 10), TextField(controller: length, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الطول بالمتر')),
        const SizedBox(height: 10), TextField(controller: supplierPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر المورد / م²')),
        const SizedBox(height: 10), TextField(controller: wholesale, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر الجملة للبائع / م²')),
        const SizedBox(height: 10), TextField(controller: low, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تنبيه المخزون المنخفض')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    )));
    final values = [name.text.trim(), color.text.trim()];
    final numbers = [_number(length), _number(supplierPrice), _number(wholesale), _number(low)];
    for (final c in [name,color,length,supplierPrice,wholesale,low]) { c.dispose(); }
    if (save != true || values.any((v) => v.isEmpty) || numbers[0] <= 0 || numbers[2] < numbers[1]) return _show('راجع بيانات المخزون');
    await widget.repository.addInventory(institutionId: widget.membership.institutionId, supplierId: supplierId, name: values[0], color: values[1], length: numbers[0], supplierPrice: numbers[1], wholesalePrice: numbers[2], lowStockAt: numbers[3]);
    _reload();
  }

  Future<void> _paySupplier(SupplierRecord supplier) async {
    final amount = TextEditingController();
    final save = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('دفعة للمورد ${supplier.name}'),
      content: TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    ));
    final value = _number(amount); amount.dispose();
    if (save != true || value <= 0) return;
    await widget.repository.paySupplier(widget.membership.institutionId, supplier.id, value);
    _reload();
  }

  void _show(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SupplierRecord>>(
    future: _suppliers,
    builder: (context, supplierSnapshot) => FutureBuilder<List<InventoryRecord>>(
      future: _inventory,
      builder: (context, inventorySnapshot) {
        if (!supplierSnapshot.hasData || !inventorySnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final suppliers = supplierSnapshot.data!; final inventory = inventorySnapshot.data!;
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (canManage) Row(children: [Expanded(child: FilledButton.icon(onPressed: _addSupplier, icon: const Icon(Icons.person_add_alt_1), label: const Text('مورد'))), const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: () => _addInventory(suppliers), icon: const Icon(Icons.add_box_outlined), label: const Text('مخزون')))]),
          const SizedBox(height: 16), const Text('المخزون', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (inventory.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا يوجد مخزون.'))),
          ...inventory.map((item) => Card(color: item.isLow ? Colors.orange.shade50 : null, child: ListTile(leading: Icon(item.isLow ? Icons.warning_amber : Icons.inventory_2_outlined), title: Text('${item.name} • ${item.color}'), subtitle: Text('المتبقي ${item.remainingLength.toStringAsFixed(2)} م • عرض 4 م'), trailing: Text('${item.wholesalePrice.toStringAsFixed(2)} ر.س/م²'))),
          if (canManage) ...[
            const SizedBox(height: 20), const Text('الموردون', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ...suppliers.map((s) => Card(child: ListTile(onTap: () => _paySupplier(s), title: Text(s.name), subtitle: Text('${s.phone}\nمشتريات ${s.purchases.toStringAsFixed(2)} • مدفوع ${s.paid.toStringAsFixed(2)}\nاضغط لتسجيل دفعة'), trailing: Text('متبقي\n${s.remaining.toStringAsFixed(2)}', textAlign: TextAlign.center)))),
          ],
        ]);
      },
    ),
  );
}

class SalesSettlementPage extends StatefulWidget {
  const SalesSettlementPage({super.key, required this.membership, required this.repository});
  final InstitutionMembership membership;
  final FarshaRepository repository;
  @override
  State<SalesSettlementPage> createState() => _SalesSettlementPageState();
}

class _SalesSettlementPageState extends State<SalesSettlementPage> {
  late Future<List<SupplierRecord>> _suppliers = widget.repository.loadSuppliers(widget.membership.institutionId);
  late Future<List<InventoryRecord>> _inventory = widget.repository.loadInventory(widget.membership.institutionId);
  late Future<List<PersonOption>> _sellers = widget.repository.loadSellers(widget.membership.institutionId);
  late Future<List<PersonOption>> _drivers = widget.repository.loadDriverOptions(widget.membership.institutionId);
  final _customer = TextEditingController(); final _length = TextEditingController(); final _price = TextEditingController();
  final _installation = TextEditingController(text: '0'); final _glueQty = TextEditingController(text: '0'); final _glueAmount = TextEditingController(text: '0');
  final _ironQty = TextEditingController(text: '0'); final _ironAmount = TextEditingController(text: '0'); final _driverFee = TextEditingController(text: '0');
  String? _inventoryId; String? _sellerId; String? _driverId; String? _glueSupplierId; String? _ironSupplierId; String _payment = 'cash'; bool _busy = false;

  @override void dispose() { for (final c in [_customer,_length,_price,_installation,_glueQty,_glueAmount,_ironQty,_ironAmount,_driverFee]) { c.dispose(); } super.dispose(); }

  Future<void> _save(List<InventoryRecord> inventory) async {
    final seller = widget.membership.role == InstitutionRole.seller ? widget.repository.userId : _sellerId;
    InventoryRecord? item;
    for (final candidate in inventory) {
      if (candidate.id == _inventoryId) item = candidate;
    }
    if (item == null || seller == null || _number(_length) <= 0 || _number(_length) > item.remainingLength || _number(_price) < 0) return _message('راجع القطعة والطول والسعر');
    if (_number(_glueQty) > 0 && _glueSupplierId == null) return _message('اختر مورد الغراء');
    if (_number(_ironQty) > 0 && _ironSupplierId == null) return _message('اختر مورد الحديد');
    setState(() => _busy = true);
    try {
      await widget.repository.recordSale(institutionId: widget.membership.institutionId, inventoryId: item.id, sellerId: seller, driverId: _driverId, customerName: _customer.text, length: _number(_length), salePrice: _number(_price), installation: _number(_installation), glueSupplierId: _glueSupplierId, glueGallons: _number(_glueQty), glueAmount: _number(_glueAmount), ironSupplierId: _ironSupplierId, ironPieces: _number(_ironQty), ironAmount: _number(_ironAmount), driverFee: _number(_driverFee), paymentMethod: _payment);
      _message('تم حفظ البيع وخصم الطول من المخزون');
      setState(() { _inventory = widget.repository.loadInventory(widget.membership.institutionId); _length.clear(); _price.clear(); });
    } catch (error) { _message('$error'); } finally { if (mounted) setState(() => _busy = false); }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SupplierRecord>>(future: _suppliers, builder: (context, supplierSnap) => FutureBuilder<List<InventoryRecord>>(future: _inventory, builder: (context, invSnap) => FutureBuilder<List<PersonOption>>(future: _sellers, builder: (context, sellerSnap) => FutureBuilder<List<PersonOption>>(future: _drivers, builder: (context, driverSnap) {
    if (!supplierSnap.hasData || !invSnap.hasData || !sellerSnap.hasData || !driverSnap.hasData) return const Center(child: CircularProgressIndicator());
    final suppliers = supplierSnap.data!; final inventory = invSnap.data!; final sellers = sellerSnap.data!; final drivers = driverSnap.data!;
    if (widget.membership.role == InstitutionRole.accountant) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('المحاسب يراجع الحسابات والتصفية، وتسجيل البيع للبائع أو صاحب المؤسسة.'))),
          const SizedBox(height: 16),
          SettlementPanel(membership: widget.membership, repository: widget.repository, sellers: sellers),
        ],
      );
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('بيعة جديدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: _inventoryId, decoration: const InputDecoration(labelText: 'القطعة واللون'), items: inventory.where((i) => i.remainingLength > 0).map((i) => DropdownMenuItem(value: i.id, child: Text('${i.name} • ${i.color} (${i.remainingLength.toStringAsFixed(1)} م)'))).toList(), onChanged: (v) => setState(() => _inventoryId = v)),
      if (widget.membership.role != InstitutionRole.seller) ...[const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: _sellerId, decoration: const InputDecoration(labelText: 'البائع'), items: sellers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(), onChanged: (v) => setState(() => _sellerId = v))],
      const SizedBox(height: 10), TextField(controller: _customer, decoration: const InputDecoration(labelText: 'اسم العميل (اختياري)')),
      const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: _length, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الطول م'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر البيع/م²')))]),
      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('العرض ثابت 4 م والمساحة = الطول × 4')),
      Row(children: [Expanded(child: TextField(controller: _installation, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'التركيب'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _glueQty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'جالون غراء')))]),
      const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: _glueSupplierId, decoration: const InputDecoration(labelText: 'مورد الغراء'), items: suppliers.map((supplier) => DropdownMenuItem(value: supplier.id, child: Text(supplier.name))).toList(), onChanged: (value) => setState(() => _glueSupplierId = value)),
      const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: _glueAmount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'قيمة الغراء'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _ironQty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'قطع حديد')))]),
      const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: _ironSupplierId, decoration: const InputDecoration(labelText: 'مورد الحديد'), items: suppliers.map((supplier) => DropdownMenuItem(value: supplier.id, child: Text(supplier.name))).toList(), onChanged: (value) => setState(() => _ironSupplierId = value)),
      const SizedBox(height: 10), TextField(controller: _ironAmount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'قيمة الحديد')),
      const SizedBox(height: 10), DropdownButtonFormField<String?>(initialValue: _driverId, decoration: const InputDecoration(labelText: 'السائق (اختياري)'), items: [const DropdownMenuItem<String?>(value: null, child: Text('بدون سائق')), ...drivers.map((d) => DropdownMenuItem<String?>(value: d.id, child: Text(d.name)))], onChanged: (v) => setState(() => _driverId = v)),
      const SizedBox(height: 10), TextField(controller: _driverFee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حساب المشوار')),
      const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: _payment, decoration: const InputDecoration(labelText: 'طريقة دفع العميل'), items: const [DropdownMenuItem(value: 'cash', child: Text('كاش')), DropdownMenuItem(value: 'network', child: Text('شبكة')), DropdownMenuItem(value: 'visa', child: Text('Visa')), DropdownMenuItem(value: 'tabby', child: Text('Tabby')), DropdownMenuItem(value: 'tamara', child: Text('Tamara'))], onChanged: (v) => setState(() => _payment = v!)),
      const SizedBox(height: 16), FilledButton(onPressed: _busy ? null : () => _save(inventory), child: Text(_busy ? 'جاري الحفظ...' : 'حفظ البيع وخصم المخزون')),
      const SizedBox(height: 24), SettlementPanel(membership: widget.membership, repository: widget.repository, sellers: sellers),
    ]);
  }))));
}

class SettlementPanel extends StatefulWidget {
  const SettlementPanel({super.key, required this.membership, required this.repository, required this.sellers});
  final InstitutionMembership membership; final FarshaRepository repository; final List<PersonOption> sellers;
  @override State<SettlementPanel> createState() => _SettlementPanelState();
}

class _SettlementPanelState extends State<SettlementPanel> {
  String? _sellerId;
  Future<void> _addEntry(String sellerId) async {
    final amount = TextEditingController(); final note = TextEditingController(); var kind = 'withdrawal';
    final save = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('حركة على حساب البائع'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: kind, decoration: const InputDecoration(labelText: 'النوع'), items: const [DropdownMenuItem(value: 'withdrawal', child: Text('مسحوبات')), DropdownMenuItem(value: 'expense', child: Text('مصروفات')), DropdownMenuItem(value: 'deduction', child: Text('خصم')), DropdownMenuItem(value: 'payment', child: Text('مدفوع'))], onChanged: (v) => setDialogState(() => kind = v!)),
        const SizedBox(height: 10), TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ')),
        const SizedBox(height: 10), TextField(controller: note, decoration: const InputDecoration(labelText: 'بيان')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    )));
    final value = _number(amount); final text = note.text.trim(); amount.dispose(); note.dispose();
    if (save != true || value <= 0) return;
    await widget.repository.addSellerLedger(institutionId: widget.membership.institutionId, sellerId: sellerId, kind: kind, amount: value, note: text);
    if (mounted) setState(() {});
  }
  @override Widget build(BuildContext context) {
    final seller = widget.membership.role == InstitutionRole.seller ? widget.repository.userId : _sellerId;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('التصفية الشهرية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
      if (widget.membership.role != InstitutionRole.seller) DropdownButtonFormField<String>(initialValue: _sellerId, decoration: const InputDecoration(labelText: 'البائع'), items: widget.sellers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(), onChanged: (v) => setState(() => _sellerId = v)),
      if (seller != null) FutureBuilder<SettlementSummary>(future: widget.repository.loadSettlement(widget.membership.institutionId, seller, DateTime.now()), builder: (context, snapshot) {
        if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
        final s = snapshot.data!;
        return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          _line('الراتب', s.salary), _line('العمولات', s.commission), _line('المسحوبات', -s.withdrawals), _line('المصروفات', -s.expenses), _line('الخصومات', -s.deductions), _line('المدفوعات', -s.payments), const Divider(), _line('صافي المستحق', s.net, bold: true),
          if (widget.membership.role != InstitutionRole.seller) ...[const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => _addEntry(seller), icon: const Icon(Icons.add), label: const Text('إضافة حركة'))],
        ])));
      }),
    ]);
  }
  Widget _line(String label, double value, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)), Text('${value.toStringAsFixed(2)} ر.س', style: TextStyle(fontWeight: bold ? FontWeight.bold : null))]));
}
