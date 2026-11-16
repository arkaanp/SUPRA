import 'package:flutter/material.dart';

const newsSeverityLabels = <String, String>{
  'low': 'All severities',
  'medium': 'Medium or higher',
  'high': 'High or higher',
  'critical': 'Critical only',
};

class NewsSeveritySelector extends StatelessWidget {
  const NewsSeveritySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: const InputDecoration(
      labelText: 'News severity',
      border: OutlineInputBorder(),
      isDense: true,
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        isDense: true,
        items: newsSeverityLabels.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: onChanged == null
            ? null
            : (v) {
                if (v != null) onChanged!(v);
              },
      ),
    ),
  );
}
