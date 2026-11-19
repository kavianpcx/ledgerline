class InvoiceLineDraft {
  const InvoiceLineDraft({
    required this.productId,
    required this.quantity,
    this.expectedUnitPriceCents,
  });

  final String productId;
  final int quantity;
  final int? expectedUnitPriceCents;
}

class InvoiceDraft {
  const InvoiceDraft({
    required this.customerName,
    required this.date,
    required this.lines,
    this.taxCents = 0,
    this.paymentAmountCents = 0,
    this.paymentMethod = 'cash',
  });

  final String customerName;
  final DateTime date;
  final List<InvoiceLineDraft> lines;
  final int taxCents;
  final int paymentAmountCents;
  final String paymentMethod;
}

class InvoicePaymentDraft {
  const InvoicePaymentDraft({
    required this.invoiceId,
    required this.amountCents,
    required this.date,
    this.paymentMethod = 'cash',
  });

  final String invoiceId;
  final int amountCents;
  final DateTime date;
  final String paymentMethod;
}

class SalesInvoice {
  const SalesInvoice({
    required this.id,
    required this.number,
    required this.customerName,
    required this.issueDate,
    required this.status,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidCents,
  });

  final String id;
  final String number;
  final String customerName;
  final DateTime issueDate;
  final String status;
  final int subtotalCents;
  final int taxCents;
  final int totalCents;
  final int paidCents;

  int get balanceDueCents =>
      totalCents > paidCents ? totalCents - paidCents : 0;

  factory SalesInvoice.fromRow(Map<String, Object?> row) {
    final status = row['status']! as String;
    final totalCents = row['total_cents']! as int;
    final paidCents = row['paid_cents'] as int? ??
        (status == 'paid' ? totalCents : 0);
    return SalesInvoice(
      id: row['id']! as String,
      number: row['invoice_number']! as String,
      customerName: row['customer_name']! as String,
      issueDate: DateTime.parse(row['issue_date']! as String),
      status: status,
      subtotalCents: row['subtotal_cents']! as int,
      taxCents: row['tax_cents']! as int,
      totalCents: totalCents,
      paidCents: paidCents,
    );
  }
}
