-- ============================================================================
-- FootLink — ANNULATION des demandes d'accès (A5) — 2026-11-01
-- Supprime les demandes (les accès déjà donnés restent).
-- ============================================================================
begin;
drop trigger if exists demandes_acces_notif on public.demandes_acces;
drop table if exists public.demandes_acces cascade;
drop function if exists public.notif_demandes_acces();
drop function if exists public.mes_demandes_acces();
drop function if exists public.demande_traiter(uuid, text, uuid, text);
drop function if exists public.demande_creer(uuid, text, uuid, text, text);
drop function if exists public.annuaire_clubs();
drop function if exists public.demande_validable(uuid);
commit;
