-- ============================================================================
-- FootCoach — ANNULATION de la messagerie (A4) — 2026-10-27
-- Supprime TOUS les messages et les indicateurs de lecture.
-- ============================================================================
begin;
drop function if exists public.mes_fils();
drop function if exists public.marquer_lu(uuid, uuid);
drop table if exists public.messages_lus;
drop table if exists public.messages;
drop function if exists public.guard_message();
drop function if exists public.peut_voir_fil(uuid, uuid);
commit;
