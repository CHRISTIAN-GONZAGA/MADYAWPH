import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:open_filex/open_filex.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../dio_client.dart';
import '../../widgets/app_scaffold.dart';

/// View / regenerate / print a room-specific guest portal QR code.
class AdminRoomGuestQrScreen extends StatefulWidget {
  const AdminRoomGuestQrScreen({
    super.key,
    required this.roomId,
    this.roomNumber,
  });

  final String roomId;
  final String? roomNumber;

  @override
  State<AdminRoomGuestQrScreen> createState() => _AdminRoomGuestQrScreenState();
}

class _AdminRoomGuestQrScreenState extends State<AdminRoomGuestQrScreen> {
  String? _payload;
  String? _hotelName;
  String? _roomNumber;
  bool _loading = true;
  bool _regenerating = false;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _roomNumber = widget.roomNumber;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/rooms/${widget.roomId}/guest-portal-qr',
      );
      if (!mounted) return;
      setState(() {
        _payload = (res.data?['qr_payload'] ?? '').toString();
        _hotelName = (res.data?['hotel_name'] ?? '').toString();
        _roomNumber = (res.data?['room_number'] ?? _roomNumber ?? '').toString();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dioErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _regenerate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate room QR?'),
        content: const Text(
          'Any printed copies of this room QR will stop working. Print the new code and place it in the room.',
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
        '/admin/rooms/${widget.roomId}/guest-portal-qr',
      );
      if (!mounted) return;
      setState(() {
        _payload = (res.data?['qr_payload'] ?? '').toString();
        _hotelName = (res.data?['hotel_name'] ?? _hotelName ?? '').toString();
        _roomNumber =
            (res.data?['room_number'] ?? _roomNumber ?? '').toString();
      });
      showAppMessage(context, 'Room QR updated.');
    } on DioException catch (e) {
      if (!mounted) return;
      showAppMessage(context, dioErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _printQr() async {
    final payload = (_payload ?? '').trim();
    if (payload.isEmpty || _printing) return;
    setState(() => _printing = true);
    try {
      final painter = QrPainter(
        data: payload,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        gapless: true,
      );
      final imageData = await painter.toImageData(
        1024,
        format: ui.ImageByteFormat.png,
      );
      if (imageData == null) {
        throw Exception('Could not render QR image.');
      }

      final roomLabel = (_roomNumber ?? '').trim().isEmpty
          ? widget.roomId
          : _roomNumber!.trim();
      final file = File(
        '${Directory.systemTemp.path}/room_${roomLabel}_guest_qr.png',
      );
      await file.writeAsBytes(imageData.buffer.asUint8List(), flush: true);

      final result = await OpenFilex.open(file.path, type: 'image/png');
      if (!mounted) return;
      if (result.type != ResultType.done) {
        showAppMessage(
          context,
          result.message.isNotEmpty
              ? result.message
              : 'QR saved to ${file.path}. Open it to print.',
        );
      } else {
        showAppMessage(
          context,
          'QR opened. Use your device share/print options to print it.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$e', isError: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roomLabel =
        (_roomNumber ?? '').trim().isEmpty ? 'Room' : 'Room $_roomNumber';

    return AppScaffold(
      appBar: AppBar(title: Text('$roomLabel QR')),
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
                      const SizedBox(height: 4),
                    ],
                    Text(
                      roomLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Guests scan this code in the app, then enter only the 4-character room password. No room number is needed.',
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
                    FilledButton.icon(
                      onPressed: _printing ? null : _printQr,
                      icon: _printing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.print_outlined),
                      label: Text(_printing ? 'Preparing…' : 'Print room QR code'),
                    ),
                    const SizedBox(height: 12),
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
