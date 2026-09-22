import 'package:flutter/material.dart';
import 'cloud_models.dart';
import 'farsha_repository.dart';

class BranchesPartnersPage extends StatefulWidget {
  const BranchesPartnersPage({super.key, required this.membership, required this.repository});
  final InstitutionMembership membership;
  final FarshaRepository repository;
  @override State<BranchesPartnersPage> createState()=>_BranchesPartnersPageState();
}
class _BranchesPartnersPageState extends State<BranchesPartnersPage>{
  int tab=0;
  late Future<List<BranchRecord>> branches=widget.repository.loadBranches(widget.membership.institutionId);
  late Future<List<PartnerRecord>> partners=widget.repository.loadPartners(widget.membership.institutionId);
  void reload()=>setState((){branches=widget.repository.loadBranches(widget.membership.institutionId);partners=widget.repository.loadPartners(widget.membership.institutionId);});
  Widget field(TextEditingController c,String label)=>Padding(padding:const EdgeInsets.only(bottom:8),child:TextField(controller:c,decoration:InputDecoration(labelText:label)));
  Future<void> addBranch()async{
    final n=TextEditingController(),code=TextEditingController(),city=TextEditingController(),address=TextEditingController(),phone=TextEditingController(),notes=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('إضافة فرع'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[field(n,'اسم الفرع'),field(code,'الكود الداخلي'),field(city,'المدينة'),field(address,'العنوان'),field(phone,'الهاتف'),field(notes,'ملاحظات')])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('إضافة'))]))??false;
    if(ok&&n.text.trim().isNotEmpty&&code.text.trim().isNotEmpty){await widget.repository.createBranch(institutionId:widget.membership.institutionId,name:n.text.trim(),code:code.text.trim(),city:city.text.trim(),address:address.text.trim(),phone:phone.text.trim(),notes:notes.text.trim());reload();}
    for(final x in[n,code,city,address,phone,notes])x.dispose();
  }
  Future<void> addPartner()async{
    final bs=await branches,n=TextEditingController(),phone=TextEditingController(),pct=TextEditingController(text:'0'),notes=TextEditingController();
    String rel='financial_partner',scope='institution';String? branchId;
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:const Text('إضافة شريك'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[field(n,'اسم الشريك'),field(phone,'الهاتف'),DropdownButtonFormField<String>(initialValue:rel,decoration:const InputDecoration(labelText:'نوع العلاقة'),items:const [DropdownMenuItem(value:'owner',child:Text('مالك')),DropdownMenuItem(value:'financial_partner',child:Text('شريك مالي')),DropdownMenuItem(value:'administrative_partner',child:Text('شريك إداري')),DropdownMenuItem(value:'authorized_manager',child:Text('مدير مفوض'))],onChanged:(v)=>setD(()=>rel=v!)),const SizedBox(height:8),DropdownButtonFormField<String>(initialValue:scope,decoration:const InputDecoration(labelText:'النطاق'),items:const [DropdownMenuItem(value:'institution',child:Text('المؤسسة كلها')),DropdownMenuItem(value:'branch',child:Text('فرع محدد'))],onChanged:(v)=>setD(()=>scope=v!)),if(scope=='branch')DropdownButtonFormField<String>(initialValue:branchId,decoration:const InputDecoration(labelText:'الفرع'),items:bs.map((b)=>DropdownMenuItem(value:b.id,child:Text(b.name))).toList(),onChanged:(v)=>setD(()=>branchId=v)),field(pct,'نسبة الاستحقاق %'),field(notes,'ملاحظات')])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('إضافة'))])))??false;
    final p=double.tryParse(pct.text)??0;
    if(ok&&n.text.trim().isNotEmpty&&(scope!='branch'||branchId!=null))await widget.repository.addPartner(institutionId:widget.membership.institutionId,name:n.text.trim(),phone:phone.text.trim(),relationship:rel,scope:scope,branchId:branchId,percentage:p,effectiveFrom:DateTime.now(),notes:notes.text.trim());
    for(final x in[n,phone,pct,notes])x.dispose();reload();
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:SegmentedButton<int>(segments:const [ButtonSegment(value:0,label:Text('الفروع'),icon:Icon(Icons.store)),ButtonSegment(value:1,label:Text('الشركاء'),icon:Icon(Icons.handshake))],selected:{tab},onSelectionChanged:(v)=>setState(()=>tab=v.first))),
    Expanded(child:tab==0?FutureBuilder<List<BranchRecord>>(future:branches,builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView(padding:const EdgeInsets.all(12),children:[FilledButton.icon(onPressed:addBranch,icon:const Icon(Icons.add),label:const Text('إضافة فرع')),const SizedBox(height:10),...s.data!.map((b)=>Card(child:ListTile(leading:Icon(b.status=='active'?Icons.storefront:Icons.storefront_outlined),title:Text(b.name),subtitle:Text(b.code+' • '+b.city+' • '+b.status),trailing:b.isDefault?const Chip(label:Text('الرئيسي')):PopupMenuButton<String>(onSelected:(v)async{await widget.repository.setBranchStatus(b.id,v);reload();},itemBuilder:(_)=>const [PopupMenuItem(value:'active',child:Text('تفعيل')),PopupMenuItem(value:'inactive',child:Text('تعطيل')),PopupMenuItem(value:'closed',child:Text('إغلاق'))]))))]);}):FutureBuilder<List<PartnerRecord>>(future:partners,builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView(padding:const EdgeInsets.all(12),children:[FilledButton.icon(onPressed:addPartner,icon:const Icon(Icons.person_add),label:const Text('إضافة شريك')),const SizedBox(height:10),...s.data!.map((p)=>Card(child:ListTile(leading:const Icon(Icons.handshake_outlined),title:Text(p.name),subtitle:Text(p.relationship+' • '+p.status))))]);}))
  ]);
}
