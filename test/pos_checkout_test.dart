import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:ledgerline/data/ledger_database.dart';
import 'package:ledgerline/data/ledger_repository.dart';
import 'package:ledgerline/domain/product.dart';
import 'package:ledgerline/domain/sales_invoice.dart';
import 'package:ledgerline/presentation/pos_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LedgerRepository> createRepository() async {
    final database = await LedgerDatabase.openInMemory();
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    return repository;
  }

  Future<void> addTestProduct(LedgerRepository repository) =>
      repository.createProduct(const ProductDraft(
        sku: 'COF-01',
        name: 'Coffee tin',
        unitPriceCents: 1000,
        unitCostCents: 400,
        stockQuantity: 5,
        category: 'Coffee',
      ));

  Future<void> mountPos(
    WidgetTester tester,
    LedgerRepository repository,
    Map<String, PosCartLine> cart, {
    required bool Function() beforeCheckout,
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
              beforeCheckout: beforeCheckout,
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

  testWidgets('cash checkout posts sale, payment, stock, and ledger together',
      (tester) async {
    final repository = await createRepository();
    addTearDown(repository.close);
    await addTestProduct(repository);

    var refreshCount = 0;
    final savedCart = <String, PosCartLine>{};
    await mountPos(
      tester,
      repository,
      savedCart,
      beforeCheckout: () => true,
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
    expect(savedCart.values.single.product.unitPriceCents, 1000);

    await tester.ensureVisible(find.byKey(const Key('pos-checkout')));
    await tester.tap(find.byKey(const Key('pos-checkout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await tester.pumpAndSettle();

    final snapshot = await repository.loadSnapshot();
    expect(refreshCount, 1);
    expect(savedCart, isEmpty);
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

  testWidgets('sale can be issued without payment and settled later',
      (tester) async {
    final repository = await createRepository();
    addTearDown(repository.close);
    await addTestProduct(repository);

    await mountPos(
      tester,
      repository,
      const {},
      beforeCheckout: () => true,
      onCompleted: () async {},
      onCartChanged: (_) {},
    );

    await tester.tap(find.byKey(const ValueKey('pos-product-COF-01')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pos-checkout')));
    await tester.tap(find.byKey(const Key('pos-checkout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-pay-cash-now')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await tester.pumpAndSettle();

    var invoice = (await repository.loadSnapshot()).invoices.single;
    expect(invoice.status, 'issued');
    expect(invoice.paidCents, 0);
    expect(invoice.balanceDueCents, 1000);

    await repository.recordInvoicePayment(InvoicePaymentDraft(
      invoiceId: invoice.id,
      amountCents: invoice.balanceDueCents,
      date: DateTime(2026, 11, 18),
    ));
    invoice = (await repository.loadSnapshot()).invoices.single;
    expect(invoice.status, 'paid');
    expect(invoice.paidCents, 1000);
    expect(invoice.balanceDueCents, 0);
  });

  testWidgets('clearing the cart updates the app shell cart snapshot',
      (tester) async {
    final repository = await createRepository();
    addTearDown(repository.close);
    await addTestProduct(repository);

    final savedCart = <String, PosCartLine>{};
    await mountPos(
      tester,
      repository,
      savedCart,
      beforeCheckout: () => true,
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

  test('checkout rejects a changed price before posting or changing stock',
      () async {
    final repository = await createRepository();
    addTearDown(repository.close);
    await addTestProduct(repository);
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
  });
}
