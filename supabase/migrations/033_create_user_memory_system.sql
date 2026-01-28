-- Migration: Create User Memory System
-- Stores contextual knowledge about the user that the LLM should remember
-- Examples: "JVM/James = haircuts", "Starbucks = coffee", "User prefers detailed responses"

CREATE TABLE IF NOT EXISTS user_memory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Memory type: 'entity_relationship', 'merchant_category', 'preference', 'fact', 'pattern'
    memory_type TEXT NOT NULL CHECK (memory_type IN (
        'entity_relationship',  -- "JVM" → "haircuts"
        'merchant_category',    -- "Starbucks" → "coffee"
        'preference',           -- "prefers detailed responses"
        'fact',                 -- "works 9-5"
        'pattern'               -- "gym visits usually 1 hour"
    )),
    
    -- Key: The entity/merchant/preference name
    key TEXT NOT NULL,
    
    -- Value: What it maps to or what it means
    value TEXT NOT NULL,
    
    -- Context: Additional context about this memory
    context TEXT,
    
    -- Confidence: How certain we are (0.0 to 1.0)
    -- Higher = user explicitly stated, lower = inferred
    confidence FLOAT DEFAULT 0.5 CHECK (confidence >= 0.0 AND confidence <= 1.0),
    
    -- Source: Where this memory came from
    -- 'explicit' = user told us directly
    -- 'inferred' = we inferred from patterns
    -- 'conversation' = extracted from conversation
    source TEXT DEFAULT 'inferred' CHECK (source IN ('explicit', 'inferred', 'conversation')),
    
    -- Usage count: How many times this memory has been used
    usage_count INTEGER DEFAULT 0,
    
    -- Last used: When was this memory last referenced
    last_used_at TIMESTAMPTZ,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Unique constraint: one memory per user per key
    UNIQUE(user_id, memory_type, key)
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_user_memory_user_type 
ON user_memory(user_id, memory_type);

CREATE INDEX IF NOT EXISTS idx_user_memory_key 
ON user_memory(user_id, key);

CREATE INDEX IF NOT EXISTS idx_user_memory_confidence 
ON user_memory(user_id, confidence DESC);

-- RLS policies
ALTER TABLE user_memory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own memory"
ON user_memory FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own memory"
ON user_memory FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own memory"
ON user_memory FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own memory"
ON user_memory FOR DELETE
USING (auth.uid() = user_id);

-- Function to upsert memory (update if exists, insert if not)
CREATE OR REPLACE FUNCTION upsert_user_memory(
    p_user_id UUID,
    p_memory_type TEXT,
    p_key TEXT,
    p_value TEXT,
    p_context TEXT DEFAULT NULL,
    p_confidence FLOAT DEFAULT 0.5,
    p_source TEXT DEFAULT 'inferred'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    memory_id UUID;
BEGIN
    INSERT INTO user_memory (
        user_id, memory_type, key, value, context, confidence, source, updated_at
    ) VALUES (
        p_user_id, p_memory_type, p_key, p_value, p_context, p_confidence, p_source, NOW()
    )
    ON CONFLICT (user_id, memory_type, key)
    DO UPDATE SET
        value = EXCLUDED.value,
        context = COALESCE(EXCLUDED.context, user_memory.context),
        confidence = GREATEST(user_memory.confidence, EXCLUDED.confidence), -- Keep highest confidence
        source = CASE 
            WHEN EXCLUDED.source = 'explicit' THEN 'explicit'
            WHEN user_memory.source = 'explicit' THEN 'explicit'
            ELSE EXCLUDED.source
        END,
        updated_at = NOW()
    RETURNING id INTO memory_id;
    
    RETURN memory_id;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION upsert_user_memory TO authenticated;

COMMENT ON TABLE user_memory IS
'Stores contextual knowledge about the user that the LLM should remember across conversations.
Examples: merchant name mappings (JVM → haircuts), user preferences, facts, and patterns.';
