import 'package:flutter/material.dart';

/// Hotel wallet rules shared across admin screens.
abstract final class HotelCreditsPolicy {
  static const double lowBalanceThreshold = 3000;

  static bool isDepleted(double balance) => balance <= 0;

  static bool isLowBalance(double balance) =>
      balance > 0 && balance < lowBalanceThreshold;

  static bool showLowBalanceReminder(double balance) =>
      isDepleted(balance) || isLowBalance(balance);

  static bool areActionsLocked(double balance) => isDepleted(balance);
}

/// Exposes live credit state to descendants (dashboard sections).
class AdminCreditsGate extends InheritedWidget {
  const AdminCreditsGate({
    super.key,
    required this.balance,
    required this.onTopUp,
    required super.child,
  });

  final double balance;
  final VoidCallback onTopUp;

  bool get isDepleted => HotelCreditsPolicy.isDepleted(balance);
  bool get isLowBalance => HotelCreditsPolicy.isLowBalance(balance);
  bool get showReminder => HotelCreditsPolicy.showLowBalanceReminder(balance);
  bool get actionsLocked => HotelCreditsPolicy.areActionsLocked(balance);

  static AdminCreditsGate? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AdminCreditsGate>();
  }

  static AdminCreditsGate of(BuildContext context) {
    final gate = maybeOf(context);
    assert(gate != null, 'AdminCreditsGate not found');
    return gate!;
  }

  static bool canPerformActions(BuildContext context) {
    return !(maybeOf(context)?.actionsLocked ?? false);
  }

  static void showActionsBlockedMessage(BuildContext context) {
    final gate = maybeOf(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          gate?.isDepleted == true
              ? 'Credits are depleted. Top up credits in Settings or sign out.'
              : 'This action is unavailable while credits are depleted.',
        ),
        action: gate != null
            ? SnackBarAction(
                label: 'Top up',
                onPressed: gate.onTopUp,
              )
            : null,
      ),
    );
  }

  @override
  bool updateShouldNotify(AdminCreditsGate oldWidget) =>
      oldWidget.balance != balance;
}

/// Always-visible strip when balance is below [HotelCreditsPolicy.lowBalanceThreshold].
class HotelCreditsReminderBanner extends StatelessWidget {
  const HotelCreditsReminderBanner({
    super.key,
    required this.balance,
    required this.onTopUp,
    this.frontDeskMode = false,
  });

  final double balance;
  final VoidCallback? onTopUp;
  final bool frontDeskMode;

  @override
  Widget build(BuildContext context) {
    if (!HotelCreditsPolicy.showLowBalanceReminder(balance)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final depleted = HotelCreditsPolicy.isDepleted(balance);
    final threshold = HotelCreditsPolicy.lowBalanceThreshold;

    final bg = depleted
        ? scheme.errorContainer
        : scheme.tertiaryContainer.withValues(alpha: 0.85);
    final fg = depleted ? scheme.onErrorContainer : scheme.onTertiaryContainer;
    final icon = depleted
        ? Icons.error_outline
        : Icons.warning_amber_rounded;

    final message = depleted
        ? frontDeskMode
            ? 'Credit balance is ₱0.00. Contact your hotel administrator to top up credits.'
            : 'Credit balance is ₱0.00. Top up credits to use the app — only recharge and sign out are available.'
        : 'Low credit balance: ₱${_format(balance)}. '
            '${frontDeskMode ? 'Ask your hotel administrator to top up.' : 'Top up to at least ₱${_format(threshold)} to avoid interrupted bookings and fees.'}';

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
              ),
            ),
            if (onTopUp != null) ...[
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onTopUp,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Top up'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}

/// Blocks interaction on locked tabs (credits depleted).
class CreditsLockedOverlay extends StatelessWidget {
  const CreditsLockedOverlay({
    super.key,
    required this.locked,
    required this.onTopUp,
    required this.child,
  });

  final bool locked;
  final VoidCallback onTopUp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;

    return Stack(
      children: [
        IgnorePointer(
          child: Opacity(opacity: 0.38, child: child),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.black.withValues(alpha: 0.08),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 40,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Credits depleted',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Open Settings → Credits to recharge, or sign out. '
                          'Other actions are disabled until your balance is above ₱0.',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: onTopUp,
                          icon: const Icon(Icons.add_card_outlined),
                          label: const Text('Top up credits'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
