-- Update embedding dimensions from 768 to 3072 for Gemini gemini-embedding-001
-- This migration updates the document_embeddings table and related functions

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

-- Recreate the upsert_embedding function with updated dimension validation
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

    -- Validate dimensions (3072 for gemini-embedding-001)
    IF array_length(v_embedding_array, 1) != 3072 THEN
        RAISE EXCEPTION 'expected 3072 dimensions, not %', array_length(v_embedding_array, 1);
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
        v_embedding_array::vector(3072),
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

-- Drop any existing indexes on the embedding column (pgvector indexes support max 2000 dimensions)
DROP INDEX IF EXISTS document_embeddings_embedding_idx;

-- Drop and recreate the embedding column to support 3072 dimensions
-- Note: No index will be created as pgvector indexes don't support >2000 dimensions
-- This means exact (not approximate) nearest neighbor search will be used
ALTER TABLE document_embeddings DROP COLUMN IF EXISTS embedding;
ALTER TABLE document_embeddings ADD COLUMN embedding vector(3072);

-- Comment the changes
COMMENT ON FUNCTION upsert_embedding(uuid, text, text, text, text, bigint, jsonb, text) IS 'Upserts document embeddings with 3072 dimensions for Gemini gemini-embedding-001';
COMMENT ON COLUMN document_embeddings.embedding IS '3072-dimensional vector embedding from Gemini gemini-embedding-001 (no index - exact NN search)';
