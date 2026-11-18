import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
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
import '../domain/sales_invoice.dart';
import '../services/offline_ocr_service.dart';
import '../services/update_service.dart';
import 'app_strings.dart';
import 'widgets/searchable_select.dart';

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
  late final UpdateService _updateService;
  bool _checkingUpdates = false;
  bool _downloadingUpdate = false;
  bool _restoringBackup = false;
  bool _updateChecked = false;
  bool _updateCheckFailed = false;
  UpdateInfo? _availableUpdate;
  bool _sidebarExpandedAtMediumWidth = false;

  static const _destinations = <(String, IconData, IconData)>[
    ('overview', Icons.grid_view_rounded, Icons.grid_view_outlined),
    ('entries', Icons.receipt_long_rounded, Icons.receipt_long_outlined),
    ('accounts', Icons.account_tree_rounded, Icons.account_tree_outlined),
    ('products', Icons.inventory_2_rounded, Icons.inventory_2_outlined),
    ('invoices', Icons.request_quote_rounded, Icons.request_quote_outlined),
    ('reports', Icons.analytics_rounded, Icons.analytics_outlined),
    ('smartImport', Icons.file_upload_outlined, Icons.file_upload_outlined),
    ('settings', Icons.settings_rounded, Icons.settings_outlined),
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
      default:
        break;
    }
    _snapshot = widget.repository.loadSnapshot();
    _businessNameController = TextEditingController(text: widget.settings.businessName);
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
      final update = await _updateService.checkForUpdate(currentVersion: appVersion);
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

  Future<void> _reload() async {
    setState(() => _snapshot = widget.repository.loadSnapshot());
    await _snapshot;
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
          1 => 1,
          4 => 2,
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
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F2EE),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.account_balance_wallet_rounded,
                                color: Color(0xFF087E78), size: 18),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            tr(context, 'appName'),
                            style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
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
                      Text(tr(context, 'appName'),
                          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
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
                                child: Text(tr(context, 'currency')),
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
                    _selectedIndex = switch (index) { 0 => 0, 1 => 1, 2 => 4, _ => 8 };
                  }),
                  destinations: [
                    for (final index in [0, 1, 4, 8])
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
      _ => _more(snapshot),
    };
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
      children: [Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: content))],
    );
  }

  Widget _products(LedgerSnapshot snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'productsTitle'), style: _pageTitle),
          const SizedBox(height: 6),
          Text(tr(context, 'productsHint'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          if (snapshot.products.isEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr(context, 'noProducts')))))
          else
            for (final product in snapshot.products)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                    title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${product.sku} · ${tr(context, 'stockOnHand')}: ${product.stockQuantity}'),
                    trailing: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(_money(product.unitPriceCents, widget.settings.currencyCode), style: const TextStyle(fontWeight: FontWeight.w800)),
                        IconButton(tooltip: tr(context, 'restock'), onPressed: () => _adjustStock(product, 1), icon: const Icon(Icons.add_circle_outline)),
                        IconButton(tooltip: tr(context, 'reduceStock'), onPressed: product.stockQuantity == 0 ? null : () => _adjustStock(product, -1), icon: const Icon(Icons.remove_circle_outline)),
                      ],
                    ),
                  ),
                ),
              ),
        ],
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
            child: FilledButton.icon(
              onPressed: () => _addInvoice(snapshot),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr(context, 'newInvoice')),
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
    final status = partial
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
          if (invoice.status == 'issued' && invoice.balanceDueCents > 0)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 12, bottom: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => _recordInvoicePayment(invoice),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(tr(context, 'recordPayment')),
                ),
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
      ('currency', Icons.currency_exchange_rounded),
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
          title: tr(context, 'currency'),
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
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _selectedIndex = 4),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(tr(context, 'openInvoices')),
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
                    label: Text(_downloadingUpdate ? tr(context, 'verifyingUpdate') : tr(context, 'downloadAndInstall')),
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

  Widget _more(LedgerSnapshot snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, 'moreTitle'), style: _pageTitle),
          const SizedBox(height: 6),
          Text(tr(context, 'chooseFeature'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final index in [2, 3, 5, 6, 7])
                SizedBox(
                  width: 190,
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => setState(() => _selectedIndex = index),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(_destinations[index].$2, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 12),
                          Text(tr(context, _destinations[index].$1), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
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
              subtitle: Text(tr(context, 'updateVerified')),
              trailing: FilledButton(
                onPressed: _downloadAndInstallUpdate,
                child: Text(tr(context, 'installUpdate')),
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

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({required this.currencyCode});

  final String currencyCode;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _stock = TextEditingController(text: '0');

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'newProduct')),
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
                TextFormField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr(context, 'sellingPrice'), prefixText: '${widget.currencyCode} '), validator: (value) { final cents = _EntryDialogState._parseCents(value ?? '', currencyCode: widget.currencyCode); return cents == null || cents <= 0 ? 'Enter an amount greater than zero.' : null; }),
                const SizedBox(height: 12),
                TextFormField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr(context, 'unitCost'), prefixText: '${widget.currencyCode} '), validator: (value) => value == null || value.trim().isEmpty || _EntryDialogState._parseCents(value, currencyCode: widget.currencyCode) == null ? 'Enter a valid amount.' : null),
                const SizedBox(height: 12),
                TextFormField(controller: _stock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'stockOnHand')), validator: (value) => int.tryParse(value ?? '') == null || int.parse(value!) < 0 ? 'Enter zero or more.' : null),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
          FilledButton(onPressed: _save, child: Text(tr(context, 'saveProduct'))),
        ],
      );

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required.' : null;

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ProductDraft(
        sku: _sku.text,
        name: _name.text,
        unitPriceCents: _EntryDialogState._parseCents(_price.text, currencyCode: widget.currencyCode)!,
        unitCostCents: _EntryDialogState._parseCents(_cost.text, currencyCode: widget.currencyCode)!,
        stockQuantity: int.parse(_stock.text),
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
      ),
    );
  }
}

class _InvoiceLineFields {
  _InvoiceLineFields(this.productId);
  String? productId;
  final TextEditingController quantity = TextEditingController(text: '1');
}

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
  String? _error;
  bool _busy = false;
  bool _ocrBusy = false;

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
                        setState(() => _error = null);
                      },
                      icon: const Icon(Icons.content_copy_rounded),
                      label: Text(tr(context, 'useRecognizedText')),
                    ),
                  ),
                ],
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'smartImportTitle'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(tr(context, 'smartImportDescription')),
                const SizedBox(height: 8),
                Text(tr(context, 'csvFormat'), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 14),
                TextField(controller: _csv, minLines: 5, maxLines: 9, decoration: InputDecoration(labelText: tr(context, 'pasteCsv'), alignLabelWithHint: true)),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 12),
                Wrap(spacing: 10, children: [
                  OutlinedButton.icon(onPressed: _previewImport, icon: const Icon(Icons.manage_search), label: Text(tr(context, 'previewImport'))),
                  FilledButton.icon(onPressed: _busy || _preview.isEmpty ? null : _import, icon: const Icon(Icons.file_download_done), label: Text(tr(context, 'importRows'))),
                ]),
              ]),
            ),
          ),
          if (_preview.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('${tr(context, 'importPreview')} · ${_preview.length} ${tr(context, 'rowsReady')}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _EntryList(entries: [
              for (var index = 0; index < _preview.length; index++)
                LedgerEntry(
                  id: 'preview_$index',
                  date: _preview[index].date,
                  description: _preview[index].description,
                  amountCents: _preview[index].amountCents,
                  debitAccountName: _accountName(_preview[index].debitAccountId),
                  creditAccountName: _accountName(_preview[index].creditAccountId),
                ),
            ], emptyMessage: tr(context, 'noImportRows'), currencyCode: widget.currencyCode),
          ],
        ],
      );

  String _accountName(String id) {
    for (final account in widget.accounts) {
      if (account.id == id) return account.name;
    }
    return id;
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
      if (mounted) setState(() => _error = '${tr(context, 'ocrFailed')}: $error');
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  void _previewImport() {
    try {
      final drafts = <JournalDraft>[];
      final accountsByCode = {for (final account in widget.accounts) account.code.toLowerCase(): account};
      final accountsById = {for (final account in widget.accounts) account.id.toLowerCase(): account};
      final rows = _csv.text.split(RegExp(r'\r?\n'));
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index].trim();
        if (row.isEmpty) continue;
        if (index == 0 && row.toLowerCase().startsWith('date,')) continue;
        final fields = row.split(',').map((field) => field.trim()).toList();
        if (fields.length != 5) throw FormatException('Row ${index + 1}: expected five comma-separated fields.');
        final date = DateTime.tryParse(fields[0]);
        final cents = _EntryDialogState._parseCents(fields[2], currencyCode: widget.currencyCode);
        final debit = accountsByCode[fields[3].toLowerCase()] ?? accountsById[fields[3].toLowerCase()];
        final credit = accountsByCode[fields[4].toLowerCase()] ?? accountsById[fields[4].toLowerCase()];
        if (date == null || cents == null || cents <= 0 || fields[1].isEmpty || debit == null || credit == null) {
          throw FormatException('Row ${index + 1}: invalid date, description, amount, or account.');
        }
        drafts.add(JournalDraft(date: date, description: fields[1], amountCents: cents, debitAccountId: debit.id, creditAccountId: credit.id));
      }
      if (drafts.isEmpty) throw const FormatException('No valid rows to import.');
      setState(() {
        _preview = drafts;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _preview = [];
        _error = error.message;
      });
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      await widget.repository.createEntries(_preview);
      await widget.onImported();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_preview.length} ${tr(context, 'imported')}')));
      setState(() {
        _preview = [];
        _csv.clear();
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
