import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'amount_input_controller.dart';

/// Custom 3x4 numeric keypad (mockup grid): 1-9, comma, 0, backspace.
/// Input rules (decimals, caps) live in [AmountInputController]; invalid
/// taps are silent no-ops, so every key is always enabled.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.controller});

  final AmountInputController controller;

  static const double _keyHeight = 56;

  Widget _key(
      {required Key key, required Widget child, required VoidCallback onTap}) {
    return Expanded(
      child: SizedBox(
        height: _keyHeight,
        child: TextButton(key: key, onPressed: onTap, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .titleLarge
        ?.copyWith(fontWeight: FontWeight.w700);
    Widget digit(int d) => _key(
          key: Key('key-$d'),
          child: Text('$d', style: style),
          onTap: () => controller.addDigit(d),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [digit(1), digit(2), digit(3)]),
        Row(children: [digit(4), digit(5), digit(6)]),
        Row(children: [digit(7), digit(8), digit(9)]),
        Row(children: [
          _key(
            key: const Key('key-comma'),
            child: Text(',', style: style),
            onTap: controller.addDecimalSeparator,
          ),
          digit(0),
          _key(
            key: const Key('key-backspace'),
            child: const Icon(Symbols.backspace),
            onTap: controller.backspace,
          ),
        ]),
      ],
    );
  }
}
