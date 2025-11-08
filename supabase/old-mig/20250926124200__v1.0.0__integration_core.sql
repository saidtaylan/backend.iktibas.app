-- Multi-Provider Integration Core Tables
-- Desteklenen external provider'ları tanımlar (Notion, Google Docs, OneDrive vb.)

-- Provider authentication türleri
CREATE TYPE "public"."auth_type" AS ENUM (
    'api_key',
    'oauth2', 
    'bearer_token'
);

-- Integration connection status türleri
CREATE TYPE "public"."connection_status" AS ENUM (
    'active',
    'inactive',
    'error'
);

-- Sync frequency türleri 
CREATE TYPE "public"."sync_frequency" AS ENUM (
    'manual',
    'hourly',
    'daily',
    'weekly'
);

-- Sync direction türleri
CREATE TYPE "public"."sync_direction" AS ENUM (
    'to_provider_only',
    'from_provider_only', 
    'bidirectional'
);

-- Sync status türleri
CREATE TYPE "public"."sync_status" AS ENUM (
    'pending',
    'synced',
    'error'
);

-- External provider'lar (Notion, Google Docs etc.)
CREATE TABLE IF NOT EXISTS "public"."providers" (
    "id" "uuid" NOT NULL DEFAULT gen_random_uuid(),
    "name" "text" NOT NULL UNIQUE, -- 'notion', 'google_docs', 'onedrive'
    "display_name" "text" NOT NULL, -- 'Notion', 'Google Docs'  
    "auth_type" "public"."auth_type" NOT NULL,
    "api_base_url" "text",
    "documentation_url" "text",
    "is_active" boolean NOT NULL DEFAULT true,
    "created_at" timestamp with time zone NOT NULL DEFAULT "timezone"('utc'::"text", "now"()),
    "updated_at" timestamp with time zone NOT NULL DEFAULT "timezone"('utc'::"text", "now"()),
    CONSTRAINT "providers_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "public"."providers" OWNER TO "postgres";

-- Kullanıcıların external provider integration'ları
CREATE TABLE IF NOT EXISTS "public"."readspace_integrations" (
    "id" "uuid" NOT NULL DEFAULT gen_random_uuid(),
    "user_id" "uuid" NOT NULL,
    "provider_id" "uuid" NOT NULL,
    "readspace_id" "uuid" NOT NULL,
    "integration_name" "text" NOT NULL, -- kullanıcının verdiği isim
    "credentials" "jsonb" NOT NULL DEFAULT '{}'::jsonb, -- encrypted provider-specific auth data
    "sync_settings" "jsonb" NOT NULL DEFAULT '{}'::jsonb, -- senkronizasyon ayarları
    "status" "public"."connection_status" NOT NULL DEFAULT 'inactive',
    "last_sync_at" timestamp with time zone,
    "error_message" "text",
    "created_at" timestamp with time zone NOT NULL DEFAULT "timezone"('utc'::"text", "now"()),
    "updated_at" timestamp with time zone NOT NULL DEFAULT "timezone"('utc'::"text", "now"()),
    CONSTRAINT "readspace_integrations_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "readspace_integrations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE,
    CONSTRAINT "readspace_integrations_provider_id_fkey" FOREIGN KEY ("provider_id") REFERENCES "public"."providers"("id") ON DELETE CASCADE,
    CONSTRAINT "readspace_integrations_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE,
    CONSTRAINT "readspace_integrations_status_check" CHECK ("status" = ANY (ARRAY['inactive', 'active', 'error']::public.connection_status[]))
);

ALTER TABLE "public"."readspace_integrations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."integration_destinations" (
    "id" "uuid" NOT NULL DEFAULT gen_random_uuid(),
    "readspace_integration_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "external_id" "text" NOT NULL,
    "name" "text",
    "is_default" boolean NOT NULL DEFAULT false,
    "metadata" "jsonb" NOT NULL DEFAULT '{}'::jsonb,
    "target_database_id" "text",
    "target_page_id" "text",
    "books_page_id" "text",
    "quotes_without_books_page_id" "text",
    "database_properties" "jsonb",
    "page_template_id" "text",
    "color_scheme" "text",
    "icon_type" "text",
    "cover_image" "text",
    "auto_create_pages" boolean NOT NULL DEFAULT true,
    "created_at" timestamp with time zone NOT NULL DEFAULT "timezone"('utc'::"text", "now"()),
    "updated_at" timestamp with time zone NOT NULL DEFAULT "timezone"('utc'::"text", "now"()),
    CONSTRAINT "integration_destinations_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "integration_destinations_integration_id_fkey" FOREIGN KEY ("readspace_integration_id") REFERENCES "public"."readspace_integrations"("id") ON DELETE CASCADE
);

ALTER TABLE "public"."integration_destinations" OWNER TO "postgres";

-- Sync işlem geçmişi ve durumları
CREATE TABLE IF NOT EXISTS "public"."sync_logs" (
    "id" "uuid" NOT NULL DEFAULT gen_random_uuid(),
    "readspace_integration_id" "uuid" NOT NULL,
    "sync_type" "text" NOT NULL, -- 'full', 'incremental', 'manual'
    "status" "public"."sync_status" NOT NULL,
    "items_synced" integer DEFAULT 0,
    "items_failed" integer DEFAULT 0,
    "error_details" "jsonb",
    "started_at" timestamp with time zone NOT NULL DEFAULT "timezone"('utc'::"text", "now"()),
    "completed_at" timestamp with time zone,
    "duration_ms" bigint,
    CONSTRAINT "sync_logs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "sync_logs_integration_id_fkey" FOREIGN KEY ("readspace_integration_id") REFERENCES "public"."readspace_integrations"("id") ON DELETE CASCADE
);

ALTER TABLE "public"."sync_logs" OWNER TO "postgres";

-- Mevcut books tablosuna sync_data kolonu ekle
ALTER TABLE "public"."books" 
ADD COLUMN IF NOT EXISTS "sync_data" "jsonb" NOT NULL DEFAULT '{}'::jsonb;

-- Mevcut quotes tablosuna sync_data kolonu ekle  
ALTER TABLE "public"."quotes"
ADD COLUMN IF NOT EXISTS "sync_data" "jsonb" NOT NULL DEFAULT '{}'::jsonb;

-- Default provider'ları ekle
INSERT INTO "public"."providers" ("name", "display_name", "auth_type", "api_base_url", "documentation_url") VALUES
('notion', 'Notion', 'api_key', 'https://api.notion.com/v1', 'https://developers.notion.com/'),
('google_docs', 'Google Docs', 'oauth2', 'https://docs.googleapis.com/v1', 'https://developers.google.com/docs/api'),
('onedrive', 'OneDrive', 'oauth2', 'https://graph.microsoft.com/v1.0', 'https://docs.microsoft.com/en-us/graph/api/overview')
ON CONFLICT ("name") DO NOTHING;

-- İndeksler
CREATE INDEX IF NOT EXISTS "idx_readspace_integrations_user_id" ON "public"."readspace_integrations"("user_id");
CREATE INDEX IF NOT EXISTS "idx_readspace_integrations_readspace_id" ON "public"."readspace_integrations"("readspace_id");
CREATE INDEX IF NOT EXISTS "idx_readspace_integrations_provider_id" ON "public"."readspace_integrations"("provider_id");
CREATE INDEX IF NOT EXISTS "idx_readspace_integrations_status" ON "public"."readspace_integrations"("status");
CREATE INDEX IF NOT EXISTS "idx_integration_destinations_integration_id" ON "public"."integration_destinations"("readspace_integration_id");
CREATE INDEX IF NOT EXISTS "idx_sync_logs_integration_id" ON "public"."sync_logs"("readspace_integration_id");
CREATE INDEX IF NOT EXISTS "idx_sync_logs_status" ON "public"."sync_logs"("status");
CREATE INDEX IF NOT EXISTS "idx_books_sync_data" ON "public"."books" USING GIN ("sync_data");
CREATE INDEX IF NOT EXISTS "idx_quotes_sync_data" ON "public"."quotes" USING GIN ("sync_data");

-- RLS (Row Level Security) politikaları
ALTER TABLE "public"."readspace_integrations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."integration_destinations" ENABLE ROW LEVEL SECURITY;  
ALTER TABLE "public"."sync_logs" ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi integration'larını görebilir
CREATE POLICY "Users can view own integrations" ON "public"."readspace_integrations"
    FOR ALL USING ("user_id" = "auth"."uid"());

-- Integration destinations policy
CREATE POLICY "Users can view own integration destinations" ON "public"."integration_destinations"
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM "public"."readspace_integrations" 
            WHERE "id" = "integration_destinations"."readspace_integration_id" 
            AND "user_id" = "auth"."uid"()
        )
    );

-- Sync logs policy
CREATE POLICY "Users can view own sync logs" ON "public"."sync_logs"
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM "public"."readspace_integrations"
            WHERE "id" = "sync_logs"."readspace_integration_id"
            AND "user_id" = "auth"."uid"()
        )
    );

-- Providers tablosu herkes tarafından okunabilir (sadece aktif olanlar)
ALTER TABLE "public"."providers" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view active providers" ON "public"."providers"
    FOR SELECT USING ("is_active" = true);

-- Trigger'lar - updated_at otomatik güncelleme
CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Provider updated_at trigger
CREATE TRIGGER "update_providers_updated_at" 
    BEFORE UPDATE ON "public"."providers" 
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- Integration updated_at trigger  
CREATE TRIGGER "update_readspace_integrations_updated_at"
    BEFORE UPDATE ON "public"."readspace_integrations"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- Destination updated_at trigger
CREATE TRIGGER "update_integration_destinations_updated_at"
    BEFORE UPDATE ON "public"."integration_destinations"
    FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

-- Comments
COMMENT ON TABLE "public"."providers" IS 'External integration providers (Notion, Google Docs, etc.)';
COMMENT ON TABLE "public"."readspace_integrations" IS 'User integrations with external providers for specific readspaces';
COMMENT ON TABLE "public"."integration_destinations" IS 'Target destinations within external providers (pages, databases, etc.)';
COMMENT ON TABLE "public"."sync_logs" IS 'Sync operation history and status tracking';
COMMENT ON COLUMN "public"."books"."sync_data" IS 'Provider-specific sync metadata and status';
COMMENT ON COLUMN "public"."quotes"."sync_data" IS 'Provider-specific sync metadata and status';
