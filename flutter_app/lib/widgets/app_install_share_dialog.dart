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
  String? _installUrl;
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

    var url = kAppInstallUrl;
    if (url.isEmpty) {
      try {
        final res = await publicDio()
            .get<Map<String, dynamic>>('/platform/info')
            .timeout(const Duration(seconds: 15));
        url = (res.data?['app_install_url'] ?? '').toString().trim();
      } on DioException catch (e) {
        if (url.isEmpty && mounted) {
          _error = dioErrorMessage(e);
        }
      } catch (e) {
        if (url.isEmpty && mounted) {
          _error = '$e';
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _installUrl = url.isNotEmpty ? url : null;
      _loading = false;
      if (_installUrl == null && _error == null) {
        _error =
            'Install link is not configured yet. Set APP_INSTALL_URL on the server or rebuild the app with --dart-define=APP_INSTALL_URL=...';
      }
    });
  }

  Future<void> _copyLink() async {
    final url = _installUrl;
    if (url == null || url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    showAppMessage(context, 'Install link copied.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = _installUrl;

    return AlertDialog(
      title: const Text('Share the app'),
      content: SizedBox(
        width: 320,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            : url == null
                ? Text(
                    _error ?? 'Install link unavailable.',
                    textAlign: TextAlign.center,
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Scan this QR to download and install MADYAW on Android.',
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
                              data: url,
                              version: QrVersions.auto,
                              size: 220,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          url,
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
        if (url != null)
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
