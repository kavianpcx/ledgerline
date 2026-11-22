import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';

class PasscodeCredentials {
  const PasscodeCredentials({required this.salt, required this.hash});

  final String salt;
  final String hash;
}

class SecurityService {
  SecurityService({
    LocalAuthentication? localAuthentication,
    int iterations = _iterations,
  })  : _localAuthentication = localAuthentication ?? LocalAuthentication(),
        _kdf = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: iterations,
          bits: 256,
        );

  static const int minimumPasscodeLength = 6;
  static const int maximumPasscodeLength = 12;
  static const int _iterations = 150000;

  final LocalAuthentication _localAuthentication;
  final Pbkdf2 _kdf;

  static String? validatePasscode(String passcode) {
    if (!RegExp(r'^\d{6,12}$').hasMatch(passcode)) {
      return 'Passcode must contain 6 to 12 digits.';
    }
    return null;
  }

  Future<PasscodeCredentials> createPasscode(String passcode) async {
    final issue = validatePasscode(passcode);
    if (issue != null) throw ArgumentError(issue);
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final secret = await _kdf.deriveKeyFromPassword(
      password: passcode,
      nonce: salt,
    );
    final hash = await secret.extractBytes();
    return PasscodeCredentials(
      salt: base64UrlEncode(salt),
      hash: base64UrlEncode(hash),
    );
  }

  Future<bool> verifyPasscode({
    required String passcode,
    required String salt,
    required String expectedHash,
  }) async {
    if (validatePasscode(passcode) != null || salt.isEmpty || expectedHash.isEmpty) {
      return false;
    }
    try {
      final saltBytes = base64Url.decode(base64Url.normalize(salt));
      final expectedBytes = base64Url.decode(base64Url.normalize(expectedHash));
      final secret = await _kdf.deriveKeyFromPassword(
        password: passcode,
        nonce: saltBytes,
      );
      final actualBytes = await secret.extractBytes();
      if (actualBytes.length != expectedBytes.length) return false;
      var difference = 0;
      for (var index = 0; index < actualBytes.length; index++) {
        difference |= actualBytes[index] ^ expectedBytes[index];
      }
      return difference == 0;
    } on FormatException {
      return false;
    }
  }

  Future<bool> canUseBiometrics() async {
    if (!Platform.isAndroid) return false;
    try {
      if (!await _localAuthentication.isDeviceSupported()) return false;
      return (await _localAuthentication.getAvailableBiometrics()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  Future<bool> authenticateBiometrics({required String localizedReason}) async {
    if (!await canUseBiometrics()) return false;
    try {
      return await _localAuthentication.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on Object {
      return false;
    }
  }
}
