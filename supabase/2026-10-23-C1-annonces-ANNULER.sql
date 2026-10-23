-- ============================================================================
-- FootCoach — ANNULER la phase C1 (annonces « Trouver un match »)
-- Supprime les annonces, créneaux et cibles, et les fonctions associées.
-- Aucune autre donnée n'est touchée.
-- ============================================================================
begin;
drop table if exists public.annonce_cibles cascade;
drop table if exists public.annonce_creneaux cascade;
drop table if exists public.annonces cascade;
drop function if exists public.guard_annonce();
drop function if exists public.annonces_reseau(uuid);
drop function if exists public.equipes_reseau();
drop function if exists public.can_edit_annonce(uuid);
drop function if exists public.can_see_annonce(uuid);
drop function if exists public.mes_clubs_reseau();
drop function if exists public.km_entre(float8, float8, float8, float8);
commit;
