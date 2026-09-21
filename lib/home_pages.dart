import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_models.dart';
import 'documents_page.dart';
import 'farsha_repository.dart';
import 'operations_pages.dart';
import 'operating_reports_page.dart';

class ProfileRouter extends StatefulWidget {
  const ProfileRouter({super.key});

  @override
  State<ProfileRouter> createState() => _ProfileRouterState();
}

class _ProfileRouterState extends State<ProfileRouter> {
  late final FarshaRepository _repository = FarshaRepository(Supabase.instance.client);
  late Future<UserProfile> _profile = _repository.loadProfile();

  void _reload() => setState(() => _profile = _repository.loadProfile());

  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfile>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorPage(message: 'تعذر تحميل الحساب: ${snapshot.error}', retry: _reload);
          }
          if (!snapshot.hasData) return const BrandedLoading();
          final profile = snapshot.data!;
          if (profile.accountKind == AccountKind.driver) {
            return DriverHome(profile: profile, repository: _repository);
          }
          return InstitutionAccountHome(profile: profile, repository: _repository);
        },
      );
}

class InstitutionAccountHome extends StatefulWidget {
  const InstitutionAccountHome({super.key, required this.profile, required this.repository});
  final UserProfile profile;
  final FarshaRepository repository;

  @override
  State<InstitutionAccountHome> createState() => _InstitutionAccountHomeState();
}

class _InstitutionAccountHomeState extends State<InstitutionAccountHome> {
  late Future<List<InstitutionMembership>> _memberships = widget.repository.loadMemberships();

  void _reload() => setState(() => _memberships = widget.repository.loadMemberships());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<InstitutionMembership>>(
        future: _memberships,
        builder: (context, snapshot) {
          if (snapshot.hasError) return ErrorPage(message: '${snapshot.error}', retry: _reload);
          if (!snapshot.hasData) return const BrandedLoading();
          final memberships = snapshot.data!;
          if (memberships.isEmpty) {
            return InstitutionOnboarding(
              profile: widget.profile,
              repository: widget.repository,
              onCompleted: _reload,
            );
          }
          if (memberships.length == 1) {
            return InstitutionDashboard(
              membership: memberships.first,
              repository: widget.repository,
            );
          }
          return Scaffold(
            appBar: AppBar(title: const Text('اختر المؤسسة'), actions: const [SignOutButton()]),
            body: ListView(
              padding: const EdgeInsets.all(18),
              children: memberships
                  .map((membership) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.storefront)),
                          title: Text(membership.institutionName),
                          subtitle: Text(membership.role.label),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InstitutionDashboard(
                                membership: membership,
                                repository: widget.repository,
                              ),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          );
        },
      );
}

class InstitutionOnboarding extends StatefulWidget {
  const InstitutionOnboarding({
    super.key,
    required this.profile,
    required this.repository,
    required this.onCompleted,
  });
  final UserProfile profile;
  final FarshaRepository repository;
  final VoidCallback onCompleted;

  @override
  State<InstitutionOnboarding> createState() => _InstitutionOnboardingState();
}

class _InstitutionOnboardingState extends State<InstitutionOnboarding> {
  final _name = TextEditingController();
  final _cr = TextEditingController();
  final _tax = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _invite = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [_name, _cr, _tax, _address, _phone, _email, _invite]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if ([_name, _cr, _tax, _address, _phone, _email].any((c) => c.text.trim().isEmpty)) {
      return _show('أكمل جميع بيانات المؤسسة', error: true);
    }
    await _run(() => widget.repository.createInstitution(
          name: _name.text.trim(),
          commercialRegistration: _cr.text.trim(),
          taxNumber: _tax.text.trim(),
          address: _address.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
        ));
  }

  Future<void> _claim() async {
    if (_invite.text.trim().isEmpty) return _show('اكتب كود الدعوة', error: true);
    await _run(() => widget.repository.claimInvitation(_invite.text.trim()));
  }

  Future<void> _run(Future<String> Function() operation) async {
    setState(() => _busy = true);
    try {
      await operation();
      widget.onCompleted();
    } catch (error) {
      if (mounted) _show('$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String text, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
      );

  @override
  Widget build(BuildContext context) {
    final owner = widget.profile.onboardingMode == 'owner';
    return Scaffold(
      appBar: AppBar(title: const Text('إعداد الحساب'), actions: const [SignOutButton()]),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text('مرحبًا ${widget.profile.fullName}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          if (owner) ...[
            const Text('أنشئ مؤسستك مرة واحدة، وبعدها ادعُ المحاسب والبائعين.'),
            const SizedBox(height: 16),
            ...[
              [_name, 'اسم المؤسسة'], [_cr, 'السجل التجاري'], [_tax, 'الرقم الضريبي'],
              [_address, 'العنوان'], [_phone, 'هاتف المؤسسة'], [_email, 'البريد الإلكتروني'],
            ].expand((item) => [
                  TextField(controller: item[0] as TextEditingController, decoration: InputDecoration(labelText: item[1] as String)),
                  const SizedBox(height: 12),
                ]),
            FilledButton(onPressed: _busy ? null : _create, child: const Text('إنشاء المؤسسة')),
          ] else ...[
            const Text('اطلب كود الدعوة من صاحب المؤسسة أو المحاسب.'),
            const SizedBox(height: 16),
            TextField(controller: _invite, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'كود الدعوة')),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _claim, child: const Text('الانضمام إلى المؤسسة')),
          ],
        ],
      ),
    );
  }
}

class InstitutionDashboard extends StatefulWidget {
  const InstitutionDashboard({super.key, required this.membership, required this.repository});
  final InstitutionMembership membership;
  final FarshaRepository repository;

  @override
  State<InstitutionDashboard> createState() => _InstitutionDashboardState();
}

class _InstitutionDashboardState extends State<InstitutionDashboard> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final manager = widget.membership.role != InstitutionRole.seller;
    final pages = <Widget>[
      InstitutionOverview(membership: widget.membership, repository: widget.repository),
      if (manager) MembersPage(membership: widget.membership, repository: widget.repository),
      InstitutionOperationsPage(membership: widget.membership, repository: widget.repository),
      if (manager) OperatingReportsPage(membership: widget.membership, repository: widget.repository),
      DocumentsPage(membership: widget.membership, repository: widget.repository),
      SalesSettlementPage(membership: widget.membership, repository: widget.repository),
    ];
    final labels = <String>['الرئيسية', if (manager) 'المستخدمون', 'المخزون', if (manager) 'التقارير', 'المستندات', 'البيع'];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.membership.institutionName),
        actions: const [SignOutButton()],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: labels
            .map((label) => NavigationDestination(icon: Icon(_navIcon(label)), label: label))
            .toList(),
      ),
    );
  }

  IconData _navIcon(String label) => switch (label) {
        'الرئيسية' => Icons.home_outlined,
        'المستخدمون' => Icons.people_outline,
        'المخزون' => Icons.inventory_2_outlined,
        'التقارير' => Icons.analytics_outlined,
        'المستندات' => Icons.description_outlined,
        _ => Icons.point_of_sale,
      };
}

class InstitutionOverview extends StatelessWidget {
  const InstitutionOverview({super.key, required this.membership, required this.repository});
  final InstitutionMembership membership;
  final FarshaRepository repository;

  Future<void> _editFees(BuildContext context) async {
    final settings = await repository.loadInstitutionSettings(membership.institutionId);
    if (!context.mounted) return;
    final visa = TextEditingController(text: settings.visaFeePercent.toStringAsFixed(2));
    final tabby = TextEditingController(text: settings.tabbyFeePercent.toStringAsFixed(2));
    final tamara = TextEditingController(text: settings.tamaraFeePercent.toStringAsFixed(2));
    final save = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('رسوم طرق الدفع'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: visa, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Visa %')),
        const SizedBox(height: 10), TextField(controller: tabby, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tabby %')),
        const SizedBox(height: 10), TextField(controller: tamara, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tamara %')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    ));
    final values = [double.tryParse(visa.text) ?? -1, double.tryParse(tabby.text) ?? -1, double.tryParse(tamara.text) ?? -1];
    visa.dispose(); tabby.dispose(); tamara.dispose();
    if (save != true || values.any((value) => value < 0 || value > 100)) return;
    await repository.updateInstitutionFees(membership.institutionId, values[0], values[1], values[2]);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ نسب الرسوم')));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, int>>(
        future: repository.loadInstitutionCounts(membership.institutionId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final counts = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(membership.role.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MetricCard(title: 'الموردون', value: '${counts['suppliers']}'),
                  MetricCard(title: 'المخزون', value: '${counts['inventory']}'),
                  MetricCard(title: 'المبيعات', value: '${counts['sales']}'),
                ],
              ),
              const SizedBox(height: 22),
              if (membership.role != InstitutionRole.seller) ...[
                OutlinedButton.icon(onPressed: () => _editFees(context), icon: const Icon(Icons.percent), label: const Text('رسوم Visa / Tabby / Tamara')),
                const SizedBox(height: 12),
              ],
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('كل مستخدم يدخل من جواله، والبيانات والصلاحيات مرتبطة بحسابه والمؤسسة.'),
                ),
              ),
            ],
          );
        },
      );
}

class MembersPage extends StatefulWidget {
  const MembersPage({super.key, required this.membership, required this.repository});
  final InstitutionMembership membership;
  final FarshaRepository repository;

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  late Future<List<Map<String, dynamic>>> _members =
      widget.repository.loadMembers(widget.membership.institutionId);
  late Future<List<Map<String, dynamic>>> _drivers =
      widget.repository.loadConnectedDrivers(widget.membership.institutionId);
  late Future<List<InstitutionTrip>> _trips =
      widget.repository.loadInstitutionTrips(widget.membership.institutionId);

  void _reload() => setState(() {
        _members = widget.repository.loadMembers(widget.membership.institutionId);
        _drivers = widget.repository.loadConnectedDrivers(widget.membership.institutionId);
        _trips = widget.repository.loadInstitutionTrips(widget.membership.institutionId);
      });

  Future<void> _invite() async {
    final phone = TextEditingController(text: '+966');
    final commission = TextEditingController(text: '50');
    final salary = TextEditingController(text: '0');
    InstitutionRole role = InstitutionRole.seller;
    String workPlan = 'commission';
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('دعوة مستخدم'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رقم الجوال')),
            const SizedBox(height: 12),
            DropdownButtonFormField<InstitutionRole>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'الصلاحية'),
              items: [InstitutionRole.accountant, InstitutionRole.seller]
                  .map((value) => DropdownMenuItem(value: value, child: Text(value.label)))
                  .toList(),
              onChanged: (value) => setDialogState(() => role = value!),
            ),
            if (role == InstitutionRole.seller) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: workPlan,
                decoration: const InputDecoration(labelText: 'نظام العمل'),
                items: const [
                  DropdownMenuItem(value: 'commission', child: Text('عمولة فقط')),
                  DropdownMenuItem(value: 'salary', child: Text('راتب فقط')),
                  DropdownMenuItem(value: 'salary_and_commission', child: Text('راتب + عمولة')),
                ],
                onChanged: (value) => setDialogState(() => workPlan = value!),
              ),
              const SizedBox(height: 12),
              TextField(controller: commission, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نسبة العمولة %')),
              const SizedBox(height: 12),
              TextField(controller: salary, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الراتب الشهري')),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                try {
                  final inviteCode = await widget.repository.inviteMember(
                    institutionId: widget.membership.institutionId,
                    phone: phone.text.trim(),
                    role: role,
                    workPlan: role == InstitutionRole.seller ? workPlan : 'salary',
                    commissionRate: role == InstitutionRole.seller ? (double.tryParse(commission.text) ?? 50) / 100 : 0,
                    monthlySalary: role == InstitutionRole.seller ? (double.tryParse(salary.text) ?? 0) : 0,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, inviteCode);
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('$error')));
                  }
                }
              },
              child: const Text('إنشاء الدعوة'),
            ),
          ],
        ),
      ),
    );
    phone.dispose();
    commission.dispose();
    salary.dispose();
    if (code != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('كود الدعوة'),
          content: SelectableText(code, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تم'))],
        ),
      );
      _reload();
    }
  }

  Future<void> _editSeller(Map<String, dynamic> member) async {
    if (widget.membership.role != InstitutionRole.owner || member['role'] != 'seller') return;
    var plan = member['work_plan'] as String;
    final commission = TextEditingController(text: ((member['commission_rate'] as num).toDouble() * 100).toStringAsFixed(2));
    final salary = TextEditingController(text: (member['monthly_salary'] as num).toStringAsFixed(2));
    final save = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('حساب البائع'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: plan, decoration: const InputDecoration(labelText: 'نظام العمل'), items: const [DropdownMenuItem(value: 'commission', child: Text('عمولة فقط')), DropdownMenuItem(value: 'salary', child: Text('راتب فقط')), DropdownMenuItem(value: 'salary_and_commission', child: Text('راتب + عمولة'))], onChanged: (value) => setDialogState(() => plan = value!)),
        const SizedBox(height: 10), TextField(controller: commission, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نسبة العمولة %')),
        const SizedBox(height: 10), TextField(controller: salary, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الراتب الشهري')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    )));
    final rate = double.tryParse(commission.text) ?? -1; final monthly = double.tryParse(salary.text) ?? -1;
    commission.dispose(); salary.dispose();
    if (save != true || rate < 0 || rate > 100 || monthly < 0) return;
    await widget.repository.updateSellerTerms(institutionId: widget.membership.institutionId, sellerId: member['user_id'] as String, workPlan: plan, commissionPercent: rate, monthlySalary: monthly);
    _reload();
  }

  Future<void> _payTrip(InstitutionTrip trip) async {
    var method = 'cash';
    final save = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text('دفع مشوار ${trip.driverName}'),
      content: DropdownButtonFormField<String>(initialValue: method, decoration: const InputDecoration(labelText: 'طريقة الدفع'), items: const [DropdownMenuItem(value: 'cash', child: Text('كاش')), DropdownMenuItem(value: 'bank_transfer', child: Text('تحويل بنكي'))], onChanged: (value) => setDialogState(() => method = value!)),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد الدفع'))],
    )));
    if (save != true) return;
    await widget.repository.payDriverTrip(trip.id, method);
    _reload();
  }

  Future<void> _connectDriver() async {
    final phone = TextEditingController(text: '+966');
    final shouldConnect = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ربط سائق مستقل'),
        content: TextField(
          controller: phone,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'رقم جوال حساب السائق'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ربط')),
        ],
      ),
    );
    final value = phone.text.trim();
    phone.dispose();
    if (shouldConnect != true || value.isEmpty) return;
    try {
      await widget.repository.connectDriver(
        institutionId: widget.membership.institutionId,
        phone: value,
      );
      _reload();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _members,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final memberCards = snapshot.data!.map((member) {
                final profile = member['profiles'] as Map<String, dynamic>;
                final role = InstitutionRoleLabel.parse(member['role'] as String);
                return Card(
                  child: ListTile(
                    onTap: () => _editSeller(member),
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(profile['full_name'] as String),
                    subtitle: Text(role == InstitutionRole.seller
                        ? '${role.label} • ${profile['phone']}\n${_workPlanLabel(member['work_plan'] as String)} • عمولة ${((member['commission_rate'] as num).toDouble() * 100).toStringAsFixed(1)}% • راتب ${(member['monthly_salary'] as num).toStringAsFixed(2)}'
                        : '${role.label} • ${profile['phone']}'),
                  ),
                );
              }).toList();
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _drivers,
              builder: (context, driverSnapshot) => FutureBuilder<List<InstitutionTrip>>(
              future: _trips,
              builder: (context, tripSnapshot) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('فريق المؤسسة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ...memberCards,
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(child: Text('السائقون المستقلون', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                      TextButton.icon(onPressed: _connectDriver, icon: const Icon(Icons.link), label: const Text('ربط سائق')),
                    ],
                  ),
                  if (driverSnapshot.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else if (driverSnapshot.data?.isEmpty ?? true)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا يوجد سائقون مربوطون.')))
                  else
                    ...driverSnapshot.data!.map((driver) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
                            title: Text(driver['full_name'] as String),
                            subtitle: Text('${driver['phone']} • ${driver['is_available'] == true ? 'متاح' : 'غير متاح'}'),
                          ),
                        )),
                  const SizedBox(height: 18),
                  const Text('حسابات المشاوير', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (tripSnapshot.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else if (tripSnapshot.data?.isEmpty ?? true)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد مشاوير مسجلة.')))
                  else
                    ...tripSnapshot.data!.map((trip) => Card(child: ListTile(
                      leading: Icon(trip.isPaid ? Icons.check_circle : Icons.payments_outlined, color: trip.isPaid ? Colors.green : null),
                      title: Text('${trip.driverName} • ${trip.amount.toStringAsFixed(2)} ر.س'),
                      subtitle: Text('${trip.sellerName} • ${trip.date.toLocal().toString().split(' ').first}\n${trip.isPaid ? (trip.paymentMethod == 'cash' ? 'مدفوع كاش' : 'مدفوع تحويل بنكي') : 'غير مدفوع'}'),
                      trailing: trip.isPaid ? null : TextButton(onPressed: () => _payTrip(trip), child: const Text('دفع')),
                    ))),
                ],
              ),
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _invite,
          icon: const Icon(Icons.person_add),
          label: const Text('دعوة'),
        ),
      );

  String _workPlanLabel(String value) => switch (value) {
        'salary' => 'راتب فقط',
        'salary_and_commission' => 'راتب + عمولة',
        _ => 'عمولة فقط',
      };
}

class DriverHome extends StatefulWidget {
  const DriverHome({super.key, required this.profile, required this.repository});
  final UserProfile profile;
  final FarshaRepository repository;

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  late Future<List<DriverTrip>> _trips = widget.repository.loadDriverTrips();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('مرحبًا ${widget.profile.fullName}'), actions: const [SignOutButton()]),
        body: FutureBuilder<List<DriverTrip>>(
          future: _trips,
          builder: (context, snapshot) {
            if (snapshot.hasError) return ErrorPage(message: '${snapshot.error}', retry: () => setState(() => _trips = widget.repository.loadDriverTrips()));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final trips = snapshot.data!;
            if (trips.isEmpty) return const Center(child: Text('لا توجد مشاوير مسجلة حتى الآن.'));
            final totals = <String, double>{};
            final pending = <String, double>{};
            for (final trip in trips) {
              totals.update(trip.institutionName, (value) => value + trip.amount, ifAbsent: () => trip.amount);
              if (trip.paymentStatus != 'paid') pending.update(trip.institutionName, (value) => value + trip.amount, ifAbsent: () => trip.amount);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('حسابك منفصل مع كل مؤسسة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...totals.entries.map((entry) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.storefront),
                        title: Text(entry.key),
                        subtitle: Text('المتبقي ${(pending[entry.key] ?? 0).toStringAsFixed(2)} ر.س'),
                        trailing: Text('الإجمالي\n${entry.value.toStringAsFixed(2)} ر.س', textAlign: TextAlign.center),
                      ),
                    )),
                const Divider(height: 30),
                ...trips.map((trip) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.route),
                        title: Text(trip.institutionName),
                        subtitle: Text('${trip.sellerName} • ${trip.date.toLocal().toString().split(' ').first} • ${trip.paymentStatus == 'paid' ? 'مدفوع' : 'غير مدفوع'}'),
                        trailing: Text('${trip.amount.toStringAsFixed(2)} ر.س'),
                      ),
                    )),
              ],
            );
          },
        ),
      );
}

class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'تسجيل الخروج',
        onPressed: () => Supabase.instance.client.auth.signOut(),
        icon: const Icon(Icons.logout),
      );
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.title, required this.value});
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [Text(title), const SizedBox(height: 8), Text(value, style: Theme.of(context).textTheme.headlineMedium)]),
          ),
        ),
      );
}

class BrandedLoading extends StatelessWidget {
  const BrandedLoading({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: retry, child: const Text('إعادة المحاولة'))]),
          ),
        ),
      );
}
