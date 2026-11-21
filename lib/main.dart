import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite/sqflite.dart' as mobile_sqlite;

import 'data/ledger_database.dart';
import 'data/ledger_repository.dart';
import 'presentation/ledger_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  } else if (Platform.isAndroid || Platform.isIOS) {
    ffi.databaseFactory = mobile_sqlite.databaseFactory;
  }

  if (Platform.isWindows) {
    final window = WindowManager.instance.getCurrent();
    if (window != null) {
      window.title = 'Ledgerline';
      window.titleBarStyle = TitleBarStyle.hidden;
      window.isResizable = true;
      window.isMinimizable = true;
      window.isMaximizable = true;
      window.isClosable = true;
      window.minimumSize = const Size(860, 600).toNative();
      window.setSize(const Size(1440, 900).toNative(), false);
      window.center();
      window.show();
    }
  }

  final appSupport = await getApplicationSupportDirectory();
  final databaseDirectory = Directory(p.join(appSupport.path, 'ledgerline'));
  await databaseDirectory.create(recursive: true);

  final database = await LedgerDatabase.open(
    p.join(databaseDirectory.path, 'ledgerline.sqlite'),
  );
  final repository = LedgerRepository(database);
  await repository.initialize();
  final settings = await repository.loadAppSettings();
  final visualScenario = const String.fromEnvironment('LEDGERLINE_VISUAL_SCENARIO');

  runApp(LedgerApp(
    repository: repository,
    initialSettings: visualScenario.isEmpty ? settings : settings.copyWith(setupCompleted: true),
    visualScenario: visualScenario,
  ));
}
