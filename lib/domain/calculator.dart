class Calculator {
  const Calculator._();

  static double evaluate(String expression) {
    final parser = _ExpressionParser(expression);
    final result = parser.parse();
    if (!result.isFinite) throw const FormatException('The result is outside the supported range.');
    return result;
  }

  static String format(double value) {
    if (value == 0) return '0';
    if (value.abs() < 1e15 && value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    if (value.abs() >= 1e15 || value.abs() < 1e-7) {
      return value
          .toStringAsExponential(8)
          .replaceFirst(RegExp(r'\.0+e'), 'e')
          .replaceFirstMapped(RegExp(r'(\.\d*?[1-9])0+e'), (match) => '${match.group(1)}e');
    }
    return value
        .toStringAsFixed(8)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _ExpressionParser {
  _ExpressionParser(this.source);

  final String source;
  int _index = 0;

  double parse() {
    final value = _additive().value;
    _skipWhitespace();
    if (_index != source.length) throw const FormatException('Unexpected input.');
    return value;
  }

  _Value _additive() {
    var left = _multiplicative();
    while (true) {
      _skipWhitespace();
      if (!_take('+') && !_take('-')) return left;
      final operator = source[_index - 1];
      final right = _multiplicative();
      final operand = right.isPercentage ? left.value * right.value : right.value;
      left = _Value(operator == '+' ? left.value + operand : left.value - operand);
    }
  }

  _Value _multiplicative() {
    var left = _unary();
    while (true) {
      _skipWhitespace();
      final multiply = _take('*') || _take('×');
      final divide = multiply ? false : (_take('/') || _take('÷'));
      if (!multiply && !divide) return left;
      final right = _unary();
      if (divide && right.value == 0) throw const FormatException('Division by zero.');
      left = _Value(multiply ? left.value * right.value : left.value / right.value);
    }
  }

  _Value _unary() {
    _skipWhitespace();
    if (_take('+')) return _unary();
    if (_take('-')) {
      final value = _unary();
      return _Value(-value.value, isPercentage: value.isPercentage);
    }
    return _primary();
  }

  _Value _primary() {
    _skipWhitespace();
    if (_take('(')) {
      final value = _additive();
      _skipWhitespace();
      if (!_take(')')) throw const FormatException('Missing closing parenthesis.');
      if (_take('%')) return _Value(value.value / 100, isPercentage: true);
      return value;
    }

    final start = _index;
    var dotSeen = false;
    var digitsSeen = false;
    while (_index < source.length) {
      final character = source[_index];
      if (character == '.') {
        if (dotSeen) throw const FormatException('A number cannot contain two decimal points.');
        dotSeen = true;
      } else if (character.codeUnitAt(0) >= 48 && character.codeUnitAt(0) <= 57) {
        digitsSeen = true;
      } else {
        break;
      }
      _index++;
    }
    if (!digitsSeen) throw const FormatException('Enter a valid expression.');
    final number = double.tryParse(source.substring(start, _index));
    if (number == null || !number.isFinite) throw const FormatException('Enter a valid number.');
    if (_take('%')) return _Value(number / 100, isPercentage: true);
    return _Value(number);
  }

  bool _take(String character) {
    if (_index >= source.length || source[_index] != character) return false;
    _index++;
    return true;
  }

  void _skipWhitespace() {
    while (_index < source.length && source[_index].trim().isEmpty) {
      _index++;
    }
  }
}

class _Value {
  const _Value(this.value, {this.isPercentage = false});

  final double value;
  final bool isPercentage;
}
