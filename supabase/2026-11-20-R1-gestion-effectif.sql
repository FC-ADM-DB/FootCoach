-- ============================================================================
-- FootLink — R1 : qui gère l'effectif et les accès d'une équipe — 2026-11-20
-- Nécessite A2 (rôles), A3 (parents), A5 (demandes d'accès).
--
-- Décision du 2026-11-20 (retour de test des rôles) :
--   * Équipe DANS UN CLUB : seuls le CQ et les coordinateurs du club ajoutent ou
--     retirent des joueurs et gèrent les membres (entraîneurs, délégués, parents).
--     L'entraîneur et le délégué gardent tout le reste : matchs, Live, convocations,
--     modification des fiches joueurs, invitations des parents.
--   * Équipe SANS CLUB (entraîneur « indépendant », usage amateur) : son encadrement
--     gère tout lui-même, comme avant (il n'y a pas de coordinateur).
--   Même règle que la suppression d'une équipe (can_delete_team), d'où can_manage_team.
--
-- Changements :
--   1. can_manage_team(t) ; is_team_admin(t) devient un alias de can_manage_team
--      (n'est plus utilisé que par la fonction serveur create-user : « créer un compte et
--      l'ajouter à l'équipe » suit donc la nouvelle règle sans la redéployer).
--   2. players : ajout / suppression → can_manage_team ; lecture / modification de la
--      fiche → encadrement ; retirer un joueur (actif = false) ou le changer d'équipe →
--      can_manage_team (déclencheur, car l'app « supprime » par une modification).
--   3. team_members : ajout / modification / retrait → can_manage_team (chacun peut
--      toujours se retirer lui-même ; le créateur d'une équipe s'y ajoute).
--   4. Demandes d'accès (A5) : l'encadrement de l'équipe ne valide plus que les demandes
--      de PARENTS ; entraîneur / délégué → CQ et coordinateurs du club seulement
--      (et eux seuls reçoivent l'e-mail).
--
-- Testé sur la base de test (supabase/tests/tests-securite.sql, section R1).
-- Annulation : 2026-11-20-R1-gestion-effectif-ANNULER.sql
-- ============================================================================
begin;

-- 1. Qui gère l'équipe ---------------------------------------------------------
create or replace function public.can_manage_team(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from teams tt where tt.id = t and (
           (tt.club_id is not null and public.is_club_member(tt.club_id))
        or (tt.club_id is null and public.is_team_staff(t)))) $$;

create or replace function public.is_team_admin(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select public.can_manage_team(t) $$;

revoke execute on function public.can_manage_team(uuid) from public, anon;
grant execute on function public.can_manage_team(uuid) to authenticated;

-- 2. Joueurs -------------------------------------------------------------------
drop policy if exists "Joueurs encadrement" on public.players;
drop policy if exists "Joueurs encadrement lecture" on public.players;
drop policy if exists "Joueurs ajout" on public.players;
drop policy if exists "Joueurs modif" on public.players;
drop policy if exists "Joueurs suppr" on public.players;
create policy "Joueurs encadrement lecture" on public.players for select to authenticated
  using (is_team_staff(team_id));
create policy "Joueurs ajout" on public.players for insert to authenticated
  with check (can_manage_team(team_id));
create policy "Joueurs modif" on public.players for update to authenticated
  using (is_team_staff(team_id)) with check (is_team_staff(team_id));
create policy "Joueurs suppr" on public.players for delete to authenticated
  using (can_manage_team(team_id));

-- L'app retire un joueur avec « actif = false » (une modification) : sans ce contrôle,
-- l'entraîneur pourrait encore vider l'effectif. auth.uid() nul = SQL Editor / serveur.
create or replace function public.players_gestion_effectif() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  if auth.uid() is not null
     and (new.actif is distinct from old.actif or new.team_id is distinct from old.team_id)
     and not (can_manage_team(old.team_id) and can_manage_team(new.team_id)) then
    raise exception 'Seuls le CQ et les coordinateurs du club gèrent l''effectif';
  end if;
  return new;
end $$;
revoke execute on function public.players_gestion_effectif() from public, anon, authenticated;
drop trigger if exists players_gestion_effectif on public.players;
create trigger players_gestion_effectif before update on public.players
  for each row execute function public.players_gestion_effectif();

-- 3. Membres d'équipe ----------------------------------------------------------
drop policy if exists "Members insert" on public.team_members;
create policy "Members insert" on public.team_members for insert to authenticated
  with check (can_manage_team(team_id) or (profile_id = auth.uid() and is_team_creator(team_id)));
drop policy if exists "Members update" on public.team_members;
create policy "Members update" on public.team_members for update to authenticated
  using (can_manage_team(team_id)) with check (can_manage_team(team_id));
drop policy if exists "Members delete" on public.team_members;
create policy "Members delete" on public.team_members for delete to authenticated
  using (can_manage_team(team_id) or profile_id = auth.uid());

-- 4. Demandes d'accès : l'encadrement ne valide plus que les parents -----------
create or replace function public.demande_validable(d uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from demandes_acces x where x.id = d and (
     is_club_member(x.club_id) or (x.role = 'parent' and x.team_id is not null and is_team_staff(x.team_id)))) $$;

create or replace function public.demande_validateurs(x demandes_acces) returns uuid[]
  language sql stable security definer set search_path = public as
$$ select array(select notif_club_staff(x.club_id)
                union select notif_team_staff(x.team_id) where x.role = 'parent' and x.team_id is not null) $$;

commit;
