import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/ledger_repository.dart';
import '../domain/money.dart';
import '../domain/product.dart';
import '../domain/sales_invoice.dart';
import 'app_strings.dart';

class PointOfSalePage extends StatefulWidget {
  const PointOfSalePage({
    super.key,
    required this.repository,
    required this.currencyCode,
    required this.beforeCheckout,
    required this.onCheckoutCompleted,
    required this.initialCart,
    required this.onCartChanged,
  });

  final LedgerRepository repository;
  final String currencyCode;
  final bool Function() beforeCheckout;
  final Future<void> Function() onCheckoutCompleted;
  final Map<String, PosCartLine> initialCart;
  final ValueChanged<Map<String, PosCartLine>> onCartChanged;

  @override
  State<PointOfSalePage> createState() => _PointOfSalePageState();
}

class _PointOfSalePageState extends State<PointOfSalePage> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, PosCartLine> _cart = {};
  Timer? _searchDebounce;
  ProductPage? _productPage;
  Object? _loadError;
  bool _loading = true;
  bool _checkingOut = false;
  int _pageIndex = 0;
  int _queryGeneration = 0;

  int get _cartQuantity =>
      _cart.values.fold<int>(0, (sum, line) => sum + line.quantity);

  int get _cartTotal => _cart.values.fold<int>(
        0,
        (sum, line) => sum + line.product.unitPriceCents * line.quantity,
      );

  bool get _cartStockAvailable =>
      _cart.values.every((line) => line.quantity <= line.product.stockQuantity);

  @override
  void initState() {
    super.initState();
    _cart.addAll(widget.initialCart);
    unawaited(_loadProducts(pageIndex: 0));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'pointOfSale'), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            tr(context, 'posSubtitle'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _catalogPanel(),
                    const SizedBox(height: 16),
                    _cartPanel(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: _catalogPanel()),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: _cartPanel()),
                ],
              );
            },
          ),
        ],
      );

  Widget _catalogPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('pos-product-search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (_) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                _loadProducts(pageIndex: 0);
              });
            },
            decoration: InputDecoration(
              labelText: tr(context, 'posProductSearch'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr(context, 'clearSearch'),
                      onPressed: () {
                        _searchDebounce?.cancel();
                        _searchController.clear();
                        _loadProducts(pageIndex: 0);
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            _productSkeleton()
          else if (_loadError != null)
            _catalogError()
          else if (_productPage == null || _productPage!.products.isEmpty)
            _catalogEmpty()
          else ...[
            GridView.builder(
              key: const Key('pos-product-results'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _productPage!.products.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisExtent: 136,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) =>
                  _productCard(_productPage!.products[index]),
            ),
            const SizedBox(height: 10),
            _pagination(),
          ],
        ],
      );

  Widget _productCard(Product product) {
    final theme = Theme.of(context);
    final available = product.stockQuantity > 0 && !_checkingOut;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('pos-product-' + product.sku),
        onTap: available ? () => _addProduct(product) : null,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    product.stockQuantity == 0
                        ? Icons.remove_shopping_cart_outlined
                        : Icons.add_circle_outline_rounded,
                    size: 20,
                    color: product.stockQuantity == 0
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                product.sku,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      CurrencyDefinition.of(widget.currencyCode)
                          .formatMinorUnits(product.unitPriceCents),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    tr(context, 'stockOnHand') + ': ' + product.stockQuantity.toString(),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartPanel() {
    final theme = Theme.of(context);
    final lines = _cart.values.toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context, 'posCart') + ' · ' + _cartQuantity.toString(),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (lines.isNotEmpty)
                  TextButton(
                    key: const Key('pos-clear-cart'),
                    onPressed: _checkingOut ? null : _clearCart,
                    child: Text(tr(context, 'posClearCart')),
                  ),
              ],
            ),
            const Divider(height: 18),
            if (lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Column(
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 34,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(tr(context, 'posEmptyCart'), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      tr(context, 'posCartHint'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else
              for (final line in lines) _cartLine(line),
            if (lines.isNotEmpty && !_cartStockAvailable)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  tr(context, 'posStockChanged'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context, 'total'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  CurrencyDefinition.of(widget.currencyCode)
                      .formatMinorUnits(_cartTotal),
                  key: const Key('pos-cart-total'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('pos-checkout'),
              onPressed: lines.isEmpty || _checkingOut || !_cartStockAvailable ? null : _checkout,
              icon: _checkingOut
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.point_of_sale_rounded),
              label: Text(tr(context, 'posReviewCheckout')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartLine(PosCartLine line) {
    final theme = Theme.of(context);
    final lineTotal = line.product.unitPriceCents * line.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  line.quantity.toString() + ' × ' +
                      CurrencyDefinition.of(widget.currencyCode)
                          .formatMinorUnits(line.product.unitPriceCents) +
                      ' = ' +
                      CurrencyDefinition.of(widget.currencyCode)
                          .formatMinorUnits(lineTotal),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('pos-decrease-' + line.product.sku),
            tooltip: tr(context, 'reduceStock'),
            onPressed: _checkingOut ? null : () => _changeQuantity(line.product, -1),
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          Text(line.quantity.toString()),
          IconButton(
            key: ValueKey('pos-increase-' + line.product.sku),
            tooltip: tr(context, 'add'),
            onPressed: _checkingOut ? null : () => _changeQuantity(line.product, 1),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }

  Widget _pagination() {
    final page = _productPage!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          page.totalCount == 0
              ? '0'
              : page.firstItemNumber.toString() + '–' +
                  page.lastItemNumber.toString() + ' / ' + page.totalCount.toString(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const Key('pos-previous-page'),
          tooltip: tr(context, 'previousPage'),
          onPressed: page.pageIndex == 0 || _loading
              ? null
              : () => _loadProducts(pageIndex: page.pageIndex - 1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          key: const Key('pos-next-page'),
          tooltip: tr(context, 'nextPage'),
          onPressed: page.pageIndex + 1 >= page.pageCount || _loading
              ? null
              : () => _loadProducts(pageIndex: page.pageIndex + 1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _productSkeleton() {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var index = 0; index < 6; index++)
          Container(
            width: 188,
            height: 136,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
      ],
    );
  }

  Widget _catalogEmpty() => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(tr(context, 'posNoProducts'))),
        ),
      );

  Widget _catalogError() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'posProductsLoadFailed') + ': ' + _loadError.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _loadProducts(pageIndex: _pageIndex),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(tr(context, 'retry')),
              ),
            ],
          ),
        ),
      );

  void _addProduct(Product product) {
    _changeQuantity(product, 1);
  }

  void _changeQuantity(Product product, int delta) {
    final existingLine = _cart[product.id];
    final current = existingLine?.quantity ?? 0;
    final next = current + delta;
    if (next <= 0) {
      if (current > 0) {
        setState(() => _cart.remove(product.id));
        _notifyCartChanged();
      }
      return;
    }
    if (next > product.stockQuantity) {
      _notify(tr(context, 'posStockLimit'));
      return;
    }
    const maxSignedInt = 0x7fffffffffffffff;
    if (product.unitPriceCents > maxSignedInt ~/ next) {
      _notify(tr(context, 'posTotalTooLarge'));
      return;
    }
    final nextLineTotal = product.unitPriceCents * next;
    final currentLineTotal =
        (existingLine?.product.unitPriceCents ?? 0) * current;
    final otherTotal = _cartTotal - currentLineTotal;
    if (otherTotal > maxSignedInt - nextLineTotal) {
      _notify(tr(context, 'posTotalTooLarge'));
      return;
    }
    setState(() {
      _cart[product.id] = PosCartLine(product: product, quantity: next);
    });
    _notifyCartChanged();
  }

  void _clearCart() {
    if (_cart.isEmpty) return;
    setState(_cart.clear);
    _notifyCartChanged();
  }

  void _notifyCartChanged() {
    widget.onCartChanged(Map.unmodifiable(_cart));
  }

  Future<void> _loadProducts({required int pageIndex}) async {
    final generation = ++_queryGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _pageIndex = pageIndex;
      });
    }
    try {
      final page = await widget.repository.loadProductPage(
        query: _searchController.text,
        pageIndex: pageIndex,
        pageSize: 25,
        sortBy: 'name',
      );
      if (!mounted || generation != _queryGeneration) return;
      setState(() {
        _productPage = page;
        _pageIndex = page.pageIndex;
      });
    } on Object catch (error) {
      if (mounted && generation == _queryGeneration) {
        setState(() => _loadError = error);
      }
    } finally {
      if (mounted && generation == _queryGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _checkingOut || !widget.beforeCheckout()) return;

    setState(() => _checkingOut = true);
    var invoicePosted = false;
    try {
      final latestProducts = await widget.repository.loadProductsByIds(
        _cart.keys.toList(growable: false),
      );
      if (!mounted) return;
      final latestById = {for (final product in latestProducts) product.id: product};
      final latestCart = <String, PosCartLine>{};
      var cartChanged = latestById.length != _cart.length;
      for (final entry in _cart.entries) {
        final latest = latestById[entry.key];
        if (latest == null) continue;
        final previous = entry.value.product;
        if (latest.name != previous.name ||
            latest.unitPriceCents != previous.unitPriceCents ||
            latest.stockQuantity != previous.stockQuantity) {
          cartChanged = true;
        }
        latestCart[entry.key] =
            PosCartLine(product: latest, quantity: entry.value.quantity);
      }
      if (cartChanged) {
        final removed = latestCart.length != _cart.length;
        setState(() {
          _cart
            ..clear()
            ..addAll(latestCart);
        });
        _notifyCartChanged();
        _notify(
          tr(context, removed ? 'posProductUnavailable' : 'posCartPricesRefreshed'),
        );
        return;
      }
      if (!_cartStockAvailable) {
        _notify(tr(context, 'posStockChanged'));
        return;
      }

      final total = _cartTotal;
      // The modal review step blocks the page below it. Stop animating a
      // checkout spinner behind the dialog while the cashier makes a choice.
      setState(() => _checkingOut = false);
      final request = await showDialog<_PosCheckoutRequest>(
        context: context,
        builder: (context) => _PosCheckoutDialog(
          currencyCode: widget.currencyCode,
          totalCents: total,
        ),
      );
      if (request == null || !mounted || _cart.isEmpty) return;
      setState(() => _checkingOut = true);

      await widget.repository.createInvoice(
        InvoiceDraft(
          customerName: request.customerName,
          date: DateTime.now(),
          lines: [
            for (final line in _cart.values)
              InvoiceLineDraft(
                productId: line.product.id,
                quantity: line.quantity,
                expectedUnitPriceCents: line.product.unitPriceCents,
              ),
          ],
          paymentAmountCents: request.payInCash ? total : 0,
        ),
      );
      invoicePosted = true;
      if (mounted) {
        setState(_cart.clear);
        _notifyCartChanged();
      }
      await widget.onCheckoutCompleted();
      await _loadProducts(pageIndex: _pageIndex);
      if (mounted) {
        _notify(
          tr(context, request.payInCash ? 'posSalePaid' : 'posSaleOnAccount'),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        _notify(
          (invoicePosted
                  ? tr(context, 'posSaleSavedRefreshFailed')
                  : tr(context, 'posCheckoutFailed')) +
              ': ' +
              error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class PosCartLine {
  const PosCartLine({required this.product, required this.quantity});

  final Product product;
  final int quantity;
}

class _PosCheckoutRequest {
  const _PosCheckoutRequest({
    required this.customerName,
    required this.payInCash,
  });

  final String customerName;
  final bool payInCash;
}

class _PosCheckoutDialog extends StatefulWidget {
  const _PosCheckoutDialog({
    required this.currencyCode,
    required this.totalCents,
  });

  final String currencyCode;
  final int totalCents;

  @override
  State<_PosCheckoutDialog> createState() => _PosCheckoutDialogState();
}

class _PosCheckoutDialogState extends State<_PosCheckoutDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _customerName = TextEditingController(
    text: 'Walk-in customer',
  );
  bool _payInCash = true;

  @override
  void dispose() {
    _customerName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'posCheckoutTitle')),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('pos-customer-name'),
                  controller: _customerName,
                  autofocus: true,
                  decoration: InputDecoration(labelText: tr(context, 'customer')),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? tr(context, 'posCustomerRequired')
                      : null,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('pos-pay-cash-now'),
                  value: _payInCash,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) =>
                      setState(() => _payInCash = value ?? false),
                  title: Text(tr(context, 'cashPaymentNow')),
                  subtitle: Text(tr(context, 'cashPaymentHint')),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(tr(context, 'total'))),
                    Text(
                      CurrencyDefinition.of(widget.currencyCode)
                          .formatMinorUnits(widget.totalCents),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, 'cancel')),
          ),
          FilledButton(
            key: const Key('pos-submit-checkout'),
            onPressed: _submit,
            child: Text(tr(context, 'posCompleteSale')),
          ),
        ],
      );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _PosCheckoutRequest(
        customerName: _customerName.text.trim(),
        payInCash: _payInCash,
      ),
    );
  }
}
