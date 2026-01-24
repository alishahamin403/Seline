-- Create day_summaries table for storing AI-generated summaries of daily visits
-- Summaries are generated once per day and updated when visits with notes are added/modified

CREATE TABLE IF NOT EXISTS day_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    summary_date DATE NOT NULL, -- The date this summary is for (without time)
    summary_text TEXT NOT NULL, -- The AI-generated summary text
    visits_hash BIGINT NOT NULL, -- Hash of visit IDs and notes used to generate this summary (for cache invalidation) - BIGINT to support 64-bit Swift Int
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    -- One summary per user per day
    UNIQUE(user_id, summary_date)
);

-- Create indexes for better query performance
CREATE INDEX idx_day_summaries_user_id ON day_summaries(user_id);
CREATE INDEX idx_day_summaries_summary_date ON day_summaries(summary_date DESC);
CREATE INDEX idx_day_summaries_user_date ON day_summaries(user_id, summary_date DESC);

-- Enable RLS on day_summaries
ALTER TABLE day_summaries ENABLE ROW LEVEL SECURITY;

-- RLS Policies for day_summaries
CREATE POLICY "Users can view their own day summaries" ON day_summaries
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own day summaries" ON day_summaries
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own day summaries" ON day_summaries
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own day summaries" ON day_summaries
    FOR DELETE USING (auth.uid() = user_id);
