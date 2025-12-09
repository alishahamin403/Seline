/**
 * LLM Proxy Edge Function
 *
 * Handles LLM requests with:
 * - API key pooling (load balancing across multiple keys)
 * - User quota management (fair resource allocation)
 * - Rate limiting (prevents abuse)
 * - Usage tracking (detailed logs for billing/analytics)
 * - Performance isolation (one user can't slow down others)
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Types
interface LLMRequest {
  model: string
  messages: Array<{ role: string; content: string }>
  temperature?: number
  max_tokens?: number
  operation_type?: string  // 'search', 'email_summary', 'chat', etc.
}

interface APIKey {
  id: string
  provider: string
  encrypted_key: string
  current_rpm: number
  max_rpm: number
  is_active: boolean
  is_rate_limited: boolean
}

interface UserBucket {
  tokens: number          // Current burst capacity
  maxTokens: number       // Max burst (based on tier)
  refillRate: number      // Tokens per second
  lastRefill: Date
}

// In-memory state (persists across requests in same worker)
const userBuckets = new Map<string, UserBucket>()
const apiKeyMetrics = new Map<string, { requests: number, lastReset: Date }>()

serve(async (req) => {
  // CORS headers
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    })
  }

  try {
    // 1. Extract and validate JWT
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonError('Missing authorization header', 401)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return jsonError('Unauthorized', 401)
    }

    const userId = user.id

    // 2. Parse request
    const llmRequest: LLMRequest = await req.json()
    const estimatedTokens = estimateTokenCount(llmRequest)

    console.log(`[${userId}] Request: ${llmRequest.operation_type}, Est tokens: ${estimatedTokens}`)

    // 3. Check user quota
    const { data: hasQuota } = await supabase.rpc('check_user_quota', {
      p_user_id: userId,
      p_tokens_needed: estimatedTokens,
    })

    if (!hasQuota) {
      return jsonError('Quota exceeded. Please upgrade your plan or wait for quota reset.', 429)
    }

    // 4. Apply rate limiting (token bucket per user)
    const canProceed = await checkUserRateLimit(userId)
    if (!canProceed) {
      return jsonError('Rate limit exceeded. Please slow down your requests.', 429)
    }

    // 5. Get available API key from pool
    const apiKey = await getAvailableAPIKey(supabase, llmRequest.model)
    if (!apiKey) {
      return jsonError('No API keys available. Please try again later.', 503)
    }

    // 6. Make request to Gemini API
    const startTime = Date.now()
    const response = await callGeminiAPI(apiKey, llmRequest)
    const latency = Date.now() - startTime

    // 7. Parse response and count actual tokens
    const actualTokens = response.usage?.total_tokens || estimatedTokens
    const inputTokens = response.usage?.prompt_tokens || Math.floor(estimatedTokens * 0.7)
    const outputTokens = response.usage?.completion_tokens || Math.floor(estimatedTokens * 0.3)

    // 8. Log usage to database
    await logUsage(supabase, {
      userId,
      provider: 'gemini',
      model: llmRequest.model,
      operationType: llmRequest.operation_type || 'unknown',
      inputTokens,
      outputTokens,
      latency,
      apiKeyHash: hashAPIKey(apiKey.id),
    })

    // 9. Update user quota
    await supabase.rpc('increment_user_quota', {
      p_user_id: userId,
      p_tokens_used: actualTokens,
    })

    // 10. Return response
    return new Response(JSON.stringify(response), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'X-Tokens-Used': actualTokens.toString(),
        'X-Latency-Ms': latency.toString(),
      },
    })

  } catch (error) {
    console.error('LLM Proxy Error:', error)
    return jsonError(error.message || 'Internal server error', 500)
  }
})

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/**
 * Get available API key from pool using least-loaded strategy
 */
async function getAvailableAPIKey(supabase: any, model: string): Promise<APIKey | null> {
  const provider = model.includes('gemini') ? 'gemini' : 'openai'

  // Get all active, non-rate-limited keys for this provider
  const { data: keys, error } = await supabase
    .from('llm_api_keys')
    .select('*')
    .eq('provider', provider)
    .eq('is_active', true)
    .eq('is_rate_limited', false)
    .order('current_rpm', { ascending: true })  // Least loaded first
    .limit(1)

  if (error || !keys || keys.length === 0) {
    console.error('No API keys available:', error)
    return null
  }

  const key = keys[0]

  // Update key metrics
  await supabase
    .from('llm_api_keys')
    .update({
      current_rpm: key.current_rpm + 1,
      total_requests: key.total_requests + 1,
      updated_at: new Date().toISOString(),
    })
    .eq('id', key.id)

  // Reset RPM counter every minute
  const keyMetric = apiKeyMetrics.get(key.id)
  if (!keyMetric || Date.now() - keyMetric.lastReset.getTime() > 60000) {
    apiKeyMetrics.set(key.id, { requests: 1, lastReset: new Date() })
    await supabase
      .from('llm_api_keys')
      .update({ current_rpm: 1, last_reset: new Date().toISOString() })
      .eq('id', key.id)
  }

  return key
}

/**
 * Token bucket rate limiting per user
 */
async function checkUserRateLimit(userId: string): Promise<boolean> {
  const now = new Date()

  // Get or create bucket for this user
  let bucket = userBuckets.get(userId)
  if (!bucket) {
    bucket = {
      tokens: 10,           // Initial burst capacity
      maxTokens: 10,        // Max 10 concurrent requests
      refillRate: 1,        // 1 token per second (60 RPM sustained)
      lastRefill: now,
    }
    userBuckets.set(userId, bucket)
  }

  // Refill tokens based on time elapsed
  const secondsElapsed = (now.getTime() - bucket.lastRefill.getTime()) / 1000
  const tokensToAdd = secondsElapsed * bucket.refillRate
  bucket.tokens = Math.min(bucket.maxTokens, bucket.tokens + tokensToAdd)
  bucket.lastRefill = now

  // Check if user has tokens available
  if (bucket.tokens < 1) {
    console.log(`[${userId}] Rate limited (bucket empty)`)
    return false
  }

  // Consume one token
  bucket.tokens -= 1
  return true
}

/**
 * Call Gemini API
 */
async function callGeminiAPI(apiKey: APIKey, request: LLMRequest) {
  // Decrypt API key (you'll need to implement decryption based on your encryption method)
  const actualKey = decryptAPIKey(apiKey.encrypted_key)

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${request.model}:generateContent?key=${actualKey}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contents: request.messages.map(msg => ({
          role: msg.role === 'user' ? 'user' : 'model',
          parts: [{ text: msg.content }],
        })),
        generationConfig: {
          temperature: request.temperature || 0.7,
          maxOutputTokens: request.max_tokens || 1024,
        },
      }),
    }
  )

  if (!response.ok) {
    const error = await response.text()
    console.error('Gemini API error:', error)
    throw new Error(`Gemini API error: ${response.status}`)
  }

  const data = await response.json()

  // Convert Gemini response to OpenAI-compatible format
  return {
    choices: [{
      message: {
        role: 'assistant',
        content: data.candidates?.[0]?.content?.parts?.[0]?.text || '',
      },
      finish_reason: 'stop',
    }],
    usage: {
      prompt_tokens: data.usageMetadata?.promptTokenCount || 0,
      completion_tokens: data.usageMetadata?.candidatesTokenCount || 0,
      total_tokens: data.usageMetadata?.totalTokenCount || 0,
    },
  }
}

/**
 * Estimate token count from request (rough approximation)
 */
function estimateTokenCount(request: LLMRequest): number {
  const text = request.messages.map(m => m.content).join(' ')
  // Rough estimate: 1 token ≈ 4 characters
  const inputTokens = Math.ceil(text.length / 4)
  const maxOutputTokens = request.max_tokens || 1024
  return inputTokens + maxOutputTokens
}

/**
 * Log usage to database
 */
async function logUsage(supabase: any, usage: any) {
  // Calculate costs based on Gemini 1.5 Flash pricing
  const inputCostPerM = 0.075  // $0.075 per 1M input tokens
  const outputCostPerM = 0.30  // $0.30 per 1M output tokens

  const inputCost = (usage.inputTokens / 1_000_000) * inputCostPerM
  const outputCost = (usage.outputTokens / 1_000_000) * outputCostPerM

  await supabase.from('llm_usage_logs').insert({
    user_id: usage.userId,
    provider: usage.provider,
    model: usage.model,
    operation_type: usage.operationType,
    input_tokens: usage.inputTokens,
    output_tokens: usage.outputTokens,
    input_cost: inputCost,
    output_cost: outputCost,
    latency_ms: usage.latency,
    api_key_used: usage.apiKeyHash,
  })
}

/**
 * Decrypt API key (implement based on your encryption method)
 */
function decryptAPIKey(encryptedKey: string): string {
  // TODO: Implement proper decryption
  // For now, assume keys are stored with AES-256-GCM encryption
  // You can use Deno's built-in crypto API or a library like tweetnacl

  // For development, you might store keys unencrypted in env vars:
  // return Deno.env.get(`GEMINI_API_KEY_${encryptedKey}`) || ''

  // Production: Use proper encryption/decryption
  return encryptedKey  // Placeholder
}

/**
 * Hash API key ID for logging
 */
function hashAPIKey(keyId: string): string {
  // Simple hash for logging purposes
  return keyId.substring(0, 8)
}

/**
 * Return JSON error response
 */
function jsonError(message: string, status: number) {
  return new Response(
    JSON.stringify({ error: message }),
    {
      status,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    }
  )
}
