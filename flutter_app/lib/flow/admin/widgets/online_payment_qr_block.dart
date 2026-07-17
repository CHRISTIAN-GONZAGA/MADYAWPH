import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_input.dart';

bool isOnlinePaymentMethod(String method) {
  final m = method.trim().toLowerCase();
  return m == 'gcash' ||
      m == 'paymaya' ||
      m == 'maya' ||
      m == 'online' ||
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
      final url = (res.data?['payment_qr_url'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _qrUrl = url.isEmpty ? null : url;
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
          'Scan hotel QR Ph to pay',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
                _qrUrl!,
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
        const SizedBox(height: 10),
        AppInput(
          controller: widget.referenceController,
          label: 'Payment reference number *',
          hint: 'GCash / PayMaya / bank reference',
        ),
      ],
    );
  }
}
