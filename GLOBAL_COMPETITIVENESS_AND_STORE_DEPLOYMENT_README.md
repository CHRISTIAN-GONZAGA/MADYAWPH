# Global Competitiveness and Store Deployment Playbook

This document is the execution guide for taking `GLORETTO_APP` from "working project" to
"globally competitive product" and safely releasing on app stores.

Use this with:
- `README.md`
- `PLAYSTORE_DEPLOYMENT_README.md`
- `FINAL_RUN.md`

---

## 1) What "Globally Competitive" Means

For this app, global competitiveness means:
- fast and stable on low-end and high-end phones
- secure for multi-hotel production data
- resilient under traffic spikes
- clear UX in mobile/tablet views
- measurable operations (monitoring + alerts)
- release process that supports frequent safe updates

Success targets:
- p95 API latency under 500ms for core flows
- crash-free sessions above 99.5%
- auth/booking error rate below 1%
- all high/critical security issues resolved before release

---

## 2) Phase Plan (Recommended)

### Phase A: Security and Isolation
- enforce role and hotel-level authorization everywhere
- rate-limit login, guest room access, and booking endpoints
- validate all mutation inputs server-side
- log admin/staff critical actions with audit trail
- review CORS, Sanctum, and secure cookie settings

### Phase B: Performance and Scale
- split JS bundles by route/view to reduce startup payload
- add query indexes for frequent MongoDB filters (hotel_id, room_number, status)
- optimize heavy dashboard queries and pagination
- add caching for static/rarely changing reads

### Phase C: Product Quality
- full mobile and tablet responsive review
- accessibility pass (contrast, focus, labels, touch targets)
- remove dead-end UI states and empty placeholders
- standardize transitions for premium, consistent feel

### Phase D: Operations and Reliability
- centralized error monitoring (frontend + backend)
- uptime checks and alerting
- backup and restore runbook for MongoDB Atlas
- rollback plan for app and backend releases

---

## 3) Production Environment Baseline

Set these minimum production rules:
- `APP_ENV=production`
- `APP_DEBUG=false`
- HTTPS only
- `SESSION_SECURE_COOKIE=true`
- strict allowed origins/domains
- secrets in environment vars only

Never commit:
- `.env`
- keystore passwords
- API secrets

---

## 4) Pre-Release Technical Gate (Must Pass)

Run from project root:

```powershell
cd "c:\Users\Christian\Documents\GLORETTO_APP"
php artisan test
php artisan route:list
npm run build
```

Run mobile checks:

```powershell
cd "c:\Users\Christian\Documents\GLORETTO_APP\mobile"
npm run cap:sync
npm run android:assemble:release
```

Release only if all above pass.

---

## 5) Store Readiness Checklist (Google Play)

### Product Assets
- app icon (512x512)
- feature graphic
- screenshots (phone + tablet recommended)
- concise store description with clear value

### Policy and Compliance
- privacy policy URL published and accessible
- data safety form completed accurately
- content rating completed
- target audience completed
- app access/test credentials provided if login required

### Release Artifacts
- use signed `.aab` for Play
- increment `versionCode` each upload
- update `versionName` each release
- keep same keystore for updates

---

## 6) Google Play Deployment Steps

1. Deploy backend production (Railway + MongoDB Atlas).
2. Update mobile config to production URL in `mobile/capacitor.config.ts`:
   - use HTTPS production domain
   - `cleartext: false`
3. Sync native project:

```powershell
cd "c:\Users\Christian\Documents\GLORETTO_APP\mobile"
npm run cap:sync
```

4. Open Android Studio:

```powershell
npm run cap:open:android
```

5. Build signed AAB:
   - `Build > Generate Signed Bundle / APK`
   - choose `Android App Bundle`
6. Upload to Play Console (Internal testing first).
7. Validate with testers.
8. Promote to Production track.

---

## 7) Post-Release Global Operations

After launch:
- monitor crash rate, ANR, API error spikes daily
- track conversion funnel (hotel select -> booking -> confirmation)
- track auth failures by role/hotel
- investigate slow endpoints and add indexes/caching
- schedule weekly quality and security review

Suggested weekly SLO report:
- API p95 latency
- crash-free sessions
- booking success rate
- guest room login failure rate
- top 10 backend errors

---

## 8) Competitive Product Enhancements (Next 30-60 Days)

High-impact roadmap:
- multilingual UI (start with EN + one target region language)
- push notifications for booking and concierge updates
- offline-friendly UI states for unstable networks
- analytics dashboard for hotel admins (bookings, occupancy, revenue)
- stronger chat workflow (status, assignment, SLA timers)
- richer room media and amenity personalization

---

## 9) Risk Register (Common Launch Blockers)

- wrong production URL in mobile config
- missing `versionCode` bump
- incorrect Sanctum/CORS domain setup
- no tested rollback path
- no monitor/alert for backend failures
- MongoDB network allowlist misconfiguration

Mitigation: run the pre-release gate and internal testing track every release.

---

## 10) One-Command Verification Bundle

```powershell
cd "c:\Users\Christian\Documents\GLORETTO_APP"
php artisan test && php artisan route:list && npm run build

cd "c:\Users\Christian\Documents\GLORETTO_APP\mobile"
npm run cap:sync && npm run android:assemble:release
```

If all pass and Play policy requirements are complete, you are ready for store submission.
