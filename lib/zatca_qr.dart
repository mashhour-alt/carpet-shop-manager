import 'dart:convert';

import 'cloud_models.dart';

/// Builds the Base64 TLV payload required for Saudi e-invoices in Phase One.
///
/// Tags 1-5 are seller name, seller VAT number, issue timestamp, total with
/// VAT, and VAT total. Phase Two cryptographic tags must come from an actual
/// ZATCA clearance/reporting integration and are intentionally not fabricated.
String buildZatcaQrPayloadFromSnapshot({
  required String sellerName,
  required String sellerVatNumber,
  required DateTime issuedAt,
  required InvoiceFinancialSnapshot snapshot,
}) => buildZatcaQrPayload(
  sellerName: sellerName,
  sellerVatNumber: sellerVatNumber,
  issuedAt: issuedAt,
  totalWithVat: snapshot.payableAmount,
  vatAmount: snapshot.vatAmount,
);

String buildZatcaQrPayload({
  required String sellerName,
  required String sellerVatNumber,
  required DateTime issuedAt,
  required double totalWithVat,
  required double vatAmount,
}) {
  final bytes = <int>[];

  void addField(int tag, String value) {
    final encoded = utf8.encode(value);
    if (encoded.length > 255) {
      throw ArgumentError.value(value, 'value', 'ZATCA TLV field exceeds 255 bytes');
    }
    bytes.addAll([tag, encoded.length, ...encoded]);
  }

  addField(1, sellerName.trim());
  addField(2, sellerVatNumber.trim());
  addField(3, issuedAt.toUtc().toIso8601String());
  addField(4, totalWithVat.toStringAsFixed(2));
  addField(5, vatAmount.toStringAsFixed(2));
  return base64Encode(bytes);
}

Map<int, String> decodeZatcaQrPayload(String payload) {
  final bytes = base64Decode(payload);
  final fields = <int, String>{};
  var offset = 0;
  while (offset < bytes.length) {
    final tag = bytes[offset++];
    final length = bytes[offset++];
    final end = offset + length;
    if (end > bytes.length) throw const FormatException('Invalid TLV payload');
    fields[tag] = utf8.decode(bytes.sublist(offset, end));
    offset = end;
  }
  return fields;
}
