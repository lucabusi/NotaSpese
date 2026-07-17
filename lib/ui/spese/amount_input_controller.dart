import 'package:flutter/foundation.dart';

/// Raw amount typed on the custom keypad. Value is the digit string with
/// ',' as decimal separator (e.g. '12,5'); empty string = no input yet.
/// All input rules live here so the keypad widget stays dumb.
class AmountInputController extends ValueNotifier<String> {
  AmountInputController({int decimalDigits = 2, String initial = ''})
      : _maxDecimals = decimalDigits,
        super(initial);

  static const int maxIntegerDigits = 9;

  int _maxDecimals;
  int get decimalDigits => _maxDecimals;

  /// Currency switch: decimals beyond the new limit are truncated.
  set decimalDigits(int digits) {
    _maxDecimals = digits;
    final i = value.indexOf(',');
    if (i < 0) return;
    if (digits == 0) {
      value = value.substring(0, i);
    } else if (value.length - i - 1 > digits) {
      value = value.substring(0, i + 1 + digits);
    }
  }

  void addDigit(int digit) {
    assert(digit >= 0 && digit <= 9);
    final i = value.indexOf(',');
    if (i < 0) {
      if (value == '0') {
        value = '$digit';
        return;
      }
      if (value.length >= maxIntegerDigits) return;
    } else if (value.length - i - 1 >= _maxDecimals) {
      return;
    }
    value = '$value$digit';
  }

  void addDecimalSeparator() {
    if (_maxDecimals == 0 || value.contains(',')) return;
    value = value.isEmpty ? '0,' : '$value,';
  }

  void backspace() {
    if (value.isEmpty) return;
    value = value.substring(0, value.length - 1);
  }

  /// Parsed amount, null when nothing was typed.
  double? get amount =>
      value.isEmpty ? null : double.tryParse(value.replaceAll(',', '.'));

  /// Edit-mode seed: stored amount → keypad string, trailing zeros dropped.
  static String initialText(double importo, int decimalDigits) {
    var s = importo.toStringAsFixed(decimalDigits);
    if (decimalDigits > 0) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s.replaceAll('.', ',');
  }
}
