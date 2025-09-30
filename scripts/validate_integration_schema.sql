-- Integration Schema Validation Script
-- Bu script migration'ın başarılı olup olmadığını kontrol eder

-- 1. Enum türlerini kontrol et
DO $$ 
BEGIN
    -- auth_type enum kontrolü
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'auth_type') THEN
        RAISE EXCEPTION 'auth_type enum bulunamadı!';
    END IF;
    
    -- connection_status enum kontrolü
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'connection_status') THEN
        RAISE EXCEPTION 'connection_status enum bulunamadı!';
    END IF;
    
    -- sync_frequency enum kontrolü
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sync_frequency') THEN
        RAISE EXCEPTION 'sync_frequency enum bulunamadı!';
    END IF;
    
    RAISE NOTICE 'Enum türleri başarıyla kontrol edildi ✓';
END $$;

-- 2. Tabloların varlığını kontrol et
DO $$
BEGIN
    -- providers tablosu
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables 
                   WHERE table_schema = 'public' AND table_name = 'providers') THEN
        RAISE EXCEPTION 'providers tablosu bulunamadı!';
    END IF;
    
    -- readspace_integrations tablosu
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables 
                   WHERE table_schema = 'public' AND table_name = 'readspace_integrations') THEN
        RAISE EXCEPTION 'readspace_integrations tablosu bulunamadı!';
    END IF;
    
    -- integration_destinations tablosu
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables 
                   WHERE table_schema = 'public' AND table_name = 'integration_destinations') THEN
        RAISE EXCEPTION 'integration_destinations tablosu bulunamadı!';
    END IF;
    
    -- sync_logs tablosu
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables 
                   WHERE table_schema = 'public' AND table_name = 'sync_logs') THEN
        RAISE EXCEPTION 'sync_logs tablosu bulunamadı!';
    END IF;
    
    RAISE NOTICE 'Tüm tablolar başarıyla kontrol edildi ✓';
END $$;

-- 3. Mevcut tablolara eklenen kolonları kontrol et
DO $$
BEGIN
    -- books tablosunda sync_data kolonu
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema = 'public' AND table_name = 'books' AND column_name = 'sync_data') THEN
        RAISE EXCEPTION 'books tablosunda sync_data kolonu bulunamadı!';
    END IF;
    
    -- quotes tablosunda sync_data kolonu
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema = 'public' AND table_name = 'quotes' AND column_name = 'sync_data') THEN
        RAISE EXCEPTION 'quotes tablosunda sync_data kolonu bulunamadı!';
    END IF;
    
    RAISE NOTICE 'Yeni kolonlar başarıyla kontrol edildi ✓';
END $$;

-- 4. Foreign key kısıtlamalarını kontrol et
DO $$
BEGIN
    -- readspace_integrations -> providers FK
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_schema = 'public' 
        AND tc.table_name = 'readspace_integrations'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND kcu.column_name = 'provider_id'
    ) THEN
        RAISE EXCEPTION 'readspace_integrations -> providers FK bulunamadı!';
    END IF;
    
    RAISE NOTICE 'Foreign key kısıtlamaları başarıyla kontrol edildi ✓';
END $$;

-- 5. İndekslerin varlığını kontrol et
DO $$
BEGIN
    -- readspace_integrations indeksleri
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'readspace_integrations' AND indexname = 'idx_readspace_integrations_user_id') THEN
        RAISE EXCEPTION 'idx_readspace_integrations_user_id indeksi bulunamadı!';
    END IF;
    
    -- JSONB GIN indeksleri
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'books' AND indexname = 'idx_books_sync_data') THEN
        RAISE EXCEPTION 'idx_books_sync_data GIN indeksi bulunamadı!';
    END IF;
    
    RAISE NOTICE 'İndeksler başarıyla kontrol edildi ✓';
END $$;

-- 6. RLS politikalarını kontrol et
DO $$
BEGIN
    -- providers tablosu RLS
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'providers' AND policyname = 'Anyone can view active providers'
    ) THEN
        RAISE EXCEPTION 'providers RLS politikası bulunamadı!';
    END IF;
    
    -- readspace_integrations RLS
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'readspace_integrations' AND policyname = 'Users can view own integrations'
    ) THEN
        RAISE EXCEPTION 'readspace_integrations RLS politikası bulunamadı!';
    END IF;
    
    RAISE NOTICE 'RLS politikaları başarıyla kontrol edildi ✓';
END $$;

-- 7. Trigger'ları kontrol et
DO $$
BEGIN
    -- providers updated_at trigger
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.triggers 
        WHERE event_object_schema = 'public' 
        AND event_object_table = 'providers' 
        AND trigger_name = 'update_providers_updated_at'
    ) THEN
        RAISE EXCEPTION 'providers updated_at trigger bulunamadı!';
    END IF;
    
    RAISE NOTICE 'Trigger''lar başarıyla kontrol edildi ✓';
END $$;

-- 8. Default provider'ları kontrol et
DO $$
DECLARE
    provider_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO provider_count FROM providers;
    
    IF provider_count < 3 THEN
        RAISE EXCEPTION 'Yeterli sayıda default provider bulunamadı! Beklenen: en az 3, bulunan: %', provider_count;
    END IF;
    
    -- Notion provider'ı özel kontrol
    IF NOT EXISTS (SELECT 1 FROM providers WHERE name = 'notion' AND display_name = 'Notion') THEN
        RAISE EXCEPTION 'Notion provider bulunamadı!';
    END IF;
    
    RAISE NOTICE 'Default provider''lar başarıyla kontrol edildi (%) ✓', provider_count;
END $$;

-- 9. JSONB default değerlerini kontrol et
DO $$
BEGIN
    -- Test için dummy data ekle ve default değerleri kontrol et
    INSERT INTO providers (name, display_name, auth_type) 
    VALUES ('test_provider', 'Test Provider', 'api_key')
    ON CONFLICT (name) DO NOTHING;
    
    -- JSONB default değerlerini kontrol et
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'readspace_integrations' 
        AND column_name = 'credentials'
        AND column_default = '''{}''::jsonb'
    ) THEN
        RAISE EXCEPTION 'readspace_integrations.credentials JSONB default değeri yanlış!';
    END IF;
    
    -- Test provider'ı temizle
    DELETE FROM providers WHERE name = 'test_provider';
    
    RAISE NOTICE 'JSONB default değerleri başarıyla kontrol edildi ✓';
END $$;

-- 10. Final onay
SELECT 
    'Integration schema validation completed successfully! 🎉' as status,
    CURRENT_TIMESTAMP as validated_at,
    (SELECT COUNT(*) FROM providers) as provider_count,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN (
        'providers', 'readspace_integrations', 'integration_destinations', 'sync_logs'
    )) as integration_table_count;
