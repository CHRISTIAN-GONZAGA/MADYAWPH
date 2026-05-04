/// Set at build time, e.g.:
/// flutter run --dart-define=API_BASE_URL=https://your-app.onrender.com/api/v1
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api/v1',
);
