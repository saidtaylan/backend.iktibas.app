#!/bin/bash

# Bu script veritabanını sıfırlayıp migration dosyasını yükler

echo "🗑️ Şemaları temizleniyor..."

# Public şemayı temizle (tablolar)
docker exec -i supabase-db psql -U postgres -d postgres -c "
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
ALTER SCHEMA public OWNER TO pg_database_owner;
COMMENT ON SCHEMA public IS 'standard public schema';
GRANT CREATE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO postgres;
"

# Auth şemayı temizle ve yeniden oluştur
docker exec -i supabase-db psql -U postgres -d postgres -c "
DROP SCHEMA IF EXISTS auth CASCADE;
CREATE SCHEMA auth;
ALTER SCHEMA auth OWNER TO supabase_admin;
"

# Storage şemayı temizle ve yeniden oluştur
docker exec -i supabase-db psql -U postgres -d postgres -c "
DROP SCHEMA IF EXISTS storage CASCADE;
CREATE SCHEMA storage;
ALTER SCHEMA storage OWNER TO supabase_admin;
"

# Cron extension'ı yeniden yükle
docker exec -i supabase-db psql -U postgres -d postgres -c "
DROP EXTENSION IF EXISTS pg_cron CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_cron;
"

echo "📥 Migration dosyası yükleniyor..."

# Migration dosyasını yükle
docker exec -i supabase-db psql -U postgres -d postgres < /Users/saidtaylan/Developer/iktibas/backend.iktibas/supabase/migrations/19092025-baseline_schema.sql

echo "✅ Migration tamamlandı!"

echo "📊 Tablolar kontrol ediliyor..."
docker exec -i supabase-db psql -U postgres -d postgres -c "\dt public.*"
