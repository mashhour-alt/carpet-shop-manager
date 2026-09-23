import 'package:farsha/cloud_models.dart';
import 'package:farsha/zatca_qr.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceLineRecord line(int no,double gross,double discount,double vat) {
  final taxable=gross-discount;
  return InvoiceLineRecord(lineNo:no,sourceKind:no==1?'carpet':'addon',description:'Line $no',quantity:1,unitCode:'PCE',unitPrice:gross,grossAmount:gross,discountAmount:discount,taxableAmount:taxable,taxCategory:'S',vatRate:.15,vatAmount:vat,totalWithVat:taxable+vat);
}
InvoiceFinancialSnapshot snapshot(List<InvoiceLineRecord> lines) {
  double sum(double Function(InvoiceLineRecord) f)=>lines.fold(0,(a,b)=>a+f(b));
  return InvoiceFinancialSnapshot(version:2,currencyCode:'SAR',taxCategory:'S',lineExtensionAmount:sum((x)=>x.grossAmount),discountAmount:sum((x)=>x.discountAmount),taxExclusiveAmount:sum((x)=>x.taxableAmount),vatAmount:sum((x)=>x.vatAmount),taxInclusiveAmount:sum((x)=>x.totalWithVat),payableAmount:sum((x)=>x.totalWithVat),lines:lines);
}
void main() {
  test('multiple lines and addons preserve canonical parity',(){
    final s=snapshot([line(1,800,20,117),line(2,100,2.50,14.63),line(3,50,2.50,7.13)]);
    expect(s.lines.length,3); expect(s.isInternallyConsistent,isTrue);
    expect(s.lineExtensionAmount,950); expect(s.discountAmount,25); expect(s.taxExclusiveAmount,925); expect(s.vatAmount,138.76); expect(s.payableAmount,1063.76);
  });

  test('VAT rounding parity is represented by persisted line VAT',(){
    final s=snapshot([line(1,33.33,0,5.00),line(2,33.33,0,5.00),line(3,33.34,0,5.00)]);
    expect(s.vatAmount,15); expect(s.payableAmount,115); expect(s.isInternallyConsistent,isTrue);
  });

  test('split payment does not recalculate invoice financial snapshot',(){
    final s=snapshot([line(1,1000,100,135)]);
    const payments=[400.0,600.0];
    expect(payments.reduce((a,b)=>a+b),s.lineExtensionAmount);
    expect(s.lineExtensionAmount,1000); expect(s.discountAmount,100); expect(s.taxExclusiveAmount,900); expect(s.vatAmount,135);
  });

  test('QR monetary tags are sourced only from canonical snapshot',(){
    final issuedAt=DateTime.utc(2026,9,23,9,30);
    final s=snapshot([line(1,1000,100,135)]);
    final payload=buildZatcaQrPayloadFromSnapshot(sellerName:'مؤسسة اختبار',sellerVatNumber:'310123456700003',issuedAt:issuedAt,snapshot:s);
    final fields=decodeZatcaQrPayload(payload);
    expect(fields[4],s.payableAmount.toStringAsFixed(2));
    expect(fields[5],s.vatAmount.toStringAsFixed(2));
  });

  test('parity guard detects a mismatched snapshot',(){
    final good=snapshot([line(1,100,0,15)]);
    final bad=InvoiceFinancialSnapshot(version:2,currencyCode:'SAR',taxCategory:'S',lineExtensionAmount:good.lineExtensionAmount,discountAmount:0,taxExclusiveAmount:100,vatAmount:14.99,taxInclusiveAmount:115,payableAmount:115,lines:good.lines);
    expect(bad.isInternallyConsistent,isFalse);
  });
}
