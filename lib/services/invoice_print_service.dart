import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/money.dart';
import '../domain/sales_invoice.dart';

enum InvoicePrintFormat { a4, thermal80 }

class InvoicePrintService {
  Future<Uint8List> buildPdf({
    required InvoicePrintData invoice,
    required String businessName,
    required String currencyCode,
    required InvoicePrintFormat format,
    required bool isPersian,
  }) async {
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );
    final textDirection =
        isPersian ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final isThermal = format == InvoicePrintFormat.thermal80;
    final receiptLineCount = invoice.lines.fold<int>(
      0,
      (count, line) => count + ((line.description.length + 27) ~/ 28),
    );
    final pageFormat = isThermal
        ? PdfPageFormat(
            80 * PdfPageFormat.mm,
            (110 + receiptLineCount * 22) * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;
    final document = pw.Document(
      title: invoice.invoiceNumber,
      author: 'Ledgerline',
      subject: isThermal ? 'Sales receipt' : 'Sales invoice',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: isThermal
            ? const pw.EdgeInsets.fromLTRB(8, 12, 8, 12)
            : const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
          fontFallback: [pw.Font.helvetica()],
        ),
        textDirection: textDirection,
        header: (context) => _header(
          businessName: businessName,
          isThermal: isThermal,
          isPersian: isPersian,
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            _text(isPersian, 'footer'),
            style: const pw.TextStyle(fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: isThermal ? 6 : 18),
          _invoiceDetails(invoice, isPersian, isThermal),
          pw.SizedBox(height: isThermal ? 8 : 18),
          if (isThermal)
            _receiptLines(invoice, currencyCode)
          else
            _invoiceLines(invoice, currencyCode, isPersian),
          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColors.grey500),
          _summary(invoice, currencyCode, isPersian),
          if (invoice.isReturned) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              _text(isPersian, 'returned'),
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
          ],
        ],
      ),
    );

    return document.save();
  }

  Future<void> printInvoice({
    required InvoicePrintData invoice,
    required String businessName,
    required String currencyCode,
    required InvoicePrintFormat format,
    required bool isPersian,
  }) async {
    final bytes = await buildPdf(
      invoice: invoice,
      businessName: businessName,
      currencyCode: currencyCode,
      format: format,
      isPersian: isPersian,
    );
    final suffix =
        format == InvoicePrintFormat.thermal80 ? '-receipt-80mm' : '-invoice';
    await Printing.layoutPdf(
      name: 'Ledgerline-${invoice.invoiceNumber}$suffix.pdf',
      onLayout: (_) async => bytes,
    );
  }

  pw.Widget _header({
    required String businessName,
    required bool isThermal,
    required bool isPersian,
  }) =>
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.only(bottom: isThermal ? 5 : 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.6),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              businessName.trim().isEmpty ? 'Ledgerline' : businessName.trim(),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: isThermal ? 12 : 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              _text(isPersian, 'invoice'),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: isThermal ? 9 : 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  pw.Widget _invoiceDetails(
    InvoicePrintData invoice,
    bool isPersian,
    bool isThermal,
  ) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _detailRow(
            _text(isPersian, 'number'),
            invoice.invoiceNumber,
            isThermal,
          ),
          _detailRow(
            _text(isPersian, 'date'),
            _date(invoice.issueDate),
            isThermal,
          ),
          _detailRow(
            _text(isPersian, 'customer'),
            invoice.customerName,
            isThermal,
          ),
          _detailRow(
            _text(isPersian, 'status'),
            _text(
              isPersian,
              invoice.isReturned ? 'returned' : invoice.status,
            ),
            isThermal,
          ),
        ],
      );

  pw.Widget _invoiceLines(
    InvoicePrintData invoice,
    String currencyCode,

    bool isPersian,
  ) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _invoiceLineRow(
            _text(isPersian, 'item'),
            _text(isPersian, 'quantity'),
            _text(isPersian, 'unitPrice'),
            _text(isPersian, 'lineTotal'),

            isHeader: true,
          ),
          pw.Divider(color: PdfColors.grey500),
          for (final line in invoice.lines)
            _invoiceLineRow(
              line.description,
              line.quantity.toString(),
              _money(line.unitPriceCents, currencyCode),
              _money(line.lineTotalCents, currencyCode),

            ),
        ],
      );

  pw.Widget _invoiceLineRow(
    String description,
    String quantity,
    String unitPrice,
    String lineTotal,
    {
    bool isHeader = false,
  }) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        decoration: isHeader
            ? const pw.BoxDecoration(color: PdfColors.grey200)
            : const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
                ),
              ),
        child: pw.Row(

          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Text(
                description,
                style: isHeader
                    ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                    : null,
              ),
            ),
            pw.Expanded(
              flex: 1,
              child: pw.Text(
                quantity,
                textAlign: pw.TextAlign.center,
                style: isHeader
                    ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                    : null,
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                unitPrice,
                textAlign: pw.TextAlign.end,
                style: isHeader
                    ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                    : null,
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                lineTotal,
                textAlign: pw.TextAlign.end,
                style: isHeader
                    ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                    : null,
              ),
            ),
          ],
        ),
      );

  pw.Widget _receiptLines(
    InvoicePrintData invoice,
    String currencyCode,
  ) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (final line in invoice.lines) ...[
            pw.Text(
              line.description,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Row(

              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${line.quantity} × ${_money(line.unitPriceCents, currencyCode)}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Text(
                  _money(line.lineTotalCents, currencyCode),
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.end,
                ),
              ],
            ),
            pw.Divider(color: PdfColors.grey300, height: 8),
          ],
        ],
      );

  pw.Widget _summary(
    InvoicePrintData invoice,
    String currencyCode,

    bool isPersian,
  ) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _summaryRow(
            _text(isPersian, 'subtotal'),
            _money(invoice.subtotalCents, currencyCode),

          ),
          if (invoice.discountCents > 0)
            _summaryRow(
              _text(isPersian, 'discount'),
              '-${_money(invoice.discountCents, currencyCode)}',

            ),
          _summaryRow(
            _text(isPersian, 'tax'),
            _money(invoice.taxCents, currencyCode),

          ),
          pw.SizedBox(height: 4),
          _summaryRow(
            _text(isPersian, 'total'),
            _money(invoice.totalCents, currencyCode),

            bold: true,
          ),
          if (invoice.returnedCents > 0)
            _summaryRow(
              _text(isPersian, 'returnedAmount'),
              '-${_money(invoice.returnedCents, currencyCode)}',
            ),
          _summaryRow(
            _text(isPersian, 'paid'),
            _money(invoice.paidCents, currencyCode),

          ),
          _summaryRow(
            _text(isPersian, 'balanceDue'),
            _money(invoice.balanceDueCents, currencyCode),

            bold: true,
          ),
        ],
      );

  pw.Widget _summaryRow(
    String label,
    String value,
    {
    bool bold = false,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(

          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              value,
              textAlign: pw.TextAlign.end,
              style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
            ),
          ],
        ),
      );

  pw.Widget _detailRow(String label, String value, bool isThermal) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(fontSize: isThermal ? 8 : 10),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                value,
                style: pw.TextStyle(fontSize: isThermal ? 8 : 10),
                textAlign: pw.TextAlign.end,
              ),
            ),
          ],
        ),
      );

  String _money(int cents, String currencyCode) =>
      CurrencyDefinition.of(currencyCode).formatMinorUnits(cents);

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _text(bool isPersian, String key) {
    const english = <String, String>{
      'invoice': 'Sales invoice',
      'number': 'Invoice number',
      'status': 'Status',
      'issued': 'Issued',
      'void': 'Voided',
      'date': 'Date',
      'customer': 'Customer',
      'item': 'Item',
      'quantity': 'Qty',
      'unitPrice': 'Unit price',
      'lineTotal': 'Line total',
      'subtotal': 'Subtotal',
      'discount': 'Discount',
      'tax': 'Tax',
      'total': 'Total',
      'paid': 'Paid',
      'returnedAmount': 'Returned',
      'balanceDue': 'Balance due',
      'returned': 'RETURNED',
      'footer': 'Thank you for your business.',
    };
    const persian = <String, String>{
      'invoice': 'فاکتور فروش',
      'number': 'شماره فاکتور',
      'status': 'وضعیت',
      'issued': 'صادرشده',
      'void': 'باطل‌شده',
      'date': 'تاریخ',
      'customer': 'مشتری',
      'item': 'کالا',
      'quantity': 'تعداد',
      'unitPrice': 'قیمت واحد',
      'lineTotal': 'جمع ردیف',
      'subtotal': 'جمع جزء',
      'discount': 'تخفیف',
      'tax': 'مالیات',
      'total': 'جمع کل',
      'paid': 'پرداخت‌شده',
      'returnedAmount': 'مرجوعی',
      'balanceDue': 'مانده قابل پرداخت',
      'returned': 'مرجوع‌شده',
      'footer': 'از خرید شما سپاسگزاریم.',
    };
    return (isPersian ? persian : english)[key] ?? key;
  }
}
