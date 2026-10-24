-- ============================================================================
-- FootCoach — ANNULER la plateforme d'administration (2026-10-24)
-- Supprime uniquement les fonctions ajoutées ; aucune donnée n'est touchée.
-- ============================================================================
begin;
drop function if exists public.admin_fusion_niveau(integer, integer);
drop function if exists public.admin_niveaux();
drop function if exists public.admin_stats();
drop function if exists public.admin_clubs();
drop function if exists public.exiger_admin_plateforme();
commit;
