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

  test('stores a balanced entry and rolls back entries for unknown accounts', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();

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

  test('persists the theme and locale settings', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();

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
    ));
    await sourceRepository.exportBackup(backupPath);

    final currentPath = '${directory.path}${Platform.pathSeparator}current.sqlite';
    final currentDatabase = await LedgerDatabase.open(currentPath);
    final currentRepository = LedgerRepository(currentDatabase);
    addTearDown(currentRepository.close);
    await currentRepository.initialize();
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
}
