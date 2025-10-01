-- Create notes table
CREATE TABLE IF NOT EXISTS notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT DEFAULT '',
    is_locked BOOLEAN DEFAULT FALSE,
    date_created TIMESTAMPTZ DEFAULT NOW(),
    date_modified TIMESTAMPTZ DEFAULT NOW(),
    is_pinned BOOLEAN DEFAULT FALSE,
    folder_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for user_id for faster queries
CREATE INDEX IF NOT EXISTS notes_user_id_idx ON notes(user_id);

-- Create index for date_modified for sorting
CREATE INDEX IF NOT EXISTS notes_date_modified_idx ON notes(date_modified DESC);

-- Enable Row Level Security
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;

-- Create policy to allow users to see only their own notes
CREATE POLICY "Users can view their own notes" ON notes
    FOR SELECT USING (auth.uid() = user_id);

-- Create policy to allow users to insert their own notes
CREATE POLICY "Users can insert their own notes" ON notes
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create policy to allow users to update their own notes
CREATE POLICY "Users can update their own notes" ON notes
    FOR UPDATE USING (auth.uid() = user_id);

-- Create policy to allow users to delete their own notes
CREATE POLICY "Users can delete their own notes" ON notes
    FOR DELETE USING (auth.uid() = user_id);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_notes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    NEW.date_modified = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
CREATE TRIGGER notes_updated_at_trigger
    BEFORE UPDATE ON notes
    FOR EACH ROW
    EXECUTE FUNCTION update_notes_updated_at();