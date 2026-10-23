-- ============================================================================
-- FootCoach — ANNULER la phase A2 (migration vers le modèle multi-clubs)
-- Remet les rôles (admin/member), les règles et les fonctions d'avant A2, détache
-- les équipes et supprime le club REH Braives. Joueurs, matchs, convocations,
-- dates de naissance : non touchés. Les tables de la phase A1 restent en place.
-- ============================================================================
begin;

-- Règles A2 → règles d'avant
drop policy if exists "Teams select" on public.teams;
drop policy if exists "Teams insert" on public.teams;
drop policy if exists "Teams update" on public.teams;
drop policy if exists "Teams delete" on public.teams;
drop policy if exists "Members select" on public.team_members;
drop policy if exists "Members insert" on public.team_members;
drop policy if exists "Members update" on public.team_members;
drop policy if exists "Members delete" on public.team_members;
drop policy if exists "Joueurs encadrement" on public.players;
drop policy if exists "Notes encadrement" on public.player_notes;
drop policy if exists "Stats match encadrement" on public.match_players;
drop policy if exists "Matchs lecture" on public.matches;
drop policy if exists "Matchs ajout" on public.matches;
drop policy if exists "Matchs modif" on public.matches;
drop policy if exists "Matchs suppr" on public.matches;
drop policy if exists "Convocations lecture" on public.convocations;
drop policy if exists "Convocations encadrement" on public.convocations;
drop policy if exists "Séances lecture" on public.trainings;
drop policy if exists "Séances encadrement" on public.trainings;
drop policy if exists "Présences encadrement" on public.training_attendance;

drop trigger if exists team_members_normalize_role on public.team_members;
drop trigger if exists teams_default_club on public.teams;
drop function if exists public.normalize_team_role();
drop function if exists public.default_team_club();

-- Rôles d'avant
alter table public.team_members drop constraint if exists team_members_role_check;
update public.team_members set role = 'admin' where role = 'entraineur';
update public.team_members set role = 'member' where role in ('delegue', 'parent');

-- Fonctions d'avant
create or replace function public.is_team_member(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members where team_id = t and profile_id = auth.uid()) $$;
create or replace function public.is_team_admin(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members where team_id = t and profile_id = auth.uid() and role = 'admin') $$;
create or replace function public.shares_team_with(p uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members a join team_members b on b.team_id = a.team_id
                 where a.profile_id = auth.uid() and b.profile_id = p) $$;
create or replace function public.find_profile_by_email(e text)
  returns table(id uuid, prenom text, nom text, email text)
  language sql stable security definer set search_path = public as
$$ select p.id, p.prenom::text, p.nom::text, p.email::text from profiles p
   where lower(p.email) = lower(trim(e))
     and exists(select 1 from team_members where profile_id = auth.uid() and role = 'admin') $$;
create or replace function public.delete_team(t uuid) returns void
  language plpgsql security definer set search_path = public as
$$ begin
  if not public.is_team_admin(t) then raise exception 'Accès admin requis'; end if;
  delete from team_members where team_id = t;
  delete from teams where id = t;
end $$;
drop function if exists public.can_delete_team(uuid);
drop function if exists public.is_any_staff();
drop function if exists public.is_team_staff(uuid);

create policy "Teams select" on public.teams for select to authenticated using (is_team_member(id) or created_by = auth.uid());
create policy "Teams insert" on public.teams for insert to authenticated with check (created_by = auth.uid());
create policy "Teams update" on public.teams for update to authenticated using (is_team_admin(id)) with check (is_team_admin(id));
create policy "Teams delete" on public.teams for delete to authenticated using (is_team_admin(id));
create policy "Members select" on public.team_members for select to authenticated using (profile_id = auth.uid() or is_team_member(team_id));
create policy "Members insert" on public.team_members for insert to authenticated with check (is_team_admin(team_id) or (profile_id = auth.uid() and is_team_creator(team_id)));
create policy "Members update" on public.team_members for update to authenticated using (is_team_admin(team_id)) with check (is_team_admin(team_id));
create policy "Members delete" on public.team_members for delete to authenticated using (is_team_admin(team_id) or profile_id = auth.uid());
create policy "Joueurs de mes équipes" on public.players for all to public
  using (exists (select 1 from team_members where team_members.team_id = players.team_id and team_members.profile_id = auth.uid()));
create policy "Matchs de mes équipes" on public.matches for all to public
  using (exists (select 1 from team_members where team_members.team_id = matches.team_id and team_members.profile_id = auth.uid()));
create policy "Convocations accessibles" on public.convocations for all to public
  using (exists (select 1 from matches m join team_members tm on tm.team_id = m.team_id where m.id = convocations.match_id and tm.profile_id = auth.uid()));
create policy "Stats match accessibles" on public.match_players for all to public
  using (exists (select 1 from matches m join team_members tm on tm.team_id = m.team_id where m.id = match_players.match_id and tm.profile_id = auth.uid()));
create policy "Notes accessibles" on public.player_notes for all to public
  using (exists (select 1 from players p join team_members tm on tm.team_id = p.team_id where p.id = player_notes.player_id and tm.profile_id = auth.uid()));
create policy "Séances accessibles" on public.trainings for all to public
  using (exists (select 1 from team_members where team_members.team_id = trainings.team_id and team_members.profile_id = auth.uid()));
create policy "Présences accessibles" on public.training_attendance for all to public
  using (exists (select 1 from trainings t join team_members tm on tm.team_id = t.team_id where t.id = training_attendance.training_id and tm.profile_id = auth.uid()));

-- Équipes détachées, club REH Braives supprimé
update public.teams set club_id = null where club_id = (select id from public.clubs where matricule = '4308');
delete from public.clubs where matricule = '4308';

commit;
