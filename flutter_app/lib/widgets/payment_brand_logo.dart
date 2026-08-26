import 'package:flutter/material.dart';

/// Distinctive brand marks for guest payment buttons.
/// These are original color chips, not official trademark artwork.
class PaymentBrandLogo extends StatelessWidget {
  const PaymentBrandLogo({
    super.key,
    required this.methodKey,
    this.size = 28,
  });

  final String methodKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(methodKey);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: spec.colors,
          ),
          boxShadow: [
            BoxShadow(
              color: spec.colors.first.withValues(alpha: 0.28),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: spec.useIcon
              ? Icon(spec.icon, size: size * 0.58, color: Colors.white)
              : Text(
                  spec.mark,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: size * spec.fontScale,
                    height: 1,
                    letterSpacing: spec.letterSpacing,
                  ),
                ),
        ),
      ),
    );
  }

  static _LogoSpec _specFor(String key) {
    switch (key) {
      case 'qrph':
        return const _LogoSpec(
          colors: [Color(0xFF0B5CAB), Color(0xFFC8102E)],
          mark: 'QR',
          fontScale: 0.34,
        );
      case 'gcash':
        return const _LogoSpec(
          colors: [Color(0xFF007CFF), Color(0xFF0057D9)],
          mark: 'G',
          fontScale: 0.52,
        );
      case 'paymaya':
        return const _LogoSpec(
          colors: [Color(0xFF00A86B), Color(0xFF007A4D)],
          mark: 'maya',
          fontScale: 0.26,
          letterSpacing: -0.3,
        );
      case 'maribank':
        return const _LogoSpec(
          colors: [Color(0xFFFF7A18), Color(0xFFE85D04)],
          mark: 'M',
          fontScale: 0.5,
        );
      case 'bank_transfer':
        return const _LogoSpec(
          colors: [Color(0xFF1B365D), Color(0xFF0F2744)],
          useIcon: true,
          icon: Icons.account_balance_rounded,
        );
      default:
        return const _LogoSpec(
          colors: [Color(0xFF475569), Color(0xFF334155)],
          useIcon: true,
          icon: Icons.qr_code_scanner_rounded,
        );
    }
  }
}

class _LogoSpec {
  const _LogoSpec({
    required this.colors,
    this.mark = '',
    this.fontScale = 0.4,
    this.letterSpacing = 0,
    this.useIcon = false,
    this.icon = Icons.payments_outlined,
  });

  final List<Color> colors;
  final String mark;
  final double fontScale;
  final double letterSpacing;
  final bool useIcon;
  final IconData icon;
}
