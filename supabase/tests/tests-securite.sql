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
  -- row_to_json force le calcul de chaque colonne : avec un simple count(*),
  -- PostgreSQL n'appelait pas les fonctions du SELECT (droits jamais vérifiés).
  if q ~* '^\s*select' then execute 'select count(*) from (select row_to_json(s) j from (' || q || ') s) t where j is not null' into n;
  else execute q; get diagnostics n = row_count; end if;
  raise exception 'RES:%', n;
exception when others then
  if sqlerrm like 'RES:%' then return substr(sqlerrm, 5); end if;
  return 'refusé';
end $$;

-- Crée un club puis compte, dans une requête SUIVANTE, si l'appelant en est CQ
-- (dans une même requête, la ligne tout juste créée n'est pas encore visible).
create or replace function pg_temp.creer_club_et_verifier_cq() returns int language plpgsql as $$
declare v uuid; n int;
begin
  v := create_club('TEST Nouveau club');
  select count(*) into n from club_members where club_id = v and role = 'cq' and profile_id = auth.uid();
  return n;
end $$;

-- Ajoute l'externe avec un ancien nom de rôle, renvoie le rôle réellement enregistré
create or replace function pg_temp.ajout_role_ancien(ancien text) returns text language plpgsql as $f$
declare v text;
begin
  insert into team_members(team_id, profile_id, role)
  values ('10000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000004', ancien);
  select role into v from team_members where team_id = '10000000-0000-4000-a000-0000000000a1'
    and profile_id = '00000000-0000-4000-a000-000000000004';
  delete from team_members where team_id = '10000000-0000-4000-a000-0000000000a1'
    and profile_id = '00000000-0000-4000-a000-000000000004';
  return v;
end $f$;

-- Crée une équipe sans préciser de club, renvoie le club attribué automatiquement
create or replace function pg_temp.creer_equipe_club() returns uuid language plpgsql as $f$
declare v uuid; c uuid;
begin
  insert into teams(nom, categorie) values ('TEST auto-club', 'U8') returning id into v;
  select club_id into c from teams where id = v;
  return c;
end $f$;

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
 ('Visiteur', 'cherche un profil par email', 'refusé', pg_temp.essai($q$select * from find_profile_by_email('coach.a@test.footcoach')$q$)),
 -- page publique : seule l'équipe A est cochée « Scores publics » (1 match aujourd'hui)
 ('Visiteur', 'scores publics : seulement l''équipe publiée', '1', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date)$q$)),
 ('Visiteur', 'scores publics : jamais l''équipe B', '0', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date) where equipe like '%Club B'$q$)),
 -- consentement : 3 buts dans le match A, un seul prénom publiable (Zoé, autorisée)
 ('Visiteur', 'scores publics : les 3 buts sont listés', '3', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date) s, jsonb_array_elements(s.buts) g$q$)),
 ('Visiteur', 'scores publics : 1 seul prénom (autorisé)', '1', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date) s, jsonb_array_elements(s.buts) g where g->>'buteur' is not null$q$)),
 ('Visiteur', 'scores publics : « Zoé C. » (autorisée)', '1', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date) s, jsonb_array_elements(s.buts) g where g->>'buteur' = 'Zoé C.'$q$)),
 ('Visiteur', 'scores publics : jamais de nom complet', '0', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date) s where s.buts::text ~ '(Alpha|Charlie)'$q$));
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

-- ------------------------------------------------------------- DÉLÉGUÉ de l'équipe A (ex-« membre », mêmes droits qu'un entraîneur depuis A2)
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', 'voit l''équipe A', '1', pg_temp.essai($q$select 1 from teams where id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Délégué A', 'voit l''équipe B', '0', pg_temp.essai($q$select 1 from teams where id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Délégué A', 'voit les joueurs A (2)', '2', pg_temp.essai($q$select 1 from players where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Délégué A', 'voit les joueurs B', '0', pg_temp.essai($q$select 1 from players where team_id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Délégué A', 'voit les matchs B', '0', pg_temp.essai($q$select 1 from matches where team_id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Délégué A', 'voit le profil du coach A', '1', pg_temp.essai($q$select 1 from profiles where id = '00000000-0000-4000-a000-000000000001'$q$)),
 ('Délégué A', 'voit le profil du coach B', '0', pg_temp.essai($q$select 1 from profiles where id = '00000000-0000-4000-a000-000000000003'$q$)),
 ('Délégué A', 'modifie l''équipe A', '1', pg_temp.essai($q$update teams set nom = nom where id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Délégué A', 'ajoute quelqu''un à l''équipe A', '1', pg_temp.essai($q$insert into team_members(team_id,profile_id,role) values ('10000000-0000-4000-a000-0000000000a1','00000000-0000-4000-a000-000000000004','member')$q$)),
 ('Délégué A', 'retire le coach A', '1', pg_temp.essai($q$delete from team_members where profile_id = '00000000-0000-4000-a000-000000000001'$q$)),
 ('Délégué A', 'met à jour le score d''un match A', '1', pg_temp.essai($q$update matches set score_nous = 1 where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Délégué A', 'supprime l''équipe A (réservé au club)', 'refusé', pg_temp.essai($q$select delete_team('10000000-0000-4000-a000-0000000000a1')$q$));
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

-- ============================================================= PHASE A1 : CLUBS & RÉFÉRENTIELS
-- Club A : CQ = Coach A, coordinateur = Fanny (Coord A). Club B : CQ = Coach B.
-- Admin plateforme = Eric. L'équipe A appartient au club A, l'équipe B au club B.
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[A1] voit des clubs', '0', pg_temp.essai($q$select 1 from clubs$q$)),
 ('Visiteur', '[A1] voit les formats', '0', pg_temp.essai($q$select 1 from formats$q$)),
 ('Visiteur', '[A1] crée un club', 'refusé', pg_temp.essai($q$select create_club('TEST pirate')$q$)),
 ('Visiteur', '[A1] appelle une fonction interne', 'refusé', pg_temp.essai($q$select is_platform_admin()$q$)),
 ('Visiteur', '[A1] appelle une fonction de trigger', 'refusé', pg_temp.essai($q$select guard_last_cq()$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[A1] voit des clubs', '0', pg_temp.essai($q$select 1 from clubs$q$)),
 ('Externe', '[A1] lit les formats (4)', '4', pg_temp.essai($q$select 1 from formats$q$)),
 ('Externe', '[A1] crée son club (devient CQ)', '1', pg_temp.essai($q$select 1 from generate_series(1, pg_temp.creer_club_et_verifier_cq())$q$)),
 ('Externe', '[A1] s''ajoute CQ du club A', 'refusé', pg_temp.essai($q$insert into club_members(club_id,profile_id,role) values ('50000000-0000-4000-a000-0000000000a1', auth.uid(), 'cq')$q$)),
 ('Externe', '[A1] ajoute un niveau', 'refusé', pg_temp.essai($q$insert into niveaux(libelle,cree_par) values ('Pirate', auth.uid())$q$)),
 ('Externe', '[A1] s''inscrit admin plateforme', 'refusé', pg_temp.essai($q$insert into platform_admins(profile_id) values (auth.uid())$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', '[A1] voit le club A (son équipe)', '1', pg_temp.essai($q$select 1 from clubs where id = '50000000-0000-4000-a000-0000000000a1'$q$)),
 ('Délégué A', '[A1] voit le club B', '0', pg_temp.essai($q$select 1 from clubs where id = '50000000-0000-4000-a000-0000000000b1'$q$)),
 ('Délégué A', '[A1] modifie le club A', '0', pg_temp.essai($q$update clubs set nom = nom where id = '50000000-0000-4000-a000-0000000000a1'$q$)),
 ('Délégué A', '[A1] voit les CQ/coordinateurs du club A', '0', pg_temp.essai($q$select 1 from club_members$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ A', '[A1] modifie le club A', '1', pg_temp.essai($q$update clubs set adresse = 'Rue du Stade 1' where id = '50000000-0000-4000-a000-0000000000a1'$q$)),
 ('CQ A', '[A1] modifie le club B', '0', pg_temp.essai($q$update clubs set nom = nom where id = '50000000-0000-4000-a000-0000000000b1'$q$)),
 ('CQ A', '[A1] se donne le badge « vérifié »', 'refusé', pg_temp.essai($q$update clubs set verifie = true where id = '50000000-0000-4000-a000-0000000000a1'$q$)),
 ('CQ A', '[A1] voit les membres du club A (2)', '2', pg_temp.essai($q$select 1 from club_members where club_id = '50000000-0000-4000-a000-0000000000a1'$q$)),
 ('CQ A', '[A1] voit les membres du club B', '0', pg_temp.essai($q$select 1 from club_members where club_id = '50000000-0000-4000-a000-0000000000b1'$q$)),
 ('CQ A', '[A1] nomme l''externe coordinateur', '1', pg_temp.essai($q$insert into club_members(club_id,profile_id,role) values ('50000000-0000-4000-a000-0000000000a1','00000000-0000-4000-a000-000000000004','coordinateur')$q$)),
 ('CQ A', '[A1] retire le dernier CQ (lui-même)', 'refusé', pg_temp.essai($q$delete from club_members where profile_id = auth.uid() and role = 'cq'$q$)),
 ('CQ A', '[A1] ajoute un niveau', '1', pg_temp.essai($q$insert into niveaux(libelle,cree_par) values ('TEST IP', auth.uid())$q$)),
 ('CQ A', '[A1] supprime le club A', '0', pg_temp.essai($q$delete from clubs where id = '50000000-0000-4000-a000-0000000000a1'$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000006","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coord A', '[A1] voit le club A', '1', pg_temp.essai($q$select 1 from clubs where id = '50000000-0000-4000-a000-0000000000a1'$q$)),
 ('Coord A', '[A1] modifie le club A', '0', pg_temp.essai($q$update clubs set nom = nom where id = '50000000-0000-4000-a000-0000000000a1'$q$)),
 ('Coord A', '[A1] se nomme CQ', 'refusé', pg_temp.essai($q$insert into club_members(club_id,profile_id,role) values ('50000000-0000-4000-a000-0000000000a1', auth.uid(), 'cq')$q$)),
 ('Coord A', '[A1] ajoute un niveau', '1', pg_temp.essai($q$insert into niveaux(libelle,cree_par) values ('TEST Régional', auth.uid())$q$)),
 ('Coord A', '[A1] modifie un format', '0', pg_temp.essai($q$update formats set duree_mt = 20 where code = '5v5'$q$)),
 ('Coord A', '[A1] quitte son rôle de coordinateur', '1', pg_temp.essai($q$delete from club_members where profile_id = auth.uid()$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ B', '[A1] voit le club A', '0', pg_temp.essai($q$select 1 from clubs where id = '50000000-0000-4000-a000-0000000000a1'$q$)),
 ('CQ B', '[A1] retire le CQ du club A', '0', pg_temp.essai($q$delete from club_members where club_id = '50000000-0000-4000-a000-0000000000a1'$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000005","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Admin', '[A1] voit tous les clubs (A, B, REH Braives)', '3', pg_temp.essai($q$select 1 from clubs$q$)),
 ('Admin', '[A1] vérifie le club A', '1', pg_temp.essai($q$update clubs set verifie = true where id = '50000000-0000-4000-a000-0000000000a1'$q$)),
 ('Admin', '[A1] modifie un format', '1', pg_temp.essai($q$update formats set duree_mt = 25 where code = '5v5'$q$)),
 ('Admin', '[A1] supprime un niveau', '1', pg_temp.essai($q$delete from niveaux where libelle = 'Niveau 4'$q$)),
 ('Admin', '[A1] ne voit pas les joueurs (pas membre)', '0', pg_temp.essai($q$select 1 from players$q$));
reset role;

-- ============================================================= PHASE A2 : MIGRATION & RÔLES
-- Contrôles de la migration (exécutés sans rôle particulier)
insert into r (qui, test, attendu, obtenu) values
 ('Migration', '[A2] plus aucun rôle « admin »/« member »', '0', (select count(*)::text from team_members where role in ('admin','member'))),
 ('Migration', '[A2] équipe historique rattachée au club 4308', '1', (select count(*)::text from teams t join clubs c on c.id = t.club_id where t.id = '10000000-0000-4000-a000-0000000000c1' and c.matricule = '4308')),
 ('Migration', '[A2] club 4308 vérifié, CQ = admin plateforme', '1', (select count(*)::text from clubs c join club_members cm on cm.club_id = c.id and cm.role = 'cq' join platform_admins a on a.profile_id = cm.profile_id where c.matricule = '4308' and c.verifie)),
 ('Migration', '[A2] équipes A et B gardent leur club', '2', (select count(*)::text from teams where club_id in ('50000000-0000-4000-a000-0000000000a1','50000000-0000-4000-a000-0000000000b1')));

-- Parent de l'équipe A : voit l'équipe et les matchs, rien d'autre
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[A2] voit l''équipe A', '1', pg_temp.essai($q$select 1 from teams where id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A2] voit les matchs A', '1', pg_temp.essai($q$select 1 from matches where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A2] voit les convocations A', '1', pg_temp.essai($q$select 1 from convocations where match_id = '40000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A2] voit les fiches joueurs (dates de naissance)', '0', pg_temp.essai($q$select 1 from players$q$)),
 ('Parent A', '[A2] voit les notes joueurs', '0', pg_temp.essai($q$select 1 from player_notes$q$)),
 ('Parent A', '[A2] modifie un match', '0', pg_temp.essai($q$update matches set score_nous = 9 where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A2] modifie une convocation', '0', pg_temp.essai($q$update convocations set statut = 'absent'$q$)),
 ('Parent A', '[A2] ajoute quelqu''un à l''équipe', 'refusé', pg_temp.essai($q$insert into team_members(team_id,profile_id,role) values ('10000000-0000-4000-a000-0000000000a1','00000000-0000-4000-a000-000000000004','delegue')$q$)),
 ('Parent A', '[A2] modifie l''équipe A', '0', pg_temp.essai($q$update teams set nom = nom where id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A2] voit l''équipe B', '0', pg_temp.essai($q$select 1 from teams where id = '10000000-0000-4000-a000-0000000000b1'$q$));
reset role;

-- Coordinateur du club A (pas membre de l'équipe A) : gère les équipes de son club
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000006","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coord A', '[A2] voit l''équipe A (son club)', '1', pg_temp.essai($q$select 1 from teams where id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Coord A', '[A2] voit les joueurs A (2)', '2', pg_temp.essai($q$select 1 from players where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Coord A', '[A2] met à jour un match A', '1', pg_temp.essai($q$update matches set score_nous = 3 where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Coord A', '[A2] ajoute un délégué à l''équipe A', '1', pg_temp.essai($q$insert into team_members(team_id,profile_id,role) values ('10000000-0000-4000-a000-0000000000a1','00000000-0000-4000-a000-000000000004','delegue')$q$)),
 ('Coord A', '[A2] voit le profil du parent A', '1', pg_temp.essai($q$select 1 from profiles where id = '00000000-0000-4000-a000-000000000007'$q$)),
 ('Coord A', '[A2] supprime l''équipe A (delete_team)', '1', pg_temp.essai($q$select delete_team('10000000-0000-4000-a000-0000000000a1')$q$)),
 ('Coord A', '[A2] voit les joueurs B (autre club)', '0', pg_temp.essai($q$select 1 from players where team_id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Coord A', '[A2] modifie l''équipe B (autre club)', '0', pg_temp.essai($q$update teams set nom = nom where id = '10000000-0000-4000-a000-0000000000b1'$q$)),
 ('Coord A', '[A2] nouvelle équipe rattachée à son club', '1', pg_temp.essai($q$select 1 where pg_temp.creer_equipe_club() = '50000000-0000-4000-a000-0000000000a1'$q$));
reset role;

-- Entraîneur A : l'app (ancienne version) écrit encore « admin » → converti en « entraineur »
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[A2] rôle « admin » écrit → « entraineur »', '1', pg_temp.essai($q$select 1 where pg_temp.ajout_role_ancien('admin') = 'entraineur'$q$)),
 ('Coach A', '[A2] rôle « member » écrit → « delegue »', '1', pg_temp.essai($q$select 1 where pg_temp.ajout_role_ancien('member') = 'delegue'$q$)),
 ('Coach A', '[A2] rôle inconnu refusé', 'refusé', pg_temp.essai($q$insert into team_members(team_id,profile_id,role) values ('10000000-0000-4000-a000-0000000000a1','00000000-0000-4000-a000-000000000004','pirate')$q$)),
 ('Coach A', '[A2] déplace l''équipe A vers le club B', 'refusé', pg_temp.essai($q$update teams set club_id = '50000000-0000-4000-a000-0000000000b1' where id = '10000000-0000-4000-a000-0000000000a1'$q$));
reset role;
select set_config('request.jwt.claims', '', false);

select n, qui, test, attendu, obtenu, case when attendu = obtenu then 'OK' else 'ÉCHEC' end as resultat
from r order by n;
