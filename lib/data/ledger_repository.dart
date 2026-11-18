import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/account.dart';
import '../domain/accounting_engine.dart';
import '../domain/ledger_entry.dart';
import '../domain/product.dart';
import '../domain/sales_invoice.dart';
import '../domain/app_settings.dart';
import '../domain/money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'ledger_database.dart';

class LedgerRepository {
  LedgerRepository(this._database);

  LedgerDatabase _database;

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
      Account(id: 'inventory-valuation-gain', code: '4200', name: 'Inventory valuation gain', type: AccountType.income),
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
    final invoiceRows = await db.rawQuery('''
      SELECT i.*, COALESCE(SUM(p.amount_cents), 0) AS paid_cents
      FROM sales_invoices i
      LEFT JOIN invoice_payments p ON p.invoice_id = i.id
      GROUP BY i.id
      ORDER BY i.issue_date DESC, i.created_at DESC
      LIMIT 200
    ''');
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
      await _requireAccountingCurrency(txn);
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
    final rows = await _database.handle.query(
      'products',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(Product.fromRow).toList(growable: false);
  }

  Future<ProductPage> loadProductPage({
    String query = '',
    int pageIndex = 0,
    int pageSize = 25,
    String sortBy = 'name',
    bool ascending = true,
  }) async {
    const allowedPageSizes = {10, 25, 50, 100};
    const sortColumns = {
      'name': 'name COLLATE NOCASE',
      'sku': 'sku COLLATE NOCASE',
      'category': 'category COLLATE NOCASE',
      'price': 'unit_price_cents',
      'stock': 'stock_quantity',
    };
    if (!allowedPageSizes.contains(pageSize)) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Use 10, 25, 50, or 100.');
    }
    if (pageIndex < 0) throw ArgumentError.value(pageIndex, 'pageIndex');
    final sortColumn = sortColumns[sortBy];
    if (sortColumn == null) throw ArgumentError.value(sortBy, 'sortBy');

    final normalizedQuery = query.trim();
    final escapedQuery = normalizedQuery
        .replaceAll('!', '!!')
        .replaceAll('%', '!%')
        .replaceAll('_', '!_');
    final where = normalizedQuery.isEmpty
        ? ''
        : "WHERE (name LIKE ? ESCAPE '!' OR sku LIKE ? ESCAPE '!' OR barcode LIKE ? ESCAPE '!' OR category LIKE ? ESCAPE '!')";
    final whereArgs = normalizedQuery.isEmpty
        ? <Object?>[]
        : List<Object?>.filled(4, '$escapedQuery%');

    return _database.handle.transaction((txn) async {
      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS total_count FROM products $where',
        whereArgs,
      );
      final totalCount = countRows.single['total_count']! as int;
      final lastPageIndex =
          totalCount == 0 ? 0 : (totalCount - 1) ~/ pageSize;
      final safePageIndex =
          pageIndex > lastPageIndex ? lastPageIndex : pageIndex;
      final rows = await txn.rawQuery(
        'SELECT * FROM products $where ORDER BY $sortColumn ${ascending ? 'ASC' : 'DESC'}, id ASC LIMIT ? OFFSET ?',
        [...whereArgs, pageSize, safePageIndex * pageSize],
      );
      return ProductPage(
        products: rows.map(Product.fromRow).toList(growable: false),
        totalCount: totalCount,
        pageIndex: safePageIndex,
        pageSize: pageSize,
      );
    });
  }

  Future<void> createProduct(ProductDraft draft) async {
    _validateProductDraft(draft);
    final db = _database.handle;
    final now = DateTime.now();
    final productId = 'product_${now.microsecondsSinceEpoch}';
    final timestamp = now.toUtc().toIso8601String();
    await db.transaction((txn) async {
      await _requireAccountingCurrency(txn);
      await txn.insert('products', {
        'id': productId,
        'sku': draft.sku.trim().toUpperCase(),
        'name': draft.name.trim(),
        'description': draft.description.trim(),
        'category': draft.category.trim(),
        'barcode': draft.barcode.trim(),
        'unit_price_cents': draft.unitPriceCents,
        'unit_cost_cents': draft.unitCostCents,
        'stock_quantity': draft.stockQuantity,
        'created_at': timestamp,
        'updated_at': timestamp,
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

  Future<void> updateProduct(String productId, ProductDraft draft) async {
    _validateProductDraft(draft);
    await _database.handle.transaction((txn) async {
      await _requireAccountingCurrency(txn);
      final rows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('Product not found.');
      final current = Product.fromRow(rows.single);
      final costDelta = draft.unitCostCents - current.unitCostCents;
      const maxSignedInt = 0x7fffffffffffffff;
      if (costDelta != 0 &&
          current.stockQuantity > maxSignedInt ~/ costDelta.abs()) {
        throw ArgumentError('Updated inventory value exceeds the supported integer range.');
      }
      final inventoryValueDelta = costDelta * current.stockQuantity;

      await txn.update(
        'products',
        {
          'sku': draft.sku.trim().toUpperCase(),
          'name': draft.name.trim(),
          'description': draft.description.trim(),
          'category': draft.category.trim(),
          'barcode': draft.barcode.trim(),
          'unit_price_cents': draft.unitPriceCents,
          'unit_cost_cents': draft.unitCostCents,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [productId],
      );

      if (inventoryValueDelta != 0) {
        final now = DateTime.now();
        final amount = inventoryValueDelta.abs();
        await _insertTwoLineJournalEntry(
          txn,
          entryId: 'product_cost_${now.microsecondsSinceEpoch}',
          date: now,
          description: 'Inventory cost update · ${current.sku}',
          debitAccountId:
              inventoryValueDelta > 0 ? 'inventory' : 'inventory-shrinkage',
          creditAccountId:
              inventoryValueDelta > 0 ? 'inventory-valuation-gain' : 'inventory',
          amountCents: amount,
        );
      }
    });
  }

  void _validateProductDraft(ProductDraft draft) {
    if (draft.name.trim().isEmpty || draft.sku.trim().isEmpty) {
      throw ArgumentError('Product name and SKU are required.');
    }
    if (draft.unitPriceCents <= 0 || draft.unitCostCents < 0 || draft.stockQuantity < 0) {
      throw ArgumentError('Price must be positive; cost and stock cannot be negative.');
    }
    const maxSignedInt = 0x7fffffffffffffff;
    if (draft.stockQuantity > 0 &&
        draft.unitCostCents > maxSignedInt ~/ draft.stockQuantity) {
      throw ArgumentError('Opening inventory value exceeds the supported integer range.');
    }
    if (draft.barcode.trim().contains(RegExp(r'\s'))) {
      throw ArgumentError('Barcode cannot contain whitespace.');
    }
  }

  Future<void> adjustStock(String productId, int delta) async {
    if (delta == 0) throw ArgumentError('Stock adjustment cannot be zero.');
    await _database.handle.transaction((txn) async {
      await _requireAccountingCurrency(txn);
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
      await _requireAccountingCurrency(txn);
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

  Future<void> recordInvoicePayment(InvoicePaymentDraft draft) async {
    if (draft.amountCents <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }

    await _database.handle.transaction((txn) async {
      await _requireAccountingCurrency(txn);
      final invoiceRows = await txn.query(
        'sales_invoices',
        where: 'id = ?',
        whereArgs: [draft.invoiceId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw ArgumentError('The invoice no longer exists.');
      }
      final invoice = invoiceRows.single;
      if (invoice['status'] == 'void') {
        throw ArgumentError('A void invoice cannot receive a payment.');
      }
      final totalCents = invoice['total_cents']! as int;
      final paidRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount_cents), 0) AS paid_cents FROM invoice_payments WHERE invoice_id = ?',
        [draft.invoiceId],
      );
      final alreadyPaidCents = paidRows.single['paid_cents']! as int;
      final balanceDueCents = totalCents - alreadyPaidCents;
      if (balanceDueCents <= 0 || draft.amountCents > balanceDueCents) {
        throw ArgumentError('Payment exceeds the invoice balance due.');
      }

      final newPaidCents = alreadyPaidCents + draft.amountCents;
      final createdAt = DateTime.now().toUtc().toIso8601String();
      await txn.insert('invoice_payments', {
        'id': 'payment_${draft.invoiceId}_$newPaidCents',
        'invoice_id': draft.invoiceId,
        'payment_date': _dateOnly(draft.date),
        'amount_cents': draft.amountCents,
        'created_at': createdAt,
      });
      await _insertBalancedEntry(
        txn,
        JournalDraft(
          date: draft.date,
          description: 'Invoice payment ${invoice['invoice_number']} · ${invoice['customer_name']}',
          amountCents: draft.amountCents,
          debitAccountId: 'cash',
          creditAccountId: 'receivables',
        ),
      );
      final updated = await txn.update(
        'sales_invoices',
        {'status': newPaidCents == totalCents ? 'paid' : 'issued'},
        where: 'id = ? AND status != ?',
        whereArgs: [draft.invoiceId, 'void'],
      );
      if (updated != 1) {
        throw StateError('The invoice status changed while recording payment.');
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
      accountingCurrencyConfigured: values['accounting_currency_configured'] == 'true',
      desktopSidebarCollapsed: values['desktop_sidebar_collapsed'] == 'true',
    );
  }

  Future<void> configureAccountingCurrency({
    required String currencyCode,
    required bool confirmExistingAmounts,
  }) async {
    final normalizedCode = currencyCode.toUpperCase();
    if (!_supportedCurrencies.contains(normalizedCode)) {
      throw ArgumentError.value(currencyCode, 'currencyCode', 'Unsupported currency.');
    }
    await _database.handle.transaction((txn) async {
      final rows = await txn.query(
        'app_settings',
        columns: ['setting_key', 'setting_value'],
        where: "setting_key IN ('currency_code', 'accounting_currency_configured')",
      );
      final settings = {
        for (final row in rows)
          row['setting_key']! as String: row['setting_value']! as String,
      };
      final wasConfigured = settings['accounting_currency_configured'] == 'true';
      final currentCode = settings['currency_code'] ?? 'USD';
      final hasData = await _hasMonetaryData(txn);
      if (hasData && !wasConfigured && !confirmExistingAmounts) {
        throw StateError('Confirm how existing amounts should be interpreted before setting the base currency.');
      }
      if (hasData && wasConfigured && currentCode != normalizedCode) {
        throw StateError('The base currency is locked after monetary records exist. Conversion is not available.');
      }
      await _writeAppSetting(txn, 'currency_code', normalizedCode);
      await _writeAppSetting(txn, 'accounting_currency_configured', 'true');
    });
  }

  Future<bool> _hasMonetaryData(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery('''
      SELECT (SELECT COUNT(*) FROM products)
           + (SELECT COUNT(*) FROM journal_entries)
           + (SELECT COUNT(*) FROM sales_invoices)
           + (SELECT COUNT(*) FROM invoice_payments) AS record_count
    ''');
    return (rows.single['record_count']! as int) > 0;
  }

  /// Reads the full ledger, not the recent-page snapshot, before legacy currency confirmation.
  Future<bool> hasMonetaryRecords() => _hasMonetaryData(_database.handle);

  Future<void> _requireAccountingCurrency(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['accounting_currency_configured'],
      limit: 1,
    );
    if (rows.isEmpty || rows.single['setting_value'] != 'true') {
      throw StateError('Choose and confirm a base accounting currency in Settings before recording monetary data.');
    }
  }

  Future<void> _writeAppSetting(
    DatabaseExecutor executor,
    String key,
    String value,
  ) async {
    await executor.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    final requestedCurrencyCode = settings.currencyCode.toUpperCase();
    if (!_supportedCurrencies.contains(requestedCurrencyCode)) {
      throw ArgumentError.value(
        settings.currencyCode,
        'currencyCode',
        'Unsupported currency.',
      );
    }
    final database = _database.handle;
    await database.transaction((txn) async {
      final rows = await txn.query(
        'app_settings',
        columns: ['setting_key', 'setting_value'],
        where: "setting_key IN ('currency_code', 'accounting_currency_configured')",
      );
      final currentSettings = {
        for (final row in rows)
          row['setting_key']! as String: row['setting_value']! as String,
      };
      final currentCode = currentSettings['currency_code'] ?? 'USD';
      final wasConfigured = currentSettings['accounting_currency_configured'] == 'true';
      final hasData = await _hasMonetaryData(txn);
      if (hasData &&
          requestedCurrencyCode != currentCode &&
          (wasConfigured || !settings.accountingCurrencyConfigured)) {
        throw StateError('Use the currency confirmation workflow before changing the base currency.');
      }
      if (hasData && !wasConfigured && settings.accountingCurrencyConfigured) {
        throw StateError('Use configureAccountingCurrency to confirm legacy amounts.');
      }
      final configured = wasConfigured ||
          settings.accountingCurrencyConfigured ||
          (!hasData && settings.currencyCode != currentCode);

      await txn.insert('app_settings',
        {'setting_key': 'dark_mode', 'setting_value': '${settings.darkMode}'},
        conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings',
        {'setting_key': 'language_code', 'setting_value': settings.languageCode},
        conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings',
        {'setting_key': 'business_name', 'setting_value': settings.businessName.trim()},
        conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings',
        {'setting_key': 'currency_code', 'setting_value': requestedCurrencyCode},
        conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings',
        {'setting_key': 'accounting_currency_configured', 'setting_value': '${configured}'},
        conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings',
        {'setting_key': 'desktop_sidebar_collapsed', 'setting_value': '${settings.desktopSidebarCollapsed}'},
        conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<void> close() => _database.close();

  /// Restores a validated Ledgerline SQLite backup without discarding the
  /// current database until the replacement has passed integrity checks.
  /// Returns the path of a recovery copy of the previous database, if one
  /// existed.
  Future<String?> restoreBackup(String backupPath) async {
    if (_database.path == inMemoryDatabasePath) {
      throw StateError('A backup cannot be restored into an in-memory ledger.');
    }

    final targetPath = p.normalize(File(_database.path).absolute.path);
    final sourceFile = File(backupPath).absolute;
    final sourcePath = p.normalize(sourceFile.path);
    if (sourcePath.toLowerCase() == targetPath.toLowerCase()) {
      throw ArgumentError('Choose a backup file other than the active database.');
    }
    if (!await sourceFile.exists() || await sourceFile.length() < 100) {
      throw const FormatException('The selected file is not a valid SQLite backup.');
    }

    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final stagedFile = File(p.join(targetFile.parent.path, 'ledgerline-restore-$stamp.sqlite'));
    final recoveryFile = File(p.join(targetFile.parent.path, 'ledgerline-recovery-$stamp.sqlite'));
    await sourceFile.copy(stagedFile.path);

    LedgerDatabase? stagedDatabase;
    var originalClosed = false;
    var originalMoved = false;
    var stagedInstalled = false;
    try {
      try {
        final readOnlyDatabase = await databaseFactoryFfi.openDatabase(
          stagedFile.path,
          options: OpenDatabaseOptions(readOnly: true),
        );
        try {
          await _validateBackupStructure(readOnlyDatabase, allowLegacySchema: true);
        } finally {
          await readOnlyDatabase.close();
        }
        stagedDatabase = await LedgerDatabase.open(stagedFile.path);
        await _validateBackup(stagedDatabase.handle);
        await stagedDatabase.close();
        stagedDatabase = null;
      } on Object catch (error) {
        await stagedDatabase?.close();
        stagedDatabase = null;
        throw FormatException('The selected file is not a valid Ledgerline backup: $error');
      }

      await _database.handle.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await _database.close();
      originalClosed = true;

      try {
        if (await targetFile.exists()) {
          await targetFile.rename(recoveryFile.path);
          originalMoved = true;
        }
        await stagedFile.rename(targetPath);
        stagedInstalled = true;
        final replacement = await LedgerDatabase.open(targetPath);
        try {
          await _validateBackup(replacement.handle);
        } on Object {
          await replacement.close();
          rethrow;
        }
        _database = replacement;
        originalClosed = false;
        return originalMoved ? recoveryFile.path : null;
      } on Object {
        if (stagedInstalled && await targetFile.exists()) await targetFile.delete();
        if (originalMoved && await recoveryFile.exists()) {
          await recoveryFile.rename(targetPath);
        }
        _database = await LedgerDatabase.open(targetPath);
        originalClosed = false;
        rethrow;
      }
    } finally {
      await stagedDatabase?.close();
      if (await stagedFile.exists()) await stagedFile.delete();
      if (originalClosed) _database = await LedgerDatabase.open(targetPath);
    }
  }

  Future<void> _validateBackup(Database database) async {
    await _validateBackupStructure(database);

    final integrityRows = await database.rawQuery('PRAGMA integrity_check');
    if (integrityRows.isEmpty ||
        integrityRows.any((row) => row.values.first.toString().toLowerCase() != 'ok')) {
      throw const FormatException('The backup database failed SQLite integrity checks.');
    }
    if ((await database.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('The backup contains broken references between records.');
    }

    final unbalancedEntries = await database.rawQuery('''
      SELECT e.id
      FROM journal_entries e
      LEFT JOIN journal_lines l ON l.entry_id = e.id
      GROUP BY e.id
      HAVING COUNT(l.id) < 2
         OR COALESCE(SUM(l.debit_cents), 0) <> COALESCE(SUM(l.credit_cents), 0)
      LIMIT 1
    ''');
    if (unbalancedEntries.isNotEmpty) {
      throw const FormatException('The backup contains an unbalanced journal entry.');
    }
  }

  Future<void> _validateBackupStructure(
    Database database, {
    bool allowLegacySchema = false,
  }) async {
    final requiredTables = <String>{
      'accounts',
      'journal_entries',
      'journal_lines',
      'products',
      'sales_invoices',
      'invoice_lines',
      'app_settings',
    };
    if (!allowLegacySchema) requiredTables.add('invoice_payments');
    final tableRows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tableRows.map((row) => row['name']! as String).toSet();
    if (!tableNames.containsAll(requiredTables)) {
      throw const FormatException('The backup does not contain a complete Ledgerline database.');
    }
  }

  static const _supportedCurrencies = CurrencyDefinition.codes;

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
