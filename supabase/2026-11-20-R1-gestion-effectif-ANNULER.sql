-- ============================================================================
-- ANNULATION de 2026-11-20-R1-gestion-effectif.sql : l'entraîneur et le délégué
-- gèrent de nouveau l'effectif et les membres de leur équipe (règles de A2 / A5).
-- ============================================================================
begin;

drop trigger if exists players_gestion_effectif on public.players;
drop function if exists public.players_gestion_effectif();

drop policy if exists "Joueurs encadrement lecture" on public.players;
drop policy if exists "Joueurs ajout" on public.players;
drop policy if exists "Joueurs modif" on public.players;
drop policy if exists "Joueurs suppr" on public.players;
drop policy if exists "Joueurs encadrement" on public.players;
create policy "Joueurs encadrement" on public.players for all to authenticated
  using (is_team_staff(team_id)) with check (is_team_staff(team_id));

drop policy if exists "Members insert" on public.team_members;
create policy "Members insert" on public.team_members for insert to authenticated
  with check (is_team_staff(team_id) or (profile_id = auth.uid() and is_team_creator(team_id)));
drop policy if exists "Members update" on public.team_members;
create policy "Members update" on public.team_members for update to authenticated
  using (is_team_staff(team_id)) with check (is_team_staff(team_id));
drop policy if exists "Members delete" on public.team_members;
create policy "Members delete" on public.team_members for delete to authenticated
  using (is_team_staff(team_id) or profile_id = auth.uid());

create or replace function public.demande_validable(d uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from demandes_acces x where x.id = d and (
     is_club_member(x.club_id) or (x.role <> 'coordinateur' and x.team_id is not null and is_team_staff(x.team_id)))) $$;

create or replace function public.demande_validateurs(x demandes_acces) returns uuid[]
  language sql stable security definer set search_path = public as
$$ select array(select notif_club_staff(x.club_id)
                union select notif_team_staff(x.team_id) where x.role <> 'coordinateur' and x.team_id is not null) $$;

create or replace function public.is_team_admin(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select public.is_team_staff(t) $$;

drop function if exists public.can_manage_team(uuid);

commit;
