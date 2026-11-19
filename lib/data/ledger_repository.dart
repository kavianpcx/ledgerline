import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/account.dart';
import '../domain/accounting_engine.dart';
import '../domain/ledger_entry.dart';
import '../domain/product.dart';
import '../domain/sales_invoice.dart';
import '../domain/stock_movement.dart';
import '../domain/app_settings.dart';
import '../domain/money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'ledger_database.dart';

class LedgerRepository {
  LedgerRepository(this._database);

  static const Set<String> _allowedPaymentMethods = {'cash', 'bank_transfer'};
  static const List<String> _productColumns = [
    'id',
    'sku',
    'name',
    'unit_price_cents',
    'unit_cost_cents',
    'stock_quantity',
    'created_at',
    'updated_at',
    'description',
    'category',
    'barcode',
    'icon_key',
  ];

  LedgerDatabase _database;

  Future<void> initialize() async {
    final db = _database.handle;
    const starterAccounts = <Account>[
      Account(id: 'cash', code: '1000', name: 'Cash', type: AccountType.asset),
      Account(id: 'bank', code: '1010', name: 'Bank', type: AccountType.asset),
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
    final productRows = await db.query(
      'products',
      columns: _productColumns,
      orderBy: 'name COLLATE NOCASE ASC',
    );
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


  /// Returns normalized identifiers that already exist in the catalog.
  /// Reads are chunked so importing a large file stays below SQLite's bind limit.
  Future<Set<String>> findProductImportConflicts(
    List<ProductDraft> drafts,
  ) async =>
      _database.handle.transaction(
        (txn) => _findProductImportConflictsInTransaction(txn, drafts),
      );

  /// Imports a catalog as a single unit. Products and their opening inventory
  /// journals either all commit or all roll back.
  Future<int> importProducts(List<ProductDraft> drafts) async {
    if (drafts.isEmpty) {
      throw ArgumentError('Choose at least one valid product to import.');
    }
    final skus = <String>{};
    final barcodes = <String>{};
    for (final draft in drafts) {
      _validateProductDraft(draft);
      final sku = draft.sku.trim().toUpperCase();
      if (!skus.add(sku)) {
        throw ArgumentError('Duplicate SKU in import: ' + sku);
      }
      final barcode = draft.barcode.trim();
      if (barcode.isNotEmpty && !barcodes.add(barcode)) {
        throw ArgumentError('Duplicate barcode in import: ' + barcode);
      }
    }

    return _database.handle.transaction((txn) async {
      await _requireAccountingCurrency(txn);
      final conflicts = await _findProductImportConflictsInTransaction(txn, drafts);
      if (conflicts.isNotEmpty) {
        throw ArgumentError(
          'Product identifiers already exist: ' + conflicts.join(', '),
        );
      }

      final now = DateTime.now();
      final timestamp = now.toUtc().toIso8601String();
      for (var index = 0; index < drafts.length; index++) {
        final draft = drafts[index];
        final productId =
            'product_import_' + now.microsecondsSinceEpoch.toString() + '_' + index.toString();
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
        if (draft.stockQuantity > 0) {
          await _insertStockMovement(
            txn,
            productId: productId,
            productSku: draft.sku.trim().toUpperCase(),
            productName: draft.name.trim(),
            movementType: 'opening_balance',
            quantityDelta: draft.stockQuantity,
            unitCostCents: draft.unitCostCents,
            referenceId: openingValue > 0 ? 'opening_' + productId : '',
            description: 'Opening stock · ' + draft.sku.trim().toUpperCase(),
            occurredAt: now,
          );
        }
        if (openingValue > 0) {
          await _insertTwoLineJournalEntry(
            txn,
            entryId: 'opening_' + productId,
            date: now,
            description: 'Opening stock · ' + draft.sku.trim().toUpperCase(),
            debitAccountId: 'inventory',
            creditAccountId: 'owner-equity',
            amountCents: openingValue,
          );
        }
      }
      return drafts.length;
    });
  }

  Future<Set<String>> _findProductImportConflictsInTransaction(
    Transaction txn,
    List<ProductDraft> drafts,
  ) async {
    final conflicts = <String>{};
    const chunkSize = 300;
    for (var start = 0; start < drafts.length; start += chunkSize) {
      final end = start + chunkSize < drafts.length
          ? start + chunkSize
          : drafts.length;
      final chunk = drafts.sublist(start, end);
      final skus = chunk.map((draft) => draft.sku.trim().toUpperCase()).toSet();
      final barcodes = chunk
          .map((draft) => draft.barcode.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      final predicates = <String>[];
      final args = <Object?>[];
      if (skus.isNotEmpty) {
        predicates.add('UPPER(sku) IN (' + List.filled(skus.length, '?').join(',') + ')');
        args.addAll(skus);
      }
      if (barcodes.isNotEmpty) {
        predicates.add('barcode IN (' + List.filled(barcodes.length, '?').join(',') + ')');
        args.addAll(barcodes);
      }
      if (predicates.isEmpty) continue;
      final rows = await txn.rawQuery(
        'SELECT sku, barcode FROM products WHERE ' + predicates.join(' OR '),
        args,
      );
      for (final row in rows) {
        final sku = (row['sku'] as String?)?.trim().toUpperCase() ?? '';
        final barcode = (row['barcode'] as String?)?.trim() ?? '';
        if (skus.contains(sku)) conflicts.add('sku:' + sku);
        if (barcode.isNotEmpty && barcodes.contains(barcode)) {
          conflicts.add('barcode:' + barcode);
        }
      }
    }
    return conflicts;
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
      columns: _productColumns,
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(Product.fromRow).toList(growable: false);
  }

  /// Reloads selected catalog records without materializing the full catalog.
  /// Used at checkout to ensure a cart does not silently use stale prices.
  Future<List<Product>> loadProductsByIds(List<String> productIds) async {
    if (productIds.isEmpty) return const [];
    final products = <Product>[];
    const chunkSize = 400;
    for (var start = 0; start < productIds.length; start += chunkSize) {
      final end = start + chunkSize < productIds.length
          ? start + chunkSize
          : productIds.length;
      final ids = productIds.sublist(start, end).toSet().toList(growable: false);
      final rows = await _database.handle.query(
        'products',
        columns: _productColumns,
        where: 'id IN (' + List.filled(ids.length, '?').join(',') + ')',
        whereArgs: ids,
      );
      products.addAll(rows.map(Product.fromRow));
    }
    return products;
  }

  Future<Product?> loadProductByBarcode(String barcode) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) return null;
    final rows = await _database.handle.query(
      'products',
      columns: _productColumns,
      where: 'barcode = ?',
      whereArgs: [normalizedBarcode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromRow(rows.single);
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

  Future<StockMovementPage> loadStockMovementPage({
    required String productId,
    int pageIndex = 0,
    int pageSize = 25,
  }) async {
    const allowedPageSizes = {10, 25, 50, 100};
    if (productId.trim().isEmpty) {
      throw ArgumentError.value(productId, 'productId');
    }
    if (!allowedPageSizes.contains(pageSize)) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Use 10, 25, 50, or 100.');
    }
    if (pageIndex < 0) throw ArgumentError.value(pageIndex, 'pageIndex');

    return _database.handle.transaction((txn) async {
      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS total_count FROM stock_movements WHERE product_id = ?',
        [productId],
      );
      final totalCount = countRows.single['total_count']! as int;
      final lastPageIndex =
          totalCount == 0 ? 0 : (totalCount - 1) ~/ pageSize;
      final safePageIndex =
          pageIndex > lastPageIndex ? lastPageIndex : pageIndex;
      final rows = await txn.query(
        'stock_movements',
        where: 'product_id = ?',
        whereArgs: [productId],
        orderBy: 'recorded_at DESC, id DESC',
        limit: pageSize,
        offset: safePageIndex * pageSize,
      );
      return StockMovementPage(
        movements: rows.map(StockMovement.fromRow).toList(growable: false),
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
        'icon_key': draft.iconKey ?? 'inventory',
        'image_bytes': draft.imageBytes,
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      final openingValue = draft.unitCostCents * draft.stockQuantity;
      if (draft.stockQuantity > 0) {
        await _insertStockMovement(
          txn,
          productId: productId,
          productSku: draft.sku.trim().toUpperCase(),
          productName: draft.name.trim(),
          movementType: 'opening_balance',
          quantityDelta: draft.stockQuantity,
          unitCostCents: draft.unitCostCents,
          referenceId: openingValue > 0 ? 'opening_' + productId : '',
          description: 'Opening stock · ' + draft.sku.trim().toUpperCase(),
          occurredAt: now,
        );
      }
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
        columns: [..._productColumns, 'image_bytes'],
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

      final updateValues = <String, Object?>{
        'sku': draft.sku.trim().toUpperCase(),
        'name': draft.name.trim(),
        'description': draft.description.trim(),
        'category': draft.category.trim(),
        'barcode': draft.barcode.trim(),
        'unit_price_cents': draft.unitPriceCents,
        'unit_cost_cents': draft.unitCostCents,
        'icon_key': draft.iconKey ?? current.iconKey,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (draft.imageBytes != null) {
        updateValues['image_bytes'] = draft.imageBytes;
      } else if (draft.clearImage) {
        updateValues['image_bytes'] = null;
      }
      await txn.update(
        'products',
        updateValues,
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
    if (draft.iconKey != null && !productIconKeys.contains(draft.iconKey)) {
      throw ArgumentError.value(draft.iconKey, 'iconKey', 'Choose a built-in icon.');
    }
    if (draft.clearImage && draft.imageBytes != null) {
      throw ArgumentError('A product image cannot be both replaced and removed.');
    }
    if (draft.imageBytes != null &&
        (draft.imageBytes!.isEmpty ||
            draft.imageBytes!.length > productImageMaxBytes)) {
      throw ArgumentError(
        'Product images must contain data and be no larger than 512 KiB.',
      );
    }
  }

  Future<void> adjustStock(String productId, int delta) async {
    if (delta == 0) throw ArgumentError('Stock adjustment cannot be zero.');
    await _database.handle.transaction((txn) async {
      await _requireAccountingCurrency(txn);
      final rows = await txn.query(
        'products',
        columns: _productColumns,
        where: 'id = ?',
        whereArgs: [productId],
      );
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
      final now = DateTime.now();
      final value = product.unitCostCents * delta.abs();
      final entryId = 'stock_${now.microsecondsSinceEpoch}';
      await _insertStockMovement(
        txn,
        productId: product.id,
        productSku: product.sku,
        productName: product.name,
        movementType: 'adjustment',
        quantityDelta: delta,
        unitCostCents: product.unitCostCents,
        referenceId: value > 0 ? entryId : '',
        description: delta > 0 ? 'Restock · ${product.sku}' : 'Stock reduction · ${product.sku}',
        occurredAt: now,
      );
      if (value > 0) {
        await _insertTwoLineJournalEntry(
          txn,
          entryId: entryId,
          date: now,
          description: delta > 0 ? 'Restock · ${product.sku}' : 'Stock reduction · ${product.sku}',
          debitAccountId: delta > 0 ? 'inventory' : 'inventory-shrinkage',
          creditAccountId: delta > 0 ? 'cash' : 'inventory',
          amountCents: value,
        );
      }
    });
  }

  Future<void> _insertStockMovement(
    Transaction txn, {
    required String productId,
    required String productSku,
    required String productName,
    required String movementType,
    required int quantityDelta,
    required int unitCostCents,
    required String referenceId,
    required String description,
    required DateTime occurredAt,
  }) async {
    if (quantityDelta == 0) {
      throw ArgumentError('Stock movement quantity cannot be zero.');
    }
    final recordedAt = DateTime.now().toUtc().toIso8601String();
    await txn.insert('stock_movements', {
      'product_id': productId,
      'product_sku': productSku,
      'product_name': productName,
      'movement_type': movementType,
      'quantity_delta': quantityDelta,
      'unit_cost_cents': unitCostCents,
      'reference_id': referenceId,
      'description': description,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'recorded_at': recordedAt,
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
    if (draft.customerName.trim().isEmpty ||
        draft.lines.isEmpty ||
        draft.taxCents < 0 ||
        draft.discountCents < 0 ||
        draft.paymentAmountCents < 0) {
      throw ArgumentError(
        'Customer, invoice lines, tax, and payment amounts must be valid.',
      );
    }
    if (!_allowedPaymentMethods.contains(draft.paymentMethod)) {
      throw ArgumentError.value(
        draft.paymentMethod,
        'paymentMethod',
        'Use cash or bank_transfer.',
      );
    }

    await _database.handle.transaction((txn) async {
      await _requireAccountingCurrency(txn);
      const maxSignedInt = 0x7fffffffffffffff;
      final lines = <({Product product, int quantity, int lineTotal})>[];
      var subtotal = 0;
      var costTotal = 0;
      for (final line in draft.lines) {
        if (line.quantity <= 0) {
          throw ArgumentError('Invoice quantities must be positive.');
        }
        final rows = await txn.query(
          'products',
          columns: _productColumns,
          where: 'id = ?',
          whereArgs: [line.productId],
        );
        if (rows.isEmpty) {
          throw ArgumentError('An invoice product no longer exists.');
        }
        final product = Product.fromRow(rows.first);
        if (product.stockQuantity < line.quantity) {
          throw ArgumentError('Not enough stock for ' + product.name + '.');
        }
        if (line.expectedUnitPriceCents != null &&
            line.expectedUnitPriceCents != product.unitPriceCents) {
          throw StateError(
            'The price changed for ' + product.name + '. Review the cart before checkout.',
          );
        }
        if (product.unitPriceCents > maxSignedInt ~/ line.quantity ||
            product.unitCostCents > maxSignedInt ~/ line.quantity) {
          throw ArgumentError('Invoice line value exceeds the supported integer range.');
        }
        final lineTotal = product.unitPriceCents * line.quantity;
        final lineCost = product.unitCostCents * line.quantity;
        if (subtotal > maxSignedInt - lineTotal ||
            costTotal > maxSignedInt - lineCost) {
          throw ArgumentError('Invoice total exceeds the supported integer range.');
        }
        subtotal += lineTotal;
        costTotal += lineCost;
        lines.add((product: product, quantity: line.quantity, lineTotal: lineTotal));
      }
      if (subtotal <= 0) {
        throw ArgumentError('Invoice total must be greater than zero.');
      }
      if (draft.discountCents > subtotal) {
        throw ArgumentError('Discount cannot exceed the invoice subtotal.');
      }
      final discountedSubtotal = subtotal - draft.discountCents;
      if (draft.taxCents > maxSignedInt - discountedSubtotal) {
        throw ArgumentError('Invoice total exceeds the supported integer range.');
      }
      final total = discountedSubtotal + draft.taxCents;
      if (draft.paymentAmountCents == 0 && draft.additionalPayments.isNotEmpty) {
        throw ArgumentError('Additional tenders require an initial payment.');
      }
      final paymentParts = <InvoiceTenderDraft>[
        if (draft.paymentAmountCents > 0)
          InvoiceTenderDraft(
            amountCents: draft.paymentAmountCents,
            paymentMethod: draft.paymentMethod,
          ),
        ...draft.additionalPayments,
      ];
      var collectedPaymentCents = 0;
      for (final payment in paymentParts) {
        if (payment.amountCents <= 0 ||
            !_allowedPaymentMethods.contains(payment.paymentMethod)) {
          throw ArgumentError(
            'Payment tenders must have a positive amount and supported method.',
          );
        }
        if (collectedPaymentCents > maxSignedInt - payment.amountCents) {
          throw ArgumentError('Payment total exceeds the supported integer range.');
        }
        collectedPaymentCents += payment.amountCents;
      }
      if (collectedPaymentCents > total) {
        throw ArgumentError('Payment cannot exceed the invoice total.');
      }

      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS invoice_count FROM sales_invoices',
      );
      final nextNumber = (countRows.first['invoice_count']! as int) + 1;
      final invoiceNumber =
          'INV-' + draft.date.year.toString() + '-' + nextNumber.toString().padLeft(6, '0');
      final invoiceId =
          'invoice_' + DateTime.now().microsecondsSinceEpoch.toString();
      final createdAt = DateTime.now().toUtc().toIso8601String();

      await txn.insert('sales_invoices', {
        'id': invoiceId,
        'invoice_number': invoiceNumber,
        'customer_name': draft.customerName.trim(),
        'issue_date': _dateOnly(draft.date),
        'status': collectedPaymentCents == total ? 'paid' : 'issued',
        'subtotal_cents': subtotal,
        'tax_cents': draft.taxCents,
        'discount_cents': draft.discountCents,
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
        await _insertStockMovement(
          txn,
          productId: line.product.id,
          productSku: line.product.sku,
          productName: line.product.name,
          movementType: 'sale',
          quantityDelta: -line.quantity,
          unitCostCents: line.product.unitCostCents,
          referenceId: invoiceId,
          description: 'Invoice ' + invoiceNumber,
          occurredAt: draft.date,
        );
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
      if (draft.discountCents > 0) {
        await txn.insert('journal_lines', {
          'entry_id': journalId,
          'account_id': 'sales-income',
          'debit_cents': draft.discountCents,
          'credit_cents': 0,
        });
      }
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

      for (var index = 0; index < paymentParts.length; index++) {
        final payment = paymentParts[index];
        final paymentId = index == 0
            ? 'pos_payment_' + invoiceId
            : 'pos_payment_' + invoiceId + '_' + index.toString();
        await _insertTwoLineJournalEntry(
          txn,
          entryId: paymentId,
          date: draft.date,
          description: 'Invoice payment · ' + invoiceNumber + ' · ' + draft.customerName.trim(),
          debitAccountId:
              payment.paymentMethod == 'bank_transfer' ? 'bank' : 'cash',
          creditAccountId: 'receivables',
          amountCents: payment.amountCents,
        );
        await txn.insert('invoice_payments', {
          'id': paymentId,
          'invoice_id': invoiceId,
          'payment_date': _dateOnly(draft.date),
          'amount_cents': payment.amountCents,
          'payment_method': payment.paymentMethod,
          'journal_entry_id': paymentId,
          'created_at': createdAt,
        });
      }
    });
  }

  Future<void> recordInvoicePayment(InvoicePaymentDraft draft) async {
    if (draft.amountCents <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    if (!_allowedPaymentMethods.contains(draft.paymentMethod)) {
      throw ArgumentError.value(
        draft.paymentMethod,
        'paymentMethod',
        'Use cash or bank_transfer.',
      );
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
      if (invoice['returned_at'] != null) {
        throw ArgumentError('A returned invoice cannot receive a payment.');
      }
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
      final paymentId = 'payment_' + draft.invoiceId + '_' + newPaidCents.toString();
      final createdAt = DateTime.now().toUtc().toIso8601String();
      await _insertTwoLineJournalEntry(
        txn,
        entryId: paymentId,
        date: draft.date,
        description: 'Invoice payment ' +
            (invoice['invoice_number']! as String) +
            ' · ' +
            (invoice['customer_name']! as String),
        debitAccountId:
            draft.paymentMethod == 'bank_transfer' ? 'bank' : 'cash',
        creditAccountId: 'receivables',
        amountCents: draft.amountCents,
      );
      await txn.insert('invoice_payments', {
        'id': paymentId,
        'invoice_id': draft.invoiceId,
        'payment_date': _dateOnly(draft.date),
        'amount_cents': draft.amountCents,
        'payment_method': draft.paymentMethod,
        'journal_entry_id': paymentId,
        'created_at': createdAt,
      });
      final updated = await txn.update(
        'sales_invoices',
        {'status': newPaidCents == totalCents ? 'paid' : 'issued'},
        where: 'id = ? AND status != ? AND returned_at IS NULL',
        whereArgs: [draft.invoiceId, 'void'],
      );
      if (updated != 1) {
        throw StateError('The invoice status changed while recording payment.');
      }
    });
  }


  Future<void> returnInvoice(InvoiceReturnDraft draft) async {
    final invoiceId = draft.invoiceId.trim();
    final reason = draft.reason.trim();
    if (invoiceId.isEmpty || reason.isEmpty || reason.length > 500) {
      throw ArgumentError('A valid invoice and return reason are required.');
    }
    if (!_allowedPaymentMethods.contains(draft.refundMethod)) {
      throw ArgumentError.value(
        draft.refundMethod,
        'refundMethod',
        'Use cash or bank_transfer.',
      );
    }

    await _database.handle.transaction((txn) async {
      await _requireAccountingCurrency(txn);
      final invoiceRows = await txn.query(
        'sales_invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw ArgumentError('The invoice no longer exists.');
      }
      final invoice = invoiceRows.single;
      if (invoice['status'] == 'void') {
        throw ArgumentError('A void invoice cannot be returned.');
      }
      if (invoice['returned_at'] != null) {
        throw StateError('This invoice has already been returned.');
      }

      const maxSignedInt = 0x7fffffffffffffff;
      final subtotal = invoice['subtotal_cents']! as int;
      final discount = invoice['discount_cents'] as int? ?? 0;
      final tax = invoice['tax_cents']! as int;
      final total = invoice['total_cents']! as int;
      if (discount < 0 || discount > subtotal || tax < 0) {
        throw StateError('Invoice totals are inconsistent; the return was not posted.');
      }
      final netRevenueCents = subtotal - discount;
      if (tax > maxSignedInt - netRevenueCents ||
          total != netRevenueCents + tax) {
        throw StateError('Invoice totals are inconsistent; the return was not posted.');
      }

      final paymentRows = await txn.query(
        'invoice_payments',
        columns: ['amount_cents'],
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      var refundCents = 0;
      for (final row in paymentRows) {
        final amount = row['amount_cents']! as int;
        if (amount <= 0 || refundCents > maxSignedInt - amount) {
          throw StateError('Invoice payment history is invalid.');
        }
        refundCents += amount;
      }
      if (refundCents > total) {
        throw StateError('Recorded payments exceed the invoice total.');
      }
      final unpaidBalanceCents = total - refundCents;

      final invoiceLines = await txn.query(
        'invoice_lines',
        columns: [
          'product_id',
          'description',
          'quantity',
          'unit_cost_cents',
        ],
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'id ASC',
      );
      if (invoiceLines.isEmpty) {
        throw StateError('The invoice has no returnable inventory lines.');
      }

      final returnedLines =
          <({Product product, String description, int quantity, int unitCostCents})>[];
      var costTotal = 0;
      for (final line in invoiceLines) {
        final productId = line['product_id'] as String?;
        if (productId == null) {
          throw StateError('An invoice product was deleted and cannot be restocked.');
        }
        final productRows = await txn.query(
          'products',
          columns: _productColumns,
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (productRows.isEmpty) {
          throw StateError('An invoice product was deleted and cannot be restocked.');
        }
        final product = Product.fromRow(productRows.single);
        final quantity = line['quantity']! as int;
        final unitCostCents = line['unit_cost_cents']! as int;
        if (quantity <= 0 || unitCostCents < 0 ||
            quantity > maxSignedInt - product.stockQuantity ||
            unitCostCents > maxSignedInt ~/ quantity) {
          throw StateError('Invoice inventory values are invalid.');
        }
        final lineCost = unitCostCents * quantity;
        if (costTotal > maxSignedInt - lineCost) {
          throw StateError('Returned inventory value exceeds the supported range.');
        }
        costTotal += lineCost;
        returnedLines.add((
          product: product,
          description: line['description']! as String,
          quantity: quantity,
          unitCostCents: unitCostCents,
        ));
      }

      final returnId = 'return_' + invoiceId;
      final journalId = 'journal_' + returnId;
      final createdAt = DateTime.now().toUtc().toIso8601String();
      final hasJournalEntry = netRevenueCents > 0 ||
          tax > 0 ||
          refundCents > 0 ||
          unpaidBalanceCents > 0 ||
          costTotal > 0;

      if (hasJournalEntry) {
        await txn.insert('journal_entries', {
          'id': journalId,
          'entry_date': _dateOnly(draft.date),
          'description':
              'Sales return · ' + (invoice['invoice_number']! as String) + ' · ' + reason,
          'created_at': createdAt,
        });

        Future<void> insertLine({
          required String accountId,
          required int debitCents,
          required int creditCents,
        }) async {
          if (debitCents == 0 && creditCents == 0) return;
          await txn.insert('journal_lines', {
            'entry_id': journalId,
            'account_id': accountId,
            'debit_cents': debitCents,
            'credit_cents': creditCents,
          });
        }

        await insertLine(
          accountId: 'sales-income',
          debitCents: netRevenueCents,
          creditCents: 0,
        );
        await insertLine(
          accountId: 'tax-payable',
          debitCents: tax,
          creditCents: 0,
        );
        await insertLine(
          accountId: draft.refundMethod == 'bank_transfer' ? 'bank' : 'cash',
          debitCents: 0,
          creditCents: refundCents,
        );
        await insertLine(
          accountId: 'receivables',
          debitCents: 0,
          creditCents: unpaidBalanceCents,
        );
        await insertLine(
          accountId: 'inventory',
          debitCents: costTotal,
          creditCents: 0,
        );
        await insertLine(
          accountId: 'cost-of-goods',
          debitCents: 0,
          creditCents: costTotal,
        );
      }

      for (final line in returnedLines) {
        final updated = await txn.rawUpdate(
          'UPDATE products SET stock_quantity = stock_quantity + ? WHERE id = ?',
          [line.quantity, line.product.id],
        );
        if (updated != 1) {
          throw StateError('Product stock changed while returning the invoice.');
        }
        await _insertStockMovement(
          txn,
          productId: line.product.id,
          productSku: line.product.sku,
          productName: line.product.name,
          movementType: 'customer_return',
          quantityDelta: line.quantity,
          unitCostCents: line.unitCostCents,
          referenceId: returnId,
          description: 'Return of invoice ' +
              (invoice['invoice_number']! as String) +
              ' · ' +
              line.description,
          occurredAt: draft.date,
        );
      }

      await txn.insert('invoice_returns', {
        'id': returnId,
        'invoice_id': invoiceId,
        'return_date': _dateOnly(draft.date),
        'reason': reason,
        'refund_amount_cents': refundCents,
        'refund_method': draft.refundMethod,
        'journal_entry_id': hasJournalEntry ? journalId : null,
        'created_at': createdAt,
      });
      final updated = await txn.update(
        'sales_invoices',
        {'returned_at': _dateOnly(draft.date)},
        where: 'id = ? AND returned_at IS NULL AND status != ?',
        whereArgs: [invoiceId, 'void'],
      );
      if (updated != 1) {
        throw StateError('The invoice changed while returning it.');
      }
    });
  }


  /// Returns distinct customer names from recent invoices for POS quick selection.
  Future<List<String>> loadRecentInvoiceCustomers({int limit = 50}) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'Use a limit from 1 to 100.');
    }
    final rows = await _database.handle.rawQuery('''
      SELECT TRIM(customer_name) AS customer_name,
             MAX(issue_date) AS latest_issue_date,
             MAX(created_at) AS latest_created_at
      FROM sales_invoices
      WHERE TRIM(customer_name) != ''
      GROUP BY TRIM(customer_name)
      ORDER BY latest_issue_date DESC, latest_created_at DESC,
               customer_name COLLATE NOCASE ASC
      LIMIT ?
    ''', [limit]);
    return rows
        .map((row) => (row['customer_name'] as String).trim())
        .toList(growable: false);
  }

  Future<InvoicePaymentHistory?> loadInvoicePaymentHistory(
    String invoiceId,
  ) async {
    if (invoiceId.trim().isEmpty) {
      throw ArgumentError.value(invoiceId, 'invoiceId');
    }
    return _database.handle.transaction((txn) async {
      final invoiceRows = await txn.query(
        'sales_invoices',
        columns: [
          'id',
          'invoice_number',
          'customer_name',
          'status',
          'subtotal_cents',
          'tax_cents',
          'discount_cents',
          'total_cents',
          'returned_at',
        ],
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) return null;
      final invoice = invoiceRows.single;
      final paymentRows = await txn.query(
        'invoice_payments',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'payment_date ASC, created_at ASC, id ASC',
      );
      final payments = <InvoicePaymentRecord>[];
      for (final row in paymentRows) {
        payments.add(InvoicePaymentRecord(
          id: row['id']! as String,
          invoiceId: row['invoice_id']! as String,
          paymentDate: DateTime.parse(row['payment_date']! as String),
          amountCents: row['amount_cents']! as int,
          paymentMethod: row['payment_method']! as String,
          journalEntryId: row['journal_entry_id'] as String?,
          ledgerPostingMatches: await _paymentJournalPostingMatches(txn, row),
        ));
      }
      final returnRows = await txn.query(
        'invoice_returns',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      final returnRow = returnRows.isEmpty ? null : returnRows.single;
      final returnRecord = returnRow == null
          ? null
          : InvoiceReturnRecord(
              returnDate: DateTime.parse(returnRow['return_date']! as String),
              reason: returnRow['reason']! as String,
              refundAmountCents: returnRow['refund_amount_cents']! as int,
              refundMethod: returnRow['refund_method']! as String,
              journalEntryId: returnRow['journal_entry_id'] as String?,
              ledgerPostingMatches: await _returnJournalPostingMatches(
                txn,
                invoice,
                returnRow,
              ),
            );
      return InvoicePaymentHistory(
        invoiceId: invoice['id']! as String,
        invoiceNumber: invoice['invoice_number']! as String,
        customerName: invoice['customer_name']! as String,
        invoiceStatus: invoice['status']! as String,
        invoiceTotalCents: invoice['total_cents']! as int,
        payments: payments,
        returnRecordExpected: invoice['returned_at'] != null,
        returnRecord: returnRecord,
      );
    });
  }

  Future<bool> _returnJournalPostingMatches(
    DatabaseExecutor executor,
    Map<String, Object?> invoice,
    Map<String, Object?> returnRow,
  ) async {
    final invoiceId = invoice['id']! as String;
    final returnId = returnRow['id']! as String;
    final journalEntryId = returnRow['journal_entry_id'] as String?;
    if (returnId != 'return_' + invoiceId ||
        returnRow['invoice_id'] != invoiceId ||
        invoice['returned_at'] != returnRow['return_date']) {
      return false;
    }

    final subtotal = invoice['subtotal_cents']! as int;
    final discount = invoice['discount_cents'] as int? ?? 0;
    final tax = invoice['tax_cents']! as int;
    final total = invoice['total_cents']! as int;
    const maxSignedInt = 0x7fffffffffffffff;
    if (discount < 0 || discount > subtotal || tax < 0) return false;
    final netRevenue = subtotal - discount;
    if (tax > maxSignedInt - netRevenue ||
        total != netRevenue + tax) {
      return false;
    }

    final refund = returnRow['refund_amount_cents']! as int;
    final refundMethod = returnRow['refund_method']! as String;
    if (refund < 0 ||
        refund > total ||
        !_allowedPaymentMethods.contains(refundMethod)) {
      return false;
    }
    final unpaidBalance = total - refund;
    final refundAccount = refundMethod == 'bank_transfer' ? 'bank' : 'cash';

    final invoiceLines = await executor.query(
      'invoice_lines',
      columns: ['product_id', 'quantity', 'unit_cost_cents'],
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'id ASC',
    );
    if (invoiceLines.isEmpty) return false;
    var costTotal = 0;
    for (final line in invoiceLines) {
      final productId = line['product_id'] as String?;
      final quantity = line['quantity']! as int;
      final unitCost = line['unit_cost_cents']! as int;
      if (productId == null ||
          quantity <= 0 ||
          unitCost < 0 ||
          unitCost > maxSignedInt ~/ quantity) {
        return false;
      }
      final lineCost = unitCost * quantity;
      if (costTotal > maxSignedInt - lineCost) return false;
      costTotal += lineCost;
    }

    final movements = await executor.query(
      'stock_movements',
      where: 'reference_id = ?',
      whereArgs: [returnId],
      orderBy: 'id ASC',
    );
    if (movements.length != invoiceLines.length) return false;
    for (var index = 0; index < invoiceLines.length; index++) {
      final line = invoiceLines[index];
      final movement = movements[index];
      if (movement['movement_type'] != 'customer_return' ||
          movement['product_id'] != line['product_id'] ||
          movement['quantity_delta'] != line['quantity'] ||
          movement['unit_cost_cents'] != line['unit_cost_cents']) {
        return false;
      }
    }

    final expectedLines = <String, List<int>>{};
    void expectLine(String accountId, int debit, int credit) {
      if (debit > 0 || credit > 0) {
        expectedLines[accountId] = [debit, credit];
      }
    }

    expectLine('sales-income', netRevenue, 0);
    expectLine('tax-payable', tax, 0);
    expectLine(refundAccount, 0, refund);
    expectLine('receivables', 0, unpaidBalance);
    expectLine('inventory', costTotal, 0);
    expectLine('cost-of-goods', 0, costTotal);

    if (journalEntryId == null) {
      return expectedLines.isEmpty;
    }
    if (journalEntryId != 'journal_' + returnId) return false;
    final entryRows = await executor.query(
      'journal_entries',
      columns: ['entry_date'],
      where: 'id = ?',
      whereArgs: [journalEntryId],
      limit: 1,
    );
    if (entryRows.isEmpty ||
        entryRows.single['entry_date'] != returnRow['return_date']) {
      return false;
    }
    final lines = await executor.query(
      'journal_lines',
      where: 'entry_id = ?',
      whereArgs: [journalEntryId],
    );
    if (lines.length != expectedLines.length || lines.length < 2) {
      return false;
    }
    final actualLines = <String, List<int>>{};
    var debitTotal = 0;
    var creditTotal = 0;
    for (final line in lines) {
      final accountId = line['account_id']! as String;
      final debit = line['debit_cents']! as int;
      final credit = line['credit_cents']! as int;
      if (debit < 0 ||
          credit < 0 ||
          (debit == 0 && credit == 0) ||
          (debit > 0 && credit > 0) ||
          debitTotal > maxSignedInt - debit ||
          creditTotal > maxSignedInt - credit ||
          actualLines.containsKey(accountId)) {
        return false;
      }
      actualLines[accountId] = [debit, credit];
      debitTotal += debit;
      creditTotal += credit;
    }
    if (debitTotal != creditTotal) return false;
    for (final entry in expectedLines.entries) {
      final actual = actualLines[entry.key];
      if (actual == null ||
          actual[0] != entry.value[0] ||
          actual[1] != entry.value[1]) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _paymentJournalPostingMatches(
    DatabaseExecutor executor,
    Map<String, Object?> payment,
  ) async {
    final journalEntryId = payment['journal_entry_id'] as String?;
    if (journalEntryId == null || journalEntryId.isEmpty) return false;
    final entryRows = await executor.query(
      'journal_entries',
      columns: ['entry_date'],
      where: 'id = ?',
      whereArgs: [journalEntryId],
      limit: 1,
    );
    if (entryRows.isEmpty ||
        entryRows.single['entry_date'] != payment['payment_date']) {
      return false;
    }

    final amountCents = payment['amount_cents']! as int;
    final paymentMethod = payment['payment_method']! as String;
    final expectedCashAccount =
        paymentMethod == 'bank_transfer' ? 'bank' : 'cash';
    final lines = await executor.query(
      'journal_lines',
      where: 'entry_id = ?',
      whereArgs: [journalEntryId],
    );
    if (lines.length != 2) return false;

    var debitMatches = false;
    var receivableMatches = false;
    for (final line in lines) {
      final accountId = line['account_id']! as String;
      final debitCents = line['debit_cents']! as int;
      final creditCents = line['credit_cents']! as int;
      if (accountId == expectedCashAccount &&
          debitCents == amountCents &&
          creditCents == 0) {
        debitMatches = true;
      } else if (accountId == 'receivables' &&
          debitCents == 0 &&
          creditCents == amountCents) {
        receivableMatches = true;
      } else {
        return false;
      }
    }
    return debitMatches && receivableMatches;
  }

  int _parseDefaultTaxRateBasisPoints(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed != null && parsed >= 0 && parsed <= 10000 ? parsed : 0;
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
      defaultTaxRateBasisPoints: _parseDefaultTaxRateBasisPoints(values['default_tax_rate_basis_points']),
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
    if (settings.defaultTaxRateBasisPoints < 0 ||
        settings.defaultTaxRateBasisPoints > 10000) {
      throw ArgumentError.value(
        settings.defaultTaxRateBasisPoints,
        'defaultTaxRateBasisPoints',
        'Tax rate must be between 0 and 100 percent.',
      );
    }
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
      await txn.insert('app_settings',
        {'setting_key': 'default_tax_rate_basis_points', 'setting_value': '${settings.defaultTaxRateBasisPoints}'},
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
    if (!allowLegacySchema) {
      requiredTables
        ..add('invoice_payments')
        ..add('invoice_returns');
    }
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
