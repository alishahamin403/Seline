/**
 * DeepSeek Proxy Edge Function (Simplified)
 *
 * Why this is simple:
 * - DeepSeek has NO rate limits! 🎉
 * - No API key pooling needed (1 key works for all users)
 * - No token bucket algorithm needed
 * - No request queuing needed
 *
 * This handles:
 * - User authentication (JWT validation)
 * - Quota management (optional, can disable for unlimited)
 * - Usage tracking (for billing/analytics)
 * - Cost calculation (including cache savings)
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Types
interface DeepSeekRequest {
  model?: string
  messages: Array<{ role: string; content: string }>
  temperature?: number
  max_tokens?: number
  operation_type?: string  // For tracking purposes
  stream?: boolean
}

interface DeepSeekResponse {
  id: string
  choices: Array<{
    message: {
      role: string
      content: string
    }
    finish_reason: string
  }>
  usage: {
    prompt_tokens: number
    completion_tokens: number
    total_tokens: number
    prompt_cache_hit_tokens?: number
    prompt_cache_miss_tokens?: number
  }
}

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
    const deepseekRequest: DeepSeekRequest = await req.json()
    const estimatedTokens = estimateTokenCount(deepseekRequest)

    console.log(`[${userId}] DeepSeek request: ${deepseekRequest.operation_type}, Est tokens: ${estimatedTokens}`)

    // 3. Check user daily quota
    const { data: quotaCheck, error: quotaError } = await supabase.rpc('check_deepseek_quota', {
      p_user_id: userId,
      p_tokens_needed: estimatedTokens,
    })

    if (quotaError || !quotaCheck || quotaCheck.length === 0) {
      return jsonError('Error checking quota. Please try again.', 500)
    }

    const { has_quota, reset_time } = quotaCheck[0]

    if (!has_quota) {
      // Format reset time for user-friendly message
      const resetDate = new Date(reset_time)
      const resetTimeStr = resetDate.toLocaleString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
        timeZoneName: 'short'
      })
      
      return jsonError(
        `Daily quota exceeded. Your quota will reset at ${resetTimeStr}. You've used your daily limit of 2M tokens.`,
        429
      )
    }

    // 4. Call DeepSeek API directly (no pooling, no rate limiting!)
    const startTime = Date.now()
    const response = await callDeepSeekAPI(deepseekRequest)

    // Handle streaming responses
    if (deepseekRequest.stream && response instanceof ReadableStream) {
      return new Response(response, {
        headers: {
          'Content-Type': 'text/event-stream',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        },
      })
    }

    // Non-streaming response (existing logic)
    const latency = Date.now() - startTime
    const deepseekResponse = response as DeepSeekResponse

    // 5. Extract usage metrics
    const usage = deepseekResponse.usage
    const inputTokens = usage.prompt_tokens
    const outputTokens = usage.completion_tokens
    const cacheHitTokens = usage.prompt_cache_hit_tokens || 0
    const cacheMissTokens = usage.prompt_cache_miss_tokens || 0

    // 6. Calculate costs (DeepSeek pricing with cache)
    const costs = calculateCosts(inputTokens, outputTokens, cacheHitTokens, cacheMissTokens)

    // 7. Log usage to database
    await logUsage(supabase, {
      userId,
      model: deepseekRequest.model || 'deepseek-chat',
      operationType: deepseekRequest.operation_type || 'unknown',
      inputTokens,
      outputTokens,
      cacheHitTokens,
      cacheMissTokens,
      costs,
      latency,
    })

    // 8. Update user daily quota
    await supabase.rpc('increment_deepseek_quota', {
      p_user_id: userId,
      p_tokens_used: usage.total_tokens,
    })

    // 9. Return response
    return new Response(JSON.stringify(deepseekResponse), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'X-Tokens-Used': usage.total_tokens.toString(),
        'X-Cache-Hit-Tokens': cacheHitTokens.toString(),
        'X-Latency-Ms': latency.toString(),
        'X-Cost-Usd': costs.total.toFixed(6),
      },
    })

  } catch (error) {
    console.error('DeepSeek Proxy Error:', error)
    return jsonError(error.message || 'Internal server error', 500)
  }
})

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/**
 * Call DeepSeek API with streaming support
 * Docs: https://api-docs.deepseek.com/
 */
async function callDeepSeekAPI(request: DeepSeekRequest): Promise<DeepSeekResponse | ReadableStream> {
  const apiKey = Deno.env.get('DEEPSEEK_API_KEY')
  if (!apiKey) {
    throw new Error('DEEPSEEK_API_KEY not configured')
  }

  // Create AbortController for timeout (80 seconds - leave buffer for Edge Function timeout)
  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), 80000) // 80 seconds

  try {
    const response = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: request.model || 'deepseek-chat',
        messages: request.messages,
        temperature: request.temperature ?? 0.7,
        max_tokens: request.max_tokens ?? 2048,
        stream: request.stream ?? false,
      }),
      signal: controller.signal,
    })

    clearTimeout(timeoutId)

    if (!response.ok) {
      const error = await response.text()
      console.error('DeepSeek API error:', error)
      throw new Error(`DeepSeek API error: ${response.status} - ${error}`)
    }

    // Return stream if requested, otherwise parse JSON
    if (request.stream) {
      return response.body!
    }

    return await response.json()
  } catch (error: any) {
    clearTimeout(timeoutId)
    if (error.name === 'AbortError') {
      throw new Error('Request timed out after 80 seconds. The query may be too complex. Try breaking it into smaller parts.')
    }
    throw error
  }
}

/**
 * Calculate costs based on DeepSeek V3.2 pricing
 *
 * Pricing (as of Dec 2025):
 * - Cache hit: $0.028 per 1M tokens
 * - Cache miss (input): $0.28 per 1M tokens
 * - Output: $0.42 per 1M tokens
 */
function calculateCosts(
  inputTokens: number,
  outputTokens: number,
  cacheHitTokens: number,
  cacheMissTokens: number
) {
  const cacheHitCost = (cacheHitTokens / 1_000_000) * 0.028
  const cacheMissCost = (cacheMissTokens / 1_000_000) * 0.28
  const outputCost = (outputTokens / 1_000_000) * 0.42

  // Calculate savings from caching
  const withoutCacheCost = (inputTokens / 1_000_000) * 0.28
  const withCacheCost = cacheHitCost + cacheMissCost
  const cacheSavings = withoutCacheCost - withCacheCost

  return {
    input: cacheHitCost + cacheMissCost,
    output: outputCost,
    total: cacheHitCost + cacheMissCost + outputCost,
    cacheSavings: Math.max(0, cacheSavings),
  }
}

/**
 * Estimate token count from request (rough approximation)
 */
function estimateTokenCount(request: DeepSeekRequest): number {
  const text = request.messages.map(m => m.content).join(' ')
  // Rough estimate: 1 token ≈ 4 characters
  const inputTokens = Math.ceil(text.length / 4)
  const maxOutputTokens = request.max_tokens || 2048
  return inputTokens + maxOutputTokens
}

/**
 * Log usage to database
 */
async function logUsage(supabase: any, usage: any) {
  await supabase.from('deepseek_usage_logs').insert({
    user_id: usage.userId,
    model: usage.model,
    operation_type: usage.operationType,
    input_tokens: usage.inputTokens,
    output_tokens: usage.outputTokens,
    cache_hit_tokens: usage.cacheHitTokens,
    cache_miss_tokens: usage.cacheMissTokens,
    input_cost: usage.costs.input,
    output_cost: usage.costs.output,
    cache_savings: usage.costs.cacheSavings,
    latency_ms: usage.latency,
  })
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
