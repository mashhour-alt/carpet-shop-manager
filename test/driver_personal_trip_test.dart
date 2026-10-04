import 'package:farsha/cloud_models.dart';
import 'package:farsha/farsha_repository.dart';
import 'package:farsha/home_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverDashboardRepository extends FarshaRepository {
  DriverDashboardRepository()
      : super(SupabaseClient('https://example.supabase.co', 'test', authOptions: const AuthClientOptions(autoRefreshToken: false)));

  @override
  Stream<void> get accountChanges => const Stream.empty();

  @override
  Future<List<DriverTrip>> loadDriverTrips() async => [
        DriverTrip.personalFromMap({
          'id': 'personal-trip',
          'shop_name': 'محل خارجي',
          'trip_at': DateTime.now().toUtc().toIso8601String(),
          'amount': 75,
          'payment_status': 'unpaid',
          'payment_method': null,
        }),
      ];

  @override
  Future<List<Map<String, dynamic>>> loadMyDriverConnections() async => [];

  @override
  Future<List<Map<String, dynamic>>> loadAccountNotifications() async => [];
}

void main() {
  test('personal trip stays separate and paid/remaining values are correct', () {
    final personal = DriverTrip.personalFromMap({
      'id': 'personal-trip',
      'shop_name': 'محل خارجي',
      'customer_name': 'عميل',
      'trip_at': '2026-10-04T10:00:00Z',
      'amount': 75,
      'payment_status': 'unpaid',
      'payment_method': null,
    });
    final institution = DriverTrip.fromMap({
      'id': 'institution-trip',
      'trip_date': '2026-10-04',
      'amount': 25,
      'payment_status': 'paid',
      'payment_method': 'cash',
      'institutions': {'name': 'مؤسسة فرشة'},
      'profiles': {'full_name': 'بائع'},
    });

    expect(personal.isPersonal, isTrue);
    expect(personal.institutionName, 'محل خارجي');
    expect(institution.isPersonal, isFalse);
    final trips = [personal, institution];
    final total = trips.fold<double>(0, (sum, trip) => sum + trip.amount);
    final paid = trips.where((trip) => trip.paymentStatus == 'paid').fold<double>(0, (sum, trip) => sum + trip.amount);
    expect(total, 100);
    expect(paid, 25);
    expect(total - paid, 75);
  });

  testWidgets('driver dashboard always exposes add trip and logout', (tester) async {
    final repository = DriverDashboardRepository();
    await tester.pumpWidget(MaterialApp(
      home: DriverHome(
        profile: const UserProfile(id: 'driver', fullName: 'سائق اختبار', phone: '', accountKind: AccountKind.driver, onboardingMode: 'driver'),
        repository: repository,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('+ إضافة مشوار'), findsOneWidget);
    await tester.tap(find.byTooltip('الحساب والإعدادات'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل الخروج'), findsOneWidget);
  });
}
