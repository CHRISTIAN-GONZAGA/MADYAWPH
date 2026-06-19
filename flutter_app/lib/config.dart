/// Set at build time, e.g.:
/// flutter run --dart-define=API_BASE_URL=https://your-app.onrender.com/api/v1
///
/// Defensive normalization:
/// - Accepts base URLs like:
///   - https://host/api/v1
///   - https://host/api/v1/
///   - https://host/api
///   - https://host/api/
///   - https://host (we will append /api/v1)
/// - Normalizes to end with `/api/v1` (no trailing slash).
final String kApiBaseUrl = _normalizeApiBaseUrl(
  const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  ),
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

/// Direct HTTPS link to the Android APK for "Share app" install QR.
/// Override at build time, e.g.:
/// flutter build apk --dart-define=APP_INSTALL_URL=https://your-host/downloads/madyaw.apk
final String kAppInstallUrl = const String.fromEnvironment(
  'APP_INSTALL_URL',
  defaultValue: '',
).trim();
