import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dio_client.dart';
import 'hotel_credits_policy.dart';

/// True when the API rejected confirmation because hotel wallet credits are too low.
bool isHotelCreditsApprovalError(DioException e) {
  if (e.response?.statusCode != 422) {
    return false;
  }
  final data = e.response?.data;
  if (data is! Map) {
    return false;
  }
  final errors = data['errors'];
  if (errors is Map && errors.containsKey('credits')) {
    return true;
  }
  final msg = (data['message'] ?? '').toString().toLowerCase();
  return msg.contains('credit') &&
      (msg.contains('insufficient') ||
          msg.contains('zero') ||
          msg.contains('top up'));
}

/// Blocks confirmation when balance is zero or negative (client-side guard).
bool hotelCreditsTooLowToConfirm(double? balance) =>
    balance != null && HotelCreditsPolicy.isDepleted(balance);

Future<bool?> showInsufficientHotelCreditsDialog(
  BuildContext context, {
  String? message,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.account_balance_wallet_outlined, color: scheme.error),
      title: const Text('Top up credits required'),
      content: Text(
        message ??
            'Your hotel credit balance is too low to confirm this booking. '
                'Recharge via GCash or PayMaya in Settings, then try again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Top up credits'),
        ),
      ],
    ),
  );
}

/// Recharge flow shared by booking approval and settings.
Future<void> showHotelCreditsRechargeDialog(BuildContext context) async {
  final amountCtrl = TextEditingController(text: '100');
  String method = 'gcash';
  final payload = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('Recharge credits'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (PHP)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: method,
              items: const [
                DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                DropdownMenuItem(value: 'paymaya', child: Text('PayMaya')),
              ],
              onChanged: (v) => setLocal(() => method = v ?? method),
              decoration: const InputDecoration(
                labelText: 'Wallet',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
              'method': method,
            }),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
  amountCtrl.dispose();
  if (payload == null || !context.mounted) return;

  try {
    final res = await portalDio().post<Map<String, dynamic>>(
      '/admin/credits/recharge',
      data: payload,
    );
    if (!context.mounted) return;
    final data = Map<String, dynamic>.from(res.data ?? {});
    final checkoutUrl = (data['checkout_url'] ?? data['invoice_url'] ?? '')
        .toString()
        .trim();
    final msg = (data['message'] ??
            'Complete payment in your browser. Credits update after payment succeeds.')
        .toString();
    if (checkoutUrl.isNotEmpty) {
      final uri = Uri.tryParse(checkoutUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    if (!context.mounted) return;
    showAppMessage(context, msg);
  } on DioException catch (e) {
    if (!context.mounted) return;
    showAppMessage(context, dioErrorMessage(e), isError: true);
  }
}

/// Shows the top-up dialog when needed; returns false if approval should be aborted.
Future<bool> guardHotelCreditsBeforeApproval(
  BuildContext context, {
  required double? currentCredits,
  VoidCallback? onTopUp,
}) async {
  if (!hotelCreditsTooLowToConfirm(currentCredits)) {
    return true;
  }
  final topUp = await showInsufficientHotelCreditsDialog(
    context,
    message:
        'Your hotel credit balance is ₱0.00. Top up credits before you can confirm bookings.',
  );
  if (topUp == true) {
    if (onTopUp != null) {
      onTopUp();
    } else if (context.mounted) {
      await showHotelCreditsRechargeDialog(context);
    }
  }
  return false;
}

/// Handles API credit errors after a failed approve request.
Future<void> handleHotelCreditsApprovalError(
  BuildContext context,
  DioException e, {
  VoidCallback? onTopUp,
}) async {
  if (!isHotelCreditsApprovalError(e)) {
    return;
  }
  final topUp = await showInsufficientHotelCreditsDialog(
    context,
    message: dioErrorMessage(e),
  );
  if (topUp == true) {
    if (onTopUp != null) {
      onTopUp();
    } else if (context.mounted) {
      await showHotelCreditsRechargeDialog(context);
    }
  }
}
