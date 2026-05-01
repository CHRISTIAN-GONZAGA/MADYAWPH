# FINAL RUN

End-to-end checklist for final deployment of the Gloretto multi-hotel app using MongoDB Atlas, plus Android build steps.

---

## 0) One-time prerequisites

- PHP 8.2+ with extensions:
  - `mongodb`
  - `openssl`
  - `mbstring`
  - `curl`
  - `fileinfo`
- Node.js LTS + npm
- Composer
- Android Studio (for APK/AAB)
- MongoDB Atlas project/cluster ready

---

## 1) Configure Atlas (required)

1. Create Atlas DB user (username/password).
2. Add Network Access for your deployment server IP (or temporary `0.0.0.0/0` for setup).
3. Copy the SRV URI from Atlas.

Example format:

```text
mongodb+srv://DB_USER:DB_PASSWORD@cluster0.xxxxx.mongodb.net/hotel_hms?retryWrites=true&w=majority&appName=HotelHMS
```

---

## 2) Finalize `.env`

Update `c:\GLORETTO_APP\.env` with real values:

- `APP_ENV=production`
- `APP_DEBUG=false`
- `APP_URL=https://your-domain.example`
- `FRONTEND_URL=https://your-domain.example`
- `DB_CONNECTION=mongodb`
- `MONGODB_URI=...` (real Atlas URI)
- `MONGODB_DATABASE=hotel_hms`
- `VITE_API_BASE_URL=https://your-domain.example`
- `SANCTUM_STATEFUL_DOMAINS=your-domain.example` (host only, no `https://`)
- `CORS_ALLOWED_ORIGINS=https://your-domain.example`
- `SESSION_SECURE_COOKIE=true` (HTTPS deployment)

Generate app key if empty:

```powershell
cd c:\GLORETTO_APP
php artisan key:generate --force
```

---

## 3) Install dependencies

```powershell
cd c:\GLORETTO_APP
composer install
npm install
```

---

## 4) Database migration + seed (MongoDB)

```powershell
cd c:\GLORETTO_APP
php artisan config:clear
php artisan migrate --force
php artisan db:seed --force
```

If migration fails, verify:
- Atlas URI is real (no placeholders like `CLUSTER_HOST`)
- `ext-mongodb` is enabled in PHP
- Atlas network access/user credentials are correct

---

## 5) Validate app integrity before deployment

```powershell
cd c:\GLORETTO_APP
php artisan test
npm run build
php artisan route:list
```

Expected:
- tests pass
- frontend builds successfully
- routes list loads without errors

---

## 6) Production optimization commands (server)

Run after successful migration/build:

```powershell
cd c:\GLORETTO_APP
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

Optional clear commands (if you change env/routes/views later):

```powershell
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan cache:clear
```

---

## 7) Android wrapper final steps (Capacitor)

`cap:*` scripts exist inside `mobile/`, not root.

1. Check `mobile/capacitor.config.ts`:
   - `server.url` must match your deployed HTTPS domain.
   - `cleartext: false` for HTTPS.

2. Sync and open Android project:

```powershell
cd c:\GLORETTO_APP\mobile
npm install
npm run cap:sync
npm run cap:open:android
```

3. In Android Studio:
   - Wait for Gradle sync
   - Run debug on emulator/device
   - Build signed release:
     - `Build > Generate Signed Bundle / APK`
     - Prefer **AAB** for Play Store

---

## 8) Quick command block (copy/paste sequence)

```powershell
cd c:\GLORETTO_APP
php artisan key:generate --force
composer install
npm install
php artisan config:clear
php artisan migrate --force
php artisan db:seed --force
php artisan test
npm run build
php artisan config:cache
php artisan route:cache
php artisan view:cache

cd c:\GLORETTO_APP\mobile
npm install
npm run cap:sync
npm run cap:open:android
```

---

## 9) Final go-live checklist

- [ ] Real Atlas URI in `.env`
- [ ] `APP_KEY` set
- [ ] HTTPS domain live
- [ ] Sanctum/CORS domain values correct
- [ ] `php artisan migrate --force` completed
- [ ] `php artisan test` passed
- [ ] `npm run build` passed
- [ ] Android app synced (`npm run cap:sync`)
- [ ] Android release artifact generated (AAB/APK)

---

## 10) Security reminders

- Never commit `.env`
- Rotate Atlas password if previously exposed
- Keep production `APP_DEBUG=false`
- Use HTTPS in production

