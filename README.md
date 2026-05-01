# Gloretto Hotel HMS

Laravel + Inertia React hotel management system with a Capacitor Android wrapper.

This guide is the single source of truth for:
- local setup
- Railway deployment
- MongoDB Atlas setup
- Android Studio APK/AAB build and release

---

## 1) Stack

- Laravel 12
- PHP 8.2+
- Inertia.js + React + Vite + Tailwind
- MongoDB Atlas via `mongodb/laravel-mongodb`
- Capacitor Android wrapper in `mobile/`

---

## 2) Prerequisites

Install on your machine:

- PHP 8.2+ (`php -v`)
- Composer (`composer -V`)
- Node.js LTS + npm (`node -v`, `npm -v`)
- Git
- Android Studio
- Java/JDK 17 (`java -version`)

Optional but recommended:
- MongoDB Compass (for manual DB checks)

---

## 3) Local Project Setup

From project root:

```powershell
cd "c:\Users\Christian\Documents\GLORETTO_APP"
composer install
npm install
```

If `.env` does not exist:

```powershell
copy .env.example .env
```

Generate app key:

```powershell
php artisan key:generate
```

Run tests and web build:

```powershell
composer test
npm run build
```

Run development servers:

```powershell
php artisan serve
npm run dev
```

---

## 4) MongoDB Atlas Setup (Production)

1. Create Atlas project and cluster.
2. Create database user (username/password).
3. In Atlas **Network Access**, allow your app/server IP.
   - For initial testing only, temporary `0.0.0.0/0` is acceptable.
4. Copy SRV connection string.

Example:

```text
mongodb+srv://<USERNAME>:<PASSWORD>@<CLUSTER>/<DATABASE>?retryWrites=true&w=majority
```

Important:
- URL-encode special password characters (`@`, `#`, `%`, etc.).
- Keep credentials only in environment variables, never in committed files.

---

## 5) Railway Deployment (Laravel + Inertia)

## 5.1 Create and connect project

1. Push this repo to GitHub.
2. In Railway, create a new project from GitHub.
3. Select this repository and branch.

## 5.2 Railway environment variables

Set these in Railway Variables (adjust values for your app):

```env
APP_NAME="Gloretto Hotel HMS"
APP_ENV=production
APP_DEBUG=false
APP_KEY=base64:REPLACE_WITH_GENERATED_KEY
APP_URL=https://your-railway-domain.up.railway.app
FRONTEND_URL=https://your-railway-domain.up.railway.app

DB_CONNECTION=mongodb
MONGODB_URI=mongodb+srv://USER:PASSWORD@CLUSTER.mongodb.net/hotel_hms?retryWrites=true&w=majority
MONGODB_DATABASE=hotel_hms

SESSION_DRIVER=file
SESSION_SECURE_COOKIE=true
SESSION_SAME_SITE=lax
SANCTUM_STATEFUL_DOMAINS=your-railway-domain.up.railway.app
CORS_ALLOWED_ORIGINS=https://your-railway-domain.up.railway.app

CACHE_STORE=file
QUEUE_CONNECTION=sync
LOG_CHANNEL=stack
```

Generate key locally if needed:

```powershell
php artisan key:generate --show
```

## 5.3 Build/start behavior

Railway should run install/build steps equivalent to:

```bash
composer install --no-dev --optimize-autoloader
npm ci
npm run build
```

And then run the app. If using a custom start command, ensure it binds to `$PORT`.

## 5.4 Post-deploy hardening

Run these (or bake into deploy command):

```bash
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

Smoke test:
- app loads over HTTPS
- login works
- DB writes to Atlas work
- main API routes respond correctly

---

## 6) Android Studio + Capacitor (APK / AAB)

## 6.1 First-time Android Studio open

When Android Studio starts:
- choose **Open** (not **New Project**)
- open folder: `mobile/android`

If menu bar is hidden on Windows, press `Alt`.

Open settings:
- `File > Settings` (shortcut: `Ctrl + Alt + S`)

Check:
- `Build, Execution, Deployment > Build Tools > Gradle` (Gradle JDK)
- `Appearance & Behavior > System Settings > Android SDK` (SDK installed)

## 6.2 Ensure Java 17

This project is configured for Java 17 in Gradle.

If terminal cannot find Java, set env vars in PowerShell (Admin):

```powershell
[Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Program Files\Android\Android Studio\jbr", "Machine")
$oldPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($oldPath -notlike "*%JAVA_HOME%\bin*") {
  [Environment]::SetEnvironmentVariable("Path", "$oldPath;%JAVA_HOME%\bin", "Machine")
}
```

Open a new terminal and verify:

```powershell
java -version
echo $env:JAVA_HOME
```

## 6.3 Point mobile app to production URL

Edit:
- `mobile/capacitor.config.ts`

Set:

```ts
server: {
  url: 'https://your-railway-domain.up.railway.app',
  cleartext: false,
  androidScheme: 'https',
}
```

Sync Capacitor:

```powershell
cd "c:\Users\Christian\Documents\GLORETTO_APP\mobile"
npm install
npm run cap:sync
```

## 6.4 Build debug APK

```powershell
cd "c:\Users\Christian\Documents\GLORETTO_APP\mobile"
npm run android:assemble:debug
```

Expected output:
- `mobile/android/app/build/outputs/apk/debug/app-debug.apk`

## 6.5 Build release (Play Store)

CLI:

```powershell
cd "c:\Users\Christian\Documents\GLORETTO_APP\mobile"
npm run android:assemble:release
```

Android Studio recommended flow:
- `Build > Generate Signed Bundle / APK`
- choose **Android App Bundle (AAB)** for Play upload
- create/select keystore
- keep keystore and passwords backed up securely

---

## 7) Full Command Checklist (Copy/Paste)

```powershell
# 1) root checks
cd "c:\Users\Christian\Documents\GLORETTO_APP"
php -v
composer -V
node -v
npm -v
java -version

# 2) backend + frontend validation
composer test
npm run build

# 3) mobile sync + debug apk
cd "c:\Users\Christian\Documents\GLORETTO_APP\mobile"
npm install
npm run cap:sync
npm run android:assemble:debug
```

---

## 8) Troubleshooting

### `java` not found / `JAVA_HOME` not set
- set `JAVA_HOME`
- add `%JAVA_HOME%\bin` to system `Path`
- restart terminal

### `invalid source release: 21`
- project must target Java 17
- re-sync Gradle and rebuild after confirming JDK 17

### White screen on mobile app
- check `mobile/capacitor.config.ts` `server.url`
- verify Railway URL is reachable over HTTPS

### Login/session issues in app
- verify `SANCTUM_STATEFUL_DOMAINS` (host only, no `https://`)
- verify `SESSION_SECURE_COOKIE=true` in production HTTPS
- verify `CORS_ALLOWED_ORIGINS` includes exact app URL

---

## 9) Security Notes

- Never commit `.env` or secrets.
- Use `APP_DEBUG=false` in production.
- Use HTTPS everywhere.
- Restrict Atlas network access once deployment is stable.

---

## 10) Useful Paths

- App root: `c:\Users\Christian\Documents\GLORETTO_APP`
- Mobile wrapper: `c:\Users\Christian\Documents\GLORETTO_APP\mobile`
- Android project: `c:\Users\Christian\Documents\GLORETTO_APP\mobile\android`
- Capacitor config: `c:\Users\Christian\Documents\GLORETTO_APP\mobile\capacitor.config.ts`
