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
import 'zatca_qr.dart';

String _invoiceDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _invoiceTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _invoiceNumber(int value) => value.toString().padLeft(6, '0');

String _money(double value) => value.toStringAsFixed(2);

String _paymentLabel(String method) => switch (method) {
      'cash' => 'نقدي / Cash',
      'network' => 'شبكة / Mada',
      'visa' => 'فيزا / Visa',
      'tabby' => 'تابي / Tabby',
      'tamara' => 'تمارا / Tamara',
      _ => method,
    };

String _invoiceKindLabel(String kind) =>
    kind == 'tax' ? 'فاتورة ضريبية' : 'فاتورة ضريبية مبسطة';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({
    super.key,
    required this.membership,
    required this.repository,
  });

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
        _sales = widget.repository
            .loadSalesForInvoicing(widget.membership.institutionId);
        _invoices =
            widget.repository.loadTaxInvoices(widget.membership.institutionId);
      });

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _issue(List<SaleInvoiceCandidate> sales) async {
    final available = sales.where((sale) => !sale.hasInvoice).toList();
    if (available.isEmpty) {
      _message('لا توجد مبيعات جديدة تحتاج فاتورة');
      return;
    }

    var saleId = available.first.id;
    var invoiceKind = 'simplified';
    final customer = TextEditingController(text: available.first.customerName);
    final commercialRegistration = TextEditingController();
    final taxNumber = TextEditingController();
    final customerAddress = TextEditingController();
    final discount = TextEditingController(text: '0');

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إصدار فاتورة ضريبية'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: invoiceKind,
                  decoration: const InputDecoration(labelText: 'نوع الفاتورة'),
                  items: const [
                    DropdownMenuItem(
                      value: 'simplified',
                      child: Text('فاتورة ضريبية مبسطة (غالبًا للأفراد)'),
                    ),
                    DropdownMenuItem(
                      value: 'tax',
                      child: Text('فاتورة ضريبية (للمنشآت)'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => invoiceKind = value!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: saleId,
                  decoration: const InputDecoration(labelText: 'اختر البيعة'),
                  items: available
                      .map(
                        (sale) => DropdownMenuItem(
                          value: sale.id,
                          child: Text(
                            '${sale.itemName} • ${sale.color} • ${_money(sale.total)} ر.س',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => saleId = value!);
                    customer.text = available
                        .firstWhere((sale) => sale.id == value)
                        .customerName;
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: customer,
                  decoration: const InputDecoration(labelText: 'اسم المشتري'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: commercialRegistration,
                  decoration:
                      const InputDecoration(labelText: 'السجل التجاري للمشتري'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: taxNumber,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'الرقم الضريبي للمشتري'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: customerAddress,
                  decoration:
                      const InputDecoration(labelText: 'عنوان المشتري'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: discount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'الخصم (ر.س)',
                    suffixText: 'SAR',
                  ),
                ),
                if (invoiceKind == 'tax') ...[
                  const SizedBox(height: 10),
                  const Text(
                    'اسم المشتري ورقمه الضريبي وعنوانه مطلوبة للفاتورة الضريبية.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إصدار الفاتورة'),
            ),
          ],
        ),
      ),
    );

    final customerValue = customer.text.trim();
    final crValue = commercialRegistration.text.trim();
    final taxValue = taxNumber.text.trim();
    final addressValue = customerAddress.text.trim();
    final discountValue = double.tryParse(discount.text.trim());
    customer.dispose();
    commercialRegistration.dispose();
    taxNumber.dispose();
    customerAddress.dispose();
    discount.dispose();

    if (save != true) return;
    if (discountValue == null || discountValue < 0) {
      _message('أدخل قيمة خصم صحيحة');
      return;
    }
    if (invoiceKind == 'tax' &&
        (customerValue.isEmpty ||
            taxValue.isEmpty ||
            addressValue.isEmpty)) {
      _message('بيانات المشتري الأساسية مطلوبة للفاتورة الضريبية');
      return;
    }

    try {
      await widget.repository.issueTaxInvoice(
        saleId: saleId,
        customerName: customerValue,
        customerCommercialRegistration: crValue,
        customerTaxNumber: taxValue,
        customerAddress: addressValue,
        invoiceKind: invoiceKind,
        discountAmount: discountValue,
      );
      _message('تم إصدار ${_invoiceKindLabel(invoiceKind)}');
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
      builder: (_) => TaxInvoiceDocumentDialog(
        institution: institution,
        invoice: invoice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<SaleInvoiceCandidate>>(
        future: _sales,
        builder: (context, salesSnapshot) =>
            FutureBuilder<List<TaxInvoiceRecord>>(
          future: _invoices,
          builder: (context, invoiceSnapshot) {
            if (!salesSnapshot.hasData || !invoiceSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final invoices = invoiceSnapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  onPressed: () => _issue(salesSnapshot.data!),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('إصدار فاتورة من بيعة'),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'اختر نوع الفاتورة وأدخل بيانات المشتري والخصم. المخزون خُصم عند حفظ البيعة.',
                    ),
                  ),
                ),
                if (invoices.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('لا توجد فواتير صادرة بعد.'),
                    ),
                  ),
                ...invoices.map(
                  (invoice) => Card(
                    child: ListTile(
                      onTap: () => _open(invoice),
                      leading: const Icon(Icons.qr_code_2),
                      title: Text(
                        '${_invoiceKindLabel(invoice.invoiceKind)} #${_invoiceNumber(invoice.invoiceNumber)}',
                      ),
                      subtitle: Text(
                        '${invoice.customerName} • ${_invoiceDate(invoice.issuedAt)}\n'
                        '${_money(invoice.totalWithVat)} ر.س شامل الضريبة',
                      ),
                      trailing: const Icon(Icons.open_in_new),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class TaxInvoiceDocumentDialog extends StatefulWidget {
  const TaxInvoiceDocumentDialog({
    super.key,
    required this.institution,
    required this.invoice,
  });

  final InstitutionDocumentDetails institution;
  final TaxInvoiceRecord invoice;

  @override
  State<TaxInvoiceDocumentDialog> createState() =>
      _TaxInvoiceDocumentDialogState();
}

class _TaxInvoiceDocumentDialogState
    extends State<TaxInvoiceDocumentDialog> {
  final GlobalKey _documentKey = GlobalKey();
  bool _busy = false;

  Future<Uint8List> _pdfBytes() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final boundary =
        _documentKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final receiptWidth = 80 * PdfPageFormat.mm;
    final receiptHeight =
        receiptWidth * boundary.size.height / boundary.size.width;
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(receiptWidth, receiptHeight, marginAll: 0),
        build: (_) => pw.Image(
          pw.MemoryImage(png!.buffer.asUint8List()),
          fit: pw.BoxFit.fill,
        ),
      ),
    );
    return document.save();
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await Printing.sharePdf(
        bytes: await _pdfBytes(),
        filename:
            'tax-invoice-${_invoiceNumber(widget.invoice.invoiceNumber)}.pdf',
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
            title: Text(
              '${_invoiceKindLabel(widget.invoice.invoiceKind)} #${_invoiceNumber(widget.invoice.invoiceNumber)}',
            ),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
            actions: [
              IconButton(
                onPressed: _busy ? null : _print,
                icon: const Icon(Icons.print_outlined),
              ),
              IconButton(
                onPressed: _busy ? null : _share,
                icon: const Icon(Icons.share_outlined),
              ),
            ],
          ),
          body: Center(
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _documentKey,
                child: TaxInvoiceDocument(
                  institution: widget.institution,
                  invoice: widget.invoice,
                ),
              ),
            ),
          ),
        ),
      );
}

class _InvoiceLine {
  const _InvoiceLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double subtotal;
}

class TaxInvoiceDocument extends StatelessWidget {
  const TaxInvoiceDocument({
    super.key,
    required this.institution,
    required this.invoice,
  });

  final InstitutionDocumentDetails institution;
  final TaxInvoiceRecord invoice;

  List<_InvoiceLine> get _lines => [
        _InvoiceLine(
          description:
              '${invoice.itemName} - ${invoice.color}\n${_money(invoice.length)}م × ${_money(invoice.width)}م = ${_money(invoice.area)}م²',
          quantity: invoice.area,
          unitPrice: invoice.pricePerSquareMeter,
          subtotal: invoice.carpetAmount,
        ),
        if (invoice.installationAmount > 0)
          _InvoiceLine(
            description: 'تركيب / Installation',
            quantity: 1,
            unitPrice: invoice.installationAmount,
            subtotal: invoice.installationAmount,
          ),
        if (invoice.glueAmount > 0)
          _InvoiceLine(
            description: 'غراء / Glue',
            quantity: invoice.glueGallons,
            unitPrice: invoice.glueGallons == 0
                ? invoice.glueAmount
                : invoice.glueAmount / invoice.glueGallons,
            subtotal: invoice.glueAmount,
          ),
        if (invoice.ironAmount > 0)
          _InvoiceLine(
            description: 'حديد / Iron',
            quantity: invoice.ironPieces,
            unitPrice: invoice.ironPieces == 0
                ? invoice.ironAmount
                : invoice.ironAmount / invoice.ironPieces,
            subtotal: invoice.ironAmount,
          ),
        if (invoice.addonsAmount > 0)
          _InvoiceLine(
            description: invoice.addonsSummary.isEmpty ? 'إضافات / Add-ons' : invoice.addonsSummary,
            quantity: 1,
            unitPrice: invoice.addonsAmount,
            subtotal: invoice.addonsAmount,
          ),
        if (invoice.driverFee > 0)
          _InvoiceLine(
            description: 'توصيل / Delivery',
            quantity: 1,
            unitPrice: invoice.driverFee,
            subtotal: invoice.driverFee,
          ),
      ];

  String get qrPayload => buildZatcaQrPayload(
        sellerName: institution.name,
        sellerVatNumber: institution.taxNumber,
        issuedAt: invoice.issuedAt,
        totalWithVat: invoice.totalWithVat,
        vatAmount: invoice.vatAmount,
      );

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: Container(
          width: 420,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
          color: Colors.white,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Color(0xff161616),
                fontSize: 11,
                height: 1.35,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    institution.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(institution.address, textAlign: TextAlign.center),
                  Text(
                    '${institution.phone}  •  ${institution.email}',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1.5, color: const Color(0xff242424)),
                  const SizedBox(height: 12),
                  Text(
                    _invoiceKindLabel(invoice.invoiceKind),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    invoice.invoiceKind == 'tax'
                        ? 'TAX INVOICE'
                        : 'SIMPLIFIED TAX INVOICE',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    arLabel: 'الرقم الضريبي للبائع',
                    enLabel: 'Seller VAT No.',
                    value: institution.taxNumber,
                  ),
                  _InfoRow(
                    arLabel: 'السجل التجاري',
                    enLabel: 'Commercial Reg.',
                    value: institution.commercialRegistration,
                  ),
                  _InfoRow(
                    arLabel: 'رقم الفاتورة',
                    enLabel: 'Invoice No.',
                    value: _invoiceNumber(invoice.invoiceNumber),
                  ),
                  _InfoRow(
                    arLabel: 'تاريخ الإصدار',
                    enLabel: 'Issue Date',
                    value:
                        '${_invoiceDate(invoice.issuedAt)}  ${_invoiceTime(invoice.issuedAt)}',
                  ),
                  _InfoRow(
                    arLabel: 'اسم المشتري',
                    enLabel: 'Customer',
                    value: invoice.customerName,
                  ),
                  if (invoice.customerTaxNumber.isNotEmpty)
                    _InfoRow(
                      arLabel: 'ضريبة المشتري',
                      enLabel: 'Customer VAT',
                      value: invoice.customerTaxNumber,
                    ),
                  if (invoice.customerCommercialRegistration.isNotEmpty)
                    _InfoRow(
                      arLabel: 'سجل المشتري',
                      enLabel: 'Customer CR',
                      value: invoice.customerCommercialRegistration,
                    ),
                  if (invoice.customerAddress.isNotEmpty)
                    _InfoRow(
                      arLabel: 'عنوان المشتري',
                      enLabel: 'Customer Address',
                      value: invoice.customerAddress,
                    ),
                  _InfoRow(
                    arLabel: 'طريقة الدفع',
                    enLabel: 'Payment',
                    value: invoice.paymentSummary.isEmpty ? _paymentLabel(invoice.paymentMethod) : invoice.paymentSummary,
                  ),
                  _InfoRow(
                    arLabel: 'البائع',
                    enLabel: 'Seller',
                    value: invoice.sellerName,
                  ),
                  const SizedBox(height: 12),
                  const _ItemsHeader(),
                  ..._lines.asMap().entries.map(
                        (entry) => _ItemRow(
                          index: entry.key + 1,
                          line: entry.value,
                        ),
                      ),
                  const SizedBox(height: 12),
                  _TotalRow(
                    label: 'الإجمالي غير شامل الضريبة / Subtotal',
                    amount: invoice.subtotal,
                  ),
                  _TotalRow(
                    label: 'الخصم / Discount',
                    amount: invoice.discountAmount,
                    negative: invoice.discountAmount > 0,
                  ),
                  _TotalRow(
                    label: 'المبلغ الخاضع للضريبة / Taxable Amount',
                    amount: invoice.taxableAmount,
                  ),
                  _TotalRow(
                    label: 'ضريبة القيمة المضافة 15% / VAT',
                    amount: invoice.vatAmount,
                  ),
                  const Divider(height: 8, thickness: 1.2),
                  _TotalRow(
                    label: 'الإجمالي المستحق / Amount Due',
                    amount: invoice.totalWithVat,
                    bold: true,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'فقط ${_amountInArabic(invoice.totalWithVat)} ريال سعودي لا غير',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    arLabel: 'نوع الفاتورة',
                    enLabel: 'Invoice Type',
                    value: _invoiceKindLabel(invoice.invoiceKind),
                  ),
                  const _InfoRow(
                    arLabel: 'نوع التوريد',
                    enLabel: 'Supply Type',
                    value: 'محلي / Domestic',
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: QrImageView(
                      data: qrPayload,
                      version: QrVersions.auto,
                      size: 128,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.arLabel,
    required this.enLabel,
    required this.value,
  });

  final String arLabel;
  final String enLabel;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 116,
              child: Text(
                arLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(value)),
            SizedBox(
              width: 92,
              child: Text(
                enLabel,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 9, color: Color(0xff555555)),
              ),
            ),
          ],
        ),
      );
}

class _ItemsHeader extends StatelessWidget {
  const _ItemsHeader();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xffdedede),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: const Row(
          children: [
            SizedBox(width: 26, child: _HeaderCell('م')),
            Expanded(flex: 5, child: _HeaderCell('البيان / Description')),
            Expanded(flex: 2, child: _HeaderCell('الكمية / Qty')),
            Expanded(flex: 2, child: _HeaderCell('السعر / Price')),
            Expanded(flex: 2, child: _HeaderCell('الإجمالي / Total')),
          ],
        ),
      );
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold),
      );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.index, required this.line});

  final int index;
  final _InvoiceLine line;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xffdddddd))),
        ),
        child: Row(
          children: [
            SizedBox(width: 26, child: Text('$index', textAlign: TextAlign.center)),
            Expanded(flex: 5, child: Text(line.description, style: const TextStyle(fontSize: 9))),
            Expanded(flex: 2, child: Text(_money(line.quantity), textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text(_money(line.unitPrice), textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text(_money(line.subtotal), textAlign: TextAlign.center)),
          ],
        ),
      );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    this.bold = false,
    this.negative = false,
  });

  final String label;
  final double amount;
  final bool bold;
  final bool negative;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Text(
              '${negative ? '- ' : ''}${_money(amount)} ر.س',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: bold ? 13 : 11,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      );
}

String _amountInArabic(double value) {
  final riyals = value.floor();
  final halalas = ((value - riyals) * 100).round();
  final result = StringBuffer(_arabicNumber(riyals));
  if (halalas > 0) {
    result.write(' و${_arabicNumber(halalas)} هللة');
  }
  return result.toString();
}

String _arabicNumber(int value) {
  if (value == 0) return 'صفر';
  if (value < 0) return 'سالب ${_arabicNumber(-value)}';
  const ones = [
    '',
    'واحد',
    'اثنان',
    'ثلاثة',
    'أربعة',
    'خمسة',
    'ستة',
    'سبعة',
    'ثمانية',
    'تسعة',
    'عشرة',
    'أحد عشر',
    'اثنا عشر',
    'ثلاثة عشر',
    'أربعة عشر',
    'خمسة عشر',
    'ستة عشر',
    'سبعة عشر',
    'ثمانية عشر',
    'تسعة عشر',
  ];
  const tens = [
    '',
    '',
    'عشرون',
    'ثلاثون',
    'أربعون',
    'خمسون',
    'ستون',
    'سبعون',
    'ثمانون',
    'تسعون',
  ];
  const hundreds = [
    '',
    'مائة',
    'مائتان',
    'ثلاثمائة',
    'أربعمائة',
    'خمسمائة',
    'ستمائة',
    'سبعمائة',
    'ثمانمائة',
    'تسعمائة',
  ];
  if (value < 20) return ones[value];
  if (value < 100) {
    final unit = value % 10;
    return unit == 0 ? tens[value ~/ 10] : '${ones[unit]} و${tens[value ~/ 10]}';
  }
  if (value < 1000) {
    final rest = value % 100;
    return rest == 0
        ? hundreds[value ~/ 100]
        : '${hundreds[value ~/ 100]} و${_arabicNumber(rest)}';
  }
  if (value < 1000000) {
    final thousands = value ~/ 1000;
    final rest = value % 1000;
    final prefix = thousands == 1
        ? 'ألف'
        : thousands == 2
            ? 'ألفان'
            : thousands <= 10
                ? '${_arabicNumber(thousands)} آلاف'
                : '${_arabicNumber(thousands)} ألفًا';
    return rest == 0 ? prefix : '$prefix و${_arabicNumber(rest)}';
  }
  final millions = value ~/ 1000000;
  final rest = value % 1000000;
  final prefix = millions == 1
      ? 'مليون'
      : millions == 2
          ? 'مليونان'
          : '${_arabicNumber(millions)} ملايين';
  return rest == 0 ? prefix : '$prefix و${_arabicNumber(rest)}';
}
