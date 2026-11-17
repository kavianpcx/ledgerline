import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/data/ledger_database.dart';
import 'package:ledgerline/data/ledger_repository.dart';
import 'package:ledgerline/domain/accounting_engine.dart';
import 'package:ledgerline/domain/app_settings.dart';
import 'package:ledgerline/presentation/ledger_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the English ledger overview by default', (tester) async {
    final database = (await tester.runAsync(LedgerDatabase.openInMemory))!;
    addTearDown(() async {
      await tester.runAsync(database.close);
    });
    final snapshot = AccountingEngine.summarize(
      accounts: const [],
      entries: const [],
      activity: const [],
    );
    final repository = _SnapshotRepository(database, snapshot);

    await tester.pumpWidget(LedgerApp(
      repository: repository,
      initialSettings: AppSettings.defaults,
    ));
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Your books, at a glance').evaluate().isNotEmpty) break;
    }

    expect(find.text('Your books, at a glance'), findsOneWidget);
    expect(find.text('Total assets'), findsOneWidget);
  });
}

class _SnapshotRepository extends LedgerRepository {
  _SnapshotRepository(LedgerDatabase database, this.snapshot) : super(database);

  final LedgerSnapshot snapshot;

  @override
  Future<LedgerSnapshot> loadSnapshot() async => snapshot;
}
