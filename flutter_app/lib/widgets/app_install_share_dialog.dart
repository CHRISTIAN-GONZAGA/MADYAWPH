import 'package:dio/dio.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config.dart';
import '../dio_client.dart';

/// Shows a QR code that links to the MADYAW Android APK for direct install.
Future<void> showAppInstallShareDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => const _AppInstallShareDialog(),
  );
}

class _AppInstallShareDialog extends StatefulWidget {
  const _AppInstallShareDialog();

  @override
  State<_AppInstallShareDialog> createState() => _AppInstallShareDialogState();
}

class _AppInstallShareDialogState extends State<_AppInstallShareDialog> {
  /// Destination users should open / copy (Drive folder).
  String? _shareUrl;

  /// Encoded in the QR: tracking URL that emails on scan then redirects.
  String? _qrUrl;

  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveInstallUrl();
  }

  Future<void> _resolveInstallUrl() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    var shareUrl = kAppInstallUrl;
    var qrUrl = kAppInstallQrUrl;

    try {
      final res = await publicDio()
          .get<Map<String, dynamic>>('/platform/info')
          .timeout(const Duration(seconds: 15));
      final remoteShare =
          (res.data?['app_install_url'] ?? '').toString().trim();
      final remoteQr =
          (res.data?['app_install_qr_url'] ?? '').toString().trim();
      // Build-time URL wins when set (keeps APK install link current even if
      // the server still has a stale APP_INSTALL_URL). Server fills gaps only.
      if (shareUrl.isEmpty && remoteShare.isNotEmpty) shareUrl = remoteShare;
      if (remoteQr.isNotEmpty) qrUrl = remoteQr;
    } on DioException catch (e) {
      // Keep build-time / local defaults when the API is unreachable.
      if (shareUrl.isEmpty && mounted) {
        _error = dioErrorMessage(e);
      }
    } catch (e) {
      if (shareUrl.isEmpty && mounted) {
        _error = '$e';
      }
    }

    if (!mounted) return;
    setState(() {
      _shareUrl = shareUrl.isNotEmpty ? shareUrl : null;
      _qrUrl = qrUrl.isNotEmpty ? qrUrl : null;
      _loading = false;
      if ((_shareUrl == null || _qrUrl == null) && _error == null) {
        _error =
            'Install link is not configured yet. Set APP_INSTALL_URL on the server or rebuild the app with --dart-define=APP_INSTALL_URL=...';
      }
    });
  }

  Future<void> _copyLink() async {
    final url = _shareUrl;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    showAppMessage(context, 'Install link copied.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shareUrl = _shareUrl;
    final qrUrl = _qrUrl;
    final ready = shareUrl != null && qrUrl != null;

    return AlertDialog(
      title: const Text('Share the app'),
      content: SizedBox(
        width: 320,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            : !ready
                ? Text(
                    _error ?? 'Install link unavailable.',
                    textAlign: TextAlign.center,
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Scan this QR with a phone camera to download MADYAW on Android.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: QrImageView(
                              data: qrUrl,
                              version: QrVersions.auto,
                              size: 220,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          shareUrl,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
      ),
      actions: [
        if (ready)
          TextButton.icon(
            onPressed: _copyLink,
            icon: const Icon(Icons.link),
            label: const Text('Copy link'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
