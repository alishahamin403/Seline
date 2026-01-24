-- Add visit_notes column to location_visits for storing user's reason for each visit
ALTER TABLE location_visits
ADD COLUMN IF NOT EXISTS visit_notes TEXT NULL;

-- Create location_memories table for storing location-specific facts
-- What user usually buys, why they visit, general patterns
CREATE TABLE IF NOT EXISTS location_memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    saved_place_id UUID NOT NULL REFERENCES saved_places(id) ON DELETE CASCADE,
    memory_type VARCHAR(50) NOT NULL, -- "purchase", "purpose", "habit", "preference"
    content TEXT NOT NULL, -- Natural language description
    items JSONB NULL, -- For purchases: ["vitamins", "allergy meds"]
    frequency VARCHAR(50) NULL, -- "weekly", "monthly", "occasionally"
    day_of_week VARCHAR(10) NULL, -- If specific to certain days
    time_of_day VARCHAR(10) NULL, -- If specific to certain times
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(user_id, saved_place_id, memory_type) -- One memory per type per location
);

-- Create indexes for location_memories
CREATE INDEX idx_location_memories_user_id ON location_memories(user_id);
CREATE INDEX idx_location_memories_saved_place_id ON location_memories(saved_place_id);
CREATE INDEX idx_location_memories_memory_type ON location_memories(memory_type);

-- Enable RLS on location_memories
ALTER TABLE location_memories ENABLE ROW LEVEL SECURITY;

-- RLS Policies for location_memories
CREATE POLICY "Users can view their own location memories" ON location_memories
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own location memories" ON location_memories
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own location memories" ON location_memories
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own location memories" ON location_memories
    FOR DELETE USING (auth.uid() = user_id);
