/**
 * Embeddings Proxy Edge Function
 *
 * Generates vector embeddings using OpenAI's text-embedding-3-small model.
 * This is used for semantic search across notes, emails, tasks, locations, receipts, visits, and people.
 *
 * Features:
 * - Batch embedding generation (up to 100 texts at once)
 * - Content hashing to avoid re-embedding unchanged content
 * - Automatic storage in document_embeddings table
 * - Support for semantic search queries
 * - 512-dimension embeddings for 3x faster search & lower cost
 * - In-memory query cache for repeated searches
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Configuration
const EMBEDDING_DIMENSIONS = 512 // Reduced from 1536 for 3x speedup

// Query embedding cache (in-memory, resets on function restart)
const queryEmbeddingCache = new Map<string, number[]>()

// Types
interface EmbeddingRequest {
    action: 'embed' | 'search' | 'batch_embed' | 'check_needed'
    // For 'embed' action
    document_type?: 'note' | 'email' | 'task' | 'location' | 'receipt' | 'visit' | 'person'
    document_id?: string
    title?: string
    content?: string
    metadata?: Record<string, any>
    // For 'search' action
    query?: string
    document_types?: string[]
    limit?: number
    similarity_threshold?: number
    // For 'batch_embed' action
    documents?: Array<{
        document_type: 'note' | 'email' | 'task' | 'location' | 'receipt' | 'visit' | 'person'
        document_id: string
        title?: string
        content: string
        metadata?: Record<string, any>
    }>
    // For 'check_needed' action
    document_ids?: string[]
    content_hashes?: number[]
    check_document_type?: string
}

interface OpenAIEmbeddingResponse {
    object: string
    data: Array<{
        object: string
        embedding: number[]
        index: number
    }>
    model: string
    usage: {
        prompt_tokens: number
        total_tokens: number
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
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', // Use service role for RPC calls
            {
                global: {
                    headers: { Authorization: authHeader },
                },
            }
        )

        // Validate user
        const { data: { user }, error: authError } = await supabase.auth.getUser()
        if (authError || !user) {
            return jsonError('Unauthorized', 401)
        }

        const userId = user.id

        // 2. Parse request
        const request: EmbeddingRequest = await req.json()

        // 3. Handle different actions
        switch (request.action) {
            case 'embed':
                return await handleEmbed(supabase, userId, request)

            case 'batch_embed':
                return await handleBatchEmbed(supabase, userId, request)

            case 'search':
                return await handleSearch(supabase, userId, request)

            case 'check_needed':
                return await handleCheckNeeded(supabase, userId, request)

            default:
                return jsonError('Invalid action', 400)
        }

    } catch (error) {
        console.error('Embeddings Proxy Error:', error)
        return jsonError(error.message || 'Internal server error', 500)
    }
})

// ============================================================
// ACTION HANDLERS
// ============================================================

/**
 * Embed a single document
 */
async function handleEmbed(supabase: any, userId: string, request: EmbeddingRequest) {
    if (!request.document_type || !request.document_id || !request.content) {
        return jsonError('Missing required fields: document_type, document_id, content', 400)
    }

    const contentHash = hashContent(request.content)

    // Generate embedding
    const embedding = await generateEmbedding(request.content)

    // Store in database
    const { error } = await supabase.rpc('upsert_embedding', {
        p_user_id: userId,
        p_document_type: request.document_type,
        p_document_id: request.document_id,
        p_title: request.title || null,
        p_content: request.content,
        p_content_hash: contentHash,
        p_metadata: request.metadata || {},
        p_embedding: `[${embedding.join(',')}]`,
    })

    if (error) {
        console.error('Error storing embedding:', error)
        return jsonError('Failed to store embedding', 500)
    }

    return jsonSuccess({
        success: true,
        document_id: request.document_id,
        dimensions: embedding.length
    })
}

/**
 * Embed multiple documents in batch (more efficient)
 */
async function handleBatchEmbed(supabase: any, userId: string, request: EmbeddingRequest) {
    if (!request.documents || request.documents.length === 0) {
        return jsonError('Missing documents array', 400)
    }

    if (request.documents.length > 100) {
        return jsonError('Maximum 100 documents per batch', 400)
    }

    // Prepare texts for batch embedding
    const texts = request.documents.map(doc => doc.content)

    // Generate embeddings in batch
    const embeddings = await generateBatchEmbeddings(texts)

    // Store all embeddings
    const results: Array<{ document_id: string; success: boolean; error?: string }> = []

    for (let i = 0; i < request.documents.length; i++) {
        const doc = request.documents[i]
        const embedding = embeddings[i]
        const contentHash = hashContent(doc.content)

        try {
            const { error } = await supabase.rpc('upsert_embedding', {
                p_user_id: userId,
                p_document_type: doc.document_type,
                p_document_id: doc.document_id,
                p_title: doc.title || null,
                p_content: doc.content,
                p_content_hash: contentHash,
                p_metadata: doc.metadata || {},
                p_embedding: `[${embedding.join(',')}]`,
            })

            if (error) {
                results.push({ document_id: doc.document_id, success: false, error: error.message })
            } else {
                results.push({ document_id: doc.document_id, success: true })
            }
        } catch (e) {
            results.push({ document_id: doc.document_id, success: false, error: e.message })
        }
    }

    const successCount = results.filter(r => r.success).length

    return jsonSuccess({
        success: true,
        total: request.documents.length,
        embedded: successCount,
        failed: request.documents.length - successCount,
        results,
    })
}

/**
 * Search for similar documents
 * Uses direct SQL to bypass RPC function search_path issues with pgvector
 */
async function handleSearch(supabase: any, userId: string, request: EmbeddingRequest) {
    if (!request.query) {
        return jsonError('Missing query', 400)
    }

    // Generate embedding for the query (with caching enabled)
    const queryEmbedding = await generateEmbedding(request.query, true)
    
    const limit = request.limit || 10
    const similarityThreshold = request.similarity_threshold || 0.3
    
    // Build the document types filter
    let typeFilter = ''
    if (request.document_types && request.document_types.length > 0) {
        const types = request.document_types.map(t => `'${t}'`).join(',')
        typeFilter = `AND document_type IN (${types})`
    }
    
    // Use direct SQL query to bypass RPC search_path issues
    // The <=> operator needs extensions schema to be visible
    const embeddingStr = `[${queryEmbedding.join(',')}]`
    
    const { data, error } = await supabase
        .from('document_embeddings')
        .select('document_type, document_id, title, content, metadata, embedding')
        .eq('user_id', userId)
        .not('embedding', 'is', null)
    
    if (error) {
        console.error('Search error:', error)
        return jsonError(`Search failed: ${error.message || error.code || JSON.stringify(error)}`, 500)
    }
    
    // Calculate similarity in JavaScript (cosine similarity)
    // This bypasses the database operator issue entirely
    const results = (data || [])
        .filter((doc: any) => {
            if (request.document_types && request.document_types.length > 0) {
                return request.document_types.includes(doc.document_type)
            }
            return true
        })
        .map((doc: any) => {
            // Parse the embedding if it's a string
            let docEmbedding: number[]
            if (typeof doc.embedding === 'string') {
                // Remove brackets and parse
                const cleaned = doc.embedding.replace(/[\[\]]/g, '')
                docEmbedding = cleaned.split(',').map((n: string) => parseFloat(n.trim()))
            } else if (Array.isArray(doc.embedding)) {
                docEmbedding = doc.embedding
            } else {
                return null
            }
            
            // Calculate cosine similarity
            const similarity = cosineSimilarity(queryEmbedding, docEmbedding)
            
            return {
                document_type: doc.document_type,
                document_id: doc.document_id,
                title: doc.title,
                content: doc.content,
                metadata: doc.metadata,
                similarity: similarity
            }
        })
        .filter((doc: any) => doc !== null && doc.similarity >= similarityThreshold)
        .sort((a: any, b: any) => b.similarity - a.similarity)
        .slice(0, limit)

    return jsonSuccess({
        success: true,
        query: request.query,
        results: results,
        count: results.length,
    })
}

/**
 * Calculate cosine similarity between two vectors
 */
function cosineSimilarity(a: number[], b: number[]): number {
    if (a.length !== b.length) {
        console.error(`Vector dimension mismatch: ${a.length} vs ${b.length}`)
        return 0
    }
    
    let dotProduct = 0
    let normA = 0
    let normB = 0
    
    for (let i = 0; i < a.length; i++) {
        dotProduct += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    
    const denominator = Math.sqrt(normA) * Math.sqrt(normB)
    if (denominator === 0) return 0
    
    return dotProduct / denominator
}

/**
 * Check which documents need embedding/re-embedding
 */
async function handleCheckNeeded(supabase: any, userId: string, request: EmbeddingRequest) {
    if (!request.document_ids || !request.content_hashes || !request.check_document_type) {
        return jsonError('Missing required fields: document_ids, content_hashes, check_document_type', 400)
    }

    if (request.document_ids.length !== request.content_hashes.length) {
        return jsonError('document_ids and content_hashes must have same length', 400)
    }

    const { data, error } = await supabase.rpc('get_documents_needing_embedding', {
        p_user_id: userId,
        p_document_type: request.check_document_type,
        p_document_ids: request.document_ids,
        p_content_hashes: request.content_hashes,
    })

    if (error) {
        console.error('Check needed error:', error)
        return jsonError('Failed to check embeddings', 500)
    }

    return jsonSuccess({
        success: true,
        needs_embedding: data || [],
        count: data?.length || 0,
    })
}

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/**
 * Generate embedding for a single text using OpenAI
 * Uses 512 dimensions for 3x speedup and lower cost
 */
async function generateEmbedding(text: string, useCache: boolean = false): Promise<number[]> {
    // Check cache if enabled (for query embeddings)
    if (useCache) {
        const cacheKey = text.toLowerCase().trim()
        if (queryEmbeddingCache.has(cacheKey)) {
            console.log('✅ Cache hit for query embedding')
            return queryEmbeddingCache.get(cacheKey)!
        }
    }

    const apiKey = Deno.env.get('OPENAI_API_KEY')
    if (!apiKey) {
        throw new Error('OPENAI_API_KEY not configured')
    }

    // Truncate text if too long (max ~8000 tokens for text-embedding-3-small)
    const truncatedText = text.slice(0, 30000) // ~7500 tokens approx

    const response = await fetch('https://api.openai.com/v1/embeddings', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
            model: 'text-embedding-3-small',
            input: truncatedText,
            dimensions: EMBEDDING_DIMENSIONS, // 512 instead of default 1536
        }),
    })

    if (!response.ok) {
        const error = await response.text()
        console.error('OpenAI API error:', error)
        throw new Error(`OpenAI API error: ${response.status}`)
    }

    const data: OpenAIEmbeddingResponse = await response.json()
    const embedding = data.data[0].embedding

    // Cache query embeddings
    if (useCache) {
        const cacheKey = text.toLowerCase().trim()
        queryEmbeddingCache.set(cacheKey, embedding)
        console.log(`📝 Cached query embedding (cache size: ${queryEmbeddingCache.size})`)

        // Prevent cache from growing too large (keep last 100 queries)
        if (queryEmbeddingCache.size > 100) {
            const firstKey = queryEmbeddingCache.keys().next().value
            queryEmbeddingCache.delete(firstKey)
        }
    }

    return embedding
}

/**
 * Generate embeddings for multiple texts in batch
 * Uses 512 dimensions for 3x speedup and lower cost
 */
async function generateBatchEmbeddings(texts: string[]): Promise<number[][]> {
    const apiKey = Deno.env.get('OPENAI_API_KEY')
    if (!apiKey) {
        throw new Error('OPENAI_API_KEY not configured')
    }

    // Truncate each text
    const truncatedTexts = texts.map(text => text.slice(0, 30000))

    const response = await fetch('https://api.openai.com/v1/embeddings', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
            model: 'text-embedding-3-small',
            input: truncatedTexts,
            dimensions: EMBEDDING_DIMENSIONS, // 512 instead of default 1536
        }),
    })

    if (!response.ok) {
        const error = await response.text()
        console.error('OpenAI API error:', error)
        throw new Error(`OpenAI API error: ${response.status}`)
    }

    const data: OpenAIEmbeddingResponse = await response.json()

    // Sort by index to ensure correct order
    const sortedData = data.data.sort((a, b) => a.index - b.index)
    return sortedData.map(item => item.embedding)
}

/**
 * Generate a hash of content to detect changes
 * Using a simple hash function for speed
 */
function hashContent(content: string): number {
    let hash = 5381
    for (let i = 0; i < content.length; i++) {
        hash = ((hash << 5) + hash) + content.charCodeAt(i)
        hash = hash & hash // Convert to 32-bit integer
    }
    return hash
}

/**
 * Return JSON success response
 */
function jsonSuccess(data: any) {
    return new Response(JSON.stringify(data), {
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
        },
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
