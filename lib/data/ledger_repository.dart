import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/account.dart';
import '../domain/accounting_engine.dart';
import '../domain/ledger_entry.dart';
import '../domain/product.dart';
import '../domain/sales_invoice.dart';
import '../domain/app_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'ledger_database.dart';

class LedgerRepository {
  LedgerRepository(this._database);

  final LedgerDatabase _database;

  Future<void> initialize() async {
    final db = _database.handle;
    const starterAccounts = <Account>[
      Account(id: 'cash', code: '1000', name: 'Cash', type: AccountType.asset),
      Account(id: 'receivables', code: '1100', name: 'Accounts receivable', type: AccountType.asset),
      Account(id: 'inventory', code: '1200', name: 'Inventory', type: AccountType.asset),
      Account(id: 'equipment', code: '1500', name: 'Equipment', type: AccountType.asset),
      Account(id: 'payables', code: '2000', name: 'Accounts payable', type: AccountType.liability),
      Account(id: 'tax-payable', code: '2300', name: 'Sales tax payable', type: AccountType.liability),
      Account(id: 'owner-equity', code: '3000', name: 'Owner equity', type: AccountType.equity),
      Account(id: 'sales-income', code: '4000', name: 'Sales income', type: AccountType.income),
      Account(id: 'service-income', code: '4100', name: 'Service income', type: AccountType.income),
      Account(id: 'cost-of-goods', code: '5000', name: 'Cost of goods sold', type: AccountType.expense),
      Account(id: 'office-expense', code: '6000', name: 'Office expense', type: AccountType.expense),
      Account(id: 'travel-expense', code: '6100', name: 'Travel expense', type: AccountType.expense),
      Account(id: 'inventory-shrinkage', code: '6300', name: 'Inventory shrinkage', type: AccountType.expense),
    ];

    await db.transaction((txn) async {
      for (final account in starterAccounts) {
        await txn.insert('accounts', {
          'id': account.id,
          'code': account.code,
          'name': account.name,
          'type': account.type.name,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> createAccount(AccountDraft draft) async {
    final code = draft.code.trim();
    final name = draft.name.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]{1,20}$').hasMatch(code) || name.isEmpty) {
      throw ArgumentError('Enter a name and an account code of 1 to 20 letters or digits.');
    }
    await _database.handle.insert('accounts', {
      'id': 'account_${DateTime.now().microsecondsSinceEpoch}',
      'code': code,
      'name': name,
      'type': draft.type.name,
    });
  }

  Future<LedgerSnapshot> loadSnapshot() async {
    final db = _database.handle;
    final accountRows = await db.query(
      'accounts',
      where: 'is_active = 1',
      orderBy: 'code ASC',
    );
    final accounts = accountRows.map(Account.fromRow).toList(growable: false);

    final activityRows = await db.rawQuery('''
      SELECT account_id,
             COALESCE(SUM(debit_cents), 0) AS debits,
             COALESCE(SUM(credit_cents), 0) AS credits
      FROM journal_lines
      GROUP BY account_id
    ''');
    final activity = activityRows
        .map((row) => AccountActivity(
              accountId: row['account_id']! as String,
              debits: row['debits']! as int,
              credits: row['credits']! as int,
            ))
        .toList(growable: false);

    final entryRows = await db.rawQuery('''
      SELECT e.id,
             e.entry_date,
             e.description,
             COALESCE(SUM(d.debit_cents), 0) AS amount_cents,
             (SELECT a.name
                FROM journal_lines l JOIN accounts a ON a.id = l.account_id
               WHERE l.entry_id = e.id AND l.debit_cents > 0 LIMIT 1) AS debit_account,
             (SELECT a.name
                FROM journal_lines l JOIN accounts a ON a.id = l.account_id
               WHERE l.entry_id = e.id AND l.credit_cents > 0 LIMIT 1) AS credit_account
      FROM journal_entries e
      LEFT JOIN journal_lines d ON d.entry_id = e.id AND d.debit_cents > 0
      GROUP BY e.id
      ORDER BY e.entry_date DESC, e.created_at DESC
      LIMIT 200
    ''');
    final entries = entryRows.map(LedgerEntry.fromRow).toList(growable: false);
    final productRows = await db.query('products', orderBy: 'name COLLATE NOCASE ASC');
    final products = productRows.map(Product.fromRow).toList(growable: false);
    final invoiceRows = await db.query(
      'sales_invoices',
      orderBy: 'issue_date DESC, created_at DESC',
      limit: 200,
    );
    final invoices = invoiceRows.map(SalesInvoice.fromRow).toList(growable: false);

    return AccountingEngine.summarize(
      accounts: accounts,
      entries: entries,
      activity: activity,
      products: products,
      invoices: invoices,
    );
  }

  Future<void> createEntry(JournalDraft draft) => createEntries([draft]);

  Future<void> createEntries(List<JournalDraft> drafts) async {
    if (drafts.isEmpty) return;
    for (final draft in drafts) {
      AccountingEngine.validateDraft(draft);
    }
    await _database.handle.transaction((txn) async {
      for (final draft in drafts) {
        await _insertBalancedEntry(txn, draft);
      }
    });
  }

  Future<void> _insertBalancedEntry(Transaction txn, JournalDraft draft) async {
    final accountRows = await txn.query(
      'accounts',
      columns: ['id'],
      where: 'id IN (?, ?) AND is_active = 1',
      whereArgs: [draft.debitAccountId, draft.creditAccountId],
    );
    if (accountRows.length != 2) {
      throw ArgumentError('Choose two active accounts from the chart of accounts.');
    }

    final entryId = 'entry_${DateTime.now().microsecondsSinceEpoch}';
    await txn.insert('journal_entries', {
      'id': entryId,
      'entry_date': _dateOnly(draft.date),
      'description': draft.description.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await txn.insert('journal_lines', {
      'entry_id': entryId,
      'account_id': draft.debitAccountId,
      'debit_cents': draft.amountCents,
      'credit_cents': 0,
    });
    await txn.insert('journal_lines', {
      'entry_id': entryId,
      'account_id': draft.creditAccountId,
      'debit_cents': 0,
      'credit_cents': draft.amountCents,
    });
  }

  Future<List<Product>> loadProducts() async {
    final rows = await _database.handle.query('products', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Product.fromRow).toList(growable: false);
  }

  Future<void> createProduct(ProductDraft draft) async {
    if (draft.name.trim().isEmpty || draft.sku.trim().isEmpty) {
      throw ArgumentError('Product name and SKU are required.');
    }
    if (draft.unitPriceCents <= 0 || draft.unitCostCents < 0 || draft.stockQuantity < 0) {
      throw ArgumentError('Price must be positive; cost and stock cannot be negative.');
    }
    final db = _database.handle;
    final now = DateTime.now();
    final productId = 'product_${now.microsecondsSinceEpoch}';
    await db.transaction((txn) async {
      await txn.insert('products', {
        'id': productId,
        'sku': draft.sku.trim().toUpperCase(),
        'name': draft.name.trim(),
        'unit_price_cents': draft.unitPriceCents,
        'unit_cost_cents': draft.unitCostCents,
        'stock_quantity': draft.stockQuantity,
        'created_at': now.toUtc().toIso8601String(),
      });
      final openingValue = draft.unitCostCents * draft.stockQuantity;
      if (openingValue > 0) {
        await _insertTwoLineJournalEntry(
          txn,
          entryId: 'opening_$productId',
          date: now,
          description: 'Opening stock · ${draft.sku.trim().toUpperCase()}',
          debitAccountId: 'inventory',
          creditAccountId: 'owner-equity',
          amountCents: openingValue,
        );
      }
    });
  }

  Future<void> adjustStock(String productId, int delta) async {
    if (delta == 0) throw ArgumentError('Stock adjustment cannot be zero.');
    await _database.handle.transaction((txn) async {
      final rows = await txn.query('products', where: 'id = ?', whereArgs: [productId]);
      if (rows.isEmpty) throw ArgumentError('Product not found.');
      final product = Product.fromRow(rows.first);
      if (product.stockQuantity + delta < 0) {
        throw ArgumentError('Stock cannot be negative.');
      }
      await txn.update(
        'products',
        {'stock_quantity': product.stockQuantity + delta},
        where: 'id = ?',
        whereArgs: [productId],
      );
      final value = product.unitCostCents * delta.abs();
      if (value > 0) {
        await _insertTwoLineJournalEntry(
          txn,
          entryId: 'stock_${DateTime.now().microsecondsSinceEpoch}',
          date: DateTime.now(),
          description: delta > 0 ? 'Restock · ${product.sku}' : 'Stock reduction · ${product.sku}',
          debitAccountId: delta > 0 ? 'inventory' : 'inventory-shrinkage',
          creditAccountId: delta > 0 ? 'cash' : 'inventory',
          amountCents: value,
        );
      }
    });
  }

  Future<void> _insertTwoLineJournalEntry(
    Transaction txn, {
    required String entryId,
    required DateTime date,
    required String description,
    required String debitAccountId,
    required String creditAccountId,
    required int amountCents,
  }) async {
    await txn.insert('journal_entries', {
      'id': entryId,
      'entry_date': _dateOnly(date),
      'description': description,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await txn.insert('journal_lines', {
      'entry_id': entryId,
      'account_id': debitAccountId,
      'debit_cents': amountCents,
      'credit_cents': 0,
    });
    await txn.insert('journal_lines', {
      'entry_id': entryId,
      'account_id': creditAccountId,
      'debit_cents': 0,
      'credit_cents': amountCents,
    });
  }

  Future<void> createInvoice(InvoiceDraft draft) async {
    if (draft.customerName.trim().isEmpty || draft.lines.isEmpty || draft.taxCents < 0) {
      throw ArgumentError('Customer, at least one line, and a non-negative tax amount are required.');
    }

    await _database.handle.transaction((txn) async {
      final lines = <({Product product, int quantity, int lineTotal})>[];
      var subtotal = 0;
      var costTotal = 0;
      for (final line in draft.lines) {
        if (line.quantity <= 0) throw ArgumentError('Invoice quantities must be positive.');
        final rows = await txn.query('products', where: 'id = ?', whereArgs: [line.productId]);
        if (rows.isEmpty) throw ArgumentError('An invoice product no longer exists.');
        final product = Product.fromRow(rows.first);
        if (product.stockQuantity < line.quantity) {
          throw ArgumentError('Not enough stock for ${product.name}.');
        }
        final lineTotal = product.unitPriceCents * line.quantity;
        subtotal += lineTotal;
        costTotal += product.unitCostCents * line.quantity;
        lines.add((product: product, quantity: line.quantity, lineTotal: lineTotal));
      }
      if (subtotal <= 0) throw ArgumentError('Invoice total must be greater than zero.');

      final countRows = await txn.rawQuery('SELECT COUNT(*) AS invoice_count FROM sales_invoices');
      final nextNumber = (countRows.first['invoice_count']! as int) + 1;
      final invoiceNumber = 'INV-${draft.date.year}-${nextNumber.toString().padLeft(6, '0')}';
      final invoiceId = 'invoice_${DateTime.now().microsecondsSinceEpoch}';
      final total = subtotal + draft.taxCents;
      final createdAt = DateTime.now().toUtc().toIso8601String();

      await txn.insert('sales_invoices', {
        'id': invoiceId,
        'invoice_number': invoiceNumber,
        'customer_name': draft.customerName.trim(),
        'issue_date': _dateOnly(draft.date),
        'status': 'issued',
        'subtotal_cents': subtotal,
        'tax_cents': draft.taxCents,
        'total_cents': total,
        'created_at': createdAt,
      });

      for (final line in lines) {
        final updated = await txn.rawUpdate(
          'UPDATE products SET stock_quantity = stock_quantity - ? WHERE id = ? AND stock_quantity >= ?',
          [line.quantity, line.product.id, line.quantity],
        );
        if (updated != 1) throw ArgumentError('Stock changed while creating the invoice.');
        await txn.insert('invoice_lines', {
          'invoice_id': invoiceId,
          'product_id': line.product.id,
          'description': line.product.name,
          'quantity': line.quantity,
          'unit_price_cents': line.product.unitPriceCents,
          'unit_cost_cents': line.product.unitCostCents,
          'line_total_cents': line.lineTotal,
        });
      }

      final journalId = 'journal_$invoiceId';
      await txn.insert('journal_entries', {
        'id': journalId,
        'entry_date': _dateOnly(draft.date),
        'description': 'Invoice $invoiceNumber · ${draft.customerName.trim()}',
        'created_at': createdAt,
      });
      await txn.insert('journal_lines', {
        'entry_id': journalId,
        'account_id': 'receivables',
        'debit_cents': total,
        'credit_cents': 0,
      });
      await txn.insert('journal_lines', {
        'entry_id': journalId,
        'account_id': 'sales-income',
        'debit_cents': 0,
        'credit_cents': subtotal,
      });
      if (draft.taxCents > 0) {
        await txn.insert('journal_lines', {
          'entry_id': journalId,
          'account_id': 'tax-payable',
          'debit_cents': 0,
          'credit_cents': draft.taxCents,
        });
      }
      if (costTotal > 0) {
        await txn.insert('journal_lines', {
          'entry_id': journalId,
          'account_id': 'cost-of-goods',
          'debit_cents': costTotal,
          'credit_cents': 0,
        });
        await txn.insert('journal_lines', {
          'entry_id': journalId,
          'account_id': 'inventory',
          'debit_cents': 0,
          'credit_cents': costTotal,
        });
      }
    });
  }

  Future<AppSettings> loadAppSettings() async {
    final rows = await _database.handle.query('app_settings');
    final values = {
      for (final row in rows)
        row['setting_key']! as String: row['setting_value']! as String,
    };
    return AppSettings(
      darkMode: values['dark_mode'] == 'true',
      languageCode: values['language_code'] == 'fa' ? 'fa' : 'en',
      businessName: values['business_name'] ?? '',
      currencyCode: _supportedCurrencies.contains(values['currency_code'])
          ? values['currency_code']!
          : 'USD',
    );
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    final txn = _database.handle;
    await txn.transaction((batch) async {
      await batch.insert(
        'app_settings',
        {'setting_key': 'dark_mode', 'setting_value': '${settings.darkMode}'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await batch.insert(
        'app_settings',
        {'setting_key': 'language_code', 'setting_value': settings.languageCode},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await batch.insert(
        'app_settings',
        {'setting_key': 'business_name', 'setting_value': settings.businessName.trim()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await batch.insert(
        'app_settings',
        {'setting_key': 'currency_code', 'setting_value': settings.currencyCode},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> exportBackup(String destinationPath) async {
    final file = File(destinationPath);
    if (p.normalize(file.absolute.path).toLowerCase() ==
        p.normalize(_database.path).toLowerCase()) {
      throw ArgumentError('Choose a different file for the backup.');
    }
    if (await file.exists()) await file.delete();
    final normalizedPath = file.absolute.path.replaceAll("'", "''");
    await _database.handle.execute("VACUUM INTO '$normalizedPath'");
  }

  static const _supportedCurrencies = {'USD', 'EUR', 'GBP', 'CAD', 'AUD', 'AED'};

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
