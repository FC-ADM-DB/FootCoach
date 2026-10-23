-- ============================================================================
-- FootCoach — TESTS DE SÉCURITÉ (RLS) — base de TEST uniquement (données de
-- supabase/tests/donnees-test.sql). Se fait passer pour chaque type d'utilisateur
-- et vérifie ce qu'il peut lire / créer / modifier / supprimer.
-- Chaque essai est exécuté puis ANNULÉ (aucune donnée n'est modifiée).
-- Résultat : une ligne par test, OK ou ÉCHEC.
-- « attendu » = le comportement SOUHAITÉ (un ÉCHEC signale une faille ou un écart).
-- ============================================================================
do $$ begin
  if exists (select 1 from public.teams where nom not like 'TEST %') then
    raise exception 'STOP : ce n''est pas la base de test.';
  end if;
end $$;

-- essai(requête) : nombre de lignes lues/touchées, ou « refusé » si la base bloque.
-- L'exception finale annule toujours l'essai (sous-transaction), même s'il a réussi.
create or replace function pg_temp.essai(q text) returns text language plpgsql as $$
declare n bigint;
begin
  if q ~* '^\s*select' then execute 'select count(*) from (' || q || ') s' into n;
  else execute q; get diagnostics n = row_count; end if;
  raise exception 'RES:%', n;
exception when others then
  if sqlerrm like 'RES:%' then return substr(sqlerrm, 5); end if;
  return 'refusé';
end $$;

drop table if exists pg_temp.r;
create temp table r (n serial, qui text, test text, attendu text, obtenu text);
grant all on r to anon, authenticated;
grant usage on sequence r_n_seq to anon, authenticated;

-- ------------------------------------------------------------- VISITEUR (sans compte)
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', 'voit des équipes', '0', pg_temp.essai($q$select 1 from teams$q$)),
 ('Visiteur', 'voit des membres', '0', pg_temp.essai($q$select 1 from team_members$q$)),
 ('Visiteur', 'voit des joueurs', '0', pg_temp.essai($q$select 1 from players$q$)),
 ('Visiteur', 'voit des matchs', '0', pg_temp.essai($q$select 1 from matches$q$)),
 ('Visiteur', 'voit des profils', '0', pg_temp.essai($q$select 1 from profiles$q$)),
 ('Visiteur', 'voit des notes joueurs', '0', pg_temp.essai($q$select 1 from player_notes$q$)),
 ('Visiteur', 'crée une saison', 'refusé', pg_temp.essai($q$insert into seasons(label) values ('pirate')$q$)),
 ('Visiteur', 'crée une équipe', 'refusé', pg_temp.essai($q$insert into teams(nom,categorie) values ('TEST pirate','U8')$q$)),
 ('Visiteur', 'cherche un profil par email', '0', pg_temp.essai($q$select * from find_profile_by_email('coach.a@test.footcoach')$q$)),
 -- page publique : seule l'équipe A est cochée « Scores publics » (1 match aujourd'hui)
 ('Visiteur', 'scores publics : seulement l''équipe publiée', '1', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date)$q$)),
 ('Visiteur', 'scores publics : jamais l''équipe B', '0', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date) where equipe like '%Club B'$q$));
reset role;

-- ------------------------------------------------------------- EXTERNE (connecté, sans équipe)
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', 'voit des équipes', '0', pg_temp.essai($q$select 1 from teams$q$)),
 ('Externe', 'voit des joueurs', '0', pg_temp.essai($q$select 1 from players$q$)),
 ('Externe', 'voit des matchs', '0', pg_temp.essai($q$select 1 from matches$q$)),
 ('Externe', 'voit le profil des autres', '0', pg_temp.essai($q$select 1 from profiles where id <> auth.uid()$q$)),
 ('Externe', 's''ajoute admin de l''équipe A', 'refusé', pg_temp.essai($q$insert into team_members(team_id,profile_id,role) values ('10000000-0000-4000-a000-0000000000a1', auth.uid(), 'admin')$q$)),
 ('Externe', 'modifie l''équipe A', '0', pg_temp.essai($q$update teams set nom = nom where id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Externe', 'crée une saison', 'refusé', pg_temp.essai($q$insert into seasons(label) values ('pirate')$q$)),
 ('Externe', 'crée sa propre équipe', '1', pg_temp.essai($q$insert into teams(nom,categorie) values ('TEST nouvelle','U8')$q$));
reset role;

-- ------------------------------------------------------------- MEMBRE de l'équipe A
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Membre A', 'voit l''équipe A', '1', pg_temp.essai($q$select 1 from teams where id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Membre A', 'voit l''équipe B', '0', pg_temp.essai($q$select 1 from teams where id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Membre A', 'voit les joueurs A', '1', pg_temp.essai($q$select 1 from players where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Membre A', 'voit les joueurs B', '0', pg_temp.essai($q$select 1 from players where team_id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Membre A', 'voit les matchs B', '0', pg_temp.essai($q$select 1 from matches where team_id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Membre A', 'voit le profil du coach A', '1', pg_temp.essai($q$select 1 from profiles where id = '00000000-0000-4000-a000-000000000001'$q$)),
 ('Membre A', 'voit le profil du coach B', '0', pg_temp.essai($q$select 1 from profiles where id = '00000000-0000-4000-a000-000000000003'$q$)),
 ('Membre A', 'modifie l''équipe A', '0', pg_temp.essai($q$update teams set nom = nom where id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Membre A', 'ajoute quelqu''un à l''équipe A', 'refusé', pg_temp.essai($q$insert into team_members(team_id,profile_id,role) values ('10000000-0000-4000-a000-0000000000a1','00000000-0000-4000-a000-000000000004','member')$q$)),
 ('Membre A', 'retire le coach A', '0', pg_temp.essai($q$delete from team_members where profile_id = '00000000-0000-4000-a000-000000000001'$q$)),
 ('Membre A', 'met à jour le score d''un match A', '1', pg_temp.essai($q$update matches set score_nous = 1 where team_id = '10000000-0000-4000-a000-0000000000a1'$q$));
reset role;

-- ------------------------------------------------------------- ADMIN de l'équipe A
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', 'modifie l''équipe A', '1', pg_temp.essai($q$update teams set nom = nom where id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Coach A', 'modifie l''équipe B', '0', pg_temp.essai($q$update teams set nom = nom where id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Coach A', 'voit les joueurs B', '0', pg_temp.essai($q$select 1 from players where team_id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Coach A', 'voit les convocations B', '0', pg_temp.essai($q$select 1 from convocations where match_id = '40000000-0000-4000-a000-0000000000b1'$q$)),
 ('Coach A', 'change le rôle du membre A', '1', pg_temp.essai($q$update team_members set role = 'member' where profile_id = '00000000-0000-4000-a000-000000000002'$q$)),
 ('Coach A', 'ajoute l''externe à l''équipe A', '1', pg_temp.essai($q$insert into team_members(team_id,profile_id,role) values ('10000000-0000-4000-a000-0000000000a1','00000000-0000-4000-a000-000000000004','member')$q$)),
 ('Coach A', 'cherche un profil par email', '1', pg_temp.essai($q$select * from find_profile_by_email('coach.b@test.footcoach')$q$)),
 ('Coach A', 'supprime l''équipe B (delete_team)', 'refusé', pg_temp.essai($q$select delete_team('10000000-0000-4000-a000-0000000000b1')$q$));
reset role;

-- ------------------------------------------------------------- ADMIN de l'équipe B
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach B', 'voit les matchs A', '0', pg_temp.essai($q$select 1 from matches where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Coach B', 'voit les notes du joueur A', '0', pg_temp.essai($q$select 1 from player_notes$q$)),
 ('Coach B', 'modifie un joueur A', '0', pg_temp.essai($q$update players set prenom = prenom where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Coach B', 'supprime un match A', '0', pg_temp.essai($q$delete from matches where team_id = '10000000-0000-4000-a000-0000000000a1'$q$));
reset role;
select set_config('request.jwt.claims', '', false);

select n, qui, test, attendu, obtenu, case when attendu = obtenu then 'OK' else 'ÉCHEC' end as resultat
from r order by n;
