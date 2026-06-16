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

/// Formats a bill/receipt line (charges positive, refunds as −₱).
String formatBillLineAmount(Map<dynamic, dynamic> line) {
  final amount = (line['amount'] as num?)?.toDouble() ?? 0;
  final type = (line['type'] ?? '').toString();
  final isCredit =
      line['is_credit'] == true || type == 'refund' || amount < 0;
  final display = amount.abs();
  if (isCredit) {
    return '−₱${display.toStringAsFixed(2)}';
  }
  return '₱${display.toStringAsFixed(2)}';
}
