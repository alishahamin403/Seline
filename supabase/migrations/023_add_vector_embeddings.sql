-- Migration: Add Vector Embeddings for Semantic Search
-- This enables RAG (Retrieval Augmented Generation) for faster, more relevant LLM context

-- 1. Enable the pgvector extension
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- 2. Create the document_embeddings table
-- This stores embeddings for all searchable content (notes, emails, tasks, locations)
-- Using a unified table is more efficient than adding columns to each table
CREATE TABLE IF NOT EXISTS document_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Document reference
    document_type TEXT NOT NULL CHECK (document_type IN ('note', 'email', 'task', 'location')),
    document_id TEXT NOT NULL, -- UUID or string ID of the source document
    
    -- Searchable content (what was embedded)
    title TEXT,
    content TEXT NOT NULL, -- The full text that was embedded
    content_hash BIGINT NOT NULL, -- Hash of content to detect changes
    
    -- Metadata for filtering
    metadata JSONB DEFAULT '{}',
    
    -- The embedding vector (512 dimensions for OpenAI text-embedding-3-small with reduced dimensions)
    embedding vector(512),
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Unique constraint to prevent duplicates
    UNIQUE(user_id, document_type, document_id)
);

-- 3. Create indexes for efficient querying
-- Index for user_id + document_type filtering (common query pattern)
CREATE INDEX IF NOT EXISTS idx_doc_embeddings_user_type 
ON document_embeddings(user_id, document_type);

-- Index for content hash to quickly check if re-embedding is needed
CREATE INDEX IF NOT EXISTS idx_doc_embeddings_hash 
ON document_embeddings(user_id, document_id, content_hash);

-- HNSW index for fast approximate nearest neighbor search
-- HNSW is faster than IVFFlat for most use cases and doesn't require training
CREATE INDEX IF NOT EXISTS idx_doc_embeddings_vector 
ON document_embeddings USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- 4. Enable Row Level Security
ALTER TABLE document_embeddings ENABLE ROW LEVEL SECURITY;

-- Users can only access their own embeddings
CREATE POLICY "Users can view own embeddings" ON document_embeddings
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own embeddings" ON document_embeddings
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own embeddings" ON document_embeddings
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own embeddings" ON document_embeddings
    FOR DELETE USING (auth.uid() = user_id);

-- 5. Create function for semantic search
-- This function performs vector similarity search with optional filters
CREATE OR REPLACE FUNCTION search_documents(
    p_user_id UUID,
    p_query_embedding vector(512),
    p_document_types TEXT[] DEFAULT NULL,
    p_limit INT DEFAULT 10,
    p_similarity_threshold FLOAT DEFAULT 0.3
)
RETURNS TABLE (
    document_type TEXT,
    document_id TEXT,
    title TEXT,
    content TEXT,
    metadata JSONB,
    similarity FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        de.document_type,
        de.document_id,
        de.title,
        de.content,
        de.metadata,
        1 - (de.embedding <=> p_query_embedding) AS similarity
    FROM document_embeddings de
    WHERE de.user_id = p_user_id
        AND de.embedding IS NOT NULL
        AND (p_document_types IS NULL OR de.document_type = ANY(p_document_types))
        AND 1 - (de.embedding <=> p_query_embedding) >= p_similarity_threshold
    ORDER BY de.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$;

-- 6. Create function to upsert embeddings (insert or update)
CREATE OR REPLACE FUNCTION upsert_embedding(
    p_user_id UUID,
    p_document_type TEXT,
    p_document_id TEXT,
    p_title TEXT,
    p_content TEXT,
    p_content_hash BIGINT,
    p_metadata JSONB,
    p_embedding vector(512)
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    INSERT INTO document_embeddings (
        user_id, document_type, document_id, title, content, 
        content_hash, metadata, embedding, updated_at
    ) VALUES (
        p_user_id, p_document_type, p_document_id, p_title, p_content,
        p_content_hash, p_metadata, p_embedding, NOW()
    )
    ON CONFLICT (user_id, document_type, document_id) 
    DO UPDATE SET
        title = EXCLUDED.title,
        content = EXCLUDED.content,
        content_hash = EXCLUDED.content_hash,
        metadata = EXCLUDED.metadata,
        embedding = EXCLUDED.embedding,
        updated_at = NOW();
END;
$$;

-- 7. Create function to check which documents need re-embedding
CREATE OR REPLACE FUNCTION get_documents_needing_embedding(
    p_user_id UUID,
    p_document_type TEXT,
    p_document_ids TEXT[],
    p_content_hashes BIGINT[]
)
RETURNS TEXT[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    needs_update TEXT[];
BEGIN
    -- Find documents that either don't exist or have different content hash
    SELECT ARRAY_AGG(input_id)
    INTO needs_update
    FROM (
        SELECT UNNEST(p_document_ids) AS input_id, UNNEST(p_content_hashes) AS input_hash
    ) inputs
    LEFT JOIN document_embeddings de 
        ON de.user_id = p_user_id 
        AND de.document_type = p_document_type 
        AND de.document_id = inputs.input_id
    WHERE de.id IS NULL 
        OR de.content_hash != inputs.input_hash
        OR de.embedding IS NULL;
    
    RETURN COALESCE(needs_update, ARRAY[]::TEXT[]);
END;
$$;

-- 8. Create function to delete embeddings for removed documents
CREATE OR REPLACE FUNCTION delete_embedding(
    p_user_id UUID,
    p_document_type TEXT,
    p_document_id TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    DELETE FROM document_embeddings
    WHERE user_id = p_user_id 
        AND document_type = p_document_type 
        AND document_id = p_document_id;
END;
$$;

-- 9. Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION search_documents TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_embedding TO authenticated;
GRANT EXECUTE ON FUNCTION get_documents_needing_embedding TO authenticated;
GRANT EXECUTE ON FUNCTION delete_embedding TO authenticated;

-- 10. Add comment for documentation
COMMENT ON TABLE document_embeddings IS 
'Stores vector embeddings for semantic search across notes, emails, tasks, and locations. 
Uses OpenAI text-embedding-3-small (1536 dimensions) with HNSW index for fast similarity search.';
