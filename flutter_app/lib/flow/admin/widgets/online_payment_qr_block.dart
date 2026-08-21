import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_input.dart';
import '../../../widgets/chat_attachment.dart';

bool isOnlinePaymentMethod(String method) {
  final m = method.trim().toLowerCase();
  return m == 'gcash' ||
      m == 'paymaya' ||
      m == 'maya' ||
      m == 'online' ||
      m == 'e-wallet' ||
      m == 'ewallet' ||
      m == 'qr ph' ||
      m == 'qrph' ||
      m.contains('card') ||
      m.contains('bank') ||
      m.contains('qr');
}

/// Loads hotel QR Ph image + collects payment reference for online methods.
class OnlinePaymentQrBlock extends StatefulWidget {
  const OnlinePaymentQrBlock({
    super.key,
    required this.paymentMethod,
    required this.referenceController,
  });

  final String paymentMethod;
  final TextEditingController referenceController;

  @override
  State<OnlinePaymentQrBlock> createState() => _OnlinePaymentQrBlockState();
}

class _OnlinePaymentQrBlockState extends State<OnlinePaymentQrBlock> {
  String? _qrUrl;
  String _gcash = '';
  String _maya = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (isOnlinePaymentMethod(widget.paymentMethod)) {
      _loadQr();
    }
  }

  @override
  void didUpdateWidget(covariant OnlinePaymentQrBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paymentMethod != widget.paymentMethod) {
      if (isOnlinePaymentMethod(widget.paymentMethod)) {
        _loadQr();
      } else {
        setState(() {
          _qrUrl = null;
          _error = null;
        });
      }
    }
  }

  Future<void> _loadQr() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/hotel/payment-qr',
      );
      final resolved = (res.data?['qr_url'] ?? '').toString().trim();
      final stored = (res.data?['payment_qr_url'] ?? '').toString().trim();
      final url = resolved.isNotEmpty
          ? resolved
          : (stored.isEmpty ? '' : ChatAttachment.resolveMediaUrl(stored));
      if (!mounted) return;
      setState(() {
        _qrUrl = url.isEmpty ? null : url;
        _gcash = (res.data?['payment_gcash_mobile'] ?? '').toString().trim();
        _maya = (res.data?['payment_maya_mobile'] ?? '').toString().trim();
        _loading = false;
        if (url.isEmpty) {
          _error = 'No QR Ph image uploaded yet. Ask admin to set it in Setup → Online payment.';
        }
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = dioErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isOnlinePaymentMethod(widget.paymentMethod)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          'Hotel QR Ph',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Guest scans this code with GCash, Maya, or any QR Ph app. '
          'Admins set it in Setup → Online payment.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_qrUrl != null)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                ChatAttachment.resolveMediaUrl(_qrUrl!),
                height: 180,
                width: 180,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(
                  'Could not load QR image.',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          )
        else if (_error != null)
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
          ),
        if (_gcash.isNotEmpty || _maya.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (_gcash.isNotEmpty)
            Text('GCash: $_gcash', style: Theme.of(context).textTheme.bodySmall),
          if (_maya.isNotEmpty)
            Text('Maya: $_maya', style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 10),
        AppInput(
          controller: widget.referenceController,
          label: 'Payment reference number *',
          hint: 'QR Ph / GCash / Maya transaction ID',
        ),
      ],
    );
  }
}
