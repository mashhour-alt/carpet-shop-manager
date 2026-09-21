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
          ...inventory.map((item) => Card(color: item.isLow ? Colors.orange.shade50 : null, child: ListTile(leading: Icon(item.isLow ? Icons.warning_amber : Icons.inventory_2_outlined), title: Text('${item.name} • ${item.color}'), subtitle: Text('المتبقي ${item.remainingLength.toStringAsFixed(2)} م • عرض 4 م'), trailing: Text('${item.wholesalePrice.toStringAsFixed(2)} ر.س/م²')))),
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
  const SalesSettlementPage({super.key,required this.membership,required this.repository});
  final InstitutionMembership membership; final FarshaRepository repository;
  @override State<SalesSettlementPage> createState()=>_SalesSettlementPageState();
}
class _SalesSettlementPageState extends State<SalesSettlementPage> {
  late Future<List<InventoryRecord>> inventory=widget.repository.loadInventory(widget.membership.institutionId);
  late final Future<List<PersonOption>> sellers=widget.repository.loadSellers(widget.membership.institutionId);
  late final Future<List<PersonOption>> drivers=widget.repository.loadDriverOptions(widget.membership.institutionId);
  late final Future<List<AddonTypeRecord>> addonTypes=widget.repository.loadAddonTypes(widget.membership.institutionId);
  final customer=TextEditingController(),length=TextEditingController(),price=TextEditingController(),driverFee=TextEditingController(text:'0'),notes=TextEditingController();
  String? inventoryId,sellerId,driverId; bool busy=false;
  final List<SaleAddonInput> addons=[]; final List<SalePaymentInput> payments=[];
  @override void dispose(){for(final x in[customer,length,price,driverFee,notes])x.dispose();super.dispose();}
  double n(TextEditingController c)=>double.tryParse(c.text.trim())??0;
  void msg(String x)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(x)));
  double get addonSales=>addons.fold(0,(a,b)=>a+b.saleTotal);
  double total(List<InventoryRecord> items){final item=items.where((e)=>e.id==inventoryId).firstOrNull;if(item==null)return 0;return n(length)*4*n(price)+addonSales+n(driverFee);}
  Future<void> addPayment(double due) async {
    var method='cash';final amount=TextEditingController(text:due>0?due.toStringAsFixed(2):'');final ref=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:const Text('إضافة دفعة'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<String>(initialValue:method,decoration:const InputDecoration(labelText:'الطريقة'),items:const [
        DropdownMenuItem(value:'cash',child:Text('كاش')),DropdownMenuItem(value:'network',child:Text('شبكة')),DropdownMenuItem(value:'bank_transfer',child:Text('تحويل بنكي')),DropdownMenuItem(value:'visa',child:Text('Visa')),DropdownMenuItem(value:'tamara',child:Text('تمارا')),DropdownMenuItem(value:'tabby',child:Text('تابي')),DropdownMenuItem(value:'other',child:Text('أخرى'))],onChanged:(v)=>setD(()=>method=v!)),
      const SizedBox(height:8),TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'المبلغ')),const SizedBox(height:8),TextField(controller:ref,decoration:const InputDecoration(labelText:'مرجع العملية (اختياري)'))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('إضافة'))])));
    final a=n(amount),r=ref.text.trim();amount.dispose();ref.dispose();if(ok==true&&a>0)setState(()=>payments.add(SalePaymentInput(method:method,amount:a,reference:r)));
  }
  Future<void> addAddon(List<AddonTypeRecord> types) async {
    if(types.isEmpty)return msg('أضف أنواع الإضافات من إعدادات المؤسسة');
    AddonTypeRecord type=types.first;final qty=TextEditingController(text:'1'),sale=TextEditingController(text:type.defaultSalePrice.toStringAsFixed(2));
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:const Text('إضافة للبيعة'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<String>(initialValue:type.id,decoration:const InputDecoration(labelText:'الإضافة'),items:types.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.name))).toList(),onChanged:(v){setD((){type=types.firstWhere((x)=>x.id==v);sale.text=type.defaultSalePrice.toStringAsFixed(2);});}),
      const SizedBox(height:8),TextField(controller:qty,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'الكمية ('+type.unit+')')),const SizedBox(height:8),TextField(controller:sale,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'سعر البيع للوحدة'))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('إضافة'))])));
    final q=n(qty),sp=n(sale);qty.dispose();sale.dispose();if(ok==true&&q>0&&sp>=0)setState(()=>addons.add(SaleAddonInput(addonTypeId:type.id,name:type.name,unit:type.unit,quantity:q,saleUnitPrice:sp,costUnitPrice:type.defaultCostPrice)));
  }
  Future<void> save(List<InventoryRecord> items) async {
    final seller=widget.membership.role==InstitutionRole.seller?widget.repository.userId:sellerId;
    final item=items.where((e)=>e.id==inventoryId).firstOrNull;
    if(item==null||seller==null||n(length)<=0||n(length)>item.remainingLength||n(price)<0)return msg('راجع القطعة والطول والسعر');
    final t=total(items),paid=payments.fold<double>(0,(a,b)=>a+b.amount);
    if((paid-t).abs()>.009)return msg('إجمالي الدفعات '+paid.toStringAsFixed(2)+' لا يساوي إجمالي البيع '+t.toStringAsFixed(2));
    setState(()=>busy=true);
    try{await widget.repository.recordSaleV2(institutionId:widget.membership.institutionId,inventoryId:item.id,sellerId:seller,driverId:driverId,customerName:customer.text,length:n(length),salePrice:n(price),driverFee:n(driverFee),notes:notes.text,payments:payments,addons:addons);
      msg('تم حفظ البيع والدفعات وخصم المخزون');setState((){inventory=widget.repository.loadInventory(widget.membership.institutionId);length.clear();price.clear();notes.clear();payments.clear();addons.clear();});
    }catch(e){msg(e.toString());}finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>FutureBuilder<List<InventoryRecord>>(future:inventory,builder:(c,iv)=>FutureBuilder<List<PersonOption>>(future:sellers,builder:(c,ss)=>FutureBuilder<List<PersonOption>>(future:drivers,builder:(c,dd)=>FutureBuilder<List<AddonTypeRecord>>(future:addonTypes,builder:(c,aa){
    if(!iv.hasData||!ss.hasData||!dd.hasData||!aa.hasData)return const Center(child:CircularProgressIndicator());
    if(widget.membership.role==InstitutionRole.accountant)return ListView(padding:const EdgeInsets.all(16),children:[SettlementPanel(membership:widget.membership,repository:widget.repository,sellers:ss.data!)]);
    final items=iv.data!,t=total(items),paid=payments.fold<double>(0,(a,b)=>a+b.amount),remaining=t-paid;
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('بيعة جديدة',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:10),
      DropdownButtonFormField<String>(initialValue:inventoryId,decoration:const InputDecoration(labelText:'الصنف واللون'),items:items.where((x)=>x.remainingLength>0).map((x)=>DropdownMenuItem(value:x.id,child:Text(x.name+' • '+x.color+' ('+x.remainingLength.toStringAsFixed(1)+' م)'))).toList(),onChanged:(v)=>setState(()=>inventoryId=v)),
      if(widget.membership.role!=InstitutionRole.seller)...[const SizedBox(height:8),DropdownButtonFormField<String>(initialValue:sellerId,decoration:const InputDecoration(labelText:'البائع'),items:ss.data!.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.name))).toList(),onChanged:(v)=>setState(()=>sellerId=v))],
      const SizedBox(height:8),TextField(controller:customer,decoration:const InputDecoration(labelText:'العميل (اختياري)')),
      const SizedBox(height:8),Row(children:[Expanded(child:TextField(controller:length,onChanged:(_)=>setState((){}),keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الطول م'))),const SizedBox(width:8),Expanded(child:TextField(controller:price,onChanged:(_)=>setState((){}),keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'سعر البيع/م²')))]),
      Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text('المساحة: '+(n(length)*4).toStringAsFixed(2)+' م² • العرض 4 م')),
      OutlinedButton.icon(onPressed:()=>addAddon(aa.data!),icon:const Icon(Icons.add),label:const Text('إضافة تركيب / لباد / حديد / غراء')),
      ...addons.asMap().entries.map((e)=>ListTile(title:Text(e.value.name+' × '+e.value.quantity.toStringAsFixed(2)),subtitle:Text((e.value.saleTotal).toStringAsFixed(2)+' ر.س'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>setState(()=>addons.removeAt(e.key))))),
      const SizedBox(height:8),DropdownButtonFormField<String?>(initialValue:driverId,decoration:const InputDecoration(labelText:'السائق (اختياري)'),items:[const DropdownMenuItem<String?>(value:null,child:Text('بدون سائق')),...dd.data!.map((x)=>DropdownMenuItem<String?>(value:x.id,child:Text(x.name)))],onChanged:(v)=>setState(()=>driverId=v)),
      const SizedBox(height:8),TextField(controller:driverFee,onChanged:(_)=>setState((){}),keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'تكلفة السائق')),
      const SizedBox(height:8),TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'ملاحظات')),
      const Divider(height:28),Text('إجمالي البيع: '+t.toStringAsFixed(2)+' ر.س',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      ...payments.asMap().entries.map((e)=>ListTile(title:Text(e.value.method),subtitle:Text(e.value.amount.toStringAsFixed(2)+' ر.س'+(e.value.reference.isEmpty?'':' • '+e.value.reference)),trailing:IconButton(icon:const Icon(Icons.close),onPressed:()=>setState(()=>payments.removeAt(e.key))))),
      OutlinedButton.icon(onPressed:()=>addPayment(remaining),icon:const Icon(Icons.payments_outlined),label:Text('إضافة دفعة • المتبقي '+remaining.toStringAsFixed(2)+' ر.س')),
      const SizedBox(height:12),FilledButton(onPressed:busy?null:()=>save(items),child:Text(busy?'جاري الحفظ...':'حفظ البيع وخصم المخزون')),
      const SizedBox(height:24),SettlementPanel(membership:widget.membership,repository:widget.repository,sellers:ss.data!),
    ]);
  })))));
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
