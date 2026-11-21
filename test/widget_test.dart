import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
      initialSettings: AppSettings.defaults.copyWith(setupCompleted: true),
    ));
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Your books, at a glance').evaluate().isNotEmpty) break;
    }

    expect(find.text('Your books, at a glance'), findsOneWidget);
    expect(find.text('Total assets'), findsOneWidget);
  });

  testWidgets('first launch asks for business details and confirms the accounting currency', (tester) async {
    final database = (await tester.runAsync(LedgerDatabase.openInMemory))!;
    addTearDown(() async {
      await tester.runAsync(database.close);
    });
    final repository = LedgerRepository(database);

    await tester.pumpWidget(LedgerApp(
      repository: repository,
      initialSettings: AppSettings.defaults,
    ));
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Set up your business').evaluate().isNotEmpty) break;
    }

    expect(find.text('Set up your business'), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet_rounded), findsOneWidget);
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      final finishButton = tester.widget<FilledButton>(find.byKey(const Key('setup-finish')));
      if (finishButton.onPressed != null) break;
    }
    await tester.enterText(find.byType(TextField).first, 'Corner Shop');
    final finishFinder = find.byKey(const Key('setup-finish'));
    await tester.ensureVisible(finishFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(finishFinder).onPressed, isNotNull);
    await tester.tap(finishFinder);
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Your books, at a glance').evaluate().isNotEmpty) break;
    }

    expect(find.text('Your books, at a glance'), findsOneWidget);
    final settings = (await tester.runAsync(repository.loadAppSettings))!;
    expect(settings.businessName, 'Corner Shop');
    expect(settings.setupCompleted, isTrue);
    expect(settings.accountingCurrencyConfigured, isTrue);
  });
}

class _SnapshotRepository extends LedgerRepository {
  _SnapshotRepository(LedgerDatabase database, this.snapshot) : super(database);

  final LedgerSnapshot snapshot;

  @override
  Future<LedgerSnapshot> loadSnapshot() async => snapshot;
}
