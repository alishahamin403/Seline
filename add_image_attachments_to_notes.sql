-- Add image_attachments column to notes table
-- Store images as JSONB array of base64 strings
ALTER TABLE public.notes
ADD COLUMN IF NOT EXISTS image_attachments JSONB DEFAULT '[]'::jsonb;
