-- ============================================================================
-- FootCoach — Phase A2 : migration vers le modèle multi-clubs — 2026-10-23
-- Prérequis : phase A1 exécutée, et l'app mise à jour (elle accepte les anciens
-- ET les nouveaux rôles). Faire une SAUVEGARDE avant (supabase/outils/sauvegarde-donnees.sql).
--
-- 1. Club « REH Braives » (matricule 4308, Liège, vérifié), CQ = admin(s) plateforme
-- 2. Toutes les équipes sans club rattachées à REH Braives
-- 3. Rôles d'équipe : admin → entraineur, member → delegue (+ parent prévu).
--    Un trigger convertit aussi les anciens noms écrits par une ancienne version de l'app.
-- 4. Droits étendus au club : CQ et coordinateurs gèrent toutes les équipes du club
-- 5. Parents : voient l'équipe, les matchs et les convocations, PAS les fiches
--    joueurs / notes / dates de naissance / stats (détails en phase A3)
-- Rien n'est supprimé : joueurs, matchs, convocations, dates de naissance intacts.
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-10-23-A2-migration-club-ANNULER.sql
-- ============================================================================
begin;

-- ------------------------------------------------------------------ 1. CLUB REH BRAIVES
insert into public.clubs (nom, slug, province_id, matricule, couleur1, couleur2, verifie, logo, cree_par)
select 'REH Braives', 'reh-braives',
       (select id from public.provinces where nom = 'Liège'),
       '4308', '#fdea2e', '#b0212f', true,
       (select logo from public.teams where logo is not null order by created_at limit 1),
       (select profile_id from public.platform_admins limit 1)
where not exists (select 1 from public.clubs where matricule = '4308');

insert into public.club_members (club_id, profile_id, role)
select c.id, a.profile_id, 'cq'
from public.clubs c cross join public.platform_admins a
where c.matricule = '4308'
on conflict (club_id, profile_id, role) do nothing;

-- ------------------------------------------------------------------ 2. ÉQUIPES → CLUB
update public.teams set club_id = (select id from public.clubs where matricule = '4308')
where club_id is null;

-- ------------------------------------------------------------------ 3. RÔLES D'ÉQUIPE
update public.team_members set role = 'entraineur' where role = 'admin';
update public.team_members set role = 'delegue' where role not in ('entraineur', 'delegue', 'parent');
alter table public.team_members alter column role set default 'delegue';
-- (rejouable : contrainte et triggers recréés s'ils existent déjà)
alter table public.team_members drop constraint if exists team_members_role_check;
alter table public.team_members add constraint team_members_role_check
  check (role in ('entraineur', 'delegue', 'parent'));

-- Compatibilité : une ancienne version de l'app (ou la fonction create-user) écrit
-- encore 'admin' / 'member' → convertis en 'entraineur' / 'delegue'.
create or replace function public.normalize_team_role() returns trigger
  language plpgsql set search_path = public as
$$ begin
  if new.role = 'admin' then new.role := 'entraineur';
  elsif new.role = 'member' then new.role := 'delegue';
  end if;
  return new;
end $$;
drop trigger if exists team_members_normalize_role on public.team_members;
create trigger team_members_normalize_role before insert or update of role on public.team_members
  for each row execute function public.normalize_team_role();

-- Une équipe créée sans club par un CQ/coordinateur d'UN seul club y est rattachée.
create or replace function public.default_team_club() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  if new.club_id is null and auth.uid() is not null then
    select min(club_id::text)::uuid into new.club_id from club_members where profile_id = auth.uid()
    having count(distinct club_id) = 1;
  end if;
  return new;
end $$;
drop trigger if exists teams_default_club on public.teams;
create trigger teams_default_club before insert on public.teams
  for each row execute function public.default_team_club();

-- ------------------------------------------------------------------ 4. FONCTIONS D'AIDE
-- Membre d'une équipe = n'importe quel rôle dans l'équipe (parent compris),
-- OU CQ/coordinateur du club de l'équipe.
create or replace function public.is_team_member(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members where team_id = t and profile_id = auth.uid())
       or exists(select 1 from teams tt join club_members cm on cm.club_id = tt.club_id
                 where tt.id = t and cm.profile_id = auth.uid()) $$;

-- Encadrement d'une équipe = entraîneur ou délégué de l'équipe (mêmes droits),
-- OU CQ/coordinateur du club. Les parents n'en font pas partie.
create or replace function public.is_team_staff(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members where team_id = t and profile_id = auth.uid()
                 and role in ('entraineur', 'delegue'))
       or exists(select 1 from teams tt join club_members cm on cm.club_id = tt.club_id
                 where tt.id = t and cm.profile_id = auth.uid()) $$;

-- Ancien nom, gardé pour l'app et la fonction create-user : = encadrement.
create or replace function public.is_team_admin(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select public.is_team_staff(t) $$;

-- Encadrement d'au moins une équipe ou d'un club (recherche d'un profil par email)
create or replace function public.is_any_staff() returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members where profile_id = auth.uid() and role in ('entraineur','delegue'))
       or exists(select 1 from club_members where profile_id = auth.uid()) $$;

-- Profils visibles : personnes d'une même équipe, et pour un CQ/coordinateur,
-- toutes les personnes des équipes et de l'encadrement de son club.
create or replace function public.shares_team_with(p uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members a join team_members b on b.team_id = a.team_id
                 where a.profile_id = auth.uid() and b.profile_id = p)
       or exists(select 1 from club_members me
                 where me.profile_id = auth.uid()
                   and (exists(select 1 from club_members o where o.club_id = me.club_id and o.profile_id = p)
                        or exists(select 1 from teams t join team_members tm on tm.team_id = t.id
                                  where t.club_id = me.club_id and tm.profile_id = p))) $$;

create or replace function public.find_profile_by_email(e text)
  returns table(id uuid, prenom text, nom text, email text)
  language sql stable security definer set search_path = public as
$$ select p.id, p.prenom::text, p.nom::text, p.email::text from profiles p
   where lower(p.email) = lower(trim(e)) and public.is_any_staff() $$;

-- Suppression d'une équipe : CQ/coordinateur de son club (ou encadrement si l'équipe
-- n'a pas de club). Un entraîneur seul ne supprime pas une équipe du club.
create or replace function public.can_delete_team(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from teams tt where tt.id = t and (
           (tt.club_id is not null and public.is_club_member(tt.club_id))
        or (tt.club_id is null and public.is_team_staff(t)))) $$;

create or replace function public.delete_team(t uuid) returns void
  language plpgsql security definer set search_path = public as
$$ begin
  if not public.can_delete_team(t) then raise exception 'Droits insuffisants pour supprimer cette équipe'; end if;
  delete from team_members where team_id = t;
  delete from teams where id = t;
end $$;

-- ------------------------------------------------------------------ 5. RÈGLES (RLS)
-- Équipes
drop policy if exists "Teams select" on public.teams;
drop policy if exists "Teams insert" on public.teams;
drop policy if exists "Teams update" on public.teams;
drop policy if exists "Teams delete" on public.teams;
drop policy if exists "Teams select" on public.teams;
create policy "Teams select" on public.teams for select to authenticated
  using (is_team_member(id) or created_by = auth.uid());
drop policy if exists "Teams insert" on public.teams;
create policy "Teams insert" on public.teams for insert to authenticated
  with check (created_by = auth.uid() and (club_id is null or is_club_member(club_id)));
drop policy if exists "Teams update" on public.teams;
create policy "Teams update" on public.teams for update to authenticated
  using (is_team_staff(id)) with check (is_team_staff(id) and (club_id is null or is_club_member(club_id) or club_id = (select t2.club_id from teams t2 where t2.id = teams.id)));
drop policy if exists "Teams delete" on public.teams;
create policy "Teams delete" on public.teams for delete to authenticated
  using (can_delete_team(id));

-- Membres d'équipe
drop policy if exists "Members select" on public.team_members;
drop policy if exists "Members insert" on public.team_members;
drop policy if exists "Members update" on public.team_members;
drop policy if exists "Members delete" on public.team_members;
drop policy if exists "Members select" on public.team_members;
create policy "Members select" on public.team_members for select to authenticated
  using (profile_id = auth.uid() or is_team_member(team_id));
drop policy if exists "Members insert" on public.team_members;
create policy "Members insert" on public.team_members for insert to authenticated
  with check (is_team_staff(team_id) or (profile_id = auth.uid() and is_team_creator(team_id)));
drop policy if exists "Members update" on public.team_members;
create policy "Members update" on public.team_members for update to authenticated
  using (is_team_staff(team_id)) with check (is_team_staff(team_id));
drop policy if exists "Members delete" on public.team_members;
create policy "Members delete" on public.team_members for delete to authenticated
  using (is_team_staff(team_id) or profile_id = auth.uid());

-- Joueurs, notes, stats : encadrement seulement (pas les parents, en attendant A3)
drop policy if exists "Joueurs de mes équipes" on public.players;
drop policy if exists "Joueurs encadrement" on public.players;
create policy "Joueurs encadrement" on public.players for all to authenticated
  using (is_team_staff(team_id)) with check (is_team_staff(team_id));

drop policy if exists "Notes accessibles" on public.player_notes;
drop policy if exists "Notes encadrement" on public.player_notes;
create policy "Notes encadrement" on public.player_notes for all to authenticated
  using (exists (select 1 from players p where p.id = player_notes.player_id and is_team_staff(p.team_id)))
  with check (exists (select 1 from players p where p.id = player_notes.player_id and is_team_staff(p.team_id)));

drop policy if exists "Stats match accessibles" on public.match_players;
drop policy if exists "Stats match encadrement" on public.match_players;
create policy "Stats match encadrement" on public.match_players for all to authenticated
  using (exists (select 1 from matches m where m.id = match_players.match_id and is_team_staff(m.team_id)))
  with check (exists (select 1 from matches m where m.id = match_players.match_id and is_team_staff(m.team_id)));

-- Matchs et convocations : lecture pour toute l'équipe (parents compris), écriture encadrement
drop policy if exists "Matchs de mes équipes" on public.matches;
drop policy if exists "Matchs lecture" on public.matches;
create policy "Matchs lecture" on public.matches for select to authenticated using (is_team_member(team_id));
drop policy if exists "Matchs ajout" on public.matches;
create policy "Matchs ajout" on public.matches for insert to authenticated with check (is_team_staff(team_id));
drop policy if exists "Matchs modif" on public.matches;
create policy "Matchs modif" on public.matches for update to authenticated using (is_team_staff(team_id)) with check (is_team_staff(team_id));
drop policy if exists "Matchs suppr" on public.matches;
create policy "Matchs suppr" on public.matches for delete to authenticated using (is_team_staff(team_id));

drop policy if exists "Convocations accessibles" on public.convocations;
drop policy if exists "Convocations lecture" on public.convocations;
create policy "Convocations lecture" on public.convocations for select to authenticated
  using (exists (select 1 from matches m where m.id = convocations.match_id and is_team_member(m.team_id)));
drop policy if exists "Convocations encadrement" on public.convocations;
create policy "Convocations encadrement" on public.convocations for all to authenticated
  using (exists (select 1 from matches m where m.id = convocations.match_id and is_team_staff(m.team_id)))
  with check (exists (select 1 from matches m where m.id = convocations.match_id and is_team_staff(m.team_id)));

-- Entraînements (pas encore utilisés par l'app) : même logique
drop policy if exists "Séances accessibles" on public.trainings;
drop policy if exists "Séances lecture" on public.trainings;
create policy "Séances lecture" on public.trainings for select to authenticated using (is_team_member(team_id));
drop policy if exists "Séances encadrement" on public.trainings;
create policy "Séances encadrement" on public.trainings for all to authenticated
  using (is_team_staff(team_id)) with check (is_team_staff(team_id));
drop policy if exists "Présences accessibles" on public.training_attendance;
drop policy if exists "Présences encadrement" on public.training_attendance;
create policy "Présences encadrement" on public.training_attendance for all to authenticated
  using (exists (select 1 from trainings t where t.id = training_attendance.training_id and is_team_staff(t.team_id)))
  with check (exists (select 1 from trainings t where t.id = training_attendance.training_id and is_team_staff(t.team_id)));

-- ------------------------------------------------------------------ DROITS D'APPEL
do $$ declare f text; begin
  foreach f in array array['is_team_staff(uuid)', 'is_any_staff()', 'can_delete_team(uuid)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['normalize_team_role()', 'default_team_club()'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

commit;

-- Contrôle : le club, ses équipes, les rôles
select c.nom as club, c.matricule, c.verifie,
       (select count(*) from public.teams t where t.club_id = c.id) as equipes,
       (select string_agg(distinct tm.role, ', ') from public.team_members tm join public.teams t on t.id = tm.team_id where t.club_id = c.id) as roles,
       (select count(*) from public.club_members cm where cm.club_id = c.id and cm.role = 'cq') as nb_cq
from public.clubs c where c.matricule = '4308';
