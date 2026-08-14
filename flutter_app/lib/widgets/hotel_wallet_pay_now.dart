import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:url_launcher/url_launcher.dart';

enum HotelWalletApp { gcash, maya }

/// Opens GCash / Maya for a hotel Pay Now flow.
///
/// GCash/Maya do **not** allow third-party apps to auto-fill Send Money
/// (number + amount). We show those details on screen, copy the number for
/// pasting, and launch the **installed** wallet app by Android package name
/// (not Play Store).
class HotelWalletPayNow {
  HotelWalletPayNow._();

  static const _appsChannel = MethodChannel('gloretto/installed_apps');
  static const _gcashPackages = <String>['com.globe.gcash.android'];
  static const _mayaPackages = <String>[
    'com.paymaya',
    'com.maya.maya',
  ];

  static String formatAmount(double amount) {
    final rounded = (amount * 100).roundToDouble() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  static String walletLabel(HotelWalletApp wallet) =>
      wallet == HotelWalletApp.gcash ? 'GCash' : 'Maya';

  static List<String> _packagesFor(HotelWalletApp wallet) =>
      wallet == HotelWalletApp.gcash ? _gcashPackages : _mayaPackages;

  /// Native PackageManager only — never market:// / Play Store.
  static Future<bool> _launchViaNativeChannel(String packageName) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final opened = await _appsChannel.invokeMethod<bool>(
        'launchApp',
        {'package': packageName},
      );
      return opened == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the installed wallet app. Returns false if not installed.
  /// Never opens Play Store automatically.
  static Future<bool> openWalletApp(HotelWalletApp wallet) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Only native getLaunchIntentForPackage. Do not use url_launcher /
      // android_intent_plus here — those often fall through to Play Store
      // when resolve fails or when a scheme is unbound.
      for (final package in _packagesFor(wallet)) {
        if (await _launchViaNativeChannel(package)) {
          return true;
        }
      }
      return false;
    }

    // iOS / other platforms: scheme only (no Play Store URL).
    final schemes = wallet == HotelWalletApp.gcash
        ? <Uri>[Uri.parse('gcash://')]
        : <Uri>[Uri.parse('maya://'), Uri.parse('paymaya://')];
    for (final uri in schemes) {
      try {
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return true;
      } catch (_) {
        // try next
      }
    }
    return false;
  }

  static Future<void> _openPlayStore(HotelWalletApp wallet) async {
    final id = wallet == HotelWalletApp.gcash
        ? 'com.globe.gcash.android'
        : 'com.paymaya';
    final store = Uri.parse('market://details?id=$id');
    final https = Uri.parse(
      'https://play.google.com/store/apps/details?id=$id',
    );
    try {
      if (await canLaunchUrl(store)) {
        await launchUrl(store, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    await launchUrl(https, mode: LaunchMode.externalApplication);
  }

  /// Shows amount + number first, then opens the installed wallet.
  static Future<void> pay({
    required BuildContext context,
    required HotelWalletApp wallet,
    required String mobile,
    required double amountPesos,
  }) async {
    final number = mobile.trim();
    if (number.isEmpty || amountPesos <= 0) {
      showAppMessage(
        context,
        'Payment details are incomplete. Ask the hotel to set a wallet number.',
        isError: true,
      );
      return;
    }

    final walletName = walletLabel(wallet);
    final amountLabel = formatAmount(amountPesos);

    if (!context.mounted) return;
    final action = await showDialog<_PayNowAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Pay ₱$amountLabel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Send via $walletName',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                _DetailRow(label: 'Send to', value: number),
                const SizedBox(height: 8),
                _DetailRow(label: 'Amount', value: '₱$amountLabel'),
                const SizedBox(height: 12),
                Text(
                  '$walletName cannot auto-fill Send Money from other apps. '
                  'Copy the number, open $walletName, paste it in Send Money, '
                  'enter ₱$amountLabel, then return here with your reference.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: number));
                    if (ctx.mounted) {
                      showAppMessage(ctx, 'Number copied: $number');
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy number'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: amountLabel));
                    if (ctx.mounted) {
                      showAppMessage(ctx, 'Amount copied: ₱$amountLabel');
                    }
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy amount'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _PayNowAction.cancel),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _PayNowAction.openWallet),
              child: Text('Open $walletName'),
            ),
          ],
        );
      },
    );

    if (action != _PayNowAction.openWallet || !context.mounted) return;

    // Copy number last so paste in GCash targets the recipient field.
    await Clipboard.setData(ClipboardData(text: number));

    final opened = await openWalletApp(wallet);
    if (!context.mounted) return;

    if (!opened) {
      final install = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text('$walletName not found'),
            content: Text(
              '$walletName does not appear to be installed on this phone. '
              'Install it, then send ₱$amountLabel to $number and paste the reference here.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open Play Store'),
              ),
            ],
          );
        },
      );
      if (install == true) {
        await _openPlayStore(wallet);
      }
      return;
    }

    if (!context.mounted) return;
    showAppMessage(
      context,
      'Number copied. In $walletName → Send Money, paste $number and pay ₱$amountLabel. Then return and paste your reference.',
    );
  }

  /// Bottom sheet: choose GCash / Maya when both are configured.
  static Future<void> showChooser({
    required BuildContext context,
    required double amountPesos,
    String? gcashMobile,
    String? mayaMobile,
  }) async {
    final gcash = (gcashMobile ?? '').trim();
    final maya = (mayaMobile ?? '').trim();
    if (gcash.isEmpty && maya.isEmpty) {
      showAppMessage(
        context,
        'This hotel has not set a GCash or Maya number yet. Use the QR code, or ask the hotel to add a wallet number in Online payments.',
        isError: true,
      );
      return;
    }

    if (gcash.isNotEmpty && maya.isEmpty) {
      await pay(
        context: context,
        wallet: HotelWalletApp.gcash,
        mobile: gcash,
        amountPesos: amountPesos,
      );
      return;
    }
    if (maya.isNotEmpty && gcash.isEmpty) {
      await pay(
        context: context,
        wallet: HotelWalletApp.maya,
        mobile: maya,
        amountPesos: amountPesos,
      );
      return;
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pay ₱${formatAmount(amountPesos)} now',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose a wallet. We open the installed app and show the number to send to.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    pay(
                      context: context,
                      wallet: HotelWalletApp.gcash,
                      mobile: gcash,
                      amountPesos: amountPesos,
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: Text('GCash · $gcash'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    pay(
                      context: context,
                      wallet: HotelWalletApp.maya,
                      mobile: maya,
                      amountPesos: amountPesos,
                    );
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: Text('Maya · $maya'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _PayNowAction { cancel, openWallet }

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
