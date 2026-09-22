import 'package:flutter/material.dart';

import 'account_statements_page.dart';
import 'branch_report_page.dart';
import 'branches_partners_page.dart';
import 'cloud_models.dart';
import 'documents_page.dart';
import 'farsha_repository.dart';
import 'home_pages.dart' show MembersPage;
import 'materials_page.dart';
import 'operating_reports_page.dart';
import 'operations_pages.dart';
import 'ui_v2_components.dart';

class FarshaShellV2 extends StatefulWidget {
  const FarshaShellV2({super.key, required this.membership, required this.repository, required this.profile});
  final InstitutionMembership membership;
  final FarshaRepository repository;
  final UserProfile profile;

  @override State<FarshaShellV2> createState() => _FarshaShellV2State();
}

class _FarshaShellV2State extends State<FarshaShellV2> {
  int index = 0;
  late final Future<Map<String, dynamic>?> partnerContext = widget.repository.loadMyPartnerContext(widget.membership.institutionId);

  void go(int value) => setState(() => index = value);

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: partnerContext,
    builder: (context, partnerSnapshot) {
      final isPartner = partnerSnapshot.data != null && widget.membership.role != InstitutionRole.owner;
      final pages = <Widget>[
        if (isPartner)
          PartnerDashboardV2(profile: widget.profile, membership: widget.membership, repository: widget.repository, contextData: partnerSnapshot.data!)
        else
          RoleDashboardV2(profile: widget.profile, membership: widget.membership, repository: widget.repository, onNavigate: go),
        SalesHubV2(membership: widget.membership, repository: widget.repository),
        InventoryHubV2(membership: widget.membership, repository: widget.repository),
        AccountsHubV2(membership: widget.membership, repository: widget.repository),
        MoreHubV2(membership: widget.membership, repository: widget.repository),
      ];
      return Scaffold(
        body: SafeArea(child: IndexedStack(index: index, children: pages)),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: go,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'البيع'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'المخزون'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'الحسابات'),
            NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'المزيد'),
          ],
        ),
      );
    },
  );
}

class RoleDashboardV2 extends StatelessWidget {
  const RoleDashboardV2({super.key, required this.profile, required this.membership, required this.repository, required this.onNavigate});
  final UserProfile profile;
  final InstitutionMembership membership;
  final FarshaRepository repository;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) => switch (membership.role) {
    InstitutionRole.owner => OwnerDashboardV2(profile: profile, membership: membership, repository: repository, onNavigate: onNavigate),
    InstitutionRole.accountant => AccountantDashboardV2(profile: profile, membership: membership, repository: repository, onNavigate: onNavigate),
    InstitutionRole.seller => SellerDashboardV2(profile: profile, membership: membership, repository: repository, onNavigate: onNavigate),
  };
}

class _DashboardData {
  const _DashboardData({required this.summary, required this.sales, required this.branches, required this.branchReport, required this.inventory, required this.recent, required this.hasAccountant, required this.expenses});
  final OperatingSummary summary;
  final List<OperatingSaleRecord> sales;
  final List<BranchRecord> branches;
  final List<BranchReportRecord> branchReport;
  final List<InventoryRecord> inventory;
  final List<Map<String, dynamic>> recent;
  final bool hasAccountant;
  final List<Map<String, dynamic>> expenses;
}

class OwnerDashboardV2 extends StatefulWidget {
  const OwnerDashboardV2({super.key, required this.profile, required this.membership, required this.repository, required this.onNavigate});
  final UserProfile profile;
  final InstitutionMembership membership;
  final FarshaRepository repository;
  final ValueChanged<int> onNavigate;
  @override State<OwnerDashboardV2> createState() => _OwnerDashboardV2State();
}

class _OwnerDashboardV2State extends State<OwnerDashboardV2> {
  DashboardPeriod period = DashboardPeriod.month;
  DateTimeRange? custom;
  String? branchId;
  String branchMetric = 'sales';
  late Future<_DashboardData> data = load();

  Future<_DashboardData> load() async {
    final range = periodRange(period, custom: custom);
    final branches = await widget.repository.loadAccessibleBranches(widget.membership.institutionId);
    final results = await Future.wait<dynamic>([
      widget.repository.loadBranchOperatingSummary(widget.membership.institutionId, branchId, range.from, range.to),
      widget.repository.loadDashboardSales(widget.membership.institutionId, range.from, range.to, branchId: branchId),
      widget.repository.loadBranchReport(widget.membership.institutionId, range.from, range.to),
      widget.repository.loadInventory(widget.membership.institutionId),
      widget.repository.loadRecentActivity(widget.membership.institutionId, branchId: branchId),
      widget.repository.hasActiveAccountant(widget.membership.institutionId),
      widget.repository.loadExpenses(widget.membership.institutionId, range.from, range.to, branchId: branchId),
    ]);
    return _DashboardData(
      summary: results[0] as OperatingSummary,
      sales: results[1] as List<OperatingSaleRecord>,
      branches: branches,
      branchReport: results[2] as List<BranchReportRecord>,
      inventory: results[3] as List<InventoryRecord>,
      recent: results[4] as List<Map<String, dynamic>>,
      hasAccountant: results[5] as bool,
      expenses: results[6] as List<Map<String, dynamic>>,
    );
  }

  void reload() => setState(() => data = load());

  Future<void> changePeriod(DashboardPeriod p) async {
    if (p == DashboardPeriod.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 4), lastDate: DateTime(now.year + 1), initialDateRange: custom ?? DateTimeRange(start: now, end: now));
      if (picked == null) return;
      custom = picked;
    }
    period = p;
    reload();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async => reload(),
    child: FutureBuilder<_DashboardData>(
      future: data,
      builder: (context, s) {
        if (!s.hasData) return const _DashboardSkeleton();
        final d = s.data!;
        final expenseTotal = d.expenses.fold<double>(0, (a, b) => a + (b['amount'] as num).toDouble());
        final collected = d.summary.payments.values.fold<double>(0, (a, b) => a + b);
        final due = (d.summary.salesAmount - collected).clamp(0.0, double.infinity).toDouble();
        final net = d.summary.grossProfit - expenseTotal;
        final trend = _dailySeries(d.sales);
        final low = d.inventory.where((x) => x.isLow && (branchId == null || x.branchId == branchId)).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          DashboardHeader(name: widget.profile.fullName, institution: widget.membership.institutionName, branches: d.branches, selectedBranchId: branchId, onBranchChanged: d.branches.length > 1 ? (v) { branchId = v; reload(); } : null),
          const SizedBox(height: 14),
          PeriodSelector(value: period, onChanged: changePeriod),
          const SizedBox(height: 14),
          if (d.summary.saleCount == 0)
            EmptyState(title: 'لا توجد مبيعات في هذه الفترة', subtitle: 'ابدأ أول عملية بيع وسيظهر أداء المؤسسة هنا.', icon: Icons.point_of_sale_outlined, actionLabel: 'بيعة جديدة', onAction: () => widget.onNavigate(1))
          else ...[
            HeroMetricCard(title: 'إجمالي المبيعات', value: farshaMoney(d.summary.salesAmount), caption: '${d.summary.saleCount} عملية • ${d.summary.totalLength.toStringAsFixed(1)} متر', child: MiniLineChart(values: trend, color: Colors.white, height: 76)),
            const SizedBox(height: 12),
            KpiGrid(children: [
              KpiCard(title: 'صافي الربح', value: farshaMoney(net), icon: Icons.auto_graph_rounded, accent: positiveGreen),
              KpiCard(title: 'المحصل', value: farshaMoney(collected), icon: Icons.payments_outlined, accent: infoBlue),
              KpiCard(title: 'المصروفات', value: farshaMoney(expenseTotal), icon: Icons.receipt_long_outlined, accent: warningOrange),
              KpiCard(title: 'غير المحصل', value: farshaMoney(due), icon: Icons.schedule_rounded, accent: due > 0 ? dangerRed : positiveGreen),
            ]),
          ],
          const SizedBox(height: 20),
          const SectionTitle('إجراءات سريعة'),
          QuickActionsRow(actions: [
            QuickActionData('بيعة جديدة', Icons.add_shopping_cart, () => widget.onNavigate(1)),
            QuickActionData('عرض سعر', Icons.request_quote_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentsPage(membership: widget.membership, repository: widget.repository))), accent: infoBlue),
            QuickActionData('توريد', Icons.local_shipping_outlined, () => widget.onNavigate(2), accent: positiveGreen),
            QuickActionData('مصروف', Icons.receipt_long_outlined, () => widget.onNavigate(3), accent: warningOrange),
            if (d.branches.length > 1) QuickActionData('تحويل مخزون', Icons.swap_horiz_rounded, () => widget.onNavigate(2), accent: partnerPurple),
          ]),
          if (d.summary.saleCount > 0) ...[
            const SizedBox(height: 22),
            const SectionTitle('طرق الدفع'),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: DonutChart(values: d.summary.payments, labels: paymentLabels))),
          ],
          if (d.branches.length > 1) ...[
            const SizedBox(height: 22),
            Row(children: [
              const Expanded(child: SectionTitle('أداء الفروع')),
              DropdownButton<String>(value: branchMetric, underline: const SizedBox.shrink(), items: const [
                DropdownMenuItem(value: 'sales', child: Text('المبيعات')),
                DropdownMenuItem(value: 'profit', child: Text('الربح')),
                DropdownMenuItem(value: 'length', child: Text('الأمتار')),
              ], onChanged: (v) => setState(() => branchMetric = v!)),
            ]),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: BranchBarChart(rows: d.branchReport, metric: branchMetric))),
          ],
          if (!d.hasAccountant) ...[
            const SizedBox(height: 22),
            _OwnerAccountingSection(membership: widget.membership, repository: widget.repository, from: periodRange(period, custom: custom).from, to: periodRange(period, custom: custom).to, onAccounts: () => widget.onNavigate(3)),
          ],
          const SizedBox(height: 22),
          const SectionTitle('تنبيهات تحتاج انتباهك'),
          if (low.isEmpty && due == 0)
            const EmptyState(title: 'كل شيء هادئ حاليًا', subtitle: 'لا توجد تنبيهات مخزون أو مبالغ غير محصلة في الفترة.', icon: Icons.check_circle_outline)
          else ...[
            ...low.take(4).map((x) => _AlertTile(icon: Icons.inventory_2_outlined, color: warningOrange, title: 'مخزون منخفض', subtitle: '${x.name} • ${x.color} — ${x.remainingLength.toStringAsFixed(1)} م')),
            if (due > 0) _AlertTile(icon: Icons.schedule_rounded, color: dangerRed, title: 'مبلغ غير محصل', subtitle: farshaMoney(due)),
          ],
          const SizedBox(height: 22),
          const SectionTitle('آخر العمليات'),
          if (d.recent.isEmpty) const EmptyState(title: 'لا توجد عمليات حديثة', icon: Icons.history_rounded) else ...d.recent.take(6).map((x) {
            final seller = x['profiles'] as Map<String, dynamic>?;
            return ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(backgroundColor: Color(0xffF3E9EA), child: Icon(Icons.shopping_bag_outlined, color: farshaBurgundy)), title: Text((x['customer_name'] as String?)?.isNotEmpty == true ? x['customer_name'] as String : 'عملية بيع'), subtitle: Text('${seller?['full_name'] ?? '—'} • ${DateTime.parse(x['created_at'] as String).toLocal().toString().substring(0,16)}'), trailing: Text(farshaMoney((x['total'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.w800)));
          }),
        ]);
      },
    ),
  );
}

class _OwnerAccountingSection extends StatelessWidget {
  const _OwnerAccountingSection({required this.membership, required this.repository, required this.from, required this.to, required this.onAccounts});
  final InstitutionMembership membership;
  final FarshaRepository repository;
  final DateTime from, to;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: infoBlue.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.account_balance_outlined, color: infoBlue)), const SizedBox(width: 10), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('الإدارة المالية اليومية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), Text('لا يوجد محاسب نشط — أدوات المحاسب ظاهرة لك هنا.', style: TextStyle(fontSize: 11, color: Colors.grey))]))]),
    const SizedBox(height: 14),
    FutureBuilder<List<AccountSummaryRecord>>(
      future: repository.loadAccountSummaries(membership.institutionId, 'supplier', from, to),
      builder: (_, s) {
        final due = (s.data ?? const <AccountSummaryRecord>[]).fold<double>(0, (a, b) => a + b.balance);
        return ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.local_shipping_outlined), title: const Text('مستحقات الموردين'), trailing: Text(farshaMoney(due), style: const TextStyle(fontWeight: FontWeight.w800)));
      },
    ),
    FutureBuilder<List<AccountSummaryRecord>>(
      future: repository.loadAccountSummaries(membership.institutionId, 'driver', from, to),
      builder: (_, s) {
        final due = (s.data ?? const <AccountSummaryRecord>[]).fold<double>(0, (a, b) => a + b.balance);
        return ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.route_outlined), title: const Text('مستحقات السائقين'), trailing: Text(farshaMoney(due), style: const TextStyle(fontWeight: FontWeight.w800)));
      },
    ),
    const SizedBox(height: 6),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: onAccounts, icon: const Icon(Icons.account_balance_wallet_outlined), label: const Text('فتح الحسابات والتسويات'))),
  ])));
}

class AccountantDashboardV2 extends StatefulWidget {
  const AccountantDashboardV2({super.key, required this.profile, required this.membership, required this.repository, required this.onNavigate});
  final UserProfile profile;
  final InstitutionMembership membership;
  final FarshaRepository repository;
  final ValueChanged<int> onNavigate;
  @override State<AccountantDashboardV2> createState() => _AccountantDashboardV2State();
}

class _AccountantDashboardV2State extends State<AccountantDashboardV2> {
  DashboardPeriod period = DashboardPeriod.month;
  DateTimeRange? custom;
  late Future<(OperatingSummary,List<OperatingSaleRecord>,List<Map<String,dynamic>>,List<BranchRecord>)> data = load();
  Future<(OperatingSummary,List<OperatingSaleRecord>,List<Map<String,dynamic>>,List<BranchRecord>)> load() async {
    final r = periodRange(period, custom: custom);
    final x = await Future.wait<dynamic>([
      widget.repository.loadOperatingSummary(widget.membership.institutionId, r.from, r.to),
      widget.repository.loadDashboardSales(widget.membership.institutionId, r.from, r.to),
      widget.repository.loadExpenses(widget.membership.institutionId, r.from, r.to),
      widget.repository.loadAccessibleBranches(widget.membership.institutionId),
    ]);
    return (x[0] as OperatingSummary, x[1] as List<OperatingSaleRecord>, x[2] as List<Map<String,dynamic>>, x[3] as List<BranchRecord>);
  }
  void reload() => setState(() => data = load());
  Future<void> change(DashboardPeriod p) async {
    if (p == DashboardPeriod.custom) {
      final now=DateTime.now(); final x=await showDateRangePicker(context: context, firstDate: DateTime(now.year-4), lastDate: DateTime(now.year+1));
      if(x==null)return; custom=x;
    }
    period=p; reload();
  }
  @override Widget build(BuildContext context) => FutureBuilder<(OperatingSummary,List<OperatingSaleRecord>,List<Map<String,dynamic>>,List<BranchRecord>)>(future:data,builder:(context,s){
    if(!s.hasData)return const _DashboardSkeleton();
    final summary=s.data!.$1,sales=s.data!.$2,expenses=s.data!.$3,branches=s.data!.$4;
    final outflow=expenses.fold<double>(0,(a,b)=>a+(b['amount'] as num).toDouble());
    final inflow=summary.payments.values.fold<double>(0,(a,b)=>a+b);
    final due=(summary.salesAmount-inflow).clamp(0.0,double.infinity).toDouble();
    return RefreshIndicator(onRefresh:()async=>reload(),child:ListView(padding:const EdgeInsets.fromLTRB(16,14,16,24),children:[
      DashboardHeader(name:widget.profile.fullName,institution:widget.membership.institutionName,subtitle:branches.length>1?'${branches.length} فروع':'المحاسب'),
      const SizedBox(height:14),PeriodSelector(value:period,onChanged:change),const SizedBox(height:14),
      HeroMetricCard(title:'التدفق النقدي',value:farshaMoney(inflow-outflow),caption:'داخل ${farshaMoney(inflow)} • خارج ${farshaMoney(outflow)}',icon:Icons.account_balance_outlined,child:MiniLineChart(values:_dailySeries(sales),color:Colors.white,height:72)),
      const SizedBox(height:12),KpiGrid(children:[
        KpiCard(title:'المبيعات',value:farshaMoney(summary.salesAmount),icon:Icons.point_of_sale,accent:infoBlue),
        KpiCard(title:'المحصل',value:farshaMoney(inflow),icon:Icons.payments_outlined,accent:positiveGreen),
        KpiCard(title:'المستحق',value:farshaMoney(due),icon:Icons.schedule,accent:dangerRed),
        KpiCard(title:'المصروفات',value:farshaMoney(outflow),icon:Icons.receipt_long,accent:warningOrange),
      ]),
      const SizedBox(height:22),const SectionTitle('طرق الدفع'),Card(child:Padding(padding:const EdgeInsets.all(16),child:DonutChart(values:summary.payments,labels:paymentLabels))),
      const SizedBox(height:22),const SectionTitle('إجراءات المحاسب'),QuickActionsRow(actions:[
        QuickActionData('مصروف',Icons.receipt_long_outlined,()=>widget.onNavigate(3),accent:warningOrange),
        QuickActionData('دفع مورد',Icons.local_shipping_outlined,()=>widget.onNavigate(3),accent:infoBlue),
        QuickActionData('تسوية بائع',Icons.person_outline,()=>widget.onNavigate(3),accent:positiveGreen),
        QuickActionData('تسوية سائق',Icons.route_outlined,()=>widget.onNavigate(3),accent:partnerPurple),
      ]),
      const SizedBox(height:22),const SectionTitle('المهام المطلوبة'),
      if(due==0)const EmptyState(title:'لا توجد مهام تحصيل معلقة في الفترة',icon:Icons.task_alt) else _AlertTile(icon:Icons.schedule,color:dangerRed,title:'تحصيلات تحتاج متابعة',subtitle:farshaMoney(due)),
    ]));
  });
}

class SellerDashboardV2 extends StatefulWidget {
  const SellerDashboardV2({super.key, required this.profile, required this.membership, required this.repository, required this.onNavigate});
  final UserProfile profile; final InstitutionMembership membership; final FarshaRepository repository; final ValueChanged<int> onNavigate;
  @override State<SellerDashboardV2> createState()=>_SellerDashboardV2State();
}
class _SellerDashboardV2State extends State<SellerDashboardV2>{
  late Future<(SellerPerformanceRecord,List<OperatingSaleRecord>)> data=load();
  Future<(SellerPerformanceRecord,List<OperatingSaleRecord>)> load()async{final n=DateTime.now(),f=DateTime(n.year,n.month,1),t=DateTime(n.year,n.month+1,1);final a=await widget.repository.loadSellerPerformance(widget.membership.institutionId,widget.repository.userId,f,t),b=await widget.repository.loadDashboardSales(widget.membership.institutionId,f,t,sellerId:widget.repository.userId);return(a,b);}
  @override Widget build(BuildContext context)=>FutureBuilder<(SellerPerformanceRecord,List<OperatingSaleRecord>)>(future:data,builder:(context,s){if(!s.hasData)return const _DashboardSkeleton();final p=s.data!.$1,sales=s.data!.$2;return RefreshIndicator(onRefresh:()async=>setState(()=>data=load()),child:ListView(padding:const EdgeInsets.fromLTRB(16,14,16,24),children:[
    DashboardHeader(name:widget.profile.fullName,institution:widget.membership.institutionName,subtitle:'البائع'),
    const SizedBox(height:14),
    if(p.saleCount==0)EmptyState(title:'لا توجد مبيعات لك هذا الشهر',subtitle:'ابدأ أول بيعة وسيظهر أداؤك هنا.',icon:Icons.point_of_sale,actionLabel:'بيعة جديدة',onAction:()=>widget.onNavigate(1))else HeroMetricCard(title:'مبيعاتي هذا الشهر',value:farshaMoney(p.salesAmount),caption:'${p.saleCount} عملية • ${p.totalLength.toStringAsFixed(1)} متر',child:MiniLineChart(values:_dailySeries(sales),color:Colors.white,height:72)),
    const SizedBox(height:12),KpiGrid(children:[
      KpiCard(title:'عدد عملياتي',value:p.saleCount.toString(),icon:Icons.receipt_long_outlined,accent:infoBlue),
      KpiCard(title:'الأمتار المباعة',value:'${p.totalLength.toStringAsFixed(1)} م',icon:Icons.straighten,accent:positiveGreen),
      KpiCard(title:'عمولتي',value:farshaMoney(p.commission),icon:Icons.workspace_premium_outlined,accent:partnerPurple),
      KpiCard(title:'المتبقي لي',value:farshaMoney(p.netDue),icon:Icons.account_balance_wallet_outlined,accent:warningOrange),
    ]),
    const SizedBox(height:22),const SectionTitle('إجراءات سريعة'),QuickActionsRow(actions:[
      QuickActionData('بيعة جديدة',Icons.add_shopping_cart,()=>widget.onNavigate(1)),
      QuickActionData('عرض سعر',Icons.request_quote_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DocumentsPage(membership:widget.membership,repository:widget.repository))),accent:infoBlue),
      QuickActionData('فواتيري',Icons.receipt_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DocumentsPage(membership:widget.membership,repository:widget.repository))),accent:positiveGreen),
      QuickActionData('حسابي',Icons.account_balance_wallet_outlined,()=>widget.onNavigate(3),accent:partnerPurple),
    ]),
    const SizedBox(height:22),const SectionTitle('آخر مبيعاتي'),
    if(sales.isEmpty)const EmptyState(title:'لا توجد مبيعات مسجلة لك',icon:Icons.history)else...sales.take(5).map((x)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(x.itemName+' • '+x.color),subtitle:Text('${x.length.toStringAsFixed(1)} م • ${x.createdAt.toLocal().toString().substring(0,10)}'),trailing:Text(farshaMoney(x.salesAmount),style:const TextStyle(fontWeight:FontWeight.w800)))),
  ]));});
}

class PartnerDashboardV2 extends StatefulWidget {
  const PartnerDashboardV2({super.key,required this.profile,required this.membership,required this.repository,required this.contextData});
  final UserProfile profile;final InstitutionMembership membership;final FarshaRepository repository;final Map<String,dynamic> contextData;
  @override State<PartnerDashboardV2> createState()=>_PartnerDashboardV2State();
}
class _PartnerDashboardV2State extends State<PartnerDashboardV2>{
  DashboardPeriod period=DashboardPeriod.month;
  @override Widget build(BuildContext context){
    final scopes=(widget.contextData['partner_scopes'] as List?)??const[];final scope=scopes.isEmpty?null:scopes.first as Map<String,dynamic>?;final history=(scope?['partner_entitlement_history'] as List?)??const[];final pct=history.isEmpty?0.0:((history.first as Map)['percentage'] as num).toDouble();final relationship=widget.contextData['relationship_type'] as String? ?? '';final admin=relationship=='administrative_partner'||relationship=='authorized_manager';final range=periodRange(period);
    return FutureBuilder<List<Map<String,dynamic>>>(future:widget.repository.loadPartnerStatement(widget.membership.institutionId,widget.contextData['id'] as String,range.from,range.to,branchId:scope?['branch_id'] as String?),builder:(context,s){if(!s.hasData)return const _DashboardSkeleton();final rows=s.data!;final entitlement=rows.where((x)=>x['kind']=='entitlement').fold<double>(0,(a,b)=>a+(b['amount'] as num).toDouble());final distributed=rows.where((x)=>x['kind']=='distribution'||x['kind']=='withdrawal'||x['kind']=='settlement').fold<double>(0,(a,b)=>a+(b['amount'] as num).abs().toDouble());final balance=rows.isEmpty?0.0:(rows.first['running_balance'] as num).toDouble();
      return ListView(padding:const EdgeInsets.fromLTRB(16,14,16,24),children:[
        DashboardHeader(name:widget.profile.fullName,institution:widget.membership.institutionName,subtitle:'شريك'),
        const SizedBox(height:14),PeriodSelector(value:period,onChanged:(v)=>setState(()=>period=v)),const SizedBox(height:14),
        if(admin&&pct==0)
          const EmptyState(title:'صلاحيات إدارية',subtitle:'هذا الحساب شريك إداري بنسبة استحقاق 0%، لذلك لا نعرض أرباحًا غير موجودة.',icon:Icons.admin_panel_settings_outlined)
        else ...[
          HeroMetricCard(title:'نصيبي المستحق',value:farshaMoney(balance),caption:'نسبة الاستحقاق ${pct.toStringAsFixed(1)}%',icon:Icons.handshake_outlined),
          const SizedBox(height:12),KpiGrid(children:[
            KpiCard(title:'الاستحقاقات',value:farshaMoney(entitlement),icon:Icons.trending_up,accent:partnerPurple),
            KpiCard(title:'تم توزيعه',value:farshaMoney(distributed),icon:Icons.payments_outlined,accent:positiveGreen),
            KpiCard(title:'المتبقي',value:farshaMoney(balance),icon:Icons.account_balance_wallet_outlined,accent:warningOrange),
            KpiCard(title:'النسبة',value:'${pct.toStringAsFixed(1)}%',icon:Icons.percent,accent:infoBlue),
          ]),
        ],
        const SizedBox(height:22),const SectionTitle('آخر حركات حساب الشريك'),
        if(rows.isEmpty)const EmptyState(title:'لا توجد حركات في هذه الفترة',icon:Icons.history)else...rows.take(8).map((x)=>ListTile(contentPadding:EdgeInsets.zero,title:Text((x['description'] as String?)?.isNotEmpty==true?x['description'] as String:x['kind'] as String),subtitle:Text('${x['branch_name']??''} • ${DateTime.parse(x['event_time'] as String).toLocal().toString().substring(0,10)}'),trailing:Text(farshaMoney((x['amount'] as num).toDouble()),style:const TextStyle(fontWeight:FontWeight.w800)))),
      ]);
    });
  }
}

class SalesHubV2 extends StatelessWidget {
  const SalesHubV2({super.key,required this.membership,required this.repository});
  final InstitutionMembership membership;final FarshaRepository repository;
  @override Widget build(BuildContext context)=>_HubList(title:'البيع',subtitle:'كل دورة البيع في مكان واحد',children:[
    _HubItem('بيعة جديدة','تسجيل البيع، الإضافات، السائق وSplit Payment',Icons.add_shopping_cart,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('بيعة جديدة')),body:SalesSettlementPage(membership:membership,repository:repository))))),
    _HubItem('عروض الأسعار والفواتير','إنشاء وعرض المستندات الحالية',Icons.description_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('المستندات')),body:DocumentsPage(membership:membership,repository:repository))))),
    if(membership.role!=InstitutionRole.seller)_HubItem('سجل المبيعات','بحث وتقارير التشغيل والمبيعات',Icons.history,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('سجل المبيعات')),body:OperatingReportsPage(membership:membership,repository:repository))))),
  ]);
}

class InventoryHubV2 extends StatelessWidget {
  const InventoryHubV2({super.key,required this.membership,required this.repository});
  final InstitutionMembership membership;final FarshaRepository repository;
  @override Widget build(BuildContext context)=>_HubList(title:'المخزون',subtitle:'الموكيت والمستلزمات والتوريدات والتحويلات',children:[
    _HubItem('مخزون الموكيت والأرضيات','الصنف ← اللون ← الأمتار الطولية',Icons.inventory_2_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('المخزون')),body:InstitutionOperationsPage(membership:membership,repository:repository))))),
    if(membership.role!=InstitutionRole.seller)_HubItem('المستلزمات','لباد، غراء، حديد ومستلزمات أخرى',Icons.handyman_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('المستلزمات')),body:MaterialsPage(membership:membership,repository:repository))))),
    if(membership.role!=InstitutionRole.seller)_HubItem('التوريد وتحويل المخزون','من نفس شاشة المخزون مع الحفاظ على منطق الفروع',Icons.swap_horiz_rounded,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('التوريد والتحويل')),body:InstitutionOperationsPage(membership:membership,repository:repository))))),
  ]);
}

class AccountsHubV2 extends StatelessWidget {
  const AccountsHubV2({super.key,required this.membership,required this.repository});
  final InstitutionMembership membership;final FarshaRepository repository;
  @override Widget build(BuildContext context){
    final seller=membership.role==InstitutionRole.seller;
    return _HubList(title:seller?'حسابي':'الحسابات',subtitle:seller?'مستحقاتك وحركات حسابك':'كشوف الحساب والتسويات والحركات المالية',children:[
      _HubItem(seller?'كشف حسابي':'كشوف الحساب','البائعون، السائقون والموردون حسب الصلاحية',Icons.account_balance_wallet_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:Text(seller?'حسابي':'كشف الحساب')),body:AccountStatementsPage(membership:membership,repository:repository,personalSeller:seller))))),
      if(!seller)_HubItem('التسويات والمصروفات','التصفية الشهرية والحركات المالية الحالية',Icons.payments_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('التسويات')),body:SalesSettlementPage(membership:membership,repository:repository))))),
    ]);
  }
}

class MoreHubV2 extends StatelessWidget {
  const MoreHubV2({super.key,required this.membership,required this.repository});
  final InstitutionMembership membership;final FarshaRepository repository;
  @override Widget build(BuildContext context){
    final manager=membership.role!=InstitutionRole.seller;
    return _HubList(title:'المزيد',subtitle:'الإدارة والتقارير والإعدادات',children:[
      if(membership.role==InstitutionRole.owner)_HubItem('الفروع والشركاء','إدارة الفروع والنسب والنطاقات',Icons.account_tree_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('الفروع والشركاء')),body:BranchesPartnersPage(membership:membership,repository:repository))))),
      if(manager)_HubItem('المستخدمون والصلاحيات','الفريق، البائعون والسائقون',Icons.people_outline,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('المستخدمون')),body:MembersPage(membership:membership,repository:repository))))),
      if(manager)_HubItem('التقارير','تقارير التشغيل والتصدير',Icons.analytics_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('التقارير')),body:OperatingReportsPage(membership:membership,repository:repository))))),
      if(manager)_HubItem('تقرير الفروع','مبيعات وربح ومصروفات كل فرع',Icons.store_mall_directory_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('تقرير الفروع')),body:BranchReportPage(membership:membership,repository:repository))))),
      _HubItem('المستندات','الفواتير وعروض الأسعار',Icons.receipt_long_outlined,()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('المستندات')),body:DocumentsPage(membership:membership,repository:repository))))),
    ]);
  }
}

class _HubList extends StatelessWidget{
  const _HubList({required this.title,required this.subtitle,required this.children});
  final String title,subtitle;final List<_HubItem> children;
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.fromLTRB(16,18,16,24),children:[
    Text(title,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900)),const SizedBox(height:4),Text(subtitle,style:TextStyle(color:Colors.grey.shade700)),const SizedBox(height:18),
    ...children.map((x)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Card(child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:7),leading:Container(width:42,height:42,decoration:BoxDecoration(color:farshaBurgundy.withValues(alpha:.08),borderRadius:BorderRadius.circular(13)),child:Icon(x.icon,color:farshaBurgundy)),title:Text(x.title,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(x.subtitle,maxLines:2),trailing:const Icon(Icons.chevron_left),onTap:x.onTap)))),
  ]);
}
class _HubItem{const _HubItem(this.title,this.subtitle,this.icon,this.onTap);final String title,subtitle;final IconData icon;final VoidCallback onTap;}

class _AlertTile extends StatelessWidget{
  const _AlertTile({required this.icon,required this.color,required this.title,required this.subtitle});
  final IconData icon;final Color color;final String title,subtitle;
  @override Widget build(BuildContext context)=>Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16),border:Border.all(color:color.withValues(alpha:.18))),child:Row(children:[Container(width:38,height:38,decoration:BoxDecoration(color:color.withValues(alpha:.1),borderRadius:BorderRadius.circular(11)),child:Icon(icon,color:color,size:20)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),Text(subtitle,style:TextStyle(color:Colors.grey.shade700,fontSize:12))]))]));
}

class _DashboardSkeleton extends StatelessWidget{
  const _DashboardSkeleton();
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:List.generate(5,(i)=>Container(height:i==1?180:88,margin:const EdgeInsets.only(bottom:12),decoration:BoxDecoration(color:Colors.white.withValues(alpha:.75),borderRadius:BorderRadius.circular(20)))));
}

List<double> _dailySeries(List<OperatingSaleRecord> sales){
  if(sales.isEmpty)return const [];
  final map=<String,double>{};
  for(final s in sales){final d=s.createdAt.toLocal();final k='${d.year}-${d.month}-${d.day}';map.update(k,(v)=>v+s.salesAmount,ifAbsent:()=>s.salesAmount);}
  final keys=map.keys.toList()..sort();return keys.map((k)=>map[k]!).toList();
}

const paymentLabels=<String,String>{'cash':'كاش','network':'شبكة','bank_transfer':'تحويل بنكي','visa':'Visa','tamara':'تمارا','tabby':'تابي','other':'أخرى'};
