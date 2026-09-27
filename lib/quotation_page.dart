import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'cloud_models.dart';
import 'farsha_repository.dart';
import 'operational_sale_totals.dart';

double _quoteNumber(TextEditingController controller) =>
    double.tryParse(controller.text.trim()) ?? 0;

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class QuotationsPage extends StatefulWidget {
  const QuotationsPage({super.key, required this.membership, required this.repository});

  final InstitutionMembership membership;
  final FarshaRepository repository;

  @override
  State<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends State<QuotationsPage> {
  late Future<List<QuotationRecord>> _quotations =
      widget.repository.loadQuotations(widget.membership.institutionId);
  late Future<List<InventoryRecord>> _inventory =
      widget.repository.loadInventory(widget.membership.institutionId);
  late Future<List<PersonOption>> _sellers =
      widget.repository.loadSellers(widget.membership.institutionId);
  late Future<List<AddonTypeRecord>> _addonTypes =
      widget.repository.loadAddonTypes(widget.membership.institutionId);

  void _reload() => setState(() {
        _quotations = widget.repository.loadQuotations(widget.membership.institutionId);
        _inventory = widget.repository.loadInventory(widget.membership.institutionId);
        _sellers = widget.repository.loadSellers(widget.membership.institutionId);
        _addonTypes = widget.repository.loadAddonTypes(widget.membership.institutionId);
      });

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<SaleAddonInput?> _pickAddon(List<AddonTypeRecord> types, double area) async {
    if (types.isEmpty) {
      _message('أضف أنواع الإضافات من إعدادات المؤسسة');
      return null;
    }
    var type = types.first;
    final quantity = TextEditingController(
        text: type.calculationBasis == 'sale_area' ? area.toStringAsFixed(2) : '1');
    final price = TextEditingController(text: type.defaultSalePrice.toStringAsFixed(2));
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة إلى عرض السعر'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: type.id,
              decoration: const InputDecoration(labelText: 'الإضافة'),
              items: types.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name))).toList(),
              onChanged: (value) => setDialogState(() {
                type = types.firstWhere((item) => item.id == value);
                quantity.text = type.calculationBasis == 'sale_area' ? area.toStringAsFixed(2) : '1';
                price.text = type.defaultSalePrice.toStringAsFixed(2);
              }),
            ),
            const SizedBox(height: 10),
            TextField(controller: quantity, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'الكمية (${type.unit})')),
            const SizedBox(height: 10),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر البيع للوحدة قبل VAT')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );
    final result = save == true && _quoteNumber(quantity) > 0 && _quoteNumber(price) >= 0
        ? SaleAddonInput(addonTypeId: type.id, name: type.name, unit: type.unit, quantity: _quoteNumber(quantity), saleUnitPrice: _quoteNumber(price), costUnitPrice: type.defaultCostPrice)
        : null;
    quantity.dispose();
    price.dispose();
    return result;
  }

  Future<void> _create(List<InventoryRecord> inventory, List<PersonOption> sellers, List<AddonTypeRecord> addonTypes) async {
    if (inventory.isEmpty || sellers.isEmpty) {
      return _message('أضف مخزونًا وبائعًا أولًا');
    }
    final customer = TextEditingController();
    final customerCr = TextEditingController();
    final customerTax = TextEditingController();
    final length = TextEditingController();
    final price = TextEditingController();
    final discount = TextEditingController(text: '0');
    final notes = TextEditingController();
    final addons = <SaleAddonInput>[];
    String inventoryId = inventory.first.id;
    String sellerId = widget.membership.role == InstitutionRole.seller
        ? widget.repository.userId
        : sellers.first.id;
    DateTime validUntil = DateTime.now().add(const Duration(days: 14));
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totals = OperationalSaleTotals.calculate(
            carpetArea: _quoteNumber(length) * 4,
            carpetUnitPrice: _quoteNumber(price),
            addonSales: addons.fold(0, (sum, addon) => sum + addon.saleTotal),
            discount: _quoteNumber(discount),
          );
          return AlertDialog(
          title: const Text('عرض سعر جديد'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.membership.role != InstitutionRole.seller) ...[
                DropdownButtonFormField<String>(
                  initialValue: sellerId,
                  decoration: const InputDecoration(labelText: 'البائع'),
                  items: sellers
                      .map((seller) => DropdownMenuItem(value: seller.id, child: Text(seller.name)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => sellerId = value!),
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                initialValue: inventoryId,
                decoration: const InputDecoration(labelText: 'القطعة واللون'),
                items: inventory
                    .map((item) => DropdownMenuItem(value: item.id, child: Text('${item.name} • ${item.color}')))
                    .toList(),
                onChanged: (value) => setDialogState(() => inventoryId = value!),
              ),
              const SizedBox(height: 10),
              TextField(controller: customer, decoration: const InputDecoration(labelText: 'اسم المشتري')),
              const SizedBox(height: 10),
              TextField(controller: customerCr, decoration: const InputDecoration(labelText: 'السجل التجاري للمشتري (اختياري)')),
              const SizedBox(height: 10),
              TextField(controller: customerTax, decoration: const InputDecoration(labelText: 'الرقم الضريبي للمشتري (اختياري)')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: length, onChanged: (_) => setDialogState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الطول م'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: price, onChanged: (_) => setDialogState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر/م² قبل VAT'))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: discount, onChanged: (_) => setDialogState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الخصم')),
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
                onPressed: () async {
                  final addon = await _pickAddon(addonTypes, _quoteNumber(length) * 4);
                  if (addon != null) setDialogState(() => addons.add(addon));
                },
                icon: const Icon(Icons.add), label: const Text('إضافة لباد / تركيب / توصيل'),
              )),
              ...addons.asMap().entries.map((entry) => ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                title: Text('${entry.value.name} × ${entry.value.quantity.toStringAsFixed(2)}'),
                subtitle: Text('${entry.value.saleTotal.toStringAsFixed(2)} ⃁ قبل VAT'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setDialogState(() => addons.removeAt(entry.key))),
              )),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('قيمة العرض قبل VAT: ${totals.taxExclusiveAmount.toStringAsFixed(2)} ⃁'),
                  Text('VAT 15%: ${totals.vatAmount.toStringAsFixed(2)} ⃁'),
                  Text('الإجمالي المطلوب: ${totals.payableAmount.toStringAsFixed(2)} ⃁', style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('صالح حتى'),
                subtitle: Text(_date(validUntil)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: validUntil,
                  );
                  if (selected != null) setDialogState(() => validUntil = selected);
                },
              ),
              TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات')),
              const SizedBox(height: 8),
              const Text('العرض ثابت 4 م • السعر المدخل قبل VAT'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
          ],
          );
        },
      ),
    );
    final customerName = customer.text.trim();
    final customerCrValue = customerCr.text.trim();
    final customerTaxValue = customerTax.text.trim();
    final lengthValue = _quoteNumber(length);
    final priceValue = _quoteNumber(price);
    final discountValue = _quoteNumber(discount);
    final notesValue = notes.text.trim();
    for (final controller in [customer, customerCr, customerTax, length, price, discount, notes]) {
      controller.dispose();
    }
    if (save != true) return;
    final gross = lengthValue * 4 * priceValue + addons.fold(0, (sum, addon) => sum + addon.saleTotal);
    if (customerName.isEmpty || lengthValue <= 0 || priceValue < 0 || discountValue < 0 || discountValue > gross) {
      return _message('راجع اسم المشتري والطول والسعر');
    }
    try {
      await widget.repository.createQuotation(
        institutionId: widget.membership.institutionId,
        sellerId: sellerId,
        inventoryId: inventoryId,
        customerName: customerName,
        customerCommercialRegistration: customerCrValue,
        customerTaxNumber: customerTaxValue,
        length: lengthValue,
        pricePerSquareMeter: priceValue,
        validUntil: validUntil,
        notes: notesValue,
        addons: addons,
        discount: discountValue,
      );
      _message('تم حفظ عرض السعر بدون خصم المخزون');
      _reload();
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _convert(QuotationRecord quotation) async {
    var method = 'cash';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تحويل عرض السعر إلى بيع'),
          content: DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'طريقة دفع العميل'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('كاش')),
              DropdownMenuItem(value: 'network', child: Text('شبكة')),
              DropdownMenuItem(value: 'visa', child: Text('Visa')),
              DropdownMenuItem(value: 'tabby', child: Text('Tabby')),
              DropdownMenuItem(value: 'tamara', child: Text('Tamara')),
            ],
            onChanged: (value) => setDialogState(() => method = value!),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تحويل وخصم المخزون')),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    try {
      await widget.repository.convertQuotationToSale(quotation.id, method);
      _message('تم التحويل إلى بيع وخصم الطول من المخزون');
      _reload();
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _openDocument(QuotationRecord quotation) async {
    final institution = await widget.repository
        .loadInstitutionDocumentDetails(widget.membership.institutionId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => QuotationDocumentDialog(
        institution: institution,
        quotation: quotation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<QuotationRecord>>(
        future: _quotations,
        builder: (context, quoteSnapshot) => FutureBuilder<List<InventoryRecord>>(
          future: _inventory,
          builder: (context, inventorySnapshot) => FutureBuilder<List<PersonOption>>(
            future: _sellers,
            builder: (context, sellerSnapshot) => FutureBuilder<List<AddonTypeRecord>>(
              future: _addonTypes,
              builder: (context, addonSnapshot) {
              if (!quoteSnapshot.hasData || !inventorySnapshot.hasData || !sellerSnapshot.hasData || !addonSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final quotations = quoteSnapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FilledButton.icon(
                    onPressed: () => _create(inventorySnapshot.data!, sellerSnapshot.data!, addonSnapshot.data!),
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('عرض سعر جديد'),
                  ),
                  const SizedBox(height: 16),
                  if (quotations.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('لا توجد عروض أسعار بعد.'))),
                  ...quotations.map((quotation) => Card(
                        child: ListTile(
                          onTap: () => _openDocument(quotation),
                          leading: Icon(quotation.status == 'converted' ? Icons.check_circle : Icons.description_outlined),
                          title: Text(quotation.customerName),
                          subtitle: Text('${_date(quotation.issueDate)} • ${quotation.total.toStringAsFixed(2)} ⃁ شامل VAT\nاضغط للعرض والمشاركة'),
                          trailing: quotation.status == 'draft' && widget.membership.role != InstitutionRole.accountant
                              ? IconButton(
                                  tooltip: 'تحويل إلى بيع',
                                  onPressed: () => _convert(quotation),
                                  icon: const Icon(Icons.shopping_cart_checkout),
                                )
                              : Text(quotation.status == 'converted' ? 'تم البيع' : 'مسودة'),
                        ),
                      )),
                ],
              );
              },
            ),
          ),
        ),
      );
}

class QuotationDocumentDialog extends StatefulWidget {
  const QuotationDocumentDialog({super.key, required this.institution, required this.quotation});

  final InstitutionDocumentDetails institution;
  final QuotationRecord quotation;

  @override
  State<QuotationDocumentDialog> createState() => _QuotationDocumentDialogState();
}

class _QuotationDocumentDialogState extends State<QuotationDocumentDialog> {
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
        filename: 'farsha-quotation-${widget.quotation.id.substring(0, 8)}.pdf',
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
            title: const Text('عرض السعر'),
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
                child: QuotationDocument(
                  institution: widget.institution,
                  quotation: widget.quotation,
                ),
              ),
            ),
          ),
        ),
      );
}

class QuotationDocument extends StatelessWidget {
  const QuotationDocument({super.key, required this.institution, required this.quotation});

  final InstitutionDocumentDetails institution;
  final QuotationRecord quotation;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: Container(
          width: 595,
          height: 842,
          padding: const EdgeInsets.all(38),
          color: Colors.white,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.black87, fontSize: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Image.asset('assets/images/farsha_logo.jpeg', width: 82, height: 82),
                  const SizedBox(width: 18),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(institution.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    Text(institution.address),
                    Text('${institution.phone} • ${institution.email}'),
                    Text('السجل: ${institution.commercialRegistration} • الرقم الضريبي: ${institution.taxNumber}'),
                  ])),
                ]),
                const Divider(height: 32, thickness: 2),
                const Text('عرض سعر', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('رقم: ${quotation.id.substring(0, 8).toUpperCase()}'),
                  Text('التاريخ: ${_date(quotation.issueDate)}'),
                  Text('صالح حتى: ${_date(quotation.validUntil)}'),
                ]),
                const SizedBox(height: 18),
                Text('المشتري: ${quotation.customerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (quotation.customerCommercialRegistration.isNotEmpty)
                  Text('السجل التجاري: ${quotation.customerCommercialRegistration}'),
                if (quotation.customerTaxNumber.isNotEmpty)
                  Text('الرقم الضريبي: ${quotation.customerTaxNumber}'),
                const SizedBox(height: 18),
                Container(
                  color: const Color(0xff8b1e2d),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: const Row(children: [
                    Expanded(flex: 3, child: Text('الصنف واللون', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    Expanded(child: Text('الطول', style: TextStyle(color: Colors.white))),
                    Expanded(child: Text('العرض', style: TextStyle(color: Colors.white))),
                    Expanded(child: Text('المساحة', style: TextStyle(color: Colors.white))),
                    Expanded(child: Text('سعر م²', style: TextStyle(color: Colors.white))),
                    Expanded(child: Text('الإجمالي', style: TextStyle(color: Colors.white))),
                  ]),
                ),
                ...quotation.items.map((item) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12))),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text('${item.name} • ${item.color}')),
                        Expanded(child: Text(item.length.toStringAsFixed(2))),
                        Expanded(child: Text(item.width.toStringAsFixed(0))),
                        Expanded(child: Text(item.area.toStringAsFixed(2))),
                        Expanded(child: Text(item.pricePerSquareMeter.toStringAsFixed(2))),
                        Expanded(child: Text(item.lineTotal.toStringAsFixed(2))),
                      ]),
                    )),
                ...quotation.addons.map((addon) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12))),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text(addon.name)),
                        Expanded(child: Text('—')),
                        Expanded(child: Text(addon.unit)),
                        Expanded(child: Text(addon.quantity.toStringAsFixed(2))),
                        Expanded(child: Text(addon.saleUnitPrice.toStringAsFixed(2))),
                        Expanded(child: Text(addon.saleTotal.toStringAsFixed(2))),
                      ]),
                    )),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(width: 270, child: Column(children: [
                    if (quotation.discountAmount > 0) _totalLine('الخصم', quotation.discountAmount),
                    _totalLine(quotation.discountAmount > 0 ? 'صافي قبل الضريبة' : 'الإجمالي قبل الضريبة', quotation.subtotal),
                    _totalLine('VAT 15%', quotation.vatAmount),
                    const Divider(),
                    _totalLine('الإجمالي شامل الضريبة', quotation.total, bold: true),
                  ])),
                ),
                if (quotation.notes.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('ملاحظات', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(quotation.notes),
                ],
                const Spacer(),
                const Text('هذا عرض سعر ولا يخصم من المخزون إلا عند تحويله إلى بيع.', textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('تم إنشاؤه بواسطة تطبيق فرشة', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              ]),
            ),
          ),
        ),
      );

  Widget _totalLine(String label, double amount, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          Text('${amount.toStringAsFixed(2)} ⃁', style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
        ]),
      );
}
