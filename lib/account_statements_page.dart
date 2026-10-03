import 'account_live.dart';
import 'package:flutter/material.dart';
import 'cloud_models.dart';
import 'farsha_repository.dart';
import 'ui_v2_components.dart';

const sar = '⃁';
String money(double v) => sar + ' ' + v.toStringAsFixed(2);

class AccountStatementsPage extends StatefulWidget {
  const AccountStatementsPage({
    super.key,
    required this.membership,
    required this.repository,
    this.personalSeller = false,
  });
  final InstitutionMembership membership;
  final FarshaRepository repository;
  final bool personalSeller;
  @override
  State<AccountStatementsPage> createState() => _AccountStatementsPageState();
}

class _AccountStatementsPageState extends State<AccountStatementsPage>
    with WidgetsBindingObserver, AccountLive<AccountStatementsPage> {
  @override
  void initState() {
    super.initState();
    startAccountLive(widget.repository, () => setState(() {}));
  }

  String party = 'seller';
  String range = 'all';
  DateTimeRange? customRange;
  final search = TextEditingController();
  (DateTime, DateTime) dates() {
    final n = DateTime.now(),
        d = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        );
    return switch (range) {
      'all' => (DateTime(1900), DateTime(n.year + 1)),
      'today' => (d, d.add(const Duration(days: 1))),
      'week' => (
        d.subtract(Duration(days: d.weekday - 1)),
        d.add(const Duration(days: 1)),
      ),
      'previous' => (
        DateTime(n.year, n.month - 1, 1),
        DateTime(n.year, n.month, 1),
      ),
      'custom' => (
        customRange?.start ?? d,
        (customRange?.end ?? d).add(const Duration(days: 1)),
      ),
      _ => (DateTime(n.year, n.month, 1), DateTime(n.year, n.month + 1, 1)),
    };
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.personalSeller)
      return StatementDetailPage(
        membership: widget.membership,
        repository: widget.repository,
        party: 'seller',
        partyId: widget.repository.userId,
        partyName: 'حسابي',
        from: dates().$1,
        to: dates().$2,
        allowEntry: false,
      );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'seller', label: Text('البائعون')),
              ButtonSegment(value: 'driver', label: Text('السائقون')),
              ButtonSegment(value: 'supplier', label: Text('الموردون')),
            ],
            selected: {party},
            onSelectionChanged: (v) => setState(() => party = v.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: range,
                  decoration: const InputDecoration(labelText: 'الفترة'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('كل الحركات')),
                    DropdownMenuItem(value: 'today', child: Text('اليوم')),
                    DropdownMenuItem(value: 'week', child: Text('هذا الأسبوع')),
                    DropdownMenuItem(value: 'month', child: Text('هذا الشهر')),
                    DropdownMenuItem(
                      value: 'previous',
                      child: Text('الشهر السابق'),
                    ),
                    DropdownMenuItem(
                      value: 'custom',
                      child: Text('فترة مخصصة'),
                    ),
                  ],
                  onChanged: (v) async {
                    if (v == 'custom') {
                      final now = DateTime.now();
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(now.year - 5),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (picked == null) return;
                      customRange = picked;
                    }
                    setState(() => range = v!);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'بحث بالاسم',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AccountSummaryRecord>>(
            future: widget.repository.loadAccountSummaries(
              widget.membership.institutionId,
              party,
              dates().$1,
              dates().$2,
            ),
            builder: (c, s) {
              if (s.hasError)
                return Center(child: Text('تعذر تحميل الحساب: ${s.error}'));
              if (!s.hasData)
                return const Center(child: CircularProgressIndicator());
              final rows = s.data!
                  .where((x) => x.name.contains(search.text.trim()))
                  .toList();
              if (rows.isEmpty)
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: EmptyState(
                    title: 'لا توجد حركات أو أرصدة في هذه الفترة',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                );
              return ListView(
                padding: const EdgeInsets.all(12),
                children: rows.map<Widget>((x) {
                  final subtitle =
                      (party == 'seller'
                          ? x.count.toString() + ' عملية • مستحق '
                          : party == 'driver'
                          ? x.count.toString() + ' مشوار • الإجمالي '
                          : x.count.toString() + ' توريد • ورد ') +
                      money(x.gross) +
                      ' • مدفوع ' +
                      money(x.paid);
                  return Card(
                    child: ListTile(
                      title: Text(
                        x.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(subtitle),
                      trailing: Text(
                        x.balance < 0
                            ? 'عليه\n' + money(-x.balance)
                            : 'له\n' + money(x.balance),
                        textAlign: TextAlign.center,
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StatementDetailPage(
                              membership: widget.membership,
                              repository: widget.repository,
                              party: party,
                              partyId: x.id,
                              partyName: x.name,
                              from: dates().$1,
                              to: dates().$2,
                              allowEntry: true,
                            ),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class StatementDetailPage extends StatefulWidget {
  const StatementDetailPage({
    super.key,
    required this.membership,
    required this.repository,
    required this.party,
    required this.partyId,
    required this.partyName,
    required this.from,
    required this.to,
    required this.allowEntry,
  });
  final InstitutionMembership membership;
  final FarshaRepository repository;
  final String party, partyId, partyName;
  final DateTime from, to;
  final bool allowEntry;
  @override
  State<StatementDetailPage> createState() => _StatementDetailPageState();
}

class _StatementDetailPageState extends State<StatementDetailPage>
    with WidgetsBindingObserver, AccountLive<StatementDetailPage> {
  bool saving = false;
  @override
  void initState() {
    super.initState();
    startAccountLive(widget.repository, reload);
  }

  late Future<Map<String, dynamic>> data = load();
  Future<Map<String, dynamic>> load() => widget.repository.loadAccountLedger(
    widget.membership.institutionId,
    widget.party,
    widget.partyId,
    widget.from,
    widget.to,
  );
  void reload() {
    if (mounted) setState(() { data = load(); });
  }

  Future<void> addEntry() async {
    if (saving) return;
    final branches = await widget.repository.loadBranches(
      widget.membership.institutionId,
    );
    if (!mounted) return;
    String? branchId;
    final amount = TextEditingController(),
        note = TextEditingController(),
        ref = TextEditingController();
    String type = widget.party == 'seller' ? 'withdrawal' : 'payment',
        method = 'cash';
    final options = widget.party == 'seller'
        ? const {
            'withdrawal': 'مسحوب',
            'expense': 'مصروف/عهدة',
            'deduction': 'خصم',
            'payment': 'تسوية',
          }
        : widget.party == 'driver'
        ? const {
            'payment': 'دفعة',
            'settlement': 'تسوية',
            'adjustment': 'تعديل',
          }
        : const {
            'payment': 'سداد',
            'return': 'مرتجع',
            'settlement': 'تسوية',
            'adjustment': 'تعديل',
          };
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text('حركة • ' + widget.partyName),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: branchId,
                  decoration: const InputDecoration(labelText: 'الفرع'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('حساب المؤسسة العام'),
                    ),
                    ...branches.map(
                      (b) => DropdownMenuItem<String?>(
                        value: b.id,
                        child: Text(b.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setD(() => branchId = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'نوع الحركة'),
                  items: options.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => type = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                ),
                if (widget.party != 'seller') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('كاش')),
                      DropdownMenuItem(
                        value: 'bank_transfer',
                        child: Text('تحويل بنكي'),
                      ),
                    ],
                    onChanged: (v) => method = v!,
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: ref,
                  decoration: const InputDecoration(labelText: 'المرجع'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final a = double.tryParse(amount.text) ?? 0, n = note.text, r = ref.text;
    for (final c in [amount, note, ref]) c.dispose();
    if (ok != true || a <= 0) return;
    if (!mounted) return;
    setState(() => saving = true);
    try {
      if (widget.party == 'seller')
        await widget.repository.addSellerLedger(
          institutionId: widget.membership.institutionId,
          sellerId: widget.partyId,
          kind: type,
          amount: a,
          note: n,
          reference: r,
          branchId: branchId,
        );
      else if (widget.party == 'driver')
        await widget.repository.recordDriverAccountEntry(
          institutionId: widget.membership.institutionId,
          driverId: widget.partyId,
          type: type,
          amount: a,
          method: method,
          reference: r,
          note: n,
          branchId: branchId,
        );
      else
        await widget.repository.recordSupplierAccountEntry(
          institutionId: widget.membership.institutionId,
          supplierId: widget.partyId,
          type: type,
          amount: a,
          method: method,
          reference: r,
          note: n,
          branchId: branchId,
        );
      reload();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر حفظ الحركة: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('كشف حساب • ' + widget.partyName)),
    floatingActionButton: widget.allowEntry
        ? FloatingActionButton.extended(
            onPressed: saving ? null : addEntry,
            icon: const Icon(Icons.add),
            label: const Text('حركة'),
          )
        : null,
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (c, s) {
        if (s.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('تعذر تحميل الحساب: ${s.error}'),
                TextButton(
                  onPressed: reload,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final ledger = s.data!,
            rows = List<Map<String, dynamic>>.from(ledger['movements'] as List);
        double number(String key) => (ledger[key] as num).toDouble();
        final balance = number('current_balance');
        return RefreshIndicator(
          onRefresh: () async {
            reload();
            await data;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  metric(
                    balance < 0 ? 'الرصيد الحالي • عليه' : 'الرصيد الحالي • له',
                    money(balance.abs()),
                  ),
                  metric('افتتاح الفترة', money(number('opening_balance'))),
                  metric('مستحقات الفترة', money(number('gross'))),
                  metric('مدفوعات/خصومات الفترة', money(number('paid'))),
                  metric('ختام الفترة', money(number('closing_balance'))),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('الفترة للعرض فقط؛ الرصيد الحالي يشمل كل الحركات.'),
              ),
              if (rows.isEmpty) const Text('لا توجد حركات في الفترة المحددة'),
              ...rows.map(
                (x) => Card(
                  child: ListTile(
                    title: Text(x['description'] as String),
                    subtitle: Text(
                      '${DateTime.parse(x['event_time'] as String).toLocal()} • ${x['created_by_name']}\nمرجع: ${x['reference']}\nحركة: ${x['movement_id']}',
                    ),
                    trailing: Text(
                      '${money((x['amount'] as num).toDouble())}\nرصيد ${money((x['running_balance'] as num).toDouble())}',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  Widget metric(String a, String b) => SizedBox(
    width: 160,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(a),
            Text(b, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ),
  );
}
