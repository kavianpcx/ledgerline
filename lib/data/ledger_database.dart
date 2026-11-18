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
        version: 5,
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
        version: 5,
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
    await _upgradeProductsToV4(db);
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
            'migration_balance'
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
        total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
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
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX invoice_payments_by_invoice ON invoice_payments(invoice_id, payment_date DESC)',
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
