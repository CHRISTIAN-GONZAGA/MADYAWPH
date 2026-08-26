import '../services/app_currency.dart';

/// Parses JSON numbers that may arrive as [num] or [String] (common from Mongo/PHP).
double parseJsonDouble(dynamic value, [double fallback = 0]) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return fallback;
    return double.tryParse(trimmed) ?? fallback;
  }
  return fallback;
}

/// Groups the integer part with thousands separators: 1234567.5 -> "1,234,567.50".
String _grouped(double value, int decimals) {
  final fixed = value.toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final whole = dot == -1 ? fixed : fixed.substring(0, dot);
  final rest = dot == -1 ? '' : fixed.substring(dot);
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '$buffer$rest';
}

/// Formats a peso amount in the hotel's display currency.
///
/// All amounts in the API are pesos; [AppCurrency] converts them when the hotel
/// runs on a different currency (e.g. a property in Korea showing ₩).
String formatMoney(
  num pesoAmount, {
  bool signed = false,
  int? decimals,
}) {
  final currency = AppCurrency.value;
  final converted = AppCurrency.convert(pesoAmount);
  final places = decimals ?? currency.decimals;
  final body = '${currency.symbol}${_grouped(converted.abs(), places)}';
  if (converted < 0) return '−$body';
  if (signed && converted > 0) return '+$body';
  return body;
}

/// Money without decimals — for dense tiles and summary cards.
String formatMoneyCompact(num pesoAmount) => formatMoney(pesoAmount, decimals: 0);

/// Legacy name kept so existing call sites keep working; the hotel's display
/// currency is applied, not necessarily pesos.
String formatPeso(num amount, {bool signed = false}) =>
    formatMoney(amount, signed: signed);

/// Formats a bill/receipt line (charges positive, refunds/partial payments as −).
String formatBillLineAmount(Map<dynamic, dynamic> line) {
  final amount = parseJsonDouble(line['amount']);
  final type = (line['type'] ?? '').toString();
  final isCashChange = type == 'cash_change';
  final isCredit = line['is_credit'] == true ||
      type == 'refund' ||
      type == 'partial_payment' ||
      type == 'member_points' ||
      type == 'member_discount' ||
      (!isCashChange && amount < 0);
  final display = amount.abs();
  if (isCashChange) {
    // Audit-only: money returned to guest (not a bill charge).
    return '${formatMoney(display)} given';
  }
  if (isCredit) {
    return '−${formatMoney(display)}';
  }
  return formatMoney(display);
}
