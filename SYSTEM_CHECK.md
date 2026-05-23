# System functionality checklist

Last verified: automated suite + Flutter analyze.

## Automated tests (run from repo root)

```powershell
composer test
```

**Expected:** 22 tests passing (booking, checkout, reports, admin dashboard, chat inbox, payments, SMS, staff, customer portal).

## Flutter (run from `flutter_app/`)

```powershell
flutter analyze
flutter run --dart-define=API_BASE_URL=https://YOUR-HOST/api/v1
```

## Production environment (Render / host)

Set in `.env` (see `.env.example`):

| Variable | Purpose |
|----------|---------|
| `MONGODB_URI` | Primary database |
| `SEMAPHORE_API_KEY` | SMS OTP / reminders |
| `XENDIT_SECRET_KEY` | GCash / PayMaya recharge |
| `XENDIT_WEBHOOK_TOKEN` | Credit webhook verification |
| `APP_URL` | Must match public HTTPS URL for webhooks |

Verify integrations:

```powershell
php artisan integrations:test YOUR_PHONE
```

## Manual UAT (recommended after deploy)

1. Hotel gate → Admin login → all 6 dashboard tabs load.
2. Room checkout: detail → receipt → confirm → room maintenance, guest cleared.
3. Chat: badge updates → open chatroom → reply.
4. Customer: category → book with PWD ID → admin approves reservation.
5. Amenities: add product → guest request → admin fulfill.
6. Reports: daily/weekly/monthly views load without 500.

## Architecture

- API: `/api/v1/*` (Sanctum + hotel tenant)
- DB: MongoDB (`hotel_hms` / `hotel_hms_test`)
- Client: `flutter_app/` (primary), `mobile/` deprecated Capacitor wrapper
