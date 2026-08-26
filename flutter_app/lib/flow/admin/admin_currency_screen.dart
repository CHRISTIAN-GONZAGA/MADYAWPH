import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../../dio_client.dart';
import '../../services/app_currency.dart';
import '../../utils/money_format.dart';

/// Hotel admin: pick the currency staff and guests see, and the rate used to
/// convert the peso amounts stored on the booking.
class AdminCurrencyScreen extends StatefulWidget {
  const AdminCurrencyScreen({super.key});

  @override
  State<AdminCurrencyScreen> createState() => _AdminCurrencyScreenState();
}

class _CurrencyOption {
  const _CurrencyOption({
    required this.code,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.defaultRate,
  });

  final String code;
  final String symbol;
  final String name;
  final int decimals;
  final double defaultRate;

  static _CurrencyOption fromJson(Map<String, dynamic> json) {
    final rate = json['default_rate'];
    final decimals = json['decimals'];
    return _CurrencyOption(
      code: (json['code'] ?? '').toString(),
      symbol: (json['symbol'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      decimals: decimals is num ? decimals.toInt() : 2,
      defaultRate: rate is num ? rate.toDouble() : 1,
    );
  }
}

class _AdminCurrencyScreenState extends State<AdminCurrencyScreen> {
  final _rateCtrl = TextEditingController();

  List<_CurrencyOption> _options = const [];
  String _code = 'PHP';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rateCtrl.dispose();
    super.dispose();
  }

  _CurrencyOption? get _selected {
    for (final option in _options) {
      if (option.code == _code) return option;
    }
    return null;
  }

  double get _rate {
    if (_code == 'PHP') return 1;
    final parsed = double.tryParse(_rateCtrl.text.trim());
    if (parsed != null && parsed > 0) return parsed;
    return _selected?.defaultRate ?? 1;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res =
          await portalDio().get<Map<String, dynamic>>('/admin/settings/currency');
      if (!mounted) return;
      final raw = (res.data?['options'] as List?) ?? const [];
      final current = (res.data?['currency'] as Map?) ?? const {};
      final rate = current['rate'];
      setState(() {
        _options = raw
            .whereType<Map>()
            .map((e) => _CurrencyOption.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _code = (current['code'] ?? 'PHP').toString();
        _rateCtrl.text = rate is num ? _trimRate(rate.toDouble()) : '';
        _loading = false;
      });
      await AppCurrency.applyFromApi(res.data?['currency']);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  static String _trimRate(double value) {
    if (value == value.roundToDouble() && value.abs() < 1000000) {
      return value.toStringAsFixed(value.abs() >= 1 ? 0 : 4);
    }
    return value.toStringAsFixed(value.abs() >= 1 ? 4 : 6);
  }

  Future<void> _save() async {
    final typed = _rateCtrl.text.trim();
    if (_code != 'PHP' && typed.isNotEmpty) {
      final parsed = double.tryParse(typed);
      if (parsed == null || parsed <= 0) {
        showAppMessage(
          context,
          'Enter a positive conversion rate, or clear the field to use the built-in rate.',
          isError: true,
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final res = await portalDio().patch<Map<String, dynamic>>(
        '/admin/settings/currency',
        data: {
          'currency_code': _code,
          if (_code != 'PHP' && typed.isNotEmpty)
            'currency_rate': double.parse(typed),
        },
      );
      await AppCurrency.applyFromApi(res.data?['currency']);
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, 'Prices now show in $_code.');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected;
    final rate = _rate;

    return Scaffold(
      appBar: AppBar(title: const Text('Display currency')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Pick the currency your staff and guests see. Rooms, bills, and reports '
                  'are converted automatically from the peso amounts saved on each booking.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _options.any((o) => o.code == _code) ? _code : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final option in _options)
                      DropdownMenuItem<String>(
                        value: option.code,
                        child: Text('${option.symbol}  ${option.code} · ${option.name}'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _code = value;
                      _rateCtrl.clear();
                    });
                  },
                ),
                if (_code != 'PHP') ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Conversion rate (₱1 = ? $_code)',
                      hintText: selected == null
                          ? ''
                          : _trimRate(selected.defaultRate),
                      helperText:
                          'Leave blank to use the built-in rate. Set your own to match your accounting.',
                      helperMaxLines: 3,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Card(
                  color: scheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 10),
                        _PreviewRow(
                          label: 'Room rate ₱1,500',
                          value: _preview(1500, selected, rate),
                        ),
                        _PreviewRow(
                          label: 'Bill total ₱4,250.75',
                          value: _preview(4250.75, selected, rate),
                        ),
                        _PreviewRow(
                          label: 'Amenity ₱120',
                          value: _preview(120, selected, rate),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Payments are still recorded in pesos, so nothing in your existing '
                  'bookings or reports changes. Amount fields you type into (rates, fees, '
                  'deposits) stay in pesos as well.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save currency'),
                ),
              ],
            ),
    );
  }

  String _preview(double pesos, _CurrencyOption? option, double rate) {
    if (option == null) return formatMoney(pesos);
    final converted = pesos * rate;
    final places = option.decimals;
    final fixed = converted.toStringAsFixed(places);
    final dot = fixed.indexOf('.');
    final whole = dot == -1 ? fixed : fixed.substring(0, dot);
    final rest = dot == -1 ? '' : fixed.substring(dot);
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
      buffer.write(whole[i]);
    }
    return '${option.symbol}$buffer$rest';
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
