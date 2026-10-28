-- ============================================================================
-- FootLink — ANNULATION des tournois (C6) — 2026-10-28
-- Supprime les tables des tournois (et tout leur contenu : tableaux, équipes, matchs,
-- inscriptions, messages) et leurs fonctions.
-- ============================================================================
begin;
drop table if exists public.tournoi_messages;
drop table if exists public.tournoi_matchs;
drop table if exists public.tournoi_equipes;
drop table if exists public.tournoi_inscriptions;
drop table if exists public.tournoi_tableaux;
drop table if exists public.tournoi_cibles;
drop table if exists public.tournois;
drop function if exists public.tournoi_public(uuid);
drop function if exists public.tournoi_score_confirmer(uuid, text);
drop function if exists public.tournoi_score(uuid, int, int, text, text, text);
drop function if exists public.mes_inscriptions();
drop function if exists public.tournoi_message(uuid, text);
drop function if exists public.tournoi_inscription_agir(uuid, text);
drop function if exists public.tournoi_inscrire(uuid, uuid, text);
drop function if exists public.inscription_verifier(uuid, uuid, uuid);
drop function if exists public.tournois_reseau();
drop function if exists public.clubs_reseau();
drop function if exists public.guard_tournoi_match();
drop function if exists public.guard_tournoi_equipe();
drop function if exists public.tableau_places_prises(uuid);
drop function if exists public.inscription_cote(uuid);
drop function if exists public.tournoi_visible_reseau(uuid);
drop function if exists public.peut_voir_tournoi(uuid);
drop function if exists public.is_club_team_staff(uuid);
drop function if exists public.tableau_club(uuid);
drop function if exists public.tableau_tournoi(uuid);
drop function if exists public.tournoi_club(uuid);
commit;
