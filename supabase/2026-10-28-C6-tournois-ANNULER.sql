-- ============================================================================
-- FootLink — ANNULATION des tournois (C6) — 2026-10-28
-- Supprime les tables des tournois (et tout leur contenu) et leurs fonctions.
-- ============================================================================
begin;
drop table if exists public.tournoi_matchs;
drop table if exists public.tournoi_equipes;
drop table if exists public.tournoi_tableaux;
drop table if exists public.tournois;
drop function if exists public.tournoi_public(uuid);
drop function if exists public.tournoi_score(uuid, int, int, text, text);
drop function if exists public.guard_tournoi_match();
drop function if exists public.guard_tournoi_equipe();
drop function if exists public.is_club_team_staff(uuid);
drop function if exists public.tableau_club(uuid);
drop function if exists public.tournoi_club(uuid);
commit;
