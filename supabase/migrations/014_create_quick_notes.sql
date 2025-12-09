-- Create quick_notes table for Quick Access sticky notes
CREATE TABLE IF NOT EXISTS public.quick_notes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    date_created TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    date_modified TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index on user_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_quick_notes_user_id ON public.quick_notes(user_id);

-- Enable RLS
ALTER TABLE public.quick_notes ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only see their own quick notes
CREATE POLICY "Users can view their own quick notes"
    ON public.quick_notes
    FOR SELECT
    USING (auth.uid() = user_id);

-- RLS Policy: Users can insert their own quick notes
CREATE POLICY "Users can insert their own quick notes"
    ON public.quick_notes
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- RLS Policy: Users can update their own quick notes
CREATE POLICY "Users can update their own quick notes"
    ON public.quick_notes
    FOR UPDATE
    USING (auth.uid() = user_id);

-- RLS Policy: Users can delete their own quick notes
CREATE POLICY "Users can delete their own quick notes"
    ON public.quick_notes
    FOR DELETE
    USING (auth.uid() = user_id);
