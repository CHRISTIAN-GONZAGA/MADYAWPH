import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display currency for the whole app.
///
/// Every amount in the API is stored in Philippine pesos. A hotel can pick the
/// currency its staff and guests see (Setup → Display currency); we convert at
/// render time with [rate], which is how many units of the display currency one
/// peso buys. PHP itself always uses rate 1.
@immutable
class AppCurrencySettings {
  const AppCurrencySettings({
    this.code = 'PHP',
    this.symbol = '₱',
    this.name = 'Philippine peso',
    this.decimals = 2,
    this.rate = 1,
  });

  final String code;
  final String symbol;
  final String name;
  final int decimals;
  final double rate;

  bool get isBase => code == 'PHP';

  static AppCurrencySettings fromJson(Map<String, dynamic> json) {
    final rawRate = json['rate'];
    final rate = rawRate is num
        ? rawRate.toDouble()
        : double.tryParse('${rawRate ?? ''}') ?? 1.0;
    final decimals = json['decimals'];
    return AppCurrencySettings(
      code: (json['code'] ?? 'PHP').toString().toUpperCase(),
      symbol: (json['symbol'] ?? '₱').toString(),
      name: (json['name'] ?? '').toString(),
      decimals: decimals is num ? decimals.toInt() : 2,
      rate: rate > 0 ? rate : 1.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'symbol': symbol,
        'name': name,
        'decimals': decimals,
        'rate': rate,
      };

  @override
  bool operator ==(Object other) =>
      other is AppCurrencySettings &&
      other.code == code &&
      other.symbol == symbol &&
      other.decimals == decimals &&
      other.rate == rate;

  @override
  int get hashCode => Object.hash(code, symbol, decimals, rate);
}

class AppCurrency {
  AppCurrency._();

  static const _prefsKey = 'app_display_currency_v1';

  /// Rebuild money widgets by listening to this.
  static final ValueNotifier<AppCurrencySettings> notifier =
      ValueNotifier<AppCurrencySettings>(const AppCurrencySettings());

  static AppCurrencySettings get value => notifier.value;

  static String get symbol => notifier.value.symbol;

  static String get code => notifier.value.code;

  /// Restores the last known currency so the first frame is already correct.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('${_prefsKey}_code');
      if (code == null || code.isEmpty) return;
      notifier.value = AppCurrencySettings(
        code: code,
        symbol: prefs.getString('${_prefsKey}_symbol') ?? '₱',
        name: prefs.getString('${_prefsKey}_name') ?? '',
        decimals: prefs.getInt('${_prefsKey}_decimals') ?? 2,
        rate: prefs.getDouble('${_prefsKey}_rate') ?? 1,
      );
    } catch (_) {
      // Keep the peso default when storage is unavailable.
    }
  }

  /// Applies a `currency` block from any API payload. Ignores anything else.
  static Future<void> applyFromApi(dynamic json) async {
    if (json is! Map) return;
    final map = Map<String, dynamic>.from(json);
    if ((map['code'] ?? '').toString().isEmpty) return;
    await apply(AppCurrencySettings.fromJson(map));
  }

  static Future<void> apply(AppCurrencySettings next) async {
    if (notifier.value == next) return;
    notifier.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_prefsKey}_code', next.code);
      await prefs.setString('${_prefsKey}_symbol', next.symbol);
      await prefs.setString('${_prefsKey}_name', next.name);
      await prefs.setInt('${_prefsKey}_decimals', next.decimals);
      await prefs.setDouble('${_prefsKey}_rate', next.rate);
    } catch (_) {
      // Non-fatal: the in-memory value is already updated.
    }
  }

  /// Converts a peso amount into the display currency.
  static double convert(num pesoAmount) {
    final rate = notifier.value.rate;
    if (rate <= 0 || rate == 1) return pesoAmount.toDouble();
    return pesoAmount.toDouble() * rate;
  }

  /// Converts a display-currency amount back to pesos (for amount inputs).
  static double toPeso(num displayAmount) {
    final rate = notifier.value.rate;
    if (rate <= 0 || rate == 1) return displayAmount.toDouble();
    return displayAmount.toDouble() / rate;
  }
}

/// Rebuilds when the hotel changes its display currency.
class CurrencyBuilder extends StatelessWidget {
  const CurrencyBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppCurrencySettings currency)
      builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppCurrencySettings>(
      valueListenable: AppCurrency.notifier,
      builder: (context, currency, _) => builder(context, currency),
    );
  }
}
