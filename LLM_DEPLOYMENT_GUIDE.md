# LLM Deployment Guide: Gemini API with User Isolation

This guide explains how to deploy a production-ready LLM system using Gemini API with proper user isolation, quota management, and performance guarantees.

## Architecture Overview

```
iOS App → Supabase Edge Function → API Key Pool → Gemini API
   ↓              ↓                      ↓
 Swift      Rate Limiting         3-5 API Keys
Client      Quota Check           Load Balanced
           User Isolation
```

## Why This Architecture?

**Problem:** Using a single API key directly from your app means:
- One user's heavy usage slows down everyone
- No way to track costs per user
- Hard to implement quotas
- API key exposed in client code
- Single point of failure

**Solution:** Proxy through Supabase Edge Function with:
- ✅ API key pooling (6000 RPM vs 2000 RPM)
- ✅ User isolation (token bucket per user)
- ✅ Quota management (prevent abuse)
- ✅ Cost tracking (know what each user costs)
- ✅ Security (API keys never leave server)

---

## Setup Instructions

### Step 1: Run Database Migration

```bash
cd /Users/alishahamin/Desktop/Vibecode/Seline
supabase db push
```

This creates:
- `llm_usage_logs` - Track every LLM request
- `llm_api_keys` - Server-side API key pool
- User quota fields in `user_profiles`
- Helper functions for quota management

### Step 2: Get Gemini API Keys

1. Go to https://ai.google.dev/
2. Click "Get API key in Google AI Studio"
3. Create **3-5 API keys** (for pooling)
4. Store them securely

### Step 3: Add API Keys to Key Pool

**Option A: Using SQL (Recommended)**

```sql
-- Insert your Gemini API keys (replace with actual keys)
INSERT INTO llm_api_keys (provider, key_hash, encrypted_key, max_rpm, is_active)
VALUES
  ('gemini', 'key1', 'YOUR_GEMINI_KEY_1', 2000, true),
  ('gemini', 'key2', 'YOUR_GEMINI_KEY_2', 2000, true),
  ('gemini', 'key3', 'YOUR_GEMINI_KEY_3', 2000, true);

-- Verify
SELECT provider, key_hash, max_rpm, is_active, total_requests
FROM llm_api_keys;
```

**Option B: Using Supabase Dashboard**

1. Open Supabase Dashboard → Table Editor
2. Select `llm_api_keys` table
3. Insert rows manually
4. **Important:** Set proper encryption in production!

### Step 4: Deploy Edge Function

```bash
# Deploy the LLM proxy function
supabase functions deploy llm-proxy

# Verify deployment
supabase functions list
```

### Step 5: Update iOS App

Replace `OpenAIService.shared` calls with `GeminiProxyService.shared`:

**Before:**
```swift
let response = try await OpenAIService.shared.answerQuestion(query: "What's my spending?")
```

**After:**
```swift
let response = try await GeminiProxyService.shared.ask("What's my spending?", operationType: "spending_query")
```

### Step 6: Add Quota Display to Settings

```swift
// In your settings view
struct SettingsView: View {
    @StateObject private var geminiService = GeminiProxyService.shared

    var body: some View {
        Section("API Usage") {
            HStack {
                Text("Monthly Quota")
                Spacer()
                Text(geminiService.quotaStatusString)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: geminiService.quotaPercentage / 100)
                .tint(geminiService.quotaPercentage > 90 ? .red : .blue)
        }
    }
}
```

---

## Cost Analysis

### Gemini 1.5 Flash Pricing
- **Input:** $0.075 per 1M tokens
- **Output:** $0.30 per 1M tokens

### Per-User Monthly Cost Estimate

| User Type | Requests/Month | Avg Tokens | Cost/Month |
|-----------|----------------|------------|------------|
| Light     | 50             | 3k         | $0.06      |
| Medium    | 200            | 4k         | $0.30      |
| Heavy     | 500            | 5k         | $1.20      |

**For 1,000 users (mixed usage):**
- Average: ~$400/month
- With 50% cheaper pricing vs OpenAI: **Save $200/month**

### Quota Recommendations

```swift
// Suggested monthly quotas
enum SubscriptionTier {
    case free      // 100k tokens  (~$0.04/user)
    case pro       // 500k tokens  (~$0.20/user)  → Charge $2.99/month
    case enterprise // 5M tokens   (~$2.00/user)  → Charge $19.99/month
}
```

---

## Performance Guarantees

### Rate Limiting (Token Bucket)

Each user gets their own "bucket":
- **Burst capacity:** 10 requests (can send 10 at once)
- **Refill rate:** 1 request/second (60 requests/min sustained)
- **Effect:** Heavy users are queued, light users always instant

**Example:**
```
User A sends 100 requests in 10 seconds:
  - First 10: ✅ Instant (burst capacity)
  - Next 10: ✅ Queued (1/sec refill)
  - Rest 80: ⏸️ Rate limited

User B sends 1 request:
  - ✅ Instant (unaffected by User A)
```

### API Key Pooling

With 3 API keys @ 2000 RPM each:
- **Total capacity:** 6000 requests/minute
- **Failover:** If one key rate-limited, use others
- **Load balancing:** Least-loaded key selected

---

## Monitoring & Analytics

### View Usage Logs

```sql
-- Top users by token consumption
SELECT
    user_id,
    SUM(total_tokens) AS total_tokens,
    SUM(total_cost) AS total_cost,
    COUNT(*) AS request_count
FROM llm_usage_logs
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY user_id
ORDER BY total_cost DESC
LIMIT 10;

-- Cost breakdown by operation type
SELECT
    operation_type,
    COUNT(*) AS requests,
    SUM(total_tokens) AS tokens,
    ROUND(SUM(total_cost)::numeric, 4) AS cost_usd
FROM llm_usage_logs
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY operation_type
ORDER BY cost_usd DESC;

-- Average latency by model
SELECT
    model,
    AVG(latency_ms) AS avg_latency_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms) AS p95_latency_ms
FROM llm_usage_logs
WHERE created_at > NOW() - INTERVAL '1 day'
GROUP BY model;
```

### Set Up Alerts

Create a Supabase Edge Function to run daily:

```sql
-- Find users approaching quota limit (>90%)
CREATE OR REPLACE FUNCTION check_quota_alerts()
RETURNS TABLE(user_id UUID, email TEXT, quota_percent NUMERIC) AS $$
SELECT
    up.id,
    up.email,
    ROUND((up.quota_used_this_month::NUMERIC / up.monthly_quota_tokens::NUMERIC) * 100, 1) AS quota_percent
FROM user_profiles up
WHERE up.quota_used_this_month::NUMERIC / up.monthly_quota_tokens::NUMERIC > 0.9
  AND up.bring_own_key = false;
$$ LANGUAGE SQL;

-- Send email alerts for users near quota
-- (Integrate with your email service)
```

---

## Security Best Practices

### 1. Encrypt API Keys

**Never store API keys in plain text!** Use encryption:

```typescript
// In Edge Function
import { crypto } from 'https://deno.land/std@0.168.0/crypto/mod.ts'

async function encryptAPIKey(key: string): Promise<string> {
  const encoder = new TextEncoder()
  const data = encoder.encode(key)

  const encryptionKey = await crypto.subtle.importKey(
    'raw',
    encoder.encode(Deno.env.get('ENCRYPTION_KEY')!),
    { name: 'AES-GCM' },
    false,
    ['encrypt']
  )

  const iv = crypto.getRandomValues(new Uint8Array(12))
  const encrypted = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    encryptionKey,
    data
  )

  return btoa(String.fromCharCode(...new Uint8Array(encrypted)))
}
```

### 2. Environment Variables

Store encryption keys in Supabase secrets:

```bash
# Set encryption key
supabase secrets set ENCRYPTION_KEY=your-32-byte-key-here

# Verify
supabase secrets list
```

### 3. Row-Level Security

**Never disable RLS** on `llm_usage_logs`:

```sql
-- Users can only see their own logs
CREATE POLICY "Users view own logs"
ON llm_usage_logs FOR SELECT
USING (auth.uid() = user_id);
```

### 4. API Key Rotation

Rotate keys every 90 days:

```sql
-- Disable old key
UPDATE llm_api_keys
SET is_active = false
WHERE id = 'old-key-id';

-- Add new key
INSERT INTO llm_api_keys (provider, encrypted_key, max_rpm, is_active)
VALUES ('gemini', 'NEW_ENCRYPTED_KEY', 2000, true);
```

---

## Troubleshooting

### "No API keys available"
**Cause:** All keys are rate-limited
**Solution:**
1. Add more API keys to pool
2. Increase rate limit thresholds
3. Check if keys are marked inactive

### "Quota exceeded"
**Cause:** User hit monthly limit
**Solution:**
1. Wait for quota reset (monthly)
2. Upgrade subscription tier
3. Use bring-your-own-key option

### High latency (>2 seconds)
**Cause:** Queue backlog
**Solution:**
1. Add more API keys (increase throughput)
2. Reduce token limits per request
3. Cache common queries

### Users reporting slow responses
**Check:**
```sql
-- Find slow requests
SELECT user_id, operation_type, latency_ms, created_at
FROM llm_usage_logs
WHERE latency_ms > 3000
ORDER BY created_at DESC
LIMIT 20;
```

---

## Migration from OpenAI

If you're currently using OpenAI, here's how to migrate:

### 1. Parallel Testing
Run both services in parallel:

```swift
// Use feature flag
let useGemini = UserDefaults.standard.bool(forKey: "use_gemini_proxy")

let response = useGemini
    ? try await GeminiProxyService.shared.ask(query)
    : try await OpenAIService.shared.answerQuestion(query)
```

### 2. Gradual Rollout
- Week 1: 10% of users on Gemini
- Week 2: 50% of users on Gemini
- Week 3: 100% on Gemini

### 3. Monitoring
Compare metrics:
- Response quality (user feedback)
- Latency (avg response time)
- Cost ($ per 1k requests)

---

## Next Steps

1. ✅ Run migration: `supabase db push`
2. ✅ Add 3 Gemini API keys to database
3. ✅ Deploy Edge Function: `supabase functions deploy llm-proxy`
4. ✅ Update iOS app to use `GeminiProxyService`
5. ✅ Test with real queries
6. ✅ Monitor usage and costs
7. ✅ Set up quota alerts

## Support

Questions? Check:
- [Gemini API Docs](https://ai.google.dev/gemini-api/docs)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Rate Limits Guide](https://ai.google.dev/gemini-api/docs/rate-limits)

---

**Cost Comparison Summary:**

| Provider | Input | Output | Total (310k tokens/user/month) |
|----------|-------|--------|-------------------------------|
| OpenAI (gpt-4o-mini) | $0.15/1M | $0.60/1M | **$0.10** |
| Gemini 1.5 Flash | $0.075/1M | $0.30/1M | **$0.05** |
| **Savings with Gemini** | | | **50%** |

**For 1,000 users: Save $50/month**
**For 10,000 users: Save $500/month**
