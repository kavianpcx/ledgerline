import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:ledgerline/data/ledger_database.dart';
import 'package:ledgerline/data/ledger_repository.dart';
import 'package:ledgerline/domain/product.dart';
import 'package:ledgerline/domain/sales_invoice.dart';
import 'package:ledgerline/presentation/pos_page.dart';

const _coffee = Product(
  id: 'product_coffee',
  sku: 'COF-01',
  name: 'Coffee tin',
  unitPriceCents: 1000,
  unitCostCents: 400,
  stockQuantity: 5,
  category: 'Coffee',
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: 'The POS checkout did not reach the expected state.');
}

Future<LedgerRepository> _createRepository() async {
  final database = await LedgerDatabase.openInMemory();
  final repository = LedgerRepository(database);
  await repository.initialize();
  await repository.configureAccountingCurrency(
    currencyCode: 'USD',
    confirmExistingAmounts: true,
  );
  return repository;
}

Future<void> _addTestProduct(LedgerRepository repository) =>
    repository.createProduct(const ProductDraft(
      sku: 'COF-01',
      name: 'Coffee tin',
      unitPriceCents: 1000,
      unitCostCents: 400,
      stockQuantity: 5,
      category: 'Coffee',
    ));

Future<_FakePosRepository> _createWidgetRepository(WidgetTester tester) async {
  final database = (await tester.runAsync(LedgerDatabase.openInMemory))!;
  return _FakePosRepository(database);
}

Future<void> _mountPos(
  WidgetTester tester,
  LedgerRepository repository,
  Map<String, PosCartLine> cart, {
  required Future<void> Function() onCompleted,
  required ValueChanged<Map<String, PosCartLine>> onCartChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PointOfSalePage(
            repository: repository,
            currencyCode: 'USD',
            beforeCheckout: () => true,
            onCheckoutCompleted: onCompleted,
            initialCart: cart,
            onCartChanged: onCartChanged,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cash checkout submits the selected cart and full payment',
      (tester) async {
    final repository = await _createWidgetRepository(tester);
    addTearDown(() async {
      await tester.runAsync(repository.close);
    });

    var refreshCount = 0;
    final savedCart = <String, PosCartLine>{};
    await _mountPos(
      tester,
      repository,
      savedCart,
      onCompleted: () async {
        refreshCount++;
      },
      onCartChanged: (cart) {
        savedCart
          ..clear()
          ..addAll(cart);
      },
    );

    final productTile = find.byKey(const ValueKey('pos-product-COF-01'));
    await tester.tap(productTile);
    await tester.pumpAndSettle();
    await tester.tap(productTile);
    await tester.pumpAndSettle();
    expect(savedCart.values.single.quantity, 2);

    await tester.ensureVisible(find.byKey(const Key('pos-checkout')));
    await tester.tap(find.byKey(const Key('pos-checkout')));
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('pos-submit-checkout')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await _pumpUntil(tester, () => refreshCount == 1);

    expect(repository.invoiceDrafts, hasLength(1));
    final draft = repository.invoiceDrafts.single;
    expect(draft.customerName, 'Walk-in customer');
    expect(draft.paymentAmountCents, 2000);
    expect(draft.lines.single.quantity, 2);
    expect(draft.lines.single.productId, _coffee.id);
    expect(draft.lines.single.expectedUnitPriceCents, 1000);
    expect(savedCart, isEmpty);
  });

  testWidgets('bank transfer checkout records the selected payment method',
      (tester) async {
    final repository = await _createWidgetRepository(tester);
    addTearDown(() async {
      await tester.runAsync(repository.close);
    });

    var refreshCount = 0;
    await _mountPos(
      tester,
      repository,
      const {},
      onCompleted: () async {
        refreshCount++;
      },
      onCartChanged: (_) {},
    );

    await tester.tap(find.byKey(const ValueKey('pos-product-COF-01')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pos-checkout')));
    await tester.tap(find.byKey(const Key('pos-checkout')));
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('pos-submit-checkout')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const Key('pos-payment-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank transfer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await _pumpUntil(tester, () => refreshCount == 1);

    expect(repository.invoiceDrafts, hasLength(1));
    expect(repository.invoiceDrafts.single.paymentAmountCents, 1000);
    expect(repository.invoiceDrafts.single.paymentMethod, 'bank_transfer');
  });

  testWidgets('unpaid checkout creates an on-account invoice draft',
      (tester) async {
    final repository = await _createWidgetRepository(tester);
    addTearDown(() async {
      await tester.runAsync(repository.close);
    });

    var refreshCount = 0;
    await _mountPos(
      tester,
      repository,
      const {},
      onCompleted: () async {
        refreshCount++;
      },
      onCartChanged: (_) {},
    );

    await tester.tap(find.byKey(const ValueKey('pos-product-COF-01')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pos-checkout')));
    await tester.tap(find.byKey(const Key('pos-checkout')));
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('pos-submit-checkout')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const Key('pos-collect-payment-now')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await _pumpUntil(tester, () => refreshCount == 1);

    expect(repository.invoiceDrafts, hasLength(1));
    expect(repository.invoiceDrafts.single.paymentAmountCents, 0);
    expect(repository.invoiceDrafts.single.lines.single.quantity, 1);
  });

  testWidgets('clearing the cart updates the app shell cart snapshot',
      (tester) async {
    final repository = await _createWidgetRepository(tester);
    addTearDown(() async {
      await tester.runAsync(repository.close);
    });

    final savedCart = <String, PosCartLine>{};
    await _mountPos(
      tester,
      repository,
      savedCart,
      onCompleted: () async {},
      onCartChanged: (cart) {
        savedCart
          ..clear()
          ..addAll(cart);
      },
    );

    await tester.tap(find.byKey(const ValueKey('pos-product-COF-01')));
    await tester.pumpAndSettle();
    expect(savedCart, hasLength(1));

    await tester.ensureVisible(find.byKey(const Key('pos-clear-cart')));
    await tester.tap(find.byKey(const Key('pos-clear-cart')));
    await tester.pumpAndSettle();

    expect(savedCart, isEmpty);
  });

  test('cash checkout posts invoice, payment, stock, and balanced journals',
      () async {
    final repository = await _createRepository();
    addTearDown(repository.close);
    await _addTestProduct(repository);
    final product = (await repository.loadProducts()).single;

    await repository.createInvoice(InvoiceDraft(
      customerName: 'Walk-in customer',
      date: DateTime(2026, 11, 18),
      lines: [
        InvoiceLineDraft(
          productId: product.id,
          quantity: 2,
          expectedUnitPriceCents: 1000,
        ),
      ],
      paymentAmountCents: 2000,
    ));

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.invoices, hasLength(1));
    expect(snapshot.invoices.single.status, 'paid');
    expect(snapshot.invoices.single.paidCents, 2000);
    expect(snapshot.products.single.stockQuantity, 3);
    expect(snapshot.assetsCents, 3200);
    expect(snapshot.netIncomeCents, 1200);
    expect(
      snapshot.assetsCents,
      snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents,
    );
    expect(snapshot.entries, hasLength(3));
  });

  test('bank transfer checkout posts to the bank account and records its method',
      () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await _addTestProduct(repository);
    final product = (await repository.loadProducts()).single;

    await repository.createInvoice(InvoiceDraft(
      customerName: 'Walk-in customer',
      date: DateTime(2026, 11, 18),
      lines: [InvoiceLineDraft(productId: product.id, quantity: 1)],
      paymentAmountCents: 1000,
      paymentMethod: 'bank_transfer',
    ));

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.invoices.single.status, 'paid');
    expect(snapshot.balancesByAccount['bank'], 1000);
    expect(snapshot.balancesByAccount['cash'], 0);
    final payments = await database.handle.query('invoice_payments');
    expect(payments.single['payment_method'], 'bank_transfer');
  });

  test('on-account invoice can be settled separately', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await _addTestProduct(repository);
    final product = (await repository.loadProducts()).single;

    await repository.createInvoice(InvoiceDraft(
      customerName: 'Walk-in customer',
      date: DateTime(2026, 11, 18),
      lines: [InvoiceLineDraft(productId: product.id, quantity: 1)],
    ));

    var invoice = (await repository.loadSnapshot()).invoices.single;
    expect(invoice.status, 'issued');
    expect(invoice.paidCents, 0);
    expect(invoice.balanceDueCents, 1000);

    await repository.recordInvoicePayment(InvoicePaymentDraft(
      invoiceId: invoice.id,
      amountCents: invoice.balanceDueCents,
      date: DateTime(2026, 11, 18),
      paymentMethod: 'bank_transfer',
    ));
    final snapshot = await repository.loadSnapshot();
    expect(snapshot.balancesByAccount['bank'], 1000);
    expect(snapshot.balancesByAccount['cash'], 0);
    final payments = await database.handle.query('invoice_payments');
    expect(payments.single['payment_method'], 'bank_transfer');
    invoice = snapshot.invoices.single;
    expect(invoice.status, 'paid');
    expect(invoice.paidCents, 1000);
    expect(invoice.balanceDueCents, 0);
  });

  test('checkout rejects a changed price before posting or changing stock',
      () async {
    final repository = await _createRepository();
    addTearDown(repository.close);
    await _addTestProduct(repository);
    final product = (await repository.loadProducts()).single;

    await repository.updateProduct(
      product.id,
      const ProductDraft(
        sku: 'COF-01',
        name: 'Coffee tin',
        unitPriceCents: 1200,
        unitCostCents: 400,
        stockQuantity: 5,
        category: 'Coffee',
      ),
    );

    await expectLater(
      repository.createInvoice(InvoiceDraft(
        customerName: 'Walk-in customer',
        date: DateTime(2026, 11, 18),
        lines: [
          InvoiceLineDraft(
            productId: product.id,
            quantity: 1,
            expectedUnitPriceCents: 1000,
          ),
        ],
        paymentAmountCents: 1000,
      )),
      throwsStateError,
    );

    expect((await repository.loadSnapshot()).invoices, isEmpty);
    expect((await repository.loadProducts()).single.stockQuantity, 5);
    expect(
      (await repository.loadStockMovementPage(productId: product.id)).totalCount,
      1,
    );
  });
}

class _FakePosRepository extends LedgerRepository {
  _FakePosRepository(super.database);

  final List<Product> _products = [_coffee];
  final List<InvoiceDraft> invoiceDrafts = [];

  @override
  Future<ProductPage> loadProductPage({
    String query = '',
    int pageIndex = 0,
    int pageSize = 25,
    String sortBy = 'name',
    bool ascending = true,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    final products = _products.where((product) {
      if (normalizedQuery.isEmpty) return true;
      return product.name.toLowerCase().contains(normalizedQuery) ||
          product.sku.toLowerCase().contains(normalizedQuery) ||
          product.barcode.toLowerCase().contains(normalizedQuery) ||
          product.category.toLowerCase().contains(normalizedQuery);
    }).toList();
    products.sort((left, right) {
      final comparison = sortBy == 'price'
          ? left.unitPriceCents.compareTo(right.unitPriceCents)
          : left.name.toLowerCase().compareTo(right.name.toLowerCase());
      return ascending ? comparison : -comparison;
    });
    final pageCount = products.isEmpty ? 1 : (products.length + pageSize - 1) ~/ pageSize;
    final safePageIndex = pageIndex >= pageCount ? pageCount - 1 : pageIndex;
    final start = safePageIndex * pageSize;
    final end = start + pageSize < products.length ? start + pageSize : products.length;
    return ProductPage(
      products: products.sublist(start, end),
      totalCount: products.length,
      pageIndex: safePageIndex,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<Product>> loadProductsByIds(List<String> productIds) async =>
      _products.where((product) => productIds.contains(product.id)).toList();

  @override
  Future<void> createInvoice(InvoiceDraft draft) async {
    invoiceDrafts.add(draft);
  }
}
