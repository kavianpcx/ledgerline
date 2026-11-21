import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:window_manager/window_manager.dart';

import 'navigation_presentation.dart';
import 'widgets/desktop_sidebar.dart';

import '../config/app_version.dart';
import '../data/ledger_repository.dart';
import '../domain/account.dart';
import '../domain/app_settings.dart';
import '../domain/accounting_engine.dart';
import '../domain/ledger_entry.dart';
import '../domain/money.dart';
import '../domain/product.dart';
import '../domain/stock_movement.dart';
import '../domain/product_csv_import.dart';
import '../domain/product_xlsx_import.dart';
import '../domain/sales_invoice.dart';
import '../services/offline_ocr_service.dart';
import '../services/invoice_print_service.dart';
import '../services/update_service.dart';
import 'app_strings.dart';
import 'widgets/searchable_select.dart';
import 'pos_page.dart';
import 'more_tools_page.dart';

IconData _productIconData(String key) => switch (key) {
      'shopping_bag' => Icons.shopping_bag_outlined,
      'restaurant' => Icons.restaurant_outlined,
      'beverage' => Icons.local_cafe_outlined,
      'electronics' => Icons.devices_outlined,
      'medicine' => Icons.medical_services_outlined,
      'tools' => Icons.build_outlined,
      'book' => Icons.menu_book_outlined,
      _ => Icons.inventory_2_outlined,
    };

String _productIconLabelKey(String key) => switch (key) {
      'shopping_bag' => 'productIconShoppingBag',
      'restaurant' => 'productIconRestaurant',
      'beverage' => 'productIconBeverage',
      'electronics' => 'productIconElectronics',
      'medicine' => 'productIconMedicine',
      'tools' => 'productIconTools',
      'book' => 'productIconBook',
      _ => 'productIconInventory',
    };

class LedgerHomePage extends StatefulWidget {
  const LedgerHomePage({
    super.key,
    required this.repository,
    required this.settings,
    required this.onSettingsChanged,
    this.visualScenario = '',
  });

  final LedgerRepository repository;
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final String visualScenario;

  @override
  State<LedgerHomePage> createState() => _LedgerHomePageState();
}

class _LedgerHomePageState extends State<LedgerHomePage> {
  int _selectedIndex = 0;
  int _settingsSectionIndex = 0;
  late Future<LedgerSnapshot> _snapshot;
  late final TextEditingController _businessNameController;
  late final TextEditingController _taxRateController;
  late final UpdateService _updateService;
  bool _checkingUpdates = false;
  bool _downloadingUpdate = false;
  String? _printingInvoiceId;
  bool _restoringBackup = false;
  bool _updateChecked = false;
  bool _updateCheckFailed = false;
  UpdateInfo? _availableUpdate;
  bool _sidebarExpandedAtMediumWidth = false;
  late final TextEditingController _productSearchController;
  Future<ProductPage>? _productPageFuture;
  Timer? _productSearchDebounce;
  int _productPageIndex = 0;
  int _productPageSize = 25;
  String _productSortBy = 'name';
  bool _productSortAscending = true;
  final Map<String, PosCartLine> _posCart = {};

  static const _destinations = <(String, IconData, IconData)>[
    ('overview', Icons.grid_view_rounded, Icons.grid_view_outlined),
    ('entries', Icons.receipt_long_rounded, Icons.receipt_long_outlined),
    ('accounts', Icons.account_tree_rounded, Icons.account_tree_outlined),
    ('products', Icons.inventory_2_rounded, Icons.inventory_2_outlined),
    ('invoices', Icons.request_quote_rounded, Icons.request_quote_outlined),
    ('reports', Icons.analytics_rounded, Icons.analytics_outlined),
    ('smartImport', Icons.file_upload_outlined, Icons.file_upload_outlined),
    ('settings', Icons.settings_rounded, Icons.settings_outlined),
    ('pointOfSale', Icons.shopping_cart_rounded, Icons.shopping_cart_outlined),
    ('more', Icons.more_horiz_rounded, Icons.more_horiz_outlined),
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    switch (widget.visualScenario) {
      case 'settings-light':
        _selectedIndex = 7;
        _settingsSectionIndex = 0;
        break;
      case 'settings-dark':
        _selectedIndex = 7;
        _settingsSectionIndex = 2;
        break;
      case 'settings-fa':
        _selectedIndex = 7;
        _settingsSectionIndex = 3;
        break;
      case 'currency-popup':
        _selectedIndex = 7;
        _settingsSectionIndex = 4;
        break;
      case 'more-tools':
        _selectedIndex = 9;
        break;
      default:
        break;
    }
    _snapshot = widget.repository.loadSnapshot();
    _businessNameController = TextEditingController(text: widget.settings.businessName);
    _taxRateController = TextEditingController(
      text: _formatTaxRate(widget.settings.defaultTaxRateBasisPoints),
    );
    _productSearchController = TextEditingController();
    _productSearchController.addListener(_onProductSearchChanged);
    _updateService = const UpdateService();
    if (kReleaseMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkForUpdates(silent: true));
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _businessNameController.dispose();
    _taxRateController.dispose();
    _productSearchDebounce?.cancel();
    _productSearchController.removeListener(_onProductSearchChanged);
    _productSearchController.dispose();
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!io.Platform.isWindows || event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed || !keyboard.isShiftPressed) return false;
    final window = WindowManager.instance.getCurrent();
    if (window == null) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyM) {
      window.minimize();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      if (window.isMaximized) {
        window.unmaximize();
      } else {
        window.maximize();
      }
      return true;
    }
    return false;
  }

  String _updateStatus() {
    if (_checkingUpdates) return tr(context, 'checkingForUpdates');
    if (_downloadingUpdate) return tr(context, 'verifyingUpdate');
    final update = _availableUpdate;
    if (update != null) return tr(context, 'updateAvailable') + ' v' + update.version;
    if (_updateChecked && !_updateCheckFailed) return tr(context, 'upToDate');
    if (_updateCheckFailed) return tr(context, 'updateCheckFailed');
    return tr(context, 'updateInfo');
  }

  Future<void> _checkForUpdates({bool silent = false}) async {
    if (_checkingUpdates) return;
    setState(() {
      _checkingUpdates = true;
      _updateCheckFailed = false;
    });
    try {
      final update = await _updateService.checkForUpdate(
        currentVersion: appVersion,
        android: io.Platform.isAndroid,
      );
      if (!mounted) return;
      setState(() {
        _availableUpdate = update;
        _updateChecked = true;
      });
      if (!silent) {
        _notify(update == null
            ? tr(context, 'upToDate')
            : tr(context, 'updateAvailable') + ' v' + update.version);
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _availableUpdate = null;
        _updateChecked = true;
        _updateCheckFailed = true;
      });
      if (!silent) _notify(tr(context, 'updateCheckFailed'));
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  Future<void> _downloadAndInstallUpdate() async {
    final update = _availableUpdate;
    if (update == null || _downloadingUpdate) return;
    if (io.Platform.isAndroid) {
      try {
        final opened = await _updateService.openAndroidUpdate(update);
        if (mounted) _notify(tr(context, opened ? 'androidUpdateOpened' : 'androidUpdateOpenFailed'));
      } on Object {
        if (mounted) _notify(tr(context, 'androidUpdateOpenFailed'));
      }
      return;
    }
    setState(() => _downloadingUpdate = true);
    try {
      final installer = await _updateService.downloadAndVerify(update);
      if (!mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(dialogContext, 'updateReady') + ' v' + update.version),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(dialogContext, 'updateVerified')),
              const SizedBox(height: 12),
              SelectableText('SHA-256: ' + update.sha256, style: Theme.of(dialogContext).textTheme.bodySmall),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr(dialogContext, 'cancel')),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.install_desktop_rounded),
              label: Text(tr(dialogContext, 'installUpdate')),
            ),
          ],
        ),
      );
      if (install != true || !mounted) return;
      await io.Process.start(
        installer.path,
        const <String>[],
        mode: io.ProcessStartMode.detached,
      );
      final window = WindowManager.instance.getCurrent();
      if (window == null || !window.close()) {
        throw StateError('Ledgerline could not close cleanly before installation.');
      }
    } on Object catch (error) {
      if (mounted) _notify(tr(context, 'updateDownloadFailed') + ': ' + error.toString());
    } finally {
      if (mounted) setState(() => _downloadingUpdate = false);
    }
  }

  Future<ProductPage> _loadProductPage() => widget.repository.loadProductPage(
        query: _productSearchController.text,
        pageIndex: _productPageIndex,
        pageSize: _productPageSize,
        sortBy: _productSortBy,
        ascending: _productSortAscending,
      );

  void _onProductSearchChanged() {
    _productSearchDebounce?.cancel();
    _productSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _productPageIndex = 0;
        _productPageFuture = _loadProductPage();
      });
    });
  }

  void _refreshProductPage({bool resetPage = false}) {
    if (resetPage) _productPageIndex = 0;
    _productPageFuture = _loadProductPage();
  }

  Future<void> _reload() async {
    setState(() {
      _snapshot = widget.repository.loadSnapshot();
      if (_productPageFuture != null) _refreshProductPage();
    });
    await _snapshot;
    final productPage = _productPageFuture;
    if (productPage != null) await productPage;
  }

  Future<void> _addEntry(LedgerSnapshot snapshot) async {
    if (!_requireAccountingCurrency()) return;
    final draft = await showDialog<JournalDraft>(
      context: context,
      builder: (context) => _EntryDialog(
        accounts: snapshot.accounts,
        currencyCode: widget.settings.currencyCode,
      ),
    );
    if (draft == null || !mounted) return;

    try {
      await widget.repository.createEntry(draft);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journal entry saved.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save entry: $error')),
      );
    }
  }

  Future<void> _addAccount() async {
    final draft = await showDialog<AccountDraft>(
      context: context,
      builder: (context) => const _AccountDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.repository.createAccount(draft);
      await _reload();
      if (mounted) _notify(tr(context, 'accountSaved'));
    } on Object catch (error) {
      if (mounted) _notify('${tr(context, 'errorCouldNotSave')}: $error');
    }
  }

  Future<void> _addProduct() async {
    if (!_requireAccountingCurrency()) return;
    final draft = await showDialog<ProductDraft>(
      context: context,
      builder: (context) => _ProductDialog(currencyCode: widget.settings.currencyCode),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.repository.createProduct(draft);
      await _reload();
      if (mounted) _notify('Product saved.');
    } on Object catch (error) {
      if (mounted) _notify('Could not save product: $error');
    }
  }

  Future<void> _editProduct(Product product) async {
    if (!_requireAccountingCurrency()) return;
    final draft = await showDialog<ProductDraft>(
      context: context,
      builder: (context) => _ProductDialog(
        currencyCode: widget.settings.currencyCode,
        product: product,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.repository.updateProduct(product.id, draft);
      await _reload();
      if (mounted) _notify(tr(context, 'productUpdated'));
    } on Object catch (error) {
      if (mounted) _notify(tr(context, 'errorCouldNotSave') + ': ' + error.toString());
    }
  }

  Future<void> _adjustStock(Product product, int delta) async {
    if (!_requireAccountingCurrency()) return;
    try {
      await widget.repository.adjustStock(product.id, delta);
      await _reload();
      if (mounted) _notify(tr(context, 'stockAdjusted'));
    } on Object catch (error) {
      if (mounted) _notify('Could not adjust stock: $error');
    }
  }

  Future<void> _showStockMovementHistory(Product product) => showDialog<void>(
        context: context,
        builder: (context) => _StockMovementHistoryDialog(
          repository: widget.repository,
          product: product,
        ),
      );

  Future<void> _printInvoice(
    SalesInvoice invoice,
    InvoicePrintFormat format,
  ) async {
    if (_printingInvoiceId != null) return;
    setState(() => _printingInvoiceId = invoice.id);
    try {
      final printData =
          await widget.repository.loadInvoicePrintData(invoice.id);
      if (printData == null) {
        throw StateError('The invoice no longer exists.');
      }
      await InvoicePrintService().printInvoice(
        invoice: printData,
        businessName: widget.settings.businessName,
        currencyCode: widget.settings.currencyCode,
        format: format,
        isPersian: Localizations.localeOf(context).languageCode == 'fa',
      );
    } on Object {
      if (mounted) _notify(tr(context, 'invoicePrintFailed'));
    } finally {
      if (mounted) setState(() => _printingInvoiceId = null);
    }
  }

  Future<void> _showInvoicePaymentHistory(SalesInvoice invoice) =>
      showDialog<void>(
        context: context,
        builder: (context) => _InvoicePaymentHistoryDialog(
          repository: widget.repository,
          invoice: invoice,
          currencyCode: widget.settings.currencyCode,
        ),
      );

  Future<void> _addInvoice(LedgerSnapshot snapshot) async {
    if (!_requireAccountingCurrency()) return;
    if (snapshot.products.isEmpty) {
      _notify(tr(context, 'invoiceNoProducts'));
      return;
    }
    final draft = await showDialog<InvoiceDraft>(
      context: context,
      builder: (context) => _InvoiceDialog(
        products: snapshot.products,
        currencyCode: widget.settings.currencyCode,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.repository.createInvoice(draft);
      await _reload();
      if (mounted) _notify(tr(context, 'invoiceSaved'));
    } on Object catch (error) {
      if (mounted) _notify('Could not issue invoice: $error');
    }
  }

  Future<void> _recordInvoicePayment(SalesInvoice invoice) async {
    if (!_requireAccountingCurrency()) return;
    final draft = await showDialog<InvoicePaymentDraft>(
      context: context,
      builder: (context) => _InvoicePaymentDialog(
        invoice: invoice,
        currencyCode: widget.settings.currencyCode,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.repository.recordInvoicePayment(draft);
      await _reload();
      if (mounted) _notify(tr(context, 'paymentSaved'));
    } on Object catch (error) {
      if (mounted) _notify('${tr(context, 'paymentFailed')}: $error');
    }
  }


  Future<void> _returnInvoice(SalesInvoice invoice) async {
    if (!_requireAccountingCurrency() || invoice.isReturned || invoice.status == 'void') {
      return;
    }
    final draft = await showDialog<InvoiceReturnDraft>(
      context: context,
      builder: (context) => _InvoiceReturnDialog(
        repository: widget.repository,
        invoice: invoice,
        currencyCode: widget.settings.currencyCode,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.repository.returnInvoice(draft);
      await _reload();
      if (mounted) _notify(tr(context, 'returnInvoiceSaved'));
    } on Object catch (error) {
      if (mounted) {
        _notify(tr(context, 'returnInvoiceFailed') + ': ' + error.toString());
      }
    }
  }


  bool _requireAccountingCurrency() {
    if (widget.settings.accountingCurrencyConfigured) return true;
    _notify(tr(context, 'currencySetupRequired'));
    setState(() {
      _selectedIndex = 7;
      _settingsSectionIndex = 4;
    });
    return false;
  }

  Future<void> _chooseAccountingCurrency(String currencyCode) async {
    if (currencyCode == widget.settings.currencyCode &&
        widget.settings.accountingCurrencyConfigured) {
      return;
    }

    late final bool hasMonetaryData;
    try {
      hasMonetaryData = await widget.repository.hasMonetaryRecords();
    } on Object catch (error) {
      if (mounted) _notify('${tr(context, 'errorCouldNotSave')}: $error');
      return;
    }
    if (!mounted) return;
    if (hasMonetaryData && widget.settings.accountingCurrencyConfigured) {
      _notify(tr(context, 'currencyLocked'));
      return;
    }

    var confirmed = !hasMonetaryData;
    if (hasMonetaryData) {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(tr(dialogContext, 'currencyConfirmLegacyTitle')),
              content: Text(
                tr(dialogContext, 'currencyConfirmLegacyBody')
                    .replaceAll('{currency}', currencyCode),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(tr(dialogContext, 'cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(tr(dialogContext, 'confirmCurrency')),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!confirmed || !mounted) return;

    try {
      await widget.repository.configureAccountingCurrency(
        currencyCode: currencyCode,
        confirmExistingAmounts: hasMonetaryData,
      );
      await widget.onSettingsChanged(
        widget.settings.copyWith(
          currencyCode: currencyCode,
          accountingCurrencyConfigured: true,
        ),
      );
      if (mounted) _notify(tr(context, 'settingsSaved'));
    } on Object catch (error) {
      if (mounted) _notify('${tr(context, 'errorCouldNotSave')}: $error');
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatTaxRate(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final fraction = basisPoints % 100;
    return fraction == 0 ? '$whole' : '$whole.' + fraction.toString().padLeft(2, '0');
  }

  int? _parseTaxRate(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    final match = RegExp(r'^(\d{1,3})(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final fraction = int.parse((match.group(2) ?? '').padRight(2, '0'));
    final basisPoints = whole * 100 + fraction;
    return basisPoints <= 10000 ? basisPoints : null;
  }

  Future<void> _saveDefaultTaxRate() async {
    final basisPoints = _parseTaxRate(_taxRateController.text);
    if (basisPoints == null) {
      _notify(tr(context, 'invalidTaxRate'));
      return;
    }
    try {
      await widget.onSettingsChanged(
        widget.settings.copyWith(defaultTaxRateBasisPoints: basisPoints),
      );
      if (mounted) _notify(tr(context, 'settingsSaved'));
    } on Object catch (error) {
      if (mounted) _notify(tr(context, 'errorCouldNotSave') + ': ' + error.toString());
    }
  }

  Future<void> _saveBusinessName() async {
    await widget.onSettingsChanged(
      widget.settings.copyWith(businessName: _businessNameController.text.trim()),
    );
    if (mounted) _notify(tr(context, 'settingsSaved'));
  }

  Future<void> _exportBackup() async {
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: tr(context, 'exportBackup'),
      fileName: 'ledgerline-backup.sqlite',
      type: FileType.custom,
      allowedExtensions: const ['sqlite', 'db'],
    );
    if (destination == null || !mounted) return;
    try {
      await widget.repository.exportBackup(destination);
      if (mounted) _notify(tr(context, 'backupSaved'));
    } on Object catch (error) {
      if (mounted) _notify('${tr(context, 'errorCouldNotSave')}: $error');
    }
  }

  Future<void> _restoreBackup() async {
    if (_restoringBackup) return;
    final selected = await FilePicker.platform.pickFiles(
      dialogTitle: tr(context, 'restoreBackup'),
      type: FileType.custom,
      allowedExtensions: const ['sqlite', 'db'],
    );
    if (selected == null || selected.files.isEmpty || !mounted) return;
    final backupPath = selected.files.single.path;
    if (backupPath == null) {
      _notify(tr(context, 'backupRestoreFailed'));
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'restoreBackup')),
        content: Text(tr(dialogContext, 'restoreBackupWarning')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(dialogContext, 'cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.restore_rounded),
            label: Text(tr(dialogContext, 'restoreBackupConfirm')),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    setState(() => _restoringBackup = true);
    try {
      final recoveryPath = await widget.repository.restoreBackup(backupPath);
      final restoredSettings = await widget.repository.loadAppSettings();
      _businessNameController.text = restoredSettings.businessName;
      _taxRateController.text = _formatTaxRate(restoredSettings.defaultTaxRateBasisPoints);
      await widget.onSettingsChanged(restoredSettings);
      await _reload();
      if (mounted) {
        final recoveryMessage = recoveryPath == null ? '' : '\n$recoveryPath';
        _notify(tr(context, 'backupRestored') + recoveryMessage);
      }
    } on Object catch (error) {
      if (mounted) _notify('${tr(context, 'backupRestoreFailed')}: $error');
    } finally {
      if (mounted) setState(() => _restoringBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWindowsDesktop = io.Platform.isWindows;
        final navigationPresentation = navigationPresentationFor(
          windowsDesktop: isWindowsDesktop,
          availableWidth: constraints.maxWidth,
        );
        final isWide = navigationPresentation != LedgerNavigationPresentation.mobileBottomBar;
        final isCompact = constraints.maxWidth < 640;
        final sidebarExpanded = isWindowsDesktop && desktopSidebarExpandedFor(
          availableWidth: constraints.maxWidth,
          collapsedPreference: widget.settings.desktopSidebarCollapsed,
          expandedAtMediumWidth: _sidebarExpandedAtMediumWidth,
        );
        final navigationWidth = navigationPresentation == LedgerNavigationPresentation.windowsSidebar
            ? (sidebarExpanded ? 252.0 : 76.0)
            : navigationPresentation == LedgerNavigationPresentation.tabletRail
                ? 80.0
                : 0.0;
        final contentWidth = (constraints.maxWidth - navigationWidth).clamp(0.0, constraints.maxWidth).toDouble();
        final navIndex = switch (_selectedIndex) {
          0 => 0,
          8 => 1,
          3 => 2,
          _ => 3,
        };
        final scaffold = Scaffold(
          appBar: io.Platform.isWindows
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: WindowCaption(
                      brightness: Theme.of(context).brightness,
                      title: SizedBox(
                      height: 56,
                      child: Row(
                        textDirection: TextDirection.ltr,
                        children: [
                          const SizedBox(width: 14),
                          Flexible(
                            child: Text(
                              widget.settings.businessName.trim().isEmpty
                                  ? tr(context, 'appName')
                                  : widget.settings.businessName.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              : AppBar(
                  titleSpacing: isWide ? 32 : 20,
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2EE),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.account_balance_wallet_rounded,
                            color: Color(0xFF087E78), size: 19),
                      ),
                      const SizedBox(width: 11),
                      Flexible(
                        child: Text(
                          tr(context, 'appName') +
                              (widget.settings.businessName.trim().isEmpty
                                  ? ''
                                  : ' · ${widget.settings.businessName.trim()}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    if (!isWindowsDesktop && (_selectedIndex == 0 || _selectedIndex == 1))
                      FutureBuilder<LedgerSnapshot>(
                        future: _snapshot,
                        builder: (context, result) => Padding(
                          padding: const EdgeInsets.only(right: 18),
                          child: FilledButton.icon(
                            onPressed: result.data == null ? null : () => _addEntry(result.data!),
                            icon: const Icon(Icons.add_rounded, size: 19),
                            label: Text(isCompact ? tr(context, 'add') : tr(context, 'newEntry')),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF087E78),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
          body: Row(
            textDirection: isWindowsDesktop ? TextDirection.ltr : null,
            children: [
              if (navigationPresentation == LedgerNavigationPresentation.windowsSidebar)
                LedgerDesktopSidebar(
                  destinations: _destinations,
                  selectedIndex: _selectedIndex,
                  collapsed: !sidebarExpanded,
                  canToggleExpanded: constraints.maxWidth >= 760,
                  onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                  onCollapsedChanged: (collapsed) {
                    setState(() => _sidebarExpandedAtMediumWidth = !collapsed);
                    unawaited(widget.onSettingsChanged(
                      widget.settings.copyWith(desktopSidebarCollapsed: collapsed),
                    ));
                  },
                ),
              if (navigationPresentation == LedgerNavigationPresentation.tabletRail)
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  groupAlignment: -0.82,
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.$3),
                        selectedIcon: Icon(destination.$2),
                        label: Text(tr(context, destination.$1)),
                      ),
                  ],
                ),
              Expanded(
                child: FutureBuilder<LedgerSnapshot>(
                  future: _snapshot,
                  builder: (context, result) {
                    if (result.connectionState != ConnectionState.done) {
                      return const _LedgerSkeleton();
                    }
                    if (result.hasError) {
                      return _LoadError(message: result.error.toString(), onRetry: _reload);
                    }
                    final snapshot = result.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!widget.settings.accountingCurrencyConfigured)
                          MaterialBanner(
                            content: Text(tr(context, 'currencySetupRequired')),
                            leading: const Icon(Icons.info_outline_rounded),
                            actions: [
                              TextButton(
                                onPressed: () => setState(() {
                                  _selectedIndex = 7;
                                  _settingsSectionIndex = 4;
                                }),
                                child: Text(tr(context, 'configureCurrency')),
                              ),
                            ],
                          ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _reload,
                            child: _page(snapshot, contentWidth),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: navigationPresentation == LedgerNavigationPresentation.mobileBottomBar
              ? NavigationBar(
                  key: const Key('ledgerline-bottom-navigation'),
                  selectedIndex: navIndex,
                  onDestinationSelected: (index) => setState(() {
                    _selectedIndex = switch (index) { 0 => 0, 1 => 8, 2 => 3, _ => 9 };
                  }),
                  destinations: [
                    for (final index in [0, 8, 3, 9])
                      NavigationDestination(
                        icon: Icon(_destinations[index].$3),
                        selectedIcon: Icon(_destinations[index].$2),
                        label: tr(context, _destinations[index].$1),
                      ),
                  ],
                )
              : null,
        );
        if (!io.Platform.isWindows) return scaffold;
        return DragToResizeArea(child: scaffold);
      },
    );
  }

  Widget _page(LedgerSnapshot snapshot, double availableWidth) {
    final maxWidth = availableWidth >= 900 ? 1200.0 : 760.0;
    final content = switch (_selectedIndex) {
      0 => _overview(snapshot, availableWidth),
      1 => _entries(snapshot),
      2 => _accounts(snapshot),
      3 => _products(snapshot),
      4 => _invoices(snapshot),
      5 => _reports(snapshot),
      6 => _smartImport(snapshot),
      7 => _settingsPage(snapshot),
      8 => PointOfSalePage(
          repository: widget.repository,
          currencyCode: widget.settings.currencyCode,
          taxRateBasisPoints: widget.settings.defaultTaxRateBasisPoints,
          beforeCheckout: _requireAccountingCurrency,
          initialCart: _posCart,
          onCartChanged: (cart) {
            _posCart
              ..clear()
              ..addAll(cart);
          },
          onCheckoutCompleted: _reload,
        ),
      _ => _more(snapshot),
    };
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
      children: [Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: content))],
    );
  }

  Widget _products(LedgerSnapshot snapshot) {
    final pageFuture = _productPageFuture ??= _loadProductPage();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(context, 'productsTitle'), style: _pageTitle),
        const SizedBox(height: 6),
        Text(
          tr(context, 'productsHint'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: _addProduct,
            icon: const Icon(Icons.add_rounded),
            label: Text(tr(context, 'newProduct')),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _productSearchController,
          decoration: InputDecoration(
            hintText: tr(context, 'productSearchHint'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _productSearchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: tr(context, 'clearSearch'),
                    onPressed: _productSearchController.clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          textInputAction: TextInputAction.search,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 210,
              child: SearchableSelect<String>(
                id: 'products-sort',
                label: tr(context, 'sortBy'),
                searchHint: tr(context, 'sortBy'),
                emptyLabel: tr(context, 'noSearchResults'),
                value: _productSortBy,
                options: [
                  SearchableSelectOption(value: 'name', label: tr(context, 'productName')),
                  SearchableSelectOption(value: 'sku', label: tr(context, 'sku')),
                  SearchableSelectOption(value: 'category', label: tr(context, 'productCategory')),
                  SearchableSelectOption(value: 'price', label: tr(context, 'sellingPrice')),
                  SearchableSelectOption(value: 'stock', label: tr(context, 'stockOnHand')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _productSortBy = value;
                    _refreshProductPage(resetPage: true);
                  });
                },
              ),
            ),
            IconButton(
              tooltip: tr(context, _productSortAscending ? 'sortAscending' : 'sortDescending'),
              onPressed: () => setState(() {
                _productSortAscending = !_productSortAscending;
                _refreshProductPage(resetPage: true);
              }),
              icon: Icon(_productSortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded),
            ),
            SizedBox(
              width: 170,
              child: SearchableSelect<int>(
                id: 'products-page-size',
                label: tr(context, 'pageSize'),
                searchHint: tr(context, 'pageSize'),
                emptyLabel: tr(context, 'noSearchResults'),
                value: _productPageSize,
                options: [10, 25, 50, 100]
                    .map((size) => SearchableSelectOption(value: size, label: size.toString()))
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _productPageSize = value;
                    _refreshProductPage(resetPage: true);
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<ProductPage>(
          future: pageFuture,
          builder: (context, result) {
            if (result.connectionState == ConnectionState.waiting) {
              final skeletonColor =
                  Theme.of(context).colorScheme.surfaceContainerHighest;
              return Column(
                children: List.generate(
                  3,
                  (_) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: skeletonColor,
                            radius: 20,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  height: 12,
                                  width: 190,
                                  decoration: BoxDecoration(
                                    color: skeletonColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  height: 9,
                                  width: 260,
                                  decoration: BoxDecoration(
                                    color: skeletonColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            if (result.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(tr(context, 'productLoadFailed')),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _refreshProductPage()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(tr(context, 'retry')),
                      ),
                    ],
                  ),
                ),
              );
            }
            final page = result.data;
            if (page == null || page.products.isEmpty) {
              final isEmptyCatalog =
                  _productSearchController.text.trim().isEmpty;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      isEmptyCatalog
                          ? tr(context, 'noProducts')
                          : tr(context, 'noProductsMatch'),
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final product in page.products) _productCard(product),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        page.firstItemNumber.toString() +
                            '–' +
                            page.lastItemNumber.toString() +
                            ' / ' +
                            page.totalCount.toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: tr(context, 'previousPage'),
                      onPressed: page.pageIndex == 0
                          ? null
                          : () => setState(() {
                                _productPageIndex--;
                                _refreshProductPage();
                              }),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text(
                      (page.pageIndex + 1).toString() +
                          ' / ' +
                          page.pageCount.toString(),
                    ),
                    IconButton(
                      tooltip: tr(context, 'nextPage'),
                      onPressed: page.pageIndex + 1 >= page.pageCount
                          ? null
                          : () => setState(() {
                                _productPageIndex++;
                                _refreshProductPage();
                              }),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _productCard(Product product) => Card(
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage: product.imageBytes == null
                    ? null
                    : MemoryImage(product.imageBytes!),
                child: product.imageBytes == null
                    ? Icon(_productIconData(product.iconKey))
                    : null,
              ),
              title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                product.sku,
                if (product.barcode.isNotEmpty) product.barcode,
                if (product.category.isNotEmpty) product.category,
                tr(context, 'stockOnHand') + ': ' + product.stockQuantity.toString(),
              ].join(' · ')),
              trailing: IconButton(
                tooltip: tr(context, 'editProduct'),
                onPressed: () => _editProduct(product),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _money(product.unitPriceCents, widget.settings.currencyCode),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('product-stock-history-${product.sku}'),
                    tooltip: tr(context, 'stockHistory'),
                    onPressed: () => _showStockMovementHistory(product),
                    icon: const Icon(Icons.history_rounded),
                  ),
                  IconButton(
                    tooltip: tr(context, 'restock'),
                    onPressed: () => _adjustStock(product, 1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  IconButton(
                    tooltip: tr(context, 'reduceStock'),
                    onPressed: product.stockQuantity == 0
                        ? null
                        : () => _adjustStock(product, -1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _invoices(LedgerSnapshot snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'invoiceTitle'), style: _pageTitle),
          const SizedBox(height: 6),
          Text(tr(context, 'invoiceHint'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _selectedIndex = 8),
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: Text(tr(context, 'pointOfSale')),
                ),
                FilledButton.icon(
                  onPressed: () => _addInvoice(snapshot),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr(context, 'newInvoice')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (snapshot.invoices.isEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr(context, 'noInvoices')))))
          else
            for (final invoice in snapshot.invoices) _invoiceCard(invoice),
        ],
      );

  Widget _invoiceCard(SalesInvoice invoice) {
    final partial = invoice.status == 'issued' &&
        invoice.paidCents > 0 &&
        invoice.balanceDueCents > 0;
    final status = invoice.isReturned
        ? tr(context, 'invoiceReturned')
        : partial
            ? tr(context, 'partiallyPaid')
            : tr(context, invoice.status);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.request_quote_outlined)),
            title: Text('${invoice.number} · ${invoice.customerName}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${_shortDate(context, invoice.issueDate)} · $status\n'
              '${tr(context, 'paidAmount')}: ${_money(invoice.paidCents, widget.settings.currencyCode)} · '
              '${tr(context, 'balanceDue')}: ${_money(invoice.balanceDueCents, widget.settings.currencyCode)}',
            ),
            trailing: Text(_money(invoice.totalCents, widget.settings.currencyCode), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12, bottom: 8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                IconButton(
                  key: ValueKey('invoice-print-a4-' + invoice.number),
                  tooltip: tr(context, 'printInvoiceA4'),
                  onPressed: _printingInvoiceId == null
                      ? () => _printInvoice(invoice, InvoicePrintFormat.a4)
                      : null,
                  icon: _printingInvoiceId == invoice.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                ),
                IconButton(
                  key: ValueKey('invoice-print-thermal-' + invoice.number),
                  tooltip: tr(context, 'printThermalReceipt'),
                  onPressed: _printingInvoiceId == null
                      ? () => _printInvoice(invoice, InvoicePrintFormat.thermal80)
                      : null,
                  icon: _printingInvoiceId == invoice.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long_outlined),
                ),
                TextButton.icon(
                  key: ValueKey('invoice-payment-history-' + invoice.number),
                  onPressed: () => _showInvoicePaymentHistory(invoice),
                  icon: const Icon(Icons.history_rounded),
                  label: Text(tr(context, 'paymentHistory')),
                ),
                if (!invoice.isReturned && invoice.status != 'void')
                  OutlinedButton.icon(
                    key: ValueKey('invoice-return-' + invoice.number),
                    onPressed: () => _returnInvoice(invoice),
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: Text(tr(context, 'returnInvoice')),
                  ),
                if (!invoice.isReturned && invoice.status == 'issued' && invoice.balanceDueCents > 0)
                  FilledButton.tonalIcon(
                    onPressed: () => _recordInvoicePayment(invoice),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(tr(context, 'recordPayment')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsPage(LedgerSnapshot snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'settingsTitle'), style: _pageTitle),
          const SizedBox(height: 5),
          Text(tr(context, 'settingsSubtitle'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final navigation = _settingsNavigation(wide);
              final panel = _settingsPanel(snapshot);
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 244, child: navigation),
                    const SizedBox(width: 18),
                    Expanded(child: panel),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [navigation, const SizedBox(height: 12), panel],
              );
            },
          ),
        ],
      );

  Widget _settingsNavigation(bool wide) {
    final sections = <(String, IconData)>[
      ('settingsGeneral', Icons.tune_rounded),
      ('settingsBusiness', Icons.business_rounded),
      ('appearance', Icons.palette_outlined),
      ('languageRegion', Icons.translate_rounded),
      ('currencySettings', Icons.currency_exchange_rounded),
      ('accountingSettings', Icons.account_balance_rounded),
      ('salesSettings', Icons.point_of_sale_rounded),
      ('inventorySettings', Icons.inventory_2_outlined),
      ('smartImport', Icons.document_scanner_outlined),
      ('backup', Icons.backup_outlined),
      ('updates', Icons.system_update_alt_rounded),
    ];
    if (wide) {
      return Card(
        child: Column(
          children: [
            for (var index = 0; index < sections.length; index++)
              ListTile(
                dense: true,
                selected: _settingsSectionIndex == index,
                selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
                leading: Icon(sections[index].$2, size: 20),
                title: Text(tr(context, sections[index].$1), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => setState(() => _settingsSectionIndex = index),
              ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            ChoiceChip(
              avatar: Icon(sections[index].$2, size: 18),
              label: Text(tr(context, sections[index].$1)),
              selected: _settingsSectionIndex == index,
              onSelected: (_) => setState(() => _settingsSectionIndex = index),
            ),
          ],
        ],
      ),
    );
  }

  Widget _settingsCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 16),
                ...children,
              ],
            ],
          ),
        ),
      );

  Widget _settingsPanel(LedgerSnapshot snapshot) {
    switch (_settingsSectionIndex) {
      case 0:
        return _settingsCard(
          title: tr(context, 'settingsGeneral'),
          subtitle: tr(context, 'settingsGeneralHint'),
          children: [
            Text('${tr(context, 'entries')}: ${snapshot.entries.length} · ${tr(context, 'accounts')}: ${snapshot.accounts.length} · ${tr(context, 'products')}: ${snapshot.products.length}'),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _selectedIndex = 0),
              icon: const Icon(Icons.dashboard_outlined),
              label: Text(tr(context, 'openOverview')),
            ),
          ],
        );
      case 1:
        return _settingsCard(
          title: tr(context, 'settingsBusiness'),
          subtitle: tr(context, 'businessInfoHint'),
          children: [
            TextField(
              controller: _businessNameController,
              decoration: InputDecoration(labelText: tr(context, 'businessName')),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveBusinessName(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: const {'retail', 'wholesale', 'cafe', 'services', 'workshop', 'other'}
                      .contains(widget.settings.businessType)
                  ? widget.settings.businessType
                  : 'retail',
              decoration: InputDecoration(labelText: tr(context, 'setupBusinessType')),
              items: [
                for (final type in ['retail', 'wholesale', 'cafe', 'services', 'workshop', 'other'])
                  DropdownMenuItem(value: type, child: Text(tr(context, 'setupType_$type'))),
              ],
              onChanged: (value) {
                if (value != null) {
                  unawaited(widget.onSettingsChanged(widget.settings.copyWith(businessType: value)));
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: const {'IR', 'AE', 'TR', 'DE', 'GB', 'US', 'OTHER'}
                      .contains(widget.settings.countryCode)
                  ? widget.settings.countryCode
                  : 'OTHER',
              decoration: InputDecoration(labelText: tr(context, 'setupCountry')),
              items: [
                for (final country in ['IR', 'AE', 'TR', 'DE', 'GB', 'US', 'OTHER'])
                  DropdownMenuItem(value: country, child: Text(tr(context, 'setupCountry_$country'))),
              ],
              onChanged: (value) {
                if (value != null) {
                  unawaited(widget.onSettingsChanged(widget.settings.copyWith(countryCode: value)));
                }
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _saveBusinessName,
                icon: const Icon(Icons.save_outlined),
                label: Text(tr(context, 'saveSettings')),
              ),
            ),
          ],
        );
      case 2:
        return _settingsCard(
          title: tr(context, 'appearance'),
          subtitle: tr(context, 'appearanceHint'),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.settings.darkMode,
              title: Text(tr(context, 'darkMode')),
              subtitle: Text(tr(context, 'darkModeHint')),
              onChanged: (value) => widget.onSettingsChanged(widget.settings.copyWith(darkMode: value)),
            ),
          ],
        );
      case 3:
        return _settingsCard(
          title: tr(context, 'languageRegion'),
          subtitle: tr(context, 'languageRegionHint'),
          children: [
            SearchableSelect<String>(
              id: 'settings-language',
              label: tr(context, 'language'),
              searchHint: tr(context, 'searchLanguages'),
              emptyLabel: tr(context, 'noSearchResults'),
              value: widget.settings.languageCode,
              options: [
                SearchableSelectOption(value: 'en', label: tr(context, 'english')),
                SearchableSelectOption(value: 'fa', label: tr(context, 'persian')),
              ],
              onChanged: (value) {
                if (value != null) widget.onSettingsChanged(widget.settings.copyWith(languageCode: value));
              },
            ),
            const SizedBox(height: 8),
            Text(tr(context, 'languageRestart'), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      case 4:
        return _settingsCard(
          title: tr(context, 'currencySettings'),
          subtitle: tr(context, 'currencyHint'),
          children: [
            Text(
              tr(
                context,
                widget.settings.accountingCurrencyConfigured
                    ? 'currencyLockedHint'
                    : 'currencyNotConfiguredHint',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SearchableSelect<String>(
              id: 'settings-currency',
              label: tr(context, 'currency'),
              searchHint: tr(context, 'searchCurrencies'),
              emptyLabel: tr(context, 'noSearchResults'),
              value: widget.settings.currencyCode,
              options: const [
                SearchableSelectOption(value: 'USD', label: 'USD · US Dollar'),
                SearchableSelectOption(value: 'EUR', label: 'EUR · Euro'),
                SearchableSelectOption(value: 'GBP', label: 'GBP · Pound sterling'),
                SearchableSelectOption(value: 'CAD', label: 'CAD · Canadian dollar'),
                SearchableSelectOption(value: 'AUD', label: 'AUD · Australian dollar'),
                SearchableSelectOption(value: 'AED', label: 'AED · UAE dirham'),
                SearchableSelectOption(value: 'JPY', label: 'JPY · Japanese yen'),
                SearchableSelectOption(value: 'IRR', label: 'IRR · Iranian rial'),
                SearchableSelectOption(value: 'TOMAN', label: 'TOMAN · Iranian toman'),
              ],
              onChanged: (value) {
                if (value != null) {
                  unawaited(_chooseAccountingCurrency(value));
                }
              },
              autoOpen: widget.visualScenario == 'currency-popup',
            ),
            const SizedBox(height: 16),
            SearchableSelect<String>(
              id: 'settings-market-display-currency',
              label: tr(context, 'marketDisplayCurrency'),
              searchHint: tr(context, 'searchCurrencies'),
              emptyLabel: tr(context, 'noSearchResults'),
              value: widget.settings.marketDisplayCurrencyCode,
              options: const [
                SearchableSelectOption(value: 'TOMAN', label: 'TOMAN · Iranian toman'),
                SearchableSelectOption(value: 'IRR', label: 'IRR · Iranian rial'),
                SearchableSelectOption(value: 'USD', label: 'USD · US Dollar'),
                SearchableSelectOption(value: 'EUR', label: 'EUR · Euro'),
                SearchableSelectOption(value: 'AED', label: 'AED · UAE dirham'),
              ],
              onChanged: (value) {
                if (value != null) {
                  unawaited(widget.onSettingsChanged(
                    widget.settings.copyWith(marketDisplayCurrencyCode: value),
                  ));
                }
              },
            ),
            const SizedBox(height: 8),
            Text(tr(context, 'marketDisplayCurrencyHint'), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      case 5:
        return _settingsCard(
          title: tr(context, 'accountingSettings'),
          subtitle: tr(context, 'journalHint'),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _selectedIndex = 2),
                  icon: const Icon(Icons.account_tree_outlined),
                  label: Text(tr(context, 'chartTitle')),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _selectedIndex = 5),
                  icon: const Icon(Icons.analytics_outlined),
                  label: Text(tr(context, 'reports')),
                ),
              ],
            ),
          ],
        );
      case 6:
        return _settingsCard(
          title: tr(context, 'salesSettings'),
          subtitle: tr(context, 'invoiceHint'),
          children: [
            Text('${snapshot.invoices.length} ${tr(context, 'invoices').toLowerCase()}'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('settings-default-tax-rate'),
              controller: _taxRateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr(context, 'defaultTaxRate'),
                suffixText: '%',
              ),
              onSubmitted: (_) => _saveDefaultTaxRate(),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                key: const Key('save-default-tax-rate'),
                onPressed: _saveDefaultTaxRate,
                icon: const Icon(Icons.percent_rounded),
                label: Text(tr(context, 'saveTaxRate')),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _selectedIndex = 4),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(tr(context, 'openInvoices')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _selectedIndex = 8),
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: Text(tr(context, 'pointOfSale')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _addInvoice(snapshot),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr(context, 'newInvoice')),
                ),
              ],
            ),
          ],
        );
      case 7:
        return _settingsCard(
          title: tr(context, 'inventorySettings'),
          subtitle: tr(context, 'productsHint'),
          children: [
            Text('${snapshot.products.length} ${tr(context, 'products').toLowerCase()}'),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _selectedIndex = 3),
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(tr(context, 'openInventory')),
            ),
          ],
        );
      case 8:
        return _settingsCard(
          title: tr(context, 'smartImport'),
          subtitle: tr(context, 'smartImportDescription'),
          children: [
            Text(tr(context, 'ocrPrivacy'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _selectedIndex = 6),
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(tr(context, 'openSmartImport')),
            ),
          ],
        );
      case 9:
        return _settingsCard(
          title: tr(context, 'backup'),
          subtitle: tr(context, 'backupDescription'),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _exportBackup,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(tr(context, 'exportBackup')),
                ),
                OutlinedButton.icon(
                  onPressed: _restoringBackup ? null : _restoreBackup,
                  icon: _restoringBackup
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.restore_rounded),
                  label: Text(tr(context, 'restoreBackup')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(tr(context, 'localStorage'), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      case 10:
        return _settingsCard(
          title: tr(context, 'updates'),
          subtitle: _updateStatus(),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _checkingUpdates || _downloadingUpdate ? null : () => _checkForUpdates(),
                  icon: _checkingUpdates
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded),
                  label: Text(tr(context, 'checkForUpdates')),
                ),
                if (_availableUpdate != null)
                  FilledButton.icon(
                    onPressed: _downloadingUpdate ? null : _downloadAndInstallUpdate,
                    icon: _downloadingUpdate
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_rounded),
                    label: Text(_downloadingUpdate
                        ? tr(context, 'verifyingUpdate')
                        : tr(context, io.Platform.isAndroid ? 'downloadAndroidUpdate' : 'downloadAndInstall')),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(tr(context, 'updateInfo'), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _smartImport(LedgerSnapshot snapshot) => _SmartImportPanel(
        repository: widget.repository,
        accounts: snapshot.accounts,
        currencyCode: widget.settings.currencyCode,
        onImported: _reload,
      );

  Widget _more(LedgerSnapshot snapshot) => MoreToolsPage(
        marketDisplayCurrency: widget.settings.marketDisplayCurrencyCode,
        onMarketDisplayCurrencyChanged: (currencyCode) => widget.onSettingsChanged(
          widget.settings.copyWith(marketDisplayCurrencyCode: currencyCode),
        ),
        onOpenSmartImport: () => setState(() => _selectedIndex = 6),
      );

  Widget _overview(LedgerSnapshot snapshot, double availableWidth) {
    final width = availableWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(context, 'overviewTitle'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.7)),
        const SizedBox(height: 6),
        Text(tr(context, 'overviewSubtitle'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15)),
        const SizedBox(height: 24),
        if (_availableUpdate != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.system_update_alt_rounded),
              title: Text(tr(context, 'updateAvailable') + ' v' + _availableUpdate!.version),
              subtitle: Text(tr(context, io.Platform.isAndroid ? 'androidUpdateInfo' : 'updateVerified')),
              trailing: FilledButton(
                onPressed: _downloadAndInstallUpdate,
                child: Text(tr(context, io.Platform.isAndroid ? 'downloadAndroidUpdate' : 'installUpdate')),
              ),
            ),
          ),
        _WelcomeCard(
          entryCount: snapshot.entries.length,
          onAdd: () => _addEntry(snapshot),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(label: tr(context, 'assets'), value: _money(snapshot.assetsCents, widget.settings.currencyCode), icon: Icons.savings_outlined, tint: const Color(0xFFE4F3ED), width: _metricWidth(width)),
            _MetricCard(label: tr(context, 'liabilities'), value: _money(snapshot.liabilitiesCents, widget.settings.currencyCode), icon: Icons.credit_card_rounded, tint: const Color(0xFFFFF0DB), width: _metricWidth(width)),
            _MetricCard(label: tr(context, 'income'), value: _money(snapshot.incomeCents, widget.settings.currencyCode), icon: Icons.trending_up_rounded, tint: const Color(0xFFE5F0FF), width: _metricWidth(width)),
            _MetricCard(label: tr(context, 'netIncome'), value: _money(snapshot.netIncomeCents, widget.settings.currencyCode), icon: Icons.stacked_line_chart_rounded, tint: const Color(0xFFF0EAFE), width: _metricWidth(width)),
          ],
        ),
        const SizedBox(height: 25),
        _SectionHeading(
          title: tr(context, 'recentEntries'),
          actionLabel: tr(context, 'viewAll'),
          onAction: () => setState(() => _selectedIndex = 1),
        ),
        const SizedBox(height: 10),
        _EntryList(entries: snapshot.entries.take(5).toList(), emptyMessage: tr(context, 'firstEntry'), currencyCode: widget.settings.currencyCode),
      ],
    );
  }

  Widget _entries(LedgerSnapshot snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'journalTitle'), style: _pageTitle),
          const SizedBox(height: 6),
          Text(tr(context, 'journalHint'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: () => _addEntry(snapshot),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr(context, 'newEntry')),
            ),
          ),
          const SizedBox(height: 18),
          _EntryList(entries: snapshot.entries, emptyMessage: tr(context, 'noEntries'), currencyCode: widget.settings.currencyCode),
        ],
      );

  Widget _accounts(LedgerSnapshot snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'chartTitle'), style: _pageTitle),
          const SizedBox(height: 6),
          Text(tr(context, 'starterAccounts'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: _addAccount,
              icon: const Icon(Icons.add_rounded),
              label: Text(tr(context, 'newAccount')),
            ),
          ),
          const SizedBox(height: 20),
          ...AccountType.values.map((type) {
            final accounts = snapshot.accounts.where((account) => account.type == type).toList();
            if (accounts.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _AccountGroup(type: type, accounts: accounts, balances: snapshot.balancesByAccount, currencyCode: widget.settings.currencyCode),
            );
          }),
        ],
      );

  Widget _reports(LedgerSnapshot snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'reports'), style: _pageTitle),
          const SizedBox(height: 6),
          Text(tr(context, 'reportsHint'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          _ReportCard(
            title: tr(context, 'incomeStatement'),
            subtitle: tr(context, 'recordedIncomeExpenses'),
            currencyCode: widget.settings.currencyCode,
            rows: [
              (tr(context, 'income'), snapshot.incomeCents, false),
              (tr(context, 'expense'), snapshot.expensesCents, false),
              (tr(context, 'netIncome'), snapshot.netIncomeCents, true),
            ],
          ),
          const SizedBox(height: 16),
          _ReportCard(
            title: tr(context, 'balanceSummary'),
            subtitle: tr(context, 'postedBalances'),
            currencyCode: widget.settings.currencyCode,
            rows: [
              (tr(context, 'assetsBalance'), snapshot.assetsCents, false),
              (tr(context, 'liabilities'), snapshot.liabilitiesCents, false),
              (tr(context, 'equity'), snapshot.equityCents, false),
              (tr(context, 'netIncome'), snapshot.netIncomeCents, true),
            ],
          ),
        ],
      );

  static double _metricWidth(double width) => width >= 900 ? 248 : width >= 600 ? 210 : width - 40;

  static const _pageTitle = TextStyle(fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.6);
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog();

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  AccountType _type = AccountType.asset;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'newAccount')),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _code,
                decoration: InputDecoration(labelText: tr(context, 'accountCode')),
                validator: (value) => value == null ||
                        !RegExp(r'^[A-Za-z0-9._-]{1,20}$').hasMatch(value.trim())
                    ? 'Use 1–20 letters, digits, dots, dashes, or underscores.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: tr(context, 'accountName')),
                validator: (value) => value == null || value.trim().isEmpty ? 'Required.' : null,
              ),
              const SizedBox(height: 12),
              SearchableSelect<AccountType>(
                id: 'new-account-type',
                label: tr(context, 'selectAccountType'),
                searchHint: tr(context, 'searchAccounts'),
                emptyLabel: tr(context, 'noSearchResults'),
                value: _type,
                options: [
                  for (final type in AccountType.values)
                    SearchableSelectOption(
                      value: type,
                      label: tr(context, switch (type) {
                        AccountType.asset => 'asset',
                        AccountType.liability => 'liability',
                        AccountType.equity => 'equity',
                        AccountType.income => 'incomeType',
                        AccountType.expense => 'expense',
                      }),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context, AccountDraft(code: _code.text, name: _name.text, type: _type));
            },
            child: Text(tr(context, 'saveAccount')),
          ),
        ],
      );
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.accounts, required this.currencyCode});

  final List<Account> accounts;
  final String currencyCode;
  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  DateTime _date = DateTime.now();
  String? _debitId;
  String? _creditId;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _debitId = widget.accounts.isEmpty ? null : widget.accounts.first.id;
    _creditId = widget.accounts.length > 1 ? widget.accounts[1].id : null;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'newJournalEntry'), style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _description,
                    autofocus: true,
                    decoration: InputDecoration(labelText: tr(context, 'description'), hintText: tr(context, 'descriptionHint')),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Add a short description.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr(context, 'amount'), prefixText: '${widget.currencyCode} ', hintText: CurrencyDefinition.of(widget.currencyCode).formatInput(0)),
                    validator: (value) {
                      final cents = _parseCents(value ?? '', currencyCode: widget.currencyCode);
                      return cents == null || cents <= 0 ? 'Enter an amount greater than zero.' : null;
                    },
                  ),
                  const SizedBox(height: 14),
                  SearchableSelect<String>(
                    id: 'journal-debit-account',
                    label: tr(context, 'debitAccount'),
                    searchHint: tr(context, 'searchAccounts'),
                    emptyLabel: tr(context, 'noSearchResults'),
                    value: _debitId,
                    options: [
                      for (final account in widget.accounts)
                        SearchableSelectOption(
                          value: account.id,
                          label: '${account.code} · ${account.name}',
                          searchText: account.code,
                        ),
                    ],
                    onChanged: (value) => setState(() => _debitId = value),
                  ),
                  const SizedBox(height: 12),
                  SearchableSelect<String>(
                    id: 'journal-credit-account',
                    label: tr(context, 'creditAccount'),
                    searchHint: tr(context, 'searchAccounts'),
                    emptyLabel: tr(context, 'noSearchResults'),
                    value: _creditId,
                    options: [
                      for (final account in widget.accounts)
                        SearchableSelectOption(
                          value: account.id,
                          label: '${account.code} · ${account.name}',
                          searchText: account.code,
                        ),
                    ],
                    onChanged: (value) => setState(() => _creditId = value),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _chooseDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 17),
                      label: Text(_shortDate(context, _date)),
                    ),
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: Text(_formError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
          FilledButton(onPressed: _save, child: Text(tr(context, 'saveEntry'))),
        ],
      );

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _date = selected);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final draft = JournalDraft(
      date: _date,
      description: _description.text.trim(),
      amountCents: _parseCents(_amount.text, currencyCode: widget.currencyCode)!,
      debitAccountId: _debitId!,
      creditAccountId: _creditId!,
    );
    try {
      AccountingEngine.validateDraft(draft);
      Navigator.pop(context, draft);
    } on ArgumentError catch (error) {
      setState(() => _formError = error.message.toString());
    }
  }

  static int? _parseCents(
    String raw, {
    String currencyCode = 'USD',
  }) =>
      CurrencyDefinition.parseMinorUnits(
        raw,
        currencyCode: currencyCode,
      );
}

class _StockMovementHistoryDialog extends StatefulWidget {
  const _StockMovementHistoryDialog({
    required this.repository,
    required this.product,
  });

  final LedgerRepository repository;
  final Product product;

  @override
  State<_StockMovementHistoryDialog> createState() =>
      _StockMovementHistoryDialogState();
}

class _StockMovementHistoryDialogState
    extends State<_StockMovementHistoryDialog> {
  static const _pageSize = 25;
  late Future<StockMovementPage> _pageFuture;

  @override
  void initState() {
    super.initState();
    _pageFuture = _loadPage(0);
  }

  Future<StockMovementPage> _loadPage(int pageIndex) =>
      widget.repository.loadStockMovementPage(
        productId: widget.product.id,
        pageIndex: pageIndex,
        pageSize: _pageSize,
      );

  void _showPage(int pageIndex) {
    setState(() => _pageFuture = _loadPage(pageIndex));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${tr(context, 'stockMovementHistory')} · ${widget.product.name}'),
        content: SizedBox(
          width: 560,
          height: 400,
          child: FutureBuilder<StockMovementPage>(
            future: _pageFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    tr(context, 'stockMovementLoadFailed') +
                        ': ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final page = snapshot.data!;
              if (page.totalCount == 0) {
                return Center(child: Text(tr(context, 'noStockMovements')));
              }
              return Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: page.movements.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final movement = page.movements[index];
                        final isIncrease = movement.quantityDelta > 0;
                        final timestamp = movement.recordedAt
                            .toLocal()
                            .toString()
                            .split('.')
                            .first;
                        final label = switch (movement.movementType) {
                          'opening_balance' =>
                            tr(context, 'stockOpeningBalance'),
                          'adjustment' => tr(context, 'stockAdjustment'),
                          'sale' => tr(context, 'stockSale'),
                          'customer_return' =>
                            tr(context, 'stockCustomerReturn'),
                          'migration_balance' =>
                            tr(context, 'stockMigrationBalance'),
                          _ => movement.movementType,
                        };
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isIncrease
                                ? Icons.add_circle_outline
                                : Icons.remove_circle_outline,
                            color: isIncrease
                                ? Theme.of(context).colorScheme.tertiary
                                : Theme.of(context).colorScheme.error,
                          ),
                          title: Text(label),
                          subtitle: Text('${movement.description} · $timestamp'),
                          trailing: Text(
                            '${isIncrease ? '+' : ''}${movement.quantityDelta}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isIncrease
                                  ? Theme.of(context).colorScheme.tertiary
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        key: const Key('stock-history-previous-page'),
                        tooltip: tr(context, 'previousPage'),
                        onPressed: page.pageIndex == 0
                            ? null
                            : () => _showPage(page.pageIndex - 1),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text('${page.pageIndex + 1} / ${page.pageCount}'),
                      IconButton(
                        key: const Key('stock-history-next-page'),
                        tooltip: tr(context, 'nextPage'),
                        onPressed: page.pageIndex + 1 >= page.pageCount
                            ? null
                            : () => _showPage(page.pageIndex + 1),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, 'stockHistoryClose')),
          ),
        ],
      );
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({required this.currencyCode, this.product});

  final String currencyCode;
  final Product? product;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sku;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _barcode;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  late String _iconKey;
  Uint8List? _imageBytes;
  bool _imageChanged = false;
  bool _clearImage = false;
  String? _imageError;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _iconKey = product?.iconKey ?? 'inventory';
    _imageBytes = product?.imageBytes;
    _sku = TextEditingController(text: product?.sku ?? '');
    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    _category = TextEditingController(text: product?.category ?? '');
    _barcode = TextEditingController(text: product?.barcode ?? '');
    _price = TextEditingController(
      text: product == null
          ? ''
          : CurrencyDefinition.of(widget.currencyCode)
              .formatInput(product.unitPriceCents),
    );
    _cost = TextEditingController(
      text: product == null
          ? ''
          : CurrencyDefinition.of(widget.currencyCode)
              .formatInput(product.unitCostCents),
    );
    _stock = TextEditingController(text: product?.stockQuantity.toString() ?? '0');
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _description.dispose();
    _category.dispose();
    _barcode.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, widget.product == null ? 'newProduct' : 'editProduct')),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: _name, decoration: InputDecoration(labelText: tr(context, 'productName')), validator: _required),
                const SizedBox(height: 12),
                TextFormField(controller: _sku, decoration: InputDecoration(labelText: tr(context, 'sku')), validator: _required),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcode,
                  decoration: InputDecoration(
                    labelText: tr(context, 'productBarcode'),
                    suffixIcon: io.Platform.isAndroid
                        ? IconButton(
                            key: const Key('product-barcode-scan'),
                            tooltip: tr(context, 'scanBarcode'),
                            onPressed: _scanBarcode,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                          )
                        : null,
                  ),
                  validator: (value) => value != null && value.trim().contains(RegExp(r'\s'))
                      ? tr(context, 'barcodeNoWhitespace')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _category, decoration: InputDecoration(labelText: tr(context, 'productCategory'))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: _imageBytes == null
                          ? null
                          : MemoryImage(_imageBytes!),
                      child: _imageBytes == null
                          ? Icon(_productIconData(_iconKey))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          OutlinedButton.icon(
                            key: const Key('product-image-pick'),
                            onPressed: _chooseImage,
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: Text(
                              tr(
                                context,
                                _imageBytes == null
                                    ? 'selectProductImage'
                                    : 'replaceProductImage',
                              ),
                            ),
                          ),
                          if (_imageBytes != null)
                            TextButton.icon(
                              key: const Key('product-image-remove'),
                              onPressed: _removeImage,
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: Text(tr(context, 'removeProductImage')),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_imageError != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _imageError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('product-icon-select'),
                  initialValue: _iconKey,
                  decoration: InputDecoration(
                    labelText: tr(context, 'productIcon'),
                  ),
                  items: [
                    for (final iconKey in productIconKeys)
                      DropdownMenuItem(
                        value: iconKey,
                        child: Row(
                          children: [
                            Icon(_productIconData(iconKey)),
                            const SizedBox(width: 8),
                            Text(tr(context, _productIconLabelKey(iconKey))),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _iconKey = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: tr(context, 'productDescription')),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr(context, 'sellingPrice'),
                    prefixText: widget.currencyCode + ' ',
                  ),
                  validator: (value) {
                    final amount = CurrencyDefinition.parseMinorUnits(
                      value ?? '',
                      currencyCode: widget.currencyCode,
                    );
                    return amount == null || amount <= 0
                        ? 'Enter an amount greater than zero.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr(context, 'unitCost'),
                    prefixText: widget.currencyCode + ' ',
                  ),
                  validator: (value) {
                    final amount = value == null
                        ? null
                        : CurrencyDefinition.parseMinorUnits(
                            value,
                            currencyCode: widget.currencyCode,
                          );
                    return amount == null || amount < 0
                        ? 'Enter a non-negative amount.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _stock,
                  readOnly: widget.product != null,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr(context, 'stockOnHand'),
                    helperText: widget.product == null
                        ? null
                        : tr(context, 'productStockEditHint'),
                  ),
                  validator: (value) =>
                      int.tryParse(value ?? '') == null || int.parse(value!) < 0
                          ? 'Enter zero or more.'
                          : null,
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
          FilledButton(
            onPressed: _save,
            child: Text(tr(context, widget.product == null ? 'saveProduct' : 'updateProduct')),
          ),
        ],
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required.' : null;

  Future<void> _chooseImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        allowMultiple: false,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > productImageMaxUploadBytes) {
        setState(() => _imageError = tr(context, 'productImageTooLarge'));
        return;
      }
      final sourceBytes = file.bytes ??
          (file.path == null ? null : await io.File(file.path!).readAsBytes());
      if (sourceBytes == null || sourceBytes.isEmpty) {
        setState(() => _imageError = tr(context, 'productImageReadFailed'));
        return;
      }
      final codec = await ui.instantiateImageCodec(
        sourceBytes,
        targetWidth: 256,
        targetHeight: 256,
      );
      Uint8List? thumbnail;
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (data != null) {
            thumbnail = Uint8List.fromList(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (!mounted) return;
      if (thumbnail == null) {
        setState(() => _imageError = tr(context, 'productImageReadFailed'));
        return;
      }
      if (thumbnail.length > productImageMaxBytes) {
        setState(() => _imageError = tr(context, 'productImageProcessedTooLarge'));
        return;
      }
      setState(() {
        _imageBytes = thumbnail;
        _imageChanged = true;
        _clearImage = false;
        _imageError = null;
      });
    } on Object catch (_) {
      if (mounted) {
        setState(() => _imageError = tr(context, 'productImageReadFailed'));
      }
    }
  }

  Future<void> _scanBarcode() async {
    var accepted = false;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'scanBarcode')),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(dialogContext, 'barcodeScanHint'), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 264,
                  height: 214,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        onDetect: (capture) {
                          if (accepted) return;
                          final value = capture.barcodes
                              .map((barcode) => barcode.rawValue?.trim() ?? '')
                              .firstWhere((barcode) => barcode.isNotEmpty, orElse: () => '');
                          if (value.isEmpty) return;
                          accepted = true;
                          Navigator.of(dialogContext).pop(value);
                        },
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 204,
                            height: 104,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr(dialogContext, 'cancel')),
          ),
        ],
      ),
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() => _barcode.text = result);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(tr(context, 'barcodeReadSuccess'))),
    );
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _imageChanged = true;
      _clearImage = true;
      _imageError = null;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ProductDraft(
        sku: _sku.text,
        name: _name.text,
        description: _description.text,
        category: _category.text,
        barcode: _barcode.text,
        unitPriceCents: CurrencyDefinition.parseMinorUnits(
          _price.text,
          currencyCode: widget.currencyCode,
        )!,
        unitCostCents: CurrencyDefinition.parseMinorUnits(
          _cost.text,
          currencyCode: widget.currencyCode,
        )!,
        stockQuantity: int.parse(_stock.text),
        iconKey: _iconKey,
        imageBytes: _imageChanged && !_clearImage ? _imageBytes : null,
        clearImage: _clearImage,
      ),
    );
  }
}

class _InvoiceDialog extends StatefulWidget {
  const _InvoiceDialog({required this.products, required this.currencyCode});

  final List<Product> products;
  final String currencyCode;

  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final List<_InvoiceLineFields> _lines = [];
  String? _error;

  List<Product> get _availableProducts =>
      widget.products.where((product) => product.stockQuantity > 0).toList();

  @override
  void initState() {
    super.initState();
    if (_availableProducts.isNotEmpty) _lines.add(_InvoiceLineFields(_availableProducts.first.id));
  }

  @override
  void dispose() {
    _customer.dispose();
    _tax.dispose();
    for (final line in _lines) {
      line.quantity.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'newInvoice')),
        content: SizedBox(
          width: 520,
          height: 440,
          child: Form(
            key: _formKey,
            child: Column(children: [
              TextFormField(controller: _customer, decoration: InputDecoration(labelText: tr(context, 'customer')), validator: _required),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tax,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr(context, 'tax'), prefixText: '${widget.currencyCode} '),
                validator: (value) {
                  final cents = _EntryDialogState._parseCents(value ?? '', currencyCode: widget.currencyCode);
                  return cents == null ? 'Enter a non-negative amount.' : null;
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(children: [
                  for (var i = 0; i < _lines.length; i++) _lineEditor(i),
                  if (_lines.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(tr(context, 'invoiceNoProducts'))),
                  TextButton.icon(onPressed: _availableProducts.isEmpty ? null : _addLine, icon: const Icon(Icons.add), label: Text(tr(context, 'addLine'))),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                ]),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
          FilledButton(onPressed: _save, child: Text(tr(context, 'createInvoice'))),
        ],
      );

  Widget _lineEditor(int index) {
    final line = _lines[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: SearchableSelect<String>(
            id: 'invoice-product-$index',
            label: tr(context, 'products'),
            searchHint: tr(context, 'searchProducts'),
            emptyLabel: tr(context, 'noSearchResults'),
            value: line.productId,
            options: [
              for (final product in _availableProducts)
                SearchableSelectOption(
                  value: product.id,
                  label: '${product.name} · ${_money(product.unitPriceCents, widget.currencyCode)}',
                  searchText: product.sku,
                ),
            ],
            onChanged: (value) => setState(() => line.productId = value),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: line.quantity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr(context, 'quantity')),
            validator: (value) => int.tryParse(value ?? '') == null || int.parse(value!) <= 0 ? 'Use a positive quantity.' : null,
          ),
        ),
        IconButton(onPressed: _lines.length == 1 ? null : () => _removeLine(index), icon: const Icon(Icons.close_rounded)),
      ]),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required.' : null;

  void _addLine() => setState(() => _lines.add(_InvoiceLineFields(_availableProducts.first.id)));

  void _removeLine(int index) {
    final removed = _lines.removeAt(index);
    removed.quantity.dispose();
    setState(() {});
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty || _lines.any((line) => line.productId == null)) {
      setState(() => _error = 'Select a product for each line.');
      return;
    }
    Navigator.pop(
      context,
      InvoiceDraft(
        customerName: _customer.text.trim(),
        date: DateTime.now(),
        lines: [
          for (final line in _lines)
            InvoiceLineDraft(productId: line.productId!, quantity: int.parse(line.quantity.text)),
        ],
        taxCents: _EntryDialogState._parseCents(_tax.text, currencyCode: widget.currencyCode)!,
      ),
    );
  }
}

class _InvoiceReturnDialog extends StatefulWidget {
  const _InvoiceReturnDialog({
    required this.repository,
    required this.invoice,
    required this.currencyCode,
  });

  final LedgerRepository repository;
  final SalesInvoice invoice;
  final String currencyCode;

  @override
  State<_InvoiceReturnDialog> createState() => _InvoiceReturnDialogState();
}

class _InvoiceReturnDialogState extends State<_InvoiceReturnDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _reasonController = TextEditingController();
  late final Future<List<InvoiceReturnableLine>> _returnableLines;
  final Map<int, int> _selectedQuantities = {};
  String _refundMethod = 'cash';
  bool _selectionInitialized = false;

  @override
  void initState() {
    super.initState();
    _returnableLines =
        widget.repository.loadInvoiceReturnableLines(widget.invoice.id);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  int _estimatedValue(InvoiceReturnableLine line, int quantity) {
    if (quantity <= 0 || line.availableQuantity <= 0) return 0;
    final numerator =
        BigInt.from(line.remainingLineValueCents) * BigInt.from(quantity);
    final denominator = BigInt.from(line.availableQuantity);
    return ((numerator + BigInt.from(line.availableQuantity ~/ 2)) ~/
            denominator)
        .toInt();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<InvoiceReturnableLine>>(
        future: _returnableLines,
        builder: (context, result) {
          if (result.connectionState != ConnectionState.done) {
            return AlertDialog(
              title: Text(tr(context, 'returnInvoiceTitle')),
              content: const SizedBox(
                width: 520,
                height: 300,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          if (result.hasError || result.data == null) {
            return AlertDialog(
              title: Text(tr(context, 'returnInvoiceTitle')),
              content: SizedBox(
                width: 520,
                height: 180,
                child: Center(
                  child: Text(tr(context, 'paymentHistoryLoadFailed')),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr(context, 'cancel')),
                ),
              ],
            );
          }

          final lines = result.data!;
          if (!_selectionInitialized) {
            for (final line in lines) {
              _selectedQuantities[line.invoiceLineId] =
                  line.productAvailable ? line.availableQuantity : 0;
            }
            _selectionInitialized = true;
          }
          final selectedCount = _selectedQuantities.values.fold<int>(
            0,
            (sum, quantity) => sum + quantity,
          );
          var estimatedReturnValue = 0;
          for (final line in lines) {
            estimatedReturnValue += _estimatedValue(
              line,
              _selectedQuantities[line.invoiceLineId] ?? 0,
            );
          }
          final currency = CurrencyDefinition.of(widget.currencyCode);

          return AlertDialog(
            title: Text(tr(context, 'returnInvoiceTitle')),
            content: SizedBox(
              width: 520,
              height: 540,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr(context, 'returnInvoiceHint')),
                    const SizedBox(height: 10),
                    Text(
                      tr(context, 'returnSelectItems'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 212,
                      child: lines.isEmpty
                          ? Center(
                              child: Text(tr(context, 'returnNoItemsAvailable')),
                            )
                          : ListView.separated(
                              itemCount: lines.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final line = lines[index];
                                final selected =
                                    _selectedQuantities[line.invoiceLineId] ?? 0;
                                final canSelect = line.productAvailable &&
                                    line.availableQuantity > 0;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(line.description),
                                  subtitle: Text(
                                    canSelect
                                        ? tr(context, 'returnAvailableQuantity') +
                                            ': ' +
                                            line.availableQuantity.toString() +
                                            ' / ' +
                                            line.originalQuantity.toString()
                                        : tr(context, 'returnProductUnavailable'),
                                  ),
                                  trailing: !canSelect
                                      ? const Icon(Icons.warning_amber_rounded)
                                      : SizedBox(
                                          width: 132,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              IconButton(
                                                key: ValueKey(
                                                  'invoice-return-line-' +
                                                      line.invoiceLineId.toString() +
                                                      '-minus',
                                                ),
                                                tooltip: tr(context, 'decreaseQuantity'),
                                                onPressed: selected <= 0
                                                    ? null
                                                    : () => setState(() {
                                                          _selectedQuantities[
                                                              line.invoiceLineId] =
                                                              selected - 1;
                                                        }),
                                                icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                ),
                                              ),
                                              Text(
                                                selected.toString(),
                                                key: ValueKey(
                                                  'invoice-return-line-' +
                                                      line.invoiceLineId.toString() +
                                                      '-quantity',
                                                ),
                                              ),
                                              IconButton(
                                                key: ValueKey(
                                                  'invoice-return-line-' +
                                                      line.invoiceLineId.toString() +
                                                      '-plus',
                                                ),
                                                tooltip: tr(context, 'increaseQuantity'),
                                                onPressed: selected >=
                                                        line.availableQuantity
                                                    ? null
                                                    : () => setState(() {
                                                          _selectedQuantities[
                                                              line.invoiceLineId] =
                                                              selected + 1;
                                                        }),
                                                icon: const Icon(
                                                  Icons.add_circle_outline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(context, 'partialReturnValue') +
                          ': ' +
                          currency.formatMinorUnits(estimatedReturnValue),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr(context, 'returnCalculationNotice'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('invoice-return-reason'),
                      controller: _reasonController,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: tr(context, 'returnReason'),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? tr(context, 'returnReasonRequired')
                              : null,
                    ),
                    DropdownButtonFormField<String>(
                      key: const Key('invoice-return-refund-method'),
                      initialValue: _refundMethod,
                      decoration: InputDecoration(
                        labelText: tr(context, 'returnRefundMethod'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'cash',
                          child: Text(tr(context, 'posPaymentCash')),
                        ),
                        DropdownMenuItem(
                          value: 'bank_transfer',
                          child: Text(tr(context, 'posPaymentBankTransfer')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _refundMethod = value);
                        }
                      },
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
                key: ValueKey('invoice-return-confirm-' + widget.invoice.number),
                onPressed: lines.isEmpty || selectedCount <= 0
                    ? null
                    : () {
                        if (!_formKey.currentState!.validate()) return;
                        final selections = <InvoiceReturnLineDraft>[
                          for (final line in lines)
                            if ((_selectedQuantities[line.invoiceLineId] ?? 0) >
                                0)
                              InvoiceReturnLineDraft(
                                invoiceLineId: line.invoiceLineId,
                                quantity:
                                    _selectedQuantities[line.invoiceLineId]!,
                              ),
                        ];
                        Navigator.of(context).pop(
                          InvoiceReturnDraft(
                            invoiceId: widget.invoice.id,
                            date: DateTime.now(),
                            reason: _reasonController.text.trim(),
                            refundMethod: _refundMethod,
                            lines: selections,
                          ),
                        );
                      },
                child: Text(tr(context, 'returnSelectedItems')),
              ),
            ],
          );
        },
      );
}

class _InvoicePaymentHistoryDialog extends StatefulWidget {
  const _InvoicePaymentHistoryDialog({
    required this.repository,
    required this.invoice,
    required this.currencyCode,
  });

  final LedgerRepository repository;
  final SalesInvoice invoice;
  final String currencyCode;

  @override
  State<_InvoicePaymentHistoryDialog> createState() =>
      _InvoicePaymentHistoryDialogState();
}

class _InvoicePaymentHistoryDialogState
    extends State<_InvoicePaymentHistoryDialog> {
  late final Future<InvoicePaymentHistory?> _history;

  @override
  void initState() {
    super.initState();
    _history =
        widget.repository.loadInvoicePaymentHistory(widget.invoice.id);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'paymentHistoryTitle')),
        content: SizedBox(
          width: 520,
          height: 420,
          child: FutureBuilder<InvoicePaymentHistory?>(
            future: _history,
            builder: (context, result) {
              if (result.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (result.hasError) {
                return Center(
                  child: Text(tr(context, 'paymentHistoryLoadFailed')),
                );
              }
              final history = result.data;
              if (history == null) {
                return Center(
                  child: Text(tr(context, 'paymentHistoryLoadFailed')),
                );
              }
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      history.invoiceNumber + ' · ' + history.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'total') +
                          ': ' +
                          _money(
                            history.invoiceTotalCents,
                            widget.currencyCode,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(context, 'paidAmount') +
                          ': ' +
                          _money(history.recordedCents, widget.currencyCode),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(context, 'balanceDue') +
                          ': ' +
                          _money(
                            history.balanceDueCents,
                            widget.currencyCode,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (history.isReconciled
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.errorContainer)
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tr(
                          context,
                          history.isReconciled
                              ? 'invoicePaymentsReconciled'
                              : 'invoicePaymentsNeedReview',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (history.payments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(tr(context, 'noPaymentsRecorded')),
                        ),
                      )
                    else
                      for (final payment in history.payments) ...[
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _money(
                              payment.amountCents,
                              widget.currencyCode,
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            _shortDate(context, payment.paymentDate) +
                                ' · ' +
                                (payment.paymentMethod == 'bank_transfer'
                                    ? tr(context, 'posPaymentBankTransfer')
                                    : tr(context, 'posPaymentCash')),
                          ),
                          trailing: Tooltip(
                            message: tr(
                              context,
                              payment.ledgerPostingMatches
                                  ? 'paymentJournalMatched'
                                  : 'paymentJournalMissing',
                            ),
                            child: Icon(
                              payment.ledgerPostingMatches
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.warning_amber_rounded,
                              color: payment.ledgerPostingMatches
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            tr(
                              context,
                              payment.ledgerPostingMatches
                                  ? 'paymentJournalMatched'
                                  : 'paymentJournalMissing',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    for (final partialReturn in history.partialReturns) ...[
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          tr(context, 'partialReturnRecordedValue') +
                              ': ' +
                              _money(
                                partialReturn.returnValueCents,
                                widget.currencyCode,
                              ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          _shortDate(context, partialReturn.returnDate) +
                              ' · ' +
                              tr(context, 'partialReturnRefund') +
                              ': ' +
                              _money(
                                partialReturn.refundAmountCents,
                                widget.currencyCode,
                              ) +
                              '\n' +
                              tr(context, 'partialReturnReceivableCredit') +
                              ': ' +
                              _money(
                                partialReturn.receivableCreditCents,
                                widget.currencyCode,
                              ) +
                              '\n' +
                              partialReturn.reason,
                        ),
                        trailing: Icon(
                          partialReturn.ledgerPostingMatches
                              ? Icons.check_circle_outline_rounded
                              : Icons.warning_amber_rounded,
                          color: partialReturn.ledgerPostingMatches
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (history.returnRecord != null) ...[
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          tr(context, 'returnRefundAmount') +
                              ': ' +
                              _money(
                                history.returnRecord!.refundAmountCents,
                                widget.currencyCode,
                              ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          _shortDate(context, history.returnRecord!.returnDate) +
                              ' · ' +
                              (history.returnRecord!.refundMethod == 'bank_transfer'
                                  ? tr(context, 'posPaymentBankTransfer')
                                  : tr(context, 'posPaymentCash')) +
                              '\n' +
                              history.returnRecord!.reason,
                        ),
                        trailing: Icon(
                          history.returnRecord!.ledgerPostingMatches
                              ? Icons.check_circle_outline_rounded
                              : Icons.warning_amber_rounded,
                          color: history.returnRecord!.ledgerPostingMatches
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          tr(
                            context,
                            history.returnRecord!.ledgerPostingMatches
                                ? 'returnLedgerMatched'
                                : 'returnLedgerNeedReview',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, 'stockHistoryClose')),
          ),
        ],
      );
}

class _InvoicePaymentDialog extends StatefulWidget {
  const _InvoicePaymentDialog({
    required this.invoice,
    required this.currencyCode,
  });

  final SalesInvoice invoice;
  final String currencyCode;

  @override
  State<_InvoicePaymentDialog> createState() => _InvoicePaymentDialogState();
}

class _InvoicePaymentDialogState extends State<_InvoicePaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  DateTime _paymentDate = DateTime.now();
  String _paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: CurrencyDefinition.of(widget.currencyCode)
          .formatInput(widget.invoice.balanceDueCents),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'invoicePaymentTitle')),
        content: SizedBox(
          width: 380,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.invoice.number} · ${widget.invoice.customerName}'),
                const SizedBox(height: 8),
                Text(
                  '${tr(context, 'balanceDue')}: '
                  '${_money(widget.invoice.balanceDueCents, widget.currencyCode)}',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr(context, 'paymentAmount'),
                    prefixText: '${widget.currencyCode} ',
                  ),
                  validator: (value) {
                    final amountCents =
                        _EntryDialogState._parseCents(value ?? '', currencyCode: widget.currencyCode);
                    if (amountCents == null || amountCents <= 0) {
                      return tr(context, 'paymentAmountError');
                    }
                    if (amountCents > widget.invoice.balanceDueCents) {
                      return tr(context, 'paymentExceedsBalance');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: InputDecoration(
                    labelText: tr(context, 'posPaymentMethod'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'cash',
                      child: Text(tr(context, 'posPaymentCash')),
                    ),
                    DropdownMenuItem(
                      value: 'bank_transfer',
                      child: Text(tr(context, 'posPaymentBankTransfer')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _paymentMethod = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: _paymentDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null && mounted) {
                      setState(() => _paymentDate = selected);
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    '${tr(context, 'paymentDate')}: '
                    '${MaterialLocalizations.of(context).formatMediumDate(_paymentDate)}',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'cancel')),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(tr(context, 'savePayment')),
          ),
        ],
      );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      InvoicePaymentDraft(
        invoiceId: widget.invoice.id,
        amountCents: _EntryDialogState._parseCents(_amount.text, currencyCode: widget.currencyCode)!,
        date: _paymentDate,
        paymentMethod: _paymentMethod,
      ),
    );
  }
}

class _InvoiceLineFields {
  _InvoiceLineFields(this.productId);
  String? productId;
  final TextEditingController quantity = TextEditingController(text: '1');
}

enum _SmartImportMode { journal, products }

class _SmartImportPanel extends StatefulWidget {
  const _SmartImportPanel({
    required this.repository,
    required this.accounts,
    required this.currencyCode,
    required this.onImported,
  });

  final LedgerRepository repository;
  final List<Account> accounts;
  final String currencyCode;
  final Future<void> Function() onImported;

  @override
  State<_SmartImportPanel> createState() => _SmartImportPanelState();
}

class _SmartImportPanelState extends State<_SmartImportPanel> {
  final _csv = TextEditingController();
  final _recognizedText = TextEditingController();
  List<JournalDraft> _preview = [];
  ProductCsvImportResult? _productImport;
  Map<ProductImportField, int?> _productMapping = {};
  Set<String> _productConflicts = {};
  String? _error;
  bool _busy = false;
  bool _ocrBusy = false;
  bool _mappingConfigured = false;
  bool _xlsxBusy = false;
  _SmartImportMode _mode = _SmartImportMode.journal;

  @override
  void dispose() {
    _csv.dispose();
    _recognizedText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'smartImport'), style: _LedgerHomePageState._pageTitle),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'scanImage'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(tr(context, 'ocrPrivacy')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _ocrBusy ? null : _pickAndRecognize,
                  icon: _ocrBusy
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.document_scanner_outlined),
                  label: Text(_ocrBusy ? tr(context, 'ocrWorking') : tr(context, 'scanImage')),
                ),
                if (_recognizedText.text.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(tr(context, 'ocrComplete'), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text(tr(context, 'recognizedText'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _recognizedText,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(alignLabelWithHint: true),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () {
                        _csv.text = _recognizedText.text;
                        setState(() {
                          _error = null;
                          _clearPreviews();
                        });
                      },
                      icon: const Icon(Icons.content_copy_rounded),
                      label: Text(tr(context, 'useRecognizedText')),
                    ),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _mode == _SmartImportMode.journal
                      ? tr(context, 'smartImportTitle')
                      : tr(context, 'productCsvTitle'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _mode == _SmartImportMode.journal
                      ? tr(context, 'smartImportDescription')
                      : tr(context, 'productCsvHint'),
                ),
                const SizedBox(height: 14),
                SegmentedButton<_SmartImportMode>(
                  segments: [
                    ButtonSegment(
                      value: _SmartImportMode.journal,
                      icon: const Icon(Icons.account_balance_outlined),
                      label: Text(tr(context, 'journalTitle')),
                    ),
                    ButtonSegment(
                      value: _SmartImportMode.products,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(tr(context, 'productsTitle')),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _mode = selection.first;
                      _error = null;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _mode == _SmartImportMode.journal
                      ? tr(context, 'csvFormat')
                      : tr(context, 'productCsvColumns'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_mode == _SmartImportMode.products) ...[
                  const SizedBox(height: 6),
                  Text(
                    tr(context, 'xlsxProductImportHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _csv,
                  minLines: 5,
                  maxLines: 9,
                  onChanged: (_) {
                    if (_preview.isNotEmpty || _productImport != null || _mappingConfigured) {
                      setState(_clearPreviews);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: _mode == _SmartImportMode.journal
                        ? tr(context, 'pasteCsv')
                        : tr(context, 'pasteProductCsv'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _busy || _xlsxBusy ? null : _pickCsv,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(tr(context, 'chooseCsvFile')),
                  ),
                  if (_mode == _SmartImportMode.products)
                    OutlinedButton.icon(
                      onPressed: _busy || _xlsxBusy ? null : _pickXlsx,
                      icon: _xlsxBusy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.table_view_outlined),
                      label: Text(
                        _xlsxBusy ? tr(context, 'loadingXlsx') : tr(context, 'chooseXlsxFile'),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy || _xlsxBusy ? null : _previewImport,
                    icon: const Icon(Icons.manage_search),
                    label: Text(tr(context, 'previewImport')),
                  ),
                  if (_mode == _SmartImportMode.journal)
                    FilledButton.icon(
                      onPressed: _busy || _xlsxBusy || _preview.isEmpty ? null : _importJournal,
                      icon: const Icon(Icons.file_download_done),
                      label: Text(tr(context, 'importRows')),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _busy || _xlsxBusy || !_canImportProducts ? null : _importProducts,
                      icon: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.inventory_2_outlined),
                      label: Text(tr(context, 'importProducts')),
                    ),
                ]),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ]),
            ),
          ),
          if (_mode == _SmartImportMode.journal && _preview.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              tr(context, 'importPreview') + ' · ' + _preview.length.toString() + ' ' + tr(context, 'rowsReady'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _EntryList(entries: [
              for (var index = 0; index < _preview.length; index++)
                LedgerEntry(
                  id: 'preview_' + index.toString(),
                  date: _preview[index].date,
                  description: _preview[index].description,
                  amountCents: _preview[index].amountCents,
                  debitAccountName: _accountName(_preview[index].debitAccountId),
                  creditAccountName: _accountName(_preview[index].creditAccountId),
                ),
            ], emptyMessage: tr(context, 'noImportRows'), currencyCode: widget.currencyCode),
          ],
          if (_mode == _SmartImportMode.products && _productImport != null)
            _buildProductPreview(_productImport!),
        ],
      );

  bool get _canImportProducts {
    final result = _productImport;
    if (result == null || result.rows.isEmpty || result.invalidCount > 0) return false;
    for (final draft in result.validDrafts) {
      if (_productConflicts.contains('sku:' + draft.sku.toUpperCase()) ||
          (draft.barcode.isNotEmpty &&
              _productConflicts.contains('barcode:' + draft.barcode))) {
        return false;
      }
    }
    return true;
  }

  void _clearPreviews() {
    _preview = [];
    _productImport = null;
    _productConflicts = {};
    _productMapping = {};
    _mappingConfigured = false;
  }

  Widget _buildProductPreview(ProductCsvImportResult result) {
    final theme = Theme.of(context);
    final visibleRows = result.rows.take(20).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          tr(context, 'productImportPreview') + ' · ' +
              result.validCount.toString() + '/' + result.rows.length.toString(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'detectedColumns'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final field in ProductImportField.values)
                    SizedBox(
                      width: 220,
                      child: _productColumnPicker(field, result.headers),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (result.invalidCount > 0)
                Text(
                  tr(context, 'invalidProductRows') + ': ' + result.invalidCount.toString(),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (_productConflicts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tr(context, 'duplicateProductIdentifiers') + ': ' +
                        _productConflicts.length.toString(),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const Divider(height: 24),
              for (final row in visibleRows)
                _buildProductPreviewRow(row),
              if (result.rows.length > visibleRows.length)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr(context, 'showingFirstRows') + ' ' +
                        visibleRows.length.toString() + '/' + result.rows.length.toString(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _productColumnPicker(
    ProductImportField field,
    List<String> headers,
  ) {
    final selectedColumn = _productMapping[field];
    return SearchableSelect<int>(
      id: 'product-import-' + field.name,
      label: _productFieldLabel(field),
      searchHint: tr(context, 'search'),
      emptyLabel: tr(context, 'noSearchResults'),
      options: [
        SearchableSelectOption<int>(
          value: -1,
          label: tr(context, 'columnNotMapped'),
        ),
        for (var index = 0; index < headers.length; index++)
          SearchableSelectOption<int>(
            value: index,
            label: headers[index].isEmpty
                ? tr(context, 'unnamedColumn') + ' ' + (index + 1).toString()
                : headers[index],
            searchText: headers[index],
          ),
      ],
      value: selectedColumn ?? -1,
      maxPopupWidth: 340,
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _mappingConfigured = true;
          if (value < 0) {
            _productMapping.remove(field);
          } else {
            _productMapping[field] = value;
          }
          _productImport = null;
          _productConflicts = {};
          _error = null;
        });
      },
    );
  }

  String _productFieldLabel(ProductImportField field) {
    switch (field) {
      case ProductImportField.sku:
        return tr(context, 'sku');
      case ProductImportField.name:
        return tr(context, 'productName');
      case ProductImportField.sellingPrice:
        return tr(context, 'sellingPrice');
      case ProductImportField.unitCost:
        return tr(context, 'unitCost');
      case ProductImportField.stockQuantity:
        return tr(context, 'stockOnHand');
      case ProductImportField.description:
        return tr(context, 'productDescription');
      case ProductImportField.category:
        return tr(context, 'productCategory');
      case ProductImportField.barcode:
        return tr(context, 'productBarcode');
    }
  }

  Widget _buildProductPreviewRow(ProductCsvImportRow row) {
    final theme = Theme.of(context);
    final draft = row.draft;
    final existing = draft != null &&
        (_productConflicts.contains('sku:' + draft.sku.toUpperCase()) ||
            (draft.barcode.isNotEmpty &&
                _productConflicts.contains('barcode:' + draft.barcode)));
    final problem = row.issue ??
        (existing ? tr(context, 'duplicateProductIdentifiers') : null);
    final detail = draft == null
        ? tr(context, 'invalidProductRow')
        : draft.sku + ' · ' + draft.name + ' · ' +
            CurrencyDefinition.of(widget.currencyCode)
                .formatMinorUnits(draft.unitPriceCents);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        problem == null ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
        color: problem == null ? theme.colorScheme.primary : theme.colorScheme.error,
      ),
      title: Text(
        detail,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: problem == null
          ? Text(tr(context, 'csvRow') + ' ' + row.lineNumber.toString())
          : Text(
              tr(context, 'csvRow') + ' ' + row.lineNumber.toString() + ' · ' + problem,
              style: TextStyle(color: theme.colorScheme.error),
            ),
    );
  }

  String _accountName(String id) {
    for (final account in widget.accounts) {
      if (account.id == id) return account.name;
    }
    return id;
  }

  Future<void> _pickCsv() async {
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
      if (selected == null || selected.files.isEmpty || !mounted) return;
      final file = selected.files.single;
      final contents = file.bytes != null
          ? utf8.decode(file.bytes!, allowMalformed: false)
          : file.path == null
              ? null
              : await io.File(file.path!).readAsString();
      if (contents == null) {
        setState(() => _error = tr(context, 'fileCouldNotBeRead'));
        return;
      }
      setState(() {
        _csv.text = contents;
        _clearPreviews();
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = tr(context, 'fileCouldNotBeRead') + ': ' + error.toString());
    }
  }

  Future<void> _pickXlsx() async {
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (selected == null || selected.files.isEmpty || !mounted) return;
      final file = selected.files.single;
      if (file.size > ProductXlsxImport.maxFileBytes) {
        setState(() => _error = tr(context, 'xlsxFileTooLarge'));
        return;
      }
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _error = tr(context, 'fileCouldNotBeRead'));
        return;
      }
      setState(() {
        _xlsxBusy = true;
        _error = null;
        _clearPreviews();
      });
      final converted = await compute(ProductXlsxImport.toCsv, bytes);
      if (!mounted) return;
      setState(() {
        _csv.text = converted;
        _mode = _SmartImportMode.products;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormatException
              ? error.message.toString()
              : tr(context, 'fileCouldNotBeRead') + ': ' + error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _xlsxBusy = false);
    }
  }

  Future<void> _pickAndRecognize() async {
    final selected = await FilePicker.platform.pickFiles(type: FileType.image);
    if (selected == null || selected.files.isEmpty || !mounted) return;
    final imagePath = selected.files.single.path;
    if (imagePath == null) {
      setState(() => _error = tr(context, 'ocrFailed'));
      return;
    }

    setState(() {
      _ocrBusy = true;
      _error = null;
    });
    try {
      final text = await const OfflineOcrService().recognizeImage(imagePath);
      if (!mounted) return;
      setState(() {
        _recognizedText.text = text;
        if (text.trim().isEmpty) _error = tr(context, 'ocrEmpty');
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = tr(context, 'ocrFailed') + ': ' + error.toString());
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  void _previewImport() {
    if (_mode == _SmartImportMode.products) {
      unawaited(_previewProducts());
    } else {
      _previewJournalEntries();
    }
  }

  void _previewJournalEntries() {
    try {
      final drafts = <JournalDraft>[];
      final accountsByCode = {
        for (final account in widget.accounts) account.code.toLowerCase(): account,
      };
      final accountsById = {
        for (final account in widget.accounts) account.id.toLowerCase(): account,
      };
      final rows = _csv.text.split(RegExp(r'\r?\n'));
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index].trim();
        if (row.isEmpty) continue;
        if (index == 0 && row.toLowerCase().startsWith('date,')) continue;
        final fields = row.split(',').map((field) => field.trim()).toList();
        if (fields.length != 5) {
          throw FormatException('Row ' + (index + 1).toString() + ': expected five comma-separated fields.');
        }
        final date = DateTime.tryParse(fields[0]);
        final cents = _EntryDialogState._parseCents(
          fields[2],
          currencyCode: widget.currencyCode,
        );
        final debit = accountsByCode[fields[3].toLowerCase()] ??
            accountsById[fields[3].toLowerCase()];
        final credit = accountsByCode[fields[4].toLowerCase()] ??
            accountsById[fields[4].toLowerCase()];
        if (date == null ||
            cents == null ||
            cents <= 0 ||
            fields[1].isEmpty ||
            debit == null ||
            credit == null) {
          throw FormatException('Row ' + (index + 1).toString() + ': invalid date, description, amount, or account.');
        }
        drafts.add(JournalDraft(
          date: date,
          description: fields[1],
          amountCents: cents,
          debitAccountId: debit.id,
          creditAccountId: credit.id,
        ));
      }
      if (drafts.isEmpty) throw const FormatException('No valid rows to import.');
      setState(() {
        _preview = drafts;
        _productImport = null;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _preview = [];
        _error = error.message;
      });
    }
  }

  Future<void> _previewProducts() async {
    setState(() {
      _busy = true;
      _error = null;
      _productImport = null;
      _productConflicts = {};
    });
    try {
      Map<ProductImportField, int>? mapping;
      if (_mappingConfigured) {
        mapping = {
          for (final entry in _productMapping.entries)
            if (entry.value != null && entry.value! >= 0) entry.key: entry.value!,
        };
      }
      final result = ProductCsvImport.parse(
        _csv.text,
        currencyCode: widget.currencyCode,
        mapping: mapping,
      );
      final conflicts = await widget.repository.findProductImportConflicts(result.validDrafts);
      if (!mounted) return;
      setState(() {
        _productImport = result;
        _productConflicts = conflicts;
        _productMapping = {
          for (final entry in result.mapping.entries) entry.key: entry.value,
        };
        _mappingConfigured = true;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importJournal() async {
    setState(() => _busy = true);
    try {
      await widget.repository.createEntries(_preview);
      await widget.onImported();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_preview.length.toString() + ' ' + tr(context, 'imported')),
        ),
      );
      setState(() {
        _csv.clear();
        _clearPreviews();
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importProducts() async {
    final result = _productImport;
    if (result == null || !_canImportProducts) return;
    setState(() => _busy = true);
    try {
      final count = await widget.repository.importProducts(result.validDrafts);
      await widget.onImported();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count.toString() + ' ' + tr(context, 'productsImported')),
        ),
      );
      setState(() {
        _csv.clear();
        _clearPreviews();
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _LedgerSkeleton extends StatelessWidget {
  const _LedgerSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
      children: [
        const _SkeletonBlock(width: 280, height: 30),
        const SizedBox(height: 10),
        const _SkeletonBlock(width: 370, height: 16),
        const SizedBox(height: 24),
        Container(
          height: 112,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (var index = 0; index < 4; index++)
              SizedBox(
                width: 220,
                child: Container(
                  height: 105,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SkeletonBlock(width: 100, height: 13),
                      _SkeletonBlock(width: 130, height: 23),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 26),
        const _SkeletonBlock(width: 150, height: 20),
        const SizedBox(height: 12),
        for (var index = 0; index < 4; index++) ...[
          Container(
            height: 70,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(7),
        ),
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            const Text('The ledger could not be opened.'),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.entryCount, required this.onAdd});
  final int entryCount;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [Color(0xFF087E78), Color(0xFF075D5A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24,
          runSpacing: 18,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entryCount == 0 ? tr(context, 'steadyStart') : tr(context, 'ledgerCurrent'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(entryCount == 0 ? tr(context, 'firstEntryHint') : '$entryCount ${tr(context, 'entriesRecorded')}', style: const TextStyle(color: Color(0xFFD3F0E9), fontSize: 14)),
              ]),
            ),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(tr(context, 'recordEntry')),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0x99FFFFFF)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13)),
            ),
          ],
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon, required this.tint, required this.width});
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 34, height: 34, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: const Color(0xFF087E78), size: 18)),
              ]),
              const SizedBox(height: 13),
              FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.7))),
            ]),
          ),
        ),
      );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.actionLabel, required this.onAction});
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ]);
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.entries, required this.emptyMessage, required this.currencyCode});
  final List<LedgerEntry> entries;
  final String emptyMessage;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(emptyMessage, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))));
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < entries.length; i++) ...[
          _EntryTile(entry: entries[i], currencyCode: currencyCode),
          if (i != entries.length - 1) const Divider(height: 1, indent: 68),
        ],
      ]),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.currencyCode});
  final LedgerEntry entry;
  final String currencyCode;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFEAF3F0), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF087E78))),
        title: Text(entry.description, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_shortDate(context, entry.date)} · ${entry.debitAccountName} / ${entry.creditAccountName}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(_money(entry.amountCents, currencyCode), style: const TextStyle(fontWeight: FontWeight.w800)),
      );
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({required this.type, required this.accounts, required this.balances, required this.currencyCode});
  final AccountType type;
  final List<Account> accounts;
  final Map<String, int> balances;
  final String currencyCode;

  @override
  Widget build(BuildContext context) => Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 15, 17, 8),
            child: Text(
              tr(context, switch (type) {
                AccountType.asset => 'asset',
                AccountType.liability => 'liability',
                AccountType.equity => 'equity',
                AccountType.income => 'incomeType',
                AccountType.expense => 'expense',
              }),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          for (var i = 0; i < accounts.length; i++) ...[
            ListTile(
              dense: true,
              title: Text(accounts[i].name),
              subtitle: Text(accounts[i].code),
              trailing: Text(_money(balances[accounts[i].id] ?? 0, currencyCode), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (i != accounts.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ]),
      );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.title, required this.subtitle, required this.rows, required this.currencyCode});
  final String title;
  final String subtitle;
  final List<(String, int, bool)> rows;
  final String currencyCode;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 13),
            for (final row in rows) ...[
              if (row.$3) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(row.$1, style: TextStyle(fontWeight: row.$3 ? FontWeight.w800 : FontWeight.w500)),
                  Text(_money(row.$2, currencyCode), style: TextStyle(fontWeight: row.$3 ? FontWeight.w800 : FontWeight.w600)),
                ]),
              ),
            ],
          ]),
        ),
      );
}

String _money(int minorUnits, [String currencyCode = 'USD']) =>
    CurrencyDefinition.of(currencyCode).formatMinorUnits(minorUnits);

String _shortDate(BuildContext context, DateTime date) {
  if (AppStrings.of(context).isPersian) {
    const months = [
      '', 'ژانویه', 'فوریه', 'مارس', 'آوریل', 'مه', 'ژوئن', 'ژوئیه', 'اوت',
      'سپتامبر', 'اکتبر', 'نوامبر', 'دسامبر',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }
  return '${_month(date.month)} ${date.day}, ${date.year}';
}

String _month(int month) => const [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][month];
