import 'package:flutter/material.dart';
import 'database.dart';
import 'models.dart';

void main() => runApp(const CarpetShopManager());

class CarpetShopManager extends StatelessWidget {
  const CarpetShopManager({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'إدارة الموكيت', locale: const Locale('ar'),
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff075c55), scaffoldBackgroundColor: const Color(0xfff7f8f6), inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true, fillColor: Colors.white)),
    builder: (_, child) => Directionality(textDirection: TextDirection.rtl, child: child!), home: const StartGate(),
  );
}

class StartGate extends StatefulWidget { const StartGate({super.key}); @override State<StartGate> createState()=>_StartGateState(); }
class _StartGateState extends State<StartGate> {
  late Future<List<Institution>> _institutions;
  @override void initState(){super.initState();_institutions=ShopDatabase.instance.institutions();}
  @override Widget build(BuildContext context)=>FutureBuilder<List<Institution>>(future:_institutions,builder:(context,s){ if(!s.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator())); if(s.data!.isEmpty)return const InstitutionForm(); return InstitutionPicker(institutions:s.data!);});
}

class InstitutionPicker extends StatelessWidget {
  const InstitutionPicker({super.key, required this.institutions});
  final List<Institution> institutions;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('مؤسسة / سائق')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('اختر المؤسسة للدخول', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...institutions.map(
              (i) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.storefront)),
                  title: Text(i.name),
                  subtitle: Text(i.phone),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => UserPicker(institution: i)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InstitutionForm()),
              ),
              icon: const Icon(Icons.add_business),
              label: const Text('إنشاء مؤسسة جديدة'),
            ),
          ],
        ),
      );
}

class InstitutionForm extends StatefulWidget { const InstitutionForm({super.key}); @override State<InstitutionForm> createState()=>_InstitutionFormState(); }
class _InstitutionFormState extends State<InstitutionForm>{ final form=GlobalKey<FormState>(); final n=TextEditingController(),cr=TextEditingController(),tax=TextEditingController(),a=TextEditingController(),p=TextEditingController(),e=TextEditingController(),visa=TextEditingController(text:'0'),tabby=TextEditingController(text:'0'),tamara=TextEditingController(text:'0');
  double num(TextEditingController c)=>double.tryParse(c.text.replaceAll(',','.'))??0;
  Future<void> save()async{if(!form.currentState!.validate())return; final id=await ShopDatabase.instance.addInstitution(Institution(name:n.text.trim(),commercialRegistration:cr.text.trim(),taxNumber:tax.text.trim(),address:a.text.trim(),phone:p.text.trim(),email:e.text.trim(),visaFee:num(visa)/100,tabbyFee:num(tabby)/100,tamaraFee:num(tamara)/100));if(!mounted)return;Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>UserSetup(institutionId:id,institutionName:n.text.trim())),(_)=>false);}
  @override void dispose(){for(final x in[n,cr,tax,a,p,e,visa,tabby,tamara]){x.dispose();}super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('إنشاء مؤسسة')),body:Form(key:form,child:ListView(padding:const EdgeInsets.all(18),children:[const Text('بيانات المؤسسة',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const Text('تُطبع تلقائيًا في عروض الأسعار والفواتير.'),gap,field(n,'اسم المؤسسة'),gap,field(cr,'السجل التجاري'),gap,field(tax,'الرقم الضريبي'),gap,field(a,'العنوان'),gap,field(p,'الهاتف'),gap,field(e,'البريد الإلكتروني',email:true),const SizedBox(height:18),const Text('رسوم الدفع (%)',style:TextStyle(fontWeight:FontWeight.bold)),gap,Row(children:[Expanded(child:number(visa,'Visa')),const SizedBox(width:8),Expanded(child:number(tabby,'Tabby')),const SizedBox(width:8),Expanded(child:number(tamara,'Tamara'))]),const SizedBox(height:24),FilledButton(onPressed:save,child:const Padding(padding:EdgeInsets.all(14),child:Text('حفظ المؤسسة وإنشاء المستخدمين')))])));
  TextFormField field(TextEditingController c,String label,{bool email=false})=>TextFormField(controller:c,keyboardType:email?TextInputType.emailAddress:TextInputType.text,decoration:InputDecoration(labelText:label),validator:(v)=>(v==null||v.trim().isEmpty)?'هذا الحقل مطلوب':null);
  TextFormField number(TextEditingController c,String l)=>TextFormField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:l));
}

class UserSetup extends StatefulWidget { const UserSetup({super.key,required this.institutionId,required this.institutionName}); final int institutionId;final String institutionName; @override State<UserSetup> createState()=>_UserSetupState();}
class _UserSetupState extends State<UserSetup>{ List<AppUser> users=[]; @override void initState(){super.initState();load();}Future<void>load()async{final loaded=await ShopDatabase.instance.users(widget.institutionId);if(mounted)setState(()=>users=loaded);} Future<void> add()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>UserForm(institutionId:widget.institutionId))); await load();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.institutionName)),body:ListView(padding:const EdgeInsets.all(18),children:[const Text('المستخدمون',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const Text('أضف صاحب المؤسسة ثم المحاسب والبائعين والسائقين. السائق يمكن إضافته في كل مؤسسة بنفس رقم الجوال.'),const SizedBox(height:12),if(users.isEmpty)const InfoCard('لم تُضف أي مستخدم بعد.'),...users.map((u)=>Card(child:ListTile(leading:CircleAvatar(child:Icon(roleIcon(u.role))),title:Text(u.name),subtitle:Text('${u.role.title} • ${u.phone}')))),const SizedBox(height:12),OutlinedButton.icon(onPressed:add,icon:const Icon(Icons.person_add),label:const Text('إضافة مستخدم')),if(users.isNotEmpty)...[const SizedBox(height:12),FilledButton(onPressed:()=>Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>UserPicker(institution:Institution(id:widget.institutionId,name:widget.institutionName,commercialRegistration:'',taxNumber:'',address:'',phone:'',email:''))),(_)=>false),child:const Text('متابعة إلى المؤسسة'))]]));}

class UserPicker extends StatefulWidget {
  const UserPicker({super.key, required this.institution});
  final Institution institution;
  @override
  State<UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<UserPicker> {
  late Future<List<AppUser>> users;

  @override
  void initState() {
    super.initState();
    users = ShopDatabase.instance.users(widget.institution.id!);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.institution.name)),
        body: FutureBuilder<List<AppUser>>(
          future: users,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            if (snapshot.data!.isEmpty) {
              return UserSetup(
                institutionId: widget.institution.id!,
                institutionName: widget.institution.name,
              );
            }
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Text('الدخول كمستخدم', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
                const Text('واجهة المؤسسة تتغير حسب الصلاحية.'),
                const SizedBox(height: 12),
                ...snapshot.data!.map(
                  (u) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(roleIcon(u.role))),
                      title: Text(u.name),
                      subtitle: Text(u.role.title),
                      trailing: const Icon(Icons.arrow_back_ios_new),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AppHome(institution: widget.institution, user: u)),
                      ),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserSetup(
                        institutionId: widget.institution.id!,
                        institutionName: widget.institution.name,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.manage_accounts),
                  label: const Text('إدارة المستخدمين'),
                ),
              ],
            );
          },
        ),
      );
}

class UserForm extends StatefulWidget{const UserForm({super.key,required this.institutionId});final int institutionId;@override State<UserForm>createState()=>_UserFormState();}
class _UserFormState extends State<UserForm>{final form=GlobalKey<FormState>();final n=TextEditingController(),p=TextEditingController(),salary=TextEditingController(text:'0'),commission=TextEditingController(text:'50');UserRole role=UserRole.seller;WorkPlan plan=WorkPlan.commission;double d(TextEditingController c)=>double.tryParse(c.text)??0;Future<void>save()async{if(!form.currentState!.validate())return;await ShopDatabase.instance.addUser(AppUser(institutionId:widget.institutionId,name:n.text.trim(),phone:p.text.trim(),role:role,workPlan:role==UserRole.seller?plan:WorkPlan.commission,salary:d(salary),commissionRate:d(commission)/100));if(mounted)Navigator.pop(context);}@override void dispose(){n.dispose();p.dispose();salary.dispose();commission.dispose();super.dispose();}@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('إضافة مستخدم')),body:Form(key:form,child:ListView(padding:const EdgeInsets.all(18),children:[TextFormField(controller:n,decoration:const InputDecoration(labelText:'الاسم'),validator:requiredText),gap,TextFormField(controller:p,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'رقم الجوال'),validator:requiredText),gap,DropdownButtonFormField<UserRole>(value:role,decoration:const InputDecoration(labelText:'الصلاحية'),items:UserRole.values.map((x)=>DropdownMenuItem(value:x,child:Text(x.title))).toList(),onChanged:(x)=>setState(()=>role=x!)),if(role==UserRole.seller)...[gap,DropdownButtonFormField<WorkPlan>(value:plan,decoration:const InputDecoration(labelText:'نظام العمل'),items:WorkPlan.values.map((x)=>DropdownMenuItem(value:x,child:Text(x.title))).toList(),onChanged:(x)=>setState(()=>plan=x!)),gap,numberField(commission,'نسبة العمولة %'),if(plan!=WorkPlan.commission)...[gap,numberField(salary,'الراتب الشهري')]],const SizedBox(height:20),FilledButton(onPressed:save,child:const Text('حفظ'))])));}

class AppHome extends StatefulWidget{const AppHome({super.key,required this.institution,required this.user});final Institution institution;final AppUser user;@override State<AppHome>createState()=>_AppHomeState();}
class _AppHomeState extends State<AppHome>{int index=0;@override Widget build(BuildContext c){final pages=widget.user.role==UserRole.driver?[DriverPage(inst:widget.institution,user:widget.user),ProfilePage(inst:widget.institution,user:widget.user)]:[OverviewPage(inst:widget.institution,user:widget.user),SalePage(inst:widget.institution,user:widget.user),InventoryPage(inst:widget.institution,user:widget.user),SettlementPage(inst:widget.institution,user:widget.user),SettingsPage(inst:widget.institution,user:widget.user)];final labels=widget.user.role==UserRole.driver?['المشاوير','الحساب']:['الرئيسية','بيع','المخزون','التصفية','الإدارة'];return Scaffold(appBar:AppBar(title:Text(widget.institution.name),actions:[IconButton(onPressed:()=>Navigator.pop(c),icon:const Icon(Icons.switch_account))]),body:pages[index],bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:labels.map((x)=>NavigationDestination(icon:Icon(navIcon(x)),label:x)).toList()));}}

class OverviewPage extends StatelessWidget{const OverviewPage({super.key,required this.inst,required this.user});final Institution inst;final AppUser user;@override Widget build(BuildContext c)=>FutureBuilder<List<dynamic>>(future:Future.wait([ShopDatabase.instance.sales(inst.id!),ShopDatabase.instance.inventory(inst.id!)]),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final sales=s.data![0] as List<Sale>;final stock=s.data![1] as List<InventoryItem>;final revenue=sales.fold<double>(0,(a,x)=>a+x.total);return ListView(padding:const EdgeInsets.all(16),children:[Text('مرحبًا ${user.name}',style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const Text('ملخص المؤسسة لهذا الشهر'),gap,Wrap(spacing:10,runSpacing:10,children:[Metric('المبيعات',money(revenue),Icons.payments),Metric('عدد البيوع','${sales.length}',Icons.receipt_long),Metric('تنبيه مخزون','${stock.where((x)=>x.length<=x.lowStockAt).length}',Icons.warning_amber)]),const SizedBox(height:18),const Text('دورة العمل',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const InfoCard('مؤسسة → مستخدمون → موردون → مخزون → بيع → خصم تلقائي → ربح البائع → حساب السائق → تصفية شهرية')]);});}

class InventoryPage extends StatefulWidget{const InventoryPage({super.key,required this.inst,required this.user});final Institution inst;final AppUser user;@override State<InventoryPage>createState()=>_InventoryPageState();}
class _InventoryPageState extends State<InventoryPage>{late Future<List<InventoryItem>> data;@override void initState(){super.initState();refresh();}void refresh()=>data=ShopDatabase.instance.inventory(widget.inst.id!);bool get canEdit=>widget.user.role==UserRole.owner||widget.user.role==UserRole.accountant;@override Widget build(BuildContext c)=>Scaffold(body:FutureBuilder<List<InventoryItem>>(future:data,builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView(padding:const EdgeInsets.all(16),children:[const Text('المخزون',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const Text('سعر الجملة للبائع محدد من المؤسسة/المحاسب.'),gap,...s.data!.map((x)=>Card(child:ListTile(title:Text('${x.name} – ${x.color}'),subtitle:Text('متبقي ${x.length.toStringAsFixed(2)}م • عرض ${x.width}م\nمورد ${money(x.supplierPrice)} / جملة ${money(x.wholesalePrice)} للم²'),isThreeLine:true,trailing:x.length<=x.lowStockAt?const Icon(Icons.warning_amber,color:Colors.orange):null)))]);} ),floatingActionButton:canEdit?FloatingActionButton.extended(onPressed:()async{await Navigator.push(c,MaterialPageRoute(builder:(_)=>InventoryForm(inst:widget.inst)));if(mounted)setState(refresh);},icon:const Icon(Icons.add),label:const Text('صنف جديد')):null);}

class InventoryForm extends StatefulWidget{const InventoryForm({super.key,required this.inst});final Institution inst;@override State<InventoryForm>createState()=>_InventoryFormState();}
class _InventoryFormState extends State<InventoryForm>{late Future<List<Supplier>> supplierFuture;Supplier? supplier;final form=GlobalKey<FormState>();final name=TextEditingController(),color=TextEditingController(),length=TextEditingController(),cost=TextEditingController(),whole=TextEditingController(),low=TextEditingController(text:'10');@override void initState(){super.initState();supplierFuture=ShopDatabase.instance.suppliers(widget.inst.id!);}Future<void>save()async{if(!form.currentState!.validate()||supplier==null){note(context,'اختر المورد');return;}await ShopDatabase.instance.addInventory(InventoryItem(institutionId:widget.inst.id!,supplierId:supplier!.id!,name:name.text.trim(),color:color.text.trim(),length:d(length),supplierPrice:d(cost),wholesalePrice:d(whole),lowStockAt:d(low),createdAt:DateTime.now()));if(mounted)Navigator.pop(context);}@override Widget build(BuildContext c)=>FutureBuilder<List<Supplier>>(future:supplierFuture,builder:(c,s){if(!s.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));final suppliers=s.data!;return Scaffold(appBar:AppBar(title:const Text('إضافة صنف')),body:Form(key:form,child:ListView(padding:const EdgeInsets.all(18),children:[if(suppliers.isEmpty)InfoCard('أضف موردًا أولًا من الإدارة.'),DropdownButtonFormField<Supplier>(value:supplier,decoration:const InputDecoration(labelText:'المورد'),items:suppliers.map((x)=>DropdownMenuItem(value:x,child:Text(x.name))).toList(),onChanged:(x)=>setState(()=>supplier=x)),gap,TextFormField(controller:name,decoration:const InputDecoration(labelText:'اسم القطعة'),validator:requiredText),gap,TextFormField(controller:color,decoration:const InputDecoration(labelText:'اللون'),validator:requiredText),gap,numberField(length,'الطول المتاح بالمتر'),gap,const InputDecorator(decoration:InputDecoration(labelText:'العرض'),child:Text('4 متر (افتراضي)')),gap,numberField(cost,'سعر المورد للم²'),gap,numberField(whole,'سعر الجملة للبائع للم²'),gap,numberField(low,'تنبيه انخفاض المخزون عند (متر)'),const SizedBox(height:20),FilledButton(onPressed:save,child:const Text('حفظ الصنف'))])));});}

class SalePage extends StatefulWidget{const SalePage({super.key,required this.inst,required this.user});final Institution inst;final AppUser user;@override State<SalePage>createState()=>_SalePageState();}
class _SalePageState extends State<SalePage>{InventoryItem? item;AppUser? seller,driver;String customerPay='كاش',driverPay='كاش';final customer=TextEditingController(),length=TextEditingController(),price=TextEditingController(),installation=TextEditingController(text:'0'),glueGallons=TextEditingController(text:'0'),glueCost=TextEditingController(text:'0'),ironPieces=TextEditingController(text:'0'),ironCost=TextEditingController(text:'0'),driverFee=TextEditingController(text:'0');double get l=>d(length);double get area=>l*(item?.width??4);double get total=>area*d(price)+d(installation)+d(glueCost)+d(ironCost)+d(driverFee);double fee()=>total*switch(customerPay){'Visa'=>widget.inst.visaFee,'Tabby'=>widget.inst.tabbyFee,'Tamara'=>widget.inst.tamaraFee,_=>0};Future<void>save()async{if(item==null||seller==null||l<=0||d(price)<=0){note(context,'أكمل القطعة والبائع والطول وسعر البيع');return;}if(l>item!.length){note(context,'الطول غير متاح في المخزون');return;}await ShopDatabase.instance.addSale(Sale(institutionId:widget.inst.id!,inventoryId:item!.id!,sellerId:seller!.id!,driverId:driver?.id,customerName:customer.text.trim(),length:l,width:item!.width,salePrice:d(price),installation:d(installation),glueGallons:d(glueGallons),glueCost:d(glueCost),ironPieces:d(ironPieces),ironCost:d(ironCost),driverFee:d(driverFee),customerPayment:customerPay,driverPayment:driverPay,paymentFee:fee(),createdAt:DateTime.now()));if(!mounted)return;note(context,'تم الحفظ وخصم ${l.toStringAsFixed(2)} متر من المخزون');Navigator.pop(context);}@override Widget build(BuildContext c){if(widget.user.role==UserRole.accountant)return const Center(child:Text('المحاسب يحدد الأسعار ويراجع التسويات؛ البيع للبائع وصاحب المؤسسة.'));return FutureBuilder<List<dynamic>>(future:Future.wait([ShopDatabase.instance.inventory(widget.inst.id!),ShopDatabase.instance.users(widget.inst.id!,role:UserRole.seller),ShopDatabase.instance.users(widget.inst.id!,role:UserRole.driver)]),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final inv=s.data![0]as List<InventoryItem>, sellers=s.data![1]as List<AppUser>,drivers=s.data![2]as List<AppUser>;if(widget.user.role==UserRole.seller&&seller==null)seller=widget.user;return ListView(padding:const EdgeInsets.all(16),children:[const Text('بيع جديد',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),gap,DropdownButtonFormField<InventoryItem>(value:item,decoration:const InputDecoration(labelText:'القطعة واللون'),items:inv.map((x)=>DropdownMenuItem(value:x,child:Text('${x.name} – ${x.color} (${x.length}م)'))).toList(),onChanged:(x)=>setState(()=>item=x)),gap,TextField(controller:customer,decoration:const InputDecoration(labelText:'اسم العميل (اختياري)')),gap,DropdownButtonFormField<AppUser>(value:seller,decoration:const InputDecoration(labelText:'البائع'),items:sellers.map((x)=>DropdownMenuItem(value:x,child:Text(x.name))).toList(),onChanged:(x)=>setState(()=>seller=x)),gap,Row(children:[Expanded(child:numberField(length,'الطول المقصوص م',onChanged:(_)=>setState((){}))),const SizedBox(width:8),Expanded(child:InputDecorator(decoration:const InputDecoration(labelText:'المساحة'),child:Text('${area.toStringAsFixed(2)} م²')))]),gap,numberField(price,'سعر البيع للم²',onChanged:(_)=>setState((){})),gap,numberField(installation,'التركيب'),gap,Row(children:[Expanded(child:numberField(glueGallons,'غراء (جالون)')),const SizedBox(width:8),Expanded(child:numberField(glueCost,'قيمة الغراء'))]),gap,Row(children:[Expanded(child:numberField(ironPieces,'حديد (قطعة)')),const SizedBox(width:8),Expanded(child:numberField(ironCost,'قيمة الحديد'))]),gap,DropdownButtonFormField<AppUser>(value:driver,decoration:const InputDecoration(labelText:'السائق'),items:drivers.map((x)=>DropdownMenuItem(value:x,child:Text(x.name))).toList(),onChanged:(x)=>setState(()=>driver=x)),gap,numberField(driverFee,'حساب المشوار'),gap,Row(children:[Expanded(child:select(customerPay,'دفع العميل',['كاش','شبكة','Visa','Tabby','Tamara'],(x)=>setState(()=>customerPay=x!))),const SizedBox(width:8),Expanded(child:select(driverPay,'دفع السائق',['كاش','تحويل بنكي'],(x)=>setState(()=>driverPay=x!)))]),gap,Card(color:Theme.of(c).colorScheme.primaryContainer,child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[row('إجمالي البيع',money(total)),row('رسوم الدفع',money(fee())),row('الصافي',money(total-fee()),bold:true)]))),const SizedBox(height:15),FilledButton(onPressed:save,child:const Padding(padding:EdgeInsets.all(12),child:Text('حفظ البيع وخصم المخزون')))]);});}}

class SettlementPage extends StatelessWidget { const SettlementPage({super.key,required this.inst,required this.user}); final Institution inst; final AppUser user;
  @override Widget build(BuildContext c)=>FutureBuilder<List<dynamic>>(future:Future.wait([ShopDatabase.instance.users(inst.id!,role:UserRole.seller),ShopDatabase.instance.sales(inst.id!)]),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final sellers=s.data![0]as List<AppUser>,sales=s.data![1]as List<Sale>;return ListView(padding:const EdgeInsets.all(16),children:[const Text('التصفية الشهرية',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const Text('عمولة البائع = (سعر البيع − سعر الجملة) × المساحة × نسبة العمولة.'),gap,...sellers.map((seller){final mine=sales.where((x)=>x.sellerId==seller.id&&sameMonth(x.createdAt)).toList();return FutureBuilder<List<dynamic>>(future:Future.wait([ShopDatabase.instance.ledger(inst.id!,seller.id!),ShopDatabase.instance.inventory(inst.id!)]),builder:(c,x){if(!x.hasData)return const SizedBox();final entries=x.data![0]as List<LedgerEntry>, items=x.data![1]as List<InventoryItem>;double commission=0,glue=0,iron=0;for(final sale in mine){final it=items.firstWhere((i)=>i.id==sale.inventoryId);commission+=(sale.salePrice-it.wholesalePrice)*sale.area*seller.commissionRate;glue+=sale.glueGallons;iron+=sale.ironPieces;}final deductions=entries.fold<double>(0,(a,e)=>a+e.amount);final salary=seller.workPlan==WorkPlan.commission?0.0:seller.salary;final gross=(seller.workPlan==WorkPlan.salary?salary:salary+commission);return Card(child:ExpansionTile(title:Text(seller.name),subtitle:Text('${seller.workPlan.title} • ${mine.length} مبيعات'),trailing:Text(money(gross-deductions),style:const TextStyle(fontWeight:FontWeight.bold)),childrenPadding:const EdgeInsets.all(16),children:[row('راتب',money(salary)),row('عمولات',money(seller.workPlan==WorkPlan.salary?0.0:commission)),row('استهلاك غراء','${glue.toStringAsFixed(2)} جالون'),row('استهلاك حديد','${iron.toStringAsFixed(0)} قطعة'),row('مسحوبات / مصاريف',money(deductions)),const Divider(),row('صافي المستحق',money(gross-deductions),bold:true),if(user.role!=UserRole.seller)Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:()=>openLedger(c,inst,seller),icon:const Icon(Icons.add),label:const Text('تسجيل مسحوب/مصروف/خصم')))]));});})]);}); }

class DriverPage extends StatelessWidget {
  const DriverPage({super.key, required this.inst, required this.user});
  final Institution inst;
  final AppUser user;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Sale>>(
        future: ShopDatabase.instance.sales(inst.id!),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final trips = snapshot.data!.where((x) => x.driverId == user.id).toList();
          final total = trips.fold<double>(0, (a, x) => a + x.driverFee);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('حساب السائق', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
              const Text('هذا الحساب منفصل لهذه المؤسسة.'),
              gap,
              Metric('إجمالي المشاوير', money(total), Icons.local_shipping),
              gap,
              ...trips.map(
                (trip) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.route),
                    title: Text('مشوار ${trip.customerName.isEmpty ? 'عميل' : trip.customerName}'),
                    subtitle: Text('${date(trip.createdAt)} • ${trip.driverPayment}'),
                    trailing: Text(money(trip.driverFee)),
                  ),
                ),
              ),
            ],
          );
        },
      );
}

class ProfilePage extends StatelessWidget {const ProfilePage({super.key,required this.inst,required this.user});final Institution inst;final AppUser user;@override Widget build(BuildContext c)=>Center(child:Column(mainAxisSize:MainAxisSize.min,children:[CircleAvatar(radius:35,child:Icon(roleIcon(user.role),size:34)),const SizedBox(height:10),Text(user.name,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text('${inst.name}\n${user.phone}') ]));}

class SettingsPage extends StatelessWidget {const SettingsPage({super.key,required this.inst,required this.user});final Institution inst;final AppUser user;@override Widget build(BuildContext c){final canEdit=user.role==UserRole.owner||user.role==UserRole.accountant;return ListView(padding:const EdgeInsets.all(16),children:[const Text('الإدارة',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),ListTile(leading:const Icon(Icons.business),title:const Text('بيانات المؤسسة'),subtitle:Text('${inst.commercialRegistration} • ضريبة ${inst.taxNumber}'),),ListTile(enabled:canEdit,leading:const Icon(Icons.people),title:const Text('المستخدمون'),onTap:canEdit?()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>UserSetup(institutionId:inst.id!,institutionName:inst.name))):null),ListTile(enabled:canEdit,leading:const Icon(Icons.local_shipping_outlined),title:const Text('الموردون'),onTap:canEdit?()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>SuppliersPage(inst:inst))):null),const Divider(),const InfoCard('عروض الأسعار والفواتير وPDF/QR ستأتي بعد تثبيت دورة التشغيل الأساسية على بيانات حقيقية.')]);}}

class SuppliersPage extends StatefulWidget {const SuppliersPage({super.key,required this.inst});final Institution inst;@override State<SuppliersPage>createState()=>_SuppliersPageState();}
class _SuppliersPageState extends State<SuppliersPage> {
  late Future<List<Supplier>> data;
  @override
  void initState() { super.initState(); load(); }
  void load() => data = ShopDatabase.instance.suppliers(widget.inst.id!);
  Future<void> add() async {
    final name = TextEditingController(), phone = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مورد جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
          gap,
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ShopDatabase.instance.addSupplier(Supplier(
                institutionId: widget.inst.id!, name: name.text.trim(), phone: phone.text.trim()));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    setState(load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الموردون')),
        body: FutureBuilder<List<Supplier>>(
          future: data,
          builder: (context, snapshot) => !snapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('قائمة الموردين', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ...snapshot.data!.map(
                      (supplier) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.factory_outlined),
                          title: Text(supplier.name),
                          subtitle: Text(supplier.phone),
                          trailing: const Text('المشتريات والمدفوع والآجل\nتظهر مع أوامر الشراء'),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: add, label: const Text('إضافة مورد'), icon: const Icon(Icons.add)),
      );
}

Future<void> openLedger(BuildContext c,Institution inst,AppUser seller)async{final amount=TextEditingController(),noteC=TextEditingController();String kind='مسحوب';await showDialog(context:c,builder:(dialogContext)=>StatefulBuilder(builder:(innerContext,set){return AlertDialog(title:Text('حركة ${seller.name}'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField(value:kind,items:['مسحوب','مصروف','خصم','مدفوعات'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x)=>set(()=>kind=x!)),gap,numberField(amount,'المبلغ'),gap,TextField(controller:noteC,decoration:const InputDecoration(labelText:'ملاحظة'))]),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('إلغاء')),FilledButton(onPressed:()async{if(d(amount)<=0)return;await ShopDatabase.instance.addLedger(LedgerEntry(institutionId:inst.id!,userId:seller.id!,kind:kind,amount:d(amount),note:noteC.text.trim(),createdAt:DateTime.now()));if(dialogContext.mounted)Navigator.pop(dialogContext);},child:const Text('حفظ'))]);}));}

const gap=SizedBox(height:10);
String? requiredText(String? x)=>(x==null||x.trim().isEmpty)?'هذا الحقل مطلوب':null;
double d(TextEditingController c)=>double.tryParse(c.text.replaceAll(',','.'))??0;
TextFormField numberField(TextEditingController c,String label,{ValueChanged<String>? onChanged})=>TextFormField(controller:c,onChanged:onChanged,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:label));
DropdownButtonFormField<String> select(String value,String label,List<String> items,ValueChanged<String?> change)=>DropdownButtonFormField(value:value,decoration:InputDecoration(labelText:label),items:items.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:change);
IconData roleIcon(UserRole role)=>switch(role){UserRole.owner=>Icons.storefront,UserRole.accountant=>Icons.calculate,UserRole.seller=>Icons.point_of_sale,UserRole.driver=>Icons.local_shipping};
IconData navIcon(String s)=>switch(s){'الرئيسية'=>Icons.home_outlined,'بيع'=>Icons.point_of_sale_outlined,'المخزون'=>Icons.inventory_2_outlined,'التصفية'=>Icons.account_balance_wallet_outlined,'الإدارة'=>Icons.settings_outlined,'المشاوير'=>Icons.route_outlined,_=>Icons.person_outline};
String money(double n)=>'${n.toStringAsFixed(2)} ر.س';String date(DateTime x)=>'${x.year}/${x.month.toString().padLeft(2,'0')}/${x.day.toString().padLeft(2,'0')}';bool sameMonth(DateTime x){final n=DateTime.now();return x.year==n.year&&x.month==n.month;}void note(BuildContext c,String x)=>ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text(x)));
Widget row(String a,String b,{bool bold=false})=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(a),Text(b,style:TextStyle(fontWeight:bold?FontWeight.w800:null))]));
class Metric extends StatelessWidget{const Metric(this.title,this.value,this.icon,{super.key});final String title,value;final IconData icon;@override Widget build(BuildContext c)=>Container(width:160,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Theme.of(c).colorScheme.primaryContainer,borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon),const SizedBox(height:8),Text(title),Text(value,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:17))]));}
class InfoCard extends StatelessWidget{const InfoCard(this.text,{super.key});final String text;@override Widget build(BuildContext c)=>Card(color:Theme.of(c).colorScheme.secondaryContainer,child:Padding(padding:const EdgeInsets.all(14),child:Text(text)));}
