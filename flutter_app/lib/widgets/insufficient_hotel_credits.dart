import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../dio_client.dart';
import '../utils/money_format.dart';
import 'chat_attachment.dart';
import 'hotel_credits_policy.dart';
import 'payment_proof_picker.dart';
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

/// Appends the platform wallet fee to an approval success message when charged.
String approvalMessageWithWalletFee(String base, Map<String, dynamic>? wallet) {
  final fee = parseJsonDouble(wallet?['fee']);
  if (fee <= 0) {
    return base;
  }
  final roomTotal = wallet?['room_total'] != null
      ? parseJsonDouble(wallet?['room_total'])
      : null;
  final feePercent = parseJsonDouble(wallet?['fee_percent'], 8);
  final balance = wallet?['balance_after'] != null
      ? parseJsonDouble(wallet?['balance_after'])
      : null;
  final percentLabel = feePercent == feePercent.roundToDouble()
      ? feePercent.toStringAsFixed(0)
      : feePercent.toStringAsFixed(2);
  var msg = '$base $percentLabel% platform fee (${formatMoney(fee)}';
  if (roomTotal != null) {
    msg += ' of ${formatMoney(roomTotal)} booking total';
  }
  msg += ') deducted from hotel credits';
  if (balance != null) {
    msg += '. Balance: ${formatMoney(balance)}';
  }
  return '$msg.';
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
/// PayMongo checkout (instant) or scan the platform QR and wait for approval.
Future<void> showHotelCreditsRechargeDialog(BuildContext context) async {
  final amountCtrl = TextEditingController(text: '1000');
  final refCtrl = TextEditingController();
  var method = 'paymongo';
  var qrUrl = '';
  var paymongoEnabled = true;
  XFile? proof;
  try {
    final info = await publicDio().get<Map<String, dynamic>>('/platform/info');
    qrUrl = ChatAttachment.resolveMediaUrl(
      (info.data?['credit_wallet_qr_url'] ?? '').toString(),
    );
    paymongoEnabled = info.data?['paymongo_checkout_enabled'] != false;
  } catch (_) {}
  if (!paymongoEnabled) method = 'qr';
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
                'Pay with PayMongo to add credits automatically, or scan the platform QR and submit a reference plus screenshot for central admin approval.',
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
              const SizedBox(height: 12),
              if (paymongoEnabled)
                _RechargeChoice(
                  selected: method == 'paymongo',
                  title: 'Pay with PayMongo',
                  subtitle: 'Credits apply automatically after payment succeeds.',
                  onTap: () => setLocal(() => method = 'paymongo'),
                ),
              if (paymongoEnabled) const SizedBox(height: 8),
              _RechargeChoice(
                selected: method == 'qr',
                title: 'Scan QR',
                subtitle:
                    'Pay with the QR uploaded by central admin, then wait for approval.',
                onTap: () => setLocal(() => method = 'qr'),
              ),
              if (method == 'qr') ...[
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
                        'Ask central admin to post the hotel credit-wallet QR.',
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
                const SizedBox(height: 10),
                PaymentProofPicker(
                  file: proof,
                  onChanged: (file) => setLocal(() => proof = file),
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
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (amount < 100) return;
              if (method == 'qr') {
                if (qrUrl.isEmpty) return;
                if (refCtrl.text.trim().isEmpty) return;
                if (proof == null) return;
              }
              Navigator.of(context).pop({
                'amount': amount,
                'method': method,
                if (method == 'qr') 'payment_reference': refCtrl.text.trim(),
                if (method == 'qr') 'proof': proof,
              });
            },
            child: Text(
              method == 'qr' ? 'Submit for approval' : 'Continue to PayMongo',
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
    if (payload['method'] == 'qr') {
      final form = await ChatAttachment.formWithImage(
        fields: {
          'amount': payload['amount'],
          'payment_reference': payload['payment_reference'],
        },
        file: payload['proof'] as XFile,
      );
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/credits/recharge-request',
        data: form,
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
      data: {
        'amount': payload['amount'],
        'method': 'qrph',
      },
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

class _RechargeChoice extends StatelessWidget {
  const _RechargeChoice({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
