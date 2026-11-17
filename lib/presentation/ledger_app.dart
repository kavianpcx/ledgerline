import 'package:material_ui/material_ui.dart';

import '../data/ledger_repository.dart';
import '../domain/app_settings.dart';
import 'ledger_home_page.dart';

class LedgerApp extends StatefulWidget {
  const LedgerApp({
    super.key,
    required this.repository,
    required this.initialSettings,
  });

  final LedgerRepository repository;
  final AppSettings initialSettings;

  @override
  State<LedgerApp> createState() => _LedgerAppState();
}

class _LedgerAppState extends State<LedgerApp> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  Future<void> _saveSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    await widget.repository.saveAppSettings(settings);
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
      home: LedgerHomePage(
        repository: widget.repository,
        settings: _settings,
        onSettingsChanged: _saveSettings,
      ),
    );
  }
}
