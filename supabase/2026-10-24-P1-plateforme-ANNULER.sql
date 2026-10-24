-- ============================================================================
-- FootCoach — ANNULER la plateforme d'administration (2026-10-24)
-- Supprime uniquement les fonctions ajoutées ; aucune donnée n'est touchée.
-- ============================================================================
begin;
drop function if exists public.admin_club_equipes(uuid);
drop function if exists public.admin_club_membres(uuid);
-- find_profile_by_email : version d'avant (encadrement seulement)
create or replace function public.find_profile_by_email(e text)
  returns table(id uuid, prenom text, nom text, email text)
  language sql stable security definer set search_path = public as
$$ select p.id, p.prenom::text, p.nom::text, p.email::text from profiles p
   where lower(p.email) = lower(trim(e)) and public.is_any_staff() $$;
drop function if exists public.admin_fusion_niveau(integer, integer);
drop function if exists public.admin_niveaux();
drop function if exists public.admin_stats();
drop function if exists public.admin_clubs();
drop function if exists public.exiger_admin_plateforme();
commit;
