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

class InvoiceReturnDraft {
  const InvoiceReturnDraft({
    required this.invoiceId,
    required this.date,
    required this.reason,
    this.refundMethod = 'cash',
  });

  final String invoiceId;
  final DateTime date;
  final String reason;
  final String refundMethod;
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


class InvoicePrintLine {
  const InvoicePrintLine({
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
    required this.lineTotalCents,
  });

  final String description;
  final int quantity;
  final int unitPriceCents;
  final int lineTotalCents;
}

class InvoicePrintData {
  const InvoicePrintData({
    required this.invoiceNumber,
    required this.customerName,
    required this.issueDate,
    required this.status,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidCents,
    required this.isReturned,
    required this.lines,
  });

  final String invoiceNumber;
  final String customerName;
  final DateTime issueDate;
  final String status;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int paidCents;
  final bool isReturned;
  final List<InvoicePrintLine> lines;

  int get balanceDueCents =>
      totalCents <= paidCents ? 0 : totalCents - paidCents;
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

class InvoiceReturnRecord {
  const InvoiceReturnRecord({
    required this.returnDate,
    required this.reason,
    required this.refundAmountCents,
    required this.refundMethod,
    required this.journalEntryId,
    required this.ledgerPostingMatches,
  });

  final DateTime returnDate;
  final String reason;
  final int refundAmountCents;
  final String refundMethod;
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
    required this.returnRecordExpected,
    this.returnRecord,
  });

  final String invoiceId;
  final String invoiceNumber;
  final String customerName;
  final String invoiceStatus;
  final int invoiceTotalCents;
  final List<InvoicePaymentRecord> payments;
  final bool returnRecordExpected;
  final InvoiceReturnRecord? returnRecord;

  int get recordedCents =>
      payments.fold<int>(0, (sum, payment) => sum + payment.amountCents);

  int get balanceDueCents =>
      returnRecordExpected || invoiceTotalCents <= recordedCents
          ? 0
          : invoiceTotalCents - recordedCents;

  bool get invoiceStatusMatchesPayments {
    if (invoiceStatus == 'void') return recordedCents == 0;
    if (recordedCents > invoiceTotalCents) return false;
    final expectedStatus =
        recordedCents == invoiceTotalCents ? 'paid' : 'issued';
    return invoiceStatus == expectedStatus;
  }

  bool get journalPostingsMatch =>
      payments.every((payment) => payment.ledgerPostingMatches) &&
      (returnRecordExpected
          ? returnRecord?.ledgerPostingMatches == true
          : returnRecord == null);

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
    this.returnedAt,
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
  final DateTime? returnedAt;
  final int totalCents;

  bool get isReturned => returnedAt != null;
  final int paidCents;

  int get balanceDueCents =>
      isReturned || totalCents <= paidCents ? 0 : totalCents - paidCents;

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
      returnedAt: row['returned_at'] == null
          ? null
          : DateTime.tryParse(row['returned_at']! as String),
      totalCents: totalCents,
      paidCents: paidCents,
    );
  }
}
