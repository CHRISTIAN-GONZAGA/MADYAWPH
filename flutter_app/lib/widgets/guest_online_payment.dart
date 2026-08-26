import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../dio_client.dart';
import '../services/app_currency.dart';
import '../utils/money_format.dart';
import 'app_input.dart';
import 'guest_payment_methods.dart';
import 'payment_redirect.dart';

/// Hotel online payment options for guest booking / status screens.
class GuestPaymentConfig {
  const GuestPaymentConfig({
    this.paymongoConnected = false,
    this.qrUrl = '',
    this.gcashMobile = '',
    this.mayaMobile = '',
    this.depositPercent = 50,
    this.paymentMethodsHint = const ['QR Ph'],
    this.methods = const [],
  });

  final bool paymongoConnected;
  final String qrUrl;
  final String gcashMobile;
  final String mayaMobile;
  final double depositPercent;
  final List<String> paymentMethodsHint;

  /// Per-method QR codes the hotel uploaded in Setup → Online payment QRs.
  final List<GuestPaymentMethod> methods;

  List<GuestPaymentMethod> get payableMethods =>
      methods.where((m) => m.isConfigured).toList();

  bool get hasMethodQrs => payableMethods.isNotEmpty;

  bool get hasManualWallet => gcashMobile.isNotEmpty || mayaMobile.isNotEmpty;

  bool get hasStaticQr => qrUrl.isNotEmpty;

  bool get canBookOnline => hasMethodQrs || hasManualWallet || hasStaticQr;

  /// Kept for older screens; guest booking no longer auto-opens PayMongo/GCash.
  bool get usesPaymongoQrPh => false;

  static GuestPaymentConfig fromJson(Map<String, dynamic>? data) {
    if (data == null) return const GuestPaymentConfig();
    final pm = data['paymongo'];
    final hints = pm is Map ? pm['payment_methods_hint'] : null;
    return GuestPaymentConfig(
      paymongoConnected: pm is Map && pm['connected'] == true,
      qrUrl: (data['qr_url'] ?? '').toString(),
      gcashMobile: (data['payment_gcash_mobile'] ?? '').toString().trim(),
      mayaMobile: (data['payment_maya_mobile'] ?? '').toString().trim(),
      depositPercent: ((data['online_booking_deposit_percent'] as num?)?.toDouble() ?? 50)
          .clamp(0, 100),
      paymentMethodsHint: hints is List
          ? hints.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const ['QR Ph'],
      methods: GuestPaymentMethod.listFrom(data['payment_methods']),
    );
  }
}

Future<GuestPaymentConfig> loadGuestPaymentConfig(String hotelId) async {
  if (hotelId.isEmpty) return const GuestPaymentConfig();
  try {
    final res = await publicDio().get<Map<String, dynamic>>(
      '/customer/payment-qr',
      queryParameters: {'hotel_id': hotelId},
    );
    await AppCurrency.applyFromApi(res.data?['currency']);
    return GuestPaymentConfig.fromJson(res.data);
  } catch (_) {
    return const GuestPaymentConfig();
  }
}

Future<bool> startGuestPaymongoCheckout({
  required BuildContext context,
  required String hotelId,
  required String reference,
  String guestEmail = '',
  String guestPhone = '',
}) async {
  try {
    showAppMessage(context, 'Opening QR Ph payment…');
    final body = <String, dynamic>{'hotel_id': hotelId};
    if (guestEmail.trim().isNotEmpty) body['guest_email'] = guestEmail.trim();
    if (guestPhone.trim().isNotEmpty) body['guest_phone'] = guestPhone.trim();

    final res = await publicDio().post<Map<String, dynamic>>(
      '/customer/reservations/$reference/payment',
      data: body,
    );
    if (!context.mounted) return false;
    return PaymentRedirect.maybeOpenFromResponse(context, res.data);
  } on DioException catch (e) {
    if (context.mounted) {
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
    return false;
  }
}

/// Payment section for guest booking: method buttons with their own QR codes,
/// plus PayMongo QR Ph checkout when the hotel has it connected.
class GuestOnlinePaymentPanel extends StatelessWidget {
  const GuestOnlinePaymentPanel({
    super.key,
    required this.config,
    required this.amountDue,
    required this.stayTotal,
    required this.depositPctLabel,
    required this.isFullDeposit,
    required this.paymentRefController,
    required this.onPrimaryAction,
    this.primaryLoading = false,
    this.primaryEnabled = true,
    this.primaryLabel,
  });

  final GuestPaymentConfig config;
  final double amountDue;
  final double stayTotal;
  final String depositPctLabel;
  final bool isFullDeposit;
  final TextEditingController paymentRefController;
  final VoidCallback? onPrimaryAction;
  final bool primaryLoading;
  final bool primaryEnabled;
  final String? primaryLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!config.canBookOnline) {
      return Text(
        'This hotel has not uploaded a payment QR yet. Contact the front desk '
        'or try again later.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step 2 · Pay online',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
        ),
        const SizedBox(height: 8),
        _AmountDueBanner(
          amountDue: amountDue,
          stayTotal: stayTotal,
          depositPctLabel: depositPctLabel,
          isFullDeposit: isFullDeposit,
        ),
        const SizedBox(height: 12),
        GuestPaymentMethodPicker(
          methods: config.methods,
          amountLabel: formatMoney(amountDue),
        ),
        const SizedBox(height: 12),
        AppInput(
          controller: paymentRefController,
          label: 'Payment reference *',
          hint: 'Paste the transaction ID shown after you pay',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: primaryEnabled && !primaryLoading ? onPrimaryAction : null,
          icon: primaryLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(
            primaryLabel ??
                (primaryLoading
                    ? 'Submitting…'
                    : 'Submit booking · paid ${formatMoney(amountDue)}'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Hotel approval is required. You will see confirmation once front desk verifies your payment.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
        ),
      ],
    );
  }
}

/// Pending payment card on booking status / member bookings.
class GuestOnlinePaymentPendingCard extends StatefulWidget {
  const GuestOnlinePaymentPendingCard({
    super.key,
    required this.hotelId,
    required this.reference,
    required this.reservation,
    this.guestEmail = '',
    this.guestPhone = '',
    this.onPaymentStarted,
  });

  final String hotelId;
  final String reference;
  final Map<String, dynamic> reservation;
  final String guestEmail;
  final String guestPhone;
  final VoidCallback? onPaymentStarted;

  @override
  State<GuestOnlinePaymentPendingCard> createState() =>
      _GuestOnlinePaymentPendingCardState();
}

class _GuestOnlinePaymentPendingCardState
    extends State<GuestOnlinePaymentPendingCard> {
  GuestPaymentConfig? _config;
  var _loadingConfig = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = await loadGuestPaymentConfig(widget.hotelId);
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _loadingConfig = false;
    });
  }

  double get _amountDue {
    final deposit = (widget.reservation['deposit_required'] as num?)?.toDouble();
    if (deposit != null && deposit > 0) return deposit;
    final paid = (widget.reservation['amount_paid'] as num?)?.toDouble() ?? 0;
    final total = (widget.reservation['estimated_total'] as num?)?.toDouble() ?? 0;
    final balance = (widget.reservation['balance_due'] as num?)?.toDouble();
    if (balance != null && balance > 0) return balance;
    if (total > paid) return total - paid;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfg = _config;
    final depositPct = (widget.reservation['deposit_percent'] as num?)?.toDouble();
    final depositLabel = depositPct == null
        ? null
        : (depositPct % 1 == 0
            ? '${depositPct.toStringAsFixed(0)}%'
            : '${depositPct.toStringAsFixed(1)}%');
    final paymentRef =
        (widget.reservation['payment_reference'] ?? '').toString();

    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Payment required',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (depositLabel != null && depositPct! < 100)
              Text(
                '$depositLabel deposit · ${formatMoney(_amountDue)} due now',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              )
            else if (_amountDue > 0)
              Text(
                'Amount due: ${formatMoney(_amountDue)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            if (paymentRef.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(
                'Reference on file: $paymentRef',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            if (_loadingConfig)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text(
                'Pick a method, pay ${formatMoney(_amountDue)}, then send the '
                'hotel your transaction reference.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              GuestPaymentMethodPicker(
                methods: cfg?.methods ?? const [],
                amountLabel: formatMoney(_amountDue),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AmountDueBanner extends StatelessWidget {
  const _AmountDueBanner({
    required this.amountDue,
    required this.stayTotal,
    required this.depositPctLabel,
    required this.isFullDeposit,
  });

  final double amountDue;
  final double stayTotal;
  final String depositPctLabel;
  final bool isFullDeposit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            isFullDeposit
                ? 'FULL PAYMENT REQUIRED — ONLINE ONLY'
                : '$depositPctLabel DEPOSIT REQUIRED — ONLINE ONLY',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.error,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            isFullDeposit
                ? 'Pay ${formatMoney(amountDue)} now (stay total)'
                : 'Pay ${formatMoney(amountDue)} now · Stay total ${formatMoney(stayTotal)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
