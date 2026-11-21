import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/services/security_service.dart';

void main() {
  group('SecurityService', () {
    test('requires a 6 to 12 digit passcode', () {
      expect(SecurityService.validatePasscode('12345'), isNotNull);
      expect(SecurityService.validatePasscode('123456'), isNull);
      expect(SecurityService.validatePasscode('1234567890123'), isNotNull);
      expect(SecurityService.validatePasscode('12ab56'), isNotNull);
    });

    test('stores a salted verifier instead of the passcode and verifies it', () async {
      final service = SecurityService(iterations: 1000);
      final credentials = await service.createPasscode('482615');

      expect(credentials.salt, isNotEmpty);
      expect(credentials.hash, isNot('482615'));
      expect(await service.verifyPasscode(
        passcode: '482615',
        salt: credentials.salt,
        expectedHash: credentials.hash,
      ), isTrue);
      expect(await service.verifyPasscode(
        passcode: '482614',
        salt: credentials.salt,
        expectedHash: credentials.hash,
      ), isFalse);
    });
  });
}
