import 'package:shared_preferences/shared_preferences.dart';

/// Mocks [AuthStorage] prefs so async guest-contact reads finish in widget tests.
void initWidgetTestBindings() {
  SharedPreferences.setMockInitialValues({
    'auth_storage_migrated_v2': true,
  });
}
