import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/data/ledger_database.dart';
import 'package:ledgerline/data/ledger_repository.dart';
import 'package:ledgerline/domain/product.dart';
import 'package:ledgerline/domain/product_csv_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses quoted CSV fields, embedded newlines, and exact minor units', () {
    final result = ProductCsvImport.parse(
      'SKU,Product Name,Category,Barcode,Selling Price,Unit Cost,Stock,Description\r\n'
      'COF-1,"Coffee, dark",Drinks,123456,12.34,6.10,5,"Roast\nblend"',
      currencyCode: 'USD',
    );

    expect(result.validCount, 1);
    expect(result.rows.single.lineNumber, 2);
    expect(result.rows.single.draft!.name, 'Coffee, dark');
    expect(result.rows.single.draft!.description, 'Roast\nblend');
    expect(result.rows.single.draft!.unitPriceCents, 1234);
    expect(result.rows.single.draft!.unitCostCents, 610);
    expect(result.rows.single.draft!.stockQuantity, 5);
  });

  test('detects semicolon CSV and Persian headings and digits', () {
    final result = ProductCsvImport.parse(
      'شناسه کالا;نام کالا;قیمت فروش;بهای واحد;موجودی\r\n'
      'IR-01;دفتر;۱۲۵۰;;۳',
      currencyCode: 'TOMAN',
    );

    expect(result.validCount, 1);
    final draft = result.validDrafts.single;
    expect(draft.sku, 'IR-01');
    expect(draft.name, 'دفتر');
    expect(draft.unitPriceCents, 1250);
    expect(draft.unitCostCents, 0);
    expect(draft.stockQuantity, 3);
  });

  test('requires recognized mandatory columns and rejects malformed quotes', () {
    expect(
      () => ProductCsvImport.parse(
        'Item,Amount\nTea,2.00',
        currencyCode: 'USD',
      ),
      throwsFormatException,
    );
    expect(
      () => ProductCsvImport.parse(
        'SKU,Product Name,Selling Price\nA,"Unclosed,2.00\n',
        currencyCode: 'USD',
      ),
      throwsFormatException,
    );
  });

  test('marks duplicate SKUs and barcodes before the user confirms import', () {
    final result = ProductCsvImport.parse(
      'SKU,Product Name,Selling Price,Barcode\n'
      'A,First,2.00,123\n'
      'A,Second,3.00,456\n'
      'B,Third,4.00,123',
      currencyCode: 'USD',
    );

    expect(result.rows, hasLength(3));
    expect(result.invalidCount, 3);
    expect(result.rows.every((row) => row.issue != null), isTrue);
  });

  test('parses a 10,000-row product catalog without building UI-sized lists', () {
    final buffer = StringBuffer('SKU,Product Name,Selling Price,Unit Cost,Stock\n');
    for (var index = 0; index < 10000; index++) {
      buffer.write('SKU-' + index.toString() + ',Product ' + index.toString() + ',1.25,0,0\n');
    }

    final result = ProductCsvImport.parse(buffer.toString(), currencyCode: 'USD');
    expect(result.validCount, 10000);
    expect(result.rows.length, 10000);
    expect(result.validDrafts.last.sku, 'SKU-9999');
  });

  test('imports products and opening inventory atomically with balanced journals', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );

    final drafts = [
      const ProductDraft(
        sku: 'TEA-1',
        name: 'Tea tin',
        unitPriceCents: 2500,
        unitCostCents: 500,
        stockQuantity: 2,
        category: 'Tea',
      ),
      const ProductDraft(
        sku: 'MUG-2',
        name: 'Travel mug',
        unitPriceCents: 1500,
        unitCostCents: 250,
        stockQuantity: 1,
        barcode: '8710001234567',
      ),
    ];
    expect(await repository.findProductImportConflicts(drafts), isEmpty);
    expect(await repository.importProducts(drafts), 2);

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.products, hasLength(2));
    expect(snapshot.entries, hasLength(2));
    final stockMovements = await database.handle.query('stock_movements');
    expect(stockMovements, hasLength(2));
    expect(
      stockMovements.map((movement) => movement['movement_type']).toSet(),
      {'opening_balance'},
    );
    expect(
      stockMovements.fold<int>(
        0,
        (total, movement) => total + (movement['quantity_delta']! as int),
      ),
      3,
    );
    expect(snapshot.assetsCents, 1250);
    expect(snapshot.equityCents, 1250);
    expect(
      snapshot.assetsCents,
      snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents,
    );

    final conflict = await repository.findProductImportConflicts([
      const ProductDraft(
        sku: 'TEA-1',
        name: 'Duplicate',
        unitPriceCents: 100,
        unitCostCents: 0,
        stockQuantity: 0,
      ),
    ]);
    expect(conflict, contains('sku:TEA-1'));

    await expectLater(
      repository.importProducts([
        const ProductDraft(
          sku: 'NEW-3',
          name: 'Should roll back',
          unitPriceCents: 1000,
          unitCostCents: 200,
          stockQuantity: 1,
        ),
        const ProductDraft(
          sku: 'TEA-1',
          name: 'Duplicate',
          unitPriceCents: 100,
          unitCostCents: 0,
          stockQuantity: 0,
        ),
      ]),
      throwsArgumentError,
    );
    expect((await repository.loadProducts()).length, 2);
    expect((await repository.loadSnapshot()).entries.length, 2);
  });
}
