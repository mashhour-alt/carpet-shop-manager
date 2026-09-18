import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'cloud_models.dart';
import 'farsha_repository.dart';

String _invoiceDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _invoiceNumber(int value) => value.toString().padLeft(6, '0');

String _paymentLabel(String method) => switch (method) {
      'cash' => 'كاش',
      'network' => 'شبكة',
      'visa' => 'Visa',
      'tabby' => 'Tabby',
      'tamara' => 'Tamara',
      _ => method,
    };

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key, required this.membership, required this.repository});

  final InstitutionMembership membership;
  final FarshaRepository repository;

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  late Future<List<SaleInvoiceCandidate>> _sales =
      widget.repository.loadSalesForInvoicing(widget.membership.institutionId);
  late Future<List<TaxInvoiceRecord>> _invoices =
      widget.repository.loadTaxInvoices(widget.membership.institutionId);

  void _reload() => setState(() {
        _sales = widget.repository.loadSalesForInvoicing(widget.membership.institutionId);
        _invoices = widget.repository.loadTaxInvoices(widget.membership.institutionId);
      });

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _issue(List<SaleInvoiceCandidate> sales) async {
    final available = sales.where((sale) => !sale.hasInvoice).toList();
    if (available.isEmpty) return _message('لا توجد مبيعات جديدة تحتاج فاتورة');
    var saleId = available.first.id;
    final customer = TextEditingController(text: available.first.customerName);
    final commercialRegistration = TextEditingController();
    final taxNumber = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إصدار فاتورة اختيارية'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: saleId,
                decoration: const InputDecoration(labelText: 'اختر البيعة'),
                items: available
                    .map((sale) => DropdownMenuItem(
                          value: sale.id,
                          child: Text('${sale.itemName} • ${sale.color} • ${sale.total.toStringAsFixed(2)} ر.س'),
                        ))
                    .toList(),
                onChanged: (value) {
                  setDialogState(() => saleId = value!);
                  final selected = available.firstWhere((sale) => sale.id == value);
                  customer.text = selected.customerName;
                },
              ),
              const SizedBox(height: 10),
              TextField(controller: customer, decoration: const InputDecoration(labelText: 'اسم المشتري')),
              const SizedBox(height: 10),
              TextField(controller: commercialRegistration, decoration: const InputDecoration(labelText: 'السجل التجاري (اختياري)')),
              const SizedBox(height: 10),
              TextField(controller: taxNumber, decoration: const InputDecoration(labelText: 'الرقم الضريبي (اختياري)')),
              const SizedBox(height: 10),
              const Text('سيتم احتساب VAT بنسبة 15% وإضافة QR ضريبي.'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إصدار الفاتورة')),
          ],
        ),
      ),
    );
    final customerValue = customer.text.trim();
    final crValue = commercialRegistration.text.trim();
    final taxValue = taxNumber.text.trim();
    customer.dispose();
    commercialRegistration.dispose();
    taxNumber.dispose();
    if (save != true) return;
    try {
      await widget.repository.issueTaxInvoice(
        saleId: saleId,
        customerName: customerValue,
        customerCommercialRegistration: crValue,
        customerTaxNumber: taxValue,
      );
      _message('تم إصدار الفاتورة الضريبية');
      _reload();
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _open(TaxInvoiceRecord invoice) async {
    final institution = await widget.repository
        .loadInstitutionDocumentDetails(widget.membership.institutionId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => TaxInvoiceDocumentDialog(institution: institution, invoice: invoice),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SaleInvoiceCandidate>>(
        future: _sales,
        builder: (context, salesSnapshot) => FutureBuilder<List<TaxInvoiceRecord>>(
          future: _invoices,
          builder: (context, invoiceSnapshot) {
            if (!salesSnapshot.hasData || !invoiceSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final invoices = invoiceSnapshot.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              FilledButton.icon(
                onPressed: () => _issue(salesSnapshot.data!),
                icon: const Icon(Icons.receipt_long),
                label: const Text('إصدار فاتورة من بيعة'),
              ),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('الفاتورة اختيارية، والبيعة تظل محفوظة حتى لو لم تُصدر فاتورة.'),
                ),
              ),
              if (invoices.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد فواتير صادرة بعد.'))),
              ...invoices.map((invoice) => Card(
                    child: ListTile(
                      onTap: () => _open(invoice),
                      leading: const Icon(Icons.qr_code_2),
                      title: Text('فاتورة #${_invoiceNumber(invoice.invoiceNumber)}'),
                      subtitle: Text('${invoice.customerName} • ${_invoiceDate(invoice.issuedAt)}\n${invoice.totalWithVat.toStringAsFixed(2)} ر.س شامل VAT'),
                      trailing: const Icon(Icons.open_in_new),
                    ),
                  )),
            ]);
          },
        ),
      );
}

class TaxInvoiceDocumentDialog extends StatefulWidget {
  const TaxInvoiceDocumentDialog({super.key, required this.institution, required this.invoice});

  final InstitutionDocumentDetails institution;
  final TaxInvoiceRecord invoice;

  @override
  State<TaxInvoiceDocumentDialog> createState() => _TaxInvoiceDocumentDialogState();
}

class _TaxInvoiceDocumentDialogState extends State<TaxInvoiceDocumentDialog> {
  final GlobalKey _documentKey = GlobalKey();
  bool _busy = false;

  Future<Uint8List> _pdfBytes() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final boundary = _documentKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final document = pw.Document();
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(pw.MemoryImage(png!.buffer.asUint8List()), fit: pw.BoxFit.fill),
    ));
    return document.save();
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await Printing.sharePdf(
        bytes: await _pdfBytes(),
        filename: 'farsha-invoice-${_invoiceNumber(widget.invoice.invoiceNumber)}.pdf',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdfBytes();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text('فاتورة #${_invoiceNumber(widget.invoice.invoiceNumber)}'),
            leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            actions: [
              IconButton(onPressed: _busy ? null : _print, icon: const Icon(Icons.print_outlined)),
              IconButton(onPressed: _busy ? null : _share, icon: const Icon(Icons.share_outlined)),
            ],
          ),
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _documentKey,
                child: TaxInvoiceDocument(institution: widget.institution, invoice: widget.invoice),
              ),
            ),
          ),
        ),
      );
}

class TaxInvoiceDocument extends StatelessWidget {
  const TaxInvoiceDocument({super.key, required this.institution, required this.invoice});

  final InstitutionDocumentDetails institution;
  final TaxInvoiceRecord invoice;

  String get qrPayload {
    final bytes = <int>[];
    void add(int tag, String value) {
      final encoded = utf8.encode(value);
      bytes.addAll([tag, encoded.length, ...encoded]);
    }
    add(1, institution.name);
    add(2, institution.taxNumber);
    add(3, invoice.issuedAt.toUtc().toIso8601String());
    add(4, invoice.totalWithVat.toStringAsFixed(2));
    add(5, invoice.vatAmount.toStringAsFixed(2));
    return base64Encode(bytes);
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: Container(
          width: 595,
          height: 842,
          padding: const EdgeInsets.all(34),
          color: Colors.white,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.black87, fontSize: 13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Image.asset('assets/images/farsha_logo.jpeg', width: 78, height: 78),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(institution.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(institution.address),
                    Text('${institution.phone} • ${institution.email}'),
                    Text('السجل: ${institution.commercialRegistration}'),
                    Text('الرقم الضريبي: ${institution.taxNumber}'),
                  ])),
                ]),
                const Divider(height: 26, thickness: 2),
                const Text('فاتورة ضريبية مبسطة', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('رقم الفاتورة: ${_invoiceNumber(invoice.invoiceNumber)}'),
                  Text('التاريخ: ${_invoiceDate(invoice.issuedAt)}'),
                  Text('الدفع: ${_paymentLabel(invoice.paymentMethod)}'),
                ]),
                const SizedBox(height: 14),
                Text('المشتري: ${invoice.customerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (invoice.customerCommercialRegistration.isNotEmpty)
                  Text('السجل التجاري: ${invoice.customerCommercialRegistration}'),
                if (invoice.customerTaxNumber.isNotEmpty)
                  Text('الرقم الضريبي: ${invoice.customerTaxNumber}'),
                const SizedBox(height: 16),
                Container(
                  color: const Color(0xff8b1e2d),
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                  child: const Row(children: [
                    Expanded(flex: 3, child: Text('البيان', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    Expanded(child: Text('الكمية', style: TextStyle(color: Colors.white))),
                    Expanded(child: Text('السعر', style: TextStyle(color: Colors.white))),
                    Expanded(child: Text('الإجمالي', style: TextStyle(color: Colors.white))),
                  ]),
                ),
                _itemLine('${invoice.itemName} • ${invoice.color}\n${invoice.length.toStringAsFixed(2)}م × ${invoice.width.toStringAsFixed(0)}م', invoice.area, invoice.pricePerSquareMeter, invoice.carpetAmount),
                if (invoice.installationAmount > 0) _itemLine('تركيب', 1, invoice.installationAmount, invoice.installationAmount),
                if (invoice.glueAmount > 0) _itemLine('غراء', invoice.glueGallons, invoice.glueGallons == 0 ? invoice.glueAmount : invoice.glueAmount / invoice.glueGallons, invoice.glueAmount),
                if (invoice.ironAmount > 0) _itemLine('حديد', invoice.ironPieces, invoice.ironPieces == 0 ? invoice.ironAmount : invoice.ironAmount / invoice.ironPieces, invoice.ironAmount),
                if (invoice.driverFee > 0) _itemLine('توصيل', 1, invoice.driverFee, invoice.driverFee),
                const SizedBox(height: 18),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  QrImageView(data: qrPayload, version: QrVersions.auto, size: 145, backgroundColor: Colors.white),
                  const SizedBox(width: 20),
                  Expanded(child: Column(children: [
                    _totalLine('الإجمالي قبل الضريبة', invoice.subtotal),
                    _totalLine('VAT 15%', invoice.vatAmount),
                    const Divider(),
                    _totalLine('الإجمالي شامل الضريبة', invoice.totalWithVat, bold: true),
                  ])),
                ]),
                const Spacer(),
                const Text('شكرًا لتعاملكم مع فرشة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ),
      );

  Widget _itemLine(String name, double quantity, double price, double total) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12))),
        child: Row(children: [
          Expanded(flex: 3, child: Text(name)),
          Expanded(child: Text(quantity.toStringAsFixed(2))),
          Expanded(child: Text(price.toStringAsFixed(2))),
          Expanded(child: Text(total.toStringAsFixed(2))),
        ]),
      );

  Widget _totalLine(String label, double amount, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          Text('${amount.toStringAsFixed(2)} ر.س', style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
        ]),
      );
}
