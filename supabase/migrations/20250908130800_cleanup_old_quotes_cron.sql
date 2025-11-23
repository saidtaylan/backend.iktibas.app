-- 1. Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Create cleanup function
CREATE OR REPLACE FUNCTION cleanup_old_quotes()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- Delete quotes older than 7 days with status 'failed' or 'unreadable'
    DELETE FROM quotes 
    WHERE created_at < (NOW() - INTERVAL '7 days')
    AND status IN ('failed', 'unreadable');
    
    -- Get the number of deleted rows
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    -- Log the deletion (optional)
    INSERT INTO cleanup_logs (function_name, deleted_count, executed_at)
    VALUES ('cleanup_old_quotes', deleted_count, NOW())
    ON CONFLICT DO NOTHING; -- If cleanup_logs table doesn't exist, it won't throw an error
    
    RETURN deleted_count;
END;
$$;

-- 3. Create cron job to run the cleanup function daily at midnight
SELECT cron.schedule(
    'cleanup-old-quotes',              -- job name
    '0 0 * * *',                      -- cron expression (daily at midnight)
    'SELECT public.cleanup_old_quotes();'  -- SQL to run (schema specified)
);

-- 4. Optional: Create log table to track when the function runs
CREATE TABLE IF NOT EXISTS cleanup_logs (
    id SERIAL PRIMARY KEY,
    function_name VARCHAR(50) NOT NULL,
    deleted_count INTEGER NOT NULL DEFAULT 0,
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Manually test the function:
-- SELECT cleanup_old_quotes();

-- 6. List cron jobs:
-- SELECT * FROM cron.job;

-- 7. Optional: Delete the cron job (if needed):
-- SELECT cron.unschedule('cleanup-old-quotes');
