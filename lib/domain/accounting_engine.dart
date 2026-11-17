import 'account.dart';
import 'ledger_entry.dart';
import 'product.dart';
import 'sales_invoice.dart';

class JournalDraft {
  const JournalDraft({
    required this.date,
    required this.description,
    required this.amountCents,
    required this.debitAccountId,
    required this.creditAccountId,
  });

  final DateTime date;
  final String description;
  final int amountCents;
  final String debitAccountId;
  final String creditAccountId;
}

class AccountActivity {
  const AccountActivity({
    required this.accountId,
    required this.debits,
    required this.credits,
  });

  final String accountId;
  final int debits;
  final int credits;
}

class LedgerSnapshot {
  const LedgerSnapshot({
    required this.accounts,
    required this.entries,
    required this.products,
    required this.invoices,
    required this.balancesByAccount,
    required this.assetsCents,
    required this.liabilitiesCents,
    required this.equityCents,
    required this.incomeCents,
    required this.expensesCents,
  });

  final List<Account> accounts;
  final List<LedgerEntry> entries;
  final List<Product> products;
  final List<SalesInvoice> invoices;
  final Map<String, int> balancesByAccount;
  final int assetsCents;
  final int liabilitiesCents;
  final int equityCents;
  final int incomeCents;
  final int expensesCents;

  int get netIncomeCents => incomeCents - expensesCents;
}

class AccountingEngine {
  const AccountingEngine._();

  static void validateDraft(JournalDraft draft) {
    if (draft.amountCents <= 0) {
      throw ArgumentError.value(draft.amountCents, 'amountCents', 'Must be positive.');
    }
    if (draft.description.trim().isEmpty) {
      throw ArgumentError.value(draft.description, 'description', 'A description is required.');
    }
    if (draft.debitAccountId == draft.creditAccountId) {
      throw ArgumentError('Debit and credit accounts must be different.');
    }
  }

  static int signedBalance(AccountType type, int debits, int credits) =>
      type.hasDebitNormalBalance ? debits - credits : credits - debits;

  static LedgerSnapshot summarize({
    required List<Account> accounts,
    required List<LedgerEntry> entries,
    required List<AccountActivity> activity,
    List<Product> products = const [],
    List<SalesInvoice> invoices = const [],
  }) {
    final activityByAccount = <String, AccountActivity>{
      for (final item in activity) item.accountId: item,
    };
    final balances = <String, int>{};
    var assets = 0;
    var liabilities = 0;
    var equity = 0;
    var income = 0;
    var expenses = 0;

    for (final account in accounts) {
      final item = activityByAccount[account.id];
      final balance = signedBalance(
        account.type,
        item?.debits ?? 0,
        item?.credits ?? 0,
      );
      balances[account.id] = balance;
      switch (account.type) {
        case AccountType.asset:
          assets += balance;
          break;
        case AccountType.liability:
          liabilities += balance;
          break;
        case AccountType.equity:
          equity += balance;
          break;
        case AccountType.income:
          income += balance;
          break;
        case AccountType.expense:
          expenses += balance;
          break;
      }
    }

    return LedgerSnapshot(
      accounts: List.unmodifiable(accounts),
      entries: List.unmodifiable(entries),
      products: List.unmodifiable(products),
      invoices: List.unmodifiable(invoices),
      balancesByAccount: Map.unmodifiable(balances),
      assetsCents: assets,
      liabilitiesCents: liabilities,
      equityCents: equity,
      incomeCents: income,
      expensesCents: expenses,
    );
  }
}
