import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:ledgerline/data/ledger_database.dart';
import 'package:ledgerline/data/ledger_repository.dart';
import 'package:ledgerline/domain/product.dart';
import 'package:ledgerline/domain/sales_invoice.dart';
import 'package:ledgerline/presentation/pos_page.dart';

const _barcodeProduct = Product(
  id: 'product_barcode',
  sku: 'BAR-1',
  name: 'Barcode item',
  unitPriceCents: 1000,
  unitCostCents: 400,
  stockQuantity: 5,
  barcode: '000012345678',
);

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

Future<_FakePosRepository> _createWidgetRepository(
  WidgetTester tester, {
  List<Product>? products,
  List<String> customerNames = const [],
}) async {
  final database = (await tester.runAsync(LedgerDatabase.openInMemory))!;
  return _FakePosRepository(
    database,
    products: products,
    customerNames: customerNames,
  );
}

Future<void> _mountPos(
  WidgetTester tester,
  LedgerRepository repository,
  Map<String, PosCartLine> cart, {
  required Future<void> Function() onCompleted,
  required ValueChanged<Map<String, PosCartLine>> onCartChanged,
  int taxRateBasisPoints = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PointOfSalePage(
            repository: repository,
            currencyCode: 'USD',
            taxRateBasisPoints: taxRateBasisPoints,
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

  testWidgets('F2 focuses the POS product search', (tester) async {
    final repository = await _createWidgetRepository(
      tester,
      products: const [_coffee],
    );
    addTearDown(() async {
      await tester.runAsync(repository.close);
    });

    await _mountPos(
      tester,
      repository,
      const {},
      onCompleted: () async {},
      onCartChanged: (_) {},
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();

    final search = tester.widget<TextField>(
      find.byKey(const Key('pos-product-search')),
    );
    expect(search.focusNode?.hasFocus, isTrue);
  });

  testWidgets('F4 opens checkout review only for a valid cart', (tester) async {
    final repository = await _createWidgetRepository(
      tester,
      products: const [_coffee],
    );
    addTearDown(() async {
      await tester.runAsync(repository.close);
    });

    await _mountPos(
      tester,
      repository,
      const {},
      onCompleted: () async {},
      onCartChanged: (_) {},
    );
    await _pumpUntil(
      tester,
      () => find.byKey(const ValueKey('pos-product-COF-01')).evaluate().isNotEmpty,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-submit-checkout')), findsNothing);
    expect(repository.invoiceDrafts, isEmpty);

    await tester.tap(find.byKey(const ValueKey('pos-product-COF-01')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('pos-submit-checkout')).evaluate().isNotEmpty,
    );

    expect(repository.invoiceDrafts, isEmpty);
    expect(find.byKey(const Key('pos-submit-checkout')), findsOneWidget);
  });

  test('barcode lookup trims input and requires the complete code', () async {
    final repository = await _createRepository();
    addTearDown(repository.close);
    await repository.createProduct(const ProductDraft(
      sku: 'BAR-1',
      name: 'Barcode item',
      unitPriceCents: 1000,
      unitCostCents: 400,
      stockQuantity: 5,
      barcode: '000012345678',
    ));
    final product = (await repository.loadProducts()).single;

    expect(
      (await repository.loadProductByBarcode(' 000012345678 '))?.id,
      product.id,
    );
    expect(await repository.loadProductByBarcode('00001234567'), isNull);
    expect(await repository.loadProductByBarcode(''), isNull);
  });

  testWidgets('scanner input adds exact barcode matches and caps quantity at stock',
      (tester) async {
    final repository = await _createWidgetRepository(
      tester,
      products: const [_barcodeProduct],
    );
    addTearDown(() async {
      await tester.runAsync(repository.close);
    });

    await _mountPos(
      tester,
      repository,
      const {},
      onCompleted: () async {},
      onCartChanged: (_) {},
    );

    final search = find.byKey(const Key('pos-product-search'));
    final quantity = find.byKey(const ValueKey('pos-quantity-BAR-1'));
    await _pumpUntil(
      tester,
      () => find.byKey(const ValueKey('pos-product-BAR-1')).evaluate().isNotEmpty,
    );

    Future<void> scanAndExpectQuantity(int expected) async {
      await tester.tap(search);
      await tester.enterText(search, _barcodeProduct.barcode);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _pumpUntil(tester, () {
        if (quantity.evaluate().isEmpty) return false;
        return tester.widget<Text>(quantity).data == expected.toString();
      });
    }

    for (var expected = 1; expected <= _barcodeProduct.stockQuantity; expected++) {
      await scanAndExpectQuantity(expected);
    }

    await tester.tap(search);
    await tester.enterText(search, _barcodeProduct.barcode);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Text>(quantity).data, '5');

    final decrease = find.byKey(const ValueKey('pos-decrease-BAR-1'));
    await tester.ensureVisible(decrease);
    await tester.tap(decrease);
    await tester.pump();
    expect(tester.widget<Text>(quantity).data, '4');
    final increase = find.byKey(const ValueKey('pos-increase-BAR-1'));
    await tester.ensureVisible(increase);
    await tester.tap(increase);
    await tester.pump();
    expect(tester.widget<Text>(quantity).data, '5');
  });

  testWidgets('checkout can select a recent invoice customer', (tester) async {
    final repository = await _createWidgetRepository(
      tester,
      products: const [_coffee],
      customerNames: const ['Mira Azadi', 'Nima Karimi'],
    );
    addTearDown(() async {
      await tester.runAsync(repository.close);
    });

    await _mountPos(
      tester,
      repository,
      const {
        'product_coffee': PosCartLine(product: _coffee, quantity: 1),
      },
      onCompleted: () async {},
      onCartChanged: (_) {},
    );

    await tester.tap(find.byKey(const Key('pos-checkout')));
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('pos-submit-checkout')).evaluate().isNotEmpty,
    );

    final customerField = find.byKey(const Key('pos-customer-name'));
    await tester.tap(customerField);
    await tester.enterText(customerField, 'Mira');
    await _pumpUntil(
      tester,
      () => find.text('Mira Azadi').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Mira Azadi'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextFormField>(customerField).controller?.text,
      'Mira Azadi',
    );
    expect(repository.invoiceDrafts, isEmpty);
  });

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

  testWidgets('discount and default tax are calculated before payment',
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
      taxRateBasisPoints: 825,
    );

    await tester.tap(find.byKey(const ValueKey('pos-product-COF-01')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pos-checkout')));
    await tester.tap(find.byKey(const Key('pos-checkout')));
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('pos-submit-checkout')).evaluate().isNotEmpty,
    );
    await tester.enterText(find.byKey(const Key('pos-discount-amount')), '1.00');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await _pumpUntil(tester, () => refreshCount == 1);

    final draft = repository.invoiceDrafts.single;
    expect(draft.discountCents, 100);
    expect(draft.taxCents, 74);
    expect(draft.paymentAmountCents, 974);
  });

  testWidgets('checkout accepts a partial payment and shows the remaining balance',
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

    final amount = find.byKey(const Key('pos-payment-amount'));
    await tester.enterText(amount, '11.00');
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await tester.pump();
    expect(find.text('Payment cannot exceed the invoice total.'), findsOneWidget);
    expect(refreshCount, 0);

    await tester.enterText(amount, '4.50');
    await tester.pump();
    expect(find.text('USD 5.50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await _pumpUntil(tester, () => refreshCount == 1);

    expect(repository.invoiceDrafts, hasLength(1));
    expect(repository.invoiceDrafts.single.paymentAmountCents, 450);
    expect(repository.invoiceDrafts.single.paymentMethod, 'cash');
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


  testWidgets('checkout supports cash and bank split tenders', (tester) async {
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

    final addPaymentButton =
        find.byKey(const Key('pos-add-payment-method'));
    await tester.ensureVisible(addPaymentButton);
    await tester.tap(addPaymentButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('pos-payment-amount')),
      '4.00',
    );
    final secondAmount = find.byKey(const ValueKey('pos-payment-amount-1'));
    await tester.ensureVisible(secondAmount);
    await tester.enterText(secondAmount, '6.00');
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('pos-balance-due'))).data,
      'USD 0.00',
    );
    await tester.enterText(secondAmount, '7.00');
    await tester.pump();
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await tester.pump();
    expect(
      find.text('Payment cannot exceed the invoice total.'),
      findsAtLeastNWidgets(1),
    );
    await tester.enterText(secondAmount, '6.00');
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('pos-submit-checkout')));
    await tester.tap(find.byKey(const Key('pos-submit-checkout')));
    await _pumpUntil(tester, () => refreshCount == 1);

    expect(repository.invoiceDrafts, hasLength(1));
    final draft = repository.invoiceDrafts.single;
    expect(draft.paymentAmountCents, 400);
    expect(draft.paymentMethod, 'cash');
    expect(draft.additionalPayments, hasLength(1));
    expect(draft.additionalPayments.single.amountCents, 600);
    expect(draft.additionalPayments.single.paymentMethod, 'bank_transfer');
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

  test('discounted and taxed sales post the net revenue and balanced totals',
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
      discountCents: 100,
      taxCents: 74,
      paymentAmountCents: 974,
    ));

    final snapshot = await repository.loadSnapshot();
    final invoice = snapshot.invoices.single;
    expect(invoice.subtotalCents, 1000);
    expect(invoice.discountCents, 100);
    expect(invoice.taxCents, 74);
    expect(invoice.totalCents, 974);
    expect(snapshot.balancesByAccount['cash'], 974);
    expect(snapshot.balancesByAccount['receivables'], 0);
    expect(snapshot.netIncomeCents, 500);
    expect(
      snapshot.assetsCents,
      snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents,
    );

    final postedLines = await database.handle.query(
      'journal_lines',
      where: 'entry_id = ?',
      whereArgs: ['journal_${invoice.id}'],
    );
    expect(
      postedLines.any((line) =>
          line['account_id'] == 'sales-income' &&
          line['debit_cents'] == 100 &&
          line['credit_cents'] == 0),
      isTrue,
    );

    await expectLater(
      repository.createInvoice(InvoiceDraft(
        customerName: 'Invalid discount',
        date: DateTime(2026, 11, 18),
        lines: [InvoiceLineDraft(productId: product.id, quantity: 1)],
        discountCents: 1001,
      )),
      throwsArgumentError,
    );
    expect((await repository.loadSnapshot()).invoices, hasLength(1));
    expect((await repository.loadProducts()).single.stockQuantity, 4);
  });

  test('full invoice return refunds payment, restores stock, and reverses accounting',
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
      discountCents: 100,
      taxCents: 74,
      paymentAmountCents: 974,
    ));
    final invoice = (await repository.loadSnapshot()).invoices.single;

    await repository.returnInvoice(InvoiceReturnDraft(
      invoiceId: invoice.id,
      date: DateTime(2026, 11, 19),
      reason: 'Customer returned item',
    ));

    final snapshot = await repository.loadSnapshot();
    final returned = snapshot.invoices.single;
    expect(returned.isReturned, isTrue);
    expect(returned.status, 'paid');
    expect(snapshot.products.single.stockQuantity, 5);
    expect(snapshot.balancesByAccount['cash'], 0);
    expect(snapshot.balancesByAccount['receivables'], 0);
    expect(snapshot.netIncomeCents, 0);
    expect(
      snapshot.assetsCents,
      snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents,
    );
    final paymentHistory = await repository.loadInvoicePaymentHistory(invoice.id);
    expect(paymentHistory!.isReconciled, isTrue);
    expect(paymentHistory.balanceDueCents, 0);
    expect(paymentHistory.returnRecord!.reason, 'Customer returned item');

    final returnRows = await database.handle.query(
      'invoice_returns',
      where: 'invoice_id = ?',
      whereArgs: [invoice.id],
    );
    expect(returnRows.single['refund_amount_cents'], 974);
    final returnLines = await database.handle.query(
      'journal_lines',
      where: 'entry_id = ?',
      whereArgs: ['journal_return_${invoice.id}'],
    );
    expect(
      returnLines.any((line) =>
          line['account_id'] == 'sales-income' && line['debit_cents'] == 900),
      isTrue,
    );
    expect(
      returnLines.any((line) =>
          line['account_id'] == 'tax-payable' && line['debit_cents'] == 74),
      isTrue,
    );
    final movements = await database.handle.query(
      'stock_movements',
      where: 'reference_id = ?',
      whereArgs: ['return_${invoice.id}'],
    );
    expect(movements.single['movement_type'], 'customer_return');
    expect(movements.single['quantity_delta'], 1);

    await database.handle.update(
      'journal_lines',
      {'debit_cents': 899},
      where: "entry_id = ? AND account_id = 'sales-income'",
      whereArgs: ['journal_return_${invoice.id}'],
    );
    expect(
      (await repository.loadInvoicePaymentHistory(invoice.id))!.isReconciled,
      isFalse,
    );

    await expectLater(
      repository.returnInvoice(InvoiceReturnDraft(
        invoiceId: invoice.id,
        date: DateTime(2026, 11, 19),
        reason: 'Duplicate return',
      )),
      throwsStateError,
    );
    await expectLater(
      repository.recordInvoicePayment(InvoicePaymentDraft(
        invoiceId: invoice.id,
        amountCents: 1,
        date: DateTime(2026, 11, 19),
      )),
      throwsArgumentError,
    );
    expect((await repository.loadProducts()).single.stockQuantity, 5);
  });

  test('returning a partially paid invoice refunds paid amount and clears receivable',
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
      paymentAmountCents: 450,
    ));
    final invoice = (await repository.loadSnapshot()).invoices.single;

    await repository.returnInvoice(InvoiceReturnDraft(
      invoiceId: invoice.id,
      date: DateTime(2026, 11, 19),
      reason: 'Order cancelled',
    ));

    final snapshot = await repository.loadSnapshot();
    expect(snapshot.invoices.single.isReturned, isTrue);
    expect(snapshot.invoices.single.balanceDueCents, 0);
    expect(snapshot.products.single.stockQuantity, 5);
    expect(snapshot.balancesByAccount['cash'], 0);
    expect(snapshot.balancesByAccount['receivables'], 0);
    expect(snapshot.netIncomeCents, 0);
    expect(
      snapshot.assetsCents,
      snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents,
    );
    final returnRow = (await database.handle.query('invoice_returns')).single;
    expect(returnRow['refund_amount_cents'], 450);
  });

  test('failed return posting rolls back stock, return, and journal changes',
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
    ));
    final invoice = (await repository.loadSnapshot()).invoices.single;
    final balancesBefore = (await repository.loadSnapshot()).balancesByAccount;

    await database.handle.execute('''
      CREATE TRIGGER reject_customer_return
      BEFORE INSERT ON stock_movements
      WHEN NEW.movement_type = 'customer_return'
      BEGIN
        SELECT RAISE(ABORT, 'forced return posting failure');
      END
    ''');

    await expectLater(
      repository.returnInvoice(InvoiceReturnDraft(
        invoiceId: invoice.id,
        date: DateTime(2026, 11, 19),
        reason: 'Return rollback check',
      )),
      throwsA(anything),
    );

    final snapshotAfter = await repository.loadSnapshot();
    expect(snapshotAfter.invoices.single.isReturned, isFalse);
    expect(snapshotAfter.products.single.stockQuantity, 4);
    expect(snapshotAfter.balancesByAccount, balancesBefore);
    expect(await database.handle.query('invoice_returns'), isEmpty);
    expect(
      await database.handle.query(
        'journal_entries',
        where: 'id = ?',
        whereArgs: ['journal_return_${invoice.id}'],
      ),
      isEmpty,
    );
  });

  test('partial cash checkout posts the receipt and leaves a balanced receivable',
      () async {
    final repository = await _createRepository();
    addTearDown(repository.close);
    await _addTestProduct(repository);
    final product = (await repository.loadProducts()).single;

    await repository.createInvoice(InvoiceDraft(
      customerName: 'Walk-in customer',
      date: DateTime(2026, 11, 18),
      lines: [InvoiceLineDraft(productId: product.id, quantity: 1)],
      paymentAmountCents: 450,
    ));

    final snapshot = await repository.loadSnapshot();
    final invoice = snapshot.invoices.single;
    expect(invoice.status, 'issued');
    expect(invoice.paidCents, 450);
    expect(invoice.balanceDueCents, 550);
    expect(snapshot.balancesByAccount['cash'], 450);
    expect(snapshot.balancesByAccount['receivables'], 550);
    expect(
      snapshot.assetsCents,
      snapshot.liabilitiesCents + snapshot.equityCents + snapshot.netIncomeCents,
    );
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

  test('failed receipt posting rolls back the sale, stock, history, and journals', () async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();
    await repository.configureAccountingCurrency(
      currencyCode: 'USD',
      confirmExistingAmounts: true,
    );
    await _addTestProduct(repository);

    await database.handle.execute('''
      CREATE TRIGGER reject_pos_payment
      BEFORE INSERT ON invoice_payments
      BEGIN
        SELECT RAISE(ABORT, 'forced payment posting failure');
      END
    ''');

    await expectLater(
      repository.createInvoice(InvoiceDraft(
        customerName: 'Walk-in customer',
        date: DateTime(2026, 11, 18),
        lines: [
          InvoiceLineDraft(
            productId: _coffee.id,
            quantity: 2,
            expectedUnitPriceCents: 1000,
          ),
        ],
        paymentAmountCents: 2000,
      )),
      throwsA(anything),
    );

    final products = await repository.loadProducts();
    expect(products.single.stockQuantity, 5);
    expect(await database.handle.query('sales_invoices'), isEmpty);
    expect(await database.handle.query('invoice_lines'), isEmpty);
    expect(await database.handle.query('invoice_payments'), isEmpty);
    expect(await database.handle.query('stock_movements'), hasLength(1));
    expect(await database.handle.query('journal_entries'), hasLength(1));
    expect(await database.handle.query('journal_lines'), hasLength(2));
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
  _FakePosRepository(
    super.database, {
    List<Product>? products,
    List<String> customerNames = const [],
  })  : _products = products ?? [_coffee],
        _customerNames = customerNames;

  final List<Product> _products;
  final List<String> _customerNames;
  final List<InvoiceDraft> invoiceDrafts = [];

  @override
  Future<List<String>> loadRecentInvoiceCustomers({int limit = 50}) async =>
      _customerNames.take(limit).toList(growable: false);

  @override
  Future<Product?> loadProductByBarcode(String barcode) async {
    for (final product in _products) {
      if (product.barcode == barcode.trim()) return product;
    }
    return null;
  }

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
