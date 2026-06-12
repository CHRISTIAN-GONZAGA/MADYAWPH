import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../dio_client.dart';
import '../widgets/app_scaffold.dart';
import 'guest_portal_flow.dart';

/// Scan a hotel guest-portal QR and route to room login.
class GuestPortalQrScanScreen extends StatefulWidget {
  const GuestPortalQrScanScreen({super.key});

  @override
  State<GuestPortalQrScanScreen> createState() =>
      _GuestPortalQrScanScreenState();
}

class _GuestPortalQrScanScreenState extends State<GuestPortalQrScanScreen> {
  bool _busy = false;
  bool _handled = false;
  String? _error;

  Future<void> _onScan(String raw) async {
    if (_busy || _handled) return;
    final payload = raw.trim();
    if (payload.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await publicDio().post<Map<String, dynamic>>(
        '/guest/portal/resolve',
        data: {'payload': payload},
      );
      final hotelId = (res.data?['hotel_id'] ?? '').toString();
      if (hotelId.isEmpty) {
        setState(() {
          _error = 'Could not read this QR code.';
          _busy = false;
        });
        return;
      }

      _handled = true;
      if (!mounted) return;
      final hotelName = (res.data?['hotel_name'] ?? '').toString();
      await openGuestPortalLogin(
        context,
        hotelId: hotelId,
        hotelName: hotelName.isEmpty ? null : hotelName,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: const Text('Scan hotel QR')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    for (final code in capture.barcodes) {
                      final raw = code.rawValue;
                      if (raw != null && raw.isNotEmpty) {
                        _onScan(raw);
                        break;
                      }
                    }
                  },
                ),
                if (_busy)
                  const ColoredBox(
                    color: Color(0x88000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Point your camera at the guest portal QR displayed at your hotel front desk.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
