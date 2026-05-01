# DEPLOYMENT INSTRUCTIONS - RENDER NAVIGATION LOOP FIX

## ⚠️ CRITICAL: Do This BEFORE Deploying Code

### Step 1: Update Render Environment Variables

Go to **Render Dashboard** → Your Service Name → **Environment**

Make these changes:

| Variable | Value | Priority |
|----------|-------|----------|
| SESSION_DRIVER | **database** | 🔴 CRITICAL |
| SESSION_LIFETIME | 120 | Optional |
| SESSION_SECURE_COOKIE | true | Required |
| APP_ENV | production | Required |
| APP_DEBUG | false | Required |

**⚠️ If SESSION_DRIVER is currently 'file', change it to 'database' immediately**

---

## Step 2: Deploy Code Changes

All code changes are ready:
- ✅ config/session.php
- ✅ app/Http/Middleware/RestoreAuthFromCookie.php
- ✅ routes/web.php (multiple locations)
- ✅ JS components fixed

**Option A: Auto-deploy (if connected to GitHub)**
```
1. Commit all changes to main branch
2. Push to GitHub
3. Render will auto-deploy
4. Wait for "Deploy successful" message
```

**Option B: Manual Deploy**
```
1. Commit and push changes
2. Go to Render Dashboard
3. Click "Manual Deploy"
4. Wait for build to complete
```

---

## Step 3: Verify Deployment

Check the build logs for:
- ✅ "Composer install completed"
- ✅ "npm build successful"  
- ✅ "Migrating: create_sessions_table"
- ✅ "Migration successful"
- ✅ "App deployed"

If migrations fail:
- Check MongoDB connection in logs
- Verify MONGODB_URI is correct in env vars

---

## Step 4: Test the Fix

### Clear Browser Cache First
1. Open DevTools (F12)
2. Settings → Clear site data
3. Close and reopen browser

### Test Login Flow
1. Go to: `https://your-render-domain.onrender.com/auth/hotel`
2. Enter hotel credentials → Should go to `/auth/category` ✅
3. Click "Admin" → Should go to `/auth/admin` ✅
4. Enter admin credentials → Should go to `/admin/dashboard` ✅
5. **NO REFRESH LOOPS SHOULD OCCUR** ✅
6. Click back → Should go to `/auth/category` ✅

### Verify Cookies in DevTools
1. Open DevTools → Application → Cookies
2. Look for:
   - `active_hotel_id` ✅
   - `auth_uid` ✅
   - `auth_role` ✅
   - `XSRF-TOKEN` ✅
   - `laravel_session` ✅

All cookies should be HttpOnly=Yes and Secure=Yes

---

## Step 5: If Loop Still Occurs

### Debug Checklist
- [ ] Verify `SESSION_DRIVER=database` in Render (not 'file')
- [ ] Check build logs for errors
- [ ] Ensure MongoDB URI is correct
- [ ] Verify sessions table exists in database
- [ ] Clear application cache: `php artisan cache:clear`
- [ ] Check browser cookies are persisting
- [ ] Review `storage/logs/laravel.log` for errors

### Common Issues

**Issue**: Loop still happens
**Solution**: 
1. Go to Render Dashboard → Environment
2. Scroll down to SESSION_DRIVER
3. Change from 'file' to 'database'
4. Manual Deploy again

**Issue**: 404 on dashboards after login
**Solution**:
1. Routes might be cached
2. Run: `php artisan route:clear`
3. Redeploy to Render

**Issue**: Cookies not persisting
**Solution**:
1. Check if SESSION_SECURE_COOKIE=true
2. Verify CORS_ALLOWED_ORIGINS includes your domain
3. Check if cookies are being blocked by browser

---

## Verify All Changes Are in Place

### Check 1: Session Config
```bash
# Should show 'database' as default
grep "driver.*env.*SESSION_DRIVER" config/session.php
```

### Check 2: Middleware
```bash
# Should have hotel ID restoration
grep "active_hotel_id.*cookie" app/Http/Middleware/RestoreAuthFromCookie.php
```

### Check 3: Routes
```bash
# Should have cookie setting
grep "active_hotel_id.*cookie()" routes/web.php
```

### Check 4: Forms
```bash
# Should have name="hotel_id"
grep 'name="hotel_id"' resources/js/Pages/Auth/AdminLogin.jsx
```

---

## Performance Optimization (After Fix Verified)

Once the loop is fixed, consider:

1. **Use Redis for sessions** (if available on Render):
   ```
   CACHE_DRIVER=redis
   SESSION_DRIVER=redis
   REDIS_HOST=your-redis-url
   ```

2. **Use queue for heavy operations**:
   ```
   QUEUE_CONNECTION=database
   ```

3. **Enable caching**:
   ```
   CACHE_DRIVER=database
   ```

---

## Rollback Plan

If anything breaks:

```bash
# 1. Reset SESSION_DRIVER to 'database' in env
SESSION_DRIVER=database

# 2. Clear all caches
php artisan cache:clear
php artisan config:clear
php artisan route:clear

# 3. Restart the app
# (Render will auto-restart on save)

# 4. If still broken, revert to previous commit
git revert HEAD
git push
```

---

## Success Indicators

After successful deployment:
- ✅ No redirect loops
- ✅ Hotel login → category menu (no loop)
- ✅ Category → admin login (no loop)
- ✅ Admin login → admin dashboard (no loop)
- ✅ Back button works correctly
- ✅ Session persists on page refresh
- ✅ Multiple browser tabs work correctly
- ✅ Logout clears all cookies
- ✅ Logs show no auth errors

---

## Post-Deployment Monitoring

Check logs daily for the first week:

```bash
# SSH into Render (if available)
ssh user@your-app.render.com

# Check Laravel logs
tail -f storage/logs/laravel.log

# Look for errors containing:
# - "Unauthorized"
# - "Session expired"
# - "Redirect loop"
```

---

## Support

If issues persist:
1. Share Render build logs
2. Share browser DevTools error messages
3. Verify all env variables are correct
4. Check MongoDB connection status

**The fix is comprehensive and should resolve all navigation loops on Render.**
