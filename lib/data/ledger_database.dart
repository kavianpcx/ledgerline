import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LedgerDatabase {
  LedgerDatabase._(this._database, this.path);

  final Database _database;
  final String path;

  Database get handle => _database;

  static Future<LedgerDatabase> open(String path) async {
    final database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 11,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    return LedgerDatabase._(database, path);
  }

  static Future<LedgerDatabase> openInMemory() async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 11,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
      ),
    );
    return LedgerDatabase._(database, inMemoryDatabasePath);
  }

  Future<void> close() => _database.close();

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('asset', 'liability', 'equity', 'income', 'expense')),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
      )
    ''');
    await db.execute('''
      CREATE TABLE journal_entries (
        id TEXT PRIMARY KEY,
        entry_date TEXT NOT NULL,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE journal_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id TEXT NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
        account_id TEXT NOT NULL REFERENCES accounts(id),
        debit_cents INTEGER NOT NULL DEFAULT 0 CHECK (debit_cents >= 0),
        credit_cents INTEGER NOT NULL DEFAULT 0 CHECK (credit_cents >= 0),
        CHECK ((debit_cents > 0 AND credit_cents = 0) OR
               (credit_cents > 0 AND debit_cents = 0))
      )
    ''');
    await db.execute(
      'CREATE INDEX journal_entries_by_date ON journal_entries(entry_date DESC)',
    );
    await db.execute(
      'CREATE INDEX journal_lines_by_account ON journal_lines(account_id)',
    );
    await _createProductInvoiceAndSettingsTables(db);
    await _createInvoicePaymentsTable(db);
    await _createInvoiceReturnsTable(db);
    await _createInvoicePartialReturnsTables(db);
    await _upgradeProductsToV4(db);
    await _upgradeProductsToV10(db);
    await _createStockMovementsTable(db);
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createProductInvoiceAndSettingsTables(db);
    }
    if (oldVersion < 3) {
      await _createInvoicePaymentsTable(db);
    }
    if (oldVersion < 4) {
      await _upgradeProductsToV4(db);
    }
    if (oldVersion < 5) {
      await _createStockMovementsTable(db, seedCurrentBalances: true);
    }
    if (oldVersion < 6) {
      await _upgradeInvoicePaymentsToV6(db);
    }
    if (oldVersion < 7) {
      await _upgradeInvoicePaymentsToV7(db);
    }
    if (oldVersion < 8) {
      await _upgradeSalesInvoicesToV8(db);
    }
    if (oldVersion < 9) {
      await _upgradeInvoiceReturnsToV9(db);
    }
    if (oldVersion < 10) {
      await _upgradeProductsToV10(db);
    }
    if (oldVersion < 11) {
      await _createInvoicePartialReturnsTables(db);
    }
  }


  static Future<void> _upgradeInvoiceReturnsToV9(Database db) async {
    final invoiceTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sales_invoices'",
    );
    if (invoiceTables.isNotEmpty) {
      final columns = await db.rawQuery('PRAGMA table_info(sales_invoices)');
      if (!columns.any((row) => row['name'] == 'returned_at')) {
        await db.execute(
          'ALTER TABLE sales_invoices ADD COLUMN returned_at TEXT',
        );
      }
      await _createInvoiceReturnsTable(db);
    }

    final movementTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'stock_movements'",
    );
    if (movementTables.isEmpty) {
      await _createStockMovementsTable(db);
      return;
    }
    await db.execute('DROP TRIGGER IF EXISTS stock_movements_reject_update');
    await db.execute('DROP TRIGGER IF EXISTS stock_movements_reject_delete');
    await db.execute(
      'ALTER TABLE stock_movements RENAME TO stock_movements_v8',
    );
    await _createStockMovementsTable(db);
    await db.execute('''
      INSERT INTO stock_movements (
        id, product_id, product_sku, product_name, movement_type,
        quantity_delta, unit_cost_cents, reference_id, description,
        occurred_at, recorded_at
      )
      SELECT
        id, product_id, product_sku, product_name, movement_type,
        quantity_delta, unit_cost_cents, reference_id, description,
        occurred_at, recorded_at
      FROM stock_movements_v8
    ''');
    await db.execute('DROP TABLE stock_movements_v8');
    await _createStockMovementsTable(db);
  }

  static Future<void> _upgradeSalesInvoicesToV8(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sales_invoices'",
    );
    if (tables.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info(sales_invoices)');
    if (!columns.any((row) => row['name'] == 'discount_cents')) {
      await db.execute(
        'ALTER TABLE sales_invoices ADD COLUMN discount_cents INTEGER NOT NULL DEFAULT 0 CHECK (discount_cents >= 0 AND discount_cents <= subtotal_cents)',
      );
    }
  }

  static Future<void> _upgradeInvoicePaymentsToV6(Database db) async {
    final paymentTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'invoice_payments'",
    );
    if (paymentTables.isEmpty) {
      final invoiceTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sales_invoices'",
      );
      if (invoiceTables.isEmpty) return;
      await _createInvoicePaymentsTable(db);
      return;
    }

    final columns = await db.rawQuery('PRAGMA table_info(invoice_payments)');
    if (!columns.any((row) => row['name'] == 'payment_method')) {
      await db.execute(
        "ALTER TABLE invoice_payments ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash', 'bank_transfer'))",
      );
    }
  }

  static Future<void> _upgradeInvoicePaymentsToV7(Database db) async {
    final paymentTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'invoice_payments'",
    );
    if (paymentTables.isEmpty) {
      final invoiceTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sales_invoices'",
      );
      if (invoiceTables.isEmpty) return;
      await _createInvoicePaymentsTable(db);
    }

    final columns = await db.rawQuery('PRAGMA table_info(invoice_payments)');
    if (!columns.any((row) => row['name'] == 'journal_entry_id')) {
      await db.execute(
        'ALTER TABLE invoice_payments ADD COLUMN journal_entry_id TEXT REFERENCES journal_entries(id) ON DELETE SET NULL',
      );
    }

    await db.execute('''
      UPDATE invoice_payments
      SET journal_entry_id = id
      WHERE journal_entry_id IS NULL
        AND EXISTS (SELECT 1 FROM journal_entries WHERE journal_entries.id = invoice_payments.id)
    ''');

    final unlinkedPayments = await db.rawQuery('''
      SELECT p.id, p.payment_date, p.amount_cents, p.payment_method,
             i.invoice_number, i.customer_name
      FROM invoice_payments p
      JOIN sales_invoices i ON i.id = p.invoice_id
      WHERE p.journal_entry_id IS NULL
      ORDER BY p.payment_date ASC, p.created_at ASC, p.id ASC
    ''');
    for (final payment in unlinkedPayments) {
      final amountCents = payment['amount_cents']! as int;
      final paymentDate = payment['payment_date']! as String;
      final method = payment['payment_method']! as String;
      final debitAccount = method == 'bank_transfer' ? 'bank' : 'cash';
      final description = 'Invoice payment ' +
          (payment['invoice_number']! as String) +
          ' · ' +
          (payment['customer_name']! as String);
      final matches = await db.rawQuery('''
        SELECT e.id
        FROM journal_entries e
        JOIN journal_lines debit_line
          ON debit_line.entry_id = e.id
         AND debit_line.account_id = ?
         AND debit_line.debit_cents = ?
         AND debit_line.credit_cents = 0
        JOIN journal_lines credit_line
          ON credit_line.entry_id = e.id
         AND credit_line.account_id = 'receivables'
         AND credit_line.debit_cents = 0
         AND credit_line.credit_cents = ?
        WHERE e.entry_date = ?
          AND e.description = ?
          AND (SELECT COUNT(*) FROM journal_lines lines WHERE lines.entry_id = e.id) = 2
          AND NOT EXISTS (
            SELECT 1 FROM invoice_payments linked
            WHERE linked.journal_entry_id = e.id
          )
        ORDER BY e.created_at ASC, e.id ASC
        LIMIT 1
      ''', [debitAccount, amountCents, amountCents, paymentDate, description]);
      if (matches.isNotEmpty) {
        await db.update(
          'invoice_payments',
          {'journal_entry_id': matches.single['id']! as String},
          where: 'id = ? AND journal_entry_id IS NULL',
          whereArgs: [payment['id']],
        );
      }
    }

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS invoice_payments_by_journal_entry ON invoice_payments(journal_entry_id) WHERE journal_entry_id IS NOT NULL',
    );
  }

  static Future<void> _upgradeProductsToV10(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'products'",
    );
    if (tables.isEmpty) return;
    final columnRows = await db.rawQuery('PRAGMA table_info(products)');
    final columns = {
      for (final row in columnRows) row['name']! as String,
    };
    if (!columns.contains('icon_key')) {
      await db.execute("""
        ALTER TABLE products ADD COLUMN icon_key TEXT NOT NULL DEFAULT 'inventory'
          CHECK (icon_key IN (
            'inventory', 'shopping_bag', 'restaurant', 'beverage',
            'electronics', 'medicine', 'tools', 'book'
          ))
      """);
    }
    if (!columns.contains('image_bytes')) {
      await db.execute('''
        ALTER TABLE products ADD COLUMN image_bytes BLOB
          CHECK (image_bytes IS NULL OR (length(image_bytes) > 0 AND length(image_bytes) <= 524288))
      ''');
    }
  }

  static Future<void> _upgradeProductsToV4(Database db) async {
    final columnRows = await db.rawQuery('PRAGMA table_info(products)');
    final columns = {
      for (final row in columnRows) row['name']! as String,
    };
    if (!columns.contains('description')) {
      await db.execute("ALTER TABLE products ADD COLUMN description TEXT NOT NULL DEFAULT ''");
    }
    if (!columns.contains('category')) {
      await db.execute("ALTER TABLE products ADD COLUMN category TEXT NOT NULL DEFAULT ''");
    }
    if (!columns.contains('barcode')) {
      await db.execute("ALTER TABLE products ADD COLUMN barcode TEXT NOT NULL DEFAULT ''");
    }
    if (!columns.contains('updated_at')) {
      await db.execute("ALTER TABLE products ADD COLUMN updated_at TEXT NOT NULL DEFAULT ''");
    }
    await db.execute(
      "UPDATE products SET updated_at = created_at WHERE updated_at = ''",
    );

    final indexRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'products'",
    );
    final indexes = {
      for (final row in indexRows) row['name']! as String,
    };
    if (!indexes.contains('products_by_name')) {
      await db.execute(
        'CREATE INDEX products_by_name ON products(name COLLATE NOCASE, id)',
      );
    }
    if (!indexes.contains('products_by_category')) {
      await db.execute(
        'CREATE INDEX products_by_category ON products(category COLLATE NOCASE, id)',
      );
    }
    if (!indexes.contains('products_by_barcode')) {
      await db.execute(
        "CREATE UNIQUE INDEX products_by_barcode ON products(barcode) WHERE barcode <> ''",
      );
    }
  }

  static Future<void> _createInvoiceReturnsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_returns (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL UNIQUE REFERENCES sales_invoices(id),
        return_date TEXT NOT NULL,
        reason TEXT NOT NULL,
        refund_amount_cents INTEGER NOT NULL CHECK (refund_amount_cents >= 0),
        refund_method TEXT NOT NULL CHECK (refund_method IN ('cash', 'bank_transfer')),
        journal_entry_id TEXT UNIQUE REFERENCES journal_entries(id),
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS invoice_returns_by_date ON invoice_returns(return_date DESC)',
    );
  }

  static Future<void> _createInvoicePartialReturnsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_partial_returns (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL REFERENCES sales_invoices(id),
        return_date TEXT NOT NULL,
        reason TEXT NOT NULL,
        net_revenue_cents INTEGER NOT NULL CHECK (net_revenue_cents >= 0),
        tax_cents INTEGER NOT NULL CHECK (tax_cents >= 0),
        return_value_cents INTEGER NOT NULL CHECK (
          return_value_cents >= 0 AND
          return_value_cents = net_revenue_cents + tax_cents
        ),
        refund_amount_cents INTEGER NOT NULL CHECK (refund_amount_cents >= 0),
        receivable_credit_cents INTEGER NOT NULL CHECK (receivable_credit_cents >= 0),
        refund_method TEXT NOT NULL CHECK (refund_method IN ('cash', 'bank_transfer')),
        journal_entry_id TEXT UNIQUE REFERENCES journal_entries(id),
        created_at TEXT NOT NULL,
        CHECK (return_value_cents = refund_amount_cents + receivable_credit_cents)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS invoice_partial_returns_by_invoice_date '
      'ON invoice_partial_returns(invoice_id, return_date DESC, id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_partial_return_lines (
        return_id TEXT NOT NULL REFERENCES invoice_partial_returns(id) ON DELETE CASCADE,
        invoice_line_id INTEGER NOT NULL REFERENCES invoice_lines(id) ON DELETE RESTRICT,
        product_id TEXT NOT NULL,
        product_sku TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        net_revenue_cents INTEGER NOT NULL CHECK (net_revenue_cents >= 0),
        tax_cents INTEGER NOT NULL CHECK (tax_cents >= 0),
        line_value_cents INTEGER NOT NULL CHECK (
          line_value_cents >= 0 AND
          line_value_cents = net_revenue_cents + tax_cents
        ),
        unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0),
        cost_total_cents INTEGER NOT NULL CHECK (cost_total_cents >= 0),
        PRIMARY KEY (return_id, invoice_line_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS invoice_partial_return_lines_by_invoice_line '
      'ON invoice_partial_return_lines(invoice_line_id, return_id)',
    );
  }

  static Future<void> _createStockMovementsTable(
    Database db, {
    bool seedCurrentBalances = false,
  }) async {
    final existingTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'stock_movements'",
    );
    final tableAlreadyExisted = existingTables.isNotEmpty;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id TEXT NOT NULL,
        product_sku TEXT NOT NULL,
        product_name TEXT NOT NULL,
        movement_type TEXT NOT NULL CHECK (
          movement_type IN (
            'opening_balance',
            'adjustment',
            'sale',
            'migration_balance',
            'customer_return'
          )
        ),
        quantity_delta INTEGER NOT NULL CHECK (quantity_delta <> 0),
        unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0),
        reference_id TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        recorded_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS stock_movements_by_product ON stock_movements(product_id, recorded_at DESC, id DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS stock_movements_by_reference ON stock_movements(reference_id)',
    );
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS stock_movements_reject_update
      BEFORE UPDATE ON stock_movements
      BEGIN
        SELECT RAISE(ABORT, 'stock movements are append-only');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS stock_movements_reject_delete
      BEFORE DELETE ON stock_movements
      BEGIN
        SELECT RAISE(ABORT, 'stock movements are append-only');
      END
    ''');

    if (!seedCurrentBalances || tableAlreadyExisted) return;
    await db.execute('''
      INSERT INTO stock_movements (
        product_id, product_sku, product_name, movement_type,
        quantity_delta, unit_cost_cents, reference_id, description,
        occurred_at, recorded_at
      )
      SELECT
        id,
        sku,
        name,
        'migration_balance',
        stock_quantity,
        unit_cost_cents,
        '',
        'Balance brought forward when stock history was introduced',
        strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
        strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
      FROM products
      WHERE stock_quantity > 0
    ''');
  }

  static Future<void> _createProductInvoiceAndSettingsTables(Database db) async {
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        sku TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0),
        unit_cost_cents INTEGER NOT NULL DEFAULT 0 CHECK (unit_cost_cents >= 0),
        stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
        icon_key TEXT NOT NULL DEFAULT 'inventory' CHECK (
          icon_key IN (
            'inventory', 'shopping_bag', 'restaurant', 'beverage',
            'electronics', 'medicine', 'tools', 'book'
          )
        ),
        image_bytes BLOB CHECK (
          image_bytes IS NULL OR (length(image_bytes) > 0 AND length(image_bytes) <= 524288)
        ),
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sales_invoices (
        id TEXT PRIMARY KEY,
        invoice_number TEXT NOT NULL UNIQUE,
        customer_name TEXT NOT NULL,
        issue_date TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('issued', 'paid', 'void')),
        subtotal_cents INTEGER NOT NULL CHECK (subtotal_cents >= 0),
        tax_cents INTEGER NOT NULL CHECK (tax_cents >= 0),
        discount_cents INTEGER NOT NULL DEFAULT 0 CHECK (discount_cents >= 0 AND discount_cents <= subtotal_cents),
        total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
        returned_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE invoice_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id TEXT NOT NULL REFERENCES sales_invoices(id) ON DELETE CASCADE,
        product_id TEXT REFERENCES products(id) ON DELETE SET NULL,
        description TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0),
        unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0),
        line_total_cents INTEGER NOT NULL CHECK (line_total_cents >= 0)
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX invoices_by_date ON sales_invoices(issue_date DESC)',
    );
  }
  
  static Future<void> _createInvoicePaymentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE invoice_payments (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL REFERENCES sales_invoices(id) ON DELETE CASCADE,
        payment_date TEXT NOT NULL,
        amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
        payment_method TEXT NOT NULL DEFAULT 'cash'
          CHECK (payment_method IN ('cash', 'bank_transfer')),
        journal_entry_id TEXT REFERENCES journal_entries(id) ON DELETE SET NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX invoice_payments_by_invoice ON invoice_payments(invoice_id, payment_date DESC)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX invoice_payments_by_journal_entry ON invoice_payments(journal_entry_id) WHERE journal_entry_id IS NOT NULL',
    );
    await db.execute('''
      INSERT INTO invoice_payments (
        id, invoice_id, payment_date, amount_cents, created_at
      )
      SELECT 'legacy-paid-' || id, id, issue_date, total_cents, created_at
      FROM sales_invoices
      WHERE status = 'paid' AND total_cents > 0
    ''');
  }

}
