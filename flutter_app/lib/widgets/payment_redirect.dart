import 'package:flutter/material.dart';
import 'package:gloretto_mobile/widgets/app_notice.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens Xendit / PayMongo checkout URLs in the device browser.
class PaymentRedirect {
  PaymentRedirect._();

  /// Reads [redirect_url], [checkout_url], or nested [payment] maps from API JSON.
  static String? extractUrl(Map<String, dynamic>? data) {
    if (data == null) return null;

    for (final key in ['redirect_url', 'checkout_url', 'payment_url']) {
      final raw = (data[key] ?? '').toString().trim();
      if (raw.isNotEmpty) return raw;
    }

    final payment = data['payment'];
    if (payment is Map) {
      return extractUrl(Map<String, dynamic>.from(payment));
    }

    return null;
  }

  static bool responseRequiresRedirect(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['requires_redirect'] == true) return true;
    return extractUrl(data) != null;
  }

  /// Launches the checkout page externally (GCash / PayMaya / card via Xendit).
  static Future<bool> openCheckout(BuildContext context, String url) async {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      if (context.mounted) {
        showAppMessage(context, 'Invalid payment link from server.');
      }
      return false;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      showAppMessage(context, 'Could not open the payment page. Install a browser or try again.',);
    }

    return launched;
  }

  /// If [data] contains a payment URL, opens it and returns true.
  static Future<bool> maybeOpenFromResponse(
    BuildContext context,
    Map<String, dynamic>? data,
  ) async {
    final url = extractUrl(data);
    if (url == null || url.isEmpty) return false;

    if (context.mounted) {
      showAppMessage(context, 'Redirecting to payment…');
    }

    return openCheckout(context, url);
  }
}
