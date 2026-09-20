import 'package:farsha/zatca_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ZATCA QR contains the five required phase-one fields', () {
    final issuedAt = DateTime.utc(2026, 9, 20, 9, 30);
    final payload = buildZatcaQrPayload(
      sellerName: 'مؤسسة اختبار',
      sellerVatNumber: '310123456700003',
      issuedAt: issuedAt,
      totalWithVat: 1300.19,
      vatAmount: 169.59,
    );
    final fields = decodeZatcaQrPayload(payload);

    expect(fields, hasLength(5));
    expect(fields[1], 'مؤسسة اختبار');
    expect(fields[2], '310123456700003');
    expect(fields[3], issuedAt.toIso8601String());
    expect(fields[4], '1300.19');
    expect(fields[5], '169.59');
  });
}
