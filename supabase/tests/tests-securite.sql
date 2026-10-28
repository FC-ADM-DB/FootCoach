-- ============================================================================
-- FootCoach — TESTS DE SÉCURITÉ (RLS) — base de TEST uniquement (données de
-- supabase/tests/donnees-test.sql). Se fait passer pour chaque type d'utilisateur
-- et vérifie ce qu'il peut lire / créer / modifier / supprimer.
-- Chaque essai est exécuté puis ANNULÉ (aucune donnée n'est modifiée).
-- Résultat : une ligne par test, OK ou ÉCHEC.
-- « attendu » = le comportement SOUHAITÉ (un ÉCHEC signale une faille ou un écart).
-- ============================================================================
do $$ begin
  -- Base de production = de vrais comptes (ni @test ni @demo.footcoach) : on refuse.
  if exists (select 1 from auth.users where email not like '%@test.footcoach' and email not like '%@demo.footcoach') then
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

-- Accepte une proposition puis compte les matchs « TEST Club B » visibles (C2)
create or replace function pg_temp.accepter_compter(p uuid) returns bigint language plpgsql as $f$
begin
  perform public.proposition_agir(p, 'accepter');
  return (select count(*) from public.matches where adversaire like 'TEST Club B%');
end $f$;

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
 ('Délégué A', 'met à jour le score d''un match A', '1', pg_temp.essai($q$update matches set score_nous = 1 where id = '40000000-0000-4000-a000-0000000000a1'$q$)),
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
 ('Visiteur', '[B2] scores du club A (1 match public)', '1', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date, 'test-club-a')$q$)),
 ('Visiteur', '[B2] scores du club B (aucune équipe publique)', '0', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date, 'test-club-b')$q$)),
 ('Visiteur', '[B2] le match indique son club', '1', pg_temp.essai($q$select 1 from public_scores((now() at time zone 'Europe/Brussels')::date) where club_nom = 'TEST Club A'$q$)),
 ('Visiteur', '[B2] identité visuelle du club A', '1', pg_temp.essai($q$select 1 from public_club('test-club-a')$q$)),
 ('Visiteur', '[B2] club inconnu', '0', pg_temp.essai($q$select 1 from public_club('pas-un-club')$q$)),
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
 ('CQ A', '[A1] change lui-même le badge « vérifié »', 'refusé', pg_temp.essai($q$update clubs set verifie = not verifie where id = '50000000-0000-4000-a000-0000000000a1'$q$)),
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
 ('Admin', '[A1] voit tous les clubs (A, B, C, REH Braives)', '4', pg_temp.essai($q$select 1 from clubs$q$)),
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
 ('Parent A', '[A2] voit les matchs A (A et A2)', '2', pg_temp.essai($q$select 1 from matches where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A2] voit les convocations A', '1', pg_temp.essai($q$select 1 from convocations where match_id = '40000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A2] voit les fiches joueurs (seulement son enfant depuis A3)', '1', pg_temp.essai($q$select 1 from players$q$)),
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
 ('Coord A', '[A2] met à jour les matchs A (A et A2)', '2', pg_temp.essai($q$update matches set score_nous = 3 where team_id = '10000000-0000-4000-a000-0000000000a1'$q$)),
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

-- ============================================================= PHASE C1 : ANNONCES « TROUVER UN MATCH »
-- Club A (Liège) et club B (Namur) vérifiés, ~53 km ; club C NON vérifié.
-- Annonces de l'équipe A : AN1 Belgique, AN2 province, AN3 80 km, AN4 30 km,
-- AN5 à valider (préparée par le délégué A), AN6 équipes choisies = équipe B.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ B', '[C1] voit AN1 (toute la Belgique)', '1', pg_temp.essai($q$select 1 from annonces where id = '60000000-0000-4000-a000-000000000001'$q$)),
 ('CQ B', '[C1] voit AN2 (province de Liège)', '0', pg_temp.essai($q$select 1 from annonces where id = '60000000-0000-4000-a000-000000000002'$q$)),
 ('CQ B', '[C1] voit AN3 (80 km, il est à ~53)', '1', pg_temp.essai($q$select 1 from annonces where id = '60000000-0000-4000-a000-000000000003'$q$)),
 ('CQ B', '[C1] voit AN4 (30 km, il est à ~53)', '0', pg_temp.essai($q$select 1 from annonces where id = '60000000-0000-4000-a000-000000000004'$q$)),
 ('CQ B', '[C1] voit AN5 (à valider, pas publiée)', '0', pg_temp.essai($q$select 1 from annonces where id = '60000000-0000-4000-a000-000000000005'$q$)),
 ('CQ B', '[C1] voit AN6 (son équipe est ciblée)', '1', pg_temp.essai($q$select 1 from annonces where id = '60000000-0000-4000-a000-000000000006'$q$)),
 ('CQ B', '[C1] recherche : 3 annonces visibles', '3', pg_temp.essai($q$select 1 from annonces_reseau('10000000-0000-4000-a000-0000000000b1')$q$)),
 ('CQ B', '[C1] recherche : distance calculée (~53 km)', '3', pg_temp.essai($q$select 1 from annonces_reseau('10000000-0000-4000-a000-0000000000b1') where distance_club between 45 and 60$q$)),
 ('CQ B', '[C1] voit le créneau de AN1', '1', pg_temp.essai($q$select 1 from annonce_creneaux where annonce_id = '60000000-0000-4000-a000-000000000001'$q$)),
 ('CQ B', '[C1] voit que son équipe est ciblée (AN6)', '1', pg_temp.essai($q$select 1 from annonce_cibles where annonce_id = '60000000-0000-4000-a000-000000000006'$q$)),
 ('CQ B', '[C1] modifie AN1 (club A)', '0', pg_temp.essai($q$update annonces set message = 'pirate' where id = '60000000-0000-4000-a000-000000000001'$q$)),
 ('CQ B', '[C1] ajoute un créneau à AN1', 'refusé', pg_temp.essai($q$insert into annonce_creneaux(annonce_id, jour) values ('60000000-0000-4000-a000-000000000001', current_date)$q$)),
 ('CQ B', '[C1] crée une annonce pour l''équipe A', 'refusé', pg_temp.essai($q$insert into annonces(team_id, zone, statut, cree_par) values ('10000000-0000-4000-a000-0000000000a1', 'belgique', 'brouillon', auth.uid())$q$)),
 ('CQ B', '[C1] publie une annonce pour son équipe', '1', pg_temp.essai($q$insert into annonces(team_id, zone, statut, cree_par) values ('10000000-0000-4000-a000-0000000000b1', 'belgique', 'publiee', auth.uid())$q$)),
 ('CQ B', '[C1] équipes du réseau (clubs vérifiés : 3)', '3', pg_temp.essai($q$select 1 from equipes_reseau()$q$)),
 ('CQ B', '[C1] le réseau n''expose aucun joueur', '0', pg_temp.essai($q$select 1 from players where team_id = '10000000-0000-4000-a000-0000000000a1'$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', '[C1] prépare une annonce « à valider »', '1', pg_temp.essai($q$insert into annonces(team_id, zone, statut, cree_par) values ('10000000-0000-4000-a000-0000000000a1', 'belgique', 'a_valider', auth.uid())$q$)),
 ('Délégué A', '[C1] publie directement', 'refusé', pg_temp.essai($q$insert into annonces(team_id, zone, statut, cree_par) values ('10000000-0000-4000-a000-0000000000a1', 'belgique', 'publiee', auth.uid())$q$)),
 ('Délégué A', '[C1] publie AN5 lui-même', 'refusé', pg_temp.essai($q$update annonces set statut = 'publiee' where id = '60000000-0000-4000-a000-000000000005'$q$)),
 ('Délégué A', '[C1] modifie AN1 (déjà publiée)', 'refusé', pg_temp.essai($q$update annonces set message = 'x' where id = '60000000-0000-4000-a000-000000000001'$q$)),
 ('Délégué A', '[C1] voit AN5 (son équipe)', '1', pg_temp.essai($q$select 1 from annonces where id = '60000000-0000-4000-a000-000000000005'$q$)),
 ('Délégué A', '[C1] ajoute un créneau à AN5 (non publiée)', '1', pg_temp.essai($q$insert into annonce_creneaux(annonce_id, jour) values ('60000000-0000-4000-a000-000000000005', current_date + 3)$q$)),
 ('Délégué A', '[C1] supprime AN5 (à valider)', '1', pg_temp.essai($q$delete from annonces where id = '60000000-0000-4000-a000-000000000005'$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000006","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coord A', '[C1] voit AN5 (à valider)', '1', pg_temp.essai($q$select 1 from annonces where id = '60000000-0000-4000-a000-000000000005'$q$)),
 ('Coord A', '[C1] publie AN5', '1', pg_temp.essai($q$update annonces set statut = 'publiee' where id = '60000000-0000-4000-a000-000000000005'$q$)),
 ('Coord A', '[C1] refuse AN5 avec un commentaire', '1', pg_temp.essai($q$update annonces set statut = 'refusee', commentaire_validation = 'Dates déjà prises' where id = '60000000-0000-4000-a000-000000000005'$q$)),
 ('Coord A', '[C1] clôture AN1', '1', pg_temp.essai($q$update annonces set statut = 'cloturee' where id = '60000000-0000-4000-a000-000000000001'$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000008","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ C (non vérifié)', '[C1] voit AN1', '0', pg_temp.essai($q$select 1 from annonces where id = '60000000-0000-4000-a000-000000000001'$q$)),
 ('CQ C (non vérifié)', '[C1] recherche', '0', pg_temp.essai($q$select 1 from annonces_reseau(null)$q$)),
 ('CQ C (non vérifié)', '[C1] équipes du réseau', '0', pg_temp.essai($q$select 1 from equipes_reseau()$q$)),
 ('CQ C (non vérifié)', '[C1] publie une annonce', 'refusé', pg_temp.essai($q$insert into annonces(team_id, zone, statut, cree_par) values ('10000000-0000-4000-a000-0000000000d1', 'belgique', 'publiee', auth.uid())$q$)),
 ('CQ C (non vérifié)', '[C1] prépare un brouillon', '1', pg_temp.essai($q$insert into annonces(team_id, zone, statut, cree_par) values ('10000000-0000-4000-a000-0000000000d1', 'belgique', 'brouillon', auth.uid())$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[C1] voit des annonces', '0', pg_temp.essai($q$select 1 from annonces$q$)),
 ('Parent A', '[C1] crée une annonce', 'refusé', pg_temp.essai($q$insert into annonces(team_id, zone, statut, cree_par) values ('10000000-0000-4000-a000-0000000000a1', 'belgique', 'brouillon', auth.uid())$q$));
reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[C1] voit des annonces', '0', pg_temp.essai($q$select 1 from annonces$q$)),
 ('Visiteur', '[C1] appelle la recherche', 'refusé', pg_temp.essai($q$select 1 from annonces_reseau(null)$q$));
reset role;

-- ============================================================= PLATEFORME D'ADMINISTRATION (P1)
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000005","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Admin', '[P1] liste de tous les clubs (A, B, C, REH)', '4', pg_temp.essai($q$select 1 from admin_clubs()$q$)),
 ('Admin', '[P1] voit le CQ du club C (non vérifié)', '1', pg_temp.essai($q$select 1 from admin_clubs() where nom = 'TEST Club C' and cq_email = 'cq.c@test.footcoach' and not verifie$q$)),
 ('Admin', '[P1] chiffres de la plateforme', '1', pg_temp.essai($q$select 1 from admin_stats() where clubs = 4 and clubs_en_attente = 1$q$)),
 ('Admin', '[P1] niveaux et leur utilisation', '4', pg_temp.essai($q$select 1 from admin_niveaux()$q$)),
 ('Admin', '[P1] vérifie le club C', '1', pg_temp.essai($q$update clubs set verifie = true where id = '50000000-0000-4000-a000-0000000000c1'$q$)),
 ('Admin', '[P1] renomme un niveau', '1', pg_temp.essai($q$update niveaux set libelle = 'Niveau 4 (régional)' where libelle = 'Niveau 4'$q$)),
 ('Admin', '[P1] fusionne Niveau 4 dans Niveau 3', '1', pg_temp.essai($q$select admin_fusion_niveau((select id from niveaux where libelle = 'Niveau 4'), (select id from niveaux where libelle = 'Niveau 3'))$q$)),
 ('Admin', '[P1] fusion d''un niveau avec lui-même', 'refusé', pg_temp.essai($q$select admin_fusion_niveau(1, 1)$q$)),
 ('Admin', '[P1] fiche club A : 5 personnes (CQ, coord., équipe)', '5', pg_temp.essai($q$select 1 from admin_club_membres('50000000-0000-4000-a000-0000000000a1')$q$)),
 ('Admin', '[P1] fiche club A : 1 équipe, compteurs', '1', pg_temp.essai($q$select 1 from admin_club_equipes('50000000-0000-4000-a000-0000000000a1') where nb_joueurs = 2$q$)),
 ('Admin', '[P1] modifie la fiche du club C', '1', pg_temp.essai($q$update clubs set adresse = 'Grand-Place 1, 4000 Liège' where id = '50000000-0000-4000-a000-0000000000c1'$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ A', '[P1] liste de tous les clubs', 'refusé', pg_temp.essai($q$select 1 from admin_clubs()$q$)),
 ('CQ A', '[P1] chiffres de la plateforme', 'refusé', pg_temp.essai($q$select 1 from admin_stats()$q$)),
 ('CQ A', '[P1] fusionne des niveaux', 'refusé', pg_temp.essai($q$select admin_fusion_niveau(4, 3)$q$)),
 ('CQ A', '[P1] fiche d''un autre club (membres)', 'refusé', pg_temp.essai($q$select 1 from admin_club_membres('50000000-0000-4000-a000-0000000000b1')$q$)),
 ('CQ A', '[P1] vérifie le club C', '0', pg_temp.essai($q$update clubs set verifie = true where id = '50000000-0000-4000-a000-0000000000c1'$q$));
reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[P1] liste de tous les clubs', 'refusé', pg_temp.essai($q$select 1 from admin_clubs()$q$));
reset role;

-- ============================================================= TABLEAU TACTIQUE (T1)
-- TB1 : tableau de l'équipe A pour le match A (phase « avant »), créé par les données de test.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[T1] voit le tableau de son équipe', '1', pg_temp.essai($q$select 1 from tableaux where id = '70000000-0000-4000-a000-000000000001'$q$)),
 ('Coach A', '[T1] crée un tableau (id du téléphone)', '1', pg_temp.essai($q$insert into tableaux(id, team_id, match_id, phase, etat) values (gen_random_uuid(), '10000000-0000-4000-a000-0000000000a1', '40000000-0000-4000-a000-0000000000a1', 'pause', '{"v":1}')$q$)),
 ('Coach A', '[T1] modifie le tableau (version +1)', '1', pg_temp.essai($q$update tableaux set titre = 'Sortie de balle' where id = '70000000-0000-4000-a000-000000000001' and version = 1$q$)),
 ('Coach A', '[T1] rattache un tableau au match d''une autre équipe', 'refusé', pg_temp.essai($q$insert into tableaux(team_id, match_id, etat) values ('10000000-0000-4000-a000-0000000000a1', '40000000-0000-4000-a000-0000000000b1', '{}')$q$)),
 ('Coach A', '[T1] crée un tableau pour l''équipe B', 'refusé', pg_temp.essai($q$insert into tableaux(team_id, etat) values ('10000000-0000-4000-a000-0000000000b1', '{}')$q$)),
 ('Coach A', '[T1] modèle lié à un match', 'refusé', pg_temp.essai($q$insert into tableaux(team_id, match_id, est_modele, etat) values ('10000000-0000-4000-a000-0000000000a1', '40000000-0000-4000-a000-0000000000a1', true, '{}')$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', '[T1] voit et modifie le tableau', '1', pg_temp.essai($q$update tableaux set titre = 'x' where id = '70000000-0000-4000-a000-000000000001'$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000006","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coord A', '[T1] voit le tableau (équipe de son club)', '1', pg_temp.essai($q$select 1 from tableaux where id = '70000000-0000-4000-a000-000000000001'$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[T1] voit les tableaux', '0', pg_temp.essai($q$select 1 from tableaux$q$)),
 ('Parent A', '[T1] crée un tableau', 'refusé', pg_temp.essai($q$insert into tableaux(team_id, etat) values ('10000000-0000-4000-a000-0000000000a1', '{}')$q$));
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ B', '[T1] voit les tableaux du club A', '0', pg_temp.essai($q$select 1 from tableaux where id = '70000000-0000-4000-a000-000000000001'$q$)),
 ('CQ B', '[T1] modifie un tableau du club A', '0', pg_temp.essai($q$update tableaux set titre = 'pirate' where id = '70000000-0000-4000-a000-000000000001'$q$));
reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[T1] voit des tableaux', '0', pg_temp.essai($q$select 1 from tableaux$q$));
reset role;

-- ============================================================= ACCÈS PARENTS (A3)
-- Parent A = parent de Léo (équipe A). Match A2 à venir, match A terminé.
-- Invitations : « test-invitation-zoe » (valable), « test-invitation-expiree ».
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[A3] voit la fiche de son enfant', '1', pg_temp.essai($q$select 1 from players where id = '30000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A3] voit la fiche d''un autre enfant', '0', pg_temp.essai($q$select 1 from players where id = '30000000-0000-4000-a000-0000000000a2'$q$)),
 ('Parent A', '[A3] voit les joueurs (total)', '1', pg_temp.essai($q$select 1 from players$q$)),
 ('Parent A', '[A3] voit ses liens parent', '1', pg_temp.essai($q$select 1 from parent_enfants$q$)),
 ('Parent A', '[A3] se rattache seul à un autre enfant', 'refusé', pg_temp.essai($q$insert into parent_enfants(player_id, profile_id) values ('30000000-0000-4000-a000-0000000000a2', auth.uid())$q$)),
 ('Parent A', '[A3] voit les invitations', '0', pg_temp.essai($q$select 1 from invitations_parent$q$)),
 ('Parent A', '[A3] répond Présent pour son enfant (match à venir)', '1', pg_temp.essai($q$select parent_repondre('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'present')$q$)),
 ('Parent A', '[A3] répond pour un autre enfant', 'refusé', pg_temp.essai($q$select parent_repondre('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a2', 'absent')$q$)),
 ('Parent A', '[A3] répond pour un match terminé', 'refusé', pg_temp.essai($q$select parent_repondre('40000000-0000-4000-a000-0000000000a1', '30000000-0000-4000-a000-0000000000a1', 'absent')$q$)),
 ('Parent A', '[A3] répond pour un match d''une autre équipe', 'refusé', pg_temp.essai($q$select parent_repondre('40000000-0000-4000-a000-0000000000b1', '30000000-0000-4000-a000-0000000000a1', 'absent')$q$)),
 ('Parent A', '[A3] réponse invalide', 'refusé', pg_temp.essai($q$select parent_repondre('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'peut-etre')$q$)),
 ('Parent A', '[A3] modifie une convocation sans passer par la réponse', '0', pg_temp.essai($q$update convocations set statut = 'absent' where match_id = '40000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A3] prénoms de son équipe', '2', pg_temp.essai($q$select 1 from equipe_prenoms('10000000-0000-4000-a000-0000000000a1')$q$)),
 ('Parent A', '[A3] prénoms d''une autre équipe', '0', pg_temp.essai($q$select 1 from equipe_prenoms('10000000-0000-4000-a000-0000000000b1')$q$)),
 ('Parent A', '[A3] voit les notes', '0', pg_temp.essai($q$select 1 from player_notes$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[A3] voit les invitations de son équipe', '2', pg_temp.essai($q$select 1 from invitations_parent$q$)),
 ('Coach A', '[A3] crée une invitation pour un joueur', '1', pg_temp.essai($q$insert into invitations_parent(player_id) values ('30000000-0000-4000-a000-0000000000a1')$q$)),
 ('Coach A', '[A3] crée une invitation pour un joueur d''une autre équipe', 'refusé', pg_temp.essai($q$insert into invitations_parent(player_id) values ('30000000-0000-4000-a000-0000000000b1')$q$)),
 ('Coach A', '[A3] révoque une invitation', '1', pg_temp.essai($q$update invitations_parent set revoquee = true where token = 'test-invitation-zoe'$q$)),
 ('Coach A', '[A3] voit les parents rattachés', '1', pg_temp.essai($q$select 1 from parent_enfants$q$)),
 ('Coach A', '[A3] retire un parent', '1', pg_temp.essai($q$delete from parent_enfants where player_id = '30000000-0000-4000-a000-0000000000a1'$q$)),
 ('Coach A', '[A3] voit la réponse des parents (colonnes)', '1', pg_temp.essai($q$select reponse_parent, reponse_par, reponse_le from convocations$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ B', '[A3] voit les invitations du club A', '0', pg_temp.essai($q$select 1 from invitations_parent$q$)),
 ('CQ B', '[A3] voit les parents du club A', '0', pg_temp.essai($q$select 1 from parent_enfants$q$)),
 ('CQ B', '[A3] crée une invitation pour l''équipe A', 'refusé', pg_temp.essai($q$insert into invitations_parent(player_id) values ('30000000-0000-4000-a000-0000000000a1')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[A3] infos d''une invitation (équipe, club)', '1', pg_temp.essai($q$select 1 from invitation_info('test-invitation-zoe')$q$)),
 ('Externe', '[A3] rejoint par une invitation valable', '1', pg_temp.essai($q$select 1 from rejoindre_invitation('test-invitation-zoe')$q$)),
 ('Externe', '[A3] rejoint par une invitation expirée', 'refusé', pg_temp.essai($q$select 1 from rejoindre_invitation('test-invitation-expiree')$q$)),
 ('Externe', '[A3] rejoint par une invitation inconnue', 'refusé', pg_temp.essai($q$select 1 from rejoindre_invitation('nimporte-quoi')$q$)),
 ('Externe', '[A3] répond pour un enfant sans lien', 'refusé', pg_temp.essai($q$select parent_repondre('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a2', 'present')$q$)),
 ('Externe', '[A3] prénoms de l''équipe A', '0', pg_temp.essai($q$select 1 from equipe_prenoms('10000000-0000-4000-a000-0000000000a1')$q$));
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[A3] infos d''une invitation', '1', pg_temp.essai($q$select 1 from invitation_info('test-invitation-zoe')$q$)),
 ('Visiteur', '[A3] rejoint par une invitation', 'refusé', pg_temp.essai($q$select 1 from rejoindre_invitation('test-invitation-zoe')$q$)),
 ('Visiteur', '[A3] prénoms d''une équipe', 'refusé', pg_temp.essai($q$select 1 from equipe_prenoms('10000000-0000-4000-a000-0000000000a1')$q$)),
 ('Visiteur', '[A3] voit les liens parent', '0', pg_temp.essai($q$select 1 from parent_enfants$q$));
reset role;

-- ============================================================= MESSAGERIE (A4)
-- Groupe équipe A, discussion de Léo (enfant de Parent A), discussion de Zoé.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[A4] lit le groupe de son équipe', '1', pg_temp.essai($q$select 1 from messages where player_id is null$q$)),
 ('Parent A', '[A4] lit la discussion de son enfant', '1', pg_temp.essai($q$select 1 from messages where player_id = '30000000-0000-4000-a000-0000000000a1'$q$)),
 ('Parent A', '[A4] lit la discussion d''un autre enfant', '0', pg_temp.essai($q$select 1 from messages where player_id = '30000000-0000-4000-a000-0000000000a2'$q$)),
 ('Parent A', '[A4] écrit dans le groupe de son équipe', '1', pg_temp.essai($q$insert into messages(team_id, texte) values ('10000000-0000-4000-a000-0000000000a1', 'Merci !')$q$)),
 ('Parent A', '[A4] écrit dans la discussion de son enfant', '1', pg_temp.essai($q$insert into messages(team_id, player_id, texte) values ('10000000-0000-4000-a000-0000000000a1', '30000000-0000-4000-a000-0000000000a1', 'Bien noté')$q$)),
 ('Parent A', '[A4] écrit dans la discussion d''un autre enfant', 'refusé', pg_temp.essai($q$insert into messages(team_id, player_id, texte) values ('10000000-0000-4000-a000-0000000000a1', '30000000-0000-4000-a000-0000000000a2', 'intrus')$q$)),
 ('Parent A', '[A4] écrit pour un enfant en se trompant d''équipe', 'refusé', pg_temp.essai($q$insert into messages(team_id, player_id, texte) values ('10000000-0000-4000-a000-0000000000b1', '30000000-0000-4000-a000-0000000000a1', 'x')$q$)),
 ('Parent A', '[A4] écrit dans le groupe d''une autre équipe', 'refusé', pg_temp.essai($q$insert into messages(team_id, texte) values ('10000000-0000-4000-a000-0000000000b1', 'intrus')$q$)),
 ('Parent A', '[A4] signe au nom de l''entraîneur (auteur forcé → remplacé)', '1', pg_temp.essai($q$with i as (insert into messages(team_id, texte, auteur) values ('10000000-0000-4000-a000-0000000000a1', 'faux', '00000000-0000-4000-a000-000000000001') returning auteur, auteur_role) select 1 from i where auteur = auth.uid() and auteur_role = 'parent'$q$)),
 ('Parent A', '[A4] message vide', 'refusé', pg_temp.essai($q$insert into messages(team_id, texte) values ('10000000-0000-4000-a000-0000000000a1', '   ')$q$)),
 ('Parent A', '[A4] supprime un message de l''encadrement', '0', pg_temp.essai($q$delete from messages where id = '80000000-0000-4000-a000-000000000001'$q$)),
 ('Parent A', '[A4] modifie un message', '0', pg_temp.essai($q$update messages set texte = 'modifié' where id = '80000000-0000-4000-a000-000000000001'$q$)),
 ('Parent A', '[A4] liste de ses discussions (groupe + Léo)', '2', pg_temp.essai($q$select 1 from mes_fils()$q$)),
 ('Parent A', '[A4] marque une discussion comme lue', '1', pg_temp.essai($q$select marquer_lu('10000000-0000-4000-a000-0000000000a1', '30000000-0000-4000-a000-0000000000a1')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[A4] lit toutes les discussions de son équipe', '3', pg_temp.essai($q$select 1 from messages$q$)),
 ('Coach A', '[A4] écrit aux parents de Zoé', '1', pg_temp.essai($q$insert into messages(team_id, player_id, texte) values ('10000000-0000-4000-a000-0000000000a1', '30000000-0000-4000-a000-0000000000a2', 'Bonjour')$q$)),
 ('Coach A', '[A4] supprime un message (modération)', '1', pg_temp.essai($q$delete from messages where id = '80000000-0000-4000-a000-000000000002'$q$)),
 ('Coach A', '[A4] voit les lectures des autres', '0', pg_temp.essai($q$select 1 from messages_lus where profile_id <> auth.uid()$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000006","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coord A', '[A4] lit les discussions des équipes de son club', '3', pg_temp.essai($q$select 1 from messages$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ B', '[A4] lit les messages du club A', '0', pg_temp.essai($q$select 1 from messages$q$)),
 ('CQ B', '[A4] écrit dans le groupe de l''équipe A', 'refusé', pg_temp.essai($q$insert into messages(team_id, texte) values ('10000000-0000-4000-a000-0000000000a1', 'pub')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[A4] lit des messages', '0', pg_temp.essai($q$select 1 from messages$q$)),
 ('Externe', '[A4] liste de discussions', '0', pg_temp.essai($q$select 1 from mes_fils()$q$));
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[A4] lit des messages', '0', pg_temp.essai($q$select 1 from messages$q$)),
 ('Visiteur', '[A4] liste de discussions', 'refusé', pg_temp.essai($q$select 1 from mes_fils()$q$));
reset role;

-- ============================================================= PROPOSITIONS (C2)
-- P1 : équipe B → annonce AN1 de l'équipe A, envoyée (suggestion « accepter » du délégué A en attente).
-- P2 : équipe B → AN2, préparée « à valider » (pas encore envoyée).
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ B', '[C2] propose un match sur une annonce visible', '1', pg_temp.essai($q$select 1 from (select proposition_creer('60000000-0000-4000-a000-000000000006', '10000000-0000-4000-a000-0000000000b1', current_date + 9, '10:30', 'annonceur', 'Dispo samedi')) x$q$)),
 ('CQ B', '[C2] 2e proposition sur la même annonce', 'refusé', pg_temp.essai($q$select proposition_creer('60000000-0000-4000-a000-000000000001', '10000000-0000-4000-a000-0000000000b1', current_date + 9, '10:30', 'annonceur')$q$)),
 ('CQ B', '[C2] propose pour une équipe qu''il n''encadre pas', 'refusé', pg_temp.essai($q$select proposition_creer('60000000-0000-4000-a000-000000000006', '10000000-0000-4000-a000-0000000000a1', current_date + 9, '10:30', 'annonceur')$q$)),
 ('CQ B', '[C2] propose une date passée', 'refusé', pg_temp.essai($q$select proposition_creer('60000000-0000-4000-a000-000000000006', '10000000-0000-4000-a000-0000000000b1', current_date - 1, '10:30', 'annonceur')$q$)),
 ('CQ B', '[C2] propose un match directement à une équipe (sans annonce)', '1', pg_temp.essai($q$select 1 from (select proposition_directe('10000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000a1', current_date + 12, '14:00', 'proposant', 'Match chez nous ?')) x$q$)),
 ('CQ B', '[C2] directe : 2e proposition même équipe même jour', 'refusé', pg_temp.essai($q$select proposition_directe('10000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000a1', current_date + 12, '15:00', 'proposant') from proposition_directe('10000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000a1', current_date + 12, '14:00', 'proposant')$q$)),
 ('CQ B', '[C2] directe : à une équipe de son propre club', 'refusé', pg_temp.essai($q$select proposition_directe('10000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000b1', current_date + 12, '14:00', 'proposant')$q$)),
 ('CQ B', '[C2] directe : pour une équipe qu''il n''encadre pas', 'refusé', pg_temp.essai($q$select proposition_directe('10000000-0000-4000-a000-0000000000a1', '10000000-0000-4000-a000-0000000000b1', current_date + 12, '14:00', 'proposant')$q$)),
 ('CQ B', '[C2] voit ses propositions (P1, P2)', '2', pg_temp.essai($q$select 1 from propositions$q$)),
 ('CQ B', '[C2] ne voit pas la suggestion en attente de l''autre club', '1', pg_temp.essai($q$select 1 from proposition_tours where proposition_id = '90000000-0000-4000-a000-000000000001'$q$)),
 ('CQ B', '[C2] accepte alors que c''est à l''annonceur de répondre', 'refusé', pg_temp.essai($q$select proposition_agir('90000000-0000-4000-a000-000000000001', 'accepter')$q$)),
 ('CQ B', '[C2] contacts de l''autre club (CQ + coordinateur A)', '2', pg_temp.essai($q$select 1 from proposition_contacts('90000000-0000-4000-a000-000000000001')$q$)),
 ('CQ B', '[C2] envoie la proposition préparée', '1', pg_temp.essai($q$select 1 where proposition_agir('90000000-0000-4000-a000-000000000002', 'envoyer') = 'envoyee'$q$)),
 ('CQ B', '[C2] annule sa proposition', '1', pg_temp.essai($q$select 1 where proposition_agir('90000000-0000-4000-a000-000000000001', 'annuler') = 'annulee'$q$)),
 ('CQ B', '[C2] liste « mes propositions »', '2', pg_temp.essai($q$select 1 from mes_propositions()$q$)),
 ('CQ B', '[C2] écrit un message à l''autre club', '1', pg_temp.essai($q$select 1 from (select proposition_message('90000000-0000-4000-a000-000000000001', 'On peut décaler à 11h ?')) x$q$)),
 ('CQ B', '[C2] message vide', 'refusé', pg_temp.essai($q$select proposition_message('90000000-0000-4000-a000-000000000001', '  ')$q$)),
 ('CQ B', '[C2] message sur une proposition pas encore envoyée', 'refusé', pg_temp.essai($q$select proposition_message('90000000-0000-4000-a000-000000000002', 'x')$q$)),
 ('CQ B', '[C2] marque une proposition comme lue', '1', pg_temp.essai($q$select 1 from (select proposition_lu('90000000-0000-4000-a000-000000000001')) x$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[C2] voit les propositions reçues (pas celle à valider)', '1', pg_temp.essai($q$select 1 from propositions$q$)),
 ('Coach A', '[C2] voit l''historique d''une proposition à valider', '0', pg_temp.essai($q$select 1 from proposition_tours where proposition_id = '90000000-0000-4000-a000-000000000002'$q$)),
 ('Coach A', '[C2] voit l''historique avec la suggestion de son délégué', '2', pg_temp.essai($q$select 1 from proposition_tours where proposition_id = '90000000-0000-4000-a000-000000000001'$q$)),
 ('Coach A', '[C2] accepte : match créé dans son calendrier', '1', pg_temp.essai($q$select 1 where pg_temp.accepter_compter('90000000-0000-4000-a000-000000000001') = 1$q$)),
 ('Coach A', '[C2] contre-propose', '1', pg_temp.essai($q$select 1 where proposition_agir('90000000-0000-4000-a000-000000000001', 'contre', current_date + 14, '11:00', 'proposant', 'Plutôt le 14 ?') = 'contre'$q$)),
 ('Coach A', '[C2] refuse', '1', pg_temp.essai($q$select 1 where proposition_agir('90000000-0000-4000-a000-000000000001', 'refuser') = 'refusee'$q$)),
 ('Coach A', '[C2] envoie une proposition de l''autre club', 'refusé', pg_temp.essai($q$select proposition_agir('90000000-0000-4000-a000-000000000002', 'envoyer')$q$)),
 ('Coach A', '[C2] contacts de l''autre club (CQ B)', '1', pg_temp.essai($q$select 1 from proposition_contacts('90000000-0000-4000-a000-000000000001')$q$)),
 ('Coach A', '[C2] écrit directement dans les propositions', '0', pg_temp.essai($q$update propositions set statut = 'acceptee' where id = '90000000-0000-4000-a000-000000000001'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', '[C2] voit la proposition reçue', '1', pg_temp.essai($q$select 1 from propositions$q$)),
 ('Délégué A', '[C2] accepte → suggestion pour le coordinateur', '1', pg_temp.essai($q$select 1 where proposition_agir('90000000-0000-4000-a000-000000000001', 'accepter') = 'suggestion'$q$)),
 ('Délégué A', '[C2] écrit un message (sans validation)', '1', pg_temp.essai($q$select 1 from (select proposition_message('90000000-0000-4000-a000-000000000001', 'Bonjour')) x$q$)),
 ('Délégué A', '[C2] retire sa propre suggestion', '1', pg_temp.essai($q$select 1 where proposition_agir('90000000-0000-4000-a000-000000000001', 'ecarter_suggestion') = 'ecartee'$q$)),
 ('Délégué A', '[C2] valide une suggestion', 'refusé', pg_temp.essai($q$select proposition_agir('90000000-0000-4000-a000-000000000001', 'valider_suggestion')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000006","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coord A', '[C2] valide la suggestion du délégué (accord)', '1', pg_temp.essai($q$select 1 where proposition_agir('90000000-0000-4000-a000-000000000001', 'valider_suggestion') = 'acceptee'$q$)),
 ('Coord A', '[C2] écarte la suggestion du délégué', '1', pg_temp.essai($q$select 1 where proposition_agir('90000000-0000-4000-a000-000000000001', 'ecarter_suggestion') = 'ecartee'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[C2] voit les propositions', '0', pg_temp.essai($q$select 1 from propositions$q$)),
 ('Parent A', '[C2] accepte une proposition', 'refusé', pg_temp.essai($q$select proposition_agir('90000000-0000-4000-a000-000000000001', 'accepter')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[C2] voit les propositions', '0', pg_temp.essai($q$select 1 from propositions$q$)),
 ('Externe', '[C2] liste « mes propositions »', '0', pg_temp.essai($q$select 1 from mes_propositions()$q$)),
 ('Externe', '[C2] contacts d''une proposition', '0', pg_temp.essai($q$select 1 from proposition_contacts('90000000-0000-4000-a000-000000000001')$q$)),
 ('Externe', '[C2] écrit un message', 'refusé', pg_temp.essai($q$select proposition_message('90000000-0000-4000-a000-000000000001', 'spam')$q$)),
 ('Externe', '[C2] propose un match directement', 'refusé', pg_temp.essai($q$select proposition_directe('10000000-0000-4000-a000-0000000000a1', '10000000-0000-4000-a000-0000000000b1', current_date + 12, '14:00', 'proposant')$q$)),
 ('Externe', '[C2] propose un match', 'refusé', pg_temp.essai($q$select proposition_creer('60000000-0000-4000-a000-000000000001', '10000000-0000-4000-a000-0000000000a1', current_date + 9, '10:30', 'annonceur')$q$));
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[C2] voit les propositions', '0', pg_temp.essai($q$select 1 from propositions$q$)),
 ('Visiteur', '[C2] liste « mes propositions »', 'refusé', pg_temp.essai($q$select 1 from mes_propositions()$q$));
reset role;
-- ===== C6 tournois =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[C6] voit les tournois du club (2)', '2', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Coach A', '[C6] crée un tournoi pour son club', '1', pg_temp.essai($q$insert into tournois (club_id, nom, jour) values ('50000000-0000-4000-a000-0000000000a1', 'Nouveau', current_date)$q$)),
 ('Coach A', '[C6] crée un tournoi pour le club B', 'refusé', pg_temp.essai($q$insert into tournois (club_id, nom, jour) values ('50000000-0000-4000-a000-0000000000b1', 'Pirate', current_date)$q$)),
 ('Coach A', '[C6] ajoute une équipe adverse (nom)', '1', pg_temp.essai($q$insert into tournoi_equipes (tableau_id, nom, poule) values ('a1000000-0000-4000-a000-000000000001', 'Autre FC', 'A')$q$)),
 ('Coach A', '[C6] ajoute une équipe du club B comme « à nous »', 'refusé', pg_temp.essai($q$insert into tournoi_equipes (tableau_id, nom, team_id) values ('a1000000-0000-4000-a000-000000000001', 'X', '10000000-0000-4000-a000-0000000000b1')$q$)),
 ('Coach A', '[C6] modifie l''heure d''un match', '1', pg_temp.essai($q$update tournoi_matchs set heure = '10:00' where id = 'a3000000-0000-4000-a000-000000000001'$q$)),
 ('Coach A', '[C6] saisit un score', '1', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 2, 1, 'termine')) x$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000006","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coord A', '[C6] ajoute un tableau', '1', pg_temp.essai($q$insert into tournoi_tableaux (tournoi_id, nom) values ('a0000000-0000-4000-a000-000000000001', 'U11')$q$)),
 ('Coord A', '[C6] publie / dépublie', '1', pg_temp.essai($q$update tournois set publie = false where id = 'a0000000-0000-4000-a000-000000000001'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', '[C6] voit les tournois du club (2)', '2', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Délégué A', '[C6] voit les matchs du tournoi', '1', pg_temp.essai($q$select 1 from tournoi_matchs$q$)),
 ('Délégué A', '[C6] saisit un score', '1', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 0, 0, 'en_cours')) x$q$)),
 ('Délégué A', '[C6] crée un tournoi', 'refusé', pg_temp.essai($q$insert into tournois (club_id, nom, jour) values ('50000000-0000-4000-a000-0000000000a1', 'X', current_date)$q$)),
 ('Délégué A', '[C6] change l''heure d''un match', '0', pg_temp.essai($q$update tournoi_matchs set heure = '11:00' where id = 'a3000000-0000-4000-a000-000000000001'$q$)),
 ('Délégué A', '[C6] ajoute une équipe', 'refusé', pg_temp.essai($q$insert into tournoi_equipes (tableau_id, nom) values ('a1000000-0000-4000-a000-000000000001', 'X')$q$)),
 ('Délégué A', '[C6] supprime le tournoi', '0', pg_temp.essai($q$delete from tournois where id = 'a0000000-0000-4000-a000-000000000001'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[C6] voit les tournois du club', '2', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Parent A', '[C6] saisit un score', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 5, 0, 'termine')) x$q$)),
 ('Parent A', '[C6] modifie un match', '0', pg_temp.essai($q$update tournoi_matchs set score_a = 9 where id = 'a3000000-0000-4000-a000-000000000001'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach B', '[C6] voit les tournois du club A', '0', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Coach B', '[C6] voit les matchs du club A', '0', pg_temp.essai($q$select 1 from tournoi_matchs$q$)),
 ('Coach B', '[C6] saisit un score au club A', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 0, 9, 'termine')) x$q$)),
 ('Coach B', '[C6] ajoute une équipe au club A', 'refusé', pg_temp.essai($q$insert into tournoi_equipes (tableau_id, nom) values ('a1000000-0000-4000-a000-000000000001', 'X')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[C6] voit des tournois', '0', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Externe', '[C6] saisit un score', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 1, 1, 'termine')) x$q$));
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[C6] lit la table des tournois', '0', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Visiteur', '[C6] page publique d''un tournoi publié', '1', pg_temp.essai($q$select 1 where tournoi_public('a0000000-0000-4000-a000-000000000001') is not null$q$)),
 ('Visiteur', '[C6] page publique : 1 match', '1', pg_temp.essai($q$select 1 from jsonb_array_elements(tournoi_public('a0000000-0000-4000-a000-000000000001')->'tableaux') tb, jsonb_array_elements(tb->'matchs') m$q$)),
 ('Visiteur', '[C6] page publique d''un tournoi non publié', '0', pg_temp.essai($q$select 1 where tournoi_public('a0000000-0000-4000-a000-000000000002') is not null$q$)),
 ('Visiteur', '[C6] saisit un score', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 1, 1, 'termine')) x$q$));
reset role;
select set_config('request.jwt.claims', '', false);

select n, qui, test, attendu, obtenu, case when attendu = obtenu then 'OK' else 'ÉCHEC' end as resultat
from r order by n;
