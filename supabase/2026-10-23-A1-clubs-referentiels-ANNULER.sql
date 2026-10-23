-- ============================================================================
-- FootCoach — ANNULER la phase A1 (clubs, référentiels, rôles de club)
-- Supprime tout ce que la phase A1 a ajouté. Les équipes, joueurs et matchs ne
-- sont pas touchés (seules les colonnes teams.club_id / niveau_id sont retirées).
-- ============================================================================
begin;
alter table public.teams drop column if exists club_id;
alter table public.teams drop column if exists niveau_id;
drop table if exists public.club_members cascade;
drop table if exists public.clubs cascade;
drop table if exists public.platform_admins cascade;
drop table if exists public.niveaux cascade;
drop table if exists public.categories cascade;
drop table if exists public.formats cascade;
drop table if exists public.provinces cascade;
drop table if exists public.pays cascade;
drop function if exists public.create_club(text, int, text, text);
drop function if exists public.guard_club_verifie();
drop function if exists public.guard_last_cq();
drop function if exists public.is_platform_admin();
drop function if exists public.is_club_member(uuid);
drop function if exists public.is_club_cq(uuid);
drop function if exists public.is_any_club_staff();
drop function if exists public.is_in_club_team(uuid);
-- Droits d'appel des fonctions existantes remis comme avant la phase A1
do $$ declare f text; begin
  foreach f in array array['is_team_member(uuid)', 'is_team_admin(uuid)', 'is_team_creator(uuid)',
    'shares_team_with(uuid)', 'find_profile_by_email(text)', 'delete_team(uuid)', 'handle_new_user()'] loop
    execute format('grant execute on function public.%s to public, anon, authenticated', f);
  end loop;
end $$;
commit;
