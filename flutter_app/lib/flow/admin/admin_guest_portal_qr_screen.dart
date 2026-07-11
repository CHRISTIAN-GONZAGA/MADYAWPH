import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../dio_client.dart';
import '../../widgets/app_scaffold.dart';

/// Display and regenerate the hotel-unique guest portal QR code.
class AdminGuestPortalQrScreen extends StatefulWidget {
  const AdminGuestPortalQrScreen({super.key});

  @override
  State<AdminGuestPortalQrScreen> createState() =>
      _AdminGuestPortalQrScreenState();
}

class _AdminGuestPortalQrScreenState extends State<AdminGuestPortalQrScreen> {
  String? _payload;
  String? _hotelName;
  bool _loading = true;
  bool _regenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/hotel/guest-portal-qr',
      );
      if (!mounted) return;
      setState(() {
        _payload = (res.data?['qr_payload'] ?? '').toString();
        _hotelName = (res.data?['hotel_name'] ?? '').toString();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _regenerate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate QR code?'),
        content: const Text(
          'The current printed QR will stop working. Print or display the new code at your front desk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _regenerating = true);
    try {
      final res = await portalDio().post<Map<String, dynamic>>(
        '/admin/hotel/guest-portal-qr',
      );
      if (!mounted) return;
      setState(() {
        _payload = (res.data?['qr_payload'] ?? '').toString();
        _hotelName = (res.data?['hotel_name'] ?? _hotelName ?? '').toString();
      });
      showAppMessage(context, 'Guest portal QR updated.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppScaffold(
      appBar: AppBar(title: const Text('Guest portal QR')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if ((_hotelName ?? '').isNotEmpty) ...[
                      Text(
                        _hotelName!,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Guests can scan this front-desk code, then enter room number and password. Prefer printing each room’s own QR (View room QR code) so guests only need the password.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if ((_payload ?? '').isNotEmpty)
                      Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: QrImageView(
                              data: _payload!,
                              version: QrVersions.auto,
                              size: 240,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _regenerating ? null : _regenerate,
                      icon: _regenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Regenerate QR code'),
                    ),
                  ],
                ),
    );
  }
}
