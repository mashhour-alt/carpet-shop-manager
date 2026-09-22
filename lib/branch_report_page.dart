import 'package:flutter/material.dart';
import 'cloud_models.dart';
import 'farsha_repository.dart';

class BranchReportPage extends StatelessWidget {
  const BranchReportPage({super.key, required this.membership, required this.repository});

  final InstitutionMembership membership;
  final FarshaRepository repository;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 1);

    return FutureBuilder<List<BranchReportRecord>>(
      future: repository.loadBranchReport(membership.institutionId, from, to),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'تقرير الفروع • هذا الشهر',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...snapshot.data!.map(
              (x) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        x.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          Text('المبيعات ⃁ ' + x.sales.toStringAsFixed(2)),
                          Text('التكلفة ⃁ ' + x.cost.toStringAsFixed(2)),
                          Text('الربح ⃁ ' + x.profit.toStringAsFixed(2)),
                          Text('المصروفات ⃁ ' + x.expenses.toStringAsFixed(2)),
                          Text('الأمتار ' + x.length.toStringAsFixed(2)),
                          Text('م² ' + x.area.toStringAsFixed(2)),
                          Text('العمليات ' + x.count.toString()),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
