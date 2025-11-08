

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


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."auth_type" AS ENUM (
    'api_key',
    'oauth2',
    'bearer_token'
);


ALTER TYPE "public"."auth_type" OWNER TO "supabase_admin";


CREATE TYPE "public"."connection_status" AS ENUM (
    'active',
    'inactive',
    'error'
);


ALTER TYPE "public"."connection_status" OWNER TO "supabase_admin";


CREATE TYPE "public"."readspace_role" AS ENUM (
    'owner',
    'admin',
    'editor',
    'viewer'
);


ALTER TYPE "public"."readspace_role" OWNER TO "supabase_admin";


CREATE TYPE "public"."sync_direction" AS ENUM (
    'to_provider_only',
    'from_provider_only',
    'bidirectional'
);


ALTER TYPE "public"."sync_direction" OWNER TO "supabase_admin";


CREATE TYPE "public"."sync_frequency" AS ENUM (
    'manual',
    'hourly',
    'daily',
    'weekly'
);


ALTER TYPE "public"."sync_frequency" OWNER TO "supabase_admin";


CREATE TYPE "public"."sync_status" AS ENUM (
    'pending',
    'synced',
    'error'
);


ALTER TYPE "public"."sync_status" OWNER TO "supabase_admin";


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


ALTER FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") OWNER TO "supabase_admin";


CREATE OR REPLACE FUNCTION "public"."cleanup_old_quotes"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- 7 günden eski ve status'u failed veya unreadable olan kayıtları sil
    DELETE FROM quotes 
    WHERE created_at < (NOW() - INTERVAL '7 days')
    AND status IN ('failed', 'unreadable');
    
    -- Silinen kayıt sayısını al
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    -- Log için bilgi kaydet (opsiyonel)
    INSERT INTO cleanup_logs (function_name, deleted_count, executed_at)
    VALUES ('cleanup_old_quotes', deleted_count, NOW())
    ON CONFLICT DO NOTHING; -- Eğer cleanup_logs tablosu yoksa hata vermez
    
    RETURN deleted_count;
END;
$$;


ALTER FUNCTION "public"."cleanup_old_quotes"() OWNER TO "supabase_admin";


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


ALTER FUNCTION "public"."decline_invitation"("p_invitation_id" "uuid") OWNER TO "supabase_admin";


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


ALTER FUNCTION "public"."export_readspace_snapshot"("p_readspace_id" "uuid") OWNER TO "supabase_admin";


COMMENT ON FUNCTION "public"."export_readspace_snapshot"("p_readspace_id" "uuid") IS 'Returns a JSON snapshot of a readspace with books and quotes for export.';



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


ALTER FUNCTION "public"."find_user_id_by_email"("user_email" "text") OWNER TO "supabase_admin";


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


ALTER FUNCTION "public"."gemini_rr_next"("total" integer) OWNER TO "supabase_admin";


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


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "supabase_admin";


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


ALTER FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb") OWNER TO "supabase_admin";


COMMENT ON FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb") IS 'Imports a JSON snapshot by creating readspaces, books, quotes, and assigning ownership to the caller.';



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


ALTER FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb", "p_readspace_suffix" "text") OWNER TO "supabase_admin";


COMMENT ON FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb", "p_readspace_suffix" "text") IS 'Imports a JSON snapshot by creating readspaces, books, quotes, assigning ownership to the caller, and optionally applying a name suffix for duplicates.';



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


ALTER FUNCTION "public"."increment_view_count"("slug" "text") OWNER TO "supabase_admin";


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


ALTER FUNCTION "public"."is_published_quote_accessible"("slug" "text") OWNER TO "supabase_admin";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "supabase_admin";

SET default_tablespace = '';

SET default_table_access_method = "heap";


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


ALTER TABLE "public"."app_versions" OWNER TO "supabase_admin";


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
    "page_count" integer,
    "sync_data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."books" OWNER TO "supabase_admin";


COMMENT ON TABLE "public"."books" IS 'Kullanıcıların kütüphanesindeki kitaplar.';



COMMENT ON COLUMN "public"."books"."sync_data" IS 'Provider-specific sync metadata and status';



CREATE TABLE IF NOT EXISTS "public"."cleanup_logs" (
    "id" integer NOT NULL,
    "function_name" character varying(50) NOT NULL,
    "deleted_count" integer DEFAULT 0 NOT NULL,
    "executed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."cleanup_logs" OWNER TO "supabase_admin";


CREATE SEQUENCE IF NOT EXISTS "public"."cleanup_logs_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."cleanup_logs_id_seq" OWNER TO "supabase_admin";


ALTER SEQUENCE "public"."cleanup_logs_id_seq" OWNED BY "public"."cleanup_logs"."id";



CREATE SEQUENCE IF NOT EXISTS "public"."gemini_rr_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."gemini_rr_seq" OWNER TO "supabase_admin";


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


ALTER TABLE "public"."integration_destinations" OWNER TO "supabase_admin";


COMMENT ON TABLE "public"."integration_destinations" IS 'Target destinations within external providers (pages, databases, etc.)';



CREATE TABLE IF NOT EXISTS "public"."invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "readspace_id" "uuid" NOT NULL,
    "inviter_id" "uuid" NOT NULL,
    "invitee_email" "text" NOT NULL,
    "invitee_user_id" "uuid",
    "role" "public"."readspace_role" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "token" "text" NOT NULL,
    "message" "text",
    "expires_at" timestamp with time zone,
    "accepted_at" timestamp with time zone,
    "declined_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "invitations_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'declined'::"text", 'expired'::"text", 'canceled'::"text"])))
);


ALTER TABLE "public"."invitations" OWNER TO "supabase_admin";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "name" "text",
    "avatar_url" "text",
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "email" "text"
);


ALTER TABLE "public"."profiles" OWNER TO "supabase_admin";


COMMENT ON TABLE "public"."profiles" IS 'Kullanıcıların herkese açık profil verilerini ve kişisel ayarlarını tutar.';



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


ALTER TABLE "public"."providers" OWNER TO "supabase_admin";


COMMENT ON TABLE "public"."providers" IS 'External integration providers (Notion, Google Docs, etc.)';



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


ALTER TABLE "public"."published_quotes" OWNER TO "supabase_admin";


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
    "sync_data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."quotes" OWNER TO "supabase_admin";


COMMENT ON COLUMN "public"."quotes"."sync_data" IS 'Provider-specific sync metadata and status';



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


ALTER TABLE "public"."readspace_integrations" OWNER TO "supabase_admin";


COMMENT ON TABLE "public"."readspace_integrations" IS 'User integrations with external providers for specific readspaces';



CREATE TABLE IF NOT EXISTS "public"."readspace_memberships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "readspace_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."readspace_role" DEFAULT 'admin'::"public"."readspace_role" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."readspace_memberships" OWNER TO "supabase_admin";


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


ALTER TABLE "public"."readspaces" OWNER TO "supabase_admin";


COMMENT ON COLUMN "public"."readspaces"."active_book_id" IS 'ReadSpace içinde aktif olan kitabın ID''si';



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


ALTER TABLE "public"."sync_logs" OWNER TO "supabase_admin";


COMMENT ON TABLE "public"."sync_logs" IS 'Sync operation history and status tracking';



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


ALTER TABLE "public"."user_devices" OWNER TO "supabase_admin";


COMMENT ON TABLE "public"."user_devices" IS 'Kullanıcıların farklı cihazlarının kaydı ve aktif readspace yönetimi';



COMMENT ON COLUMN "public"."user_devices"."last_login_at" IS 'Timestamp of user''s last successful login on this device';



COMMENT ON COLUMN "public"."user_devices"."is_active" IS 'Whether this device is active for the user';



ALTER TABLE ONLY "public"."cleanup_logs" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."cleanup_logs_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."app_versions"
    ADD CONSTRAINT "app_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_versions"
    ADD CONSTRAINT "app_versions_platform_version_build_key" UNIQUE ("platform", "version", "build_number");



ALTER TABLE ONLY "public"."books"
    ADD CONSTRAINT "books_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cleanup_logs"
    ADD CONSTRAINT "cleanup_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."integration_destinations"
    ADD CONSTRAINT "integration_destinations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."providers"
    ADD CONSTRAINT "providers_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."providers"
    ADD CONSTRAINT "providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quotes"
    ADD CONSTRAINT "quotes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."readspace_integrations"
    ADD CONSTRAINT "readspace_integrations_pkey" PRIMARY KEY ("id");



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



ALTER TABLE ONLY "public"."sync_logs"
    ADD CONSTRAINT "sync_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_user_id_device_name_key" UNIQUE ("user_id", "device_name");



CREATE INDEX "idx_app_versions_platform_released_date" ON "public"."app_versions" USING "btree" ("platform", "is_released" DESC, "release_date" DESC);



CREATE INDEX "idx_books_sync_data" ON "public"."books" USING "gin" ("sync_data");



CREATE INDEX "idx_integration_destinations_integration_id" ON "public"."integration_destinations" USING "btree" ("readspace_integration_id");



CREATE INDEX "idx_invitations_invitee_email_lower" ON "public"."invitations" USING "btree" ("lower"("invitee_email"));



CREATE INDEX "idx_invitations_invitee_user_id" ON "public"."invitations" USING "btree" ("invitee_user_id");



CREATE INDEX "idx_invitations_readspace_id_status" ON "public"."invitations" USING "btree" ("readspace_id", "status");



CREATE INDEX "idx_quotes_created_at" ON "public"."quotes" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_quotes_readspace_id" ON "public"."quotes" USING "btree" ("readspace_id");



CREATE INDEX "idx_quotes_status" ON "public"."quotes" USING "btree" ("status");



CREATE INDEX "idx_quotes_sync_data" ON "public"."quotes" USING "gin" ("sync_data");



CREATE INDEX "idx_quotes_user_id" ON "public"."quotes" USING "btree" ("user_id");



CREATE INDEX "idx_readspace_integrations_provider_id" ON "public"."readspace_integrations" USING "btree" ("provider_id");



CREATE INDEX "idx_readspace_integrations_readspace_id" ON "public"."readspace_integrations" USING "btree" ("readspace_id");



CREATE INDEX "idx_readspace_integrations_status" ON "public"."readspace_integrations" USING "btree" ("status");



CREATE INDEX "idx_readspace_integrations_user_id" ON "public"."readspace_integrations" USING "btree" ("user_id");



CREATE INDEX "idx_shared_quotes_active" ON "public"."published_quotes" USING "btree" ("is_active");



CREATE INDEX "idx_shared_quotes_public_slug" ON "public"."published_quotes" USING "btree" ("public_slug");



CREATE INDEX "idx_shared_quotes_quote_id" ON "public"."published_quotes" USING "btree" ("quote_id");



CREATE INDEX "idx_shared_quotes_readspace_id" ON "public"."published_quotes" USING "btree" ("readspace_id");



CREATE INDEX "idx_sync_logs_integration_id" ON "public"."sync_logs" USING "btree" ("readspace_integration_id");



CREATE INDEX "idx_sync_logs_status" ON "public"."sync_logs" USING "btree" ("status");



CREATE INDEX "idx_user_devices_is_active" ON "public"."user_devices" USING "btree" ("is_active");



CREATE INDEX "idx_user_devices_last_login_at" ON "public"."user_devices" USING "btree" ("last_login_at");



CREATE INDEX "quotes_user_device_id_idx" ON "public"."quotes" USING "btree" ("user_device_id");



CREATE INDEX "quotes_user_pending_idx" ON "public"."quotes" USING "btree" ("user_id", "updated_at" DESC) WHERE ("status" = 'pending_selection'::"text");



CREATE INDEX "quotes_user_space_pending_idx" ON "public"."quotes" USING "btree" ("user_id", "readspace_id", "updated_at" DESC) WHERE ("status" = 'pending_selection'::"text");



CREATE INDEX "readspaces_active_book_id_idx" ON "public"."readspaces" USING "btree" ("active_book_id");



CREATE UNIQUE INDEX "uniq_invitations_pending_email" ON "public"."invitations" USING "btree" ("readspace_id", "lower"("invitee_email")) WHERE ("status" = 'pending'::"text");



CREATE INDEX "user_devices_active_readspace_id_idx" ON "public"."user_devices" USING "btree" ("active_readspace_id");



CREATE INDEX "user_devices_user_id_idx" ON "public"."user_devices" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "on_updated" BEFORE UPDATE ON "public"."books" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_integration_destinations_updated_at" BEFORE UPDATE ON "public"."integration_destinations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_providers_updated_at" BEFORE UPDATE ON "public"."providers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_readspace_integrations_updated_at" BEFORE UPDATE ON "public"."readspace_integrations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."books"
    ADD CONSTRAINT "books_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."books"
    ADD CONSTRAINT "books_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."published_quotes"
    ADD CONSTRAINT "fk_shared_quotes_quote_id" FOREIGN KEY ("quote_id") REFERENCES "public"."quotes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."integration_destinations"
    ADD CONSTRAINT "integration_destinations_integration_id_fkey" FOREIGN KEY ("readspace_integration_id") REFERENCES "public"."readspace_integrations"("id") ON DELETE CASCADE;



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



ALTER TABLE ONLY "public"."readspace_integrations"
    ADD CONSTRAINT "readspace_integrations_provider_id_fkey" FOREIGN KEY ("provider_id") REFERENCES "public"."providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."readspace_integrations"
    ADD CONSTRAINT "readspace_integrations_readspace_id_fkey" FOREIGN KEY ("readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."readspace_integrations"
    ADD CONSTRAINT "readspace_integrations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



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



ALTER TABLE ONLY "public"."sync_logs"
    ADD CONSTRAINT "sync_logs_integration_id_fkey" FOREIGN KEY ("readspace_integration_id") REFERENCES "public"."readspace_integrations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_active_readspace_id_fkey" FOREIGN KEY ("active_readspace_id") REFERENCES "public"."readspaces"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



CREATE POLICY "Anyone can view active providers" ON "public"."providers" FOR SELECT USING (("is_active" = true));



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



CREATE POLICY "Users can view own integration destinations" ON "public"."integration_destinations" USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_integrations"
  WHERE (("readspace_integrations"."id" = "integration_destinations"."readspace_integration_id") AND ("readspace_integrations"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view own integrations" ON "public"."readspace_integrations" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view own sync logs" ON "public"."sync_logs" USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_integrations"
  WHERE (("readspace_integrations"."id" = "sync_logs"."readspace_integration_id") AND ("readspace_integrations"."user_id" = "auth"."uid"())))));



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



CREATE POLICY "books_select_for_published_public" ON "public"."books" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."published_quotes" "pq"
     JOIN "public"."quotes" "q" ON (("pq"."quote_id" = "q"."id")))
  WHERE (("q"."book_id" = "books"."id") AND ("pq"."is_active" = true)))));



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



ALTER TABLE "public"."integration_destinations" ENABLE ROW LEVEL SECURITY;


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


CREATE POLICY "profiles_select_for_published_quote_owners" ON "public"."profiles" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."published_quotes" "pq"
     JOIN "public"."quotes" "q" ON (("pq"."quote_id" = "q"."id")))
  WHERE (("q"."user_id" = "profiles"."id") AND ("pq"."is_active" = true)))));



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



ALTER TABLE "public"."providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."published_quotes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."quotes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "quotes_delete_policy" ON "public"."quotes" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));



CREATE POLICY "quotes_insert_policy" ON "public"."quotes" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))) AND ("user_id" = "auth"."uid"())));



CREATE POLICY "quotes_select_for_published_public" ON "public"."quotes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."published_quotes" "pq"
  WHERE (("pq"."quote_id" = "quotes"."id") AND ("pq"."is_active" = true)))));



CREATE POLICY "quotes_select_policy" ON "public"."quotes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"())))));



CREATE POLICY "quotes_update_policy" ON "public"."quotes" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."readspace_memberships" "rm"
  WHERE (("rm"."readspace_id" = "quotes"."readspace_id") AND ("rm"."user_id" = "auth"."uid"()) AND ("rm"."role" <> 'viewer'::"public"."readspace_role")))));



ALTER TABLE "public"."readspace_integrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."readspaces" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sync_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_devices" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "supabase_admin";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_invitation"("p_invitation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_old_quotes"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_old_quotes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_old_quotes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."decline_invitation"("p_invitation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."decline_invitation"("p_invitation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decline_invitation"("p_invitation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."export_readspace_snapshot"("p_readspace_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."export_readspace_snapshot"("p_readspace_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."export_readspace_snapshot"("p_readspace_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."find_user_id_by_email"("user_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."find_user_id_by_email"("user_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_user_id_by_email"("user_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."gemini_rr_next"("total" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."gemini_rr_next"("total" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gemini_rr_next"("total" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb", "p_readspace_suffix" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb", "p_readspace_suffix" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."import_readspace_snapshot"("p_payload" "jsonb", "p_readspace_suffix" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_view_count"("slug" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_view_count"("slug" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_view_count"("slug" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_published_quote_accessible"("slug" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."is_published_quote_accessible"("slug" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_published_quote_accessible"("slug" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON TABLE "public"."app_versions" TO "anon";
GRANT ALL ON TABLE "public"."app_versions" TO "authenticated";
GRANT ALL ON TABLE "public"."app_versions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."app_versions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."app_versions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."app_versions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."books" TO "anon";
GRANT ALL ON TABLE "public"."books" TO "authenticated";
GRANT ALL ON TABLE "public"."books" TO "service_role";



GRANT ALL ON TABLE "public"."cleanup_logs" TO "anon";
GRANT ALL ON TABLE "public"."cleanup_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."cleanup_logs" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cleanup_logs_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cleanup_logs_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cleanup_logs_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."gemini_rr_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."gemini_rr_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."gemini_rr_seq" TO "service_role";



GRANT ALL ON TABLE "public"."integration_destinations" TO "anon";
GRANT ALL ON TABLE "public"."integration_destinations" TO "authenticated";
GRANT ALL ON TABLE "public"."integration_destinations" TO "service_role";



GRANT ALL ON TABLE "public"."invitations" TO "anon";
GRANT ALL ON TABLE "public"."invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."invitations" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."providers" TO "anon";
GRANT ALL ON TABLE "public"."providers" TO "authenticated";
GRANT ALL ON TABLE "public"."providers" TO "service_role";



GRANT ALL ON TABLE "public"."published_quotes" TO "anon";
GRANT ALL ON TABLE "public"."published_quotes" TO "authenticated";
GRANT ALL ON TABLE "public"."published_quotes" TO "service_role";



GRANT ALL ON TABLE "public"."quotes" TO "anon";
GRANT ALL ON TABLE "public"."quotes" TO "authenticated";
GRANT ALL ON TABLE "public"."quotes" TO "service_role";



GRANT ALL ON TABLE "public"."readspace_integrations" TO "anon";
GRANT ALL ON TABLE "public"."readspace_integrations" TO "authenticated";
GRANT ALL ON TABLE "public"."readspace_integrations" TO "service_role";



GRANT ALL ON TABLE "public"."readspace_memberships" TO "anon";
GRANT ALL ON TABLE "public"."readspace_memberships" TO "authenticated";
GRANT ALL ON TABLE "public"."readspace_memberships" TO "service_role";



GRANT ALL ON TABLE "public"."readspaces" TO "anon";
GRANT ALL ON TABLE "public"."readspaces" TO "authenticated";
GRANT ALL ON TABLE "public"."readspaces" TO "service_role";



GRANT ALL ON TABLE "public"."sync_logs" TO "anon";
GRANT ALL ON TABLE "public"."sync_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."sync_logs" TO "service_role";



GRANT ALL ON TABLE "public"."user_devices" TO "anon";
GRANT ALL ON TABLE "public"."user_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."user_devices" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "supabase_admin";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "supabase_admin";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON TABLES TO "supabase_admin";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_admin" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






RESET ALL;
