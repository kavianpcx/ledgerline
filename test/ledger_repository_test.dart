import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/domain/account.dart';
import 'package:ledgerline/data/ledger_database.dart';
import 'package:ledgerline/data/ledger_repository.dart';
import 'package:ledgerline/domain/accounting_engine.dart';
import 'package:ledgerline/domain/app_settings.dart';
import 'package:ledgerline/domain/product.dart';
import 'package:ledgerline/domain/sales_invoice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('requires a confirmed base currency before monetary writes', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();

    await expectLater(
      repository.createEntry(JournalDraft(
        date: DateTime(2026, 5, 1),
        description: 'Blocked until currency setup',
        amountCents: 100,
        debitAccountId: 'cash',
        creditAccountId: 'owner-equity',
      )),
      throwsStateError,
    );

    await repository.configureAccountingCurrency(
      currencyCode: 'IRR',
      confirmExistingAmounts: false,
    );
    expect((await repository.loadAppSettings()).accountingCurrencyConfigured, isTrue);
    await repository.createEntry(JournalDraft(
      date: DateTime(2026, 5, 1),
      description: 'Rial opening balance',
      amountCents: 100,
      debitAccountId: 'cash',
      creditAccountId: 'owner-equity',
    ));
    expect((await repository.loadSnapshot()).assetsCents, 100);
  });

  test('legacy currency confirmation checks all monetary records', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();

    // The visible business tables are intentionally not loaded into a snapshot.
    await database.handle.insert('products', {
      'id': 'legacy-product',
      'sku': 'LEGACY-COUNT',
      'name': 'Legacy product',
      'unit_price_cents': 300,
      'unit_cost_cents': 150,
      'stock_quantity': 1,
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    });
    expect(await repository.hasMonetaryRecords(), isTrue);
    await expectLater(
      repository.configureAccountingCurrency(
        currencyCode: 'TOMAN',
        confirmExistingAmounts: false,
      ),
      throwsStateError,
    );
    await repository.configureAccountingCurrency(
      currencyCode: 'TOMAN',
      confirmExistingAmounts: true,
    );
    expect((await repository.loadAppSettings()).currencyCode, 'TOMAN');
  });

  test('requires confirmation for legacy records and locks the base currency', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();

    await database.handle.insert('products', {
      'id': 'legacy-product',
      'sku': 'LEGACY-1',
      'name': 'Legacy product',
      'unit_price_cents': 12500,
      'unit_cost_cents': 7000,
      'stock_quantity': 1,
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    });

    await expectLater(
      repository.configureAccountingCurrency(
        currencyCode: 'USD',
        confirmExistingAmounts: false,
      ),
      throwsStateError,
    );
    expect((await repository.loadAppSettings()).accountingCurrencyConfigured, isFalse);

    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    final persisted = await repository.loadAppSettings();
    expect(persisted.accountingCurrencyConfigured, isTrue);
    expect(persisted.currencyCode, 'USD');

    await expectLater(
      repository.configureAccountingCurrency(
        currencyCode: 'EUR',
        confirmExistingAmounts: true,
      ),
      throwsStateError,
    );
    expect((await repository.loadAppSettings()).currencyCode, 'USD');
  });

  test('stores a balanced entry and rolls back entries for unknown accounts', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );

    await repository.createEntry(JournalDraft(
      date: DateTime(2026, 1, 5),
      description: 'Owner deposit',
      amountCents: 125000,
      debitAccountId: 'cash',
      creditAccountId: 'owner-equity',
    ));

    await expectLater(
      repository.createEntry(JournalDraft(
        date: DateTime(2026, 1, 6),
        description: 'Invalid account',
        amountCents: 100,
        debitAccountId: 'cash',
        creditAccountId: 'missing-account',
      )),
      throwsArgumentError,
    );

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.entries, hasLength(1));
    expect(snapshot.assetsCents, 125000);
    expect(snapshot.equityCents, 125000);
    expect(snapshot.assetsCents, snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents);
  });

  test('adds custom accounts to the persisted chart', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );

    await repository.createAccount(const AccountDraft(
      code: '7200',
      name: 'Software subscriptions',
      type: AccountType.expense,
    ));

    final snapshot = await repository.loadSnapshot();
    final account = snapshot.accounts.singleWhere((item) => item.code == '7200');
    expect(account.name, 'Software subscriptions');
    expect(account.type, AccountType.expense);
  });

  test('issues an invoice atomically and reduces inventory', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await repository.createProduct(const ProductDraft(
      sku: 'MUG-01',
      name: 'Ceramic mug',
      unitPriceCents: 10000,
      unitCostCents: 4000,
      stockQuantity: 5,
    ));
    final product = (await repository.loadProducts()).single;

    await repository.createInvoice(InvoiceDraft(
      customerName: 'Sample customer',
      date: DateTime.now(),
      lines: [InvoiceLineDraft(productId: product.id, quantity: 2)],
    ));

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.invoices, hasLength(1));
    expect(snapshot.invoices.single.totalCents, 20000);
    expect(snapshot.products.single.stockQuantity, 3);
    expect(snapshot.assetsCents, 32000);
    expect(snapshot.equityCents, 20000);
    expect(snapshot.netIncomeCents, 12000);
    expect(snapshot.assetsCents, snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents);

    await expectLater(
      repository.createInvoice(InvoiceDraft(
        customerName: 'Out of stock',
        date: DateTime.now(),
        lines: [InvoiceLineDraft(productId: product.id, quantity: 4)],
      )),
      throwsArgumentError,
    );
    expect((await repository.loadProducts()).single.stockQuantity, 3);
    expect((await repository.loadSnapshot()).invoices, hasLength(1));
  });

  test('records partial and final invoice payments against receivables', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await repository.createProduct(const ProductDraft(
      sku: 'MUG-PAY',
      name: 'Payment test mug',
      unitPriceCents: 10000,
      unitCostCents: 4000,
      stockQuantity: 3,
    ));
    final product = (await repository.loadProducts()).single;
    await repository.createInvoice(InvoiceDraft(
      customerName: 'Payment customer',
      date: DateTime(2026, 6, 1),
      taxCents: 2000,
      lines: [InvoiceLineDraft(productId: product.id, quantity: 2)],
    ));
    var invoice = (await repository.loadSnapshot()).invoices.single;
    expect(invoice.totalCents, 22000);
    expect(invoice.paidCents, 0);
    expect(invoice.balanceDueCents, 22000);

    await repository.recordInvoicePayment(InvoicePaymentDraft(
      invoiceId: invoice.id,
      amountCents: 8000,
      date: DateTime(2026, 6, 3),
    ));
    invoice = (await repository.loadSnapshot()).invoices.single;
    expect(invoice.status, 'issued');
    expect(invoice.paidCents, 8000);
    expect(invoice.balanceDueCents, 14000);

    await expectLater(
      repository.recordInvoicePayment(InvoicePaymentDraft(
        invoiceId: invoice.id,
        amountCents: 14001,
        date: DateTime(2026, 6, 4),
      )),
      throwsArgumentError,
    );
    invoice = (await repository.loadSnapshot()).invoices.single;
    expect(invoice.paidCents, 8000);
    expect(invoice.balanceDueCents, 14000);

    await repository.recordInvoicePayment(InvoicePaymentDraft(
      invoiceId: invoice.id,
      amountCents: 14000,
      date: DateTime(2026, 6, 5),
    ));
    final snapshot = await repository.loadSnapshot();
    invoice = snapshot.invoices.single;
    expect(invoice.status, 'paid');
    expect(invoice.paidCents, 22000);
    expect(invoice.balanceDueCents, 0);
    expect(
      snapshot.entries
          .where((entry) => entry.description.startsWith('Invoice payment'))
          .length,
      2,
    );

    final paymentBalances = await database.handle.rawQuery('''
      SELECT l.account_id,
             COALESCE(SUM(l.debit_cents), 0) AS debits,
             COALESCE(SUM(l.credit_cents), 0) AS credits
      FROM journal_lines l
      WHERE l.entry_id IN (
        SELECT id FROM journal_entries WHERE description LIKE ?
      )
      GROUP BY l.account_id
    ''', ['Invoice payment ${invoice.number}%']);
    expect(paymentBalances, hasLength(2));
    final cash = paymentBalances.singleWhere((row) => row['account_id'] == 'cash');
    final receivables =
        paymentBalances.singleWhere((row) => row['account_id'] == 'receivables');
    expect(cash['debits'], 22000);
    expect(cash['credits'], 0);
    expect(receivables['debits'], 0);
    expect(receivables['credits'], 22000);
    expect(
      snapshot.assetsCents,
      snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents,
    );
  });

  test('migrates legacy paid invoices into payment history', () async {
    final directory = await Directory.systemTemp.createTemp('ledgerline-migration-');
    addTearDown(() => directory.delete(recursive: true));
    final initialized = await LedgerDatabase.openInMemory();
    await initialized.close();
    final path = '${directory.path}${Platform.pathSeparator}legacy.sqlite';
    final legacy = await LedgerDatabase.open(path);
    await legacy.handle.insert('sales_invoices', {
      'id': 'legacy-invoice',
      'invoice_number': 'INV-2026-000001',
      'customer_name': 'Legacy customer',
      'issue_date': '2026-01-02',
      'status': 'paid',
      'subtotal_cents': 5000,
      'tax_cents': 0,
      'total_cents': 5000,
      'created_at': '2026-01-02T12:00:00Z',
    });
    await legacy.handle.execute('DROP TABLE invoice_payments');
    await legacy.handle.execute('PRAGMA user_version = 2');
    await legacy.close();

    final migrated = await LedgerDatabase.open(path);
    addTearDown(migrated.close);
    final repository = LedgerRepository(migrated);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    final invoice = (await repository.loadSnapshot()).invoices.single;
    expect(invoice.status, 'paid');
    expect(invoice.paidCents, 5000);
    expect(invoice.balanceDueCents, 0);
    final payments = await migrated.handle.query('invoice_payments');
    expect(payments, hasLength(1));
    expect(payments.single['payment_date'], '2026-01-02');
    expect(payments.single['amount_cents'], 5000);
  });

  test('persists the theme and locale settings', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );

    expect((await repository.loadAppSettings()).languageCode, 'en');
    await repository.saveAppSettings(const AppSettings(
      darkMode: true,
      languageCode: 'fa',
      businessName: 'Northstar Books',
      currencyCode: 'EUR',
    ));
    final settings = await repository.loadAppSettings();

    expect(settings.darkMode, isTrue);
    expect(settings.languageCode, 'fa');
    expect(settings.businessName, 'Northstar Books');
    expect(settings.currencyCode, 'EUR');
  });

  test('exports a consistent SQLite backup', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    final directory = await Directory.systemTemp.createTemp('ledgerline-test-');
    addTearDown(() => directory.delete(recursive: true));
    final backupFile = File('${directory.path}${Platform.pathSeparator}ledgerline.sqlite');

    await repository.createEntry(JournalDraft(
      date: DateTime(2026, 5, 12),
      description: 'Backup check',
      amountCents: 4200,
      debitAccountId: 'cash',
      creditAccountId: 'owner-equity',
    ));
    await repository.exportBackup(backupFile.path);

    expect(await backupFile.exists(), isTrue);
    expect(await backupFile.length(), greaterThan(0));
    final restored = await LedgerDatabase.open(backupFile.path);
    addTearDown(restored.close);
    expect((await restored.handle.query('journal_entries')), hasLength(1));
  });

  test('restores a validated backup and keeps the previous ledger for recovery', () async {
    final directory = await Directory.systemTemp.createTemp('ledgerline-restore-');
    addTearDown(() => directory.delete(recursive: true));
    final backupPath = '${directory.path}${Platform.pathSeparator}backup.sqlite';
    final sourceDatabase = await LedgerDatabase.openInMemory();
    addTearDown(sourceDatabase.close);
    final sourceRepository = LedgerRepository(sourceDatabase);
    await sourceRepository.initialize();
    await sourceRepository.configureAccountingCurrency(
      currencyCode: 'EUR',
      confirmExistingAmounts: true,
    );
    await sourceRepository.createEntry(JournalDraft(
      date: DateTime(2026, 4, 3),
      description: 'Entry from backup',
      amountCents: 7500,
      debitAccountId: 'cash',
      creditAccountId: 'owner-equity',
    ));
    await sourceRepository.saveAppSettings(const AppSettings(
      darkMode: true,
      languageCode: 'fa',
      businessName: 'Backup Books',
      currencyCode: 'EUR',
      desktopSidebarCollapsed: true,
    ));
    await sourceRepository.exportBackup(backupPath);

    final currentPath = '${directory.path}${Platform.pathSeparator}current.sqlite';
    final currentDatabase = await LedgerDatabase.open(currentPath);
    final currentRepository = LedgerRepository(currentDatabase);
    addTearDown(currentRepository.close);
    await currentRepository.initialize();
    await currentRepository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await currentRepository.createEntry(JournalDraft(
      date: DateTime(2026, 4, 4),
      description: 'Entry before restore',
      amountCents: 2300,
      debitAccountId: 'cash',
      creditAccountId: 'owner-equity',
    ));

    final recoveryPath = await currentRepository.restoreBackup(backupPath);
    expect(recoveryPath, isNotNull);
    expect(await File(recoveryPath!).exists(), isTrue);
    final snapshot = await currentRepository.loadSnapshot();
    expect(snapshot.entries, hasLength(1));
    expect(snapshot.entries.single.description, 'Entry from backup');
    final settings = await currentRepository.loadAppSettings();
    expect(settings.businessName, 'Backup Books');
    expect(settings.currencyCode, 'EUR');
    expect(settings.darkMode, isTrue);
    expect(settings.languageCode, 'fa');
    expect(settings.desktopSidebarCollapsed, isTrue);

    final previousDatabase = await LedgerDatabase.open(recoveryPath);
    addTearDown(previousDatabase.close);
    final previousEntries = await previousDatabase.handle.query('journal_entries');
    expect(previousEntries, hasLength(1));
    expect(previousEntries.single['description'], 'Entry before restore');
  });

  test('rejects a damaged backup without changing the current ledger', () async {
    final directory = await Directory.systemTemp.createTemp('ledgerline-bad-restore-');
    addTearDown(() => directory.delete(recursive: true));
    final currentPath = '${directory.path}${Platform.pathSeparator}current.sqlite';
    final database = await LedgerDatabase.open(currentPath);
    final repository = LedgerRepository(database);
    addTearDown(repository.close);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await repository.createEntry(JournalDraft(
      date: DateTime(2026, 4, 5),
      description: 'Keep this entry',
      amountCents: 3100,
      debitAccountId: 'cash',
      creditAccountId: 'owner-equity',
    ));
    final damagedFile = File('${directory.path}${Platform.pathSeparator}damaged.sqlite');
    await damagedFile.writeAsString('This is not an SQLite database. ' * 8);

    await expectLater(repository.restoreBackup(damagedFile.path), throwsFormatException);
    final snapshot = await repository.loadSnapshot();
    expect(snapshot.entries, hasLength(1));
    expect(snapshot.entries.single.description, 'Keep this entry');
  });
  test('persists the desktop sidebar preference in application settings', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );

    expect((await repository.loadAppSettings()).desktopSidebarCollapsed, isFalse);
    await repository.saveAppSettings(
      AppSettings.defaults.copyWith(desktopSidebarCollapsed: true),
    );

    final settings = await repository.loadAppSettings();
    expect(settings.desktopSidebarCollapsed, isTrue);
  });

}
