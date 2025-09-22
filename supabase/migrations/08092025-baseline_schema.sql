

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "auth";


ALTER SCHEMA "auth" OWNER TO "supabase_admin";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "storage";


ALTER SCHEMA "storage" OWNER TO "supabase_admin";


CREATE TYPE "auth"."aal_level" AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE "auth"."aal_level" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."code_challenge_method" AS ENUM (
    's256',
    'plain'
);


ALTER TYPE "auth"."code_challenge_method" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_status" AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE "auth"."factor_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_type" AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE "auth"."factor_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."one_time_token_type" AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE "auth"."one_time_token_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "public"."readspace_role" AS ENUM (
    'owner',
    'admin',
    'editor',
    'viewer'
);


ALTER TYPE "public"."readspace_role" OWNER TO "postgres";


CREATE TYPE "storage"."buckettype" AS ENUM (
    'STANDARD',
    'ANALYTICS'
);


ALTER TYPE "storage"."buckettype" OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "auth"."email"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION "auth"."email"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."email"() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';



CREATE OR REPLACE FUNCTION "auth"."jwt"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION "auth"."jwt"() OWNER TO "supabase_auth_admin";


CREATE OR REPLACE FUNCTION "auth"."role"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION "auth"."role"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."role"() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';



CREATE OR REPLACE FUNCTION "auth"."uid"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION "auth"."uid"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."uid"() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';



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
  -- JWT email oku (yoksa null)
  BEGIN
    v_jwt_email := (current_setting('request.jwt.claims', true)::jsonb ->> 'email');
  EXCEPTION WHEN OTHERS THEN
    v_jwt_email := NULL;
  END;

  -- Daveti kilitleyerek al
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

  -- Yetki: user_id eşleşmeli veya email eşleşmeli
  IF (v_invitee_user_id IS NOT NULL AND v_invitee_user_id <> auth.uid()) THEN
    RAISE EXCEPTION 'forbidden_not_invitee';
  END IF;
  IF (v_invitee_user_id IS NULL AND (v_jwt_email IS NULL OR lower(v_email) <> lower(v_jwt_email))) THEN
    RAISE EXCEPTION 'forbidden_not_invitee_email';
  END IF;

  -- user_id boşsa current uid set et
  IF v_invitee_user_id IS NULL THEN
    v_invitee_user_id := auth.uid();
  END IF;

  -- Membership oluştur (rol text -> enum cast)
  INSERT INTO public.readspace_memberships (readspace_id, user_id, role)
  VALUES (v_readspace_id, v_invitee_user_id, v_role::public.readspace_role)
  ON CONFLICT (readspace_id, user_id) DO NOTHING;

  -- Daveti kabul edildi olarak işaretle
  UPDATE public.invitations
  SET status = 'accepted', accepted_at = now(), invitee_user_id = v_invitee_user_id
  WHERE id = p_invitation_id;
END;$$;


ALTER FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") OWNER TO "postgres";


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


COMMENT ON FUNCTION "public"."gemini_rr_next"("total" integer) IS 'Returns the next round-robin index in [0,total) using gemini_rr_seq.';



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

  -- user email
  user_email := NEW.email;

  -- name from metadata or email local-part
  user_name := coalesce(
    NEW.raw_user_meta_data ->> 'name',
    NEW.raw_user_meta_data ->> 'full_name',
    split_part(user_email, '@', 1)
  );

  if user_name is null or trim(user_name) = '' then
    user_name := 'Kullanıcı';
  end if;

  raise log 'Creating profile first for user: % (name: %)', NEW.id, user_name;

  -- 1) profile
  insert into public.profiles (id, name, email, avatar_url, updated_at)
  values (
    NEW.id,
    user_name,
    user_email,
    NEW.raw_user_meta_data ->> 'avatar_url',
    now()
  );

  raise log 'Profile created successfully';

  -- 2) readspace
  insert into public.readspaces (name, owner_id, is_personal, description)
  values (user_name, NEW.id, true, 'Kişisel okuma alanı')
  returning id into readspace_id;

  raise log 'ReadSpace created with id: %', readspace_id;

  -- 3) membership (enum fix: readspace_role)
  insert into public.readspace_memberships (readspace_id, user_id, role)
  values (readspace_id, NEW.id, 'owner'::public.readspace_role);

  raise log 'ReadSpace membership created';

  raise log 'handle_new_user completed successfully for user: %', NEW.id;
  return NEW;

exception when others then
  raise log 'ERROR in handle_new_user for user %: % (SQLSTATE: %)', NEW.id, SQLERRM, SQLSTATE;

  delete from public.readspace_memberships where user_id = NEW.id;
  delete from public.readspaces where owner_id = NEW.id;
  delete from public.profiles where id = NEW.id;
  raise log 'Cleanup completed for user: %', NEW.id;
  return NEW;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "storage"."add_prefixes"("_bucket_id" "text", "_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    prefixes text[];
BEGIN
    prefixes := "storage"."get_prefixes"("_name");

    IF array_length(prefixes, 1) > 0 THEN
        INSERT INTO storage.prefixes (name, bucket_id)
        SELECT UNNEST(prefixes) as name, "_bucket_id" ON CONFLICT DO NOTHING;
    END IF;
END;
$$;


ALTER FUNCTION "storage"."add_prefixes"("_bucket_id" "text", "_name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."delete_prefix"("_bucket_id" "text", "_name" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Check if we can delete the prefix
    IF EXISTS(
        SELECT FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name") + 1
          AND "prefixes"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    )
    OR EXISTS(
        SELECT FROM "storage"."objects"
        WHERE "objects"."bucket_id" = "_bucket_id"
          AND "storage"."get_level"("objects"."name") = "storage"."get_level"("_name") + 1
          AND "objects"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    ) THEN
    -- There are sub-objects, skip deletion
    RETURN false;
    ELSE
        DELETE FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name")
          AND "prefixes"."name" = "_name";
        RETURN true;
    END IF;
END;
$$;


ALTER FUNCTION "storage"."delete_prefix"("_bucket_id" "text", "_name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."delete_prefix_hierarchy_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    prefix text;
BEGIN
    prefix := "storage"."get_prefix"(OLD."name");

    IF coalesce(prefix, '') != '' THEN
        PERFORM "storage"."delete_prefix"(OLD."bucket_id", prefix);
    END IF;

    RETURN OLD;
END;
$$;


ALTER FUNCTION "storage"."delete_prefix_hierarchy_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_bucket_name_length"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION "storage"."enforce_bucket_name_length"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."extension"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION "storage"."extension"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."filename"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


ALTER FUNCTION "storage"."filename"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."foldername"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION "storage"."foldername"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_level"("name" "text") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
SELECT array_length(string_to_array("name", '/'), 1);
$$;


ALTER FUNCTION "storage"."get_level"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_prefix"("name" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $_$
SELECT
    CASE WHEN strpos("name", '/') > 0 THEN
             regexp_replace("name", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$_$;


ALTER FUNCTION "storage"."get_prefix"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_prefixes"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE STRICT
    AS $$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array("name", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$$;


ALTER FUNCTION "storage"."get_prefixes"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_size_by_bucket"() RETURNS TABLE("size" bigint, "bucket_id" "text")
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION "storage"."get_size_by_bucket"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "next_key_token" "text" DEFAULT ''::"text", "next_upload_token" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "id" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "next_key_token" "text", "next_upload_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_objects_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "start_after" "text" DEFAULT ''::"text", "next_token" "text" DEFAULT ''::"text") RETURNS TABLE("name" "text", "id" "uuid", "metadata" "jsonb", "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(name COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                        substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1)))
                    ELSE
                        name
                END AS name, id, metadata, updated_at
            FROM
                storage.objects
            WHERE
                bucket_id = $5 AND
                name ILIKE $1 || ''%'' AND
                CASE
                    WHEN $6 != '''' THEN
                    name COLLATE "C" > $6
                ELSE true END
                AND CASE
                    WHEN $4 != '''' THEN
                        CASE
                            WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                                substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                name COLLATE "C" > $4
                            END
                    ELSE
                        true
                END
            ORDER BY
                name COLLATE "C" ASC) as e order by name COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_token, bucket_id, start_after;
END;
$_$;


ALTER FUNCTION "storage"."list_objects_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "start_after" "text", "next_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."objects_insert_prefix_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    NEW.level := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."objects_insert_prefix_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."objects_update_prefix_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    old_prefixes TEXT[];
BEGIN
    -- Ensure this is an update operation and the name has changed
    IF TG_OP = 'UPDATE' AND (NEW."name" <> OLD."name" OR NEW."bucket_id" <> OLD."bucket_id") THEN
        -- Retrieve old prefixes
        old_prefixes := "storage"."get_prefixes"(OLD."name");

        -- Remove old prefixes that are only used by this object
        WITH all_prefixes as (
            SELECT unnest(old_prefixes) as prefix
        ),
        can_delete_prefixes as (
             SELECT prefix
             FROM all_prefixes
             WHERE NOT EXISTS (
                 SELECT 1 FROM "storage"."objects"
                 WHERE "bucket_id" = OLD."bucket_id"
                   AND "name" <> OLD."name"
                   AND "name" LIKE (prefix || '%')
             )
         )
        DELETE FROM "storage"."prefixes" WHERE name IN (SELECT prefix FROM can_delete_prefixes);

        -- Add new prefixes
        PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    END IF;
    -- Set the new level
    NEW."level" := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."objects_update_prefix_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."operation"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION "storage"."operation"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."prefixes_insert_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."prefixes_insert_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
declare
    can_bypass_rls BOOLEAN;
begin
    SELECT rolbypassrls
    INTO can_bypass_rls
    FROM pg_roles
    WHERE rolname = coalesce(nullif(current_setting('role', true), 'none'), current_user);

    IF can_bypass_rls THEN
        RETURN QUERY SELECT * FROM storage.search_v1_optimised(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    ELSE
        RETURN QUERY SELECT * FROM storage.search_legacy_v1(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    END IF;
end;
$$;


ALTER FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_legacy_v1"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


ALTER FUNCTION "storage"."search_legacy_v1"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v1_optimised"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select (string_to_array(name, ''/''))[level] as name
           from storage.prefixes
             where lower(prefixes.name) like lower($2 || $3) || ''%''
               and bucket_id = $4
               and level = $1
           order by name ' || v_sort_order || '
     )
     (select name,
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[level] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where lower(objects.name) like lower($2 || $3) || ''%''
       and bucket_id = $4
       and level = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


ALTER FUNCTION "storage"."search_v1_optimised"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "start_after" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
BEGIN
    RETURN query EXECUTE
        $sql$
        SELECT * FROM (
            (
                SELECT
                    split_part(name, '/', $4) AS key,
                    name || '/' AS name,
                    NULL::uuid AS id,
                    NULL::timestamptz AS updated_at,
                    NULL::timestamptz AS created_at,
                    NULL::jsonb AS metadata
                FROM storage.prefixes
                WHERE name COLLATE "C" LIKE $1 || '%'
                AND bucket_id = $2
                AND level = $4
                AND name COLLATE "C" > $5
                ORDER BY prefixes.name COLLATE "C" LIMIT $3
            )
            UNION ALL
            (SELECT split_part(name, '/', $4) AS key,
                name,
                id,
                updated_at,
                created_at,
                metadata
            FROM storage.objects
            WHERE name COLLATE "C" LIKE $1 || '%'
                AND bucket_id = $2
                AND level = $4
                AND name COLLATE "C" > $5
            ORDER BY name COLLATE "C" LIMIT $3)
        ) obj
        ORDER BY name COLLATE "C" LIMIT $3;
        $sql$
        USING prefix, bucket_name, limits, levels, start_after;
END;
$_$;


ALTER FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer, "levels" integer, "start_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION "storage"."update_updated_at_column"() OWNER TO "supabase_storage_admin";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "auth"."audit_log_entries" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "payload" json,
    "created_at" timestamp with time zone,
    "ip_address" character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE "auth"."audit_log_entries" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."audit_log_entries" IS 'Auth: Audit trail for user actions.';



CREATE TABLE IF NOT EXISTS "auth"."flow_state" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid",
    "auth_code" "text" NOT NULL,
    "code_challenge_method" "auth"."code_challenge_method" NOT NULL,
    "code_challenge" "text" NOT NULL,
    "provider_type" "text" NOT NULL,
    "provider_access_token" "text",
    "provider_refresh_token" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "authentication_method" "text" NOT NULL,
    "auth_code_issued_at" timestamp with time zone
);


ALTER TABLE "auth"."flow_state" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."flow_state" IS 'stores metadata for pkce logins';



CREATE TABLE IF NOT EXISTS "auth"."identities" (
    "provider_id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "identity_data" "jsonb" NOT NULL,
    "provider" "text" NOT NULL,
    "last_sign_in_at" timestamp with time zone,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "email" "text" GENERATED ALWAYS AS ("lower"(("identity_data" ->> 'email'::"text"))) STORED,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "auth"."identities" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."identities" IS 'Auth: Stores identities associated to a user.';



COMMENT ON COLUMN "auth"."identities"."email" IS 'Auth: Email is a generated column that references the optional email property in the identity_data';



CREATE TABLE IF NOT EXISTS "auth"."instances" (
    "id" "uuid" NOT NULL,
    "uuid" "uuid",
    "raw_base_config" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
);


ALTER TABLE "auth"."instances" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."instances" IS 'Auth: Manages users across multiple sites.';



CREATE TABLE IF NOT EXISTS "auth"."mfa_amr_claims" (
    "session_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "authentication_method" "text" NOT NULL,
    "id" "uuid" NOT NULL
);


ALTER TABLE "auth"."mfa_amr_claims" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_amr_claims" IS 'auth: stores authenticator method reference claims for multi factor authentication';



CREATE TABLE IF NOT EXISTS "auth"."mfa_challenges" (
    "id" "uuid" NOT NULL,
    "factor_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "verified_at" timestamp with time zone,
    "ip_address" "inet" NOT NULL,
    "otp_code" "text",
    "web_authn_session_data" "jsonb"
);


ALTER TABLE "auth"."mfa_challenges" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_challenges" IS 'auth: stores metadata about challenge requests made';



CREATE TABLE IF NOT EXISTS "auth"."mfa_factors" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "friendly_name" "text",
    "factor_type" "auth"."factor_type" NOT NULL,
    "status" "auth"."factor_status" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "secret" "text",
    "phone" "text",
    "last_challenged_at" timestamp with time zone,
    "web_authn_credential" "jsonb",
    "web_authn_aaguid" "uuid"
);


ALTER TABLE "auth"."mfa_factors" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_factors" IS 'auth: stores metadata about factors';



CREATE TABLE IF NOT EXISTS "auth"."one_time_tokens" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token_type" "auth"."one_time_token_type" NOT NULL,
    "token_hash" "text" NOT NULL,
    "relates_to" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "one_time_tokens_token_hash_check" CHECK (("char_length"("token_hash") > 0))
);


ALTER TABLE "auth"."one_time_tokens" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."refresh_tokens" (
    "instance_id" "uuid",
    "id" bigint NOT NULL,
    "token" character varying(255),
    "user_id" character varying(255),
    "revoked" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "parent" character varying(255),
    "session_id" "uuid"
);


ALTER TABLE "auth"."refresh_tokens" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."refresh_tokens" IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';



CREATE SEQUENCE IF NOT EXISTS "auth"."refresh_tokens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNER TO "supabase_auth_admin";


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNED BY "auth"."refresh_tokens"."id";



CREATE TABLE IF NOT EXISTS "auth"."saml_providers" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "entity_id" "text" NOT NULL,
    "metadata_xml" "text" NOT NULL,
    "metadata_url" "text",
    "attribute_mapping" "jsonb",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "name_id_format" "text",
    CONSTRAINT "entity_id not empty" CHECK (("char_length"("entity_id") > 0)),
    CONSTRAINT "metadata_url not empty" CHECK ((("metadata_url" = NULL::"text") OR ("char_length"("metadata_url") > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK (("char_length"("metadata_xml") > 0))
);


ALTER TABLE "auth"."saml_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_providers" IS 'Auth: Manages SAML Identity Provider connections.';



CREATE TABLE IF NOT EXISTS "auth"."saml_relay_states" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "request_id" "text" NOT NULL,
    "for_email" "text",
    "redirect_to" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "flow_state_id" "uuid",
    CONSTRAINT "request_id not empty" CHECK (("char_length"("request_id") > 0))
);


ALTER TABLE "auth"."saml_relay_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_relay_states" IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';



CREATE TABLE IF NOT EXISTS "auth"."schema_migrations" (
    "version" character varying(255) NOT NULL
);


ALTER TABLE "auth"."schema_migrations" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."schema_migrations" IS 'Auth: Manages updates to the auth system.';



CREATE TABLE IF NOT EXISTS "auth"."sessions" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "factor_id" "uuid",
    "aal" "auth"."aal_level",
    "not_after" timestamp with time zone,
    "refreshed_at" timestamp without time zone,
    "user_agent" "text",
    "ip" "inet",
    "tag" "text"
);


ALTER TABLE "auth"."sessions" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sessions" IS 'Auth: Stores session data associated to a user.';



COMMENT ON COLUMN "auth"."sessions"."not_after" IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';



CREATE TABLE IF NOT EXISTS "auth"."sso_domains" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "domain" "text" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK (("char_length"("domain") > 0))
);


ALTER TABLE "auth"."sso_domains" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_domains" IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';



CREATE TABLE IF NOT EXISTS "auth"."sso_providers" (
    "id" "uuid" NOT NULL,
    "resource_id" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    CONSTRAINT "resource_id not empty" CHECK ((("resource_id" = NULL::"text") OR ("char_length"("resource_id") > 0)))
);


ALTER TABLE "auth"."sso_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_providers" IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';



COMMENT ON COLUMN "auth"."sso_providers"."resource_id" IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';



CREATE TABLE IF NOT EXISTS "auth"."users" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "aud" character varying(255),
    "role" character varying(255),
    "email" character varying(255),
    "encrypted_password" character varying(255),
    "email_confirmed_at" timestamp with time zone,
    "invited_at" timestamp with time zone,
    "confirmation_token" character varying(255),
    "confirmation_sent_at" timestamp with time zone,
    "recovery_token" character varying(255),
    "recovery_sent_at" timestamp with time zone,
    "email_change_token_new" character varying(255),
    "email_change" character varying(255),
    "email_change_sent_at" timestamp with time zone,
    "last_sign_in_at" timestamp with time zone,
    "raw_app_meta_data" "jsonb",
    "raw_user_meta_data" "jsonb",
    "is_super_admin" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "phone" "text" DEFAULT NULL::character varying,
    "phone_confirmed_at" timestamp with time zone,
    "phone_change" "text" DEFAULT ''::character varying,
    "phone_change_token" character varying(255) DEFAULT ''::character varying,
    "phone_change_sent_at" timestamp with time zone,
    "confirmed_at" timestamp with time zone GENERATED ALWAYS AS (LEAST("email_confirmed_at", "phone_confirmed_at")) STORED,
    "email_change_token_current" character varying(255) DEFAULT ''::character varying,
    "email_change_confirm_status" smallint DEFAULT 0,
    "banned_until" timestamp with time zone,
    "reauthentication_token" character varying(255) DEFAULT ''::character varying,
    "reauthentication_sent_at" timestamp with time zone,
    "is_sso_user" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "is_anonymous" boolean DEFAULT false NOT NULL,
    CONSTRAINT "users_email_change_confirm_status_check" CHECK ((("email_change_confirm_status" >= 0) AND ("email_change_confirm_status" <= 2)))
);


ALTER TABLE "auth"."users" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."users" IS 'Auth: Stores user login data within a secure schema.';



COMMENT ON COLUMN "auth"."users"."is_sso_user" IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';



CREATE TABLE IF NOT EXISTS "public"."app_versions" (
    "id" bigint NOT NULL,
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


ALTER TABLE "public"."app_versions" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."app_versions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



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
    "page_count" integer
);


ALTER TABLE "public"."books" OWNER TO "postgres";


COMMENT ON TABLE "public"."books" IS 'Kullanıcıların kütüphanesindeki kitaplar.';



CREATE SEQUENCE IF NOT EXISTS "public"."gemini_rr_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."gemini_rr_seq" OWNER TO "postgres";


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
    "email" "text"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."profiles" IS 'Kullanıcıların herkese açık profil verilerini ve kişisel ayarlarını tutar.';



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
    "user_device_id" "uuid"
);


ALTER TABLE "public"."quotes" OWNER TO "postgres";


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
    "active_book_id" "uuid"
);


ALTER TABLE "public"."readspaces" OWNER TO "postgres";


COMMENT ON COLUMN "public"."readspaces"."active_book_id" IS 'ReadSpace içinde aktif olan kitabın ID''si';



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


COMMENT ON TABLE "public"."user_devices" IS 'Kullanıcıların farklı cihazlarının kaydı ve aktif readspace yönetimi';



COMMENT ON COLUMN "public"."user_devices"."last_login_at" IS 'Timestamp of user''s last successful login on this device';



COMMENT ON COLUMN "public"."user_devices"."is_active" IS 'Whether this device is active for the user';



CREATE TABLE IF NOT EXISTS "storage"."buckets" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "public" boolean DEFAULT false,
    "avif_autodetection" boolean DEFAULT false,
    "file_size_limit" bigint,
    "allowed_mime_types" "text"[],
    "owner_id" "text",
    "type" "storage"."buckettype" DEFAULT 'STANDARD'::"storage"."buckettype" NOT NULL
);


ALTER TABLE "storage"."buckets" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."buckets"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."buckets_analytics" (
    "id" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'ANALYTICS'::"storage"."buckettype" NOT NULL,
    "format" "text" DEFAULT 'ICEBERG'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."buckets_analytics" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."migrations" (
    "id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "hash" character varying(40) NOT NULL,
    "executed_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "storage"."migrations" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_id" "text",
    "name" "text",
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb",
    "path_tokens" "text"[] GENERATED ALWAYS AS ("string_to_array"("name", '/'::"text")) STORED,
    "version" "text",
    "owner_id" "text",
    "user_metadata" "jsonb",
    "level" integer
);


ALTER TABLE "storage"."objects" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."objects"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."prefixes" (
    "bucket_id" "text" NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "level" integer GENERATED ALWAYS AS ("storage"."get_level"("name")) STORED NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "storage"."prefixes" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads" (
    "id" "text" NOT NULL,
    "in_progress_size" bigint DEFAULT 0 NOT NULL,
    "upload_signature" "text" NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "version" "text" NOT NULL,
    "owner_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_metadata" "jsonb"
);


ALTER TABLE "storage"."s3_multipart_uploads" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "upload_id" "text" NOT NULL,
    "size" bigint DEFAULT 0 NOT NULL,
    "part_number" integer NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "etag" "text" NOT NULL,
    "owner_id" "text",
    "version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."s3_multipart_uploads_parts" OWNER TO "supabase_storage_admin";


ALTER TABLE ONLY "auth"."refresh_tokens" ALTER COLUMN "id" SET DEFAULT "nextval"('"auth"."refresh_tokens_id_seq"'::"regclass");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "amr_id_pk" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."audit_log_entries"
    ADD CONSTRAINT "audit_log_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."flow_state"
    ADD CONSTRAINT "flow_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_provider_id_provider_unique" UNIQUE ("provider_id", "provider");



ALTER TABLE ONLY "auth"."instances"
    ADD CONSTRAINT "instances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_authentication_method_pkey" UNIQUE ("session_id", "authentication_method");



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_last_challenged_at_key" UNIQUE ("last_challenged_at");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_token_unique" UNIQUE ("token");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_entity_id_key" UNIQUE ("entity_id");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."schema_migrations"
    ADD CONSTRAINT "schema_migrations_pkey" PRIMARY KEY ("version");



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_providers"
    ADD CONSTRAINT "sso_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_versions"
    ADD CONSTRAINT "app_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_versions"
    ADD CONSTRAINT "app_versions_platform_version_build_key" UNIQUE ("platform", "version", "build_number");



ALTER TABLE ONLY "public"."books"
    ADD CONSTRAINT "books_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quotes"
    ADD CONSTRAINT "quotes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."readspace_memberships"
    ADD CONSTRAINT "readspace_memberships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."readspace_memberships"
    ADD CONSTRAINT "readspace_memberships_readspace_id_user_id_key" UNIQUE ("readspace_id", "user_id");



ALTER TABLE ONLY "public"."readspaces"
    ADD CONSTRAINT "readspaces_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."published_quotes"
    ADD CONSTRAINT "shared_quotes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."published_quotes"
    ADD CONSTRAINT "shared_quotes_public_slug_key" UNIQUE ("public_slug");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_user_id_device_name_key" UNIQUE ("user_id", "device_name");



ALTER TABLE ONLY "storage"."buckets_analytics"
    ADD CONSTRAINT "buckets_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets"
    ADD CONSTRAINT "buckets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_name_key" UNIQUE ("name");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."prefixes"
    ADD CONSTRAINT "prefixes_pkey" PRIMARY KEY ("bucket_id", "level", "name");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_pkey" PRIMARY KEY ("id");



CREATE INDEX "audit_logs_instance_id_idx" ON "auth"."audit_log_entries" USING "btree" ("instance_id");



CREATE UNIQUE INDEX "confirmation_token_idx" ON "auth"."users" USING "btree" ("confirmation_token") WHERE (("confirmation_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "email_change_token_current_idx" ON "auth"."users" USING "btree" ("email_change_token_current") WHERE (("email_change_token_current")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "email_change_token_new_idx" ON "auth"."users" USING "btree" ("email_change_token_new") WHERE (("email_change_token_new")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "factor_id_created_at_idx" ON "auth"."mfa_factors" USING "btree" ("user_id", "created_at");



CREATE INDEX "flow_state_created_at_idx" ON "auth"."flow_state" USING "btree" ("created_at" DESC);



CREATE INDEX "identities_email_idx" ON "auth"."identities" USING "btree" ("email" "text_pattern_ops");



COMMENT ON INDEX "auth"."identities_email_idx" IS 'Auth: Ensures indexed queries on the email column';



CREATE INDEX "identities_user_id_idx" ON "auth"."identities" USING "btree" ("user_id");



CREATE INDEX "idx_auth_code" ON "auth"."flow_state" USING "btree" ("auth_code");



CREATE INDEX "idx_user_id_auth_method" ON "auth"."flow_state" USING "btree" ("user_id", "authentication_method");



CREATE INDEX "mfa_challenge_created_at_idx" ON "auth"."mfa_challenges" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "mfa_factors_user_friendly_name_unique" ON "auth"."mfa_factors" USING "btree" ("friendly_name", "user_id") WHERE (TRIM(BOTH FROM "friendly_name") <> ''::"text");



CREATE INDEX "mfa_factors_user_id_idx" ON "auth"."mfa_factors" USING "btree" ("user_id");



CREATE INDEX "one_time_tokens_relates_to_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("relates_to");



CREATE INDEX "one_time_tokens_token_hash_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("token_hash");



CREATE UNIQUE INDEX "one_time_tokens_user_id_token_type_key" ON "auth"."one_time_tokens" USING "btree" ("user_id", "token_type");



CREATE UNIQUE INDEX "reauthentication_token_idx" ON "auth"."users" USING "btree" ("reauthentication_token") WHERE (("reauthentication_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "recovery_token_idx" ON "auth"."users" USING "btree" ("recovery_token") WHERE (("recovery_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "refresh_tokens_instance_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id");



CREATE INDEX "refresh_tokens_instance_id_user_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id", "user_id");



CREATE INDEX "refresh_tokens_parent_idx" ON "auth"."refresh_tokens" USING "btree" ("parent");



CREATE INDEX "refresh_tokens_session_id_revoked_idx" ON "auth"."refresh_tokens" USING "btree" ("session_id", "revoked");



CREATE INDEX "refresh_tokens_updated_at_idx" ON "auth"."refresh_tokens" USING "btree" ("updated_at" DESC);



CREATE INDEX "saml_providers_sso_provider_id_idx" ON "auth"."saml_providers" USING "btree" ("sso_provider_id");



CREATE INDEX "saml_relay_states_created_at_idx" ON "auth"."saml_relay_states" USING "btree" ("created_at" DESC);



CREATE INDEX "saml_relay_states_for_email_idx" ON "auth"."saml_relay_states" USING "btree" ("for_email");



CREATE INDEX "saml_relay_states_sso_provider_id_idx" ON "auth"."saml_relay_states" USING "btree" ("sso_provider_id");



CREATE INDEX "sessions_not_after_idx" ON "auth"."sessions" USING "btree" ("not_after" DESC);



CREATE INDEX "sessions_user_id_idx" ON "auth"."sessions" USING "btree" ("user_id");



CREATE UNIQUE INDEX "sso_domains_domain_idx" ON "auth"."sso_domains" USING "btree" ("lower"("domain"));



CREATE INDEX "sso_domains_sso_provider_id_idx" ON "auth"."sso_domains" USING "btree" ("sso_provider_id");



CREATE UNIQUE INDEX "sso_providers_resource_id_idx" ON "auth"."sso_providers" USING "btree" ("lower"("resource_id"));



CREATE UNIQUE INDEX "unique_phone_factor_per_user" ON "auth"."mfa_factors" USING "btree" ("user_id", "phone");



CREATE INDEX "user_id_created_at_idx" ON "auth"."sessions" USING "btree" ("user_id", "created_at");



CREATE UNIQUE INDEX "users_email_partial_key" ON "auth"."users" USING "btree" ("email") WHERE ("is_sso_user" = false);



COMMENT ON INDEX "auth"."users_email_partial_key" IS 'Auth: A partial unique index that applies only when is_sso_user is false';



CREATE INDEX "users_instance_id_email_idx" ON "auth"."users" USING "btree" ("instance_id", "lower"(("email")::"text"));



CREATE INDEX "users_instance_id_idx" ON "auth"."users" USING "btree" ("instance_id");



CREATE INDEX "users_is_anonymous_idx" ON "auth"."users" USING "btree" ("is_anonymous");



CREATE INDEX "idx_app_versions_platform_released_date" ON "public"."app_versions" USING "btree" ("platform", "is_released" DESC, "release_date" DESC);



CREATE INDEX "idx_invitations_invitee_email_lower" ON "public"."invitations" USING "btree" ("lower"("invitee_email"));



CREATE INDEX "idx_invitations_invitee_user_id" ON "public"."invitations" USING "btree" ("invitee_user_id");



CREATE INDEX "idx_invitations_readspace_id_status" ON "public"."invitations" USING "btree" ("readspace_id", "status");



CREATE INDEX "idx_quotes_created_at" ON "public"."quotes" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_quotes_readspace_id" ON "public"."quotes" USING "btree" ("readspace_id");



CREATE INDEX "idx_quotes_status" ON "public"."quotes" USING "btree" ("status");



CREATE INDEX "idx_quotes_user_id" ON "public"."quotes" USING "btree" ("user_id");



CREATE INDEX "idx_shared_quotes_active" ON "public"."published_quotes" USING "btree" ("is_active");



CREATE INDEX "idx_shared_quotes_public_slug" ON "public"."published_quotes" USING "btree" ("public_slug");



CREATE INDEX "idx_shared_quotes_quote_id" ON "public"."published_quotes" USING "btree" ("quote_id");



CREATE INDEX "idx_shared_quotes_readspace_id" ON "public"."published_quotes" USING "btree" ("readspace_id");



CREATE INDEX "idx_user_devices_is_active" ON "public"."user_devices" USING "btree" ("is_active");



CREATE INDEX "idx_user_devices_last_login_at" ON "public"."user_devices" USING "btree" ("last_login_at");



CREATE INDEX "quotes_user_device_id_idx" ON "public"."quotes" USING "btree" ("user_device_id");



CREATE INDEX "quotes_user_pending_idx" ON "public"."quotes" USING "btree" ("user_id", "updated_at" DESC) WHERE ("status" = 'pending_selection'::"text");



CREATE INDEX "quotes_user_space_pending_idx" ON "public"."quotes" USING "btree" ("user_id", "readspace_id", "updated_at" DESC) WHERE ("status" = 'pending_selection'::"text");



CREATE INDEX "readspaces_active_book_id_idx" ON "public"."readspaces" USING "btree" ("active_book_id");



CREATE UNIQUE INDEX "uniq_invitations_pending_email" ON "public"."invitations" USING "btree" ("readspace_id", "lower"("invitee_email")) WHERE ("status" = 'pending'::"text");



CREATE INDEX "user_devices_active_readspace_id_idx" ON "public"."user_devices" USING "btree" ("active_readspace_id");



CREATE INDEX "user_devices_user_id_idx" ON "public"."user_devices" USING "btree" ("user_id");



CREATE UNIQUE INDEX "bname" ON "storage"."buckets" USING "btree" ("name");



CREATE UNIQUE INDEX "bucketid_objname" ON "storage"."objects" USING "btree" ("bucket_id", "name");



CREATE INDEX "idx_multipart_uploads_list" ON "storage"."s3_multipart_uploads" USING "btree" ("bucket_id", "key", "created_at");



CREATE UNIQUE INDEX "idx_name_bucket_level_unique" ON "storage"."objects" USING "btree" ("name" COLLATE "C", "bucket_id", "level");



CREATE INDEX "idx_objects_bucket_id_name" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C");



CREATE INDEX "idx_objects_lower_name" ON "storage"."objects" USING "btree" (("path_tokens"["level"]), "lower"("name") "text_pattern_ops", "bucket_id", "level");



CREATE INDEX "idx_prefixes_lower_name" ON "storage"."prefixes" USING "btree" ("bucket_id", "level", (("string_to_array"("name", '/'::"text"))["level"]), "lower"("name") "text_pattern_ops");



CREATE INDEX "name_prefix_search" ON "storage"."objects" USING "btree" ("name" "text_pattern_ops");



CREATE UNIQUE INDEX "objects_bucket_id_level_idx" ON "storage"."objects" USING "btree" ("bucket_id", "level", "name" COLLATE "C");



CREATE OR REPLACE TRIGGER "on_auth_user_created" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_user"();



CREATE OR REPLACE TRIGGER "on_updated" BEFORE UPDATE ON "public"."books" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "enforce_bucket_name_length_trigger" BEFORE INSERT OR UPDATE OF "name" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_bucket_name_length"();



CREATE OR REPLACE TRIGGER "objects_delete_delete_prefix" AFTER DELETE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."delete_prefix_hierarchy_trigger"();



CREATE OR REPLACE TRIGGER "objects_insert_create_prefix" BEFORE INSERT ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."objects_insert_prefix_trigger"();



CREATE OR REPLACE TRIGGER "objects_update_create_prefix" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW WHEN ((("new"."name" <> "old"."name") OR ("new"."bucket_id" <> "old"."bucket_id"))) EXECUTE FUNCTION "storage"."objects_update_prefix_trigger"();



CREATE OR REPLACE TRIGGER "prefixes_create_hierarchy" BEFORE INSERT ON "storage"."prefixes" FOR EACH ROW WHEN (("pg_trigger_depth"() < 1)) EXECUTE FUNCTION "storage"."prefixes_insert_trigger"();



CREATE OR REPLACE TRIGGER "prefixes_delete_hierarchy" AFTER DELETE ON "storage"."prefixes" FOR EACH ROW EXECUTE FUNCTION "storage"."delete_prefix_hierarchy_trigger"();



CREATE OR REPLACE TRIGGER "update_objects_updated_at" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."update_updated_at_column"();



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_auth_factor_id_fkey" FOREIGN KEY ("factor_id") REFERENCES "auth"."mfa_factors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_flow_state_id_fkey" FOREIGN KEY ("flow_state_id") REFERENCES "auth"."flow_state"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."books"
    ADD CONSTRAINT "books_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."books"
    ADD CONSTRAINT "books_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."published_quotes"
    ADD CONSTRAINT "fk_shared_quotes_quote_id" FOREIGN KEY ("quote_id") REFERENCES "public"."quotes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_invitee_user_id_fkey" FOREIGN KEY ("invitee_user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_inviter_id_fkey" FOREIGN KEY ("inviter_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quotes"
    ADD CONSTRAINT "quotes_book_id_fkey" FOREIGN KEY ("book_id") REFERENCES "public"."books"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."quotes"
    ADD CONSTRAINT "quotes_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quotes"
    ADD CONSTRAINT "quotes_user_device_id_fkey" FOREIGN KEY ("user_device_id") REFERENCES "public"."user_devices"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."quotes"
    ADD CONSTRAINT "quotes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."readspace_memberships"
    ADD CONSTRAINT "readspace_memberships_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."readspace_memberships"
    ADD CONSTRAINT "readspace_memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."readspaces"
    ADD CONSTRAINT "readspaces_active_book_id_fkey" FOREIGN KEY ("active_book_id") REFERENCES "public"."books"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."readspaces"
    ADD CONSTRAINT "readspaces_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."published_quotes"
    ADD CONSTRAINT "shared_quotes_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_active_readspace_id_fkey" FOREIGN KEY ("active_readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."prefixes"
    ADD CONSTRAINT "prefixes_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_upload_id_fkey" FOREIGN KEY ("upload_id") REFERENCES "storage"."s3_multipart_uploads"("id") ON DELETE CASCADE;



ALTER TABLE "auth"."audit_log_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."flow_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."identities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."instances" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_amr_claims" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_challenges" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_factors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."one_time_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."refresh_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_relay_states" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."schema_migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_domains" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Kullanıcılar kendi profillerini görebilir." ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Kullanıcılar kendi profillerini güncelleyebilir." ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Kullanıcılar kendi profillerini oluşturabilir." ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Owners can delete their readspaces" ON "public"."readspaces" FOR DELETE USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "Owners can update their readspaces" ON "public"."readspaces" FOR UPDATE USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "Owners can view their readspaces" ON "public"."readspaces" FOR SELECT USING (("owner_id" = "auth"."uid"()));



CREATE POLICY "Public read released app versions" ON "public"."app_versions" FOR SELECT TO "authenticated", "anon" USING (("is_released" = true));



CREATE POLICY "Users can create readspaces" ON "public"."readspaces" FOR INSERT WITH CHECK (("owner_id" = "auth"."uid"()));



CREATE POLICY "Users can delete own devices" ON "public"."user_devices" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert own devices" ON "public"."user_devices" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own devices" ON "public"."user_devices" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own devices" ON "public"."user_devices" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view readspaces they are members of" ON "public"."readspaces" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships"
  WHERE (("readspace_memberships"."readspace_id" = "readspaces"."id") AND ("readspace_memberships"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."app_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."books" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "books_delete_for_full_or_owner" ON "public"."books" FOR DELETE USING ((("user_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = 'admin'::"public"."readspace_role"))))));



CREATE POLICY "books_delete_policy" ON "public"."books" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "books"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));



CREATE POLICY "books_insert_for_members_or_owner" ON "public"."books" FOR INSERT WITH CHECK ((("user_id" = "auth"."uid"()) AND ((EXISTS ( SELECT 1
   FROM "public"."readspaces" "r"
  WHERE (("r"."id" = "books"."readspace_id") AND ("r"."owner_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'editor'::"public"."readspace_role"]))))))));



CREATE POLICY "books_insert_policy" ON "public"."books" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "books"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))) AND ("user_id" = "auth"."uid"())));



CREATE POLICY "books_select_for_members" ON "public"."books" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'editor'::"public"."readspace_role", 'viewer'::"public"."readspace_role"]))))));



CREATE POLICY "books_select_policy" ON "public"."books" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "books"."readspace_id") AND ("rm"."user_id" = "auth"."uid"())))));



CREATE POLICY "books_update_for_members_or_owner" ON "public"."books" FOR UPDATE USING (((EXISTS ( SELECT 1
   FROM "public"."readspaces" "r"
  WHERE (("r"."id" = "books"."readspace_id") AND ("r"."owner_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'editor'::"public"."readspace_role"]))))))) WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."readspaces" "r"
  WHERE (("r"."id" = "books"."readspace_id") AND ("r"."owner_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "m"
  WHERE (("m"."readspace_id" = "books"."readspace_id") AND ("m"."user_id" = "auth"."uid"()) AND ("m"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'editor'::"public"."readspace_role"])))))));



CREATE POLICY "books_update_policy" ON "public"."books" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "books"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));



ALTER TABLE "public"."invitations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invitations_delete_policy" ON "public"."invitations" FOR DELETE USING (("inviter_id" = "auth"."uid"()));



CREATE POLICY "invitations_insert_inviter" ON "public"."invitations" FOR INSERT WITH CHECK (("inviter_id" = "auth"."uid"()));



CREATE POLICY "invitations_insert_policy" ON "public"."invitations" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "invitations"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = 'owner'::"public"."readspace_role")))) AND ("inviter_id" = "auth"."uid"())));



CREATE POLICY "invitations_select_invitee" ON "public"."invitations" FOR SELECT USING ((("invitee_user_id" = "auth"."uid"()) OR ("lower"("invitee_email") = "lower"(COALESCE((("current_setting"('request.jwt.claims'::"text", true))::"jsonb" ->> 'email'::"text"), ''::"text")))));



CREATE POLICY "invitations_select_inviter" ON "public"."invitations" FOR SELECT USING (("inviter_id" = "auth"."uid"()));



CREATE POLICY "invitations_select_policy" ON "public"."invitations" FOR SELECT USING ((("auth"."uid"() IS NOT NULL) AND (("invitee_user_id" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "invitations"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = 'owner'::"public"."readspace_role")))))));



CREATE POLICY "invitations_update_policy" ON "public"."invitations" FOR UPDATE USING (("invitee_user_id" = "auth"."uid"()));



CREATE POLICY "pq_delete_admin_owner_only" ON "public"."published_quotes" FOR DELETE USING ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "published_quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'owner'::"public"."readspace_role"])))))));



CREATE POLICY "pq_insert_admin_owner_only" ON "public"."published_quotes" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "published_quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'owner'::"public"."readspace_role"])))))));



CREATE POLICY "pq_select_public_active" ON "public"."published_quotes" FOR SELECT USING (("is_active" = true));



CREATE POLICY "pq_update_admin_owner_only" ON "public"."published_quotes" FOR UPDATE USING ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "published_quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'owner'::"public"."readspace_role"]))))))) WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "published_quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" = ANY (ARRAY['admin'::"public"."readspace_role", 'owner'::"public"."readspace_role"])))))));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_same_readspace_for_owner_admin" ON "public"."profiles" FOR SELECT USING ((("auth"."uid"() = "id") OR (EXISTS ( SELECT 1
   FROM ("public"."readspace_memberships" "rm_me"
     JOIN "public"."readspace_memberships" "rm_other" ON (("rm_me"."readspace_id" = "rm_other"."readspace_id")))
  WHERE (("rm_me"."user_id" = "auth"."uid"()) AND ("rm_me"."role" = ANY (ARRAY['owner'::"public"."readspace_role", 'admin'::"public"."readspace_role"])) AND ("rm_other"."user_id" = "profiles"."id")))) OR (EXISTS ( SELECT 1
   FROM ("public"."readspaces" "r"
     JOIN "public"."readspace_memberships" "rm_other" ON (("r"."id" = "rm_other"."readspace_id")))
  WHERE (("r"."owner_id" = "auth"."uid"()) AND ("rm_other"."user_id" = "profiles"."id"))))));



CREATE POLICY "profiles_select_same_readspace_for_owners" ON "public"."profiles" FOR SELECT USING ((("auth"."uid"() = "id") OR (EXISTS ( SELECT 1
   FROM ("public"."readspace_memberships" "rm_owner"
     JOIN "public"."readspace_memberships" "rm_user" ON (("rm_owner"."readspace_id" = "rm_user"."readspace_id")))
  WHERE (("rm_owner"."user_id" = "auth"."uid"()) AND ("rm_owner"."role" = 'owner'::"public"."readspace_role") AND ("rm_user"."user_id" = "profiles"."id"))))));



ALTER TABLE "public"."published_quotes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."quotes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "quotes_delete_policy" ON "public"."quotes" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));



CREATE POLICY "quotes_insert_policy" ON "public"."quotes" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))) AND ("user_id" = "auth"."uid"())));



CREATE POLICY "quotes_select_policy" ON "public"."quotes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"())))));



CREATE POLICY "quotes_update_policy" ON "public"."quotes" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));



ALTER TABLE "public"."readspaces" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Service role can list all buckets" ON "storage"."buckets" FOR SELECT TO "authenticated", "service_role" USING (true);



CREATE POLICY "book covers access everything 179dn28_0" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'book-covers'::"text"));



CREATE POLICY "book covers access everything 179dn28_1" ON "storage"."objects" FOR INSERT WITH CHECK (("bucket_id" = 'book-covers'::"text"));



CREATE POLICY "book covers access everything 179dn28_2" ON "storage"."objects" FOR UPDATE USING (("bucket_id" = 'book-covers'::"text"));



CREATE POLICY "book covers access everything 179dn28_3" ON "storage"."objects" FOR DELETE USING (("bucket_id" = 'book-covers'::"text"));



ALTER TABLE "storage"."buckets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."objects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "operate all" ON "storage"."objects" USING (true);



ALTER TABLE "storage"."prefixes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads_parts" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "auth" TO "anon";
GRANT USAGE ON SCHEMA "auth" TO "authenticated";
GRANT USAGE ON SCHEMA "auth" TO "service_role";
GRANT ALL ON SCHEMA "auth" TO "supabase_auth_admin";
GRANT ALL ON SCHEMA "auth" TO "dashboard_user";
GRANT USAGE ON SCHEMA "auth" TO "postgres";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "storage" TO "postgres" WITH GRANT OPTION;
GRANT USAGE ON SCHEMA "storage" TO "anon";
GRANT USAGE ON SCHEMA "storage" TO "authenticated";
GRANT USAGE ON SCHEMA "storage" TO "service_role";
GRANT ALL ON SCHEMA "storage" TO "supabase_storage_admin";
GRANT ALL ON SCHEMA "storage" TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."email"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."jwt"() TO "postgres";
GRANT ALL ON FUNCTION "auth"."jwt"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."role"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."uid"() TO "dashboard_user";



GRANT ALL ON FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."decline_invitation"("p_invitation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."decline_invitation"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decline_invitation"("p_invitation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."find_user_id_by_email"("user_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."find_user_id_by_email"("user_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_user_id_by_email"("user_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."gemini_rr_next"("total" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."gemini_rr_next"("total" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gemini_rr_next"("total" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_view_count"("slug" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_view_count"("slug" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_view_count"("slug" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_published_quote_accessible"("slug" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_published_quote_accessible"("slug" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_published_quote_accessible"("slug" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON TABLE "auth"."audit_log_entries" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."audit_log_entries" TO "postgres";
GRANT SELECT ON TABLE "auth"."audit_log_entries" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."flow_state" TO "postgres";
GRANT SELECT ON TABLE "auth"."flow_state" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."flow_state" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."identities" TO "postgres";
GRANT SELECT ON TABLE "auth"."identities" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."identities" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."instances" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."instances" TO "postgres";
GRANT SELECT ON TABLE "auth"."instances" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_amr_claims" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_amr_claims" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_amr_claims" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_challenges" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_challenges" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_challenges" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_factors" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_factors" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_factors" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."one_time_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."one_time_tokens" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."one_time_tokens" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."refresh_tokens" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."refresh_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."refresh_tokens" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "dashboard_user";
GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "postgres";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_relay_states" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_relay_states" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_relay_states" TO "dashboard_user";



GRANT SELECT ON TABLE "auth"."schema_migrations" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sessions" TO "postgres";
GRANT SELECT ON TABLE "auth"."sessions" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sessions" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_domains" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_domains" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_domains" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_providers" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."users" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."users" TO "postgres";
GRANT SELECT ON TABLE "auth"."users" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "public"."app_versions" TO "anon";
GRANT ALL ON TABLE "public"."app_versions" TO "authenticated";
GRANT ALL ON TABLE "public"."app_versions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."app_versions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."app_versions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."app_versions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."books" TO "anon";
GRANT ALL ON TABLE "public"."books" TO "authenticated";
GRANT ALL ON TABLE "public"."books" TO "service_role";



GRANT ALL ON SEQUENCE "public"."gemini_rr_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."gemini_rr_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."gemini_rr_seq" TO "service_role";



GRANT ALL ON TABLE "public"."invitations" TO "anon";
GRANT ALL ON TABLE "public"."invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."invitations" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."published_quotes" TO "anon";
GRANT ALL ON TABLE "public"."published_quotes" TO "authenticated";
GRANT ALL ON TABLE "public"."published_quotes" TO "service_role";



GRANT ALL ON TABLE "public"."quotes" TO "anon";
GRANT ALL ON TABLE "public"."quotes" TO "authenticated";
GRANT ALL ON TABLE "public"."quotes" TO "service_role";



GRANT ALL ON TABLE "public"."readspace_memberships" TO "anon";
GRANT ALL ON TABLE "public"."readspace_memberships" TO "authenticated";
GRANT ALL ON TABLE "public"."readspace_memberships" TO "service_role";



GRANT ALL ON TABLE "public"."readspaces" TO "anon";
GRANT ALL ON TABLE "public"."readspaces" TO "authenticated";
GRANT ALL ON TABLE "public"."readspaces" TO "service_role";



GRANT ALL ON TABLE "public"."user_devices" TO "anon";
GRANT ALL ON TABLE "public"."user_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."user_devices" TO "service_role";



GRANT ALL ON TABLE "storage"."buckets" TO "anon";
GRANT ALL ON TABLE "storage"."buckets" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."buckets_analytics" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "anon";



GRANT ALL ON TABLE "storage"."objects" TO "anon";
GRANT ALL ON TABLE "storage"."objects" TO "authenticated";
GRANT ALL ON TABLE "storage"."objects" TO "service_role";
GRANT ALL ON TABLE "storage"."objects" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."prefixes" TO "service_role";
GRANT ALL ON TABLE "storage"."prefixes" TO "authenticated";
GRANT ALL ON TABLE "storage"."prefixes" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads_parts" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "anon";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "service_role";



RESET ALL;
