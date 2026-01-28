-- Migration: Migrate Embeddings from OpenAI (512 dims) to Gemini (768 dims)
-- This migration updates the vector embeddings to use Gemini's text-embedding-004 model
-- which provides 768 dimensions (vs OpenAI's 512) for better search quality

-- STEP 1: Drop existing functions that depend on vector(512)
DROP FUNCTION IF EXISTS search_documents(UUID, vector, TEXT[], INT, FLOAT);
DROP FUNCTION IF EXISTS upsert_embedding(UUID, TEXT, TEXT, TEXT, TEXT, BIGINT, JSONB, vector);

-- STEP 2: Drop the HNSW index (it will be recreated with new dimensions)
DROP INDEX IF EXISTS idx_doc_embeddings_vector;

-- STEP 3: Clear all existing embeddings (they need to be re-generated with new dimensions)
-- This is safe because embeddings will be automatically regenerated on next app launch
TRUNCATE TABLE document_embeddings;

-- STEP 4: Alter the embedding column to use 768 dimensions
ALTER TABLE document_embeddings
    ALTER COLUMN embedding TYPE vector(768);

-- STEP 5: Recreate the HNSW index for 768 dimensions
CREATE INDEX idx_doc_embeddings_vector
ON document_embeddings USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- STEP 6: Recreate the search function with 768 dimensions
CREATE OR REPLACE FUNCTION search_documents(
    p_user_id UUID,
    p_query_embedding vector(768),
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

-- STEP 7: Recreate the upsert function with 768 dimensions
CREATE OR REPLACE FUNCTION upsert_embedding(
    p_user_id UUID,
    p_document_type TEXT,
    p_document_id TEXT,
    p_title TEXT,
    p_content TEXT,
    p_content_hash BIGINT,
    p_metadata JSONB,
    p_embedding vector(768)
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

-- STEP 8: Grant execute permissions (same as before)
GRANT EXECUTE ON FUNCTION search_documents TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_embedding TO authenticated;

-- STEP 9: Update table comment to reflect Gemini usage
COMMENT ON TABLE document_embeddings IS
'Stores vector embeddings for semantic search across notes, emails, tasks, locations, receipts, visits, and people.
Uses Gemini text-embedding-004 (768 dimensions) with HNSW index for fast similarity search.
Embeddings are automatically regenerated after migration.';

-- Migration complete!
-- Next app launch will automatically regenerate all embeddings using Gemini.
