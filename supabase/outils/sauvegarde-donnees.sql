-- ============================================================================
-- FootCoach — SAUVEGARDE de toutes les données (lecture seule)
-- À exécuter dans Supabase → SQL Editor → Run, sur le projet de PRODUCTION.
-- Renvoie une cellule « sauvegarde » : copiez son contenu dans un fichier texte
-- (ex. sauvegarde-2026-10-23.json) RANGÉ HORS DU DOSSIER FootCoach (Documents…).
-- ⚠️ Contient des données d'enfants : ne pas l'envoyer, ne pas le publier, ne pas
-- le mettre dans le dépôt GitHub.
-- ============================================================================
select jsonb_build_object(
  'date', now(),
  'seasons',             (select coalesce(jsonb_agg(x), '[]') from public.seasons x),
  'profiles',            (select coalesce(jsonb_agg(x), '[]') from public.profiles x),
  'teams',               (select coalesce(jsonb_agg(x), '[]') from public.teams x),
  'team_members',        (select coalesce(jsonb_agg(x), '[]') from public.team_members x),
  'players',             (select coalesce(jsonb_agg(x), '[]') from public.players x),
  'matches',             (select coalesce(jsonb_agg(x), '[]') from public.matches x),
  'convocations',        (select coalesce(jsonb_agg(x), '[]') from public.convocations x),
  'match_players',       (select coalesce(jsonb_agg(x), '[]') from public.match_players x),
  'player_notes',        (select coalesce(jsonb_agg(x), '[]') from public.player_notes x),
  'trainings',           (select coalesce(jsonb_agg(x), '[]') from public.trainings x),
  'training_attendance', (select coalesce(jsonb_agg(x), '[]') from public.training_attendance x),
  'clubs',               (select coalesce(jsonb_agg(x), '[]') from public.clubs x),
  'club_members',        (select coalesce(jsonb_agg(x), '[]') from public.club_members x),
  'platform_admins',     (select coalesce(jsonb_agg(x), '[]') from public.platform_admins x)
) as sauvegarde;
