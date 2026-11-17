import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/domain/account.dart';
import 'package:ledgerline/domain/accounting_engine.dart';

void main() {
  group('AccountingEngine', () {
    test('rejects an unbalanced account selection', () {
      final draft = JournalDraft(
        date: DateTime(2026, 1, 1),
        description: 'Test',
        amountCents: 100,
        debitAccountId: 'cash',
        creditAccountId: 'cash',
      );

      expect(() => AccountingEngine.validateDraft(draft), throwsArgumentError);
    });

    test('calculates normal balances and net income in integer cents', () {
      const accounts = [
        Account(id: 'cash', code: '1000', name: 'Cash', type: AccountType.asset),
        Account(id: 'sales', code: '4000', name: 'Sales', type: AccountType.income),
        Account(id: 'office', code: '6000', name: 'Office expense', type: AccountType.expense),
      ];
      const activity = [
        AccountActivity(accountId: 'cash', debits: 12000, credits: 2500),
        AccountActivity(accountId: 'sales', debits: 0, credits: 10000),
        AccountActivity(accountId: 'office', debits: 2500, credits: 0),
      ];

      final result = AccountingEngine.summarize(
        accounts: accounts,
        entries: const [],
        activity: activity,
      );

      expect(result.assetsCents, 9500);
      expect(result.incomeCents, 10000);
      expect(result.expensesCents, 2500);
      expect(result.netIncomeCents, 7500);
    });
  });
}
