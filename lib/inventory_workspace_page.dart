import 'package:flutter/material.dart';

import 'cloud_models.dart';
import 'farsha_repository.dart';
import 'materials_page.dart';
import 'operations_pages.dart';

/// The sole operational entry point for physical stock.  It deliberately keeps
/// the established carpet and add-on data models separate: they use different
/// units and deduction rules.
class InventoryWorkspacePage extends StatelessWidget {
  const InventoryWorkspacePage({super.key, required this.membership, required this.repository});
  final InstitutionMembership membership;
  final FarshaRepository repository;

  @override
  Widget build(BuildContext context) {
    final canManageMaterials = membership.role != InstitutionRole.seller;
    return DefaultTabController(
      length: canManageMaterials ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المخزون'),
          bottom: TabBar(tabs: [
            const Tab(text: 'الموكيت'),
            if (canManageMaterials) const Tab(text: 'المستلزمات'),
          ]),
        ),
        body: TabBarView(children: [
          InstitutionOperationsPage(membership: membership, repository: repository),
          if (canManageMaterials) MaterialsPage(membership: membership, repository: repository),
        ]),
      ),
    );
  }
}
