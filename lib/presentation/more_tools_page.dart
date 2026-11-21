import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/calculator.dart';
import '../services/market_rates_service.dart';
import 'app_strings.dart';

class MoreToolsPage extends StatefulWidget {
  const MoreToolsPage({
    super.key,
    required this.marketDisplayCurrency,
    required this.onMarketDisplayCurrencyChanged,
    required this.onOpenSmartImport,
    this.marketRatesService,
  });

  final String marketDisplayCurrency;
  final Future<void> Function(String currencyCode) onMarketDisplayCurrencyChanged;
  final VoidCallback onOpenSmartImport;
  final MarketRatesService? marketRatesService;

  @override
  State<MoreToolsPage> createState() => _MoreToolsPageState();
}

class _MoreToolsPageState extends State<MoreToolsPage> {
  String? _activeTool;

  @override
  Widget build(BuildContext context) {
    if (_activeTool == 'calculator') {
      return _ToolPageShell(
        title: tr(context, 'calculatorTitle'),
        onBack: () => setState(() => _activeTool = null),
        child: const _CalculatorTool(),
      );
    }
    if (_activeTool == 'currency') {
      return _ToolPageShell(
        title: tr(context, 'marketRatesTitle'),
        onBack: () => setState(() => _activeTool = null),
        child: MarketRatesTool(
          initialDisplayCurrency: widget.marketDisplayCurrency,
          onDisplayCurrencyChanged: widget.onMarketDisplayCurrencyChanged,
          service: widget.marketRatesService ?? MarketRatesService(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(context, 'moreTitle'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(tr(context, 'moreToolsHint'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 640 ? 220.0 : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ToolCard(
                  width: width,
                  icon: Icons.calculate_outlined,
                  title: tr(context, 'calculatorTitle'),
                  subtitle: tr(context, 'calculatorDescription'),
                  onTap: () => setState(() => _activeTool = 'calculator'),
                  key: const Key('more-tool-calculator'),
                ),
                _ToolCard(
                  width: width,
                  icon: Icons.currency_exchange_rounded,
                  title: tr(context, 'marketRatesTitle'),
                  subtitle: tr(context, 'marketRatesDescription'),
                  onTap: () => setState(() => _activeTool = 'currency'),
                  key: const Key('more-tool-currency'),
                ),
                _ToolCard(
                  width: width,
                  icon: Icons.document_scanner_outlined,
                  title: tr(context, 'smartImport'),
                  subtitle: tr(context, 'smartImportDescription'),
                  onTap: widget.onOpenSmartImport,
                  key: const Key('more-tool-smart-import'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ToolPageShell extends StatelessWidget {
  const _ToolPageShell({required this.title, required this.onBack, required this.child});

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: tr(context, 'backToTools'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      );
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    super.key,
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
                  const SizedBox(height: 14),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      );
}

class _CalculatorTool extends StatefulWidget {
  const _CalculatorTool();

  @override
  State<_CalculatorTool> createState() => _CalculatorToolState();
}

class _CalculatorToolState extends State<_CalculatorTool> {
  String _expression = '';
  String? _error;
  bool _justEvaluated = false;

  static const _keys = <List<String>>[
    ['C', '(', ')', '⌫'],
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '−'],
    ['0', '.', '%', '+'],
    ['='],
  ];

  void _press(String key) {
    if (key == 'C') {
      setState(() {
        _expression = '';
        _error = null;
        _justEvaluated = false;
      });
      return;
    }
    if (key == '⌫') {
      setState(() {
        _expression = _expression.isEmpty ? '' : _expression.substring(0, _expression.length - 1);
        _error = null;
        _justEvaluated = false;
      });
      return;
    }
    if (key == '=') {
      try {
        final result = Calculator.format(Calculator.evaluate(_expression));
        setState(() {
          _expression = result;
          _error = null;
          _justEvaluated = true;
        });
      } on FormatException catch (error) {
        setState(() {
          _error = error.message.toString();
        });
      }
      return;
    }

    final operator = const {'+', '−', '×', '÷', '%', ')'};
    setState(() {
      if (_justEvaluated && !operator.contains(key)) _expression = '';
      _expression += key == '−' ? '-' : key;
      _error = null;
      _justEvaluated = false;
    });
  }

  String? get _preview {
    if (_expression.trim().isEmpty) return null;
    try {
      return Calculator.format(Calculator.evaluate(_expression));
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = _preview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).inputDecorationTheme.fillColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_expression.isEmpty ? '0' : _expression,
                      key: const Key('calculator-expression'),
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.headlineSmall),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(tr(context, 'calculatorInvalidExpression'), style: TextStyle(color: colors.error)),
                  ] else if (preview != null) ...[
                    const SizedBox(height: 4),
                    Text('= $preview', key: const Key('calculator-result'),
                        style: TextStyle(color: colors.primary, fontSize: 17, fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final row in _keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    for (final key in row)
                      Expanded(
                        flex: key == '=' && row.length == 1 ? 4 : 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: SizedBox(
                            height: 54,
                            child: FilledButton.tonal(
                              key: Key('calculator-key-$key'),
                              onPressed: () => _press(key),
                              style: FilledButton.styleFrom(
                                backgroundColor: key == '=' ? colors.primary : null,
                                foregroundColor: key == '=' ? colors.onPrimary : null,
                              ),
                              child: Text(key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MarketRatesTool extends StatefulWidget {
  const MarketRatesTool({
    super.key,
    required this.initialDisplayCurrency,
    required this.onDisplayCurrencyChanged,
    required this.service,
  });

  final String initialDisplayCurrency;
  final Future<void> Function(String currencyCode) onDisplayCurrencyChanged;
  final MarketRatesService service;

  @override
  State<MarketRatesTool> createState() => _MarketRatesToolState();
}

class _MarketRatesToolState extends State<MarketRatesTool> {
  static const _currencies = <(String, String)>[
    ('TOMAN', 'TOMAN · Iranian toman'),
    ('IRR', 'IRR · Iranian rial'),
    ('USD', 'USD · US Dollar'),
    ('EUR', 'EUR · Euro'),
    ('AED', 'AED · UAE dirham'),
  ];
  static const _cardCodes = ['USD', 'EUR', 'GBP', 'AED', 'CNY', 'TRY'];

  late String _displayCurrency;
  String _fromCurrency = 'TOMAN';
  String _toCurrency = 'USD';
  String? _operation;
  final _amount = TextEditingController(text: '1');
  final _adjustment = TextEditingController();
  MarketRatesSnapshot? _snapshot;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _displayCurrency = _currencies.any((item) => item.$1 == widget.initialDisplayCurrency)
        ? widget.initialDisplayCurrency
        : 'TOMAN';
    _toCurrency = _displayCurrency == 'IRR' || _displayCurrency == 'TOMAN' ? 'USD' : _displayCurrency;
    _refresh();
  }

  @override
  void dispose() {
    _amount.dispose();
    _adjustment.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await widget.service.fetchLatest();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? get _adjustedAmount {
    final first = _parseAmount(_amount.text);
    if (first == null || !first.isFinite) return null;
    if (_operation == null || _adjustment.text.trim().isEmpty) return first;
    final second = _parseAmount(_adjustment.text);
    if (second == null || !second.isFinite) return null;
    return switch (_operation) {
      '+' => first + second,
      '−' => first - second,
      '×' => first * second,
      '÷' => second == 0 ? null : first / second,
      _ => first,
    };
  }

  double? get _convertedAmount {
    final amount = _adjustedAmount;
    final snapshot = _snapshot;
    if (amount == null || snapshot == null) return null;
    return snapshot.convert(amount, _fromCurrency, _toCurrency);
  }

  Future<void> _selectDisplayCurrency(String? code) async {
    if (code == null) return;
    setState(() {
      _displayCurrency = code;
      if (_toCurrency == 'TOMAN' || _toCurrency == 'IRR') _toCurrency = code == 'TOMAN' || code == 'IRR' ? 'USD' : code;
    });
    await widget.onDisplayCurrencyChanged(code);
  }

  Future<void> _openSource() async {
    await launchUrl(Uri.parse('https://nerkhara.com/en/api/'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final stale = snapshot != null && _cardCodes
        .map((code) => snapshot.quotes[code])
        .whereType<MarketRateQuote>()
        .any((quote) => quote.isStaleAt(DateTime.now())) || (snapshot?.cached ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(tr(context, 'marketRatesTitle'), style: const TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(
                      key: const Key('market-rates-refresh'),
                      tooltip: tr(context, 'refreshRates'),
                      onPressed: _loading ? null : _refresh,
                      icon: _loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('market-display-currency'),
                  initialValue: _displayCurrency,
                  decoration: InputDecoration(labelText: tr(context, 'marketDisplayCurrency')),
                  items: [
                    for (final currency in _currencies)
                      DropdownMenuItem(value: currency.$1, child: Text(currency.$2)),
                  ],
                  onChanged: _selectDisplayCurrency,
                ),
                const SizedBox(height: 8),
                Text(tr(context, 'marketRateDisclaimer'), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null && snapshot == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(tr(context, 'marketRatesFailed'), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  TextButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded), label: Text(tr(context, 'retry'))),
                ],
              ),
            ),
          ),
        if (snapshot != null) ...[
          if (stale)
            MaterialBanner(
              content: Text(tr(context, 'marketRatesStale')),
              leading: const Icon(Icons.schedule_rounded),
              actions: [TextButton(onPressed: _refresh, child: Text(tr(context, 'refreshRates')))],
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 660 ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final code in _cardCodes)
                    if (snapshot.quotes.containsKey(code))
                      _RateCard(
                        width: width,
                        quote: snapshot.quotes[code]!,
                        displayCurrency: _displayCurrency,
                        snapshot: snapshot,
                      ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _converterCard(snapshot),
        ],
        if (_error != null && snapshot != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr(context, 'marketRatesRefreshFailed'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _openSource,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(tr(context, 'marketRateSource')),
          ),
        ),
      ],
    );
  }

  Widget _converterCard(MarketRatesSnapshot snapshot) {
    final converted = _convertedAmount;
    final adjusted = _adjustedAmount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'currencyConverter'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: tr(context, 'amount'), suffixText: _fromCurrency),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(tr(context, 'calculatorOptionalOperation'), style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final operation in ['+', '−', '×', '÷'])
                        ChoiceChip(
                          label: Text(operation),
                          selected: _operation == operation,
                          onSelected: (selected) => setState(() => _operation = selected ? operation : null),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 116,
                  child: TextField(
                    controller: _adjustment,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(labelText: tr(context, 'secondAmount')),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _fromCurrency,
                    decoration: InputDecoration(labelText: tr(context, 'fromCurrency')),
                    items: [for (final item in _currencies) DropdownMenuItem(value: item.$1, child: Text(item.$1))],
                    onChanged: (value) => setState(() => _fromCurrency = value ?? _fromCurrency),
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'swapCurrencies'),
                  onPressed: () => setState(() {
                    final prior = _fromCurrency;
                    _fromCurrency = _toCurrency;
                    _toCurrency = prior;
                  }),
                  icon: const Icon(Icons.swap_horiz_rounded),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _toCurrency,
                    decoration: InputDecoration(labelText: tr(context, 'toCurrency')),
                    items: [for (final item in _currencies) DropdownMenuItem(value: item.$1, child: Text(item.$1))],
                    onChanged: (value) => setState(() => _toCurrency = value ?? _toCurrency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                adjusted == null || converted == null
                    ? tr(context, 'currencyConversionUnavailable')
                    : '${_formatAmount(adjusted, _fromCurrency)} $_fromCurrency  =  ${_formatAmount(converted, _toCurrency)} $_toCurrency',
                key: const Key('market-conversion-result'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
            if (snapshot.generatedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                tr(context, 'marketSnapshotTime') + ' ${_formatTime(snapshot.generatedAt!.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.width, required this.quote, required this.displayCurrency, required this.snapshot});

  final double width;
  final MarketRateQuote quote;
  final String displayCurrency;
  final MarketRatesSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final rate = snapshot.rate(quote.code, displayCurrency);
    final stale = snapshot.cached || quote.isStaleAt(DateTime.now());
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(quote.code.substring(0, 1), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_currencyName(context, quote.code), style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (stale) Icon(Icons.schedule_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                ],
              ),
              const SizedBox(height: 14),
              Text('1 ${quote.code}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 3),
              Text(
                rate == null ? '—' : '${_formatAmount(rate, displayCurrency)} $displayCurrency',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              Text(
                '${_formatQuoteTime(context, quote.updatedAt, isPersian)}  ·  ${stale ? tr(context, 'staleRate') : tr(context, 'freshRate')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: stale ? Theme.of(context).colorScheme.error : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _currencyName(BuildContext context, String code) => switch (code) {
      'USD' => tr(context, 'currencyUsd'),
      'EUR' => tr(context, 'currencyEur'),
      'GBP' => tr(context, 'currencyGbp'),
      'AED' => tr(context, 'currencyAed'),
      'CNY' => tr(context, 'currencyCny'),
      'TRY' => tr(context, 'currencyTry'),
      _ => code,
    };

String _formatQuoteTime(BuildContext context, DateTime? time, bool persian) {
  if (time == null) return tr(context, 'timeUnavailable');
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final value = '$day/$month/${local.year} $hour:$minute';
  return persian ? _persianDigits(value) : value;
}

String _formatTime(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _formatAmount(double value, String currency) {
  final decimals = currency == 'IRR' || currency == 'TOMAN' ? 0 : 4;
  final fixed = value.toStringAsFixed(decimals);
  final pieces = fixed.split('.');
  final grouped = pieces.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final fractional = pieces.length > 1 ? pieces[1].replaceFirst(RegExp(r'0+$'), '') : '';
  if (fractional.isEmpty) return grouped;
  return '$grouped.$fractional';
}

double? _parseAmount(String input) {
  final normalized = _latinDigits(input).replaceAll(',', '').trim();
  return double.tryParse(normalized);
}

String _latinDigits(String input) => input.replaceAllMapped(RegExp('[۰-۹٠-٩]'), (match) {
      final code = match[0]!.codeUnitAt(0);
      final digit = code >= 0x06F0 ? code - 0x06F0 : code - 0x0660;
      return digit.toString();
    });

String _persianDigits(String input) => input.replaceAllMapped(RegExp(r'[0-9]'), (match) => String.fromCharCode(0x06F0 + int.parse(match[0]!)));
