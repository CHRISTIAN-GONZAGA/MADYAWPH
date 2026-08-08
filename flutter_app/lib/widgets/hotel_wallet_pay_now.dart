import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:url_launcher/url_launcher.dart';

enum HotelWalletApp { gcash, maya }

/// Opens GCash / Maya for a hotel Pay Now flow.
///
/// Important accuracy note: GCash and Maya do **not** publish a public deep link
/// that auto-fills Send Money with number + amount. This helper:
/// 1) copies amount + recipient number to the clipboard,
/// 2) opens the wallet app (or Play Store if missing),
/// 3) guest completes Send Money, returns, and pastes the reference.
class HotelWalletPayNow {
  HotelWalletPayNow._();

  static String formatAmount(double amount) {
    final rounded = (amount * 100).roundToDouble() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
  }

  static String clipboardPayload({
    required HotelWalletApp wallet,
    required String mobile,
    required double amountPesos,
  }) {
    final label = wallet == HotelWalletApp.gcash ? 'GCash' : 'Maya';
    return 'Send ₱${formatAmount(amountPesos)} via $label to $mobile';
  }

  static Future<bool> openWalletApp(HotelWalletApp wallet) async {
    final schemes = wallet == HotelWalletApp.gcash
        ? <Uri>[
            Uri.parse('gcash://'),
            Uri.parse(
              'intent://#Intent;scheme=gcash;package=com.globe.gcash.android;end',
            ),
          ]
        : <Uri>[
            Uri.parse('maya://'),
            Uri.parse('paymaya://'),
            Uri.parse(
              'intent://#Intent;scheme=maya;package=com.paymaya;end',
            ),
          ];

    for (final uri in schemes) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {
        // try next candidate
      }
    }

    final store = wallet == HotelWalletApp.gcash
        ? Uri.parse(
            'https://play.google.com/store/apps/details?id=com.globe.gcash.android',
          )
        : Uri.parse(
            'https://play.google.com/store/apps/details?id=com.paymaya',
          );
    try {
      return await launchUrl(store, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Copies payment details, opens the wallet, and shows return-to-app guidance.
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

    final payload = clipboardPayload(
      wallet: wallet,
      mobile: number,
      amountPesos: amountPesos,
    );
    await Clipboard.setData(ClipboardData(text: payload));

    if (!context.mounted) return;
    final walletName = wallet == HotelWalletApp.gcash ? 'GCash' : 'Maya';
    showAppMessage(
      context,
      'Payment details copied. Opening $walletName…',
    );

    final opened = await openWalletApp(wallet);
    if (!context.mounted) return;
    if (!opened) {
      showAppMessage(
        context,
        'Could not open $walletName. Install the app, then send ₱${formatAmount(amountPesos)} to $number.',
        isError: true,
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Pay ₱${formatAmount(amountPesos)} in $walletName'),
          content: Text(
            '1. In $walletName, open Send Money.\n'
            '2. Send to $number.\n'
            '3. Amount: ₱${formatAmount(amountPesos)} '
            '(number and amount were copied for you).\n'
            '4. After payment succeeds, return here and paste your reference number.\n\n'
            'Note: GCash/Maya do not allow apps to auto-fill Send Money. '
            'You must confirm the number and amount in the wallet app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('I paid — enter reference'),
            ),
          ],
        );
      },
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
                  'Choose a wallet. We copy the amount and number, then open the app.',
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
