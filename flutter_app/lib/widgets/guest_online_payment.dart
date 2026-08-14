import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';

import '../dio_client.dart';
import 'app_input.dart';
import 'chat_attachment.dart';
import 'hotel_wallet_pay_now.dart';
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
  });

  final bool paymongoConnected;
  final String qrUrl;
  final String gcashMobile;
  final String mayaMobile;
  final double depositPercent;
  final List<String> paymentMethodsHint;

  bool get hasManualWallet => gcashMobile.isNotEmpty || mayaMobile.isNotEmpty;

  bool get hasStaticQr => qrUrl.isNotEmpty;

  bool get canBookOnline =>
      paymongoConnected || hasManualWallet || hasStaticQr;

  /// PayMongo QR Ph hosted checkout (preferred when connected).
  bool get usesPaymongoQrPh => paymongoConnected;

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

/// Clear payment section for guest booking — QR Ph first when PayMongo is connected.
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
        'Hotel has not set up online payment yet (PayMongo QR Ph, scan QR, or wallet). '
        'Try again later or contact the hotel.',
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
        if (config.usesPaymongoQrPh) ...[
          _PaymongoQrPhCard(
            amountDue: amountDue,
            onPay: onPrimaryAction,
            loading: primaryLoading,
            enabled: primaryEnabled,
            buttonLabel: primaryLabel,
          ),
          if (config.hasStaticQr || config.hasManualWallet) ...[
            const SizedBox(height: 12),
            _ManualFallbackSection(
              config: config,
              amountDue: amountDue,
              paymentRefController: paymentRefController,
            ),
          ],
        ] else ...[
          Text(
            'Choose how to pay, then enter your transaction reference below.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          if (config.hasStaticQr) ...[
            _StaticQrSection(qrUrl: config.qrUrl),
            const SizedBox(height: 12),
          ],
          if (config.hasManualWallet) ...[
            _ManualWalletSection(
              config: config,
              amountDue: amountDue,
            ),
            const SizedBox(height: 12),
          ],
          AppInput(
            controller: paymentRefController,
            label: 'Payment reference *',
            hint: 'Paste GCash / Maya / QR Ph transaction ID after paying',
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
                      : 'Submit booking · paid ₱${amountDue.toStringAsFixed(2)}'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          config.usesPaymongoQrPh
              ? 'After QR Ph payment, return here — your booking updates automatically while the hotel approves.'
              : 'Hotel approval is required. You will see confirmation once front desk verifies your payment.',
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
  var _openingCheckout = false;

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

  Future<void> _payWithQrPh() async {
    if (_openingCheckout) return;
    setState(() => _openingCheckout = true);
    try {
      final opened = await startGuestPaymongoCheckout(
        context: context,
        hotelId: widget.hotelId,
        reference: widget.reference,
        guestEmail: widget.guestEmail,
        guestPhone: widget.guestPhone,
      );
      if (opened) widget.onPaymentStarted?.call();
    } finally {
      if (mounted) setState(() => _openingCheckout = false);
    }
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
                '$depositLabel deposit · ₱${_amountDue.toStringAsFixed(2)} due now',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              )
            else if (_amountDue > 0)
              Text(
                'Amount due: ₱${_amountDue.toStringAsFixed(2)}',
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
            else if (cfg != null && cfg.usesPaymongoQrPh) ...[
              _PaymongoQrPhCard(
                amountDue: _amountDue,
                onPay: _payWithQrPh,
                loading: _openingCheckout,
                enabled: true,
                buttonLabel: _openingCheckout
                    ? 'Opening QR Ph…'
                    : 'Pay with QR Ph · ₱${_amountDue.toStringAsFixed(2)}',
                compact: true,
              ),
            ] else if (cfg != null && cfg.hasStaticQr) ...[
              Text(
                'Scan the hotel QR, pay ₱${_amountDue.toStringAsFixed(2)}, '
                'then contact the hotel with your transaction reference.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Center(
                child: NetworkMediaImage(
                  url: cfg.qrUrl,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ),
              if (cfg.hasManualWallet) ...[
                const SizedBox(height: 12),
                _ManualWalletSection(config: cfg, amountDue: _amountDue),
              ],
            ] else if (cfg != null && cfg.hasManualWallet)
              _ManualWalletSection(config: cfg, amountDue: _amountDue)
            else
              Text(
                'Ask the hotel to enable PayMongo QR Ph or add a payment QR.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
              ),
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
                ? 'Pay ₱${amountDue.toStringAsFixed(2)} now (stay total)'
                : 'Pay ₱${amountDue.toStringAsFixed(2)} now · Stay total ₱${stayTotal.toStringAsFixed(2)}',
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

class _PaymongoQrPhCard extends StatelessWidget {
  const _PaymongoQrPhCard({
    required this.amountDue,
    required this.onPay,
    required this.loading,
    required this.enabled,
    this.buttonLabel,
    this.compact = false,
  });

  final double amountDue;
  final VoidCallback? onPay;
  final bool loading;
  final bool enabled;
  final String? buttonLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: scheme.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QR Ph (recommended)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                    ),
                    Text(
                      'Secure PayMongo checkout · scan with any bank or e-wallet app',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 14),
            _PaymentStepRow(
              step: '1',
              text: 'Tap the button below — your browser opens a secure payment page.',
            ),
            const SizedBox(height: 6),
            _PaymentStepRow(
              step: '2',
              text: 'Scan the QR Ph code with GCash, Maya, your bank app, or other QR Ph wallet.',
            ),
            const SizedBox(height: 6),
            _PaymentStepRow(
              step: '3',
              text: 'Return to this app — payment is recorded automatically.',
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: enabled && !loading ? onPay : null,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_scanner),
            label: Text(
              buttonLabel ??
                  (loading
                      ? 'Opening QR Ph…'
                      : 'Pay with QR Ph · ₱${amountDue.toStringAsFixed(2)}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentStepRow extends StatelessWidget {
  const _PaymentStepRow({required this.step, required this.text});

  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: scheme.primary,
          child: Text(
            step,
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
        ),
      ],
    );
  }
}

class _ManualFallbackSection extends StatelessWidget {
  const _ManualFallbackSection({
    required this.config,
    required this.amountDue,
    required this.paymentRefController,
  });

  final GuestPaymentConfig config;
  final double amountDue;
  final TextEditingController paymentRefController;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Manual fallback (not QR Ph checkout)',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
      subtitle: const Text(
        'Only if QR Ph checkout fails — send to hotel wallet or scan their QR, then paste reference.',
      ),
      children: [
        if (config.hasStaticQr) ...[
          _StaticQrSection(qrUrl: config.qrUrl),
          const SizedBox(height: 8),
        ],
        if (config.hasManualWallet)
          _ManualWalletSection(config: config, amountDue: amountDue),
        const SizedBox(height: 8),
        AppInput(
          controller: paymentRefController,
          label: 'Manual payment reference',
          hint: 'Only if you paid outside QR Ph checkout',
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _StaticQrSection extends StatelessWidget {
  const _StaticQrSection({required this.qrUrl});

  final String qrUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Scan hotel QR Ph',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        NetworkMediaImage(
          url: qrUrl,
          width: 200,
          height: 200,
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}

class _ManualWalletSection extends StatelessWidget {
  const _ManualWalletSection({
    required this.config,
    required this.amountDue,
  });

  final GuestPaymentConfig config;
  final double amountDue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Send Money (manual)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Opens GCash or Maya — you copy the hotel number and amount yourself. '
            'This is not the same as QR Ph checkout above.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 10),
          if (config.gcashMobile.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => HotelWalletPayNow.pay(
                context: context,
                wallet: HotelWalletApp.gcash,
                mobile: config.gcashMobile,
                amountPesos: amountDue,
              ),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text('GCash Send Money · ${config.gcashMobile}'),
            ),
          if (config.gcashMobile.isNotEmpty && config.mayaMobile.isNotEmpty)
            const SizedBox(height: 8),
          if (config.mayaMobile.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => HotelWalletPayNow.pay(
                context: context,
                wallet: HotelWalletApp.maya,
                mobile: config.mayaMobile,
                amountPesos: amountDue,
              ),
              icon: const Icon(Icons.payments_outlined),
              label: Text('Maya Send Money · ${config.mayaMobile}'),
            ),
        ],
      ),
    );
  }
}
