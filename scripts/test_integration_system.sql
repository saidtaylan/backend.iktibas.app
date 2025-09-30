-- Integration System Test Script
-- Bu script integration sisteminin çalışıp çalışmadığını test eder

-- Test kullanıcısı ve readspace oluştur (eğer yoksa)
DO $$
DECLARE
    test_user_id UUID;
    test_readspace_id UUID;
    notion_provider_id UUID;
    integration_id UUID;
BEGIN
    -- Test user ekle (auth.users tablosuna manuel olarak)
    INSERT INTO auth.users (id, email, encrypted_password, role, created_at, updated_at, confirmation_token, email_confirmed_at)
    VALUES (
        gen_random_uuid(),
        'test@iktibas.com',
        crypt('testpassword', gen_salt('bf')),
        'authenticated',
        NOW(),
        NOW(),
        'confirmed',
        NOW()
    )
    ON CONFLICT (email) DO NOTHING
    RETURNING id INTO test_user_id;
    
    -- Eğer kullanıcı zaten varsa ID'sini al
    IF test_user_id IS NULL THEN
        SELECT id INTO test_user_id FROM auth.users WHERE email = 'test@iktibas.com';
    END IF;
    
    RAISE NOTICE 'Test user ID: %', test_user_id;
    
    -- Test readspace ekle
    INSERT INTO public.readspaces (id, name, created_at, updated_at)
    VALUES (
        gen_random_uuid(),
        'Test Integration Readspace',
        NOW(),
        NOW()
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO test_readspace_id;
    
    -- Eğer readspace zaten varsa ID'sini al
    IF test_readspace_id IS NULL THEN
        SELECT id INTO test_readspace_id FROM public.readspaces WHERE name = 'Test Integration Readspace';
    END IF;
    
    RAISE NOTICE 'Test readspace ID: %', test_readspace_id;
    
    -- Readspace membership ekle
    INSERT INTO public.readspace_memberships (readspace_id, user_id, role)
    VALUES (test_readspace_id, test_user_id, 'admin')
    ON CONFLICT DO NOTHING;
    
    -- Notion provider ID'sini al
    SELECT id INTO notion_provider_id FROM public.providers WHERE name = 'notion';
    
    IF notion_provider_id IS NULL THEN
        RAISE EXCEPTION 'Notion provider bulunamadı!';
    END IF;
    
    RAISE NOTICE 'Notion provider ID: %', notion_provider_id;
    
    -- Test integration ekle
    INSERT INTO public.readspace_integrations (
        user_id,
        provider_id, 
        readspace_id,
        integration_name,
        credentials,
        sync_settings,
        status
    )
    VALUES (
        test_user_id,
        notion_provider_id,
        test_readspace_id,
        'Test Notion Integration',
        '{"api_key": "secret_test_key", "workspace_url": "https://test.notion.so"}'::jsonb,
        '{"auto_sync": false, "sync_frequency": "manual", "sync_direction": "to_provider_only", "target_config": {"main_page_id": "test123", "books_page_id": "books123", "quotes_page_id": "quotes123"}}'::jsonb,
        'inactive'
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO integration_id;
    
    RAISE NOTICE 'Test integration ID: %', integration_id;
    
    -- Test kitap ekle
    INSERT INTO public.books (
        user_id,
        readspace_id,
        title,
        author,
        description,
        sync_data
    )
    VALUES (
        test_user_id,
        test_readspace_id,
        'Test Kitap - Integration',
        'Test Yazar',
        'Bu kitap integration sistemini test etmek için oluşturuldu.',
        '{}'::jsonb
    )
    ON CONFLICT DO NOTHING;
    
    -- Test quote ekle
    INSERT INTO public.quotes (
        user_id,
        readspace_id,
        content,
        page,
        sync_data
    )
    VALUES (
        test_user_id,
        test_readspace_id,
        'Bu test alıntısıdır. Integration sistemi bu alıntıyı external provider''a sync edecek.',
        42,
        '{}'::jsonb
    )
    ON CONFLICT DO NOTHING;
    
    -- Test sync log ekle
    IF integration_id IS NOT NULL THEN
        INSERT INTO public.sync_logs (
            readspace_integration_id,
            sync_type,
            status,
            items_synced,
            items_failed
        )
        VALUES (
            integration_id,
            'manual',
            'synced',
            2,
            0
        )
        ON CONFLICT DO NOTHING;
    END IF;
    
    RAISE NOTICE 'Test veriler başarıyla oluşturuldu!';
END $$;

-- Test sorguları çalıştır
SELECT 
    'Integration System Test Results' as test_section,
    '=====================================' as separator;

-- 1. Provider listesi
SELECT 
    'Available Providers' as section,
    p.name,
    p.display_name,
    p.auth_type,
    p.is_active
FROM public.providers p
WHERE p.is_active = true
ORDER BY p.name;

-- 2. Test integration bilgileri
SELECT 
    'Test Integration' as section,
    ri.integration_name,
    ri.status,
    p.display_name as provider,
    ri.sync_settings ->> 'auto_sync' as auto_sync,
    ri.sync_settings -> 'target_config' ->> 'books_page_id' as books_page_id,
    ri.last_sync_at,
    ri.created_at
FROM public.readspace_integrations ri
JOIN public.providers p ON ri.provider_id = p.id
WHERE ri.integration_name = 'Test Notion Integration';

-- 3. Test books sync_data
SELECT 
    'Books Sync Data' as section,
    b.title,
    b.author,
    b.sync_data,
    CASE 
        WHEN b.sync_data = '{}'::jsonb THEN 'Not synced'
        ELSE 'Has sync data'
    END as sync_status
FROM public.books b
WHERE b.title LIKE '%Test Kitap%';

-- 4. Test quotes sync_data
SELECT 
    'Quotes Sync Data' as section,
    LEFT(q.content, 50) || '...' as content_preview,
    q.page,
    q.sync_data,
    CASE 
        WHEN q.sync_data = '{}'::jsonb THEN 'Not synced'
        ELSE 'Has sync data'
    END as sync_status
FROM public.quotes q
WHERE q.content LIKE '%test alıntısıdır%';

-- 5. Sync logs
SELECT 
    'Sync Logs' as section,
    sl.sync_type,
    sl.status,
    sl.items_synced,
    sl.items_failed,
    sl.started_at,
    sl.completed_at,
    CASE 
        WHEN sl.completed_at IS NOT NULL THEN 
            EXTRACT(EPOCH FROM (sl.completed_at - sl.started_at)) * 1000
        ELSE NULL
    END as duration_ms
FROM public.sync_logs sl
ORDER BY sl.started_at DESC
LIMIT 5;

-- 6. RLS test (sadece kendi integration'larını görmeli)
SELECT 
    'RLS Test' as section,
    COUNT(*) as user_integration_count,
    'Should only see own integrations' as note
FROM public.readspace_integrations
-- Bu query RLS aktifken sadece auth'd user'ın integration'larını döner
;

-- 7. JSONB query test
SELECT 
    'JSONB Query Test' as section,
    ri.integration_name,
    ri.sync_settings ->> 'sync_frequency' as sync_frequency,
    ri.sync_settings -> 'target_config' ->> 'auto_create_structure' as auto_create,
    jsonb_pretty(ri.credentials) as credentials_structure
FROM public.readspace_integrations ri
WHERE ri.sync_settings ->> 'sync_direction' = 'to_provider_only';

-- 8. Index performance test
EXPLAIN (ANALYZE, BUFFERS) 
SELECT ri.*, p.display_name
FROM public.readspace_integrations ri
JOIN public.providers p ON ri.provider_id = p.id
WHERE ri.status = 'active'
AND ri.sync_settings ->> 'auto_sync' = 'true';

-- 9. Trigger test (updated_at otomatik güncellemesi)
DO $$
DECLARE
    old_updated_at TIMESTAMP;
    new_updated_at TIMESTAMP;
    test_provider_id UUID;
BEGIN
    -- Test provider'ı bul
    SELECT id, updated_at INTO test_provider_id, old_updated_at 
    FROM public.providers 
    WHERE name = 'notion';
    
    -- Küçük bir güncelleme yap
    UPDATE public.providers 
    SET documentation_url = 'https://developers.notion.com/updated'
    WHERE id = test_provider_id;
    
    -- Yeni updated_at değerini al
    SELECT updated_at INTO new_updated_at 
    FROM public.providers 
    WHERE id = test_provider_id;
    
    IF new_updated_at > old_updated_at THEN
        RAISE NOTICE 'Trigger test SUCCESS: updated_at automatically updated from % to %', old_updated_at, new_updated_at;
    ELSE
        RAISE EXCEPTION 'Trigger test FAILED: updated_at not updated automatically';
    END IF;
    
    -- Değişikliği geri al
    UPDATE public.providers 
    SET documentation_url = 'https://developers.notion.com/'
    WHERE id = test_provider_id;
END $$;

-- 10. Final summary
SELECT 
    'Test Summary' as section,
    (SELECT COUNT(*) FROM public.providers WHERE is_active = true) as active_providers,
    (SELECT COUNT(*) FROM public.readspace_integrations) as total_integrations,
    (SELECT COUNT(*) FROM public.books WHERE sync_data != '{}'::jsonb) as books_with_sync_data,
    (SELECT COUNT(*) FROM public.quotes WHERE sync_data != '{}'::jsonb) as quotes_with_sync_data,
    (SELECT COUNT(*) FROM public.sync_logs) as total_sync_logs,
    CURRENT_TIMESTAMP as test_completed_at;

-- Clean up test data
/*
DO $$
BEGIN
    -- Test verilerini temizle (isteğe bağlı)
    DELETE FROM public.sync_logs 
    WHERE readspace_integration_id IN (
        SELECT id FROM public.readspace_integrations 
        WHERE integration_name = 'Test Notion Integration'
    );
    
    DELETE FROM public.readspace_integrations 
    WHERE integration_name = 'Test Notion Integration';
    
    DELETE FROM public.quotes 
    WHERE content LIKE '%test alıntısıdır%';
    
    DELETE FROM public.books 
    WHERE title LIKE '%Test Kitap%';
    
    DELETE FROM public.readspace_memberships 
    WHERE readspace_id IN (
        SELECT id FROM public.readspaces 
        WHERE name = 'Test Integration Readspace'
    );
    
    DELETE FROM public.readspaces 
    WHERE name = 'Test Integration Readspace';
    
    DELETE FROM auth.users 
    WHERE email = 'test@iktibas.com';
    
    RAISE NOTICE 'Test verileri temizlendi';
END $$;
*/
