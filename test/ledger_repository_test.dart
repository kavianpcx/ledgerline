import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/domain/account.dart';
import 'package:ledgerline/data/ledger_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

  test('rejects unsupported currency settings', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();

    await expectLater(
      repository.saveAppSettings(
        AppSettings.defaults.copyWith(currencyCode: 'XYZ'),
      ),
      throwsArgumentError,
    );
    expect((await repository.loadAppSettings()).currencyCode, 'USD');
    expect((await repository.loadAppSettings()).accountingCurrencyConfigured, isFalse);
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


  test('posts split cash and bank tenders to their matching accounts', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await repository.createProduct(const ProductDraft(
      sku: 'MUG-SPLIT',
      name: 'Split tender mug',
      unitPriceCents: 10000,
      unitCostCents: 4000,
      stockQuantity: 3,
    ));
    final product = (await repository.loadProducts()).single;

    await repository.createInvoice(InvoiceDraft(
      customerName: 'Split payment customer',
      date: DateTime(2026, 11, 19),
      lines: [InvoiceLineDraft(productId: product.id, quantity: 1)],
      paymentAmountCents: 4000,
      additionalPayments: [
        const InvoiceTenderDraft(
          amountCents: 6000,
          paymentMethod: 'bank_transfer',
        ),
      ],
    ));

    final snapshot = await repository.loadSnapshot();
    final invoice = snapshot.invoices.single;
    expect(invoice.status, 'paid');
    expect(invoice.paidCents, 10000);
    expect(snapshot.products.single.stockQuantity, 2);
    expect(
      snapshot.assetsCents,
      snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents,
    );

    final payments = await database.handle.query(
      'invoice_payments',
      where: 'invoice_id = ?',
      whereArgs: [invoice.id],
    );
    expect(payments, hasLength(2));
    final paidByMethod = <String, int>{
      for (final payment in payments)
        (payment['payment_method']! as String):
            (payment['amount_cents']! as int),
    };
    expect(paidByMethod, {'cash': 4000, 'bank_transfer': 6000});

    await expectLater(
      repository.createInvoice(InvoiceDraft(
        customerName: 'Overpaid split customer',
        date: DateTime(2026, 11, 20),
        lines: [InvoiceLineDraft(productId: product.id, quantity: 1)],
        paymentAmountCents: 4000,
        additionalPayments: [
          const InvoiceTenderDraft(
            amountCents: 7000,
            paymentMethod: 'bank_transfer',
          ),
        ],
      )),
      throwsArgumentError,
    );
    expect((await repository.loadSnapshot()).invoices, hasLength(1));
    expect((await repository.loadProducts()).single.stockQuantity, 2);

    final paymentLines = await database.handle.query(
      'journal_lines',
      where: 'entry_id IN (?, ?)',
      whereArgs: payments.map((payment) => payment['id']).toList(),
    );
    final cashLine = paymentLines.singleWhere(
      (line) => line['account_id'] == 'cash',
    );
    final bankLine = paymentLines.singleWhere(
      (line) => line['account_id'] == 'bank',
    );
    final receivablesLines = paymentLines
        .where((line) => line['account_id'] == 'receivables')
        .toList();
    expect(cashLine['debit_cents'], 4000);
    expect(cashLine['credit_cents'], 0);
    expect(bankLine['debit_cents'], 6000);
    expect(bankLine['credit_cents'], 0);
    expect(
      receivablesLines.fold<int>(
        0,
        (sum, line) => sum + (line['credit_cents']! as int),
      ),
      10000,
    );
  });

  test('rolls back the invoice and first tender when a later tender fails',
      () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await repository.createProduct(const ProductDraft(
      sku: 'MUG-SPLIT-ROLLBACK',
      name: 'Split rollback mug',
      unitPriceCents: 10000,
      unitCostCents: 4000,
      stockQuantity: 3,
    ));
    final product = (await repository.loadProducts()).single;
    final journalCountBefore =
        (await database.handle.query('journal_entries')).length;
    final movementCountBefore =
        (await database.handle.query('stock_movements')).length;
    await database.handle.execute('''
      CREATE TRIGGER reject_split_bank_tender
      BEFORE INSERT ON invoice_payments
      WHEN NEW.payment_method = 'bank_transfer'
      BEGIN
        SELECT RAISE(ABORT, 'forced later tender failure');
      END;
    ''');

    await expectLater(
      repository.createInvoice(InvoiceDraft(
        customerName: 'Rollback customer',
        date: DateTime(2026, 11, 19),
        lines: [InvoiceLineDraft(productId: product.id, quantity: 1)],
        paymentAmountCents: 4000,
        additionalPayments: [
          const InvoiceTenderDraft(
            amountCents: 6000,
            paymentMethod: 'bank_transfer',
          ),
        ],
      )),
      throwsA(isA<Object>()),
    );

    expect(await database.handle.query('sales_invoices'), isEmpty);
    expect(await database.handle.query('invoice_lines'), isEmpty);
    expect(await database.handle.query('invoice_payments'), isEmpty);
    expect((await repository.loadProducts()).single.stockQuantity, 3);
    expect(
      (await database.handle.query('journal_entries')).length,
      journalCountBefore,
    );
    expect(
      (await database.handle.query('stock_movements')).length,
      movementCountBefore,
    );
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

  test('migrates version 5 invoice payments to the cash method', () async {
    final directory = await Directory.systemTemp.createTemp('ledgerline-payment-migration-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}version-five.sqlite';
    final versionFive = await LedgerDatabase.open(path);
    await versionFive.handle.insert('sales_invoices', {
      'id': 'legacy-invoice-v5',
      'invoice_number': 'INV-2026-000002',
      'customer_name': 'Legacy customer',
      'issue_date': '2026-01-03',
      'status': 'paid',
      'subtotal_cents': 4200,
      'tax_cents': 0,
      'total_cents': 4200,
      'created_at': '2026-01-03T12:00:00Z',
    });
    await versionFive.handle.execute('DROP TABLE invoice_payments');
    await versionFive.handle.execute('''
      CREATE TABLE invoice_payments (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL REFERENCES sales_invoices(id) ON DELETE CASCADE,
        payment_date TEXT NOT NULL,
        amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
        created_at TEXT NOT NULL
      )
    ''');
    await versionFive.handle.execute(
      'CREATE INDEX invoice_payments_by_invoice ON invoice_payments(invoice_id, payment_date DESC)',
    );
    await versionFive.handle.insert('invoice_payments', {
      'id': 'legacy-payment-v5',
      'invoice_id': 'legacy-invoice-v5',
      'payment_date': '2026-01-03',
      'amount_cents': 4200,
      'created_at': '2026-01-03T12:00:00Z',
    });
    await versionFive.handle.execute('PRAGMA user_version = 5');
    await versionFive.close();

    final migrated = await LedgerDatabase.open(path);
    addTearDown(migrated.close);
    final payments = await migrated.handle.query('invoice_payments');
    expect(payments, hasLength(1));
    expect(payments.single['payment_method'], 'cash');
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


  test('product search and sorting use bounded database pages', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );

    for (var i = 0; i < 31; i++) {
      final index = i.toString().padLeft(3, '0');
      await repository.createProduct(ProductDraft(
        sku: 'SKU-' + index,
        name: 'Item ' + i.toString(),
        unitPriceCents: 100 + i,
        unitCostCents: 50,
        stockQuantity: 0,
        category: i.isEven ? 'Food' : 'Tools',
        barcode: '900000' + index,
      ));
    }
    await repository.createProduct(const ProductDraft(
      sku: 'COTTON-1',
      name: '100% Cotton',
      unitPriceCents: 50,
      unitCostCents: 20,
      stockQuantity: 0,
      category: 'Clothing',
      barcode: '99999901',
    ));

    final first = await repository.loadProductPage(
      pageIndex: 0,
      pageSize: 10,
      sortBy: 'price',
      ascending: false,
    );
    expect(first.totalCount, 32);
    expect(first.products, hasLength(10));
    expect(first.products.first.sku, 'SKU-030');
    expect(first.pageCount, 4);
    expect(first.firstItemNumber, 1);
    expect(first.lastItemNumber, 10);

    final last = await repository.loadProductPage(pageIndex: 3, pageSize: 10);
    expect(last.products, hasLength(2));
    expect(last.lastItemNumber, 32);

    final skuSearch = await repository.loadProductPage(
      query: 'SKU-02',
      pageSize: 10,
    );
    expect(skuSearch.totalCount, 10);
    expect(skuSearch.products, hasLength(10));

    final literalPercent = await repository.loadProductPage(
      query: '100%',
      pageSize: 10,
    );
    expect(literalPercent.totalCount, 1);
    expect(literalPercent.products.single.sku, 'COTTON-1');

    await expectLater(
      repository.loadProductPage(pageSize: 20),
      throwsArgumentError,
    );
  });

  test('editing products preserves invoice snapshots and posts cost revaluation', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await repository.createProduct(const ProductDraft(
      sku: 'BOOK-OLD',
      name: 'Ledger Book',
      unitPriceCents: 1000,
      unitCostCents: 400,
      stockQuantity: 5,
      category: 'Books',
      barcode: '10001000',
      description: 'Original description',
    ));
    final product = (await repository.loadProducts()).single;
    await repository.createInvoice(InvoiceDraft(
      customerName: 'History customer',
      date: DateTime(2026, 8, 2),
      lines: [InvoiceLineDraft(productId: product.id, quantity: 2)],
    ));
    final invoiceBefore = (await database.handle.query('sales_invoices')).single;
    final lineBefore = (await database.handle.query('invoice_lines')).single;

    await repository.updateProduct(product.id, const ProductDraft(
      sku: 'BOOK-NEW',
      name: 'Updated Ledger Book',
      unitPriceCents: 1200,
      unitCostCents: 500,
      stockQuantity: 999,
      category: 'Stationery',
      barcode: '10001001',
      description: 'Updated description',
    ));

    final updated = (await repository.loadProducts()).single;
    expect(updated.sku, 'BOOK-NEW');
    expect(updated.name, 'Updated Ledger Book');
    expect(updated.description, 'Updated description');
    expect(updated.category, 'Stationery');
    expect(updated.barcode, '10001001');
    expect(updated.stockQuantity, 3);

    final invoiceAfter = (await database.handle.query('sales_invoices')).single;
    final lineAfter = (await database.handle.query('invoice_lines')).single;
    expect(invoiceAfter['total_cents'], invoiceBefore['total_cents']);
    expect(lineAfter['description'], lineBefore['description']);
    expect(lineAfter['unit_price_cents'], 1000);
    expect(lineAfter['unit_cost_cents'], 400);
    expect(lineAfter['line_total_cents'], lineBefore['line_total_cents']);

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.assetsCents,
        snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents);
  });

  test('v3 product rows migrate without changing values', () async {
    final directory = await Directory.systemTemp.createTemp('ledgerline-v3-products-');
    addTearDown(() => directory.delete(recursive: true));
    final path = directory.path + Platform.pathSeparator + 'legacy.sqlite';
    sqfliteFfiInit();
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              sku TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              unit_price_cents INTEGER NOT NULL,
              unit_cost_cents INTEGER NOT NULL DEFAULT 0,
              stock_quantity INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    const createdAt = '2026-01-03T00:00:00.000Z';
    await legacy.insert('products', {
      'id': 'legacy-1',
      'sku': 'OLD-1',
      'name': 'Legacy product',
      'unit_price_cents': 1234,
      'unit_cost_cents': 456,
      'stock_quantity': 7,
      'created_at': createdAt,
    });
    await legacy.close();

    final upgraded = await LedgerDatabase.open(path);
    addTearDown(upgraded.close);
    final migrated = (await upgraded.handle.query('products')).single;
    expect(migrated['unit_price_cents'], 1234);
    expect(migrated['unit_cost_cents'], 456);
    expect(migrated['stock_quantity'], 7);
    expect(migrated['description'], '');
    expect(migrated['category'], '');
    expect(migrated['barcode'], '');
    expect(migrated['updated_at'], createdAt);
    final movements = await upgraded.handle.query('stock_movements');
    expect(movements, hasLength(1));
    expect(movements.single['product_id'], 'legacy-1');
    expect(movements.single['product_sku'], 'OLD-1');
    expect(movements.single['product_name'], 'Legacy product');
    expect(movements.single['movement_type'], 'migration_balance');
    expect(movements.single['quantity_delta'], 7);
    expect(movements.single['unit_cost_cents'], 456);
  });


  test('stock changes are append-only and paginated by product', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await repository.createProduct(const ProductDraft(
      sku: 'STOCK-1',
      name: 'Stock history item',
      unitPriceCents: 1000,
      unitCostCents: 400,
      stockQuantity: 1,
    ));
    final product = (await repository.loadProducts()).single;

    for (var index = 0; index < 9; index++) {
      await repository.adjustStock(product.id, 1);
    }
    await repository.createInvoice(InvoiceDraft(
      customerName: 'Stock history customer',
      date: DateTime.now(),
      lines: [InvoiceLineDraft(productId: product.id, quantity: 2)],
    ));

    final firstPage = await repository.loadStockMovementPage(
      productId: product.id,
      pageSize: 10,
    );
    final secondPage = await repository.loadStockMovementPage(
      productId: product.id,
      pageIndex: 1,
      pageSize: 10,
    );
    expect(firstPage.totalCount, 11);
    expect(firstPage.pageCount, 2);
    expect(firstPage.movements, hasLength(10));
    expect(firstPage.movements.first.quantityDelta, -2);
    expect(firstPage.movements.first.movementType, 'sale');
    expect(
      firstPage.movements.skip(1).every((movement) => movement.quantityDelta == 1),
      isTrue,
    );
    expect(secondPage.movements, hasLength(1));
    expect(secondPage.movements.single.quantityDelta, 1);
    expect(secondPage.movements.single.movementType, 'opening_balance');

    final allMovements = [
      ...firstPage.movements,
      ...secondPage.movements,
    ];
    expect(
      allMovements.fold<int>(0, (total, movement) => total + movement.quantityDelta),
      8,
    );
    expect((await repository.loadProducts()).single.stockQuantity, 8);

    await expectLater(
      database.handle.update(
        'stock_movements',
        {'description': 'rewritten'},
        where: 'id = ?',
        whereArgs: [firstPage.movements.first.id],
      ),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      database.handle.delete(
        'stock_movements',
        where: 'id = ?',
        whereArgs: [firstPage.movements.first.id],
      ),
      throwsA(isA<Exception>()),
    );
    expect(
      (await database.handle.query('stock_movements')).length,
      11,
    );
  });

  test('10,000 product catalog stays page-bounded during search', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    final timestamp = DateTime.utc(2026, 1, 1).toIso8601String();

    await database.handle.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < 10000; i++) {
        batch.insert('products', {
          'id': 'bulk-' + i.toString(),
          'sku': 'SKU-' + i.toString().padLeft(5, '0'),
          'name': 'Inventory item ' + i.toString(),
          'unit_price_cents': 100,
          'unit_cost_cents': 10,
          'stock_quantity': 0,
          'created_at': timestamp,
          'updated_at': timestamp,
        });
      }
      await batch.commit(noResult: true);
    });

    final page = await repository.loadProductPage(
      query: 'SKU-099',
      pageIndex: 2,
      pageSize: 25,
      sortBy: 'sku',
    );
    expect(page.totalCount, 100);
    expect(page.products, hasLength(25));
    expect(page.products.first.sku, 'SKU-09950');
    expect(page.products.last.sku, 'SKU-09974');
    expect(page.pageCount, 4);
  });


}
