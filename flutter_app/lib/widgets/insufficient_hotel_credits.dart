import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';

import '../dio_client.dart';
import 'chat_attachment.dart';
import 'hotel_credits_policy.dart';
import 'payment_redirect.dart';

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
                'Recharge via PayMongo or scan the platform QR Ph, then try again.',
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
/// PayMongo checkout plus manual platform QR Ph (central admin screenshot).
Future<void> showHotelCreditsRechargeDialog(BuildContext context) async {
  final amountCtrl = TextEditingController(text: '1000');
  final refCtrl = TextEditingController();
  var method = 'qrph';
  var qrUrl = '';
  var paymongoEnabled = true;
  try {
    final info = await publicDio().get<Map<String, dynamic>>('/platform/info');
    qrUrl = ChatAttachment.resolveMediaUrl(
      (info.data?['credit_wallet_qr_url'] ?? '').toString(),
    );
    paymongoEnabled = info.data?['paymongo_checkout_enabled'] != false;
  } catch (_) {}
  if (!paymongoEnabled) method = 'qrph_manual';
  if (!context.mounted) {
    amountCtrl.dispose();
    refCtrl.dispose();
    return;
  }

  final payload = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('Recharge credits'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PayMongo is instant. Or scan the platform QR Ph posted by central admin and submit the reference for approval.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
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
                value: method,
                items: [
                  if (paymongoEnabled)
                    const DropdownMenuItem(
                      value: 'qrph',
                      child: Text('QR Ph — PayMongo (opens in browser)'),
                    ),
                  const DropdownMenuItem(
                    value: 'qrph_manual',
                    child: Text('QR Ph — scan platform QR (manual approval)'),
                  ),
                  const DropdownMenuItem(
                    value: 'gcash',
                    child: Text('GCash (online)'),
                  ),
                  const DropdownMenuItem(
                    value: 'paymaya',
                    child: Text('PayMaya (online)'),
                  ),
                ],
                onChanged: (v) => setLocal(() => method = v ?? method),
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  border: OutlineInputBorder(),
                ),
              ),
              if (method == 'qrph_manual') ...[
                const SizedBox(height: 12),
                if (qrUrl.isNotEmpty)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: NetworkMediaImage(
                        url: qrUrl,
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                    ),
                  )
                else
                  const Card(
                    child: ListTile(
                      title: Text('Platform QR Ph not uploaded yet'),
                      subtitle: Text(
                        'Ask central admin to post the hotel credit-wallet QR screenshot.',
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Payment reference / transaction ID',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (method == 'qrph_manual') {
                if (qrUrl.isEmpty) return;
                if (refCtrl.text.trim().isEmpty) return;
              }
              Navigator.of(context).pop({
                'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
                'method': method,
                if (method == 'qrph_manual')
                  'payment_reference': refCtrl.text.trim(),
              });
            },
            child: Text(
              method == 'qrph_manual'
                  ? 'Submit for approval'
                  : method == 'qrph'
                      ? 'Continue to PayMongo'
                      : 'Continue',
            ),
          ),
        ],
      ),
    ),
  );
  amountCtrl.dispose();
  refCtrl.dispose();
  if (payload == null || !context.mounted) return;

  try {
    if (payload['method'] == 'qrph_manual') {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/credits/recharge-request',
        data: {
          'amount': payload['amount'],
          'payment_reference': payload['payment_reference'],
        },
      );
      if (!context.mounted) return;
      showAppMessage(
        context,
        (res.data?['message'] ??
                'Top-up submitted. Credits apply after platform approval.')
            .toString(),
      );
      return;
    }

    final res = await portalDio().post<Map<String, dynamic>>(
      '/admin/credits/recharge',
      data: payload,
    );
    if (!context.mounted) return;
    final data = Map<String, dynamic>.from(res.data ?? {});
    if (PaymentRedirect.responseRequiresRedirect(data)) {
      await PaymentRedirect.maybeOpenFromResponse(context, data);
    }
    if (!context.mounted) return;
    showAppMessage(
      context,
      (data['message'] ??
              'Complete payment in your browser. Credits update after payment succeeds.')
          .toString(),
    );
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
