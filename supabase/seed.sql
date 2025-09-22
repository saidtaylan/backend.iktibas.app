-- Supabase seed: Admin kullanıcı oluştur
-- Güvenlik notu: Bu dosya yerel geliştirme ve preview branch'leri içindir.
-- Üretimde yönetici kullanıcıları CLI/SDK ile oluşturmanız tavsiye edilir.

-- Gerekli uzantılar
create extension if not exists pgcrypto;

-- Storage buckets seed (idempotent)
-- Not: Bu seed sadece bucket tanımlarını içerir, dosya içeriklerini içermez.
insert into storage.buckets (
  id,
  name,
  owner,
  created_at,
  updated_at,
  public,
  avif_autodetection,
  file_size_limit,
  allowed_mime_types,
  owner_id
) values (
  'book-covers',
  'book-covers',
  null,
  timestamptz '2025-07-16 17:35:37.769323+00',
  timestamptz '2025-07-16 17:35:37.769323+00',
  true,
  false,
  2097152,
  ARRAY['image/*']::text[],
  null
)
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public,
  avif_autodetection = excluded.avif_autodetection,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  owner = excluded.owner,
  owner_id = excluded.owner_id,
  updated_at = excluded.updated_at;
