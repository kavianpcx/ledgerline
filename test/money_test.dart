import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerline/domain/money.dart';

void main() {
  group('CurrencyDefinition', () {
    test('parses and formats decimal currencies using integer minor units', () {
      final money = Money.parse('1,234.56', currencyCode: 'USD')!;
      expect(money.minorUnits, 123456);
      expect(money.format(), 'USD 1,234.56');
    });

    test('accepts Persian and Arabic-Indic numerals and separators', () {
      expect(
        CurrencyDefinition.parseMinorUnits('۱۲٬۳۴۵', currencyCode: 'IRR'),
        12345,
      );
      expect(
        CurrencyDefinition.parseMinorUnits('١٢٫٥', currencyCode: 'USD'),
        1250,
      );
    });

    test('formats zero-decimal currencies without fabricated fractions', () {
      final yen = Money.parse('1,234', currencyCode: 'JPY')!;
      final toman = Money.parse('۱۲۳۴', currencyCode: 'TOMAN')!;
      expect(yen.minorUnits, 1234);
      expect(yen.format(), 'JPY 1,234');
      expect(toman.minorUnits, 1234);
      expect(toman.format(), 'TOMAN 1,234');
    });

    test('rejects invalid grouping and precision beyond currency support', () {
      expect(CurrencyDefinition.parseMinorUnits('1,23,4', currencyCode: 'USD'), isNull);
      expect(CurrencyDefinition.parseMinorUnits('1.001', currencyCode: 'USD'), isNull);
      expect(CurrencyDefinition.parseMinorUnits('1.5', currencyCode: 'JPY'), isNull);
      expect(CurrencyDefinition.parseMinorUnits('1.00', currencyCode: 'JPY'), 1);
    });

    test('converts rial and toman exactly and rejects loss', () {
      const rial = Money(minorUnits: 120, currencyCode: 'IRR');
      expect(rial.convertIranianUnit('TOMAN').minorUnits, 12);
      expect(
        const Money(minorUnits: 12, currencyCode: 'TOMAN')
            .convertIranianUnit('IRR')
            .minorUnits,
        120,
      );
      expect(
        () => const Money(minorUnits: 125, currencyCode: 'IRR')
            .convertIranianUnit('TOMAN'),
        throwsArgumentError,
      );
    });

    test('rejects unsupported source currencies and conversion overflow', () {
      expect(
        () => const Money(minorUnits: 10, currencyCode: 'UNKNOWN')
            .convertIranianUnit('IRR'),
        throwsArgumentError,
      );
      expect(
        () => const Money(minorUnits: 0x7fffffffffffffff, currencyCode: 'TOMAN')
            .convertIranianUnit('IRR'),
        throwsArgumentError,
      );
    });

    test('requires an explicit exchange rate for other currency pairs', () {
      expect(
        () => const Money(minorUnits: 100, currencyCode: 'USD')
            .convertIranianUnit('TOMAN'),
        throwsUnsupportedError,
      );
    });
  });
}
