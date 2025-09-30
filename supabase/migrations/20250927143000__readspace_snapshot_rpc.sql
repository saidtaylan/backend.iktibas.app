-- Readspace snapshot export/import RPCs
-- Generated at 2025-09-27

set check_function_bodies = off;

create or replace function public.export_readspace_snapshot(p_readspace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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

comment on function public.export_readspace_snapshot(uuid)
is 'Returns a JSON snapshot of a readspace with books and quotes for export.';

create or replace function public.import_readspace_snapshot(p_payload jsonb, p_readspace_suffix text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
  v_readspace_suffix text := coalesce(nullif(p_readspace_suffix, ''), '-copy');
  v_base_name text;
  v_candidate_name text;
  v_attempt integer;
  v_readspace_reports jsonb := '[]'::jsonb;
  v_report jsonb;
  v_suffix_applied boolean;
  v_original_id uuid;
  v_original_name text;
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
    v_original_id := v_readspace_row.id;
    v_original_name := v_readspace_row.name;
    v_suffix_applied := false;

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
      v_suffix_applied := true;
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

    v_report := jsonb_build_object(
      'original_id', v_original_id,
      'final_id', v_readspace_row.id,
      'original_name', v_original_name,
      'final_name', v_readspace_row.name,
      'suffix_applied', v_suffix_applied
    );
    v_readspace_reports := v_readspace_reports || jsonb_build_array(v_report);
  end loop;

  return jsonb_build_object(
    'imported_readspaces', v_imported,
    'readspaces', v_readspace_reports
  );
end;
$$;

comment on function public.import_readspace_snapshot(jsonb, text)
is 'Imports a JSON snapshot by creating readspaces, books, quotes, assigning ownership to the caller, and optionally applying a name suffix for duplicates.';

grant execute on function public.export_readspace_snapshot(uuid) to authenticated;
grant execute on function public.import_readspace_snapshot(jsonb, text) to authenticated;
