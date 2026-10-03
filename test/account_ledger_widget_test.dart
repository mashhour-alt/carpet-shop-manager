import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:farsha/account_statements_page.dart';
import 'package:farsha/cloud_models.dart';
import 'package:farsha/farsha_repository.dart';
import 'package:farsha/operations_pages.dart';
import 'package:farsha/ui_v2_shell.dart';

class TestLedgerRepository extends FarshaRepository {
  TestLedgerRepository() : super(SupabaseClient('https://example.supabase.co', 'test',authOptions:const AuthClientOptions(autoRefreshToken:false)));
  final events = StreamController<void>.broadcast();
  double balance = 400;
  int loads = 0;
  @override Stream<void> get accountChanges => events.stream;
  @override Future<Map<String,dynamic>> loadAccountLedger(String institutionId, String party, String partyId, DateTime from, DateTime to) async {
    loads++;
    return {'current_balance':balance,'opening_balance':400,'closing_balance':400,'gross':0,'paid':0,'movements':<Map<String,dynamic>>[]};
  }
  @override Future<List<AccountSummaryRecord>> loadAccountSummaries(String institutionId,String party,DateTime from,DateTime to) async => [];
}
const member = InstitutionMembership(institutionId:'institution',institutionName:'Test',role:InstitutionRole.owner,status:'active');
void main() {
  testWidgets('current balance survives empty period and refreshes on an event; listener is disposed', (tester) async {
    final repo=TestLedgerRepository();
    await tester.pumpWidget(MaterialApp(home:StatementDetailPage(membership:member,repository:repo,party:'seller',partyId:'seller',partyName:'Ahmed',from:DateTime(2026,2),to:DateTime(2026,3),allowEntry:false)));
    await tester.pumpAndSettle();
    expect(find.text('الرصيد الحالي • له'),findsOneWidget);
    expect(find.text('لا توجد حركات في الفترة المحددة'),findsOneWidget);
    repo.balance=-112;repo.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('الرصيد الحالي • عليه'),findsOneWidget);
    expect(find.textContaining('112.00'),findsOneWidget);
    expect(repo.loads,2);
    await tester.pumpWidget(const SizedBox());
    expect(repo.events.hasListener,isFalse);
    await repo.events.close();
  });
  testWidgets('Accounts financial entry opens accounts and never the sales form', (tester) async {
    final repo=TestLedgerRepository();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:AccountsHubV2(membership:member,repository:repo))));
    await tester.tap(find.text('التسويات والمصروفات'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountStatementsPage),findsOneWidget);
    expect(find.byType(SalesSettlementPage),findsNothing);
    await tester.pumpWidget(const SizedBox());await repo.events.close();
  });
}
