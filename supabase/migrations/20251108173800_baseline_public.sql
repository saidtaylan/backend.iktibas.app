-- =============================================================================
-- TAM VE DÜZELTİLMİŞ MIGRATION DOSYASI
-- İçerik: Tipler, Tablolar, Constraintler, Fonksiyonlar, Triggerlar, Policy'ler
-- =============================================================================

-- 1. BÖLÜM: TİPLER (ENUMS)
-- =============================================================================

DO $$ BEGIN
    CREATE TYPE "public"."auth_type" AS ENUM ('api_key', 'oauth2', 'bearer_token');
EXCEPTION WHEN duplicate_object THEN null; END $$;
ALTER TYPE "public"."auth_type" OWNER TO "postgres";

DO $$ BEGIN
    CREATE TYPE "public"."connection_status" AS ENUM ('active', 'inactive', 'error');
EXCEPTION WHEN duplicate_object THEN null; END $$;
ALTER TYPE "public"."connection_status" OWNER TO "postgres";

DO $$ BEGIN
    CREATE TYPE "public"."content_type" AS ENUM ('pdf', 'image', 'audio');
EXCEPTION WHEN duplicate_object THEN null; END $$;
ALTER TYPE "public"."content_type" OWNER TO "postgres";

DO $$ BEGIN
    CREATE TYPE "public"."readspace_role" AS ENUM ('owner', 'admin', 'editor', 'viewer');
EXCEPTION WHEN duplicate_object THEN null; END $$;
ALTER TYPE "public"."readspace_role" OWNER TO "postgres";

DO $$ BEGIN
    CREATE TYPE "public"."readspace_subscription_type" AS ENUM ('free', 'team');
EXCEPTION WHEN duplicate_object THEN null; END $$;
ALTER TYPE "public"."readspace_subscription_type" OWNER TO "postgres";
COMMENT ON TYPE "public"."readspace_subscription_type" IS 'ReadSpace abonelik tipi: free veya team';

DO $$ BEGIN
    CREATE TYPE "public"."sync_direction" AS ENUM ('to_provider_only', 'from_provider_only', 'bidirectional');
EXCEPTION WHEN duplicate_object THEN null; END $$;
ALTER TYPE "public"."sync_direction" OWNER TO "postgres";

DO $$ BEGIN
    CREATE TYPE "public"."sync_frequency" AS ENUM ('manual', 'hourly', 'daily', 'weekly');
EXCEPTION WHEN duplicate_object THEN null; END $$;
ALTER TYPE "public"."sync_frequency" OWNER TO "postgres";

DO $$ BEGIN
    CREATE TYPE "public"."sync_status" AS ENUM ('pending', 'synced', 'error');
EXCEPTION WHEN duplicate_object THEN null; END $$;
ALTER TYPE "public"."sync_status" OWNER TO "postgres";

DO $$ BEGIN
    CREATE TYPE "public"."user_subscription_type" AS ENUM ('free', 'pro');
EXCEPTION WHEN duplicate_object THEN null; END $$;
ALTER TYPE "public"."user_subscription_type" OWNER TO "postgres";
COMMENT ON TYPE "public"."user_subscription_type" IS 'Kullanıcı abonelik tipi: free veya pro';


-- =============================================================================
-- 2. BÖLÜM: SEQUENCES & TABLES
-- =============================================================================

SET default_tablespace = '';
SET default_table_access_method = "heap";

CREATE SEQUENCE IF NOT EXISTS "public"."cleanup_logs_id_seq";
ALTER SEQUENCE "public"."cleanup_logs_id_seq" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."gemini_rr_seq";
ALTER SEQUENCE "public"."gemini_rr_seq" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."app_versions_id_seq";
ALTER SEQUENCE "public"."app_versions_id_seq" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."app_versions" (
    "id" bigint DEFAULT nextval('public.app_versions_id_seq') NOT NULL,
    "platform" "text" NOT NULL,
    "version" "text" NOT NULL,
    "build_number" integer DEFAULT 0 NOT NULL,
    "minimum_supported_version" "text",
    "is_critical" boolean DEFAULT false NOT NULL,
    "is_released" boolean DEFAULT true NOT NULL,
    "release_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "release_notes" "text",
    "store_url" "text" DEFAULT ''::"text" NOT NULL,
    CONSTRAINT "app_versions_platform_check" CHECK (("platform" = ANY (ARRAY['ios'::"text", 'android'::"text"])))
);
ALTER TABLE "public"."app_versions" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."book_reading_progress" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "book_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "last_read_page" integer DEFAULT 1 NOT NULL,
    "last_read_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "reading_status" "text" DEFAULT 'not_started'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "book_reading_progress_last_read_page_check" CHECK (("last_read_page" > 0)),
    CONSTRAINT "book_reading_progress_reading_status_check" CHECK (("reading_status" = ANY (ARRAY['not_started'::"text", 'reading'::"text", 'completed'::"text"])))
);
ALTER TABLE "public"."book_reading_progress" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."books" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "title" "text" NOT NULL,
    "author" "text",
    "publish_year" smallint,
    "publisher" "text",
    "version" bigint DEFAULT 1 NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "description" "text",
    "image_url" "text",
    "readspace_id" "uuid" NOT NULL,
    "page_count" integer,
    "sync_data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "content_type" "public"."content_type",
    "storage_path" "text",
    "file_size" bigint,
    "content_uploaded_by" "uuid",
    "content_uploaded_at" timestamp with time zone,
    "external_file_url" "text"
);
ALTER TABLE "public"."books" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."cleanup_logs" (
    "id" integer DEFAULT nextval('public.cleanup_logs_id_seq') NOT NULL,
    "function_name" character varying(50) NOT NULL,
    "deleted_count" integer DEFAULT 0 NOT NULL,
    "executed_at" timestamp with time zone DEFAULT "now"()
);
ALTER TABLE "public"."cleanup_logs" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."integration_destinations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "readspace_integration_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "external_id" "text" NOT NULL,
    "name" "text",
    "is_default" boolean DEFAULT false NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "target_database_id" "text",
    "target_page_id" "text",
    "books_page_id" "text",
    "quotes_without_books_page_id" "text",
    "database_properties" "jsonb",
    "page_template_id" "text",
    "color_scheme" "text",
    "icon_type" "text",
    "cover_image" "text",
    "auto_create_pages" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);
ALTER TABLE "public"."integration_destinations" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "readspace_id" "uuid" NOT NULL,
    "inviter_id" "uuid" NOT NULL,
    "invitee_email" "text" NOT NULL,
    "invitee_user_id" "uuid",
    "role" "public"."readspace_role" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "token" "text" DEFAULT "encode"("extensions"."gen_random_bytes"(16), 'hex'::"text") NOT NULL,
    "message" "text",
    "expires_at" timestamp with time zone,
    "accepted_at" timestamp with time zone,
    "declined_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "invitations_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text", 'expired'::"text", 'canceled'::"text"])))
);
ALTER TABLE "public"."invitations" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "name" "text",
    "avatar_url" "text",
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "email" "text",
    "subscription_type" "public"."user_subscription_type" DEFAULT 'pro'::"public"."user_subscription_type" NOT NULL,
    "subscription_expires_at" timestamp with time zone
);
ALTER TABLE "public"."profiles" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."providers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "display_name" "text" NOT NULL,
    "auth_type" "public"."auth_type" NOT NULL,
    "api_base_url" "text",
    "documentation_url" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);
ALTER TABLE "public"."providers" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."published_quotes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "quote_id" "uuid" NOT NULL,
    "public_slug" character varying(128) NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "view_count" integer DEFAULT 0 NOT NULL,
    "expires_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "privacy_level" "text" DEFAULT 'public'::"text",
    "last_viewed_at" timestamp with time zone,
    "readspace_id" "uuid" NOT NULL,
    CONSTRAINT "shared_quotes_privacy_level_check" CHECK (("privacy_level" = ANY (ARRAY['public'::"text", 'private'::"text", 'password_protected'::"text"])))
);
ALTER TABLE "public"."published_quotes" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."quotes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "readspace_id" "uuid" NOT NULL,
    "book_id" "uuid",
    "content" "text",
    "page" integer,
    "status" "text" DEFAULT 'completed'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "notification_shown" boolean DEFAULT false NOT NULL,
    "user_device_id" "uuid",
    "sync_data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "type" "public"."content_type"
);
ALTER TABLE "public"."quotes" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."readers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "book_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "readspace_id" "uuid" NOT NULL,
    "started_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "completed_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);
ALTER TABLE "public"."readers" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."readspace_integrations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "provider_id" "uuid" NOT NULL,
    "readspace_id" "uuid" NOT NULL,
    "integration_name" "text" NOT NULL,
    "credentials" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "sync_settings" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "public"."connection_status" DEFAULT 'inactive'::"public"."connection_status" NOT NULL,
    "last_sync_at" timestamp with time zone,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "readspace_integrations_status_check" CHECK (("status" = ANY (ARRAY['inactive'::"public"."connection_status", 'active'::"public"."connection_status", 'error'::"public"."connection_status"])))
);
ALTER TABLE "public"."readspace_integrations" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."readspace_memberships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "readspace_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."readspace_role" DEFAULT 'admin'::"public"."readspace_role" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."readspace_memberships" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."readspaces" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "is_personal" boolean DEFAULT false NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_shared" boolean DEFAULT false,
    "active_book_id" "uuid",
    "member_count" integer DEFAULT 1 NOT NULL,
    "subscription_type" "public"."readspace_subscription_type" DEFAULT 'team'::"public"."readspace_subscription_type" NOT NULL,
    "subscription_expires_at" timestamp with time zone
);
ALTER TABLE "public"."readspaces" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."sync_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "readspace_integration_id" "uuid" NOT NULL,
    "sync_type" "text" NOT NULL,
    "status" "public"."sync_status" NOT NULL,
    "items_synced" integer DEFAULT 0,
    "items_failed" integer DEFAULT 0,
    "error_details" "jsonb",
    "started_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "completed_at" timestamp with time zone,
    "duration_ms" bigint
);
ALTER TABLE "public"."sync_logs" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."user_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "device_name" "text" NOT NULL,
    "device_type" "text" NOT NULL,
    "active_readspace_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_login_at" timestamp with time zone,
    "is_active" boolean DEFAULT true,
    "device_id" "text"
);
ALTER TABLE "public"."user_devices" OWNER TO "postgres";


-- =============================================================================
-- 3. BÖLÜM: PRIMARY KEYS & UNIQUE CONSTRAINTS (ROBUST)
-- "42P07": Relation (Index) already exists hatasını da yutar.
-- =============================================================================

-- PRIMARY KEYS

DO $$ BEGIN
    ALTER TABLE ONLY "public"."app_versions" ADD CONSTRAINT "app_versions_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."book_reading_progress" ADD CONSTRAINT "book_reading_progress_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."books" ADD CONSTRAINT "books_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."cleanup_logs" ADD CONSTRAINT "cleanup_logs_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."integration_destinations" ADD CONSTRAINT "integration_destinations_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."invitations" ADD CONSTRAINT "invitations_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."profiles" ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."providers" ADD CONSTRAINT "providers_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."published_quotes" ADD CONSTRAINT "shared_quotes_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."quotes" ADD CONSTRAINT "quotes_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readers" ADD CONSTRAINT "readers_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspace_integrations" ADD CONSTRAINT "readspace_integrations_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspace_memberships" ADD CONSTRAINT "readspace_memberships_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspaces" ADD CONSTRAINT "readspaces_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."sync_logs" ADD CONSTRAINT "sync_logs_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."user_devices" ADD CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P16' THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;


-- UNIQUE CONSTRAINTS

DO $$ BEGIN
    ALTER TABLE ONLY "public"."app_versions" ADD CONSTRAINT "app_versions_platform_version_build_key" UNIQUE ("platform", "version", "build_number");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."book_reading_progress" ADD CONSTRAINT "book_reading_progress_book_id_user_id_key" UNIQUE ("book_id", "user_id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."invitations" ADD CONSTRAINT "invitations_token_key" UNIQUE ("token");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."providers" ADD CONSTRAINT "providers_name_key" UNIQUE ("name");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readers" ADD CONSTRAINT "readers_book_id_user_id_readspace_id_key" UNIQUE ("book_id", "user_id", "readspace_id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspace_memberships" ADD CONSTRAINT "readspace_memberships_readspace_id_user_id_key" UNIQUE ("readspace_id", "user_id");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."published_quotes" ADD CONSTRAINT "shared_quotes_public_slug_key" UNIQUE ("public_slug");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."user_devices" ADD CONSTRAINT "user_devices_user_id_device_name_key" UNIQUE ("user_id", "device_name");
EXCEPTION WHEN duplicate_object THEN null; WHEN SQLSTATE '42P07' THEN null; END $$;


-- =============================================================================
-- 4. BÖLÜM: FONKSİYONLAR
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$DECLARE
  v_readspace_id uuid;
  v_invitee_user_id uuid;
  v_role text;
  v_status text;
  v_email text;
  v_jwt_email text;
BEGIN
  BEGIN
    v_jwt_email := (current_setting('request.jwt.claims', true)::jsonb ->> 'email');
  EXCEPTION WHEN OTHERS THEN
    v_jwt_email := NULL;
  END;

  SELECT readspace_id, invitee_user_id, role, status, lower(invitee_email)
    INTO v_readspace_id, v_invitee_user_id, v_role, v_status, v_email
  FROM public.invitations
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation_not_found';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'invitation_not_pending';
  END IF;

  IF (v_invitee_user_id IS NOT NULL AND v_invitee_user_id <> auth.uid()) THEN
    RAISE EXCEPTION 'forbidden_not_invitee';
  END IF;
  IF (v_invitee_user_id IS NULL AND (v_jwt_email IS NULL OR lower(v_email) <> lower(v_jwt_email))) THEN
    RAISE EXCEPTION 'forbidden_not_invitee_email';
  END IF;

  IF v_invitee_user_id IS NULL THEN
    v_invitee_user_id := auth.uid();
  END IF;

  INSERT INTO public.readspace_memberships (readspace_id, user_id, role)
  VALUES (v_readspace_id, v_invitee_user_id, v_role::public.readspace_role)
  ON CONFLICT (readspace_id, user_id) DO NOTHING;

  UPDATE public.invitations
  SET status = 'accepted', accepted_at = now(), invitee_user_id = v_invitee_user_id
  WHERE id = p_invitation_id;
END;$$;
ALTER FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."cleanup_old_quotes"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM quotes 
    WHERE created_at < (NOW() - INTERVAL '7 days')
    AND status IN ('failed', 'unreadable');
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    INSERT INTO cleanup_logs (function_name, deleted_count, executed_at)
    VALUES ('cleanup_old_quotes', deleted_count, NOW())
    ON CONFLICT DO NOTHING;
    
    RETURN deleted_count;
END;
$$;
ALTER FUNCTION "public"."cleanup_old_quotes"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."decline_invitation"("p_invitation_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_status text;
  v_invitee_user_id uuid;
  v_email text;
  v_jwt_email text;
begin
  begin
    v_jwt_email := (current_setting('request.jwt.claims', true)::jsonb ->> 'email');
  exception when others then
    v_jwt_email := null;
  end;

  select status, invitee_user_id, lower(invitee_email)
    into v_status, v_invitee_user_id, v_email
  from public.invitations
  where id = p_invitation_id
  for update;

  if not found then
    raise exception 'invitation_not_found';
  end if;

  if v_status <> 'pending' then
    raise exception 'invitation_not_pending';
  end if;

  if (v_invitee_user_id is not null and v_invitee_user_id <> auth.uid()) then
    raise exception 'forbidden_not_invitee';
  end if;
  if (v_invitee_user_id is null and (v_jwt_email is null or lower(v_email) <> lower(v_jwt_email))) then
    raise exception 'forbidden_not_invitee_email';
  end if;

  update public.invitations
  set status = 'declined', declined_at = now()
  where id = p_invitation_id;
end;
$$;
ALTER FUNCTION "public"."decline_invitation"("p_invitation_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."export_readspace_snapshot"("p_readspace_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_readspace_row readspaces%rowtype;
  v_readspace jsonb;
  v_books jsonb;
  v_orphan_quotes jsonb;
  v_generated_at text := to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_profile record;
  v_application_version text := coalesce(nullif(current_setting('iktibas.app_version', true), ''), 'web-unknown');
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into v_readspace_row
  from readspaces r
  where r.id = p_readspace_id;

  if not found then
    raise exception 'readspace_not_found';
  end if;

  if v_readspace_row.owner_id <> v_user_id then
    if not exists (
      select 1
      from readspace_memberships m
      where m.readspace_id = p_readspace_id
        and m.user_id = v_user_id
    ) then
      raise exception 'forbidden';
    end if;
  end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(b) || jsonb_build_object(
        'quotes', coalesce(
          (
            select jsonb_agg(to_jsonb(q) order by q.created_at, q.id)
            from quotes q
            where q.readspace_id = p_readspace_id
              and q.book_id = b.id
          ),
          '[]'::jsonb
        )
      )
      order by b.created_at, b.id
    ),
    '[]'::jsonb
  )
  into v_books
  from books b
  where b.readspace_id = p_readspace_id;

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.created_at, q.id),
    '[]'::jsonb
  )
  into v_orphan_quotes
  from quotes q
  where q.readspace_id = p_readspace_id
    and q.book_id is null;

  select p.id as user_id, p.email, p.name
  into v_profile
  from profiles p
  where p.id = v_user_id;

  v_readspace := to_jsonb(v_readspace_row)
    || jsonb_build_object(
      'books', v_books,
      'standalone_quotes', v_orphan_quotes
    );

  v_result := jsonb_build_object(
    'version', '1.0.0',
    'generated_at', v_generated_at,
    'generated_by', jsonb_build_object(
      'user_id', v_user_id,
      'email', coalesce(v_profile.email, ''),
      'name', coalesce(v_profile.name, '')
    ),
    'application_version', v_application_version,
    'readspaces', jsonb_build_array(v_readspace)
  );

  return v_result;
end;
$$;
ALTER FUNCTION "public"."export_readspace_snapshot"("p_readspace_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."find_user_id_by_email"("user_email" "text") RETURNS TABLE("user_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT id
    FROM auth.users
    WHERE email = user_email;
END;
$$;
ALTER FUNCTION "public"."find_user_id_by_email"("user_email" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."gemini_rr_next"("total" integer) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v bigint;
begin
  if total is null or total <= 0 then
    return 0;
  end if;
  v := nextval('gemini_rr_seq');
  return (v % total)::int;
end;
$$;
ALTER FUNCTION "public"."gemini_rr_next"("total" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
    user_name text;
    user_email text;
    readspace_id uuid;
begin
  raise log 'handle_new_user triggered for user: %', NEW.id;

  user_email := NEW.email;
  user_name := coalesce(
    NEW.raw_user_meta_data ->> 'name',
    NEW.raw_user_meta_data ->> 'full_name',
    split_part(user_email, '@', 1)
  );

  if user_name is null or trim(user_name) = '' then
    user_name := 'Kullanıcı';
  end if;

  insert into public.profiles (id, name, email, avatar_url, updated_at)
  values (
    NEW.id,
    user_name,
    user_email,
    NEW.raw_user_meta_data ->> 'avatar_url',
    now()
  );

  insert into public.readspaces (name, owner_id, is_personal, description)
  values (user_name, NEW.id, true, 'Kişisel okuma alanı')
  returning id into readspace_id;

  insert into public.readspace_memberships (readspace_id, user_id, role)
  values (readspace_id, NEW.id, 'owner'::public.readspace_role);

  return NEW;

exception when others then
  raise log 'ERROR in handle_new_user for user %: % (SQLSTATE: %)', NEW.id, SQLERRM, SQLSTATE;
  delete from public.readspace_memberships where user_id = NEW.id;
  delete from public.readspaces where owner_id = NEW.id;
  delete from public.profiles where id = NEW.id;
  return NEW;
end;
$$;
ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_version text;
  v_readspaces jsonb;
  v_readspace_json jsonb;
  v_readspace_data jsonb;
  v_readspace_row readspaces%rowtype;
  v_book_json jsonb;
  v_book_data jsonb;
  v_book_row books%rowtype;
  v_quote_json jsonb;
  v_quote_row quotes%rowtype;
  v_books_array jsonb;
  v_quotes_array jsonb;
  v_standalone_array jsonb;
  v_imported integer := 0;
  rec record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_payload';
  end if;

  v_version := coalesce(p_payload->>'version', '');
  if v_version is null or v_version = '' then
    raise exception 'missing_version';
  end if;
  if v_version <> '1.0.0' then
    raise exception 'unsupported_version';
  end if;

  v_readspaces := coalesce(p_payload->'readspaces', '[]'::jsonb);
  if jsonb_typeof(v_readspaces) <> 'array' then
    raise exception 'invalid_readspaces_array';
  end if;

  for rec in
    select value as readspace_value
    from jsonb_array_elements(v_readspaces)
  loop
    v_readspace_json := rec.readspace_value;
    if jsonb_typeof(v_readspace_json) <> 'object' then
      raise exception 'invalid_readspace_item';
    end if;

    if (v_readspace_json->>'id') is null then
      raise exception 'invalid_readspace_id';
    end if;

    v_readspace_data := v_readspace_json - array['books', 'standalone_quotes'];
    v_readspace_row := jsonb_populate_record(null::readspaces, v_readspace_data);
    v_readspace_row.owner_id := v_user_id;

    if v_readspace_row.id is null then
      raise exception 'invalid_readspace_id';
    end if;

    if exists (select 1 from readspaces where id = v_readspace_row.id) then
      raise exception 'readspace_id_conflict';
    end if;

    if v_readspace_row.created_at is null then
      v_readspace_row.created_at := timezone('utc', now());
    end if;
    if v_readspace_row.updated_at is null then
      v_readspace_row.updated_at := timezone('utc', now());
    end if;

    insert into readspaces
    select v_readspace_row.*;

    insert into readspace_memberships (readspace_id, user_id, role, joined_at)
    values (v_readspace_row.id, v_user_id, 'owner', now())
    on conflict (readspace_id, user_id)
    do update set role = excluded.role, joined_at = excluded.joined_at;

    v_books_array := coalesce(v_readspace_json->'books', '[]'::jsonb);
    if jsonb_typeof(v_books_array) <> 'array' then
      raise exception 'invalid_books_array';
    end if;

    for rec in
      select value as book_value
      from jsonb_array_elements(v_books_array)
    loop
      v_book_json := rec.book_value;
      if jsonb_typeof(v_book_json) <> 'object' then
        raise exception 'invalid_book_item';
      end if;

      v_book_data := v_book_json - 'quotes';
      v_book_row := jsonb_populate_record(null::books, v_book_data);
      v_book_row.readspace_id := v_readspace_row.id;

      insert into books
      select v_book_row.*;

      v_quotes_array := coalesce(v_book_json->'quotes', '[]'::jsonb);
      if jsonb_typeof(v_quotes_array) <> 'array' then
        raise exception 'invalid_book_quotes_array';
      end if;

      for rec in
        select value as quote_value
        from jsonb_array_elements(v_quotes_array)
      loop
        v_quote_json := rec.quote_value;
        if jsonb_typeof(v_quote_json) <> 'object' then
          raise exception 'invalid_quote_item';
        end if;

        v_quote_row := jsonb_populate_record(null::quotes, v_quote_json);
        v_quote_row.book_id := v_book_row.id;
        v_quote_row.readspace_id := v_readspace_row.id;

        insert into quotes
        select v_quote_row.*;
      end loop;
    end loop;

    v_standalone_array := coalesce(v_readspace_json->'standalone_quotes', '[]'::jsonb);
    if jsonb_typeof(v_standalone_array) <> 'array' then
      raise exception 'invalid_standalone_quotes_array';
    end if;

    for rec in
      select value as quote_value
      from jsonb_array_elements(v_standalone_array)
    loop
      v_quote_json := rec.quote_value;
      if jsonb_typeof(v_quote_json) <> 'object' then
        raise exception 'invalid_quote_item';
      end if;

      v_quote_row := jsonb_populate_record(null::quotes, v_quote_json);
      if v_quote_row.id is null then
        v_quote_row.id := gen_random_uuid();
      elsif exists (select 1 from quotes where id = v_quote_row.id) then
        v_quote_row.id := gen_random_uuid();
        loop
          exit when not exists(select 1 from quotes where id = v_quote_row.id);
          v_quote_row.id := gen_random_uuid();
        end loop;
      end if;

      v_quote_row.book_id := null;
      v_quote_row.readspace_id := v_readspace_row.id;

      insert into quotes
      select v_quote_row.*;
    end loop;

    v_imported := v_imported + 1;
  end loop;

  return jsonb_build_object('imported_readspaces', v_imported);
end;
$$;
ALTER FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb", "p_readspace_suffix" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$declare
  v_user_id uuid := auth.uid();
  v_version text;
  v_readspaces jsonb;
  v_readspace_json jsonb;
  v_readspace_data jsonb;
  v_readspace_row readspaces%rowtype;
  v_book_json jsonb;
  v_book_data jsonb;
  v_book_row books%rowtype;
  v_quote_json jsonb;
  v_quote_row quotes%rowtype;
  v_books_array jsonb;
  v_quotes_array jsonb;
  v_standalone_array jsonb;
  v_imported integer := 0;
  v_readspace_suffix text := coalesce(nullif(p_readspace_suffix, ''), '-copy');
  v_base_name text;
  v_candidate_name text;
  v_attempt integer;
  v_book_id_map jsonb := '{}';
  rec record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_payload';
  end if;

  v_version := coalesce(p_payload->>'version', '');
  if v_version is null or v_version = '' then
    raise exception 'missing_version';
  end if;
  if v_version <> '1.0.0' then
    raise exception 'unsupported_version';
  end if;

  v_readspaces := coalesce(p_payload->'readspaces', '[]'::jsonb);
  if jsonb_typeof(v_readspaces) <> 'array' then
    raise exception 'invalid_readspaces_array';
  end if;

  for rec in
    select value as readspace_value
    from jsonb_array_elements(v_readspaces)
  loop
    v_readspace_json := rec.readspace_value;
    if jsonb_typeof(v_readspace_json) <> 'object' then
      raise exception 'invalid_readspace_item';
    end if;

    if (v_readspace_json->>'id') is null then
      raise exception 'invalid_readspace_id';
    end if;

    v_readspace_data := v_readspace_json - array['books', 'standalone_quotes'];
    v_readspace_row := jsonb_populate_record(null::readspaces, v_readspace_data);
    v_readspace_row.owner_id := v_user_id;
    v_readspace_row.is_personal := false;
    v_readspace_row.name := coalesce(nullif(v_readspace_row.name, ''), 'Imported Readspace');

    if v_readspace_row.id is null then
      raise exception 'invalid_readspace_id';
    end if;

    if exists (select 1 from readspaces where id = v_readspace_row.id) then
      v_readspace_row.id := gen_random_uuid();
      loop
        exit when not exists(select 1 from readspaces where id = v_readspace_row.id);
        v_readspace_row.id := gen_random_uuid();
      end loop;

      v_base_name := v_readspace_row.name;
      v_candidate_name := trim(both from v_base_name || v_readspace_suffix);
      if v_candidate_name = '' then
        v_candidate_name := 'Imported Readspace' || v_readspace_suffix;
      end if;
      v_attempt := 1;
      while exists (
        select 1
        from readspaces
        where owner_id = v_user_id
          and name = v_candidate_name
      ) loop
        v_attempt := v_attempt + 1;
        v_candidate_name := trim(both from v_base_name || v_readspace_suffix || ' ' || v_attempt::text);
      end loop;
      v_readspace_row.name := v_candidate_name;
    end if;

    if v_readspace_row.created_at is null then
      v_readspace_row.created_at := timezone('utc', now());
    end if;
    if v_readspace_row.updated_at is null then
      v_readspace_row.updated_at := timezone('utc', now());
    end if;

    insert into readspaces
    select v_readspace_row.*;

    insert into readspace_memberships (readspace_id, user_id, role, joined_at)
    values (v_readspace_row.id, v_user_id, 'owner', now())
    on conflict (readspace_id, user_id)
    do update set role = excluded.role, joined_at = excluded.joined_at;

    v_books_array := coalesce(v_readspace_json->'books', '[]'::jsonb);
    if jsonb_typeof(v_books_array) <> 'array' then
      raise exception 'invalid_books_array';
    end if;

    for rec in
      select value as book_value
      from jsonb_array_elements(v_books_array)
    loop
      v_book_json := rec.book_value;
      if jsonb_typeof(v_book_json) <> 'object' then
        raise exception 'invalid_book_item';
      end if;

      v_book_data := v_book_json - 'quotes';
      v_book_row := jsonb_populate_record(null::books, v_book_data);
      if v_book_row.id is null then
        v_book_row.id := gen_random_uuid();
      elsif exists (select 1 from books where id = v_book_row.id) then
        v_book_row.id := gen_random_uuid();
        loop
          exit when not exists(select 1 from books where id = v_book_row.id);
          v_book_row.id := gen_random_uuid();
        end loop;
      end if;
      v_book_id_map := v_book_id_map || jsonb_build_object((v_book_json->>'id'), v_book_row.id::text);
      v_book_row.readspace_id := v_readspace_row.id;

      insert into books
      select v_book_row.*;

      v_quotes_array := coalesce(v_book_json->'quotes', '[]'::jsonb);
      if jsonb_typeof(v_quotes_array) <> 'array' then
        raise exception 'invalid_book_quotes_array';
      end if;

      for rec in
        select value as quote_value
        from jsonb_array_elements(v_quotes_array)
      loop
        v_quote_json := rec.quote_value;
        if jsonb_typeof(v_quote_json) <> 'object' then
          raise exception 'invalid_quote_item';
        end if;

        v_quote_row := jsonb_populate_record(null::quotes, v_quote_json);
        if v_quote_row.id is null then
          v_quote_row.id := gen_random_uuid();
        elsif exists (select 1 from quotes where id = v_quote_row.id) then
          v_quote_row.id := gen_random_uuid();
          loop
            exit when not exists(select 1 from quotes where id = v_quote_row.id);
            v_quote_row.id := gen_random_uuid();
          end loop;
        end if;

        v_quote_row.book_id := v_book_row.id;
        v_quote_row.readspace_id := v_readspace_row.id;

        insert into quotes
        select v_quote_row.*;
      end loop;
    end loop;

    v_standalone_array := coalesce(v_readspace_json->'standalone_quotes', '[]'::jsonb);
    if jsonb_typeof(v_standalone_array) <> 'array' then
      raise exception 'invalid_standalone_quotes_array';
    end if;

    for rec in
      select value as quote_value
      from jsonb_array_elements(v_standalone_array)
    loop
      v_quote_json := rec.quote_value;
      if jsonb_typeof(v_quote_json) <> 'object' then
        raise exception 'invalid_quote_item';
      end if;

      v_quote_row := jsonb_populate_record(null::quotes, v_quote_json);
      if v_quote_row.id is null then
        v_quote_row.id := gen_random_uuid();
      elsif exists (select 1 from quotes where id = v_quote_row.id) then
        v_quote_row.id := gen_random_uuid();
        loop
          exit when not exists(select 1 from quotes where id = v_quote_row.id);
          v_quote_row.id := gen_random_uuid();
        end loop;
      end if;

      v_quote_row.book_id := null;
      v_quote_row.readspace_id := v_readspace_row.id;

      insert into quotes
      select v_quote_row.*;
    end loop;

    v_imported := v_imported + 1;
  end loop;

  return jsonb_build_object('imported_readspaces', v_imported);
end;$$;
ALTER FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb", "p_readspace_suffix" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."increment_view_count"("slug" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$BEGIN
  UPDATE published_quotes 
  SET 
    view_count = view_count + 1,
    last_viewed_at = NOW()
  WHERE public_slug = slug 
  AND is_active = true
  AND (expires_at IS NULL OR expires_at > NOW());
END;$$;
ALTER FUNCTION "public"."increment_view_count"("slug" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."is_published_quote_accessible"("slug" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$BEGIN
  RETURN EXISTS (
    SELECT 1 
    FROM published_quotes 
    WHERE public_slug = slug 
    AND is_active = true
    AND (expires_at IS NULL OR expires_at > NOW())
  );
END;$$;
ALTER FUNCTION "public"."is_published_quote_accessible"("slug" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."update_member_count_on_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE public.readspaces 
  SET member_count = GREATEST(member_count - 1, 0)
  WHERE id = OLD.readspace_id;
  RETURN OLD;
END;
$$;
ALTER FUNCTION "public"."update_member_count_on_delete"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."update_member_count_on_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE public.readspaces 
  SET member_count = member_count + 1
  WHERE id = NEW.readspace_id;
  RETURN NEW;
END;
$$;
ALTER FUNCTION "public"."update_member_count_on_insert"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;
ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


-- =============================================================================
-- 5. BÖLÜM: İNDEKSLER
-- =============================================================================

CREATE INDEX IF NOT EXISTS "idx_app_versions_platform_released_date" ON "public"."app_versions" USING "btree" ("platform", "is_released" DESC, "release_date" DESC);
CREATE INDEX IF NOT EXISTS "idx_book_reading_progress_book_id" ON "public"."book_reading_progress" USING "btree" ("book_id");
CREATE INDEX IF NOT EXISTS "idx_book_reading_progress_status" ON "public"."book_reading_progress" USING "btree" ("reading_status");
CREATE INDEX IF NOT EXISTS "idx_book_reading_progress_user_id" ON "public"."book_reading_progress" USING "btree" ("user_id");
CREATE INDEX IF NOT EXISTS "idx_books_content_type" ON "public"."books" USING "btree" ("content_type") WHERE ("content_type" IS NOT NULL);
CREATE INDEX IF NOT EXISTS "idx_books_sync_data" ON "public"."books" USING "gin" ("sync_data");
CREATE INDEX IF NOT EXISTS "idx_integration_destinations_integration_id" ON "public"."integration_destinations" USING "btree" ("readspace_integration_id");
CREATE INDEX IF NOT EXISTS "idx_invitations_invitee_email_lower" ON "public"."invitations" USING "btree" ("lower"("invitee_email"));
CREATE INDEX IF NOT EXISTS "idx_invitations_invitee_user_id" ON "public"."invitations" USING "btree" ("invitee_user_id");
CREATE INDEX IF NOT EXISTS "idx_invitations_readspace_id_status" ON "public"."invitations" USING "btree" ("readspace_id", "status");
CREATE INDEX IF NOT EXISTS "idx_profiles_subscription_expires" ON "public"."profiles" USING "btree" ("subscription_expires_at") WHERE ("subscription_expires_at" IS NOT NULL);
CREATE INDEX IF NOT EXISTS "idx_quotes_created_at" ON "public"."quotes" USING "btree" ("created_at" DESC);
CREATE INDEX IF NOT EXISTS "idx_quotes_readspace_id" ON "public"."quotes" USING "btree" ("readspace_id");
CREATE INDEX IF NOT EXISTS "idx_quotes_status" ON "public"."quotes" USING "btree" ("status");
CREATE INDEX IF NOT EXISTS "idx_quotes_sync_data" ON "public"."quotes" USING "gin" ("sync_data");
CREATE INDEX IF NOT EXISTS "idx_quotes_user_id" ON "public"."quotes" USING "btree" ("user_id");
CREATE INDEX IF NOT EXISTS "idx_readers_active" ON "public"."readers" USING "btree" ("readspace_id", "book_id") WHERE ("is_active" = true);
CREATE INDEX IF NOT EXISTS "idx_readers_book_id" ON "public"."readers" USING "btree" ("book_id");
CREATE INDEX IF NOT EXISTS "idx_readers_readspace_id" ON "public"."readers" USING "btree" ("readspace_id");
CREATE INDEX IF NOT EXISTS "idx_readers_user_id" ON "public"."readers" USING "btree" ("user_id");
CREATE INDEX IF NOT EXISTS "idx_readspace_integrations_provider_id" ON "public"."readspace_integrations" USING "btree" ("provider_id");
CREATE INDEX IF NOT EXISTS "idx_readspace_integrations_readspace_id" ON "public"."readspace_integrations" USING "btree" ("readspace_id");
CREATE INDEX IF NOT EXISTS "idx_readspace_integrations_status" ON "public"."readspace_integrations" USING "btree" ("status");
CREATE INDEX IF NOT EXISTS "idx_readspace_integrations_user_id" ON "public"."readspace_integrations" USING "btree" ("user_id");
CREATE INDEX IF NOT EXISTS "idx_shared_quotes_active" ON "public"."published_quotes" USING "btree" ("is_active");
CREATE INDEX IF NOT EXISTS "idx_shared_quotes_public_slug" ON "public"."published_quotes" USING "btree" ("public_slug");
CREATE INDEX IF NOT EXISTS "idx_shared_quotes_quote_id" ON "public"."published_quotes" USING "btree" ("quote_id");
CREATE INDEX IF NOT EXISTS "idx_shared_quotes_readspace_id" ON "public"."published_quotes" USING "btree" ("readspace_id");
CREATE INDEX IF NOT EXISTS "idx_sync_logs_integration_id" ON "public"."sync_logs" USING "btree" ("readspace_integration_id");
CREATE INDEX IF NOT EXISTS "idx_sync_logs_status" ON "public"."sync_logs" USING "btree" ("status");
CREATE INDEX IF NOT EXISTS "idx_user_devices_is_active" ON "public"."user_devices" USING "btree" ("is_active");
CREATE INDEX IF NOT EXISTS "idx_user_devices_last_login_at" ON "public"."user_devices" USING "btree" ("last_login_at");
CREATE INDEX IF NOT EXISTS "quotes_user_device_id_idx" ON "public"."quotes" USING "btree" ("user_device_id");
CREATE INDEX IF NOT EXISTS "quotes_user_pending_idx" ON "public"."quotes" USING "btree" ("user_id", "updated_at" DESC) WHERE ("status" = 'pending_selection'::"text");
CREATE INDEX IF NOT EXISTS "quotes_user_space_pending_idx" ON "public"."quotes" USING "btree" ("user_id", "readspace_id", "updated_at" DESC) WHERE ("status" = 'pending_selection'::"text");
CREATE INDEX IF NOT EXISTS "readspaces_active_book_id_idx" ON "public"."readspaces" USING "btree" ("active_book_id");
CREATE UNIQUE INDEX IF NOT EXISTS "uniq_invitations_pending_email" ON "public"."invitations" USING "btree" ("readspace_id", "lower"("invitee_email")) WHERE ("status" = 'pending'::"text");
CREATE INDEX IF NOT EXISTS "user_devices_active_readspace_id_idx" ON "public"."user_devices" USING "btree" ("active_readspace_id");
CREATE INDEX IF NOT EXISTS "user_devices_user_id_idx" ON "public"."user_devices" USING "btree" ("user_id");


-- =============================================================================
-- 6. BÖLÜM: TRIGGERLAR
-- =============================================================================

CREATE OR REPLACE TRIGGER "after_member_delete" AFTER DELETE ON "public"."readspace_memberships" FOR EACH ROW EXECUTE FUNCTION "public"."update_member_count_on_delete"();
CREATE OR REPLACE TRIGGER "after_member_insert" AFTER INSERT ON "public"."readspace_memberships" FOR EACH ROW EXECUTE FUNCTION "public"."update_member_count_on_insert"();
CREATE OR REPLACE TRIGGER "on_updated" BEFORE UPDATE ON "public"."books" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
CREATE OR REPLACE TRIGGER "update_book_reading_progress_updated_at" BEFORE UPDATE ON "public"."book_reading_progress" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
CREATE OR REPLACE TRIGGER "update_integration_destinations_updated_at" BEFORE UPDATE ON "public"."integration_destinations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
CREATE OR REPLACE TRIGGER "update_providers_updated_at" BEFORE UPDATE ON "public"."providers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
CREATE OR REPLACE TRIGGER "update_readers_updated_at" BEFORE UPDATE ON "public"."readers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
CREATE OR REPLACE TRIGGER "update_readspace_integrations_updated_at" BEFORE UPDATE ON "public"."readspace_integrations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();


-- =============================================================================
-- 7. BÖLÜM: RLS (POLICIES)
-- =============================================================================

ALTER TABLE "public"."app_versions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."book_reading_progress" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."books" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."integration_destinations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."invitations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."providers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."published_quotes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."quotes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."readers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."readspace_integrations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."readspaces" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."sync_logs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."user_devices" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active providers" ON "public"."providers";
CREATE POLICY "Anyone can view active providers" ON "public"."providers" FOR SELECT USING (("is_active" = true));

DROP POLICY IF EXISTS "Kullanıcılar kendi profillerini görebilir." ON "public"."profiles";
CREATE POLICY "Kullanıcılar kendi profillerini görebilir." ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Kullanıcılar kendi profillerini güncelleyebilir." ON "public"."profiles";
CREATE POLICY "Kullanıcılar kendi profillerini güncelleyebilir." ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Kullanıcılar kendi profillerini oluşturabilir." ON "public"."profiles";
CREATE POLICY "Kullanıcılar kendi profillerini oluşturabilir." ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Owners can delete their readspaces" ON "public"."readspaces";
CREATE POLICY "Owners can delete their readspaces" ON "public"."readspaces" FOR DELETE USING (("owner_id" = "auth"."uid"()));

DROP POLICY IF EXISTS "Owners can update their readspaces" ON "public"."readspaces";
CREATE POLICY "Owners can update their readspaces" ON "public"."readspaces" FOR UPDATE USING (("owner_id" = "auth"."uid"()));

DROP POLICY IF EXISTS "Owners can view their readspaces" ON "public"."readspaces";
CREATE POLICY "Owners can view their readspaces" ON "public"."readspaces" FOR SELECT USING (("owner_id" = "auth"."uid"()));

DROP POLICY IF EXISTS "Public read released app versions" ON "public"."app_versions";
CREATE POLICY "Public read released app versions" ON "public"."app_versions" FOR SELECT TO "authenticated", "anon" USING (("is_released" = true));

DROP POLICY IF EXISTS "Users can create readspaces" ON "public"."readspaces";
CREATE POLICY "Users can create readspaces" ON "public"."readspaces" FOR INSERT WITH CHECK (("owner_id" = "auth"."uid"()));

DROP POLICY IF EXISTS "Users can delete own devices" ON "public"."user_devices";
CREATE POLICY "Users can delete own devices" ON "public"."user_devices" FOR DELETE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can delete their own reading progress" ON "public"."book_reading_progress";
CREATE POLICY "Users can delete their own reading progress" ON "public"."book_reading_progress" FOR DELETE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can insert own devices" ON "public"."user_devices";
CREATE POLICY "Users can insert own devices" ON "public"."user_devices" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can insert their own reading progress" ON "public"."book_reading_progress";
CREATE POLICY "Users can insert their own reading progress" ON "public"."book_reading_progress" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can insert themselves as readers" ON "public"."readers";
CREATE POLICY "Users can insert themselves as readers" ON "public"."readers" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can update own devices" ON "public"."user_devices";
CREATE POLICY "Users can update own devices" ON "public"."user_devices" FOR UPDATE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can update their own reader status" ON "public"."readers";
CREATE POLICY "Users can update their own reader status" ON "public"."readers" FOR UPDATE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can update their own reading progress" ON "public"."book_reading_progress";
CREATE POLICY "Users can update their own reading progress" ON "public"."book_reading_progress" FOR UPDATE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view own devices" ON "public"."user_devices";
CREATE POLICY "Users can view own devices" ON "public"."user_devices" FOR SELECT USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view own integration destinations" ON "public"."integration_destinations";
CREATE POLICY "Users can view own integration destinations" ON "public"."integration_destinations" USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_integrations"
  WHERE (("readspace_integrations"."id" = "integration_destinations"."readspace_integration_id") AND ("readspace_integrations"."user_id" = "auth"."uid"())))));

DROP POLICY IF EXISTS "Users can view own integrations" ON "public"."readspace_integrations";
CREATE POLICY "Users can view own integrations" ON "public"."readspace_integrations" USING (("user_id" = "auth"."uid"()));

DROP POLICY IF EXISTS "Users can view own sync logs" ON "public"."sync_logs";
CREATE POLICY "Users can view own sync logs" ON "public"."sync_logs" USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_integrations"
  WHERE (("readspace_integrations"."id" = "sync_logs"."readspace_integration_id") AND ("readspace_integrations"."user_id" = "auth"."uid"())))));

DROP POLICY IF EXISTS "Users can view readers in their readspaces" ON "public"."readers";
CREATE POLICY "Users can view readers in their readspaces" ON "public"."readers" FOR SELECT USING (("readspace_id" IN ( SELECT "readspace_memberships"."readspace_id"
   FROM "public"."readspace_memberships"
  WHERE ("readspace_memberships"."user_id" = "auth"."uid"()))));

DROP POLICY IF EXISTS "Users can view readspaces they are members of" ON "public"."readspaces";
CREATE POLICY "Users can view readspaces they are members of" ON "public"."readspaces" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships"
  WHERE (("readspace_memberships"."readspace_id" = "readspaces"."id") AND ("readspace_memberships"."user_id" = "auth"."uid"())))));

DROP POLICY IF EXISTS "Users can view their own reading progress" ON "public"."book_reading_progress";
CREATE POLICY "Users can view their own reading progress" ON "public"."book_reading_progress" FOR SELECT USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "books_delete_for_full_or_owner" ON "public"."books";
CREATE POLICY "books_delete_for_full_or_owner" ON "public"."books" FOR DELETE USING ((("user_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = 'admin'::"public"."readspace_role"))))));

DROP POLICY IF EXISTS "books_delete_policy" ON "public"."books";
CREATE POLICY "books_delete_policy" ON "public"."books" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "books"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));

DROP POLICY IF EXISTS "books_insert_for_members_or_owner" ON "public"."books";
CREATE POLICY "books_insert_for_members_or_owner" ON "public"."books" FOR INSERT WITH CHECK ((("user_id" = "auth"."uid"()) AND ((EXISTS ( SELECT 1
   FROM "public"."readspaces" "r"
  WHERE (("r"."id" = "books"."readspace_id") AND ("r"."owner_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'editor'::"public"."readspace_role"]))))))));

DROP POLICY IF EXISTS "books_insert_policy" ON "public"."books";
CREATE POLICY "books_insert_policy" ON "public"."books" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "books"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))) AND ("user_id" = "auth"."uid"())));

DROP POLICY IF EXISTS "books_select_for_members" ON "public"."books";
CREATE POLICY "books_select_for_members" ON "public"."books" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'editor'::"public"."readspace_role", 'viewer'::"public"."readspace_role"]))))));

DROP POLICY IF EXISTS "books_select_for_published_public" ON "public"."books";
CREATE POLICY "books_select_for_published_public" ON "public"."books" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."published_quotes" "pq"
     JOIN "public"."quotes" "q" ON (("pq"."quote_id" = "q"."id")))
  WHERE (("q"."book_id" = "books"."id") AND ("pq"."is_active" = true)))));

DROP POLICY IF EXISTS "books_select_policy" ON "public"."books";
CREATE POLICY "books_select_policy" ON "public"."books" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "books"."readspace_id") AND ("rm"."user_id" = "auth"."uid"())))));

DROP POLICY IF EXISTS "books_update_for_members_or_owner" ON "public"."books";
CREATE POLICY "books_update_for_members_or_owner" ON "public"."books" FOR UPDATE USING (((EXISTS ( SELECT 1
   FROM "public"."readspaces" "r"
  WHERE (("r"."id" = "books"."readspace_id") AND ("r"."owner_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'editor'::"public"."readspace_role"]))))))) WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."readspaces" "r"
  WHERE (("r"."id" = "books"."readspace_id") AND ("r"."owner_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'editor'::"public"."readspace_role"])))))));

DROP POLICY IF EXISTS "books_update_policy" ON "public"."books";
CREATE POLICY "books_update_policy" ON "public"."books" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "books"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));

DROP POLICY IF EXISTS "invitations_delete_policy" ON "public"."invitations";
CREATE POLICY "invitations_delete_policy" ON "public"."invitations" FOR DELETE USING (("inviter_id" = "auth"."uid"()));

DROP POLICY IF EXISTS "invitations_insert_inviter" ON "public"."invitations";
CREATE POLICY "invitations_insert_inviter" ON "public"."invitations" FOR INSERT WITH CHECK (("inviter_id" = "auth"."uid"()));

DROP POLICY IF EXISTS "invitations_insert_policy" ON "public"."invitations";
CREATE POLICY "invitations_insert_policy" ON "public"."invitations" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "invitations"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = 'owner'::"public"."readspace_role")))) AND ("inviter_id" = "auth"."uid"())));

DROP POLICY IF EXISTS "invitations_select_invitee" ON "public"."invitations";
CREATE POLICY "invitations_select_invitee" ON "public"."invitations" FOR SELECT USING ((("invitee_user_id" = "auth"."uid"()) OR ("lower"("invitee_email") = "lower"(COALESCE((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'email'::"text"), ''::"text")))));

DROP POLICY IF EXISTS "invitations_select_inviter" ON "public"."invitations";
CREATE POLICY "invitations_select_inviter" ON "public"."invitations" FOR SELECT USING (("inviter_id" = "auth"."uid"()));

DROP POLICY IF EXISTS "invitations_select_policy" ON "public"."invitations";
CREATE POLICY "invitations_select_policy" ON "public"."invitations" FOR SELECT USING ((("auth"."uid"() IS NOT NULL) AND (("invitee_user_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "invitations"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = 'owner'::"public"."readspace_role")))))));

DROP POLICY IF EXISTS "invitations_update_policy" ON "public"."invitations";
CREATE POLICY "invitations_update_policy" ON "public"."invitations" FOR UPDATE USING (("invitee_user_id" = "auth"."uid"()));

DROP POLICY IF EXISTS "pq_delete_admin_owner_only" ON "public"."published_quotes";
CREATE POLICY "pq_delete_admin_owner_only" ON "public"."published_quotes" FOR DELETE USING ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "published_quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'owner'::"public"."readspace_role"])))))));

DROP POLICY IF EXISTS "pq_insert_admin_owner_only" ON "public"."published_quotes";
CREATE POLICY "pq_insert_admin_owner_only" ON "public"."published_quotes" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "published_quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'owner'::"public"."readspace_role"])))))));

DROP POLICY IF EXISTS "pq_select_public_active" ON "public"."published_quotes";
CREATE POLICY "pq_select_public_active" ON "public"."published_quotes" FOR SELECT USING (("is_active" = true));

DROP POLICY IF EXISTS "pq_update_admin_owner_only" ON "public"."published_quotes";
CREATE POLICY "pq_update_admin_owner_only" ON "public"."published_quotes" FOR UPDATE USING ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "published_quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'owner'::"public"."readspace_role"]))))))) WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "published_quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'owner'::"public"."readspace_role"])))))));

DROP POLICY IF EXISTS "profiles_select_for_published_quote_owners" ON "public"."profiles";
CREATE POLICY "profiles_select_for_published_quote_owners" ON "public"."profiles" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."published_quotes" "pq"
     JOIN "public"."quotes" "q" ON (("pq"."quote_id" = "q"."id")))
  WHERE (("q"."user_id" = "profiles"."id") AND ("pq"."is_active" = true)))));

DROP POLICY IF EXISTS "profiles_select_same_readspace_for_owner_admin" ON "public"."profiles";
CREATE POLICY "profiles_select_same_readspace_for_owner_admin" ON "public"."profiles" FOR SELECT USING ((("auth"."uid"() = "id") OR (EXISTS ( SELECT 1
   FROM ("public"."readspace_memberships" "rm_me"
     JOIN "public"."readspace_memberships" "rm_other" ON (("rm_me"."readspace_id" = "rm_other"."readspace_id")))
  WHERE (("rm_me"."user_id" = "auth"."uid"()) AND ("rm_me"."role" = ANY (ARRAY['owner'::"public"."readspace_role", 'admin'::"public"."readspace_role"])) AND ("rm_other"."user_id" = "profiles"."id")))) OR (EXISTS ( SELECT 1
   FROM ("public"."readspaces" "r"
     JOIN "public"."readspace_memberships" "rm_other" ON (("r"."id" = "rm_other"."readspace_id")))
  WHERE (("r"."owner_id" = "auth"."uid"()) AND ("rm_other"."user_id" = "profiles"."id"))))));

DROP POLICY IF EXISTS "profiles_select_same_readspace_for_owners" ON "public"."profiles";
CREATE POLICY "profiles_select_same_readspace_for_owners" ON "public"."profiles" FOR SELECT USING ((("auth"."uid"() = "id") OR (EXISTS ( SELECT 1
   FROM ("public"."readspace_memberships" "rm_owner"
     JOIN "public"."readspace_memberships" "rm_user" ON (("rm_owner"."readspace_id" = "rm_user"."readspace_id")))
  WHERE (("rm_owner"."user_id" = "auth"."uid"()) AND ("rm_owner"."role" = 'owner'::"public"."readspace_role") AND ("rm_user"."user_id" = "profiles"."id"))))));

DROP POLICY IF EXISTS "quotes_delete_policy" ON "public"."quotes";
CREATE POLICY "quotes_delete_policy" ON "public"."quotes" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));

DROP POLICY IF EXISTS "quotes_insert_policy" ON "public"."quotes";
CREATE POLICY "quotes_insert_policy" ON "public"."quotes" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))) AND ("user_id" = "auth"."uid"())));

DROP POLICY IF EXISTS "quotes_select_for_published_public" ON "public"."quotes";
CREATE POLICY "quotes_select_for_published_public" ON "public"."quotes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."published_quotes" "pq"
  WHERE (("pq"."quote_id" = "quotes"."id") AND ("pq"."is_active" = true)))));

DROP POLICY IF EXISTS "quotes_select_policy" ON "public"."quotes";
CREATE POLICY "quotes_select_policy" ON "public"."quotes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"())))));

DROP POLICY IF EXISTS "quotes_update_policy" ON "public"."quotes";
CREATE POLICY "quotes_update_policy" ON "public"."quotes" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));


-- =============================================================================
-- 8. BÖLÜM: FOREIGN KEYS
-- =============================================================================

DO $$ BEGIN
    ALTER TABLE ONLY "public"."book_reading_progress"
        ADD CONSTRAINT "book_reading_progress_book_id_fkey" FOREIGN KEY ("book_id") REFERENCES "public"."books"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."book_reading_progress"
        ADD CONSTRAINT "book_reading_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."books"
        ADD CONSTRAINT "books_content_uploaded_by_fkey" FOREIGN KEY ("content_uploaded_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."books"
        ADD CONSTRAINT "books_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."books"
        ADD CONSTRAINT "books_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."published_quotes"
        ADD CONSTRAINT "fk_shared_quotes_quote_id" FOREIGN KEY ("quote_id") REFERENCES "public"."quotes"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."integration_destinations"
        ADD CONSTRAINT "integration_destinations_integration_id_fkey" FOREIGN KEY ("readspace_integration_id") REFERENCES "public"."readspace_integrations"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."invitations"
        ADD CONSTRAINT "invitations_invitee_user_id_fkey" FOREIGN KEY ("invitee_user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."invitations"
        ADD CONSTRAINT "invitations_inviter_id_fkey" FOREIGN KEY ("inviter_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."invitations"
        ADD CONSTRAINT "invitations_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."profiles"
        ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."quotes"
        ADD CONSTRAINT "quotes_book_id_fkey" FOREIGN KEY ("book_id") REFERENCES "public"."books"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."quotes"
        ADD CONSTRAINT "quotes_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."quotes"
        ADD CONSTRAINT "quotes_user_device_id_fkey" FOREIGN KEY ("user_device_id") REFERENCES "public"."user_devices"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."quotes"
        ADD CONSTRAINT "quotes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readers"
        ADD CONSTRAINT "readers_book_id_fkey" FOREIGN KEY ("book_id") REFERENCES "public"."books"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readers"
        ADD CONSTRAINT "readers_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readers"
        ADD CONSTRAINT "readers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspace_integrations"
        ADD CONSTRAINT "readspace_integrations_provider_id_fkey" FOREIGN KEY ("provider_id") REFERENCES "public"."providers"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspace_integrations"
        ADD CONSTRAINT "readspace_integrations_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspace_integrations"
        ADD CONSTRAINT "readspace_integrations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspace_memberships"
        ADD CONSTRAINT "readspace_memberships_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspace_memberships"
        ADD CONSTRAINT "readspace_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspaces"
        ADD CONSTRAINT "readspaces_active_book_id_fkey" FOREIGN KEY ("active_book_id") REFERENCES "public"."books"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."readspaces"
        ADD CONSTRAINT "readspaces_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."published_quotes"
        ADD CONSTRAINT "shared_quotes_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."sync_logs"
        ADD CONSTRAINT "sync_logs_integration_id_fkey" FOREIGN KEY ("readspace_integration_id") REFERENCES "public"."readspace_integrations"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."user_devices"
        ADD CONSTRAINT "user_devices_active_readspace_id_fkey" FOREIGN KEY ("active_readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    ALTER TABLE ONLY "public"."user_devices"
        ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN null; END $$;


-- =============================================================================
-- 9. BÖLÜM: GRANTS
-- =============================================================================

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON ALL TABLES IN SCHEMA "public" TO "postgres";
GRANT ALL ON ALL TABLES IN SCHEMA "public" TO "anon";
GRANT ALL ON ALL TABLES IN SCHEMA "public" TO "authenticated";
GRANT ALL ON ALL TABLES IN SCHEMA "public" TO "service_role";

GRANT ALL ON ALL SEQUENCES IN SCHEMA "public" TO "postgres";
GRANT ALL ON ALL SEQUENCES IN SCHEMA "public" TO "anon";
GRANT ALL ON ALL SEQUENCES IN SCHEMA "public" TO "authenticated";
GRANT ALL ON ALL SEQUENCES IN SCHEMA "public" TO "service_role";

GRANT ALL ON ALL FUNCTIONS IN SCHEMA "public" TO "postgres";
GRANT ALL ON ALL FUNCTIONS IN SCHEMA "public" TO "anon";
GRANT ALL ON ALL FUNCTIONS IN SCHEMA "public" TO "authenticated";
GRANT ALL ON ALL FUNCTIONS IN SCHEMA "public" TO "service_role";

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();