import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ledgerline/domain/app_settings.dart';
import 'package:ledgerline/presentation/security_lock_page.dart';
import 'package:ledgerline/services/security_service.dart';

void main() {
  testWidgets('protected workspace stays locked until passcode verification succeeds', (tester) async {
    final security = _PasscodeStub();
    var unlocked = false;
    final settings = AppSettings.defaults.copyWith(
      businessName: 'Northstar Books',
      setupCompleted: true,
      securityLockEnabled: true,
      securitySalt: 'test-salt',
      securityHash: 'test-hash',
    );

    await tester.pumpWidget(MaterialApp(
      home: SecurityLockPage(
        settings: settings,
        securityService: security,
        onUnlocked: () => unlocked = true,
      ),
    ));

    expect(find.text('Unlock Ledgerline'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('security-lock-passcode')), '482614');
    await tester.tap(find.byKey(const Key('security-lock-unlock')));
    await tester.pump();
    expect(unlocked, isFalse);

    await tester.enterText(find.byKey(const Key('security-lock-passcode')), '482615');
    await tester.tap(find.byKey(const Key('security-lock-unlock')));
    await tester.pump();

    expect(unlocked, isTrue);
  });
}

class _PasscodeStub extends SecurityService {
  @override
  Future<bool> verifyPasscode({
    required String passcode,
    required String salt,
    required String expectedHash,
  }) async =>
      passcode == '482615';
}
