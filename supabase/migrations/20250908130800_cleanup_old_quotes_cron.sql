-- 1. pg_cron extension'ını etkinleştir
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Önce temizleme fonksiyonunu oluşturalım
CREATE OR REPLACE FUNCTION cleanup_old_quotes()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- 7 günden eski ve status'u failed veya unreadable olan kayıtları sil
    DELETE FROM quotes 
    WHERE created_at < (NOW() - INTERVAL '7 days')
    AND status IN ('failed', 'unreadable');
    
    -- Silinen kayıt sayısını al
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    -- Log için bilgi kaydet (opsiyonel)
    INSERT INTO cleanup_logs (function_name, deleted_count, executed_at)
    VALUES ('cleanup_old_quotes', deleted_count, NOW())
    ON CONFLICT DO NOTHING; -- Eğer cleanup_logs tablosu yoksa hata vermez
    
    RETURN deleted_count;
END;
$$;

-- 3. Fonksiyonu her gece saat 12:00'da çalıştıracak cron job oluştur
SELECT cron.schedule(
    'cleanup-old-quotes',              -- job name
    '0 0 * * *',                      -- cron expression (her gece 12:00)
    'SELECT public.cleanup_old_quotes();'  -- çalıştırılacak SQL (şema belirtildi)
);

-- 4. Opsiyonel: Log tablosu oluşturma (fonksiyonun ne zaman çalıştığını takip etmek için)
CREATE TABLE IF NOT EXISTS cleanup_logs (
    id SERIAL PRIMARY KEY,
    function_name VARCHAR(50) NOT NULL,
    deleted_count INTEGER NOT NULL DEFAULT 0,
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Fonksiyonu manuel test etmek için:
-- SELECT cleanup_old_quotes();

-- 6. Cron job'ları listelemek için:
-- SELECT * FROM cron.job;

-- 7. Cron job'u silmek için (gerekirse):
-- SELECT cron.unschedule('cleanup-old-quotes');
