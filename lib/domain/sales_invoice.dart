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

class InvoiceTenderDraft {
  const InvoiceTenderDraft({
    required this.amountCents,
    required this.paymentMethod,
  });

  final int amountCents;
  final String paymentMethod;
}

class InvoiceDraft {
  const InvoiceDraft({
    required this.customerName,
    required this.date,
    required this.lines,
    this.taxCents = 0,
    this.discountCents = 0,
    this.paymentAmountCents = 0,
    this.paymentMethod = 'cash',
    this.additionalPayments = const [],
  });

  final String customerName;
  final DateTime date;
  final List<InvoiceLineDraft> lines;
  final int taxCents;
  final int discountCents;
  final int paymentAmountCents;
  final String paymentMethod;
  final List<InvoiceTenderDraft> additionalPayments;
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

class InvoicePaymentRecord {
  const InvoicePaymentRecord({
    required this.id,
    required this.invoiceId,
    required this.paymentDate,
    required this.amountCents,
    required this.paymentMethod,
    required this.journalEntryId,
    required this.ledgerPostingMatches,
  });

  final String id;
  final String invoiceId;
  final DateTime paymentDate;
  final int amountCents;
  final String paymentMethod;
  final String? journalEntryId;
  final bool ledgerPostingMatches;
}

class InvoicePaymentHistory {
  const InvoicePaymentHistory({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.customerName,
    required this.invoiceStatus,
    required this.invoiceTotalCents,
    required this.payments,
  });

  final String invoiceId;
  final String invoiceNumber;
  final String customerName;
  final String invoiceStatus;
  final int invoiceTotalCents;
  final List<InvoicePaymentRecord> payments;

  int get recordedCents =>
      payments.fold<int>(0, (sum, payment) => sum + payment.amountCents);

  int get balanceDueCents =>
      invoiceTotalCents > recordedCents ? invoiceTotalCents - recordedCents : 0;

  bool get invoiceStatusMatchesPayments {
    if (invoiceStatus == 'void') return recordedCents == 0;
    if (recordedCents > invoiceTotalCents) return false;
    final expectedStatus =
        recordedCents == invoiceTotalCents ? 'paid' : 'issued';
    return invoiceStatus == expectedStatus;
  }

  bool get journalPostingsMatch =>
      payments.every((payment) => payment.ledgerPostingMatches);

  bool get isReconciled =>
      invoiceStatusMatchesPayments && journalPostingsMatch;
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
    this.discountCents = 0,
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
  final int discountCents;
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
      discountCents: row['discount_cents'] as int? ?? 0,
      totalCents: totalCents,
      paidCents: paidCents,
    );
  }
}
