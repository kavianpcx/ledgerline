import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/domain/calculator.dart';
import 'package:ledgerline/services/market_rates_service.dart';

void main() {
  group('Calculator', () {
    test('respects precedence, parentheses, and unary signs', () {
      expect(Calculator.evaluate('2 + 3 × 4'), 14);
      expect(Calculator.evaluate('(2 + 3) × -4'), -20);
      expect(Calculator.evaluate('12 / 3 + 2'), 6);
    });

    test('uses contextual percentages for addition and subtraction', () {
      expect(Calculator.evaluate('200 + 15%'), 230);
      expect(Calculator.evaluate('200 - 15%'), 170);
      expect(Calculator.evaluate('10 × 5%'), 0.5);
    });

    test('rejects incomplete and unsafe expressions', () {
      expect(() => Calculator.evaluate('10 / 0'), throwsFormatException);
      expect(() => Calculator.evaluate('3 +'), throwsFormatException);
      expect(() => Calculator.evaluate('1 + bad'), throwsFormatException);
    });
  });

  group('MarketRatesSnapshot', () {
    test('converts real quotes through the toman base without mixing rial units', () {
      final snapshot = MarketRatesSnapshot.fromJson(_sampleRates);
      expect(snapshot.convert(1, 'USD', 'EUR'), closeTo(0.8333333, 0.00001));
      expect(snapshot.convert(1000000, 'TOMAN', 'USD'), closeTo(1, 0.000001));
      expect(snapshot.convert(10000000, 'IRR', 'USD'), closeTo(1, 0.000001));
      expect(snapshot.rate('USD', 'IRR'), 10000000);
    });

    test('keeps source timestamps and stale status', () {
      final snapshot = MarketRatesSnapshot.fromJson(_sampleRates);
      expect(snapshot.generatedAt, DateTime.utc(2026, 11, 20, 10));
      expect(snapshot.quotes['USD']!.updatedAt, DateTime.utc(2026, 11, 20, 9, 59));
      expect(snapshot.quotes['USD']!.sourceSaysStale, isFalse);
      expect(snapshot.quotes['EUR']!.sourceSaysStale, isTrue);
    });

    test('ignores unsupported quote units and rejects empty feeds', () {
      final snapshot = MarketRatesSnapshot.fromJson({
        'items': [
          {'id': 'usd', 'unit': 'USD', 'price': 1.0, 'updated_utc': '2026-11-20T10:00:00Z'},
        ],
      });
      expect(snapshot.quotes, isEmpty);
      expect(() => MarketRatesSnapshot.fromJson({'items': []}), throwsFormatException);
    });
  });

  test('MarketRatesService parses a loader response without requiring network access', () async {
    final service = MarketRatesService(loader: () async => _sampleRates);
    final snapshot = await service.fetchLatest();
    expect(snapshot.quotes.keys, containsAll(['USD', 'EUR', 'AED']));

    final offlineService = MarketRatesService(loader: () async => throw StateError('offline'));
    final cached = await offlineService.fetchLatest();
    expect(cached.cached, isTrue);
  });
}

final Map<String, Object?> _sampleRates = {
  'api': 'nerkhara/v1',
  'generated_utc': '2026-11-20T10:00:00Z',
  'items': [
    {
      'id': 'usd',
      'unit': 'IRT',
      'price': 1000000.0,
      'updated_utc': '2026-11-20T09:59:00Z',
      'stale': false,
      'change_pct': 0.2,
      'sources': 3,
    },
    {
      'item': {
        'id': 'eur',
        'unit': 'IRT',
        'price': 1200000.0,
        'updated_utc': '2026-11-20T09:58:00Z',
        'stale': true,
      },
    },
    {
      'id': 'aed',
      'unit': 'IRT',
      'price': 270000.0,
      'updated_utc': '2026-11-20T09:59:00Z',
      'stale': false,
    },
  ],
};
