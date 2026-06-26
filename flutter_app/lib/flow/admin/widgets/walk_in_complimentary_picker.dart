import 'package:flutter/material.dart';

/// Dropdown + quantity picker for walk-in complimentary amenity items.
class WalkInComplimentaryPicker extends StatelessWidget {
  const WalkInComplimentaryPicker({
    super.key,
    required this.menuItems,
    required this.quantitiesById,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> menuItems;
  final Map<String, int> quantitiesById;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (menuItems.isEmpty) return const SizedBox.shrink();

    return _WalkInComplimentaryPickerBody(
      menuItems: menuItems,
      quantitiesById: quantitiesById,
      onChanged: onChanged,
    );
  }
}

class _WalkInComplimentaryPickerBody extends StatefulWidget {
  const _WalkInComplimentaryPickerBody({
    required this.menuItems,
    required this.quantitiesById,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> menuItems;
  final Map<String, int> quantitiesById;
  final VoidCallback onChanged;

  @override
  State<_WalkInComplimentaryPickerBody> createState() =>
      _WalkInComplimentaryPickerBodyState();
}

class _WalkInComplimentaryPickerBodyState
    extends State<_WalkInComplimentaryPickerBody> {
  String? _selectedId;
  var _addQty = 1;

  String _idOf(Map<String, dynamic> item) =>
      (item['id'] ?? item['_id'] ?? '').toString();

  String _labelOf(Map<String, dynamic> item) {
    final name = (item['name'] ?? 'Item').toString();
    final type = (item['amenity_type'] ?? item['type'] ?? '').toString();
    return type.isEmpty ? name : '$name · $type';
  }

  List<Map<String, dynamic>> get _selectedItems {
    return widget.menuItems
        .where((item) => (widget.quantitiesById[_idOf(item)] ?? 0) > 0)
        .toList();
  }

  void _addSelection() {
    final id = _selectedId;
    if (id == null || id.isEmpty) return;
    final qty = _addQty.clamp(1, 20);
    widget.quantitiesById[id] = (widget.quantitiesById[id] ?? 0) + qty;
    widget.onChanged();
    setState(() {
      _addQty = 1;
    });
  }

  void _removeItem(String id) {
    widget.quantitiesById.remove(id);
    widget.onChanged();
    setState(() {});
  }

  void _adjustItem(String id, int delta) {
    final next = (widget.quantitiesById[id] ?? 0) + delta;
    if (next <= 0) {
      widget.quantitiesById.remove(id);
    } else {
      widget.quantitiesById[id] = next.clamp(1, 20);
    }
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.quantitiesById.values.fold<int>(0, (a, b) => a + b);
    final selected = _selectedItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Complimentary items (optional)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          'Choose from your amenities menu — add multiple products and quantities.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedId,
          decoration: const InputDecoration(
            labelText: 'Product',
            border: OutlineInputBorder(),
          ),
          items: widget.menuItems
              .map(
                (item) => DropdownMenuItem(
                  value: _idOf(item),
                  child: Text(_labelOf(item)),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedId = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _QtyStepper(
                label: 'Qty to add',
                value: _addQty,
                onChanged: (v) => setState(() => _addQty = v),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _selectedId == null ? null : _addSelection,
              child: const Text('Add'),
            ),
          ],
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Selected ($total item${total == 1 ? '' : 's'})',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          ...selected.map((item) {
            final id = _idOf(item);
            final qty = widget.quantitiesById[id] ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(_labelOf(item)),
                subtitle: Text('Quantity: $qty'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Decrease',
                      onPressed: () => _adjustItem(id, -1),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Increase',
                      onPressed: () => _adjustItem(id, 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => _removeItem(id),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value < 20 ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
