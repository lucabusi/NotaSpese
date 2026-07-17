import 'package:flutter/material.dart';

import '../../../core/constants/categories.dart';

/// Single-select category chips (icon + label), one per [Categoria].
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Categoria selected;
  final ValueChanged<Categoria> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in Categoria.values)
          ChoiceChip(
            key: Key('chip-${c.name}'),
            avatar: Icon(c.icon, size: 18),
            label: Text(c.label),
            selected: c == selected,
            onSelected: (_) => onSelected(c),
          ),
      ],
    );
  }
}
