# Book Content System Migration Kılavuzu

## 📋 Genel Bakış

Bu migration, PDF/EPUB content yönetim sistemini Supabase veritabanına ekler.

**Migration Dosyası:** `20251004230000_book_content_system.sql`  
**Rollback Dosyası:** `20251004230000_book_content_system_rollback.sql`

## 🎯 Eklenen Özellikler

### 1. ENUM Tipleri
- `user_subscription_type`: `free` | `pro`
- `readspace_subscription_type`: `free` | `team`
- `content_type`: `pdf` | `epub` | `audio`

### 2. Tablo Değişiklikleri

#### `profiles` Tablosu
- `subscription_type` (user_subscription_type, default: 'free')
- `subscription_expires_at` (timestamptz, nullable)

#### `readspaces` Tablosu
- `subscription_type` (readspace_subscription_type, default: 'free')
- `subscription_expires_at` (timestamptz, nullable)
- `member_count` (integer, default: 1, denormalized)

#### `books` Tablosu
- `content_type` (content_type, nullable)
- `storage_path` (text, nullable)
- `file_size` (bigint, nullable)
- `content_uploaded_by` (uuid, foreign key → profiles)
- `content_uploaded_at` (timestamptz, nullable)

### 3. Yeni Tablolar

#### `book_reading_progress`
Kullanıcıların kitap okuma ilerlemesini takip eder.

**Kolonlar:**
- `id` (uuid, primary key)
- `book_id` (uuid, foreign key → books)
- `user_id` (uuid, foreign key → auth.users)
- `last_read_page` (integer, default: 1)
- `last_read_at` (timestamptz)
- `reading_status` ('not_started' | 'reading' | 'completed')
- `created_at`, `updated_at` (timestamptz)

**Unique Constraint:** `(book_id, user_id)`

#### `readers`
Bir kitabı okuyan kullanıcıları takip eder (team readspace için).

**Kolonlar:**
- `id` (uuid, primary key)
- `book_id` (uuid, foreign key → books)
- `user_id` (uuid, foreign key → auth.users)
- `readspace_id` (uuid, foreign key → readspaces)
- `started_at` (timestamptz)
- `completed_at` (timestamptz, nullable)
- `is_active` (boolean, default: true)
- `created_at`, `updated_at` (timestamptz)

**Unique Constraint:** `(book_id, user_id, readspace_id)`

### 4. Trigger'lar

#### Member Count Otomatik Güncelleme
- `after_member_insert`: Yeni member eklendiğinde `readspaces.member_count` +1
- `after_member_delete`: Member silindiğinde `readspaces.member_count` -1

### 5. RLS Politikaları

**`book_reading_progress`:**
- Users can view/insert/update/delete their own reading progress

**`readers`:**
- Users can view readers in their readspaces
- Users can insert themselves as readers
- Users can update their own reader status

## 🚀 Migration'ı Çalıştırma

### Yöntem 1: Supabase CLI (Önerilen)

```bash
cd backend.iktibas

# Migration'ı uygula
supabase db push

# Veya sadece bu migration'ı çalıştır
supabase db execute --file supabase/migrations/20251004230000_book_content_system.sql
```

### Yöntem 2: Manuel SQL (Supabase Dashboard)

1. Supabase Dashboard'a git: `https://your-project.supabase.co`
2. **SQL Editor** bölümüne git
3. `20251004230000_book_content_system.sql` dosyasının içeriğini kopyala
4. SQL Editor'e yapıştır ve **RUN** tuşuna bas

### Yöntem 3: psql (Local Development)

```bash
# Supabase local DB'ye bağlan
psql "postgresql://postgres:postgres@localhost:54322/postgres"

# Migration'ı çalıştır
\i supabase/migrations/20251004230000_book_content_system.sql
```

## ⏮️ Rollback (Geri Alma)

**⚠️ UYARI:** Rollback tüm book content verilerini silecektir! Production'da çalıştırmadan önce mutlaka backup alın!

### Supabase CLI

```bash
supabase db execute --file supabase/migrations/20251004230000_book_content_system_rollback.sql
```

### Manuel SQL

1. `20251004230000_book_content_system_rollback.sql` dosyasını aç
2. İçeriği kopyala
3. SQL Editor'de çalıştır

### psql

```bash
\i supabase/migrations/20251004230000_book_content_system_rollback.sql
```

## 🔍 Migration'ı Doğrulama

Migration başarıyla çalıştıktan sonra aşağıdaki kontrolleri yapın:

```sql
-- 1. ENUM'ların varlığını kontrol et
SELECT typname FROM pg_type WHERE typname IN (
  'user_subscription_type', 
  'readspace_subscription_type', 
  'content_type'
);
-- Beklenen: 3 satır

-- 2. Yeni kolonları kontrol et
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'profiles' 
  AND column_name IN ('subscription_type', 'subscription_expires_at');
-- Beklenen: 2 satır

SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'readspaces' 
  AND column_name IN ('subscription_type', 'subscription_expires_at', 'member_count');
-- Beklenen: 3 satır

SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'books' 
  AND column_name IN ('content_type', 'storage_path', 'file_size');
-- Beklenen: 3 satır

-- 3. Yeni tabloları kontrol et
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN ('book_reading_progress', 'readers');
-- Beklenen: 2 satır

-- 4. Trigger'ları kontrol et
SELECT trigger_name 
FROM information_schema.triggers 
WHERE trigger_name IN ('after_member_insert', 'after_member_delete');
-- Beklenen: 2 satır

-- 5. RLS politikalarını kontrol et
SELECT policyname 
FROM pg_policies 
WHERE tablename IN ('book_reading_progress', 'readers');
-- Beklenen: 7 satır

-- 6. Member count'ların doğruluğunu kontrol et
SELECT id, name, member_count, 
  (SELECT COUNT(*) FROM readspace_memberships WHERE readspace_id = readspaces.id) as actual_count
FROM readspaces;
-- member_count ve actual_count eşit olmalı
```

## 📊 Migration Sırası

Migration'ları doğru sırayla çalıştırın:

1. ✅ **ENUM'lar** → Tip tanımlamaları
2. ✅ **Profiles kolonları** → User subscription
3. ✅ **Readspaces kolonları** → ReadSpace subscription & member_count
4. ✅ **Books kolonları** → Content metadata
5. ✅ **book_reading_progress tablosu** → Okuma ilerlemesi
6. ✅ **readers tablosu** → Çoklu okuyucu takibi
7. ✅ **Trigger'lar** → Otomatik member_count güncelleme
8. ✅ **RLS Politikaları** → Güvenlik

## 🐛 Sorun Giderme

### Hata: "type already exists"

```sql
-- Eğer ENUM zaten varsa, DROP komutuyla silin
DROP TYPE IF EXISTS user_subscription_type CASCADE;
DROP TYPE IF EXISTS readspace_subscription_type CASCADE;
DROP TYPE IF EXISTS content_type CASCADE;

-- Sonra migration'ı tekrar çalıştırın
```

### Hata: "column already exists"

```sql
-- Mevcut kolonları kontrol edin
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'profiles';

-- Eğer kolon varsa, önce silin veya migration'ı düzeltin
ALTER TABLE profiles DROP COLUMN IF EXISTS subscription_type;
```

### Hata: "trigger already exists"

```sql
-- Mevcut trigger'ları silin
DROP TRIGGER IF EXISTS after_member_insert ON readspace_memberships;
DROP TRIGGER IF EXISTS after_member_delete ON readspace_memberships;

-- Function'ları da silin
DROP FUNCTION IF EXISTS update_member_count_on_insert();
DROP FUNCTION IF EXISTS update_member_count_on_delete();
```

### Member Count Yanlış Hesaplandı

```sql
-- Tüm readspace'lerde member_count'u yeniden hesapla
UPDATE readspaces 
SET member_count = (
  SELECT COUNT(*) 
  FROM readspace_memberships 
  WHERE readspace_memberships.readspace_id = readspaces.id
);
```

## 📝 Notlar

- Migration production'a almadan önce **staging ortamında test edin**
- Migration sırasında **downtime beklenmiyor** (yeni kolonlar NULL veya default değerlerle ekleniyor)
- Rollback sonrası **veri kaybı olur**, mutlaka backup alın
- `member_count` denormalized bir kolondur, trigger'lar otomatik güncelleyecektir
- RLS politikaları aktif, user'lar sadece kendi verilerine erişebilir

## 🔗 İlgili Dosyalar

- Flutter Drift Tables: `mobile.iktibas/lib/src/data/local/tables/`
  - `books.dart`
  - `book_reading_progress.dart`
  - `readers.dart`
  - `profiles.dart` (güncellendi)
  - `readspaces.dart` (güncellendi)

- Permission Service: `mobile.iktibas/lib/src/services/book_content/book_content_permission_service.dart`
- Guard'lar: `mobile.iktibas/lib/src/guards/book_content_guards.dart`
- Models: `mobile.iktibas/lib/src/models/book_content_permissions.dart`

## ✅ Checklist

Migration öncesi:
- [ ] Backup aldım
- [ ] Staging'de test ettim
- [ ] Team'e bildirdim
- [ ] Rollback planım var

Migration sonrası:
- [ ] Doğrulama sorguları çalıştırdım
- [ ] Trigger'lar çalışıyor
- [ ] RLS politikaları aktif
- [ ] Member count'lar doğru
- [ ] Flutter app build runner çalıştırdım (`dart run build_runner build`)
- [ ] Test kullanıcılarla denedim
