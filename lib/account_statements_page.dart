import 'package:flutter/material.dart';
import 'cloud_models.dart';
import 'farsha_repository.dart';
const sar='⃁';
String money(double v)=>sar+' '+v.toStringAsFixed(2);
class AccountStatementsPage extends StatefulWidget{
 const AccountStatementsPage({super.key,required this.membership,required this.repository,this.personalSeller=false});
 final InstitutionMembership membership;final FarshaRepository repository;final bool personalSeller;
 @override State<AccountStatementsPage> createState()=>_AccountStatementsPageState();
}
class _AccountStatementsPageState extends State<AccountStatementsPage>{
 String party='seller';String range='month';final search=TextEditingController();
 (DateTime,DateTime) dates(){final n=DateTime.now(),d=DateTime(DateTime.now().year,DateTime.now().month,DateTime.now().day);return switch(range){'today'=>(d,d.add(const Duration(days:1))),'week'=>(d.subtract(Duration(days:d.weekday-1)),d.add(const Duration(days:1))),'previous'=>(DateTime(n.year,n.month-1,1),DateTime(n.year,n.month,1)),_=>(DateTime(n.year,n.month,1),DateTime(n.year,n.month+1,1))};}
 @override void dispose(){search.dispose();super.dispose();}
 @override Widget build(BuildContext context){
  if(widget.personalSeller)return StatementDetailPage(membership:widget.membership,repository:widget.repository,party:'seller',partyId:widget.repository.userId,partyName:'حسابي',from:dates().$1,to:dates().$2,allowEntry:false);
  return Column(children:[
   Padding(padding:const EdgeInsets.all(12),child:SegmentedButton<String>(segments:const [ButtonSegment(value:'seller',label:Text('البائعون')),ButtonSegment(value:'driver',label:Text('السائقون')),ButtonSegment(value:'supplier',label:Text('الموردون'))],selected:{party},onSelectionChanged:(v)=>setState(()=>party=v.first))),
   Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Row(children:[Expanded(child:DropdownButtonFormField<String>(initialValue:range,decoration:const InputDecoration(labelText:'الفترة'),items:const [DropdownMenuItem(value:'today',child:Text('اليوم')),DropdownMenuItem(value:'week',child:Text('هذا الأسبوع')),DropdownMenuItem(value:'month',child:Text('هذا الشهر')),DropdownMenuItem(value:'previous',child:Text('الشهر السابق'))],onChanged:(v)=>setState(()=>range=v!))),const SizedBox(width:8),Expanded(child:TextField(controller:search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'بحث بالاسم',prefixIcon:Icon(Icons.search))))])),
   Expanded(child:FutureBuilder<List<AccountSummaryRecord>>(
     future:widget.repository.loadAccountSummaries(widget.membership.institutionId,party,dates().$1,dates().$2),
     builder:(c,s){
       if(!s.hasData)return const Center(child:CircularProgressIndicator());
       final rows=s.data!.where((x)=>x.name.contains(search.text.trim())).toList();
       return ListView(padding:const EdgeInsets.all(12),children:rows.map<Widget>((x){
         final subtitle=(party=='seller'?x.count.toString()+' عملية • مستحق ':party=='driver'?x.count.toString()+' مشوار • الإجمالي ':x.count.toString()+' توريد • ورد ')+money(x.gross)+' • مدفوع '+money(x.paid);
         return Card(child:ListTile(title:Text(x.name,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(subtitle),trailing:Text('المتبقي\\n'+money(x.balance),textAlign:TextAlign.center),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>StatementDetailPage(membership:widget.membership,repository:widget.repository,party:party,partyId:x.id,partyName:x.name,from:dates().$1,to:dates().$2,allowEntry:true)))));
       }).toList());
     },
   )),
  ]);
 }
}
class StatementDetailPage extends StatefulWidget{
 const StatementDetailPage({super.key,required this.membership,required this.repository,required this.party,required this.partyId,required this.partyName,required this.from,required this.to,required this.allowEntry});
 final InstitutionMembership membership;final FarshaRepository repository;final String party,partyId,partyName;final DateTime from,to;final bool allowEntry;
 @override State<StatementDetailPage> createState()=>_StatementDetailPageState();
}
class _StatementDetailPageState extends State<StatementDetailPage>{
 late Future<List<AccountMovementRecord>> data=load();Future<List<AccountMovementRecord>> load()=>widget.repository.loadAccountStatement(widget.membership.institutionId,widget.party,widget.partyId,widget.from,widget.to);void reload()=>setState(()=>data=load());
 Future<void> addEntry()async{final amount=TextEditingController(),note=TextEditingController(),ref=TextEditingController();String type=widget.party=='seller'?'withdrawal':'payment',method='cash';final options=widget.party=='seller'?const {'withdrawal':'مسحوب','expense':'مصروف/عهدة','deduction':'خصم','payment':'تسوية'}:widget.party=='driver'?const {'payment':'دفعة','settlement':'تسوية','adjustment':'تعديل'}:const {'payment':'سداد','return':'مرتجع','settlement':'تسوية','adjustment':'تعديل'};final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:Text('حركة • '+widget.partyName),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(initialValue:type,decoration:const InputDecoration(labelText:'نوع الحركة'),items:options.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v)=>setD(()=>type=v!)),const SizedBox(height:8),TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'المبلغ')),if(widget.party!='seller')...[const SizedBox(height:8),DropdownButtonFormField<String>(initialValue:method,decoration:const InputDecoration(labelText:'طريقة الدفع'),items:const [DropdownMenuItem(value:'cash',child:Text('كاش')),DropdownMenuItem(value:'bank_transfer',child:Text('تحويل بنكي'))],onChanged:(v)=>method=v!)],const SizedBox(height:8),TextField(controller:ref,decoration:const InputDecoration(labelText:'المرجع')),const SizedBox(height:8),TextField(controller:note,decoration:const InputDecoration(labelText:'ملاحظات'))]),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('حفظ'))])));
  final a=double.tryParse(amount.text)??0,n=note.text,r=ref.text;for(final c in[amount,note,ref])c.dispose();if(ok!=true||a<=0)return;if(widget.party=='seller')await widget.repository.addSellerLedger(institutionId:widget.membership.institutionId,sellerId:widget.partyId,kind:type,amount:a,note:n);else if(widget.party=='driver')await widget.repository.recordDriverAccountEntry(institutionId:widget.membership.institutionId,driverId:widget.partyId,type:type,amount:a,method:method,reference:r,note:n);else await widget.repository.recordSupplierAccountEntry(institutionId:widget.membership.institutionId,supplierId:widget.partyId,type:type,amount:a,method:method,reference:r,note:n);reload();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('كشف حساب • '+widget.partyName)),floatingActionButton:widget.allowEntry?FloatingActionButton.extended(onPressed:addEntry,icon:const Icon(Icons.add),label:const Text('حركة')):null,body:FutureBuilder<List<AccountMovementRecord>>(future:data,builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final rows=s.data!,gross=rows.where((x)=>x.amount>0).fold<double>(0,(a,b)=>a+b.amount),paid=-rows.where((x)=>x.amount<0).fold<double>(0,(a,b)=>a+b.amount),balance=rows.isEmpty?0.0:rows.first.balance;return ListView(padding:const EdgeInsets.all(12),children:[Wrap(spacing:8,runSpacing:8,children:[metric('إجمالي المستحق',money(gross)),metric('المسحوب/المدفوع',money(paid)),metric('المتبقي',money(balance))]),const SizedBox(height:14),...rows.map((x)=>Card(child:ListTile(title:Text(x.description),subtitle:Text(x.time.toString().substring(0,16)+' • '+x.createdBy+'\nمرجع: '+x.reference),trailing:Text((x.amount>=0?'+':'')+money(x.amount)+'\nرصيد '+money(x.balance),textAlign:TextAlign.end))))]);}));
 Widget metric(String a,String b)=>SizedBox(width:160,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[Text(a),Text(b,style:const TextStyle(fontWeight:FontWeight.bold))]))));
}
