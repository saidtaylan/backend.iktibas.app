-- Migration: Book Content System
-- Tarih: 2025-10-04 23:00:00
-- Açıklama: PDF/EPUB content yönetim sistemi için gerekli tablo ve kolon eklemeleri
-- 
-- Eklenenler:
-- 1. ENUM'lar: user_subscription_type, readspace_subscription_type, content_type
-- 2. profiles tablosuna subscription kolonları
-- 3. readspaces tablosuna subscription ve member_count kolonları
-- 4. books tablosuna content metadata kolonları
-- 5. book_reading_progress tablosu
-- 6. readers tablosu
-- 7. Trigger: member_count otomatik güncelleme

-- ============================================================================
-- 1. ENUM Tipleri Oluştur
-- ============================================================================

-- User subscription tipi
CREATE TYPE user_subscription_type AS ENUM ('free', 'pro');
COMMENT ON TYPE user_subscription_type IS 'Kullanıcı abonelik tipi: free veya pro';

-- Readspace subscription tipi
CREATE TYPE readspace_subscription_type AS ENUM ('free', 'team');
COMMENT ON TYPE readspace_subscription_type IS 'ReadSpace abonelik tipi: free veya team';

-- Content type
CREATE TYPE content_type AS ENUM ('pdf', 'epub', 'audio');
COMMENT ON TYPE content_type IS 'Kitap içerik tipi: PDF, EPUB veya sesli kitap';

-- ============================================================================
-- 2. Profiles Tablosuna Subscription Kolonları Ekle
-- ============================================================================

ALTER TABLE public.profiles 
ADD COLUMN subscription_type user_subscription_type DEFAULT 'free' NOT NULL,
ADD COLUMN subscription_expires_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.profiles.subscription_type IS 'Kullanıcının abonelik tipi';
COMMENT ON COLUMN public.profiles.subscription_expires_at IS 'Abonelik bitiş tarihi (NULL ise sınırsız veya free)';

-- Partial index: Sadece expiry date olan subscription'lar
-- Cron job için optimize edilmiş (expire olacak kullanıcıları bul)
CREATE INDEX idx_profiles_subscription_expires ON public.profiles(subscription_expires_at) 
WHERE subscription_expires_at IS NOT NULL;

-- ============================================================================
-- 3. ReadSpaces Tablosuna Subscription Kolonları Ekle
-- ============================================================================

-- NOT: member_count zaten mevcut, sadece subscription kolonları ekleniyor
ALTER TABLE public.readspaces 
ADD COLUMN subscription_type readspace_subscription_type DEFAULT 'free' NOT NULL,
ADD COLUMN subscription_expires_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.readspaces.subscription_type IS 'ReadSpace abonelik tipi';
COMMENT ON COLUMN public.readspaces.subscription_expires_at IS 'Abonelik bitiş tarihi';
COMMENT ON COLUMN public.readspaces.member_count IS 'Üye sayısı (denormalized - trigger ile otomatik güncellenir)';

-- Mevcut member sayılarını doğru değerlerle güncelle
-- (Profil oluşurken 1 yapılıyor ama doğrulamak için)
UPDATE public.readspaces 
SET member_count = (
  SELECT COUNT(*) 
  FROM public.readspace_memberships 
  WHERE readspace_memberships.readspace_id = readspaces.id
)
WHERE member_count = 0 OR member_count IS NULL;

-- ============================================================================
-- 4. Books Tablosuna Content Metadata Kolonları Ekle
-- ============================================================================

ALTER TABLE public.books 
ADD COLUMN content_type content_type NULL,
ADD COLUMN storage_path TEXT NULL,
ADD COLUMN file_size BIGINT NULL,
ADD COLUMN content_uploaded_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
ADD COLUMN content_uploaded_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.books.content_type IS 'İçerik tipi: pdf, epub, audio';
COMMENT ON COLUMN public.books.storage_path IS 'Supabase Storage path (örn: readspace_id/book_id.pdf)';
COMMENT ON COLUMN public.books.file_size IS 'Dosya boyutu (bytes)';
COMMENT ON COLUMN public.books.content_uploaded_by IS 'İçeriği yükleyen kullanıcı';
COMMENT ON COLUMN public.books.content_uploaded_at IS 'İçerik yüklenme zamanı';

-- Index: Content type için filtreleme (WHERE content_type = 'pdf')
-- Partial index: Sadece content olan kitaplar
CREATE INDEX idx_books_content_type ON public.books(content_type) 
WHERE content_type IS NOT NULL;

-- ============================================================================
-- 5. Book Reading Progress Tablosu Oluştur
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.book_reading_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_read_page INTEGER DEFAULT 1 NOT NULL CHECK (last_read_page > 0),
  last_read_at TIMESTAMPTZ DEFAULT timezone('utc', now()) NOT NULL,
  reading_status TEXT DEFAULT 'not_started' NOT NULL CHECK (reading_status IN ('not_started', 'reading', 'completed')),
  created_at TIMESTAMPTZ DEFAULT timezone('utc', now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc', now()) NOT NULL,
  UNIQUE(book_id, user_id)
);

COMMENT ON TABLE public.book_reading_progress IS 'Kullanıcıların kitap okuma ilerlemesi';
COMMENT ON COLUMN public.book_reading_progress.last_read_page IS 'Son okunan sayfa numarası';
COMMENT ON COLUMN public.book_reading_progress.reading_status IS 'Okuma durumu: not_started, reading, completed';

-- Index ekle
CREATE INDEX idx_book_reading_progress_book_id ON public.book_reading_progress(book_id);
CREATE INDEX idx_book_reading_progress_user_id ON public.book_reading_progress(user_id);
CREATE INDEX idx_book_reading_progress_status ON public.book_reading_progress(reading_status);

-- Trigger: updated_at otomatik güncelleme
CREATE TRIGGER update_book_reading_progress_updated_at 
  BEFORE UPDATE ON public.book_reading_progress 
  FOR EACH ROW 
  EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- 6. Readers Tablosu Oluştur
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.readers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  readspace_id UUID NOT NULL REFERENCES public.readspaces(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ DEFAULT timezone('utc', now()) NOT NULL,
  completed_at TIMESTAMPTZ NULL,
  is_active BOOLEAN DEFAULT true NOT NULL,
  created_at TIMESTAMPTZ DEFAULT timezone('utc', now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc', now()) NOT NULL,
  UNIQUE(book_id, user_id, readspace_id)
);

COMMENT ON TABLE public.readers IS 'Bir kitabı okuyan kullanıcılar (team readspace için çoklu okuyucu takibi)';
COMMENT ON COLUMN public.readers.is_active IS 'Hala aktif olarak okuyor mu?';
COMMENT ON COLUMN public.readers.completed_at IS 'Kitabı bitirme tarihi (NULL ise devam ediyor)';

-- Foreign key index'leri (JOIN performansı için kritik)
CREATE INDEX idx_readers_book_id ON public.readers(book_id);
CREATE INDEX idx_readers_user_id ON public.readers(user_id);
CREATE INDEX idx_readers_readspace_id ON public.readers(readspace_id);

-- Partial index: Sadece aktif okuyucular (WHERE is_active = true sorguları için)
CREATE INDEX idx_readers_active ON public.readers(readspace_id, book_id) 
WHERE is_active = true;

-- Trigger: updated_at otomatik güncelleme
CREATE TRIGGER update_readers_updated_at 
  BEFORE UPDATE ON public.readers 
  FOR EACH ROW 
  EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- 7. ReadSpace Member Count Otomatik Güncelleme Trigger'ları
-- ============================================================================

-- NOT: accept_invitation RPC'de zaten count artırılıyor ama trigger güvenli
-- Trigger sayesinde:
-- 1. Her durumda tutarlı (manuel SQL, başka RPC'ler, app)
-- 2. Unutma riski yok
-- 3. Merkezi kontrol
-- 
-- ÖNERİ: accept_invitation RPC'deki count artırma kodunu kaldırabilirsin,
-- trigger otomatik halleder.

-- Member eklendiğinde member_count +1
CREATE OR REPLACE FUNCTION update_member_count_on_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- Yeni member eklendiğinde readspace'in count'unu artır
  UPDATE public.readspaces 
  SET member_count = member_count + 1
  WHERE id = NEW.readspace_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: INSERT sonrası çalışır
CREATE TRIGGER after_member_insert
AFTER INSERT ON public.readspace_memberships
FOR EACH ROW 
EXECUTE FUNCTION update_member_count_on_insert();

-- Member silindiğinde member_count -1
CREATE OR REPLACE FUNCTION update_member_count_on_delete()
RETURNS TRIGGER AS $$
BEGIN
  -- Member silindiğinde readspace'in count'unu azalt
  UPDATE public.readspaces 
  SET member_count = GREATEST(member_count - 1, 0)
  WHERE id = OLD.readspace_id;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: DELETE sonrası çalışır
CREATE TRIGGER after_member_delete
AFTER DELETE ON public.readspace_memberships
FOR EACH ROW 
EXECUTE FUNCTION update_member_count_on_delete();

-- ============================================================================
-- 8. RLS (Row Level Security) Politikaları
-- ============================================================================

-- book_reading_progress RLS
ALTER TABLE public.book_reading_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own reading progress"
  ON public.book_reading_progress
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own reading progress"
  ON public.book_reading_progress
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own reading progress"
  ON public.book_reading_progress
  FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own reading progress"
  ON public.book_reading_progress
  FOR DELETE
  USING (auth.uid() = user_id);

-- readers RLS
ALTER TABLE public.readers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view readers in their readspaces"
  ON public.readers
  FOR SELECT
  USING (
    readspace_id IN (
      SELECT readspace_id 
      FROM public.readspace_memberships 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert themselves as readers"
  ON public.readers
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own reader status"
  ON public.readers
  FOR UPDATE
  USING (auth.uid() = user_id);

-- ============================================================================
-- Migration Tamamlandı
-- ============================================================================

-- Migration başarıyla tamamlandı
SELECT 'Book Content System migration completed successfully' AS status;
