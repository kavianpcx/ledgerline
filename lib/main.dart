import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite/sqflite.dart' as mobile_sqlite;

import 'data/ledger_database.dart';
import 'data/ledger_repository.dart';
import 'presentation/ledger_app.dart';

void _traceStartup(String stage) {
  try {
    File(p.join(Directory.systemTemp.path, 'ledgerline-startup.log'))
        .writeAsStringSync('$stage\n', mode: FileMode.append, flush: true);
  } on Object {
    // Startup diagnostics must never prevent the application from opening.
  }
}

Future<void> main() async {
  _traceStartup('main entered');
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    _traceStartup('Flutter error: ${details.exception.runtimeType}');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _traceStartup('Platform error: ${error.runtimeType}');
    return false;
  };
  _traceStartup('Flutter binding initialized');
  if (Platform.isWindows || Platform.isLinux) {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  } else if (Platform.isAndroid || Platform.isIOS) {
    ffi.databaseFactory = mobile_sqlite.databaseFactory;
  }

  Window? desktopWindow;
  if (Platform.isWindows) {
    desktopWindow = WindowManager.instance.getCurrent();
    if (desktopWindow != null) {
      desktopWindow.title = 'Ledgerline';
      desktopWindow.titleBarStyle = TitleBarStyle.hidden;
      desktopWindow.isResizable = true;
      desktopWindow.isMinimizable = true;
      desktopWindow.isMaximizable = true;
      desktopWindow.isClosable = true;
      desktopWindow.minimumSize = const Size(860, 600).toNative();
      desktopWindow.setSize(const Size(1440, 900).toNative(), false);
      desktopWindow.center();
    }
  }

  final visualScenario = const String.fromEnvironment('LEDGERLINE_VISUAL_SCENARIO');
  runApp(_LedgerStartup(visualScenario: visualScenario));
  _traceStartup('runApp returned');
  WidgetsBinding.instance.addPostFrameCallback((_) => _traceStartup('first Flutter frame completed'));
  if (desktopWindow != null) {
    desktopWindow.show();
    _traceStartup('desktop window show invoked');
  }
}

class _LedgerStartup extends StatefulWidget {
  const _LedgerStartup({required this.visualScenario});

  final String visualScenario;

  @override
  State<_LedgerStartup> createState() => _LedgerStartupState();
}

class _LedgerStartupState extends State<_LedgerStartup> {
  Widget? _application;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _traceStartup('startup widget initialized');
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _traceStartup('loading application support directory');
      final appSupport = await getApplicationSupportDirectory();
      final databaseDirectory = Directory(p.join(appSupport.path, 'ledgerline'));
      await databaseDirectory.create(recursive: true);
      _traceStartup('opening local database');
      final database = await LedgerDatabase.open(
        p.join(databaseDirectory.path, 'ledgerline.sqlite'),
      );
      final repository = LedgerRepository(database);
      await repository.initialize();
      _traceStartup('local database initialized');
      final settings = await repository.loadAppSettings();
      _traceStartup('settings loaded');
      if (!mounted) return;
      setState(() {
        _application = LedgerApp(
          repository: repository,
          initialSettings: widget.visualScenario.isEmpty
              ? settings
              : settings.copyWith(setupCompleted: true),
          visualScenario: widget.visualScenario,
        );
      });
    } catch (error) {
      _traceStartup('startup failed: ${error.runtimeType}');
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_application case final app?) {
      _traceStartup('LedgerApp replacement build');
      return app;
    }
    _traceStartup('startup progress screen build');
    return MaterialApp(
      title: 'Ledgerline',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F7F5),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: Color(0xFF087E78), size: 44),
                  const SizedBox(height: 16),
                  const Text('Ledgerline',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  if (_error == null) ...[
                    const CircularProgressIndicator(color: Color(0xFF087E78)),
                    const SizedBox(height: 12),
                    const Text('Preparing your local books…'),
                  ] else ...[
                    const Text('Ledgerline could not open its local data.'),
                    const SizedBox(height: 8),
                    Text('$_error', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _initialize, child: const Text('Retry')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
