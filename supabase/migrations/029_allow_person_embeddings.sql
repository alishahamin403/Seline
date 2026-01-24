-- Migration: Allow 'person' in document_embeddings
-- The app embeds people for semantic search; the CHECK constraint only allowed
-- ('note','email','task','location','receipt','visit'), causing "X persons failed to embed".

ALTER TABLE public.document_embeddings
DROP CONSTRAINT IF EXISTS document_embeddings_document_type_check;

ALTER TABLE public.document_embeddings
ADD CONSTRAINT document_embeddings_document_type_check
CHECK (document_type IN ('note', 'email', 'task', 'location', 'receipt', 'visit', 'person'));

COMMENT ON TABLE public.document_embeddings IS
'Stores vector embeddings for semantic search across notes, emails, tasks, locations, receipts, visits, and people.
Uses OpenAI text-embedding-3-small (512 dimensions) with HNSW index for fast similarity search.';
