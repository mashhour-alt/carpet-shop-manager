import 'package:flutter/material.dart';
import 'cloud_models.dart';
import 'farsha_repository.dart';
import 'ui_v2_components.dart';
class MaterialsPage extends StatefulWidget{const MaterialsPage({super.key,required this.membership,required this.repository});final InstitutionMembership membership;final FarshaRepository repository;@override State<MaterialsPage> createState()=>_MaterialsPageState();}
class _MaterialsPageState extends State<MaterialsPage>{
 late Future<List<AddonTypeRecord>> materials=load();Future<List<AddonTypeRecord>> load()async=>(await widget.repository.loadAddonTypes(widget.membership.institutionId)).where((x)=>x.trackStock).toList();void reload()=>setState(()=>materials=load());
 Future<void> receive(AddonTypeRecord a)async{final q=TextEditingController(),cost=TextEditingController(text:a.defaultCostPrice.toStringAsFixed(2)),note=TextEditingController();final ok=await dialog('توريد '+a.name,[TextField(controller:q,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'الكمية ('+a.unit+')')),TextField(controller:cost,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'التكلفة / الوحدة')),TextField(controller:note,decoration:const InputDecoration(labelText:'ملاحظات'))]);final qty=double.tryParse(q.text)??0,co=double.tryParse(cost.text)??0,n=note.text;for(final c in[q,cost,note])c.dispose();if(ok&&qty>0){await widget.repository.receiveAddonStock(widget.membership.institutionId,a.id,qty,co,n);reload();}}
 Future<void> issue(AddonTypeRecord a)async{final sellers=await widget.repository.loadSellers(widget.membership.institutionId);if(sellers.isEmpty)return;String seller=sellers.first.id;final q=TextEditingController(),note=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:Text('تسليم '+a.name+' لبائع'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(initialValue:seller,decoration:const InputDecoration(labelText:'البائع'),items:sellers.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.name))).toList(),onChanged:(v)=>setD(()=>seller=v!)),TextField(controller:q,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'الكمية ('+a.unit+')')),TextField(controller:note,decoration:const InputDecoration(labelText:'ملاحظات / العملية'))]),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('تسليم'))])))??false;final qty=double.tryParse(q.text)??0,n=note.text;q.dispose();note.dispose();if(ok&&qty>0){await widget.repository.issueInternalAddon(widget.membership.institutionId,a.id,seller,qty,n);reload();}}
 Future<bool> dialog(String title,List<Widget> fields)async=>await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(title),content:Column(mainAxisSize:MainAxisSize.min,children:fields.map((x)=>Padding(padding:const EdgeInsets.only(bottom:8),child:x)).toList()),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('حفظ'))]))??false;
 Future<void> editor([AddonTypeRecord? current])async{final name=TextEditingController(text:current?.name??''),unit=TextEditingController(text:current?.unit??'قطعة'),sale=TextEditingController(text:(current?.defaultSalePrice??0).toString()),cost=TextEditingController(text:(current?.defaultCostPrice??0).toString()),low=TextEditingController(text:(current?.lowStockAt??0).toString()),opening=TextEditingController(text:'0');bool track=current?.trackStock??true;String behavior=current?.behavior??'internal_consumable',basis=current?.calculationBasis??'quantity';final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:Text(current==null?'مستلزم جديد':'تعديل ${current.name}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,enabled:current==null,decoration:const InputDecoration(labelText:'الاسم')),TextField(controller:unit,decoration:const InputDecoration(labelText:'الوحدة')),TextField(controller:sale,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'سعر البيع الافتراضي')),TextField(controller:cost,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'التكلفة')),SwitchListTile(value:track,onChanged:(v)=>setD(()=>track=v),title:const Text('تتبع المخزون')),if(track)TextField(controller:low,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'حد التنبيه')),if(current==null&&track)TextField(controller:opening,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الرصيد الافتتاحي'))])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('حفظ'))])));final n=name.text.trim(),u=unit.text.trim(),sp=double.tryParse(sale.text)??-1,cp=double.tryParse(cost.text)??-1,lo=double.tryParse(low.text)??0,op=double.tryParse(opening.text)??0;for(final c in[name,unit,sale,cost,low,opening])c.dispose();if(ok!=true||n.isEmpty||u.isEmpty||sp<0||cp<0)return;await widget.repository.saveAddonTypeV2(institutionId:widget.membership.institutionId,name:n,unit:u,salePrice:sp,costPrice:cp,supplierId:null,behavior:behavior,calculationBasis:basis,trackStock:track,openingStock:op,lowStockAt:lo,customerVisible:current?.customerVisible??false,chargeToSeller:current?.chargeToSeller??false);reload();}
 Future<void> details(AddonTypeRecord a)async{final moves=await widget.repository.loadAddonMovements(widget.membership.institutionId,a.id);if(!mounted)return;await showModalBottomSheet(context:context,isScrollControlled:true,builder:(d)=>DraggableScrollableSheet(expand:false,builder:(_,scroll)=>ListView(controller:scroll,padding:const EdgeInsets.all(16),children:[Text(a.name,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Text('الرصيد الحالي: ${a.stockQuantity.toStringAsFixed(2)} ${a.unit}'),const Divider(),const Text('الحركات والاستهلاك',style:TextStyle(fontWeight:FontWeight.bold)),if(moves.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('لا توجد حركات بعد.')),...moves.map((m)=>ListTile(contentPadding:EdgeInsets.zero,title:Text((m['movement_type'] as String)),subtitle:Text('${m['note']??''}\n${m['created_at'].toString().substring(0,16)}'),trailing:Text('${(m['quantity_delta'] as num).toStringAsFixed(2)} ${a.unit}')))])));}
 @override
 Widget build(BuildContext context)=>FutureBuilder<List<AddonTypeRecord>>(
   future:materials,
   builder:(context,s){
     if(!s.hasData)return const Center(child:CircularProgressIndicator());
     final rows=s.data!;
     String category(AddonTypeRecord a){
       final n=a.name.toLowerCase();
       if(n.contains('لباد')||n.contains('felt'))return 'لباد';
       if(n.contains('غراء')||n.contains('glue'))return 'غراء';
       if(n.contains('حديد')||n.contains('شريح')||n.contains('strip'))return 'حديد وشرائح';
       return 'مستلزمات أخرى';
     }
     final groups=<String,List<AddonTypeRecord>>{};
     for(final a in rows){groups.putIfAbsent(category(a),()=>[]).add(a);}
     final children=<Widget>[
       const Text('المستلزمات',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),
       const SizedBox(height:4),
       Text('المخزون والاستهلاك الداخلي منظم حسب النوع.',style:TextStyle(color:Colors.grey.shade700)),
       const SizedBox(height:16),
     ];
     if(rows.isEmpty){
       children.add(const EmptyState(title:'لا توجد مستلزمات مضافة',subtitle:'أضف لباد أو غراء أو حديد من إعدادات المخزون.',icon:Icons.handyman_outlined));
     }else{
       for(final group in groups.entries){
         children.add(SectionTitle(group.key));
         for(final a in group.value){
           children.add(Padding(
             padding:const EdgeInsets.only(bottom:8),
             child:Card(child:ListTile(
               leading:Container(width:40,height:40,decoration:BoxDecoration(color:(a.isLow?warningOrange:positiveGreen).withValues(alpha:.1),borderRadius:BorderRadius.circular(12)),child:Icon(a.isLow?Icons.warning_amber:Icons.handyman_outlined,color:a.isLow?warningOrange:positiveGreen)),
               title:Text(a.name,style:const TextStyle(fontWeight:FontWeight.w800)),
               subtitle:Text((a.behavior=='internal_consumable'?'استخدام داخلي':'للعميل')+' • '+a.stockQuantity.toStringAsFixed(2)+' '+a.unit+(a.isLow?' • مخزون منخفض':'')),
               onTap:()=>details(a),
               trailing:PopupMenuButton<String>(
                 onSelected:(v){if(v=='receive')receive(a);else if(v=='issue')issue(a);else if(v=='edit')editor(a);else details(a);},
                 itemBuilder:(_)=>[
                   const PopupMenuItem(value:'details',child:Text('التفاصيل والحركات')),
                   if(widget.membership.role!=InstitutionRole.seller)const PopupMenuItem(value:'edit',child:Text('تعديل')),
                   const PopupMenuItem(value:'receive',child:Text('توريد مخزون')),
                   if(a.behavior=='internal_consumable')const PopupMenuItem(value:'issue',child:Text('تسليم لبائع')),
                 ],
               ),
             )),
           ));
         }
       }
     }
     final manager=widget.membership.role!=InstitutionRole.seller;
     return Scaffold(body:ListView(padding:const EdgeInsets.all(16),children:children.map((w)=>w).toList()),floatingActionButton:manager?FloatingActionButton.extended(onPressed:()=>editor(),icon:const Icon(Icons.add),label:const Text('مستلزم جديد')):null);
   },
 );

}
