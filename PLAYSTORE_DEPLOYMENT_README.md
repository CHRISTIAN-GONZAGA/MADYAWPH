# Play Store Deployment README

This guide takes your project from local testing mode to a production Play Store release.

It is written for your current stack:
- Laravel + Inertia React backend/frontend
- MongoDB Atlas
- Railway hosting
- Capacitor Android wrapper in `mobile/`

---

## 0) Current State Check (Important)

Your current mobile config is local testing mode:
- `mobile/capacitor.config.ts` points to `http://192.168.1.224:8000`
- `cleartext: true`

That is only for local Wi-Fi testing.  
For Play Store, you must switch to your real HTTPS domain.

---

## 1) Production Prerequisites

Before building release binaries, make sure you have:

- Railway app deployed and reachable over HTTPS
- MongoDB Atlas connected and working in production
- Android Studio installed
- JDK 17 installed
- Google Play Console account

Quick local checks:

```powershell
php -v
composer -V
node -v
npm -v
java -version
```

---

## 2) Deploy Backend to Railway (Production)

1. Push latest code to GitHub.
2. Connect repo to Railway project.
3. Set production env vars in Railway.

Minimum recommended Railway variables:

```env
APP_ENV=production
APP_DEBUG=false
APP_URL=https://your-app.up.railway.app
FRONTEND_URL=https://your-app.up.railway.app
APP_KEY=base64:YOUR_REAL_KEY

DB_CONNECTION=mongodb
MONGODB_URI=mongodb+srv://USER:PASSWORD@CLUSTER.mongodb.net/hotel_hms?retryWrites=true&w=majority
MONGODB_DATABASE=hotel_hms

SESSION_DRIVER=file
SESSION_SECURE_COOKIE=true
SESSION_SAME_SITE=lax
SANCTUM_STATEFUL_DOMAINS=your-app.up.railway.app
CORS_ALLOWED_ORIGINS=https://your-app.up.railway.app
```

4. Confirm Railway deploy succeeds.
5. Confirm browser access to:
- `https://your-app.up.railway.app`
- login works
- key API calls return valid responses

---

## 3) Switch Mobile From Local Mode to Production Mode

Edit `mobile/capacitor.config.ts` to use HTTPS production URL:

```ts
import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.gloretto.hotelhms',
  appName: 'Gloretto Hotel HMS',
  webDir: 'www',
  server: {
    url: 'https://your-app.up.railway.app',
    cleartext: false,
    androidScheme: 'https',
  },
};

export default config;
```

Notes:
- Do not use `http://192.168.x.x` for production APK/AAB.
- Do not use `10.0.2.2` for production.

---

## 4) Android Manifest Production Check

Open:
- `mobile/android/app/src/main/AndroidManifest.xml`

If present from local testing, remove or disable:
- `android:usesCleartextTraffic="true"`

Production should use HTTPS only.

---

## 5) Sync Capacitor Native Project

From `mobile/`:

```powershell
cd "c:\Users\Christian\Documents\GLORETTO_APP\mobile"
npm install
npx cap sync android
```

Then open Android Studio:

```powershell
npx cap open android
```

---

## 6) Versioning Before Release

Open:
- `mobile/android/app/build.gradle`

Increase for every store upload:
- `versionCode` (must be higher than previous upload)
- `versionName` (human-readable version)

Example:
- `versionCode 2`
- `versionName "1.0.1"`

---

## 7) Build Signed Release AAB (Recommended)

In Android Studio:

1. `Build` -> `Generate Signed Bundle / APK`
2. Choose: `Android App Bundle`
3. Create/select keystore
4. Choose `release`
5. Build

Keep safe backups of:
- keystore file
- key alias
- keystore password
- key password

Without these, future updates become difficult/impossible.

---

## 8) Upload to Google Play Console

1. Open Play Console.
2. Create app (if first time).
3. Complete required store listing:
- app name
- short/long description
- screenshots
- app icon
- feature graphic
- privacy policy URL
4. Complete policy forms:
- Data safety
- App access (if login required)
- Content rating
- Target audience
5. Create release in testing track first (Internal or Closed testing).
6. Upload generated `.aab`.
7. Add release notes.
8. Roll out to testers.

After tester validation, promote to production track.

---

## 9) Recommended Release Flow (Every Update)

1. Update app code.
2. Deploy backend to Railway.
3. Verify production web app works.
4. Update Android `versionCode` and `versionName`.
5. `npx cap sync android`.
6. Build signed AAB.
7. Upload to Play Console.
8. Roll out update.

---

## 10) Troubleshooting

### App loads blank page on production APK
- Check `server.url` is HTTPS production URL.
- Confirm domain is reachable from phone browser.
- Confirm SSL certificate valid.

### Login fails in app only
- Check `SANCTUM_STATEFUL_DOMAINS` uses hostname only (no `https://`).
- Check `SESSION_SECURE_COOKIE=true`.
- Check CORS origin exactly matches app domain.

### Play Console rejects upload
- Ensure `versionCode` increased.
- Ensure release is signed with same keystore/key as previous release.

### New build seems unchanged
- Run `npx cap sync android` before building.
- Clean/rebuild in Android Studio.

---

## 11) Officially Out of Local Setup Checklist

You are officially out of local mode when ALL are true:

- `mobile/capacitor.config.ts` points to `https://...` production URL
- `cleartext: false`
- no local IP (`192.168.x.x`) in production app config
- Railway app is live and healthy
- signed AAB uploaded to Play Console
- release deployed to testing/production track

