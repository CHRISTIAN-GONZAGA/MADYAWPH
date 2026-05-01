# Mobile apps (Capacitor — Android & iOS)

This folder wraps your **deployed** Laravel + Inertia app in native shells. Both platforms load the same **`server.url`** from `capacitor.config.ts` in a WebView; your Laravel backend and `.env` stay on the server.

| Platform | Build on | Output |
|----------|----------|--------|
| **Android** | Windows, macOS, or Linux (Android Studio) | APK / AAB |
| **iOS** | **macOS only** (Xcode) | IPA for TestFlight / App Store |

One config (`server.url`) drives both apps, so users on iPhone and Android see the same hosted site.

## Prerequisites

### Shared

- **Node.js** (LTS)
- Deploy the Laravel app to a stable **HTTPS** URL, then set `server.url` in `capacitor.config.ts`.

### Android

- **Android Studio** (Android SDK + platform tools)
- **JDK 17**

Set the SDK:

- **Option A:** `ANDROID_HOME` → e.g. `%LOCALAPPDATA%\Android\Sdk` (Windows)
- **Option B:** `android/local.properties` from `android/local.properties.example`

### iOS (Mac only)

- **Xcode** (from App Store)
- **CocoaPods** (`sudo gem install cocoapods` or Homebrew)
- Apple Developer account for device testing / App Store

After cloning on a Mac, run once in `mobile/ios/App`:

```bash
pod install
```

Then open **`App.xcworkspace`** (not the `.xcodeproj` alone).

## One-time setup

1. Set `server.url` in `capacitor.config.ts` to your HTTPS origin.
2. In this directory:

```bash
npm install
npm run cap:sync
```

3. Open the native IDE:

```bash
npm run cap:open:android   # Android Studio
npm run cap:open:ios       # Xcode (macOS)
```

(`npm run cap:open` is the same as `cap:open:android`.)

## Build — Android

### Debug APK

```bash
npm run android:assemble:debug
```

Typical output: `android/app/build/outputs/apk/debug/app-debug.apk`.

### Release (Play Store)

Android Studio: **Build → Generate Signed App Bundle or APK** (prefer **AAB** for Play Console).

Or: `npm run android:assemble:release` after configuring signing in Gradle.

## Build — iOS (macOS)

1. `cd ios/App && pod install`
2. `npm run cap:open:ios` or open `ios/App/App.xcworkspace`
3. Select a development team in **Signing & Capabilities**
4. **Product → Archive** for distribution (TestFlight / App Store)

Simulator: choose a simulator and press Run.

## When to rebuild store binaries

You usually **do not** need a new store release for normal UI/API changes on the same URL—the WebView loads the live site.

Ship a new Android/iOS build when you change:

- `appId`, display name, icons, splash, or Capacitor plugins
- `server.url` or native permissions

After any change to `capacitor.config.ts` or `www/`:

```bash
npm run cap:sync
```

## Local HTTP / LAN (development only)

- **Android:** `server.cleartext: true` and `android:usesCleartextTraffic="true"` in `AndroidManifest.xml`.
- **iOS:** Add ATS exceptions in `Info.plist` only if you must use plain HTTP (not recommended for production).

Use HTTPS in production.

## Troubleshooting

| Issue | What to do |
|--------|------------|
| Android: `SDK location not found` | `ANDROID_HOME` or `android/local.properties` |
| iOS: Pods errors | Run `pod install` in `ios/App` on a Mac |
| White screen | Check `server.url`, TLS, and network from device |
| Login / session | Align Sanctum, `SESSION_DOMAIN`, cookies with your deployed domain |
