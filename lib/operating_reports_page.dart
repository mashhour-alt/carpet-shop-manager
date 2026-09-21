import 'package:flutter/material.dart';
import 'cloud_models.dart';
import 'farsha_repository.dart';

enum ReportRange { today,yesterday,week,month,previousMonth,custom }

class OperatingReportsPage extends StatefulWidget {
  const OperatingReportsPage({super.key,required this.membership,required this.repository});
  final InstitutionMembership membership; final FarshaRepository repository;
  @override State<OperatingReportsPage> createState()=>_OperatingReportsPageState();
}
class _OperatingReportsPageState extends State<OperatingReportsPage> {
  ReportRange range=ReportRange.today; final search=TextEditingController(); DateTime? customFrom,customTo;
  late Future<(OperatingSummary,List<OperatingSaleRecord>,List<Map<String,dynamic>>,List<PersonOption>)> data=_load();
  (DateTime,DateTime) _dates(){final n=DateTime.now();final d=DateTime(n.year,n.month,n.day);return switch(range){
    ReportRange.today=>(d,d.add(const Duration(days:1))),ReportRange.yesterday=>(d.subtract(const Duration(days:1)),d),
    ReportRange.week=>(d.subtract(Duration(days:d.weekday-1)),d.add(const Duration(days:1))),
    ReportRange.month=>(DateTime(n.year,n.month,1),DateTime(n.year,n.month+1,1)),
    ReportRange.previousMonth=>(DateTime(n.year,n.month-1,1),DateTime(n.year,n.month,1)),ReportRange.custom=>(customFrom??d,(customTo??d).add(const Duration(days:1))),};}
  Future<(OperatingSummary,List<OperatingSaleRecord>,List<Map<String,dynamic>>,List<PersonOption>)> _load() async {final (from,to)=_dates();final a=await widget.repository.loadOperatingSummary(widget.membership.institutionId,from,to);final b=await widget.repository.loadOperatingSales(widget.membership.institutionId,from,to,search:search.text);final p=await widget.repository.loadPaymentReport(widget.membership.institutionId,from,to);final sellers=await widget.repository.loadSellers(widget.membership.institutionId);return(a,b,p,sellers);}
  void reload()=>setState(()=>data=_load());
  @override void dispose(){search.dispose();super.dispose();}
  String money(double v)=>v.toStringAsFixed(2)+' ر.س';
  String label(ReportRange r)=>switch(r){ReportRange.today=>'اليوم',ReportRange.yesterday=>'أمس',ReportRange.week=>'هذا الأسبوع',ReportRange.month=>'هذا الشهر',ReportRange.previousMonth=>'الشهر السابق',ReportRange.custom=>'فترة مخصصة'};
  @override Widget build(BuildContext context)=>FutureBuilder<(OperatingSummary,List<OperatingSaleRecord>,List<Map<String,dynamic>>,List<PersonOption>)>(future:data,builder:(context,s){
    if(!s.hasData)return const Center(child:CircularProgressIndicator());final summary=s.data!.$1;final sales=s.data!.$2;final paymentRows=s.data!.$3;final sellers=s.data!.$4;
    return ListView(padding:const EdgeInsets.all(16),children:[
      Row(children:[Expanded(child:DropdownButtonFormField<ReportRange>(initialValue:range,decoration:const InputDecoration(labelText:'الفترة'),items:ReportRange.values.map((r)=>DropdownMenuItem(value:r,child:Text(label(r)))).toList(),onChanged:(v) async {range=v!;if(range==ReportRange.custom){final now=DateTime.now();final picked=await showDateRangePicker(context:context,firstDate:DateTime(now.year-5),lastDate:DateTime(now.year+1),initialDateRange:DateTimeRange(start:customFrom??now,end:customTo??now));if(picked!=null){customFrom=picked.start;customTo=picked.end;}}reload();})),const SizedBox(width:8),IconButton(onPressed:reload,icon:const Icon(Icons.refresh))]),
      const SizedBox(height:12),TextField(controller:search,decoration:InputDecoration(labelText:'بحث بالصنف أو اللون أو البائع أو الملاحظات',suffixIcon:IconButton(onPressed:reload,icon:const Icon(Icons.search))),onSubmitted:(_)=>reload()),
      const SizedBox(height:16),const Text('ملخص التشغيل',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:10),
      Wrap(spacing:8,runSpacing:8,children:[_metric('المبيعات',money(summary.salesAmount)),_metric('الأمتار',summary.totalLength.toStringAsFixed(2)+' م'),_metric('المساحة',summary.totalArea.toStringAsFixed(2)+' م²'),_metric('العمليات',summary.saleCount.toString()),_metric('تكلفة البضاعة',money(summary.merchandiseCost)),_metric('تكلفة الإضافات',money(summary.addonCost)),_metric('السائقين',money(summary.driverCost)),_metric('رسوم الدفع',money(summary.paymentFees)),_metric('الربح التشغيلي',money(summary.grossProfit))]),
      const SizedBox(height:18),const Text('التحصيل حسب طريقة الدفع',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      ...summary.payments.entries.where((e)=>e.value!=0).map((e){final count=paymentRows.where((p)=>p['method']==e.key).map((p)=>p['sale_id']).toSet().length;return ListTile(dense:true,title:Text(_payment(e.key)),subtitle:Text(count.toString()+' عملية'),trailing:Text(money(e.value)));}),
      if(sellers.isNotEmpty)...[const Divider(height:28),const Text('أداء البائعين',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),...sellers.map((seller)=>FutureBuilder<SellerPerformanceRecord>(future:widget.repository.loadSellerPerformance(widget.membership.institutionId,seller.id,_dates().$1,_dates().$2),builder:(context,p){if(!p.hasData)return const SizedBox.shrink();final x=p.data!;return Card(child:ListTile(title:Text(seller.name),subtitle:Text(x.saleCount.toString()+' عملية • '+x.totalLength.toStringAsFixed(1)+' م • '+x.totalArea.toStringAsFixed(1)+' م²\nعمولة '+money(x.commission)+' • صافي '+money(x.netDue)),trailing:Text(money(x.salesAmount))));}))],
      const Divider(height:28),Text('المبيعات ('+sales.length.toString()+')',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      ...sales.map((x)=>Card(child:ExpansionTile(title:Text(x.itemName+' • '+money(x.salesAmount)),subtitle:Text(x.length.toStringAsFixed(2)+' م • '+x.area.toStringAsFixed(2)+' م² • '+x.sellerName),children:[Padding(padding:const EdgeInsets.fromLTRB(16,0,16,16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[_row('الإضافات',x.addons.isEmpty?'—':x.addons),_row('الدفع',x.payments),_row('السائق',x.driverName.isEmpty?'—':x.driverName+' • '+money(x.driverCost)),_row('تكلفة البضاعة',money(x.merchandiseCost)),_row('تكلفة الإضافات',money(x.addonCost)),_row('إجمالي التكلفة',money(x.totalCost)),_row('الربح',money(x.grossProfit)),if(x.notes.isNotEmpty)_row('ملاحظات',x.notes),if(x.status!='completed')_row('الحالة',x.status)]))]))),
    ]);});
  Widget _metric(String t,String v)=>SizedBox(width:160,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[Text(t,textAlign:TextAlign.center),const SizedBox(height:5),Text(v,style:const TextStyle(fontWeight:FontWeight.bold))]))));
  Widget _row(String a,String b)=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[SizedBox(width:110,child:Text(a,style:const TextStyle(fontWeight:FontWeight.bold))),Expanded(child:Text(b))]));
  String _payment(String x)=>switch(x){'cash'=>'كاش','network'=>'شبكة','bank_transfer'=>'تحويل بنكي','visa'=>'Visa','tamara'=>'تمارا','tabby'=>'تابي',_=>'أخرى'};
}
