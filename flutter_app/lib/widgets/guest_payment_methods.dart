import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_notice.dart';
import 'chat_attachment.dart';
import 'payment_brand_logo.dart';

/// One payment option a hotel has set up (QR Ph, GCash, PayMaya, Maribank,
/// bank transfer). Each carries its own QR image and account details.
@immutable
class GuestPaymentMethod {
  const GuestPaymentMethod({
    required this.key,
    required this.label,
    this.hint = '',
    this.qrUrl = '',
    this.accountName = '',
    this.accountNumber = '',
    this.instructions = '',
  });

  final String key;
  final String label;
  final String hint;
  final String qrUrl;
  final String accountName;
  final String accountNumber;
  final String instructions;

  bool get hasQr => qrUrl.isNotEmpty;

  bool get hasAccount => accountNumber.isNotEmpty || accountName.isNotEmpty;

  bool get isConfigured => hasQr || hasAccount;

  /// Always-visible guest buttons, in this order.
  static const catalog = <GuestPaymentMethod>[
    GuestPaymentMethod(
      key: 'qrph',
      label: 'QR Ph',
      hint: 'Scan with any bank or e-wallet app',
    ),
    GuestPaymentMethod(
      key: 'gcash',
      label: 'GCash',
      hint: 'Scan inside GCash → Pay QR',
    ),
    GuestPaymentMethod(
      key: 'paymaya',
      label: 'PayMaya',
      hint: 'Scan inside Maya → Scan to pay',
    ),
    GuestPaymentMethod(
      key: 'maribank',
      label: 'Maribank',
      hint: 'Scan inside MariBank → Scan & pay',
    ),
    GuestPaymentMethod(
      key: 'bank_transfer',
      label: 'Bank transfer',
      hint: 'InstaPay / PESONet to the account below',
    ),
  ];

  /// Hotel QRs overlaid on the predetermined method list.
  static List<GuestPaymentMethod> merged(List<GuestPaymentMethod> fromHotel) {
    final byKey = {for (final m in fromHotel) m.key: m};
    return [
      for (final base in catalog) byKey[base.key] ?? base,
    ];
  }

  static GuestPaymentMethod fromJson(Map<String, dynamic> json) {
    return GuestPaymentMethod(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      hint: (json['hint'] ?? '').toString(),
      qrUrl: (json['qr_url'] ?? '').toString(),
      accountName: (json['account_name'] ?? '').toString(),
      accountNumber: (json['account_number'] ?? '').toString(),
      instructions: (json['instructions'] ?? '').toString(),
    );
  }

  static List<GuestPaymentMethod> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => GuestPaymentMethod.fromJson(Map<String, dynamic>.from(e)))
        .where((m) => m.key.isNotEmpty)
        .toList();
  }
}

IconData guestPaymentMethodIcon(String key) {
  switch (key) {
    case 'qrph':
      return Icons.qr_code_2_rounded;
    case 'gcash':
      return Icons.account_balance_wallet_outlined;
    case 'paymaya':
      return Icons.payments_outlined;
    case 'maribank':
      return Icons.savings_outlined;
    case 'bank_transfer':
      return Icons.account_balance_outlined;
    default:
      return Icons.qr_code_scanner_rounded;
  }
}

/// Method buttons plus the QR / account details for whichever one is picked.
class GuestPaymentMethodPicker extends StatefulWidget {
  const GuestPaymentMethodPicker({
    super.key,
    required this.methods,
    this.amountLabel = '',
  });

  final List<GuestPaymentMethod> methods;
  final String amountLabel;

  @override
  State<GuestPaymentMethodPicker> createState() =>
      _GuestPaymentMethodPickerState();
}

class _GuestPaymentMethodPickerState extends State<GuestPaymentMethodPicker> {
  String? _selectedKey;

  List<GuestPaymentMethod> get _options =>
      GuestPaymentMethod.merged(widget.methods);

  GuestPaymentMethod get _selected {
    final options = _options;
    for (final m in options) {
      if (m.key == _selectedKey) return m;
    }
    for (final m in options) {
      if (m.isConfigured) return m;
    }
    return options.first;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a payment method',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final method in _options)
              _MethodButton(
                method: method,
                selected: method.key == selected.key,
                onTap: () => setState(() => _selectedKey = method.key),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _MethodDetails(method: selected, amountLabel: widget.amountLabel),
      ],
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final GuestPaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PaymentBrandLogo(methodKey: method.key, size: 22),
              const SizedBox(width: 8),
              Text(
                method.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodDetails extends StatelessWidget {
  const _MethodDetails({required this.method, required this.amountLabel});

  final GuestPaymentMethod method;
  final String amountLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            method.hasQr
                ? 'Scan this ${method.label} code'
                : 'Send to this ${method.label} account',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (method.hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              method.hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (!method.isConfigured) ...[
            const SizedBox(height: 12),
            Text(
              'This hotel has not uploaded a ${method.label} QR yet. '
              'Choose another method or ask the front desk.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                    height: 1.35,
                  ),
            ),
          ],
          if (method.hasQr) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: NetworkMediaImage(
                  url: method.qrUrl,
                  width: 210,
                  height: 210,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
          if (amountLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CopyRow(
              label: 'Amount to pay',
              value: amountLabel,
              copyValue: amountLabel.replaceAll(RegExp(r'[^0-9.]'), ''),
            ),
          ],
          if (method.accountName.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CopyRow(label: 'Account name', value: method.accountName),
          ],
          if (method.accountNumber.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CopyRow(
              label: method.key == 'bank_transfer'
                  ? 'Account number'
                  : 'Mobile number',
              value: method.accountNumber,
            ),
          ],
          if (method.instructions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              method.instructions,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.35,
                  ),
            ),
          ],
          if (method.isConfigured) ...[
            const SizedBox(height: 10),
            Text(
              'After paying, copy the transaction reference from your app and '
              'paste it below so the front desk can confirm.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value, this.copyValue});

  final String label;
  final String value;
  final String? copyValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              SelectableText(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () async {
            final text = (copyValue ?? value).trim();
            if (text.isEmpty) return;
            await Clipboard.setData(ClipboardData(text: text));
            if (!context.mounted) return;
            showAppMessage(context, '$label copied.');
          },
        ),
      ],
    );
  }
}
