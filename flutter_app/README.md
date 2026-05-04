# Gloretto — Flutter client (APK / Play Store)

This directory contains the **Flutter frontend** (`pubspec.yaml`, `lib/`, `test/`). Laravel on Render is the **only backend**: use `/api/v1/...` with **Sanctum** (`Authorization: Bearer …`) and **guest tokens** for the in-house portal.

The **Capacitor** wrapper under `mobile/` is optional/legacy.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (stable) on your `PATH`
- Android Studio + Android SDK + JDK 17 for APK/AAB

## One-time: add Android/iOS project files

This repo ships **Dart sources** only. Generate platform folders once:

```powershell
cd flutter_app
powershell -ExecutionPolicy Bypass -File .\setup_platforms.ps1
```

Or manually:

```powershell
cd flutter_app
flutter create . --project-name gloretto_mobile --org com.gloretto
```

`flutter create .` **adds** missing `android/`, `ios/`, etc., without removing your `lib/main.dart`.

After `flutter create`, add dependencies (example):

```yaml
# pubspec.yaml
dependencies:
  dio: ^5.7.0
  flutter_secure_storage: ^9.2.2
```

Point Dio at your Render URL (same host as `APP_URL` in Laravel `.env`).

## Configure API base URL

Use `--dart-define` for the **v1** prefix (recommended):

```bash
flutter run --dart-define=API_BASE_URL=https://your-service.onrender.com/api/v1
flutter build appbundle --dart-define=API_BASE_URL=https://your-service.onrender.com/api/v1
```

### Primary v1 endpoints (Sanctum unless noted)

| Flow | Method | Path |
|------|--------|------|
| List hotels | GET | `/hotels` |
| Hotel gate (username/password) | POST | `/hotel/access` |
| New hotel + admin | POST | `/hotel/register` |
| Admin/staff login → Bearer token | POST | `/auth/portal-login` |
| Forgot password SMS | POST | `/auth/forgot/send` |
| Reset password | POST | `/auth/forgot/reset` |
| Guest room login → `guest_token` | POST | `/guest/login` |
| Guest dashboard | GET | `/guest/dashboard` (Bearer `guest_token`) |
| Customer categories | GET | `/customer/categories?hotel_id=…` |
| Admin dashboard JSON | GET | `/admin/dashboard` (Bearer staff/admin Sanctum token) |
| Staff dashboard JSON | GET | `/staff/dashboard` |

Legacy `/api/login` (email + `hotel_id`) still exists for older clients.

Implement:

1. After portal or legacy login, store `token` in secure storage; send `Authorization: Bearer <token>`.
2. Guest: store `guest_token`; send as Bearer on `/guest/*` routes.
3. `POST /api/logout` revokes the current Sanctum token (same as before).

## Play Store

1. `flutter build appbundle`
2. Upload `.aab` to Google Play Console (internal testing first).
3. Complete **Data safety** and privacy policy (describe Laravel/Mongo data use).

## Laravel side

- Default browser home `/` is an **API landing** page (no Vite) unless `INERTIA_WEB_HOME=true`.
- Legacy Inertia welcome: `/web/welcome`.
