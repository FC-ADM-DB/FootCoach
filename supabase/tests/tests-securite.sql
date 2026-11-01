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

-- C6 : saisit un score puis renvoie l'état de confirmation « a=…,b=… » (requête suivante)
create or replace function pg_temp.score_confirmation(p_m uuid, p_cote text) returns text language plpgsql as $f$
declare r text;
begin
  perform public.tournoi_score(p_m, 1, 0, 'termine', null, p_cote);
  select 'a=' || confirme_a || ',b=' || confirme_b into r from public.tournoi_matchs where id = p_m;
  return r;
end $f$;
-- C6 : désistement puis acceptation d'une autre équipe → « libres=… » du tableau
create or replace function pg_temp.desister_puis_accepter(p_des uuid, p_acc uuid) returns text language plpgsql as $f$
declare tb uuid; r text;
begin
  select tableau_id into tb from public.tournoi_inscriptions where id = p_des;
  perform public.tournoi_inscription_agir(p_des, 'desister');
  select 'libres=' || count(*) filter (where libre) into r from public.tournoi_equipes where tableau_id = tb;
  perform public.tournoi_inscription_agir(p_acc, 'accepter');
  select r || ' puis libres=' || count(*) filter (where libre) || ',equipes=' || count(*) into r from public.tournoi_equipes where tableau_id = tb;
  return r;
end $f$;

-- C3 : destinataires (3 derniers caractères de l'id, triés) des e-mails « type » déposés
-- par l'action q dans CETTE transaction, encore à envoyer ; l'action est ensuite annulée.
create or replace function pg_temp.notif_dest(t text) returns text language sql security definer as $f$
  select coalesce(string_agg(right(profile_id::text, 3), ',' order by profile_id), 'aucun')
  from public.notifications where created_at = now() and type = t and statut = 'a_envoyer' $f$;
create or replace function pg_temp.notif_test(q text, t text) returns text language plpgsql as $f$
declare r text;
begin
  execute q;
  r := pg_temp.notif_dest(t);
  raise exception 'RES:%', r;
exception when others then
  if sqlerrm like 'RES:%' then return substr(sqlerrm, 5); end if;
  return 'erreur: ' || sqlerrm;
end $f$;
-- C3 : l'e-mail de convocation est bien différé (envoyé dans ~10 minutes)
create or replace function pg_temp.notif_differe(q text) returns text language plpgsql security definer as $f$
declare r text;
begin
  execute q;
  select case when min(envoyer_apres) > now() + interval '9 minutes' then 'differe' else 'immediat' end into r
    from public.notifications where created_at = now() and type = 'convocation' and statut = 'a_envoyer';
  raise exception 'RES:%', coalesce(r, 'aucun');
exception when others then
  if sqlerrm like 'RES:%' then return substr(sqlerrm, 5); end if;
  return 'erreur: ' || sqlerrm;
end $f$;

-- A5 : accepte une demande puis vérifie l'accès réellement donné (requête suivante)
create or replace function pg_temp.accepter_verifier(p_d uuid, p_joueur uuid, p_verif text) returns text language plpgsql security definer as $f$
declare n bigint;
begin
  perform public.demande_traiter(p_d, 'accepter', p_joueur);
  execute p_verif into n;
  return n::text;
end $f$;

-- C5 : adresses externes des e-mails « type » déposés par q dans cette transaction
create or replace function pg_temp.notif_ext(q text, t text) returns text language plpgsql as $f$
declare r text;
begin
  execute q;
  select coalesce(string_agg(email_externe, ',' order by email_externe), 'aucun') into r
    from public.notifications where created_at = now() and type = t and profile_id is null;
  raise exception 'RES:%', r;
exception when others then
  if sqlerrm like 'RES:%' then return substr(sqlerrm, 5); end if;
  return 'erreur: ' || sqlerrm;
end $f$;
-- C5 : la lecture des e-mails externes exige les droits du propriétaire (file privée)
alter function pg_temp.notif_ext(text, text) security definer;

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
 ('Coach A', '[C6] ajoute directement une équipe du club B', 'refusé', pg_temp.essai($q$insert into tournoi_equipes (tableau_id, nom, team_id) values ('a1000000-0000-4000-a000-000000000001', 'X', '10000000-0000-4000-a000-0000000000b1')$q$)),
 ('Coach A', '[C6] modifie l''heure d''un match', '1', pg_temp.essai($q$update tournoi_matchs set heure = '10:00' where id = 'a3000000-0000-4000-a000-000000000001'$q$)),
 ('Coach A', '[C6] saisit un score (table de marque)', '1', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 2, 1, 'termine', null, null)) x$q$)),
 ('Coach A', '[C6] score table de marque = confirmé des deux côtés', '1', pg_temp.essai($q$select 1 where pg_temp.score_confirmation('a3000000-0000-4000-a000-000000000002', null) = 'a=true,b=true'$q$)),
 ('Coach A', '[C6] voit les inscriptions de son tournoi (3)', '3', pg_temp.essai($q$select 1 from tournoi_inscriptions$q$)),
 ('Coach A', '[C6] accepte l''inscription du club B', '1', pg_temp.essai($q$select 1 where tournoi_inscription_agir('a4000000-0000-4000-a000-000000000001', 'accepter') = 'acceptee'$q$)),
 ('Coach A', '[C6] refuse l''inscription du club B', '1', pg_temp.essai($q$select 1 where tournoi_inscription_agir('a4000000-0000-4000-a000-000000000001', 'refuser') = 'refusee'$q$)),
 ('Coach A', '[C6] accepte une inscription « à valider »', 'refusé', pg_temp.essai($q$select 1 where tournoi_inscription_agir('a4000000-0000-4000-a000-000000000002', 'accepter') = 'acceptee'$q$)),
 ('Coach A', '[C6] désistement puis nouvelle équipe : place reprise', '1', pg_temp.essai($q$select 1 where pg_temp.desister_puis_accepter('a4000000-0000-4000-a000-000000000003', 'a4000000-0000-4000-a000-000000000001') = 'libres=1 puis libres=0,equipes=3'$q$)),
 ('Coach A', '[C6] écrit un message sur une inscription', '1', pg_temp.essai($q$select 1 from (select tournoi_message('a4000000-0000-4000-a000-000000000001', 'Bienvenue')) x$q$)),
 ('Coach A', '[C6] inscrit son équipe à son propre tournoi', 'refusé', pg_temp.essai($q$select tournoi_inscrire('a1000000-0000-4000-a000-000000000004', '10000000-0000-4000-a000-0000000000a1')$q$)),
 ('Coach A', '[C6] voit son tournoi dans les annonces', '0', pg_temp.essai($q$select 1 from tournois_reseau()$q$)),
 ('Coach A', '[C6] « mes inscriptions » : 1 à traiter', '1', pg_temp.essai($q$select 1 from mes_inscriptions() where a_traiter$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000006","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coord A', '[C6] ajoute un tableau', '1', pg_temp.essai($q$insert into tournoi_tableaux (tournoi_id, nom) values ('a0000000-0000-4000-a000-000000000001', 'U13')$q$)),
 ('Coord A', '[C6] publie / dépublie', '1', pg_temp.essai($q$update tournois set publie = false where id = 'a0000000-0000-4000-a000-000000000001'$q$)),
 ('Coord A', '[C6] invite un club (zone clubs)', '1', pg_temp.essai($q$insert into tournoi_cibles (tournoi_id, club_id) values ('a0000000-0000-4000-a000-000000000001', '50000000-0000-4000-a000-0000000000b1')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', '[C6] voit les tournois du club (2)', '2', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Délégué A', '[C6] voit les matchs du tournoi', '2', pg_temp.essai($q$select 1 from tournoi_matchs$q$)),
 ('Délégué A', '[C6] saisit un score (table de marque)', '1', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 0, 0, 'en_cours', null, null)) x$q$)),
 ('Délégué A', '[C6] crée un tournoi', 'refusé', pg_temp.essai($q$insert into tournois (club_id, nom, jour) values ('50000000-0000-4000-a000-0000000000a1', 'X', current_date)$q$)),
 ('Délégué A', '[C6] change l''heure d''un match', '0', pg_temp.essai($q$update tournoi_matchs set heure = '11:00' where id = 'a3000000-0000-4000-a000-000000000001'$q$)),
 ('Délégué A', '[C6] ajoute une équipe', 'refusé', pg_temp.essai($q$insert into tournoi_equipes (tableau_id, nom) values ('a1000000-0000-4000-a000-000000000001', 'X')$q$)),
 ('Délégué A', '[C6] supprime le tournoi', '0', pg_temp.essai($q$delete from tournois where id = 'a0000000-0000-4000-a000-000000000001'$q$)),
 ('Délégué A', '[C6] voit les inscriptions', '0', pg_temp.essai($q$select 1 from tournoi_inscriptions$q$)),
 ('Délégué A', '[C6] accepte une inscription', 'refusé', pg_temp.essai($q$select 1 where tournoi_inscription_agir('a4000000-0000-4000-a000-000000000001', 'accepter') = 'acceptee'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach B', '[C6] voit l''annonce du tournoi (réseau)', '1', pg_temp.essai($q$select 1 from tournois_reseau()$q$)),
 ('Coach B', '[C6] liste les clubs du réseau (3 vérifiés)', '3', pg_temp.essai($q$select 1 from clubs_reseau()$q$)),
 ('Coach B', '[C6] l''annonce donne les places (U10 : 3 / 4)', '1', pg_temp.essai($q$select 1 from tournois_reseau() t, jsonb_array_elements(t.tableaux) tb where tb->>'nom' = 'U10' and (tb->>'prises')::int = 3 and (tb->>'places')::int = 4$q$)),
 ('Coach B', '[C6] lit les tables du tournoi (pas encore accepté)', '0', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Coach B', '[C6] voit ses inscriptions (2)', '2', pg_temp.essai($q$select 1 from tournoi_inscriptions$q$)),
 ('Coach B', '[C6] inscrit son équipe (U12)', '1', pg_temp.essai($q$select 1 where tournoi_inscrire('a1000000-0000-4000-a000-000000000004', '10000000-0000-4000-a000-0000000000b1') is not null$q$)),
 ('Coach B', '[C6] inscrit dans une catégorie complète', 'refusé', pg_temp.essai($q$select tournoi_inscrire('a1000000-0000-4000-a000-000000000003', '10000000-0000-4000-a000-0000000000b1')$q$)),
 ('Coach B', '[C6] inscrit une équipe d''un autre club', 'refusé', pg_temp.essai($q$select tournoi_inscrire('a1000000-0000-4000-a000-000000000004', '10000000-0000-4000-a000-0000000000a1')$q$)),
 ('Coach B', '[C6] inscrit deux fois la même équipe', 'refusé', pg_temp.essai($q$select tournoi_inscrire('a1000000-0000-4000-a000-000000000001', '10000000-0000-4000-a000-0000000000b1')$q$)),
 ('Coach B', '[C6] envoie l''inscription « à valider »', '1', pg_temp.essai($q$select 1 where tournoi_inscription_agir('a4000000-0000-4000-a000-000000000002', 'envoyer') = 'envoyee'$q$)),
 ('Coach B', '[C6] annule son inscription envoyée', '1', pg_temp.essai($q$select 1 where tournoi_inscription_agir('a4000000-0000-4000-a000-000000000001', 'annuler') = 'annulee'$q$)),
 ('Coach B', '[C6] accepte sa propre inscription', 'refusé', pg_temp.essai($q$select 1 where tournoi_inscription_agir('a4000000-0000-4000-a000-000000000001', 'accepter') = 'acceptee'$q$)),
 ('Coach B', '[C6] écrit un message sur son inscription', '1', pg_temp.essai($q$select 1 from (select tournoi_message('a4000000-0000-4000-a000-000000000001', 'On arrive à 9h')) x$q$)),
 ('Coach B', '[C6] écrit sur l''inscription d''un autre club', 'refusé', pg_temp.essai($q$select tournoi_message('a4000000-0000-4000-a000-000000000003', 'spam')$q$)),
 ('Coach B', '[C6] saisit un score (pas inscrit)', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 0, 9, 'termine', null, 'b')) x$q$)),
 ('Coach B', '[C6] inscrit au tournoi brouillon', 'refusé', pg_temp.essai($q$select tournoi_inscrire((select id from tournoi_tableaux where tournoi_id = 'a0000000-0000-4000-a000-000000000002' limit 1), '10000000-0000-4000-a000-0000000000b1')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000008","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ C', '[C6] lit le tournoi (inscription acceptée)', '1', pg_temp.essai($q$select 1 from tournois$q$)),
 ('CQ C', '[C6] voit les matchs du tournoi', '2', pg_temp.essai($q$select 1 from tournoi_matchs$q$)),
 ('CQ C', '[C6] saisit le score de son match (côté b)', '1', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000002', 0, 2, 'termine', null, 'b')) x$q$)),
 ('CQ C', '[C6] score saisi côté b : à confirmer par A', '1', pg_temp.essai($q$select 1 where pg_temp.score_confirmation('a3000000-0000-4000-a000-000000000002', 'b') = 'a=false,b=true'$q$)),
 ('CQ C', '[C6] saisit en se disant côté a', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000002', 0, 2, 'termine', null, 'a')) x$q$)),
 ('CQ C', '[C6] saisit un match où il ne joue pas', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 0, 2, 'termine', null, 'b')) x$q$)),
 ('CQ C', '[C6] saisit sans côté (table de marque)', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000002', 0, 2, 'termine', null, null)) x$q$)),
 ('CQ C', '[C6] confirme le score côté b', '1', pg_temp.essai($q$select 1 from (select tournoi_score_confirmer('a3000000-0000-4000-a000-000000000002', 'b')) x$q$)),
 ('CQ C', '[C6] confirme à la place de l''équipe A', 'refusé', pg_temp.essai($q$select tournoi_score_confirmer('a3000000-0000-4000-a000-000000000002', 'a')$q$)),
 ('CQ C', '[C6] se désiste', '1', pg_temp.essai($q$select 1 where tournoi_inscription_agir('a4000000-0000-4000-a000-000000000003', 'desister') = 'desistee'$q$)),
 ('CQ C', '[C6] modifie un match directement', '0', pg_temp.essai($q$update tournoi_matchs set score_a = 9 where id = 'a3000000-0000-4000-a000-000000000002'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[C6] confirme le score côté a (son équipe)', '1', pg_temp.essai($q$select 1 from (select tournoi_score_confirmer('a3000000-0000-4000-a000-000000000002', 'a')) x$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[C6] voit les tournois du club', '2', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Parent A', '[C6] saisit un score', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 5, 0, 'termine', null, null)) x$q$)),
 ('Parent A', '[C6] modifie un match', '0', pg_temp.essai($q$update tournoi_matchs set score_a = 9 where id = 'a3000000-0000-4000-a000-000000000001'$q$)),
 ('Parent A', '[C6] voit les inscriptions', '0', pg_temp.essai($q$select 1 from tournoi_inscriptions$q$)),
 ('Parent A', '[C6] voit les annonces de tournoi', '0', pg_temp.essai($q$select 1 from tournois_reseau()$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[C6] voit des tournois', '0', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Externe', '[C6] voit les annonces de tournoi', '0', pg_temp.essai($q$select 1 from tournois_reseau()$q$)),
 ('Externe', '[C6] liste les clubs du réseau', '0', pg_temp.essai($q$select 1 from clubs_reseau()$q$)),
 ('Externe', '[C6] voit des inscriptions', '0', pg_temp.essai($q$select 1 from mes_inscriptions()$q$)),
 ('Externe', '[C6] inscrit une équipe', 'refusé', pg_temp.essai($q$select tournoi_inscrire('a1000000-0000-4000-a000-000000000004', '10000000-0000-4000-a000-0000000000b1')$q$)),
 ('Externe', '[C6] saisit un score', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 1, 1, 'termine', null, null)) x$q$));
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[C6] lit la table des tournois', '0', pg_temp.essai($q$select 1 from tournois$q$)),
 ('Visiteur', '[C6] page publique d''un tournoi publié', '1', pg_temp.essai($q$select 1 where tournoi_public('a0000000-0000-4000-a000-000000000001') is not null$q$)),
 ('Visiteur', '[C6] page publique : 2 matchs', '2', pg_temp.essai($q$select 1 from jsonb_array_elements(tournoi_public('a0000000-0000-4000-a000-000000000001')->'tableaux') tb, jsonb_array_elements(tb->'matchs') m$q$)),
 ('Visiteur', '[C6] page publique d''un tournoi non publié', '0', pg_temp.essai($q$select 1 where tournoi_public('a0000000-0000-4000-a000-000000000002') is not null$q$)),
 ('Visiteur', '[C6] annonces de tournoi', 'refusé', pg_temp.essai($q$select 1 from tournois_reseau()$q$)),
 ('Visiteur', '[C6] inscriptions', 'refusé', pg_temp.essai($q$select 1 from mes_inscriptions()$q$)),
 ('Visiteur', '[C6] saisit un score', 'refusé', pg_temp.essai($q$select 1 from (select tournoi_score('a3000000-0000-4000-a000-000000000001', 1, 1, 'termine', null, null)) x$q$));
reset role;
-- ===== C3 notifications =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach B', '[C3] proposition directe envoyée → club et équipe A (CQ, coordinatrice, délégué)', '001,002,006', pg_temp.notif_test($q$select proposition_directe('10000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000a1', current_date + 15, '10:00', 'proposant', 'Salut')$q$, 'prop_recue')),
 ('Coach B', '[C3] inscription au tournoi → organisateur (CQ et coordinatrice A)', '001,006', pg_temp.notif_test($q$select tournoi_inscrire('a1000000-0000-4000-a000-000000000004', '10000000-0000-4000-a000-0000000000b1')$q$, 'ins_recue')),
 ('Coach B', '[C3] message sur son inscription → organisateur', '001,006', pg_temp.notif_test($q$select tournoi_message('a4000000-0000-4000-a000-000000000001', 'Bonjour')$q$, 'ins_message'));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', '[C3] message sur une proposition → club et équipe B', '003', pg_temp.notif_test($q$select proposition_message('90000000-0000-4000-a000-000000000001', 'On confirme ?')$q$, 'prop_message')),
 ('Délégué A', '[C3] suggère d''accepter → CQ et coordinatrice A', '001,006', pg_temp.notif_test($q$select proposition_agir('90000000-0000-4000-a000-000000000001', 'accepter')$q$, 'prop_suggestion')),
 ('Délégué A', '[C3] prépare une proposition → CQ et coordinatrice A (à envoyer)', '001,006', pg_temp.notif_test($q$select proposition_directe('10000000-0000-4000-a000-0000000000a1', '10000000-0000-4000-a000-0000000000b1', current_date + 16, '10:00', 'annonceur')$q$, 'prop_a_envoyer'));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[C3] accepte une proposition → tout le monde sauf lui', '002,003,006', pg_temp.notif_test($q$select proposition_agir('90000000-0000-4000-a000-000000000001', 'accepter')$q$, 'prop_acceptee')),
 ('Coach A', '[C3] refuse une proposition → club B', '003', pg_temp.notif_test($q$select proposition_agir('90000000-0000-4000-a000-000000000001', 'refuser')$q$, 'prop_refusee')),
 ('Coach A', '[C3] contre-proposition → club B', '003', pg_temp.notif_test($q$select proposition_agir('90000000-0000-4000-a000-000000000001', 'contre', current_date + 20, '11:00', 'annonceur')$q$, 'prop_contre')),
 ('Coach A', '[C3] accepte une inscription → club B', '003', pg_temp.notif_test($q$select tournoi_inscription_agir('a4000000-0000-4000-a000-000000000001', 'accepter')$q$, 'ins_acceptee')),
 ('Coach A', '[C3] retire une équipe inscrite → club C', '008', pg_temp.notif_test($q$select tournoi_inscription_agir('a4000000-0000-4000-a000-000000000003', 'desister')$q$, 'ins_desistee')),
 ('Coach A', '[C3] convoque un enfant → son parent', '007', pg_temp.notif_test($q$insert into convocations (match_id, player_id, statut) values ('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'present') on conflict (match_id, player_id) do update set statut = 'present'$q$, 'convocation')),
 ('Coach A', '[C3] convocation envoyée 10 minutes plus tard', '1', pg_temp.essai($q$select 1 where pg_temp.notif_differe($c$insert into convocations (match_id, player_id, statut) values ('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'present') on conflict (match_id, player_id) do update set statut = 'present'$c$) = 'differe'$q$)),
 ('Coach A', '[C3] convoque puis décoche → aucun e-mail', 'aucun', pg_temp.notif_test($q$insert into convocations (match_id, player_id, statut) values ('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'present') on conflict (match_id, player_id) do update set statut = 'present'; insert into convocations (match_id, player_id, statut) values ('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'absent') on conflict (match_id, player_id) do update set statut = 'absent'$q$, 'convocation')),
 ('Coach A', '[C3] convoque deux fois → un seul e-mail', '007', pg_temp.notif_test($q$insert into convocations (match_id, player_id, statut) values ('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'present') on conflict (match_id, player_id) do update set statut = 'present'; insert into convocations (match_id, player_id, statut) values ('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'incertain') on conflict (match_id, player_id) do update set statut = 'incertain'; insert into convocations (match_id, player_id, statut) values ('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'present') on conflict (match_id, player_id) do update set statut = 'present'$q$, 'convocation')),
 ('Coach A', '[C3] ne voit que ses propres notifications', '0', pg_temp.essai($q$select 1 from notifications where profile_id <> auth.uid()$q$)),
 ('Coach A', '[C3] dépose un e-mail lui-même', 'refusé', pg_temp.essai($q$insert into notifications (profile_id, type, titre, texte) values ('00000000-0000-4000-a000-000000000007', 'x', 'x', 'x')$q$)),
 ('Coach A', '[C3] appelle notif_ajouter', 'refusé', pg_temp.essai($q$select notif_ajouter(array['00000000-0000-4000-a000-000000000007'::uuid], 'x', 'x', 'x')$q$)),
 ('Coach A', '[C3] réserve la file d''envoi', 'refusé', pg_temp.essai($q$select * from notif_reserver(10)$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000008","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('CQ C', '[C3] se désiste → organisateur', '001,006', pg_temp.notif_test($q$select tournoi_inscription_agir('a4000000-0000-4000-a000-000000000003', 'desister')$q$, 'ins_desistee'));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[C3] voit sa notification seulement', '1', pg_temp.essai($q$select 1 from notifications$q$)),
 ('Parent A', '[C3] répond à une convocation → aucun e-mail', 'aucun', pg_temp.notif_test($q$select parent_repondre('40000000-0000-4000-a000-0000000000a2', '30000000-0000-4000-a000-0000000000a1', 'absent')$q$, 'convocation')),
 ('Parent A', '[C3] coupe ses e-mails dans son profil', '1', pg_temp.essai($q$update profiles set notif_email = false where id = '00000000-0000-4000-a000-000000000007'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[C3] voit des notifications', '0', pg_temp.essai($q$select 1 from notifications$q$)),
 ('Externe', '[C3] lit la configuration', '0', pg_temp.essai($q$select 1 from app_config$q$));
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[C3] voit des notifications', '0', pg_temp.essai($q$select 1 from notifications$q$)),
 ('Visiteur', '[C3] réserve la file d''envoi', 'refusé', pg_temp.essai($q$select * from notif_reserver(10)$q$));
reset role;
update public.profiles set notif_email = false where id = '00000000-0000-4000-a000-000000000006';
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach B', '[C3] e-mails coupés par la coordinatrice → plus rien pour elle', '001,002', pg_temp.notif_test($q$select proposition_directe('10000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000a1', current_date + 17, '10:00', 'proposant')$q$, 'prop_recue'));
reset role;
update public.profiles set notif_email = true where id = '00000000-0000-4000-a000-000000000006';
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[C3] crée un club → e-mail à l''admin plateforme', '005', pg_temp.notif_test($q$select create_club('TEST Club nouveau')$q$, 'club_a_verifier'));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000005","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Admin', '[C3] crée un club lui-même → pas d''e-mail', 'aucun', pg_temp.notif_test($q$select create_club('TEST Club admin')$q$, 'club_a_verifier'));
reset role;
-- ===== A5 demandes =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[A5] voit ses demandes (3)', '3', pg_temp.essai($q$select 1 from demandes_acces$q$)),
 ('Externe', '[A5] annuaire : clubs vérifiés (A, B, REH)', '3', pg_temp.essai($q$select 1 from annuaire_clubs()$q$)),
 ('Externe', '[A5] demande à être délégué de l''équipe A', '1', pg_temp.essai($q$select 1 where demande_creer('50000000-0000-4000-a000-0000000000a1', 'delegue', '10000000-0000-4000-a000-0000000000a1') is not null$q$)),
 ('Externe', '[A5] demande la même chose deux fois', 'refusé', pg_temp.essai($q$select demande_creer('50000000-0000-4000-a000-0000000000a1', 'entraineur', '10000000-0000-4000-a000-0000000000a1')$q$)),
 ('Externe', '[A5] demande dans un club non vérifié', 'refusé', pg_temp.essai($q$select demande_creer('50000000-0000-4000-a000-0000000000c1', 'coordinateur')$q$)),
 ('Externe', '[A5] demande une équipe d''un autre club', 'refusé', pg_temp.essai($q$select demande_creer('50000000-0000-4000-a000-0000000000a1', 'entraineur', '10000000-0000-4000-a000-0000000000b1')$q$)),
 ('Externe', '[A5] demande parent sans prénom d''enfant', 'refusé', pg_temp.essai($q$select demande_creer('50000000-0000-4000-a000-0000000000a1', 'parent', '10000000-0000-4000-a000-0000000000a1')$q$)),
 ('Externe', '[A5] accepte sa propre demande', 'refusé', pg_temp.essai($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000001', 'accepter') = 'acceptee'$q$)),
 ('Externe', '[A5] annule sa demande', '1', pg_temp.essai($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000001', 'annuler') = 'annulee'$q$)),
 ('Externe', '[A5] lit l''effectif après sa demande parent', '0', pg_temp.essai($q$select 1 from players$q$)),
 ('Externe', '[A5] demande d''équipe → club A + encadrement de l''équipe', '001,002,006', pg_temp.notif_test($q$select demande_creer('50000000-0000-4000-a000-0000000000a1', 'delegue', '10000000-0000-4000-a000-0000000000a1', null, 'Bonjour')$q$, 'acces_demande')),
 ('Externe', '[A5] demande de coordinateur → club A seulement', '001,006', pg_temp.notif_test($q$select demande_traiter('b0000000-0000-4000-a000-000000000001', 'annuler'); select demande_creer('50000000-0000-4000-a000-0000000000a1', 'coordinateur', null, null, 'Je rejoins le comité')$q$, 'acces_demande'));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[A5] voit les 3 demandes à valider', '3', pg_temp.essai($q$select 1 from demandes_acces$q$)),
 ('Coach A', '[A5] accepte le coordinateur → membre du club', '1', pg_temp.essai($q$select 1 where pg_temp.accepter_verifier('b0000000-0000-4000-a000-000000000001', null, $v$select count(*) from club_members where club_id = '50000000-0000-4000-a000-0000000000a1' and profile_id = '00000000-0000-4000-a000-000000000004' and role = 'coordinateur'$v$) = '1'$q$)),
 ('Coach A', '[A5] accepte l''entraîneur → membre de l''équipe', '1', pg_temp.essai($q$select 1 where pg_temp.accepter_verifier('b0000000-0000-4000-a000-000000000002', null, $v$select count(*) from team_members where team_id = '10000000-0000-4000-a000-0000000000a1' and profile_id = '00000000-0000-4000-a000-000000000004' and role = 'entraineur'$v$) = '1'$q$)),
 ('Coach A', '[A5] accepte le parent avec Léo → relié à Léo', '1', pg_temp.essai($q$select 1 where pg_temp.accepter_verifier('b0000000-0000-4000-a000-000000000003', '30000000-0000-4000-a000-0000000000a1', $v$select count(*) from parent_enfants where player_id = '30000000-0000-4000-a000-0000000000a1' and profile_id = '00000000-0000-4000-a000-000000000004'$v$) = '1'$q$)),
 ('Coach A', '[A5] accepte le parent sans choisir l''enfant', 'refusé', pg_temp.essai($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000003', 'accepter') = 'acceptee'$q$)),
 ('Coach A', '[A5] accepte le parent avec un enfant d''une autre équipe', 'refusé', pg_temp.essai($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000003', 'accepter', '30000000-0000-4000-a000-0000000000b1') = 'acceptee'$q$)),
 ('Coach A', '[A5] refuse une demande', '1', pg_temp.essai($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000002', 'refuser', null, 'Équipe complète') = 'refusee'$q$)),
 ('Coach A', '[A5] acceptation → e-mail au demandeur', '004', pg_temp.notif_test($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000002', 'accepter') = 'acceptee'$q$, 'acces_accepte')),
 ('Coach A', '[A5] refus → e-mail au demandeur', '004', pg_temp.notif_test($q$select demande_traiter('b0000000-0000-4000-a000-000000000002', 'refuser')$q$, 'acces_refuse'));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', '[A5] voit les demandes de son équipe (pas le coordinateur)', '2', pg_temp.essai($q$select 1 from demandes_acces$q$)),
 ('Délégué A', '[A5] accepte l''entraîneur de son équipe', '1', pg_temp.essai($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000002', 'accepter') = 'acceptee'$q$)),
 ('Délégué A', '[A5] accepte un coordinateur', 'refusé', pg_temp.essai($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000001', 'accepter') = 'acceptee'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach B', '[A5] voit les demandes du club A', '0', pg_temp.essai($q$select 1 from demandes_acces$q$)),
 ('Coach B', '[A5] accepte une demande du club A', 'refusé', pg_temp.essai($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000002', 'accepter') = 'acceptee'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[A5] voit les demandes', '0', pg_temp.essai($q$select 1 from demandes_acces$q$)),
 ('Parent A', '[A5] accepte une demande', 'refusé', pg_temp.essai($q$select 1 where demande_traiter('b0000000-0000-4000-a000-000000000003', 'accepter', '30000000-0000-4000-a000-0000000000a1') = 'acceptee'$q$));
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[A5] voit les demandes', '0', pg_temp.essai($q$select 1 from demandes_acces$q$)),
 ('Visiteur', '[A5] annuaire des clubs', 'refusé', pg_temp.essai($q$select 1 from annuaire_clubs()$q$)),
 ('Visiteur', '[A5] crée une demande', 'refusé', pg_temp.essai($q$select demande_creer('50000000-0000-4000-a000-0000000000a1', 'coordinateur')$q$));
reset role;
-- ===== C5 clubs sans compte =====
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
insert into r (qui, test, attendu, obtenu) values
 ('Visiteur', '[C5] voit la proposition avec le lien', '1', pg_temp.essai($q$select 1 where invitation_match_voir('test-im-envoyee') is not null$q$)),
 ('Visiteur', '[C5] lien inconnu', '0', pg_temp.essai($q$select 1 where invitation_match_voir('mauvais-lien') is not null$q$)),
 ('Visiteur', '[C5] lit la table des propositions par e-mail', '0', pg_temp.essai($q$select 1 from invitations_match$q$)),
 ('Visiteur', '[C5] accepte avec le lien', '1', pg_temp.essai($q$select 1 where invitation_match_repondre('test-im-envoyee', 'accepter', null, null, null, 'OK pour nous', 'Paul', '0470 00 00 00') = 'acceptee'$q$)),
 ('Visiteur', '[C5] acceptation → e-mail au club (CQ, coordinatrice, délégué)', '001,002,006', pg_temp.notif_test($q$select invitation_match_repondre('test-im-envoyee', 'accepter')$q$, 'im_acceptee')),
 ('Visiteur', '[C5] autre date → e-mail au club', '001,002,006', pg_temp.notif_test($q$select invitation_match_repondre('test-im-envoyee', 'contre', current_date + 21, '15:00', 'eux', 'Plutôt le dimanche')$q$, 'im_contre')),
 ('Visiteur', '[C5] répond à une proposition déjà en contre-proposition', 'refusé', pg_temp.essai($q$select invitation_match_repondre('test-im-contre', 'accepter')$q$)),
 ('Visiteur', '[C5] répond avec un lien inconnu', 'refusé', pg_temp.essai($q$select invitation_match_repondre('mauvais-lien', 'accepter')$q$)),
 ('Visiteur', '[C5] infos de l''invitation à rejoindre', '1', pg_temp.essai($q$select 1 where invitation_club_info('test-ic') is not null$q$)),
 ('Visiteur', '[C5] crée une proposition', 'refusé', pg_temp.essai($q$select invitation_match_creer('10000000-0000-4000-a000-0000000000a1', 'FC Nouveau', 'U10', 'coach@exemple.invalid', 'Marc', current_date + 20, '10:00', 'nous', 'Bonjour')$q$)),
 ('Visiteur', '[C5] invite un club', 'refusé', pg_temp.essai($q$select invitation_club_creer('50000000-0000-4000-a000-0000000000a1', 'x@exemple.invalid')$q$)),
 ('Visiteur', '[C5] voit l''annonce partagée (lien public)', '1', pg_temp.essai($q$select 1 where annonce_publique('test-annonce') is not null$q$)),
 ('Visiteur', '[C5] annonce partagée : 1 créneau libre', '1', pg_temp.essai($q$select 1 from jsonb_array_elements(annonce_publique('test-annonce')->'creneaux')$q$)),
 ('Visiteur', '[C5] annonce : lien inconnu', '0', pg_temp.essai($q$select 1 where annonce_publique('mauvais') is not null$q$)),
 ('Visiteur', '[C5] répond à l''annonce partagée', '1', pg_temp.essai($q$select 1 where (select annonce_repondre_public('test-annonce', current_date + 7, '10:00', 'nous', 'FC Facebook', 'U10', 'fb@exemple.invalid', 'Lou', '0470 00 00 01', 'Partant !')) = 'envoyee'$q$)),
 ('Visiteur', '[C5] réponse à l''annonce → e-mail au club et à l''équipe', '001,002,006', pg_temp.notif_test($q$select annonce_repondre_public('test-annonce', current_date + 7, '10:00', 'nous', 'FC Facebook', 'U10', 'fb@exemple.invalid', 'Lou', '0470 00 00 01', 'Partant !')$q$, 'im_annonce')),
 ('Visiteur', '[C5] répond pour un jour hors créneaux', 'refusé', pg_temp.essai($q$select annonce_repondre_public('test-annonce', current_date + 8, '10:00', 'nous', 'FC Facebook', 'U10', 'fb@exemple.invalid', 'Lou', '0470 00 00 01', 'Partant !')$q$)),
 ('Visiteur', '[C5] répond sans e-mail valide', 'refusé', pg_temp.essai($q$select annonce_repondre_public('test-annonce', current_date + 7, null, 'nous', 'FC X', null, 'pas-un-mail')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000001","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach A', '[C5] voit les propositions par e-mail de son équipe (2)', '2', pg_temp.essai($q$select 1 from invitations_match$q$)),
 ('Coach A', '[C5] envoie une proposition → e-mail à l''adresse externe', 'coach@exemple.invalid', pg_temp.notif_ext($q$select invitation_match_creer('10000000-0000-4000-a000-0000000000a1', 'FC Nouveau', 'U10', 'coach@exemple.invalid', 'Marc', current_date + 20, '10:00', 'nous', 'Bonjour')$q$, 'im_proposition')),
 ('Coach A', '[C5] accepte la contre-proposition → match créé', '1', pg_temp.essai($q$select 1 where invitation_match_agir('c0000000-0000-4000-a000-000000000002', 'accepter_contre') = 'acceptee'$q$)),
 ('Coach A', '[C5] accepte la contre-proposition → e-mail au club extérieur', 'sc@exemple.invalid', pg_temp.notif_ext($q$select invitation_match_agir('c0000000-0000-4000-a000-000000000002', 'accepter_contre')$q$, 'im_confirme')),
 ('Coach A', '[C5] refuse la contre-proposition', '1', pg_temp.essai($q$select 1 where invitation_match_agir('c0000000-0000-4000-a000-000000000002', 'refuser_contre') = 'refusee'$q$)),
 ('Coach A', '[C5] proposition avec une adresse invalide', 'refusé', pg_temp.essai($q$select invitation_match_creer('10000000-0000-4000-a000-0000000000a1', 'FC X', null, 'pas-une-adresse', null, current_date + 20, null, 'nous')$q$)),
 ('Coach A', '[C5] invite un club → e-mail d''invitation', 'nouveau@exemple.invalid', pg_temp.notif_ext($q$select invitation_club_creer('50000000-0000-4000-a000-0000000000a1', 'nouveau@exemple.invalid', 'Luc', 'RFC Nouveau')$q$, 'ic_invitation')),
 ('Coach A', '[C5] voit les invitations de son club', '1', pg_temp.essai($q$select 1 from invitations_club$q$)),
 ('Coach A', '[C5] obtient le lien public de son annonce', '1', pg_temp.essai($q$select 1 where annonce_partager('60000000-0000-4000-a000-000000000001') = 'test-annonce'$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000002","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Délégué A', '[C5] voit les propositions par e-mail de son équipe', '2', pg_temp.essai($q$select 1 from invitations_match$q$)),
 ('Délégué A', '[C5] prépare une proposition → CQ et coordinatrice (à envoyer)', '001,006', pg_temp.notif_test($q$select invitation_match_creer('10000000-0000-4000-a000-0000000000a1', 'FC Nouveau', 'U10', 'coach@exemple.invalid', 'Marc', current_date + 20, '10:00', 'nous', 'Bonjour')$q$, 'im_a_envoyer')),
 ('Délégué A', '[C5] sa proposition préparée ne part pas encore', 'aucun', pg_temp.notif_ext($q$select invitation_match_creer('10000000-0000-4000-a000-0000000000a1', 'FC Nouveau', 'U10', 'coach@exemple.invalid', 'Marc', current_date + 20, '10:00', 'nous', 'Bonjour')$q$, 'im_proposition')),
 ('Délégué A', '[C5] accepte une contre-proposition', 'refusé', pg_temp.essai($q$select invitation_match_agir('c0000000-0000-4000-a000-000000000002', 'accepter_contre')$q$)),
 ('Délégué A', '[C5] invite un club', 'refusé', pg_temp.essai($q$select invitation_club_creer('50000000-0000-4000-a000-0000000000a1', 'x@exemple.invalid')$q$)),
 ('Délégué A', '[C5] voit les invitations du club', '0', pg_temp.essai($q$select 1 from invitations_club$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000003","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Coach B', '[C5] voit les propositions du club A', '0', pg_temp.essai($q$select 1 from invitations_match$q$)),
 ('Coach B', '[C5] accepte une contre-proposition du club A', 'refusé', pg_temp.essai($q$select invitation_match_agir('c0000000-0000-4000-a000-000000000002', 'accepter_contre')$q$)),
 ('Coach B', '[C5] invite au nom du club A', 'refusé', pg_temp.essai($q$select invitation_club_creer('50000000-0000-4000-a000-0000000000a1', 'x@exemple.invalid')$q$)),
 ('Coach B', '[C5] partage l''annonce du club A', 'refusé', pg_temp.essai($q$select annonce_partager('60000000-0000-4000-a000-000000000001')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000007","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Parent A', '[C5] voit les propositions', '0', pg_temp.essai($q$select 1 from invitations_match$q$)),
 ('Parent A', '[C5] crée une proposition', 'refusé', pg_temp.essai($q$select invitation_match_creer('10000000-0000-4000-a000-0000000000a1', 'FC Nouveau', 'U10', 'coach@exemple.invalid', 'Marc', current_date + 20, '10:00', 'nous', 'Bonjour')$q$));
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-a000-000000000004","role":"authenticated"}', false);
set role authenticated;
insert into r (qui, test, attendu, obtenu) values
 ('Externe', '[C5] rejoint FootLink via l''invitation → le club A est prévenu', '001,006', pg_temp.notif_test($q$select invitation_club_utiliser('test-ic', create_club('RFC Invité'))$q$, 'ic_acceptee')),
 ('Externe', '[C5] utilise l''invitation pour un club dont il n''est pas CQ', 'refusé', pg_temp.essai($q$select invitation_club_utiliser('test-ic', '50000000-0000-4000-a000-0000000000a1')$q$));
reset role;
select set_config('request.jwt.claims', '', false);

select n, qui, test, attendu, obtenu, case when attendu = obtenu then 'OK' else 'ÉCHEC' end as resultat
from r order by n;
