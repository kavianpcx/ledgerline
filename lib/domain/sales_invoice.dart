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

class InvoiceReturnLineDraft {
  const InvoiceReturnLineDraft({
    required this.invoiceLineId,
    required this.quantity,
  });

  final int invoiceLineId;
  final int quantity;
}

class InvoiceReturnDraft {
  const InvoiceReturnDraft({
    required this.invoiceId,
    required this.date,
    required this.reason,
    this.refundMethod = 'cash',
    this.lines = const [],
  });

  final String invoiceId;
  final DateTime date;
  final String reason;
  final String refundMethod;
  final List<InvoiceReturnLineDraft> lines;
}

class InvoiceReturnableLine {
  const InvoiceReturnableLine({
    required this.invoiceLineId,
    required this.description,
    required this.originalQuantity,
    required this.returnedQuantity,
    required this.availableQuantity,
    required this.unitPriceCents,
    required this.remainingLineValueCents,
    required this.productAvailable,
  });

  final int invoiceLineId;
  final String description;
  final int originalQuantity;
  final int returnedQuantity;
  final int availableQuantity;
  final int unitPriceCents;
  final int remainingLineValueCents;
  final bool productAvailable;
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

class InvoicePartialReturnRecord {
  const InvoicePartialReturnRecord({
    required this.returnDate,
    required this.reason,
    required this.netRevenueCents,
    required this.taxCents,
    required this.returnValueCents,
    required this.refundAmountCents,
    required this.receivableCreditCents,
    required this.refundMethod,
    required this.journalEntryId,
    required this.ledgerPostingMatches,
  });

  final DateTime returnDate;
  final String reason;
  final int netRevenueCents;
  final int taxCents;
  final int returnValueCents;
  final int refundAmountCents;
  final int receivableCreditCents;
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
    this.partialReturns = const [],
  });

  final String invoiceId;
  final String invoiceNumber;
  final String customerName;
  final String invoiceStatus;
  final int invoiceTotalCents;
  final List<InvoicePaymentRecord> payments;
  final bool returnRecordExpected;
  final InvoiceReturnRecord? returnRecord;
  final List<InvoicePartialReturnRecord> partialReturns;

  int get paymentTotalCents =>
      payments.fold<int>(0, (sum, payment) => sum + payment.amountCents);

  int get totalRefundCents =>
      partialReturns.fold<int>(
        returnRecord?.refundAmountCents ?? 0,
        (sum, item) => sum + item.refundAmountCents,
      );

  int get recordedCents =>
      paymentTotalCents <= totalRefundCents
          ? 0
          : paymentTotalCents - totalRefundCents;

  int get partialReturnedCents =>
      partialReturns.fold<int>(0, (sum, item) => sum + item.returnValueCents);

  int get balanceDueCents {
    if (returnRecordExpected || invoiceTotalCents <= partialReturnedCents) {
      return 0;
    }
    final remainingValue = invoiceTotalCents - partialReturnedCents;
    return remainingValue <= recordedCents ? 0 : remainingValue - recordedCents;
  }

  bool get invoiceStatusMatchesPayments {
    if (invoiceStatus == 'void') return paymentTotalCents == 0;
    if (returnRecordExpected) {
      final hasFinalReturn =
          returnRecord != null ||
          (partialReturns.isNotEmpty &&
              partialReturnedCents == invoiceTotalCents);
      return hasFinalReturn && balanceDueCents == 0;
    }
    if (partialReturnedCents > invoiceTotalCents) return false;
    final remainingValue = invoiceTotalCents - partialReturnedCents;
    if (recordedCents > remainingValue) return false;
    final expectedStatus =
        recordedCents == remainingValue ? 'paid' : 'issued';
    return invoiceStatus == expectedStatus;
  }

  bool get journalPostingsMatch =>
      totalRefundCents <= paymentTotalCents &&
      payments.every((payment) => payment.ledgerPostingMatches) &&
      partialReturns.every((record) => record.ledgerPostingMatches) &&
      (returnRecordExpected
          ? returnRecord?.ledgerPostingMatches == true ||
              (returnRecord == null &&
                  partialReturns.isNotEmpty &&
                  partialReturnedCents == invoiceTotalCents)
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
