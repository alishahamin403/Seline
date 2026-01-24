-- Migration: Allow receipts + visits in document_embeddings
-- The initial vector embeddings migration constrained document_type to only
-- ('note','email','task','location'), but the app also embeds 'receipt' and 'visit'.

-- Drop the old CHECK constraint (default name from inline CHECK)
ALTER TABLE public.document_embeddings
DROP CONSTRAINT IF EXISTS document_embeddings_document_type_check;

-- Re-add constraint with expanded set of supported types
ALTER TABLE public.document_embeddings
ADD CONSTRAINT document_embeddings_document_type_check
CHECK (document_type IN ('note', 'email', 'task', 'location', 'receipt', 'visit'));

COMMENT ON TABLE public.document_embeddings IS
'Stores vector embeddings for semantic search across notes, emails, tasks, locations, receipts, and visits.
Uses OpenAI text-embedding-3-small (1536 dimensions) with HNSW index for fast similarity search.';

