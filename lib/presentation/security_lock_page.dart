import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/app_settings.dart';
import '../services/security_service.dart';
import 'app_strings.dart';

class SecurityLockPage extends StatefulWidget {
  const SecurityLockPage({
    super.key,
    required this.settings,
    required this.securityService,
    required this.onUnlocked,
  });

  final AppSettings settings;
  final SecurityService securityService;
  final VoidCallback onUnlocked;

  @override
  State<SecurityLockPage> createState() => _SecurityLockPageState();
}

class _SecurityLockPageState extends State<SecurityLockPage> {
  final _passcode = TextEditingController();
  String? _error;
  bool _busy = false;
  int _failedAttempts = 0;
  DateTime? _retryAfter;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    if (widget.settings.biometricUnlockEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlockWithBiometrics());
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _passcode.dispose();
    super.dispose();
  }

  Future<void> _unlockWithPasscode() async {
    if (_busy) return;
    final retryAfter = _retryAfter;
    if (retryAfter != null && retryAfter.isAfter(DateTime.now())) {
      setState(() => _error = tr(context, 'securityRetryDelay'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final valid = await widget.securityService.verifyPasscode(
      passcode: _passcode.text,
      salt: widget.settings.securitySalt,
      expectedHash: widget.settings.securityHash,
    );
    if (!mounted) return;
    if (valid) {
      widget.onUnlocked();
      return;
    }
    _failedAttempts++;
    if (_failedAttempts >= 5) {
      _retryAfter = DateTime.now().add(const Duration(seconds: 15));
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 15), () {
        if (mounted) setState(() => _retryAfter = null);
      });
      _failedAttempts = 0;
    }
    setState(() {
      _busy = false;
      _error = tr(context, 'securityWrongPasscode');
      _passcode.clear();
    });
  }

  Future<void> _unlockWithBiometrics() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final authenticated = await widget.securityService.authenticateBiometrics(
      localizedReason: tr(context, 'securityBiometricPrompt'),
    );
    if (!mounted) return;
    if (authenticated) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _busy = false;
      _error = tr(context, 'securityBiometricFailed');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 14),
                      Text(
                        tr(context, 'securityLockTitle'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.settings.businessName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const Key('security-lock-passcode'),
                        controller: _passcode,
                        autofocus: true,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        maxLength: SecurityService.maximumPasscodeLength,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: tr(context, 'securityPasscode'),
                          counterText: '',
                        ),
                        onSubmitted: (_) => _unlockWithPasscode(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('security-lock-unlock'),
                        onPressed: _busy ? null : _unlockWithPasscode,
                        icon: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.lock_open_rounded),
                        label: Text(tr(context, 'securityUnlock')),
                      ),
                      if (widget.settings.biometricUnlockEnabled) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('security-lock-biometrics'),
                          onPressed: _busy ? null : _unlockWithBiometrics,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: Text(tr(context, 'securityUseBiometrics')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
