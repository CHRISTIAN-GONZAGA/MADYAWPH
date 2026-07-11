import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../dio_client.dart';
import '../widgets/app_input.dart';
import '../widgets/app_scaffold.dart';

class MemberScanResult {
  const MemberScanResult({
    required this.shid,
    required this.name,
    required this.discountPercent,
    required this.pointsBalance,
    required this.pointsBalancePesos,
    required this.pointsPerPeso,
  });

  final String shid;
  final String name;
  final double discountPercent;
  final int pointsBalance;
  final double pointsBalancePesos;
  final double pointsPerPeso;
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

/// After scanning, optionally redeem points into the hotel credit wallet
/// (and optionally apply them to a booking).
Future<bool> promptRedeemMemberPoints(
  BuildContext context, {
  required MemberScanResult member,
  String? bookingId,
}) async {
  final pointsCtrl = TextEditingController();
  var busy = false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final pts = int.tryParse(pointsCtrl.text.trim()) ?? 0;
          final pesos = member.pointsPerPeso > 0
              ? pts / member.pointsPerPeso
              : 0.0;

          return AlertDialog(
            title: const Text('Redeem member points'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    member.name.isEmpty ? member.shid : member.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(member.shid),
                  const SizedBox(height: 12),
                  Text(
                    'Available: ${member.pointsBalance} pts '
                    '(≈ ₱${member.pointsBalancePesos.toStringAsFixed(2)})',
                  ),
                  const SizedBox(height: 12),
                  AppInput(
                    controller: pointsCtrl,
                    label: 'Points to redeem',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pts > 0
                        ? 'Hotel credit wallet will receive ≈ ₱${pesos.toStringAsFixed(2)}'
                        : 'Enter points to convert to hotel credit.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx, false),
                child: const Text('Skip'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final points = int.tryParse(pointsCtrl.text.trim());
                        if (points == null || points < 1) {
                          showAppMessage(
                            ctx,
                            'Enter a valid points amount.',
                            isError: true,
                          );
                          return;
                        }
                        if (points > member.pointsBalance) {
                          showAppMessage(
                            ctx,
                            'Not enough points.',
                            isError: true,
                          );
                          return;
                        }
                        setLocal(() => busy = true);
                        try {
                          await portalDio().post<Map<String, dynamic>>(
                            '/admin/member/redeem-points',
                            data: {
                              'member_shid_id': member.shid,
                              'points': points,
                              if (bookingId != null && bookingId.isNotEmpty)
                                'booking_id': bookingId,
                            },
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx, true);
                        } on DioException catch (e) {
                          if (!ctx.mounted) return;
                          showAppMessage(ctx, dioErrorMessage(e), isError: true);
                          setLocal(() => busy = false);
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Redeem'),
              ),
            ],
          );
        },
      );
    },
  );

  pointsCtrl.dispose();
  if (confirmed == true && context.mounted) {
    showAppMessage(context, 'Member points redeemed. Hotel credit wallet updated.');
  }
  return confirmed == true;
}

/// Load member by SHID and open the redeem dialog (no camera).
Future<bool> promptRedeemMemberPointsByShid(
  BuildContext context, {
  required String memberShidId,
  String? bookingId,
}) async {
  final member = await _validatePayload(context, memberShidId: memberShidId);
  if (member == null || !context.mounted) return false;
  if (member.pointsBalance <= 0) {
    showAppMessage(context, 'This member has no points to redeem.');
    return false;
  }
  return promptRedeemMemberPoints(
    context,
    member: member,
    bookingId: bookingId,
  );
}

/// Scan member QR, apply discount identity, then offer points redemption.
Future<MemberScanResult?> scanMemberForBooking(
  BuildContext context, {
  String? bookingId,
  bool offerRedeem = true,
}) async {
  final member = await scanAndValidateMemberShid(context);
  if (member == null || !context.mounted) return null;
  if (offerRedeem && member.pointsBalance > 0) {
    await promptRedeemMemberPoints(
      context,
      member: member,
      bookingId: bookingId,
    );
  }
  return member;
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
              'Scan the guest\'s MADYAWPH membership QR to apply their discount and redeem points.',
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
