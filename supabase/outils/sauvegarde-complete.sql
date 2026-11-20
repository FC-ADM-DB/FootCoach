-- ============================================================================
-- FootLink — SAUVEGARDE COMPLÈTE (lecture seule, ne modifie rien)
-- À exécuter dans Supabase → SQL Editor → Run, sur le projet voulu
-- (PRODUCTION avant une réinitialisation ; FootLink pour s'entraîner).
--
-- Contrairement à sauvegarde-donnees.sql (liste figée de tables, périmée), celui-ci
-- parcourt TOUTES les tables du schéma public : une table ajoutée plus tard par une
-- migration est sauvegardée automatiquement. Il ajoute aussi les comptes (auth.users),
-- sans quoi une restauration perdrait les mots de passe et les liens profil ↔ compte.
--
-- Résultat : UNE cellule « sauvegarde ». Clic droit → copier la cellule (ou
-- « Download CSV »), collez dans un fichier texte, ex. sauvegarde-prod-2026-11-20.json,
-- RANGÉ HORS DU DOSSIER FootCoach (Documents…).
--
-- ⚠️ Contient des données d'enfants ET les empreintes de mots de passe : ne pas
-- l'envoyer, ne pas le publier, JAMAIS dans le dépôt GitHub.
-- Vérification : la ligne « comptage » ci-dessous donne le nombre de lignes par table ;
-- comparez-la avec le contenu du fichier avant de réinitialiser quoi que ce soit.
-- ============================================================================
create or replace function pg_temp.sauvegarde_complete() returns jsonb
language plpgsql as $$
declare
  t record;
  v_tables jsonb := '{}'::jsonb;
  v_data jsonb;
  v_comptage jsonb := '{}'::jsonb;
begin
  for t in
    select c.relname as nom
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')   -- tables (et partitionnées), pas les vues
    order by c.relname
  loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.%I x', t.nom) into v_data;
    v_tables := v_tables || jsonb_build_object(t.nom, v_data);
    v_comptage := v_comptage || jsonb_build_object(t.nom, jsonb_array_length(v_data));
  end loop;

  return jsonb_build_object(
    'date', now(),
    'projet', current_database(),
    'comptage', v_comptage || jsonb_build_object('auth.users', (select count(*) from auth.users)),
    'auth_users', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', u.id, 'email', u.email, 'encrypted_password', u.encrypted_password,
        'email_confirmed_at', u.email_confirmed_at, 'created_at', u.created_at,
        'raw_app_meta_data', u.raw_app_meta_data, 'raw_user_meta_data', u.raw_user_meta_data)), '[]'::jsonb)
      from auth.users u),
    'public', v_tables
  );
end $$;

select pg_temp.sauvegarde_complete() as sauvegarde;
