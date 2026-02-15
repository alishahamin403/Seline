-- Migration: Fix vector type schema access
-- Date: 2026-02-11
-- Purpose: Fix upsert_embedding function to access vector type in extensions schema
--
-- Bug:
-- The upsert_embedding function has "SET search_path = public" which prevents it
-- from accessing the vector type that exists in the extensions schema.
-- This causes "type 'vector' does not exist" errors when embedding emails and tasks.
--
-- Fix:
-- Change search_path to include both public and extensions schemas.

CREATE OR REPLACE FUNCTION public.upsert_embedding(
    p_user_id uuid,
    p_document_type text,
    p_document_id text,
    p_title text,
    p_content text,
    p_content_hash bigint,
    p_metadata jsonb,
    p_embedding text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions  -- Add extensions schema for vector type
AS $$
DECLARE
    v_embedding_array float[];
BEGIN
    v_embedding_array := string_to_array(trim(both '[]' from p_embedding), ',')::float[];

    IF array_length(v_embedding_array, 1) != 3072 THEN
        RAISE EXCEPTION 'expected 3072 dimensions, not %', array_length(v_embedding_array, 1);
    END IF;

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
$$;

COMMENT ON FUNCTION public.upsert_embedding IS
'Upserts document embeddings with proper access to vector type in extensions schema.
Validates embedding dimensions (3072) before insertion.';
