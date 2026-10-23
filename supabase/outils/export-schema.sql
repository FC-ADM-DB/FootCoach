-- ============================================================================
-- FootCoach — Export de la STRUCTURE de la base (lecture seule, aucune donnée)
-- À exécuter dans Supabase → SQL Editor → Run, sur le projet de PRODUCTION.
-- Renvoie une seule cellule « schema » : tables, colonnes, contraintes, index,
-- RLS, règles (policies), fonctions et triggers. Ne contient ni joueurs, ni matchs,
-- ni emails : uniquement la description des tables.
-- ============================================================================
select jsonb_build_object(
  'tables', (
    select jsonb_agg(jsonb_build_object(
      'table', c.relname,
      'rls', c.relrowsecurity,
      'columns', (
        select jsonb_agg(jsonb_build_object(
          'name', a.attname,
          'type', format_type(a.atttypid, a.atttypmod),
          'notnull', a.attnotnull,
          'default', pg_get_expr(d.adbin, d.adrelid)) order by a.attnum)
        from pg_attribute a
        left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
        where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped),
      'constraints', (
        select jsonb_agg(jsonb_build_object('name', k.conname, 'def', pg_get_constraintdef(k.oid)))
        from pg_constraint k where k.conrelid = c.oid),
      'indexes', (
        select jsonb_agg(pg_get_indexdef(i.indexrelid))
        from pg_index i where i.indrelid = c.oid and not i.indisprimary)
    ) order by c.relname)
    from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'),
  'policies', (
    select jsonb_agg(jsonb_build_object(
      'table', tablename, 'name', policyname, 'cmd', cmd, 'roles', roles,
      'using', qual, 'check', with_check) order by tablename, policyname)
    from pg_policies where schemaname = 'public'),
  'functions', (
    select jsonb_agg(pg_get_functiondef(p.oid) order by p.proname)
    from pg_proc p where p.pronamespace = 'public'::regnamespace),
  'triggers', (
    select jsonb_agg(jsonb_build_object(
      'table', t.tgrelid::regclass::text, 'name', t.tgname, 'def', pg_get_triggerdef(t.oid)))
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    where not t.tgisinternal
      and c.relnamespace in ('public'::regnamespace, 'auth'::regnamespace)),
  'storage_buckets', (select jsonb_agg(name) from storage.buckets)
) as schema;
