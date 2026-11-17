import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/ledger_database.dart';
import 'data/ledger_repository.dart';
import 'presentation/ledger_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final appSupport = await getApplicationSupportDirectory();
  final databaseDirectory = Directory(p.join(appSupport.path, 'ledgerline'));
  await databaseDirectory.create(recursive: true);

  final database = await LedgerDatabase.open(
    p.join(databaseDirectory.path, 'ledgerline.sqlite'),
  );
  final repository = LedgerRepository(database);
  await repository.initialize();
  final settings = await repository.loadAppSettings();

  runApp(LedgerApp(repository: repository, initialSettings: settings));
}
