-- ============================================================================
-- FootCoach — ANNULATION des propositions de match (C2) — 2026-10-27
-- Supprime les propositions et leur historique. Les matchs déjà créés par un accord
-- RESTENT dans le calendrier des équipes. Le téléphone du profil est conservé.
-- ============================================================================
begin;
drop function if exists public.mes_propositions();
drop function if exists public.proposition_lu(uuid);
drop function if exists public.proposition_message(uuid, text);
drop table if exists public.proposition_lus;
drop function if exists public.proposition_contacts(uuid);
drop function if exists public.proposition_agir(uuid, text, date, time, text, text);
drop function if exists public.proposition_creer(uuid, uuid, date, time, text, text);
drop table if exists public.proposition_tours;
drop table if exists public.propositions;
drop function if exists public.prop_nom_moi();
drop function if exists public.prop_cote(uuid);
commit;
