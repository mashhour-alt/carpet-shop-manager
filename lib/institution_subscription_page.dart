import 'package:flutter/material.dart';

import 'cloud_models.dart';
import 'farsha_repository.dart';

/// Owner-only status page. Provider activation is intentionally absent until
/// real Play Console products and server-side receipt verification exist.
class InstitutionSubscriptionPage extends StatelessWidget {
  const InstitutionSubscriptionPage({super.key, required this.membership, required this.repository});
  final InstitutionMembership membership;
  final FarshaRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('اشتراك المؤسسة')),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: repository.loadSubscriptionEntitlement(membership.institutionId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return const Center(child: Text('تعذر تحميل حالة الاشتراك.'));
            final entitlement = snapshot.data;
            if (entitlement == null) return const Center(child: Text('تعذر تحميل حالة الاشتراك.'));
            final status = entitlement['status'] as String;
            final entitled = entitlement['is_entitled'] == true;
            final expiry = entitlement['expires_at']?.toString();
            return ListView(padding: const EdgeInsets.all(20), children: [
              Icon(entitled ? Icons.verified_outlined : Icons.info_outline, size: 52, color: entitled ? Colors.green : Colors.orange),
              const SizedBox(height: 12),
              Text(entitled ? 'المؤسسة مفعّلة' : 'الاشتراك يحتاج متابعة', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 18),
              Card(child: ListTile(title: const Text('الحالة'), subtitle: Text(status), trailing: expiry == null ? null : Text('حتى $expiry'))),
              const SizedBox(height: 12),
              const Text('الاشتراك يخص المؤسسة فقط. لا يحتاج البائع أو المحاسب أو السائق إلى شراء اشتراك.'),
              const SizedBox(height: 12),
              const Text('ربط Google Play سيظهر هنا بعد إنشاء منتجات فعلية في Play Console وتفعيل التحقق الخادمي من الإيصالات.'),
            ]);
          },
        ),
      );
}
