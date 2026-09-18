import 'package:flutter/material.dart';

import 'cloud_models.dart';
import 'farsha_repository.dart';
import 'invoice_page.dart';
import 'quotation_page.dart';

class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key, required this.membership, required this.repository});

  final InstitutionMembership membership;
  final FarshaRepository repository;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(children: [
          const Material(
            child: TabBar(tabs: [
              Tab(icon: Icon(Icons.request_quote_outlined), text: 'عروض الأسعار'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'الفواتير'),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              QuotationsPage(membership: membership, repository: repository),
              InvoicesPage(membership: membership, repository: repository),
            ]),
          ),
        ]),
      );
}
