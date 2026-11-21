import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test('compares semantic release versions', () {
      expect(UpdateService.isVersionNewer('v0.2.0', '0.1.9'), isTrue);
      expect(UpdateService.isVersionNewer('0.2.0+2', '0.2.0+1'), isFalse);
      expect(UpdateService.isVersionNewer('0.1.9', '0.2.0'), isFalse);
      expect(UpdateService.isVersionNewer('preview', '0.1.0'), isFalse);
      expect(UpdateService.isVersionNewer('0.6.0-beta.2', '0.6.0-beta.1'), isTrue);
      expect(UpdateService.isVersionNewer('0.6.0', '0.6.0-beta.1'), isTrue);
      expect(UpdateService.isVersionNewer('0.6.0-beta.1', '0.6.0'), isFalse);
    });

    test('calculates SHA-256 for installer bytes', () {
      expect(
        UpdateService.sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });
}
