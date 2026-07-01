import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';

/// Scans a MADYAWPH member QR (`madyaw:member:SHID-…`) and validates via API.
Future<String?> scanAndValidateMemberShid(BuildContext context) async {
  final raw = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => const _MemberQrScanScreen(),
    ),
  );
  if (raw == null || raw.trim().isEmpty) return null;

  try {
    final res = await publicDio().post<Map<String, dynamic>>(
      '/member/validate',
      data: {'qr_payload': raw.trim()},
    );
  if (!context.mounted) return null;
    if (res.data?['valid'] == true) {
      return (res.data?['member_shid_id'] ?? '').toString();
    }
    showAppMessage(
      context,
      (res.data?['message'] ?? 'Invalid membership.').toString(),
      isError: true,
    );
    return null;
  } on DioException catch (e) {
    if (!context.mounted) return null;
    showAppMessage(context, dioErrorMessage(e), isError: true);
    return null;
  }
}

/// Validates a typed SHID membership ID.
Future<({String shid, double percent, String name})?> validateMemberShidInput(
  BuildContext context,
  String input,
) async {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  try {
    final res = await publicDio().post<Map<String, dynamic>>(
      '/member/validate',
      data: {'member_shid_id': trimmed},
    );
    if (res.data?['valid'] != true) {
      if (context.mounted) {
        showAppMessage(
          context,
          (res.data?['message'] ?? 'Invalid membership.').toString(),
          isError: true,
        );
      }
      return null;
    }
    return (
      shid: (res.data?['member_shid_id'] ?? '').toString(),
      percent: (res.data?['discount_percent'] as num?)?.toDouble() ?? 0,
      name: (res.data?['full_name'] ?? '').toString(),
    );
  } on DioException catch (e) {
    if (context.mounted) {
      showAppMessage(context, dioErrorMessage(e), isError: true);
    }
    return null;
  }
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
              'Scan the guest\'s MADYAWPH membership QR to apply their discount.',
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
