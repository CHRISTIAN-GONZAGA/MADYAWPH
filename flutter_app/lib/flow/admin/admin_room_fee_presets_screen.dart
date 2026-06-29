import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../dio_client.dart';

class AdminRoomFeePresetsScreen extends StatefulWidget {
  const AdminRoomFeePresetsScreen({super.key});

  @override
  State<AdminRoomFeePresetsScreen> createState() =>
      _AdminRoomFeePresetsScreenState();
}

class _AdminRoomFeePresetsScreenState extends State<AdminRoomFeePresetsScreen> {
  bool _loading = true;
  bool _saving = false;
  final List<_FeePresetRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await portalDio()
          .get<Map<String, dynamic>>('/admin/settings/room-fee-presets');
      final raw = (res.data?['presets'] as List?) ?? const [];
      _rows
        ..clear()
        ..addAll(
          raw.whereType<Map>().map(
            (m) => _FeePresetRow(
              label: TextEditingController(
                text: (m['label'] ?? '').toString(),
              ),
              amount: TextEditingController(
                text: '${m['amount'] ?? 0}',
              ),
            ),
          ),
        );
      if (_rows.isEmpty) {
        _rows.add(_FeePresetRow.empty());
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  void _addRow() {
    setState(() => _rows.add(_FeePresetRow.empty()));
  }

  void _removeRow(int index) {
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
      if (_rows.isEmpty) _rows.add(_FeePresetRow.empty());
    });
  }

  Future<void> _save() async {
    final presets = <Map<String, dynamic>>[];
    for (final row in _rows) {
      final label = row.label.text.trim();
      if (label.isEmpty) continue;
      presets.add({
        'label': label,
        'amount': double.tryParse(row.amount.text.trim()) ?? 0,
      });
    }
    if (presets.isEmpty) {
      showAppMessage(context, 'Add at least one fee option with a label.');
      return;
    }

    setState(() => _saving = true);
    try {
      await portalDio().patch(
        '/admin/settings/room-fee-presets',
        data: {'presets': presets},
      );
      if (!mounted) return;
      showAppMessage(context, 'Room fee options saved.');
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room fee options'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Text(
                  'Preset fees for Add fee in room details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Staff can tap these when charging extras to a guest room (e.g. stained sheets, minibar). Amount can be zero so they enter it manually.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ...List.generate(_rows.length, (i) {
                  final row = _rows[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Option ${i + 1}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _removeRow(i),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remove',
                              ),
                            ],
                          ),
                          TextField(
                            controller: row.label,
                            decoration: const InputDecoration(
                              labelText: 'Reason / label',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: row.amount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Default amount (PHP, optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              ],
            ),
    );
  }
}

class _FeePresetRow {
  _FeePresetRow({required this.label, required this.amount});

  factory _FeePresetRow.empty() => _FeePresetRow(
        label: TextEditingController(),
        amount: TextEditingController(text: '0'),
      );

  final TextEditingController label;
  final TextEditingController amount;

  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

/// Loads hotel-configured fee presets for the add-fee dialog.
Future<List<Map<String, dynamic>>> fetchRoomFeePresets() async {
  try {
    final res = await portalDio()
        .get<Map<String, dynamic>>('/admin/settings/room-fee-presets');
    final raw = (res.data?['presets'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => (m['label'] ?? '').toString().trim().isNotEmpty)
        .toList();
  } on DioException {
    return const [];
  }
}
