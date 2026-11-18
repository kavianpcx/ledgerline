import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/data/ledger_database.dart';
import 'package:ledgerline/data/ledger_repository.dart';
import 'package:ledgerline/domain/accounting_engine.dart';
import 'package:ledgerline/domain/app_settings.dart';
import 'package:ledgerline/presentation/ledger_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings control center opens a bounded currency picker', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
      visualScenario: 'settings-light',
    ));
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Configure Ledgerline for the way your business works.')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(find.text('Business information'), findsOneWidget);
    expect(find.text('Accounting'), findsOneWidget);
    expect(find.text('Sales & POS'), findsOneWidget);
    expect(find.text('Inventory & warehouses'), findsOneWidget);

    await tester.tap(find.text('Display currency'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('searchable-select-trigger-settings-currency')),
    );
    await tester.pumpAndSettle();

    final popup = find.byKey(
      const ValueKey('searchable-select-popup-settings-currency'),
    );
    expect(popup, findsOneWidget);
    final rect = tester.getRect(popup);
    expect(rect.height, lessThanOrEqualTo(320));
    expect(rect.width, lessThanOrEqualTo(480));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(1200));
    expect(tester.takeException(), isNull);
  });
}

class _SnapshotRepository extends LedgerRepository {
  _SnapshotRepository(LedgerDatabase database, this.snapshot) : super(database);

  final LedgerSnapshot snapshot;

  @override
  Future<LedgerSnapshot> loadSnapshot() async => snapshot;
}
