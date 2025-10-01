-- Create folders table with hierarchy support
CREATE TABLE IF NOT EXISTS public.folders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color TEXT NOT NULL DEFAULT '#84cae9',
    parent_folder_id UUID REFERENCES public.folders(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Clean up orphaned folder_id references in notes table
-- Set folder_id to NULL for any notes that reference non-existent folders
UPDATE public.notes
SET folder_id = NULL
WHERE folder_id IS NOT NULL
AND folder_id NOT IN (SELECT id FROM public.folders);

-- Add foreign key constraint from notes to folders (may already exist)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'notes_folder_id_fkey'
        AND table_name = 'notes'
    ) THEN
        ALTER TABLE public.notes
        ADD CONSTRAINT notes_folder_id_fkey
        FOREIGN KEY (folder_id) REFERENCES public.folders(id) ON DELETE SET NULL;
    END IF;
END $$;

-- Create index for faster folder queries
CREATE INDEX IF NOT EXISTS folders_user_id_idx ON public.folders(user_id);
CREATE INDEX IF NOT EXISTS folders_parent_folder_id_idx ON public.folders(parent_folder_id);
CREATE INDEX IF NOT EXISTS notes_folder_id_idx ON public.notes(folder_id);

-- Enable RLS
ALTER TABLE public.folders ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for folders
DROP POLICY IF EXISTS "Users can view their own folders" ON public.folders;
CREATE POLICY "Users can view their own folders"
    ON public.folders FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own folders" ON public.folders;
CREATE POLICY "Users can insert their own folders"
    ON public.folders FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own folders" ON public.folders;
CREATE POLICY "Users can update their own folders"
    ON public.folders FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own folders" ON public.folders;
CREATE POLICY "Users can delete their own folders"
    ON public.folders FOR DELETE
    USING (auth.uid() = user_id);

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_folders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS folders_updated_at_trigger ON public.folders;
CREATE TRIGGER folders_updated_at_trigger
    BEFORE UPDATE ON public.folders
    FOR EACH ROW
    EXECUTE FUNCTION update_folders_updated_at();
