import 'package:material_ui/material_ui.dart';

import '../data/ledger_repository.dart';
import '../domain/app_settings.dart';
import 'app_strings.dart';

class FirstRunSetupPage extends StatefulWidget {
  const FirstRunSetupPage({
    super.key,
    required this.repository,
    required this.initialSettings,
    required this.onComplete,
  });

  final LedgerRepository repository;
  final AppSettings initialSettings;
  final Future<void> Function(
    AppSettings settings, {
    required bool confirmExistingAmounts,
  }) onComplete;

  @override
  State<FirstRunSetupPage> createState() => _FirstRunSetupPageState();
}

class _FirstRunSetupPageState extends State<FirstRunSetupPage> {
  late final TextEditingController _businessName;
  late String _businessType;
  late String _countryCode;
  late String _currencyCode;
  late String _languageCode;
  bool _checkingLegacyRecords = true;
  bool _legacyCheckFailed = false;
  bool _hasLegacyRecords = false;
  bool _confirmedLegacyCurrency = false;
  bool _saving = false;
  String? _error;

  static const _businessTypes = <String>[
    'retail',
    'wholesale',
    'cafe',
    'services',
    'workshop',
    'other',
  ];

  static const _countries = <(String, String)>[
    ('IR', 'Iran'),
    ('AE', 'United Arab Emirates'),
    ('TR', 'Türkiye'),
    ('DE', 'Germany'),
    ('GB', 'United Kingdom'),
    ('US', 'United States'),
    ('OTHER', 'Other'),
  ];

  static const _currencies = <(String, String)>[
    ('USD', 'USD · US Dollar'),
    ('EUR', 'EUR · Euro'),
    ('GBP', 'GBP · Pound sterling'),
    ('AED', 'AED · UAE dirham'),
    ('IRR', 'IRR · Iranian rial'),
    ('TOMAN', 'TOMAN · Iranian toman'),
  ];

  @override
  void initState() {
    super.initState();
    _businessName = TextEditingController(text: widget.initialSettings.businessName);
    _businessType = _businessTypes.contains(widget.initialSettings.businessType)
        ? widget.initialSettings.businessType
        : 'retail';
    _countryCode = _countries.any((country) => country.$1 == widget.initialSettings.countryCode)
        ? widget.initialSettings.countryCode
        : 'IR';
    _currencyCode = _currencies.any((currency) => currency.$1 == widget.initialSettings.currencyCode)
        ? widget.initialSettings.currencyCode
        : 'USD';
    _languageCode = widget.initialSettings.languageCode;
    _checkLegacyRecords();
  }

  @override
  void dispose() {
    _businessName.dispose();
    super.dispose();
  }

  Future<void> _checkLegacyRecords({bool retry = false}) async {
    if (retry && mounted) {
      setState(() {
        _checkingLegacyRecords = true;
        _legacyCheckFailed = false;
        _error = null;
      });
    }
    try {
      final hasRecords = await widget.repository.hasMonetaryRecords();
      if (!mounted) return;
      setState(() {
        _hasLegacyRecords = hasRecords && !widget.initialSettings.accountingCurrencyConfigured;
        _checkingLegacyRecords = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingLegacyRecords = false;
        _legacyCheckFailed = true;
        _error = tr(context, 'setupCouldNotCheckRecords') + ': $error';
      });
    }
  }

  Future<void> _finish() async {
    if (_saving || _checkingLegacyRecords || _legacyCheckFailed) return;
    final name = _businessName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = tr(context, 'setupBusinessNameRequired'));
      return;
    }
    if (_hasLegacyRecords && !_confirmedLegacyCurrency) {
      setState(() => _error = tr(context, 'setupConfirmLegacyCurrency'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onComplete(
        widget.initialSettings.copyWith(
          businessName: name,
          businessType: _businessType,
          countryCode: _countryCode,
          currencyCode: _currencyCode,
          languageCode: _languageCode,
          accountingCurrencyConfigured: true,
          setupCompleted: true,
        ),
        confirmExistingAmounts: _confirmedLegacyCurrency,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = '${tr(context, 'setupCouldNotSave')}: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
              shrinkWrap: true,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.account_balance_wallet_rounded, color: colors.primary, size: 28),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  tr(context, 'setupWelcome'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context, 'setupIntro'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 22),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _businessName,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(labelText: tr(context, 'businessName')),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _businessType,
                          decoration: InputDecoration(labelText: tr(context, 'setupBusinessType')),
                          items: [
                            for (final type in _businessTypes)
                              DropdownMenuItem(value: type, child: Text(tr(context, 'setupType_$type'))),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _businessType = value);
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _countryCode,
                          decoration: InputDecoration(labelText: tr(context, 'setupCountry')),
                          items: [
                            for (final country in _countries)
                              DropdownMenuItem(value: country.$1, child: Text(tr(context, 'setupCountry_${country.$1}'))),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _countryCode = value);
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _currencyCode,
                          decoration: InputDecoration(labelText: tr(context, 'currency')),
                          items: [
                            for (final currency in _currencies)
                              DropdownMenuItem(value: currency.$1, child: Text(currency.$2)),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _currencyCode = value);
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _languageCode,
                          decoration: InputDecoration(labelText: tr(context, 'language')),
                          items: [
                            DropdownMenuItem(value: 'en', child: Text(tr(context, 'english'))),
                            DropdownMenuItem(value: 'fa', child: Text(tr(context, 'persian'))),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _languageCode = value);
                          },
                        ),
                        if (_checkingLegacyRecords) ...[
                          const SizedBox(height: 14),
                          const LinearProgressIndicator(),
                        ],
                        if (_hasLegacyRecords) ...[
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _confirmedLegacyCurrency,
                            onChanged: (value) => setState(() {
                              _confirmedLegacyCurrency = value ?? false;
                              _error = null;
                            }),
                            title: Text(tr(context, 'setupLegacyConfirmation')),
                            subtitle: Text(tr(context, 'setupLegacyHint')),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(color: colors.error)),
                          if (_legacyCheckFailed)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                onPressed: _checkingLegacyRecords ? null : () => _checkLegacyRecords(retry: true),
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(tr(context, 'retry')),
                              ),
                            ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          key: const Key('setup-finish'),
                          onPressed: _saving || _checkingLegacyRecords || _legacyCheckFailed ? null : _finish,
                          icon: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.arrow_forward_rounded),
                          label: Text(_saving ? tr(context, 'setupSaving') : tr(context, 'setupFinish')),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(context, 'setupLocalPrivacy'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
