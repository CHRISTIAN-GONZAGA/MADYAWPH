/// Set at build time, e.g.:
/// flutter run --dart-define=API_BASE_URL=https://your-app.onrender.com/api/v1
///
/// Defensive normalization:
/// - If API_BASE_URL ends with `/api`, append `/v1`.
/// - If `/v1` is already present, keep it as-is.
final String kApiBaseUrl = _normalizeApiBaseUrl(
  const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  ),
);

String _normalizeApiBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.endsWith('/api/v1')) return trimmed;
  if (trimmed.endsWith('/api')) return '$trimmed/v1';
  return trimmed;
}
