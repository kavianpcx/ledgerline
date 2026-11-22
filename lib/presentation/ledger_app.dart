import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../data/ledger_repository.dart';
import '../domain/app_settings.dart';
import 'first_run_setup_page.dart';
import 'ledger_home_page.dart';
import 'security_lock_page.dart';
import '../services/security_service.dart';

class LedgerApp extends StatefulWidget {
  const LedgerApp({
    super.key,
    required this.repository,
    required this.initialSettings,
    this.visualScenario = '',
  });

  final LedgerRepository repository;
  final AppSettings initialSettings;
  final String visualScenario;

  @override
  State<LedgerApp> createState() => _LedgerAppState();
}

class _LedgerAppState extends State<LedgerApp> with WidgetsBindingObserver {
  late AppSettings _settings;
  late bool _unlocked;
  final _securityService = SecurityService();

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _unlocked = !widget.initialSettings.securityLockEnabled;
    WidgetsBinding.instance.addObserver(this);
    if (widget.visualScenario == 'settings-light') {
      _settings = _settings.copyWith(darkMode: false);
    } else if (widget.visualScenario == 'settings-dark') {
      _settings = _settings.copyWith(darkMode: true);
    } else if (widget.visualScenario == 'settings-fa') {
      _settings = _settings.copyWith(languageCode: 'fa', darkMode: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isAndroid &&
        (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) &&
        _settings.securityLockEnabled &&
        _unlocked) {
      setState(() => _unlocked = false);
    }
  }

  Future<void> _saveSettings(AppSettings settings) async {
    await widget.repository.saveAppSettings(settings);
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _completeFirstRun(
    AppSettings settings, {
    required bool confirmExistingAmounts,
  }) async {
    await widget.repository.configureAccountingCurrency(
      currencyCode: settings.currencyCode,
      confirmExistingAmounts: confirmExistingAmounts,
    );
    final completed = settings.copyWith(
      accountingCurrencyConfigured: true,
      setupCompleted: true,
    );
    _unlocked = true;
    await _saveSettings(completed);
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF087E78);
    const lightInk = Color(0xFF172A35);
    final lightScheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.light,
      surface: const Color(0xFFF5F7F5),
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF54C4B5),
      brightness: Brightness.dark,
      surface: const Color(0xFF151B1E),
    );

    return MaterialApp(
      title: 'Ledgerline',
      debugShowCheckedModeBanner: false,
      locale: Locale(_settings.languageCode),
      supportedLocales: const [Locale('en'), Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: _settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        scaffoldBackgroundColor: const Color(0xFFF5F7F5),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: lightInk,
              displayColor: lightInk,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7F5),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE5EBE8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAF9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE5E1)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: const Color(0xFF111719),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111719),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1D2629),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF2C3A3D)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF202A2D),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF39484A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF39484A)),
          ),
        ),
      ),
      home: !_settings.setupCompleted
          ? FirstRunSetupPage(
              repository: widget.repository,
              initialSettings: _settings,
              onComplete: _completeFirstRun,
            )
          : _settings.securityLockEnabled && !_unlocked
              ? SecurityLockPage(
                  settings: _settings,
                  securityService: _securityService,
                  onUnlocked: () => setState(() => _unlocked = true),
                )
              : LedgerHomePage(
                  repository: widget.repository,
                  settings: _settings,
                  onSettingsChanged: _saveSettings,
                  visualScenario: widget.visualScenario,
                )
    );
  }
}
