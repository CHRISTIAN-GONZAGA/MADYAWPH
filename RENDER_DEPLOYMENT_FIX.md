# Render Deployment Checklist - Fix Navigation Loop

## Step 1: Verify .env Configuration in Render Dashboard

Go to your Render service → Environment → ensure these variables are set:

```
# SESSION CONFIGURATION (Critical for fixing the loop)
SESSION_DRIVER=database          ← MUST be 'database', NOT 'file'
SESSION_LIFETIME=120
SESSION_EXPIRE_ON_CLOSE=false
SESSION_SECURE_COOKIE=true

# APP CONFIGURATION  
APP_ENV=production
APP_DEBUG=false
APP_URL=https://your-render-domain.onrender.com
FRONTEND_URL=https://your-render-domain.onrender.com

# DATABASE (MongoDB)
DB_CONNECTION=mongodb
MONGODB_URI=mongodb+srv://USER:PASSWORD@cluster.mongodb.net/hotel_hms?retryWrites=true&w=majority
MONGODB_DATABASE=hotel_hms

# SANCTUM & CORS
SANCTUM_STATEFUL_DOMAINS=your-render-domain.onrender.com
CORS_ALLOWED_ORIGINS=https://your-render-domain.onrender.com
VITE_API_BASE_URL=https://your-render-domain.onrender.com
```

⚠️ **CRITICAL**: If SESSION_DRIVER is set to 'file', the loop WILL continue!

---

## Step 2: Verify Build & Start Commands in Render

In Render Dashboard → Build Command, ensure you have:

```bash
composer install && npm install && npm run build && php artisan migrate --force && php artisan config:clear
```

In Render Dashboard → Start Command, ensure you have:

```bash
php artisan serve --host=0.0.0.0 --port=10000
```

OR if using Laravel Octane:

```bash
php artisan octane:start --host=0.0.0.0 --port=10000
```

---

## Step 3: Clear Cache After Deployment

After deploying these changes, restart your service:

1. Go to Render Dashboard
2. Click your service
3. Click "Manual Deploy" or push code to trigger auto-deploy
4. Once deployed, SSH into the instance (if available) or use Build Logs to verify
5. If deployment fails, check logs for errors

---

## Step 4: Test the Complete Flow

Once deployed to Render:

### Test 1: Hotel Access Flow
```
1. Go to: https://your-render-domain.onrender.com/auth/hotel
2. Login with hotel credentials
3. Should redirect to: /auth/category
4. ✅ Verify URL shows category selection menu
```

### Test 2: Admin Login Flow
```
1. Click "Admin" button
2. Should go to: /auth/admin?hotel=<id>
3. Enter admin credentials
4. Should redirect to: /admin/dashboard
5. ✅ Verify dashboard loads without refresh
```

### Test 3: Staff Login Flow
```
1. From category, click "Staff"
2. Should go to: /auth/staff?hotel=<id>
3. Enter staff credentials
4. Should redirect to: /staff/dashboard
5. ✅ Verify dashboard loads
```

### Test 4: Navigation Doesn't Loop
```
1. On admin dashboard, click back button
2. Should go to: /auth/category (menu)
3. NOT refresh the dashboard
4. ✅ Select Admin again - should work
```

### Test 5: Session Persistence
```
1. Login as admin
2. Hard refresh page (Ctrl+Shift+R)
3. Dashboard should still load (session restored from cookies)
4. ✅ No redirect to login
```

---

## Step 5: Verify Database Migrations

The sessions table must exist. In your Render build logs or SSH, run:

```bash
php artisan migrate --force
```

This should show:
```
Migrating: 2024_XX_XX_XXXXXX_create_sessions_table.php
Migrated: 2024_XX_XX_XXXXXX_create_sessions_table.php
```

If migrations fail, check your MongoDB connection settings.

---

## Common Issues & Fixes

### Issue: "Loop continues on Render but works locally"
**Cause**: SESSION_DRIVER is 'file' (ephemeral on Render)
**Fix**: Change SESSION_DRIVER=database in Render env vars

### Issue: "404 errors after login"
**Cause**: Routes not properly reloaded
**Fix**: Run `php artisan route:clear` in Render build command

### Issue: "Session not persisting"
**Cause**: Database connection is broken
**Fix**: Verify MONGODB_URI is correct and database exists

### Issue: "403 Unauthorized on admin dashboard"
**Cause**: Role middleware can't find user
**Fix**: Verify auth_uid and auth_role cookies are set (check browser DevTools)

---

## Render Service Configuration (Best Practices)

```yaml
# render.yaml (if using YAML deployment)
services:
  - type: web
    name: gloretto-app
    env: php
    buildCommand: composer install && npm install && npm run build && php artisan migrate --force && php artisan config:clear
    startCommand: php artisan serve --host=0.0.0.0 --port=10000
    envVars:
      - key: SESSION_DRIVER
        value: database        # ← CRITICAL
      - key: APP_ENV
        value: production
      - key: APP_DEBUG
        value: false
      # ... other vars
```

---

## Key Changes Made to Code

1. ✅ **SessionDriver Changed**: `config/session.php` → `database` (not `cookie`)
2. ✅ **Cookie Persistence**: Routes now set `active_hotel_id` cookie on every auth page
3. ✅ **Middleware Enhancement**: `RestoreAuthFromCookie` now also restores hotel ID
4. ✅ **BackButton Fixed**: Dashboard back buttons go to `/auth/category`

All these changes work together to prevent the loop on stateless Render infrastructure.

---

## After Deployment Verification

After redeploying with these changes:

✅ Clear browser cookies for the domain
✅ Try fresh login flow
✅ Verify no redirect loops
✅ Check DevTools → Application → Cookies to verify all auth cookies are set
✅ Verify sessions table has entries in MongoDB

If you still experience issues:
1. Check Render logs for errors
2. Verify all env vars are set correctly
3. Ensure migrations ran successfully  
4. Clear application cache (`php artisan cache:clear`)
