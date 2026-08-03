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

/// Philippine peso formatting for bills, receipts, and admin fees.
String formatPeso(num amount, {bool signed = false}) {
  final value = amount.toDouble();
  final absText = value.abs().toStringAsFixed(2);
  final body = '₱$absText';
  if (!signed) {
    if (value < 0) return '−$body';
    return body;
  }
  if (value < 0) return '−$body';
  if (value > 0) return '+$body';
  return body;
}

/// Formats a bill/receipt line (charges positive, refunds/partial payments as −₱).
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
    return '₱${display.toStringAsFixed(2)} given';
  }
  if (isCredit) {
    return '−₱${display.toStringAsFixed(2)}';
  }
  return '₱${display.toStringAsFixed(2)}';
}
