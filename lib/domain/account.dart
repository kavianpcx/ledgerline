enum AccountType { asset, liability, equity, income, expense }

extension AccountTypeLabels on AccountType {
  String get label => switch (this) {
        AccountType.asset => 'Asset',
        AccountType.liability => 'Liability',
        AccountType.equity => 'Equity',
        AccountType.income => 'Income',
        AccountType.expense => 'Expense',
      };

  bool get hasDebitNormalBalance =>
      this == AccountType.asset || this == AccountType.expense;
}

class Account {
  const Account({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
  });

  final String id;
  final String code;
  final String name;
  final AccountType type;

  factory Account.fromRow(Map<String, Object?> row) => Account(
        id: row['id']! as String,
        code: row['code']! as String,
        name: row['name']! as String,
        type: AccountType.values.byName(row['type']! as String),
      );
}

class AccountDraft {
  const AccountDraft({required this.code, required this.name, required this.type});

  final String code;
  final String name;
  final AccountType type;
}
