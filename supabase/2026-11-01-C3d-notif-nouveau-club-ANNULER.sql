-- ============================================================================
-- FootLink — ANNULATION de C3d (e-mail « nouveau club à vérifier ») — 2026-11-01
-- ============================================================================
begin;
drop trigger if exists clubs_notif_nouveau on public.clubs;
drop function if exists public.notif_nouveau_club();
commit;
