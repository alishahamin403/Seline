-- Alter day_summaries.visits_hash from INTEGER to BIGINT
-- Needed because Swift Hasher().finalize() returns 64-bit Int values
-- that exceed PostgreSQL INTEGER range (-2,147,483,648 to 2,147,483,647)

-- Only alter if column exists and is INTEGER type
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'day_summaries' 
        AND column_name = 'visits_hash'
        AND data_type = 'integer'
    ) THEN
        ALTER TABLE day_summaries 
        ALTER COLUMN visits_hash TYPE BIGINT;
        
        RAISE NOTICE 'Altered day_summaries.visits_hash from INTEGER to BIGINT';
    ELSE
        RAISE NOTICE 'Column day_summaries.visits_hash does not exist or is not INTEGER type - skipping';
    END IF;
END $$;
