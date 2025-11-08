-- Rollback Migration: Book Content System
-- Tarih: 2025-10-04 23:00:00
-- Açıklama: 20251004230000_book_content_system.sql migration'ını geri al
--
-- UYARI: Bu script tüm book content verilerini silecektir!
-- Production'da çalıştırmadan önce mutlaka backup alın!

-- ============================================================================
-- 1. RLS Politikalarını Sil
-- ============================================================================

-- readers RLS politikaları
DROP POLICY IF EXISTS "Users can update their own reader status" ON public.readers;
DROP POLICY IF EXISTS "Users can insert themselves as readers" ON public.readers;
DROP POLICY IF EXISTS "Users can view readers in their readspaces" ON public.readers;

-- book_reading_progress RLS politikaları
DROP POLICY IF EXISTS "Users can delete their own reading progress" ON public.book_reading_progress;
DROP POLICY IF EXISTS "Users can update their own reading progress" ON public.book_reading_progress;
DROP POLICY IF EXISTS "Users can insert their own reading progress" ON public.book_reading_progress;
DROP POLICY IF EXISTS "Users can view their own reading progress" ON public.book_reading_progress;

-- ============================================================================
-- 2. Trigger'ları Sil
-- ============================================================================

-- Member count trigger'ları
DROP TRIGGER IF EXISTS after_member_delete ON public.readspace_memberships;
DROP FUNCTION IF EXISTS update_member_count_on_delete();

DROP TRIGGER IF EXISTS after_member_insert ON public.readspace_memberships;
DROP FUNCTION IF EXISTS update_member_count_on_insert();

-- Tablo trigger'ları
DROP TRIGGER IF EXISTS update_readers_updated_at ON public.readers;
DROP TRIGGER IF EXISTS update_book_reading_progress_updated_at ON public.book_reading_progress;

-- ============================================================================
-- 3. Index'leri Sil
-- ============================================================================

-- readers index'leri
DROP INDEX IF EXISTS public.idx_readers_active;
DROP INDEX IF EXISTS public.idx_readers_readspace_id;
DROP INDEX IF EXISTS public.idx_readers_user_id;
DROP INDEX IF EXISTS public.idx_readers_book_id;

-- book_reading_progress index'leri
DROP INDEX IF EXISTS public.idx_book_reading_progress_status;
DROP INDEX IF EXISTS public.idx_book_reading_progress_user_id;
DROP INDEX IF EXISTS public.idx_book_reading_progress_book_id;

-- books index'leri
DROP INDEX IF EXISTS public.idx_books_content_type;

-- profiles index'leri
DROP INDEX IF EXISTS public.idx_profiles_subscription_expires;

-- ============================================================================
-- 4. Tabloları Sil
-- ============================================================================

DROP TABLE IF EXISTS public.readers CASCADE;
DROP TABLE IF EXISTS public.book_reading_progress CASCADE;

-- ============================================================================
-- 5. Books Tablosundan Content Kolonlarını Sil
-- ============================================================================

ALTER TABLE public.books 
DROP COLUMN IF EXISTS content_uploaded_at,
DROP COLUMN IF EXISTS content_uploaded_by,
DROP COLUMN IF EXISTS file_size,
DROP COLUMN IF EXISTS storage_path,
DROP COLUMN IF EXISTS content_type;

-- ============================================================================
-- 6. ReadSpaces Tablosundan Subscription Kolonlarını Sil
-- ============================================================================

-- NOT: member_count zaten mevcut ve kullanılıyor, sadece subscription kolonlarını sil
ALTER TABLE public.readspaces 
DROP COLUMN IF EXISTS subscription_expires_at,
DROP COLUMN IF EXISTS subscription_type;

-- ============================================================================
-- 7. Profiles Tablosundan Subscription Kolonlarını Sil
-- ============================================================================

ALTER TABLE public.profiles 
DROP COLUMN IF EXISTS subscription_expires_at,
DROP COLUMN IF EXISTS subscription_type;

-- ============================================================================
-- 8. ENUM Tiplerini Sil
-- ============================================================================

DROP TYPE IF EXISTS content_type CASCADE;
DROP TYPE IF EXISTS readspace_subscription_type CASCADE;
DROP TYPE IF EXISTS user_subscription_type CASCADE;

-- ============================================================================
-- Rollback Tamamlandı
-- ============================================================================

-- Rollback başarıyla tamamlandı
SELECT 'Book Content System rollback completed successfully' AS status;
SELECT 'WARNING: All book content data has been removed!' AS warning;
