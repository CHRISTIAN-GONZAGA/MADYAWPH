import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../dio_client.dart';
import '../../../widgets/app_input.dart';
import '../../../widgets/guest_payment_methods.dart';

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

/// Maps the booking form's payment method label onto a stored QR method key.
String? _methodKeyFor(String method) {
  final m = method.trim().toLowerCase();
  if (m.contains('gcash')) return 'gcash';
  if (m.contains('maya')) return 'paymaya';
  if (m.contains('mari')) return 'maribank';
  if (m.contains('bank')) return 'bank_transfer';
  if (m.contains('qr')) return 'qrph';
  return null;
}

/// Shows the hotel's payment QRs at the front desk and collects the reference.
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
  List<GuestPaymentMethod> _methods = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (isOnlinePaymentMethod(widget.paymentMethod)) {
      _loadMethods();
    }
  }

  @override
  void didUpdateWidget(covariant OnlinePaymentQrBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paymentMethod != widget.paymentMethod &&
        isOnlinePaymentMethod(widget.paymentMethod) &&
        _methods.isEmpty) {
      _loadMethods();
    }
  }

  Future<void> _loadMethods() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await portalDio().get<Map<String, dynamic>>(
        '/admin/hotel/payment-methods',
      );
      if (!mounted) return;
      final methods = GuestPaymentMethod.listFrom(res.data?['methods'])
          .where((m) => m.isConfigured)
          .toList();
      setState(() {
        _methods = methods;
        _loading = false;
        _error = methods.isEmpty
            ? 'No payment QR uploaded yet. Add one in Setup → Online payment QRs.'
            : null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = dioErrorMessage(e);
      });
    }
  }

  /// Puts the method matching the chosen payment type first.
  List<GuestPaymentMethod> get _ordered {
    final preferred = _methodKeyFor(widget.paymentMethod);
    if (preferred == null) return _methods;
    final match = _methods.where((m) => m.key == preferred).toList();
    if (match.isEmpty) return _methods;
    return [...match, ..._methods.where((m) => m.key != preferred)];
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
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_methods.isNotEmpty)
          GuestPaymentMethodPicker(methods: _ordered)
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
          hint: 'QR Ph / GCash / Maya transaction ID',
        ),
      ],
    );
  }
}
