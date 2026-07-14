import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../dio_client.dart';
import '../utils/money_format.dart';
import '../widgets/app_scaffold.dart';

class MemberScanResult {
  const MemberScanResult({
    required this.shid,
    required this.name,
    required this.discountPercent,
    required this.pointsBalance,
    required this.pointsBalancePesos,
    required this.pointsPerPeso,
    this.paidInFullWithPoints = false,
    this.discountAppliedOnBooking = false,
  });

  final String shid;
  final String name;
  final double discountPercent;
  final int pointsBalance;
  final double pointsBalancePesos;
  final double pointsPerPeso;
  final bool paidInFullWithPoints;
  final bool discountAppliedOnBooking;

  int pointsNeededForAmount(double amountPesos) {
    if (amountPesos <= 0.009 || pointsPerPeso <= 0) return 0;
    return (amountPesos * pointsPerPeso).ceil();
  }

  bool canCoverAmount(double amountPesos) {
    final needed = pointsNeededForAmount(amountPesos);
    return needed > 0 && pointsBalance >= needed;
  }
}

/// Scans a MADYAWPH member QR and validates via API (discount + points).
Future<MemberScanResult?> scanAndValidateMemberShid(BuildContext context) async {
  final raw = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => const _MemberQrScanScreen(),
    ),
  );
  if (raw == null || raw.trim().isEmpty) return null;

  if (!context.mounted) return null;
  return _validatePayload(context, qrPayload: raw.trim());
}

/// Validates a typed SHID membership ID.
Future<({String shid, double percent, String name})?> validateMemberShidInput(
  BuildContext context,
  String input,
) async {
  final result = await _validatePayload(context, memberShidId: input.trim());
  if (result == null) return null;
  return (shid: result.shid, percent: result.discountPercent, name: result.name);
}

Future<MemberScanResult?> _validatePayload(
  BuildContext context, {
  String? qrPayload,
  String? memberShidId,
}) async {
  try {
    final res = await publicDio().post<Map<String, dynamic>>(
      '/member/validate',
      data: {
        if (qrPayload != null) 'qr_payload': qrPayload,
        if (memberShidId != null) 'member_shid_id': memberShidId,
      },
    );
    if (!context.mounted) return null;
    if (res.data?['valid'] != true) {
      showAppMessage(
        context,
        (res.data?['message'] ?? 'Invalid membership.').toString(),
        isError: true,
      );
      return null;
    }
    return MemberScanResult(
      shid: (res.data?['member_shid_id'] ?? '').toString(),
      name: (res.data?['full_name'] ?? '').toString(),
      discountPercent: (res.data?['discount_percent'] as num?)?.toDouble() ?? 0,
      pointsBalance: (res.data?['points_balance'] as num?)?.toInt() ?? 0,
      pointsBalancePesos:
          (res.data?['points_balance_pesos'] as num?)?.toDouble() ?? 0,
      pointsPerPeso: (res.data?['points_per_peso'] as num?)?.toDouble() ?? 10,
    );
  } on DioException catch (e) {
    if (!context.mounted) return null;
    showAppMessage(context, dioErrorMessage(e), isError: true);
    return null;
  }
}

/// Post-scan sheet: auto-applied discount + optional full-balance points payment.
Future<MemberScanResult?> showMemberScanActions(
  BuildContext context, {
  required MemberScanResult member,
  required double amountDuePesos,
  String? bookingId,
  bool discountAlreadyApplied = false,
}) async {
  final pointsNeeded = member.pointsNeededForAmount(amountDuePesos);
  final canPayFull = member.canCoverAmount(amountDuePesos);
  var busy = false;
  var working = member;

  final result = await showDialog<MemberScanResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Member scanned'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    working.name.isEmpty ? working.shid : working.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(working.shid),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      working.discountPercent > 0
                          ? (discountAlreadyApplied
                              ? '${working.discountPercent.toStringAsFixed(0)}% member discount is applied.'
                              : '${working.discountPercent.toStringAsFixed(0)}% member discount will be applied automatically.')
                          : 'No member discount is configured by central admin right now.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Stay amount due: ${formatPeso(amountDuePesos)}',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  _PointsStatRow(
                    label: 'Member points',
                    value: '${working.pointsBalance} pts',
                  ),
                  _PointsStatRow(
                    label: '≈ peso value',
                    value: formatPeso(working.pointsBalancePesos),
                  ),
                  _PointsStatRow(
                    label: 'Points needed for full stay',
                    value: amountDuePesos <= 0.009
                        ? '—'
                        : '$pointsNeeded pts',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    amountDuePesos <= 0.009
                        ? 'No remaining balance to pay with points.'
                        : (canPayFull
                            ? 'Points are enough to cover the entire stay.'
                            : 'Points are not enough to cover the entire stay. Use cash/GCash for the remainder (or skip points).'),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: canPayFull
                              ? Theme.of(ctx).colorScheme.primary
                              : Theme.of(ctx).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx, working),
                child: const Text('Continue with discount'),
              ),
              if (canPayFull &&
                  bookingId != null &&
                  bookingId.isNotEmpty &&
                  amountDuePesos > 0.009)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setLocal(() => busy = true);
                          try {
                            await portalDio().post<Map<String, dynamic>>(
                              '/admin/member/redeem-points',
                              data: {
                                'member_shid_id': working.shid,
                                'booking_id': bookingId,
                                'pay_full_balance': true,
                              },
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(
                              ctx,
                              MemberScanResult(
                                shid: working.shid,
                                name: working.name,
                                discountPercent: working.discountPercent,
                                pointsBalance:
                                    (working.pointsBalance - pointsNeeded)
                                        .clamp(0, working.pointsBalance),
                                pointsBalancePesos: working.pointsBalancePesos,
                                pointsPerPeso: working.pointsPerPeso,
                                paidInFullWithPoints: true,
                                discountAppliedOnBooking:
                                    working.discountAppliedOnBooking,
                              ),
                            );
                          } on DioException catch (e) {
                            if (!ctx.mounted) return;
                            showAppMessage(
                              ctx,
                              dioErrorMessage(e),
                              isError: true,
                            );
                            setLocal(() => busy = false);
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Pay full stay with points'),
                ),
            ],
          );
        },
      );
    },
  );

  return result;
}

class _PointsStatRow extends StatelessWidget {
  const _PointsStatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Scan member QR, auto-apply discount identity, then offer full points payment.
Future<MemberScanResult?> scanMemberForBooking(
  BuildContext context, {
  String? bookingId,
  double amountDuePesos = 0,
  double grossAmountPesos = 0,
  bool offerPointsPayment = true,
  bool applyDiscountToBooking = false,
}) async {
  final scanned = await scanAndValidateMemberShid(context);
  if (scanned == null || !context.mounted) return null;

  var member = scanned;
  var discountAlreadyApplied = false;
  var due = amountDuePesos;
  if (due <= 0.009 && grossAmountPesos > 0.009) {
    final pct = member.discountPercent.clamp(0, 100);
    due = ((grossAmountPesos * (1 - (pct / 100))) * 2).roundToDouble() / 2;
    // Match hotel round-to-50 when helper unavailable here; walk-in callers
    // should prefer amountDuePesos after they round.
    due = _round50(due);
  }

  if (applyDiscountToBooking &&
      bookingId != null &&
      bookingId.trim().isNotEmpty) {
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/bookings/$bookingId/apply-member',
        data: {'member_shid_id': member.shid},
      );
      if (!context.mounted) return member;
      final bill = res.data?['bill'];
      final billMap = bill is Map
          ? Map<String, dynamic>.from(bill)
          : const <String, dynamic>{};
      final quote = res.data?['points_quote'];
      final quoteMap = quote is Map
          ? Map<String, dynamic>.from(quote)
          : const <String, dynamic>{};
      final balance = parseJsonDouble(
        billMap['balance_due'] ??
            billMap['total_due'] ??
            due,
      );
      discountAlreadyApplied = res.data?['discount_applied'] == true ||
          member.discountPercent > 0;
      member = MemberScanResult(
        shid: member.shid,
        name: member.name,
        discountPercent:
            (res.data?['discount_percent'] as num?)?.toDouble() ??
                member.discountPercent,
        pointsBalance: (quoteMap['points_available'] as num?)?.toInt() ??
            member.pointsBalance,
        pointsBalancePesos:
            (quoteMap['points_balance_pesos'] as num?)?.toDouble() ??
                member.pointsBalancePesos,
        pointsPerPeso: (quoteMap['points_per_peso'] as num?)?.toDouble() ??
            member.pointsPerPeso,
        discountAppliedOnBooking: true,
      );
      due = balance;
      showAppMessage(
        context,
        discountAlreadyApplied
            ? 'Member linked. ${member.discountPercent.toStringAsFixed(0)}% discount applied.'
            : 'Member linked to this stay.',
      );
    } on DioException catch (e) {
      if (!context.mounted) return member;
      showAppMessage(context, dioErrorMessage(e), isError: true);
      return member;
    }
  }

  if (!offerPointsPayment || !context.mounted) return member;

  final after = await showMemberScanActions(
    context,
    member: member,
    amountDuePesos: due,
    bookingId: bookingId,
    discountAlreadyApplied:
        discountAlreadyApplied || member.discountAppliedOnBooking,
  );
  if (after?.paidInFullWithPoints == true && context.mounted) {
    showAppMessage(context, 'Stay paid in full with member points.');
  }
  return after ?? member;
}

double _round50(double value) {
  if (value <= 0) return 0;
  return (value / 50).round() * 50.0;
}

/// @deprecated Prefer [scanMemberForBooking] with amountDuePesos.
Future<bool> promptRedeemMemberPoints(
  BuildContext context, {
  required MemberScanResult member,
  String? bookingId,
  double amountDuePesos = 0,
}) async {
  final result = await showMemberScanActions(
    context,
    member: member,
    amountDuePesos: amountDuePesos,
    bookingId: bookingId,
  );
  return result?.paidInFullWithPoints == true;
}

/// Load member by SHID and open the post-scan actions (no camera).
Future<bool> promptRedeemMemberPointsByShid(
  BuildContext context, {
  required String memberShidId,
  String? bookingId,
  double amountDuePesos = 0,
}) async {
  final member = await _validatePayload(context, memberShidId: memberShidId);
  if (member == null || !context.mounted) return false;
  final result = await showMemberScanActions(
    context,
    member: member,
    amountDuePesos: amountDuePesos,
    bookingId: bookingId,
  );
  return result?.paidInFullWithPoints == true;
}

class _MemberQrScanScreen extends StatefulWidget {
  const _MemberQrScanScreen();

  @override
  State<_MemberQrScanScreen> createState() => _MemberQrScanScreenState();
}

class _MemberQrScanScreenState extends State<_MemberQrScanScreen> {
  bool _handled = false;

  void _onDetect(String raw) {
    if (_handled) return;
    final payload = raw.trim();
    if (payload.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Scan member QR')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Scan the guest\'s MADYAWPH membership QR to apply the central admin discount and optionally pay the full stay with points.',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                for (final barcode in capture.barcodes) {
                  final raw = barcode.rawValue;
                  if (raw != null && raw.isNotEmpty) {
                    _onDetect(raw);
                    break;
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
