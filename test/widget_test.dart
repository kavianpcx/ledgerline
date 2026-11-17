import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/data/ledger_database.dart';
import 'package:ledgerline/data/ledger_repository.dart';
import 'package:ledgerline/domain/app_settings.dart';
import 'package:ledgerline/presentation/ledger_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the English ledger overview by default', (tester) async {
    final database = await LedgerDatabase.openInMemory();
    addTearDown(database.close);
    final repository = LedgerRepository(database);
    await repository.initialize();

    await tester.pumpWidget(LedgerApp(
      repository: repository,
      initialSettings: AppSettings.defaults,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Your books, at a glance'), findsOneWidget);
    expect(find.text('Total assets'), findsOneWidget);
  });
}
