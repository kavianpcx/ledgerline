class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.date,
    required this.description,
    required this.amountCents,
    required this.debitAccountName,
    required this.creditAccountName,
  });

  final String id;
  final DateTime date;
  final String description;
  final int amountCents;
  final String debitAccountName;
  final String creditAccountName;

  factory LedgerEntry.fromRow(Map<String, Object?> row) => LedgerEntry(
        id: row['id']! as String,
        date: DateTime.parse(row['entry_date']! as String),
        description: row['description']! as String,
        amountCents: row['amount_cents']! as int,
        debitAccountName: row['debit_account']! as String,
        creditAccountName: row['credit_account']! as String,
      );
}
