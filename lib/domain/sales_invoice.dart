class InvoiceLineDraft {
  const InvoiceLineDraft({required this.productId, required this.quantity});

  final String productId;
  final int quantity;
}

class InvoiceDraft {
  const InvoiceDraft({
    required this.customerName,
    required this.date,
    required this.lines,
    this.taxCents = 0,
  });

  final String customerName;
  final DateTime date;
  final List<InvoiceLineDraft> lines;
  final int taxCents;
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
  });

  final String id;
  final String number;
  final String customerName;
  final DateTime issueDate;
  final String status;
  final int subtotalCents;
  final int taxCents;
  final int totalCents;

  factory SalesInvoice.fromRow(Map<String, Object?> row) => SalesInvoice(
        id: row['id']! as String,
        number: row['invoice_number']! as String,
        customerName: row['customer_name']! as String,
        issueDate: DateTime.parse(row['issue_date']! as String),
        status: row['status']! as String,
        subtotalCents: row['subtotal_cents']! as int,
        taxCents: row['tax_cents']! as int,
        totalCents: row['total_cents']! as int,
      );
}
