import 'package:flutter/material.dart';

import 'cloud_models.dart';

const farshaBurgundy = Color(0xff861B2C);
const farshaCream = Color(0xffF7F3EA);
const positiveGreen = Color(0xff168A55);
const infoBlue = Color(0xff246BCE);
const warningOrange = Color(0xffD97706);
const partnerPurple = Color(0xff7251B5);
const dangerRed = Color(0xffC53B3B);
const sarSign = '⃁';

String farshaMoney(double value) => value.abs() >= 1000
    ? '${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')} $sarSign'
    : '${value.toStringAsFixed(2)} $sarSign';

enum DashboardPeriod { today, week, month, custom }

extension DashboardPeriodLabel on DashboardPeriod {
  String get label => switch (this) {
    DashboardPeriod.today => 'اليوم',
    DashboardPeriod.week => 'الأسبوع',
    DashboardPeriod.month => 'الشهر',
    DashboardPeriod.custom => 'فترة مخصصة',
  };
}

class DashboardRange {
  const DashboardRange(this.from, this.to);
  final DateTime from;
  final DateTime to;
}

DashboardRange periodRange(DashboardPeriod period, {DateTimeRange? custom}) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return switch (period) {
    DashboardPeriod.today => DashboardRange(day, day.add(const Duration(days: 1))),
    DashboardPeriod.week => DashboardRange(day.subtract(Duration(days: day.weekday - 1)), day.add(const Duration(days: 1))),
    DashboardPeriod.month => DashboardRange(DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1)),
    DashboardPeriod.custom => DashboardRange(custom?.start ?? day, (custom?.end ?? day).add(const Duration(days: 1))),
  };
}

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.name,
    required this.institution,
    this.subtitle,
    this.branches = const [],
    this.selectedBranchId,
    this.onBranchChanged,
  });
  final String name;
  final String institution;
  final String? subtitle;
  final List<BranchRecord> branches;
  final String? selectedBranchId;
  final ValueChanged<String?>? onBranchChanged;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'صباح الخير' : 'مساء الخير';
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Image.asset('assets/images/farsha_logo.jpeg', width: 48, height: 48, fit: BoxFit.cover),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$greeting، $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(subtitle == null ? institution : '$institution • $subtitle', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
      ])),
      if (branches.length > 1 && onBranchChanged != null)
        PopupMenuButton<String?>(
          tooltip: 'اختيار الفرع',
          icon: const Icon(Icons.storefront_outlined),
          onSelected: onBranchChanged,
          itemBuilder: (_) => [
            const PopupMenuItem<String?>(value: null, child: Text('كل الفروع')),
            ...branches.map((b) => PopupMenuItem<String?>(value: b.id, child: Text(b.name))),
          ],
        ),
      IconButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد تنبيهات جديدة'))), icon: const Icon(Icons.notifications_none_rounded)),
    ]);
  }
}

class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.value, required this.onChanged});
  final DashboardPeriod value;
  final ValueChanged<DashboardPeriod> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<DashboardPeriod>(
      showSelectedIcon: false,
      segments: DashboardPeriod.values.map((p) => ButtonSegment(value: p, label: Text(p.label))).toList(),
      selected: {value},
      onSelectionChanged: (v) => onChanged(v.first),
      style: ButtonStyle(visualDensity: VisualDensity.compact, shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ),
  );
}

class HeroMetricCard extends StatelessWidget {
  const HeroMetricCard({super.key, required this.title, required this.value, this.caption, this.child, this.icon = Icons.trending_up_rounded});
  final String title;
  final String value;
  final String? caption;
  final Widget? child;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xff861B2C), Color(0xffA32B3E)], begin: Alignment.topRight, end: Alignment.bottomLeft),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [BoxShadow(color: farshaBurgundy.withValues(alpha: .14), blurRadius: 22, offset: const Offset(0, 8))],
    ),
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))), Icon(icon, color: Colors.white70)]),
      const SizedBox(height: 8),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900))),
      if (caption != null) ...[const SizedBox(height: 4), Text(caption!, style: const TextStyle(color: Colors.white70, fontSize: 12))],
      if (child != null) ...[const SizedBox(height: 16), child!],
    ]),
  );
}

class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.title, required this.value, required this.icon, this.accent = infoBlue, this.subtitle});
  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: accent, size: 19)),
        const Spacer(),
        Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        const SizedBox(height: 3),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
        if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 10)),
      ]),
    ),
  );
}

class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final width = (c.maxWidth - 10) / 2;
    return Wrap(spacing: 10, runSpacing: 10, children: children.map((x) => SizedBox(width: width, height: 132, child: x)).toList());
  });
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 10),
    child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
    ]),
  );
}

class QuickActionData {
  const QuickActionData(this.label, this.icon, this.onTap, {this.accent = farshaBurgundy});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;
}

class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.actions});
  final List<QuickActionData> actions;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: actions.map((a) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: a.onTap,
        child: Container(
          width: 92,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xffEAE3DA))),
          child: Column(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: a.accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)), child: Icon(a.icon, color: a.accent, size: 20)),
            const SizedBox(height: 7),
            Text(a.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    )).toList()),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.subtitle, this.icon = Icons.inbox_outlined, this.actionLabel, this.onAction});
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xffEAE3DA))),
    child: Column(children: [
      Icon(icon, size: 38, color: Colors.grey.shade400),
      const SizedBox(height: 10),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
      if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 12))],
      if (actionLabel != null && onAction != null) ...[const SizedBox(height: 10), TextButton.icon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(actionLabel!))],
    ]),
  );
}

class MiniLineChart extends StatelessWidget {
  const MiniLineChart({super.key, required this.values, this.color = infoBlue, this.height = 120});
  final List<double> values;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) {
    if (values.isEmpty || values.every((x) => x == 0)) return const EmptyState(title: 'لا توجد بيانات كافية للرسم خلال هذه الفترة', icon: Icons.show_chart);
    return SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _LinePainter(values, color)));
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    if (maxValue <= 0) return;
    final step = values.length <= 1 ? size.width : size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = step * i;
      final y = size.height - (values[i] / maxValue * (size.height - 10)) - 5;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    final fill = Path.from(path)..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)]).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 2.4..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }
  @override bool shouldRepaint(covariant _LinePainter oldDelegate) => oldDelegate.values != values || oldDelegate.color != color;
}

class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.values, required this.labels});
  final Map<String, double> values;
  final Map<String, String> labels;
  static const colors = [infoBlue, positiveGreen, warningOrange, partnerPurple, farshaBurgundy, Color(0xff2E8B8B), dangerRed];

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return const EmptyState(title: 'لا توجد عمليات تحصيل في هذه الفترة', icon: Icons.donut_large);
    final total = entries.fold<double>(0, (a, b) => a + b.value);
    return Row(children: [
      SizedBox(width: 118, height: 118, child: CustomPaint(painter: _DonutPainter(entries.map((e) => e.value).toList()))),
      const SizedBox(width: 16),
      Expanded(child: Column(children: entries.asMap().entries.map((x) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: colors[x.key % colors.length], shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Expanded(child: Text(labels[x.value.key] ?? x.value.key, style: const TextStyle(fontSize: 12))),
          Text('${(x.value.value / total * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      )).toList())),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    var start = -1.5708;
    final rect = Offset.zero & size;
    for (var i = 0; i < values.length; i++) {
      final sweep = total == 0 ? 0.0 : values[i] / total * 6.28318;
      canvas.drawArc(rect.deflate(14), start, sweep, false, Paint()..color = DonutChart.colors[i % DonutChart.colors.length]..style = PaintingStyle.stroke..strokeWidth = 18..strokeCap = StrokeCap.butt);
      start += sweep;
    }
  }
  @override bool shouldRepaint(covariant _DonutPainter oldDelegate) => oldDelegate.values != values;
}

class BranchBarChart extends StatelessWidget {
  const BranchBarChart({super.key, required this.rows, this.metric = 'sales'});
  final List<BranchReportRecord> rows;
  final String metric;
  double value(BranchReportRecord r) => switch (metric) { 'profit' => r.profit - r.expenses, 'length' => r.length, _ => r.sales };

  @override
  Widget build(BuildContext context) {
    final active = rows.where((r) => value(r) > 0).toList();
    if (active.isEmpty) return const EmptyState(title: 'لا توجد بيانات فروع في هذه الفترة', icon: Icons.bar_chart);
    final maxValue = active.map(value).reduce((a, b) => a > b ? a : b);
    return Column(children: active.map((r) {
      final ratio = maxValue == 0 ? 0.0 : value(r) / maxValue;
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
        SizedBox(width: 74, child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ratio, minHeight: 13, backgroundColor: const Color(0xffEFE9E2), color: infoBlue))),
        const SizedBox(width: 8),
        SizedBox(width: 76, child: Text(metric == 'length' ? '${value(r).toStringAsFixed(1)} م' : farshaMoney(value(r)), textAlign: TextAlign.left, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
      ]));
    }).toList());
  }
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.centerText, this.size = 112});
  final double value;
  final String centerText;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: Stack(alignment: Alignment.center, children: [
    SizedBox(width: size, height: size, child: CircularProgressIndicator(value: value.clamp(0, 1), strokeWidth: 9, backgroundColor: const Color(0xffEFE9E2), color: positiveGreen, strokeCap: StrokeCap.round)),
    Text(centerText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
  ]));
}
