/// Set at build time, e.g.:
/// flutter run --dart-define=API_BASE_URL=https://your-app.onrender.com/api/v1
///
/// Optional Google Maps / Geocoding (for “near me” on Select property):
/// flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=your_key_here
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

/// Empty by default — nearby hotels still work when the server geocodes hotels.
/// Set this to geocode missing hotels on the device via Google Geocoding API.
final String kGoogleMapsApiKey = const String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: '',
).trim();

bool get kGoogleMapsConfigured => kGoogleMapsApiKey.isNotEmpty;

String _normalizeApiBaseUrl(String raw) {
  var s = raw.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }

  // Already correct.
  if (s.endsWith('/api/v1')) return s;

  // If someone passed ".../api/v1/..." (rare), keep only up to /api/v1.
  final idx = s.indexOf('/api/v1');
  if (idx >= 0) return s.substring(0, idx + '/api/v1'.length);

  // If ends with /api, append /v1.
  if (s.endsWith('/api')) return '$s/v1';

  // If it contains /api somewhere, ensure /v1 after it (best-effort).
  final apiIdx = s.indexOf('/api');
  if (apiIdx >= 0) {
    final prefix = s.substring(0, apiIdx + '/api'.length);
    return '$prefix/v1';
  }

  // Otherwise assume it's host root.
  return '$s/api/v1';
}
