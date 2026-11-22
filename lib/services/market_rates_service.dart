import 'dart:convert';
import 'dart:io';

typedef MarketRatesLoader = Future<Map<String, Object?>> Function();

class MarketRateQuote {
  const MarketRateQuote({
    required this.code,
    required this.priceInToman,
    required this.updatedAt,
    required this.sourceSaysStale,
    this.changePercent,
    this.sourceCount,
  });

  final String code;
  final double priceInToman;
  final DateTime? updatedAt;
  final bool sourceSaysStale;
  final double? changePercent;
  final int? sourceCount;

  bool isStaleAt(DateTime now) =>
      sourceSaysStale || updatedAt == null || now.toUtc().difference(updatedAt!).inMinutes > 30;
}

class MarketRatesSnapshot {
  const MarketRatesSnapshot({required this.quotes, required this.generatedAt, this.cached = false});

  final Map<String, MarketRateQuote> quotes;
  final DateTime? generatedAt;
  final bool cached;

  MarketRatesSnapshot asCached() => MarketRatesSnapshot(
        quotes: quotes,
        generatedAt: generatedAt,
        cached: true,
      );

  static MarketRatesSnapshot fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    if (rawItems is! List) throw const FormatException('The rate provider returned no quote list.');
    final quotes = <String, MarketRateQuote>{};
    for (final rawItem in rawItems) {
      if (rawItem is! Map<Object?, Object?>) continue;
      final rawNestedItem = rawItem['item'];
      final item = rawNestedItem is Map<Object?, Object?> ? rawNestedItem : rawItem;
      final id = item['id']?.toString().toLowerCase();
      final unit = item['unit']?.toString().toUpperCase();
      final price = _number(item['price']);
      if (id == null || unit != 'IRT' || price == null || price <= 0) continue;
      if (!RegExp(r'^[a-z]{3}$').hasMatch(id)) continue;
      quotes[id.toUpperCase()] = MarketRateQuote(
        code: id.toUpperCase(),
        priceInToman: price,
        updatedAt: _utcDate(item['updated_utc'] ?? item['as_of']),
        sourceSaysStale: item['stale'] == true,
        changePercent: _number(item['change_pct']),
        sourceCount: item['sources'] is num ? (item['sources'] as num).toInt() : null,
      );
    }
    if (quotes.isEmpty) throw const FormatException('The rate provider returned no usable currency quotes.');
    return MarketRatesSnapshot(
      quotes: Map.unmodifiable(quotes),
      generatedAt: _utcDate(json['generated_utc']),
    );
  }

  double? rate(String fromCode, String toCode) {
    final from = fromCode.toUpperCase();
    final to = toCode.toUpperCase();
    if (from == to) return 1;
    final fromToman = _tomanPerUnit(from);
    final toToman = _tomanPerUnit(to);
    if (fromToman == null || toToman == null || toToman == 0) return null;
    return fromToman / toToman;
  }

  double? convert(double amount, String fromCode, String toCode) {
    if (!amount.isFinite) return null;
    final conversionRate = rate(fromCode, toCode);
    if (conversionRate == null) return null;
    final converted = amount * conversionRate;
    return converted.isFinite ? converted : null;
  }

  double? _tomanPerUnit(String code) {
    if (code == 'TOMAN' || code == 'IRT') return 1;
    if (code == 'IRR') return 0.1;
    return quotes[code]?.priceInToman;
  }

  static double? _number(Object? value) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
    return parsed?.isFinite == true ? parsed : null;
  }

  static DateTime? _utcDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final source = value.trim();
    final hasZone = source.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(source);
    return DateTime.tryParse(hasZone ? source : '${source}Z')?.toUtc();
  }
}

class MarketRatesService {
  MarketRatesService({MarketRatesLoader? loader}) : _loader = loader;

  static const uri = 'https://nerkhara.com/api/v1/latest.json';
  static MarketRatesSnapshot? _lastGoodSnapshot;
  final MarketRatesLoader? _loader;

  Future<MarketRatesSnapshot> fetchLatest() async {
    try {
      final json = await (_loader ?? _loadJson)();
      final snapshot = MarketRatesSnapshot.fromJson(json);
      _lastGoodSnapshot = snapshot;
      return snapshot;
    } on Object {
      final cached = _lastGoodSnapshot;
      if (cached != null) return cached.asCached();
      rethrow;
    }
  }

  static Future<Map<String, Object?>> _loadJson() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(uri)).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Ledgerline/0.7');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException('Rate service returned HTTP ${response.statusCode}.');
      }
      final payload = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?>) throw const FormatException('Invalid rate-service response.');
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}
