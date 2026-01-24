-- Migration: Fix Vector Search Operator Error
-- Fixes "operator does not exist: extensions.vector <=> extensions.vector" error
-- by ensuring extensions schema is in search_path for all vector functions

-- 1. Update search_documents function to include extensions in search_path
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

-- 2. Update upsert_embedding function to include extensions in search_path
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
