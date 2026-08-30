import 'package:flutter/foundation.dart';

/// Set at build time, e.g.:
/// flutter run --dart-define=API_BASE_URL=https://your-app.onrender.com/api/v1
///
/// If unset: debug/profile use the Android emulator host; release uses production.
///
/// Defensive normalization:
/// - Accepts base URLs like:
///   - https://host/api/v1
///   - https://host/api/v1/
///   - https://host/api
///   - https://host/api/
///   - https://host (we will append /api/v1)
/// - Normalizes to end with `/api/v1` (no trailing slash).
const _apiBaseUrlFromEnv = String.fromEnvironment('API_BASE_URL');

final String kApiBaseUrl = _normalizeApiBaseUrl(
  _apiBaseUrlFromEnv.isNotEmpty
      ? _apiBaseUrlFromEnv
      : (kReleaseMode
          ? 'https://madyawph.onrender.com/api/v1'
          : 'http://10.0.2.2:8000/api/v1'),
);

String _normalizeApiBaseUrl(String raw) {
  var s = raw.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }

  // Already correct.
  if (s.endsWith('/api/v1')) return s;

  // If someone passed ".../api/v1/..." (rare), keep only up to /api/v1.
  final v1Index = s.indexOf('/api/v1/');
  if (v1Index != -1) {
    return s.substring(0, v1Index + '/api/v1'.length);
  }

  if (s.endsWith('/api')) return '$s/v1';

  return '$s/api/v1';
}

/// Origin of the API host (scheme + host, no `/api/v1`), used for public QR landings.
String get kApiOrigin {
  final base = kApiBaseUrl;
  final idx = base.indexOf('/api/v1');
  if (idx != -1) return base.substring(0, idx);
  return base;
}

/// Default Google Drive folder with the MADYAW Android APK (copy / open link).
/// Override at build time with `--dart-define=APP_INSTALL_URL=...`
const String kDefaultAppInstallUrl =
    'https://drive.google.com/drive/folders/1MExvBsaikbFZir3r_dNqsyTIomEiT28A?usp=drive_link';

final String kAppInstallUrl = const String.fromEnvironment(
  'APP_INSTALL_URL',
  defaultValue: kDefaultAppInstallUrl,
).trim();

/// Tracking URL for the share-app QR (emails on scan, then redirects to Drive).
String get kAppInstallQrUrl => '$kApiOrigin/qr/app';

/// Public legal pages (Play Console privacy URL).
String get kPrivacyPolicyUrl => '$kApiOrigin/privacy';

String get kTermsOfServiceUrl => '$kApiOrigin/terms';
