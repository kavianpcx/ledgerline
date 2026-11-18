/// Exact currency metadata and minor-unit arithmetic for Ledgerline.
///
/// Amounts are integers in the currency's minor unit. This class does not
/// fetch exchange rates or infer conversions between unrelated currencies.
class CurrencyDefinition {
  const CurrencyDefinition({
    required this.code,
    required this.name,
    required this.minorUnitExponent,
  });

  final String code;
  final String name;
  final int minorUnitExponent;

  static const supported = <CurrencyDefinition>[
    CurrencyDefinition(code: 'USD', name: 'US dollar', minorUnitExponent: 2),
    CurrencyDefinition(code: 'EUR', name: 'Euro', minorUnitExponent: 2),
    CurrencyDefinition(code: 'GBP', name: 'Pound sterling', minorUnitExponent: 2),
    CurrencyDefinition(code: 'CAD', name: 'Canadian dollar', minorUnitExponent: 2),
    CurrencyDefinition(code: 'AUD', name: 'Australian dollar', minorUnitExponent: 2),
    CurrencyDefinition(code: 'AED', name: 'UAE dirham', minorUnitExponent: 2),
    CurrencyDefinition(code: 'JPY', name: 'Japanese yen', minorUnitExponent: 0),
    CurrencyDefinition(code: 'IRR', name: 'Iranian rial', minorUnitExponent: 0),
    // TOMAN is a Ledgerline accounting unit, not an ISO 4217 currency code.
    CurrencyDefinition(code: 'TOMAN', name: 'Iranian toman', minorUnitExponent: 0),
  ];

  static const codes = <String>{
    'USD', 'EUR', 'GBP', 'CAD', 'AUD', 'AED', 'JPY', 'IRR', 'TOMAN',
  };

  static bool isSupported(String code) => codes.contains(code.toUpperCase());

  static CurrencyDefinition of(String code) {
    final normalized = code.toUpperCase();
    for (final currency in supported) {
      if (currency.code == normalized) return currency;
    }
    throw ArgumentError.value(code, 'currencyCode', 'Unsupported currency.');
  }

  int get minorUnitsPerUnit {
    var result = 1;
    for (var i = 0; i < minorUnitExponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// Parses an amount without floating-point arithmetic.
  ///
  /// ASCII, Persian, and Arabic-Indic digits are accepted. A period or Arabic
  /// decimal separator marks the fractional part. A single comma with three
  /// trailing digits groups thousands; otherwise it can mark the fraction.
  /// Non-zero digits beyond the currency precision are rejected.
  static int? parseMinorUnits(String input, {required String currencyCode}) {
    final currency = of(currencyCode);
    var value = _normalizeDigits(input.trim())
        .replaceAll('\u066B', '.')
        .replaceAll('\u066C', ',')
        .replaceAll('\u00A0', '')
        .replaceAll(' ', '');
    if (value.isEmpty) return null;

    var sign = 1;
    if (value.startsWith('-')) {
      sign = -1;
      value = value.substring(1);
    } else if (value.startsWith('+')) {
      value = value.substring(1);
    }
    if (value.isEmpty) return null;

    final dot = value.lastIndexOf('.');
    final comma = value.lastIndexOf(',');
    String integerPart = value;
    var fractionPart = '';
    String? groupingSeparator;
    if (dot >= 0 && comma >= 0) {
      final decimalSeparator = dot > comma ? '.' : ',';
      final decimalIndex = dot > comma ? dot : comma;
      groupingSeparator = decimalSeparator == '.' ? ',' : '.';
      integerPart = value.substring(0, decimalIndex);
      fractionPart = value.substring(decimalIndex + 1);
    } else if (dot >= 0) {
      if (value.indexOf('.') != dot) return null;
      integerPart = value.substring(0, dot);
      fractionPart = value.substring(dot + 1);
    } else if (comma >= 0) {
      if (value.indexOf(',') != comma) {
        groupingSeparator = ',';
      } else if (value.length - comma - 1 == 3) {
        groupingSeparator = ',';
      } else {
        integerPart = value.substring(0, comma);
        fractionPart = value.substring(comma + 1);
      }
    }

    if (fractionPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fractionPart)) return null;
    if (fractionPart.isEmpty &&
        ((dot >= 0 && value.endsWith('.')) ||
            (dot < 0 && comma >= 0 && groupingSeparator == null))) return null;

    final whole = _parseGroupedInteger(integerPart, groupingSeparator);
    if (whole == null) return null;
    if (fractionPart.length > currency.minorUnitExponent) {
      final extra = fractionPart.substring(currency.minorUnitExponent);
      if (extra.split('').any((digit) => digit != '0')) return null;
      fractionPart = fractionPart.substring(0, currency.minorUnitExponent);
    }
    final normalizedFraction = fractionPart.padRight(currency.minorUnitExponent, '0');
    final fraction = normalizedFraction.isEmpty ? 0 : int.tryParse(normalizedFraction);
    if (fraction == null) return null;

    const maxSignedInt = 0x7fffffffffffffff;
    final scale = currency.minorUnitsPerUnit;
    if (whole > (maxSignedInt - fraction) ~/ scale) return null;
    final amount = whole * scale + fraction;
    return sign < 0 ? -amount : amount;
  }

  String formatMinorUnits(int minorUnits, {bool includeCode = true}) {
    final negative = minorUnits < 0;
    final absolute = minorUnits.abs();
    final whole = absolute ~/ minorUnitsPerUnit;
    final groupedWhole = whole.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
    final amountText = minorUnitExponent == 0
        ? '${negative ? '-' : ''}$groupedWhole'
        : '${negative ? '-' : ''}$groupedWhole.'
            '${(absolute % minorUnitsPerUnit).toString().padLeft(minorUnitExponent, '0')}';
    return includeCode ? '$code $amountText' : amountText;
  }

  String formatInput(int minorUnits) =>
      formatMinorUnits(minorUnits, includeCode: false);

  static String _normalizeDigits(String input) => input.replaceAllMapped(
        RegExp('[\u0660-\u0669\u06F0-\u06F9]'),
        (match) {
          final code = match.group(0)!.codeUnitAt(0);
          final zero = code <= 0x0669 ? 0x0660 : 0x06F0;
          return String.fromCharCode(0x30 + code - zero);
        },
      );

  static int? _parseGroupedInteger(String input, String? separator) {
    if (input.isEmpty) return null;
    if (separator == null || !input.contains(separator)) {
      return RegExp(r'^\d+$').hasMatch(input) ? int.tryParse(input) : null;
    }
    final groups = input.split(separator);
    if (groups.isEmpty ||
        groups.first.isEmpty ||
        groups.first.length > 3 ||
        !RegExp(r'^\d+$').hasMatch(groups.first)) return null;
    for (final group in groups.skip(1)) {
      if (group.length != 3 || !RegExp(r'^\d{3}$').hasMatch(group)) return null;
    }
    return int.tryParse(groups.join());
  }
}

/// A currency-tagged, integer-only monetary value.
class Money {
  const Money({required this.minorUnits, required this.currencyCode});

  final int minorUnits;
  final String currencyCode;

  static Money? parse(String input, {required String currencyCode}) {
    final amount = CurrencyDefinition.parseMinorUnits(input, currencyCode: currencyCode);
    return amount == null ? null : Money(
      minorUnits: amount,
      currencyCode: currencyCode.toUpperCase(),
    );
  }

  String format() => CurrencyDefinition.of(currencyCode).formatMinorUnits(minorUnits);

  /// Converts only between rial and toman using their fixed 10:1 unit ratio.
  /// Fractional toman results are rejected instead of rounded silently.
  Money convertIranianUnit(String targetCurrencyCode) {
    final source = currencyCode.toUpperCase();
    final target = targetCurrencyCode.toUpperCase();
    CurrencyDefinition.of(source);
    CurrencyDefinition.of(target);
    if (target == source) return this;
    if (source == 'TOMAN' && target == 'IRR') {
      const maxSignedInt = 0x7fffffffffffffff;
      if (minorUnits > maxSignedInt ~/ 10 || minorUnits < -maxSignedInt ~/ 10) {
        throw ArgumentError('The converted rial amount exceeds the supported integer range.');
      }
      return Money(minorUnits: minorUnits * 10, currencyCode: target);
    }
    if (source == 'IRR' && target == 'TOMAN') {
      if (minorUnits % 10 != 0) {
        throw ArgumentError('This rial amount cannot be represented as a whole toman.');
      }
      return Money(minorUnits: minorUnits ~/ 10, currencyCode: target);
    }
    throw UnsupportedError(
      'An explicit exchange rate is required to convert $source to $target.',
    );
  }
}
