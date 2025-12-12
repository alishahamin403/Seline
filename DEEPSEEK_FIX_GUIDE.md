# DeepSeek API Fix Guide

## 🔍 Issues Found

### 1. **Database Function Mismatch** ✅ FIXED
The `check_deepseek_quota` function was returning a BOOLEAN, but the edge function expects a table with `has_quota` and `reset_time` fields.

**Fix:** Created migration `20251212120000_fix_deepseek_quota_function.sql`

### 2. **Missing Daily Quota Tracking** ✅ FIXED
The database only had monthly quotas, but the edge function expects daily quotas (2M tokens/day).

**Fix:** Added daily quota columns and updated functions in the migration.

### 3. **Potential Missing API Key** ⚠️ NEEDS VERIFICATION
The DEEPSEEK_API_KEY may not be set in Supabase secrets.

### 4. **Migrations Not Applied** ⚠️ ACTION REQUIRED
The new migration needs to be applied to your Supabase database.

### 5. **Edge Function May Need Redeployment** ⚠️ ACTION REQUIRED
After applying migrations, the edge function should be redeployed.

---

## 🛠️ Step-by-Step Fix

### Step 1: Apply the Migration

Run this command to apply the new migration:

```bash
supabase db push
```

This will:
- Add daily quota tracking columns
- Fix the `check_deepseek_quota` function to return proper structure
- Update the `increment_deepseek_quota` function to track both daily and monthly usage

### Step 2: Set DeepSeek API Key

If you don't have a DeepSeek API key yet:
1. Go to https://platform.deepseek.com/
2. Sign up and get your API key

Then set it in Supabase:

```bash
# Login to Supabase (if not already logged in)
supabase login

# Set the API key
supabase secrets set DEEPSEEK_API_KEY=your_api_key_here
```

### Step 3: Deploy the Edge Function

```bash
supabase functions deploy deepseek-proxy
```

### Step 4: Verify the Setup

After deployment, test the API by:

1. Open your Seline app
2. Try using the AI chat feature
3. Check the console for any error messages

---

## 📋 What the Migration Fixed

### New Database Columns Added:
```sql
- daily_quota_tokens (2M tokens/day)
- quota_used_today (tracks daily usage)
- daily_quota_reset_date (resets at midnight)
```

### Functions Updated:

**`check_deepseek_quota`** now returns:
- `has_quota`: Boolean indicating if user has enough tokens
- `reset_time`: When the quota resets

**`increment_deepseek_quota`** now:
- Tracks both daily and monthly usage
- Automatically resets at midnight

### View Updated:

**`deepseek_quota_status`** now includes:
- Daily quota info (for real-time limits)
- Monthly quota info (for backward compatibility)

---

## 🔍 Troubleshooting

### Error: "Daily quota exceeded"

**Cause:** User has used 2M tokens today.

**Solution:** Wait until midnight for quota reset, or increase `daily_quota_tokens` in the database.

### Error: "DEEPSEEK_API_KEY not configured"

**Cause:** API key not set in Supabase secrets.

**Solution:** Run `supabase secrets set DEEPSEEK_API_KEY=your_key`

### Error: "Error checking quota"

**Cause:** Migration not applied or function doesn't exist.

**Solution:** Run `supabase db push` to apply migrations.

### Chat Still Not Working

Try these steps:
1. Check Supabase logs: `supabase functions logs deepseek-proxy`
2. Verify API key is set: `supabase secrets list | grep DEEPSEEK`
3. Test edge function directly using curl:

```bash
curl -X POST https://rtiacmeeqkihzhgosvjn.supabase.co/functions/v1/deepseek-proxy \
  -H "Authorization: Bearer YOUR_USER_JWT_TOKEN" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-chat",
    "messages": [{"role": "user", "content": "Hello"}],
    "temperature": 0.7,
    "max_tokens": 100
  }'
```

---

## 📊 Quota Limits

### Free Tier (Default):
- **Daily:** 2,000,000 tokens/day
- **Monthly:** 100,000 tokens/month

### Cost per 1M tokens:
- Input (cache miss): $0.28
- Input (cache hit): $0.028 (10x cheaper!)
- Output: $0.42

**Tip:** DeepSeek caching can save you 90% on repeated prompts!

---

## 🎯 Quick Commands Reference

```bash
# Apply all pending migrations
supabase db push

# Set API key
supabase secrets set DEEPSEEK_API_KEY=sk-xxxxx

# Deploy edge function
supabase functions deploy deepseek-proxy

# View logs
supabase functions logs deepseek-proxy

# Check function status
supabase functions list

# Test locally (if Docker is running)
supabase start
supabase functions serve deepseek-proxy
```

---

## ✅ Verification Checklist

After running the fixes, verify:

- [ ] Migration applied successfully (`supabase db push`)
- [ ] API key is set (`supabase secrets list | grep DEEPSEEK`)
- [ ] Edge function deployed (`supabase functions list`)
- [ ] AI chat works in the app
- [ ] No errors in console logs
- [ ] Quota tracking visible in app

---

## 🚀 Expected Behavior After Fix

1. **First Message:** Should work instantly with <2 second latency
2. **Repeated Queries:** Should be cached and 10x faster
3. **Quota Tracking:** Should show daily usage in the app
4. **Error Handling:** Should show user-friendly quota exceeded messages
5. **Auto-Reset:** Quota resets automatically at midnight

---

## 📚 Additional Resources

- [DeepSeek API Docs](https://api-docs.deepseek.com/)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Supabase CLI Reference](https://supabase.com/docs/reference/cli/introduction)

---

Need help? Check the console logs in Xcode or run `supabase functions logs deepseek-proxy` to see detailed error messages.
