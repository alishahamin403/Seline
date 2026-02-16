-- Migration: Add HNSW index for 1536-dimension embeddings
-- Switches from Gemini 3072-dim to OpenAI text-embedding-3-small (1536-dim)
-- This enables pgvector HNSW indexing for O(log n) similarity search

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- First, clear all existing embeddings (they're 3072-dim, need re-embedding with new model)
-- This is required since we can't convert 3072 -> 1536 directly
TRUNCATE TABLE document_embeddings;

-- Drop ALL existing versions of upsert_embedding function
DO $$
DECLARE
    func_signature text;
BEGIN
    FOR func_signature IN
        SELECT oid::regprocedure::text
        FROM pg_proc
        WHERE proname = 'upsert_embedding'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || func_signature || ' CASCADE';
    END LOOP;
END $$;

-- Recreate the upsert_embedding function with 1536 dimensions
CREATE OR REPLACE FUNCTION upsert_embedding(
    p_user_id uuid,
    p_document_type text,
    p_document_id text,
    p_title text,
    p_content text,
    p_content_hash bigint,
    p_metadata jsonb,
    p_embedding text
) RETURNS void AS $$
DECLARE
    v_embedding_array float[];
BEGIN
    -- Parse the embedding text to array
    v_embedding_array := string_to_array(trim(both '[]' from p_embedding), ',')::float[];

    -- Validate dimensions (1536 for text-embedding-3-small)
    IF array_length(v_embedding_array, 1) != 1536 THEN
        RAISE EXCEPTION 'expected 1536 dimensions, not %', array_length(v_embedding_array, 1);
    END IF;

    -- Upsert the embedding
    INSERT INTO document_embeddings (
        user_id,
        document_type,
        document_id,
        title,
        content,
        content_hash,
        metadata,
        embedding,
        updated_at
    ) VALUES (
        p_user_id,
        p_document_type,
        p_document_id,
        p_title,
        p_content,
        p_content_hash,
        p_metadata,
        v_embedding_array::vector(1536),
        now()
    )
    ON CONFLICT (user_id, document_type, document_id)
    DO UPDATE SET
        title = EXCLUDED.title,
        content = EXCLUDED.content,
        content_hash = EXCLUDED.content_hash,
        metadata = EXCLUDED.metadata,
        embedding = EXCLUDED.embedding,
        updated_at = now();
END;
$$ LANGUAGE plpgsql;

-- Drop and recreate the embedding column to support 1536 dimensions
ALTER TABLE document_embeddings DROP COLUMN IF EXISTS embedding;
ALTER TABLE document_embeddings ADD COLUMN embedding vector(1536);

-- Create HNSW index for fast approximate nearest neighbor search
-- This index supports up to 2000 dimensions, so 1536 works perfectly
-- Parameters: m = 16 (connections per layer), ef_construction = 64 (search width)
-- This provides good balance of speed vs accuracy
CREATE INDEX IF NOT EXISTS document_embeddings_embedding_idx 
ON document_embeddings 
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Add index on user_id for faster user-scoped queries
CREATE INDEX IF NOT EXISTS document_embeddings_user_id_idx 
ON document_embeddings (user_id);

-- Add composite index for common query patterns
CREATE INDEX IF NOT EXISTS document_embeddings_user_type_idx 
ON document_embeddings (user_id, document_type);

-- Comment the changes
COMMENT ON FUNCTION upsert_embedding(uuid, text, text, text, text, bigint, jsonb, text) IS 'Upserts document embeddings with 1536 dimensions for OpenAI text-embedding-3-small';
COMMENT ON COLUMN document_embeddings.embedding IS '1536-dimensional vector embedding from OpenAI text-embedding-3-small with HNSW index';
COMMENT ON INDEX document_embeddings_embedding_idx IS 'HNSW index for fast cosine similarity search';

-- Create a function for indexed similarity search (optional optimization)
CREATE OR REPLACE FUNCTION search_embeddings(
    p_user_id uuid,
    p_query_embedding vector(1536),
    p_document_types text[] DEFAULT NULL,
    p_limit int DEFAULT 10,
    p_min_similarity float DEFAULT 0.0
) RETURNS TABLE (
    document_type text,
    document_id text,
    title text,
    content text,
    metadata jsonb,
    similarity float
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        de.document_type,
        de.document_id,
        de.title,
        de.content,
        de.metadata,
        (1 - (de.embedding <=> p_query_embedding))::float AS similarity
    FROM document_embeddings de
    WHERE de.user_id = p_user_id
      AND de.embedding IS NOT NULL
      AND (p_document_types IS NULL OR de.document_type = ANY(p_document_types))
      AND (1 - (de.embedding <=> p_query_embedding)) >= p_min_similarity
    ORDER BY de.embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION search_embeddings TO authenticated, anon;
