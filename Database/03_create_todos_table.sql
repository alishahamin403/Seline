-- Seline Email App - Todos Table Schema
-- Created: 2025-09-04

CREATE TABLE IF NOT EXISTS todos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    due_date TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    is_completed BOOLEAN DEFAULT FALSE,
    original_speech_text TEXT,
    reminder_date TIMESTAMPTZ,
    priority TEXT,
    completion_date TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_todos_user_id ON todos(user_id);
CREATE INDEX IF NOT EXISTS idx_todos_due_date ON todos(due_date);
CREATE INDEX IF NOT EXISTS idx_todos_is_completed ON todos(is_completed);

-- RLS Policy
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own todos" ON todos
    FOR ALL USING (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON todos TO authenticated;
