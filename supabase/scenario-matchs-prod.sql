-- ============================================================================
-- PRODUCTION — SCÉNARIO « Trouver un match » entre les 4 clubs TEST (2026-11-20)
-- À lancer APRÈS comptes-test-prod.sql. Se fait passer tour à tour pour les comptes
-- footlink.be+… (coordinateur, entraîneur, délégué, parent) et appelle les mêmes
-- fonctions que l'app. Contrairement aux tests de sécurité, TOUT EST GARDÉ :
-- annonces, propositions dans tous les états, matchs créés, messages → matière pour
-- tester dans l'app et faire des démonstrations.
--
-- Résultat : une ligne par étape, OK ou ÉCHEC (ÉCHEC = comportement à examiner).
-- Les vraies notifications partent (≈ 30 e-mails vers footlink.be@gmail.com).
-- Les 4 clubs TEST deviennent « vérifiés » et géolocalisés (visibles des autres clubs).
-- À lancer UNE fois (refuse si le scénario existe déjà). Tout retirer :
-- comptes-test-prod-ANNULER.sql (supprime clubs, équipes, annonces, matchs, comptes).
-- ============================================================================

-- Clubs du scénario (identifiant de chaque club TEST)
drop table if exists pg_temp.cfg;
create temp table cfg (club text primary key, slug text, lat float, lng float, commune text);
insert into cfg values
  ('hannut',   'comptes-test-hannut',   50.6725, 5.0780, 'Hannut'),
  ('burdinne', 'comptes-test-burdinne', 50.5813, 5.0724, 'Burdinne'),
  ('geer',     'comptes-test-geer',     50.6680, 5.1700, 'Geer'),
  ('braives',  'comptes-test-braives',  50.6301, 5.1435, 'Braives');

do $$ begin
  if (select count(*) from clubs c join cfg on cfg.slug = c.slug) <> 4 then
    raise exception 'STOP : les 4 clubs TEST sont introuvables (lancer d''abord comptes-test-prod.sql)';
  end if;
  if (select count(*) from auth.users where email like 'footlink.be+%@gmail.com') < 32 then
    raise exception 'STOP : les 32 comptes de test sont introuvables (lancer d''abord comptes-test-prod.sql)';
  end if;
  if exists (select 1 from annonces a join clubs c on c.id = a.club_id join cfg on cfg.slug = c.slug
             where a.message like '%[scénario]%') then
    raise exception 'STOP : le scénario a déjà été joué (comptes-test-prod-ANNULER.sql puis comptes-test-prod.sql pour repartir de zéro)';
  end if;
end $$;

-- Préparation (droits complets) : clubs vérifiés, position des communes, province de Liège
update clubs c set verifie = true, lat = cfg.lat, lng = cfg.lng, adresse = coalesce(c.adresse, cfg.commune),
       province_id = coalesce(c.province_id, (select id from provinces where nom = 'Liège'))
from cfg where c.slug = cfg.slug;

-- Clés : comptes (« hannut-u10-coordinateur »…), équipes (« t:hannut-U10 »…), annonces, propositions
drop table if exists pg_temp.k;
create temp table k (cle text primary key, id uuid);
insert into k select replace(replace(email, 'footlink.be+', ''), '@gmail.com', ''), id from auth.users where email like 'footlink.be+%@gmail.com';
insert into k select distinct on (cfg.club, t.categorie) 't:' || cfg.club || '-' || t.categorie, t.id
  from teams t join clubs c on c.id = t.club_id join cfg on cfg.slug = c.slug
  where t.categorie in ('U9', 'U10') order by cfg.club, t.categorie, t.created_at;
insert into k values ('an_h10', gen_random_uuid()), ('an_b10', gen_random_uuid()), ('an_r9', gen_random_uuid()), ('an_x', gen_random_uuid());
grant all on k to authenticated;

drop table if exists pg_temp.r;
create temp table r (n serial, etape text, qui text, action text, attendu text, obtenu text);
grant all on r to authenticated;
grant usage on sequence r_n_seq to authenticated;

create or replace function pg_temp.id(c text) returns uuid language sql as $f$ select id from pg_temp.k where cle = c $f$;
-- Se faire passer pour un compte (appelé AVANT « set role authenticated »)
create or replace function pg_temp.qui(c text) returns text language sql as $f$
  select set_config('request.jwt.claims', json_build_object('sub', (select id from pg_temp.k where cle = c), 'role', 'authenticated')::text, false) $f$;
-- Exécute l'action et la GARDE ; renvoie le résultat, le nombre de lignes, ou « refusé : … »
create or replace function pg_temp.faire(q text) returns text language plpgsql as $f$
declare v text; n bigint;
begin
  -- Une fonction sans résultat (ex. proposition_message) renvoie un texte vide → « ok »
  if q ~* '^\s*select' then execute q into v; v := coalesce(nullif(v, ''), 'ok');
  else execute q; get diagnostics n = row_count; v := n::text; end if;
  return v;
exception when others then return 'refusé : ' || sqlerrm;
end $f$;
-- Crée une proposition (q renvoie son id), la garde sous « cle », renvoie son statut
create or replace function pg_temp.garde(c text, q text) returns text language plpgsql as $f$
declare v uuid; s text;
begin
  execute q into v;
  insert into pg_temp.k values (c, v);
  select statut into s from propositions where id = v;
  return coalesce(s, 'créée (statut invisible)');
exception when others then return 'refusé : ' || sqlerrm;
end $f$;

-- ======================================================================== A. ANNONCES
select pg_temp.qui('hannut-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('A1', 'Coord. Hannut', 'prépare une annonce U10 (toute la Belgique)', '1', pg_temp.faire($q$insert into annonces (id, team_id, type, lieu, format, duree_mt, categories, zone, message, statut, cree_par) values (pg_temp.id('an_h10'), pg_temp.id('t:hannut-U10'), 'amical', 'domicile', '8v8', 30, '{U10}', 'belgique', 'Synthétique, goûter offert. [scénario]', 'brouillon', auth.uid())$q$)),
 ('A1', 'Coord. Hannut', 'ajoute 2 créneaux (J+10, J+17)', '2', pg_temp.faire($q$insert into annonce_creneaux (annonce_id, jour, heure_debut, heure_fin) values (pg_temp.id('an_h10'), current_date + 10, '10:00', '12:00'), (pg_temp.id('an_h10'), current_date + 17, '10:00', '15:00')$q$)),
 ('A1', 'Coord. Hannut', 'publie l''annonce', '1', pg_temp.faire($q$update annonces set statut = 'publiee' where id = pg_temp.id('an_h10')$q$));
reset role;

select pg_temp.qui('burdinne-u10-entraineur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('A2', 'Entraîneur Burdinne U10', 'prépare une annonce « à valider » (province)', '1', pg_temp.faire($q$insert into annonces (id, team_id, type, lieu, format, duree_mt, categories, zone, message, statut, cree_par) values (pg_temp.id('an_b10'), pg_temp.id('t:burdinne-U10'), 'amical', 'indifferent', '8v8', 30, '{U10}', 'province', 'On cherche un amical, chez nous ou chez vous. [scénario]', 'a_valider', auth.uid())$q$)),
 ('A2', 'Entraîneur Burdinne U10', 'ajoute un créneau (J+11)', '1', pg_temp.faire($q$insert into annonce_creneaux (annonce_id, jour, heure_debut, heure_fin) values (pg_temp.id('an_b10'), current_date + 11, '10:00', '12:00')$q$)),
 ('A3', 'Entraîneur Burdinne U10', 'publie lui-même une annonce (interdit)', 'refusé', pg_temp.faire($q$insert into annonces (id, team_id, zone, message, statut, cree_par) values (pg_temp.id('an_x'), pg_temp.id('t:burdinne-U10'), 'belgique', '[scénario]', 'publiee', auth.uid())$q$));
reset role;

select pg_temp.qui('burdinne-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('A4', 'Coord. Burdinne', 'valide et publie l''annonce de son entraîneur', '1', pg_temp.faire($q$update annonces set statut = 'publiee' where id = pg_temp.id('an_b10')$q$));
reset role;

select pg_temp.qui('geer-u10-delegue'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('A5', 'Délégué Geer U10', 'publie lui-même une annonce (interdit)', 'refusé', pg_temp.faire($q$insert into annonces (id, team_id, zone, message, statut, cree_par) values (pg_temp.id('an_x'), pg_temp.id('t:geer-U10'), 'belgique', '[scénario]', 'publiee', auth.uid())$q$));
reset role;

select pg_temp.qui('braives-u9-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('A6', 'Coord. Braives', 'prépare une annonce U9 (20 km)', '1', pg_temp.faire($q$insert into annonces (id, team_id, type, lieu, format, duree_mt, categories, zone, distance_km, message, statut, cree_par) values (pg_temp.id('an_r9'), pg_temp.id('t:braives-U9'), 'amical', 'domicile', '5v5', 20, '{U9}', 'distance', 20, 'Plateau U9 du samedi. [scénario]', 'brouillon', auth.uid())$q$)),
 ('A6', 'Coord. Braives', 'ajoute un créneau (J+12)', '1', pg_temp.faire($q$insert into annonce_creneaux (annonce_id, jour, heure_debut, heure_fin) values (pg_temp.id('an_r9'), current_date + 12, '10:00', '12:00')$q$)),
 ('A6', 'Coord. Braives', 'publie l''annonce', '1', pg_temp.faire($q$update annonces set statut = 'publiee' where id = pg_temp.id('an_r9')$q$));
reset role;

select pg_temp.qui('hannut-u10-parent'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('A7', 'Parent Hannut U10', 'crée une annonce (interdit)', 'refusé', pg_temp.faire($q$insert into annonces (id, team_id, zone, message, statut, cree_par) values (pg_temp.id('an_x'), pg_temp.id('t:hannut-U10'), 'belgique', '[scénario]', 'brouillon', auth.uid())$q$)),
 ('A8', 'Parent Hannut U10', 'voit les annonces', '0', pg_temp.faire($q$select count(*)::text from annonces$q$));
reset role;

select pg_temp.qui('geer-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('A9', 'Coord. Geer', 'recherche pour Geer U10 : voit les 3 annonces', '3', pg_temp.faire($q$select count(*)::text from annonces_reseau(pg_temp.id('t:geer-U10')) where id in (pg_temp.id('an_h10'), pg_temp.id('an_b10'), pg_temp.id('an_r9'))$q$));
reset role;

-- ======================================================================== B. PROPOSITION ACCEPTÉE (suggestion de l'entraîneur, validée par le coordinateur)
select pg_temp.qui('geer-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('B1', 'Coord. Geer', 'propose Geer U10 sur l''annonce de Hannut (J+10, chez Hannut)', 'envoyee', pg_temp.garde('p1', $q$select proposition_creer(pg_temp.id('an_h10'), pg_temp.id('t:geer-U10'), current_date + 10, '10:30', 'annonceur', 'Bonjour, partants pour le samedi !')$q$));
reset role;

select pg_temp.qui('hannut-u10-entraineur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('B2', 'Entraîneur Hannut U10', 'voit la proposition reçue', '1', pg_temp.faire($q$select count(*)::text from propositions where id = pg_temp.id('p1')$q$)),
 ('B3', 'Entraîneur Hannut U10', 'accepte → suggestion pour son coordinateur', 'suggestion', pg_temp.faire($q$select proposition_agir(pg_temp.id('p1'), 'accepter')$q$));
reset role;

select pg_temp.qui('hannut-u10-delegue'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('B4', 'Délégué Hannut U10', 'valide la suggestion (réservé au club)', 'refusé', pg_temp.faire($q$select proposition_agir(pg_temp.id('p1'), 'valider_suggestion')$q$));
reset role;

select pg_temp.qui('hannut-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('B5', 'Coord. Hannut', 'valide la suggestion → match accepté', 'acceptee', pg_temp.faire($q$select proposition_agir(pg_temp.id('p1'), 'valider_suggestion')$q$)),
 ('B6', 'Coord. Hannut', 'le créneau J+10 de l''annonce est marqué pris', 'pris', pg_temp.faire($q$select statut from annonce_creneaux where annonce_id = pg_temp.id('an_h10') and jour = current_date + 10$q$));
reset role;

select pg_temp.qui('hannut-u10-parent'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('B7', 'Parent Hannut U10', 'voit le match contre Geer dans le calendrier', '1', pg_temp.faire($q$select count(*)::text from matches where team_id = pg_temp.id('t:hannut-U10') and adversaire ilike '%geer%' and (date at time zone 'Europe/Brussels')::date = current_date + 10$q$)),
 ('B8', 'Parent Hannut U10', 'voit les propositions', '0', pg_temp.faire($q$select count(*)::text from propositions$q$));
reset role;

select pg_temp.qui('geer-u10-parent'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('B9', 'Parent Geer U10', 'voit le match contre Hannut dans le calendrier', '1', pg_temp.faire($q$select count(*)::text from matches where team_id = pg_temp.id('t:geer-U10') and adversaire ilike '%hannut%' and (date at time zone 'Europe/Brussels')::date = current_date + 10$q$));
reset role;

-- ======================================================================== C. CONTRE-PROPOSITION puis accord
select pg_temp.qui('braives-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('C1', 'Coord. Braives', 'propose Braives U10 sur l''annonce de Hannut (J+17 14h, chez Braives)', 'envoyee', pg_temp.garde('p2', $q$select proposition_creer(pg_temp.id('an_h10'), pg_temp.id('t:braives-U10'), current_date + 17, '14:00', 'proposant', 'On vous reçoit volontiers.')$q$));
reset role;

select pg_temp.qui('hannut-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('C2', 'Coord. Hannut', 'contre-propose : même jour, 10h, chez Hannut', 'contre', pg_temp.faire($q$select proposition_agir(pg_temp.id('p2'), 'contre', current_date + 17, '10:00', 'annonceur', 'Plutôt chez nous à 10h ?')$q$));
reset role;

select pg_temp.qui('braives-u10-entraineur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('C3', 'Entraîneur Braives U10', 'accepte la contre-proposition → suggestion', 'suggestion', pg_temp.faire($q$select proposition_agir(pg_temp.id('p2'), 'accepter')$q$));
reset role;

select pg_temp.qui('braives-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('C4', 'Coord. Braives', 'valide la suggestion → match accepté', 'acceptee', pg_temp.faire($q$select proposition_agir(pg_temp.id('p2'), 'valider_suggestion')$q$)),
 ('C5', 'Coord. Braives', 'écrit un message à Hannut', 'ok', pg_temp.faire($q$select proposition_message(pg_temp.id('p2'), 'Merci, à samedi ! On arrive vers 9h30.')$q$));
reset role;

-- ======================================================================== D. PROPOSITION PRÉPARÉE par un entraîneur, envoyée par le club, REFUSÉE
select pg_temp.qui('hannut-u10-entraineur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('D1', 'Entraîneur Hannut U10', 'prépare une proposition sur l''annonce de Burdinne (J+11)', 'a_valider', pg_temp.garde('p3', $q$select proposition_creer(pg_temp.id('an_b10'), pg_temp.id('t:hannut-U10'), current_date + 11, '10:30', 'annonceur', 'On peut venir chez vous.')$q$));
reset role;

select pg_temp.qui('burdinne-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('D2', 'Coord. Burdinne', 'voit la proposition pas encore envoyée', '0', pg_temp.faire($q$select count(*)::text from propositions where id = pg_temp.id('p3')$q$));
reset role;

select pg_temp.qui('hannut-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('D3', 'Coord. Hannut', 'envoie la proposition préparée par l''entraîneur', 'envoyee', pg_temp.faire($q$select proposition_agir(pg_temp.id('p3'), 'envoyer')$q$));
reset role;

select pg_temp.qui('burdinne-u10-delegue'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('D4', 'Délégué Burdinne U10', 'suggère de refuser', 'suggestion', pg_temp.faire($q$select proposition_agir(pg_temp.id('p3'), 'refuser', null, null, null, 'Pas de terrain libre ce jour-là')$q$));
reset role;

select pg_temp.qui('burdinne-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('D5', 'Coord. Burdinne', 'valide le refus', 'refusee', pg_temp.faire($q$select proposition_agir(pg_temp.id('p3'), 'valider_suggestion')$q$));
reset role;

-- ======================================================================== E. PROPOSITIONS DIRECTES (sans annonce)
select pg_temp.qui('hannut-u9-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('E1', 'Coord. Hannut', 'propose directement Hannut U9 → Geer U9 (J+14, chez Hannut)', 'envoyee', pg_temp.garde('p4', $q$select proposition_directe(pg_temp.id('t:hannut-U9'), pg_temp.id('t:geer-U9'), current_date + 14, '10:00', 'proposant', 'Un match U9 chez nous ?')$q$));
reset role;

select pg_temp.qui('geer-u9-entraineur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('E2', 'Entraîneur Geer U9', 'écrit un message à Hannut', 'ok', pg_temp.faire($q$select proposition_message(pg_temp.id('p4'), 'Avec plaisir, on vérifie le transport.')$q$));
reset role;

select pg_temp.qui('geer-u9-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('E3', 'Coord. Geer', 'accepte → match dans les deux calendriers', 'acceptee', pg_temp.faire($q$select proposition_agir(pg_temp.id('p4'), 'accepter')$q$));
reset role;

select pg_temp.qui('braives-u9-delegue'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('E4', 'Délégué Braives U9', 'prépare une proposition directe Braives U9 → Burdinne U9 (reste à envoyer)', 'a_valider', pg_temp.garde('p5', $q$select proposition_directe(pg_temp.id('t:braives-U9'), pg_temp.id('t:burdinne-U9'), current_date + 15, '10:00', 'proposant', 'Proposition du délégué')$q$));
reset role;

select pg_temp.qui('braives-u9-parent'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('E5', 'Parent Braives U9', 'propose un match (interdit)', 'refusé', pg_temp.faire($q$select proposition_directe(pg_temp.id('t:braives-U9'), pg_temp.id('t:geer-U9'), current_date + 16, '10:00', 'proposant')$q$));
reset role;

select pg_temp.qui('geer-u10-delegue'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('E6', 'Délégué Geer U10', 'propose au nom d''une équipe d''un autre club (interdit)', 'refusé', pg_temp.faire($q$select proposition_directe(pg_temp.id('t:hannut-U10'), pg_temp.id('t:braives-U10'), current_date + 16, '10:00', 'proposant')$q$));
reset role;

-- ======================================================================== F. LAISSÉES EN ATTENTE (pour tester dans l'app)
select pg_temp.qui('burdinne-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('F1', 'Coord. Burdinne', 'propose directement Burdinne U10 → Braives U10 (J+21) : Braives doit répondre', 'envoyee', pg_temp.garde('p6', $q$select proposition_directe(pg_temp.id('t:burdinne-U10'), pg_temp.id('t:braives-U10'), current_date + 21, '10:00', 'proposant', 'Match retour ?')$q$));
reset role;

select pg_temp.qui('geer-u9-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('F2', 'Coord. Geer', 'propose Geer U9 sur l''annonce U9 de Braives (J+12) : Braives doit répondre', 'envoyee', pg_temp.garde('p7', $q$select proposition_creer(pg_temp.id('an_r9'), pg_temp.id('t:geer-U9'), current_date + 12, '10:00', 'annonceur', 'Partants pour votre plateau !')$q$));
reset role;

-- ======================================================================== G. CE QUI DOIT RESTER IMPOSSIBLE
select pg_temp.qui('braives-u10-parent'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('G1', 'Parent Braives U10', 'voit les propositions', '0', pg_temp.faire($q$select count(*)::text from propositions$q$)),
 ('G2', 'Parent Braives U10', 'voit le match contre Hannut', '1', pg_temp.faire($q$select count(*)::text from matches where team_id = pg_temp.id('t:braives-U10') and adversaire ilike '%hannut%' and (date at time zone 'Europe/Brussels')::date = current_date + 17$q$));
reset role;

select pg_temp.qui('burdinne-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('G3', 'Coord. Burdinne', 'voit la proposition Geer → Hannut (pas son club)', '0', pg_temp.faire($q$select count(*)::text from propositions where id = pg_temp.id('p1')$q$));
reset role;

select pg_temp.qui('hannut-u10-coordinateur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('G4', 'Coord. Hannut', 'accepte la proposition Burdinne → Braives (pas son club)', 'refusé', pg_temp.faire($q$select proposition_agir(pg_temp.id('p6'), 'accepter')$q$)),
 ('G5', 'Coord. Hannut', 'propose sur sa propre annonce', 'refusé', pg_temp.faire($q$select proposition_creer(pg_temp.id('an_h10'), pg_temp.id('t:hannut-U9'), current_date + 10, '10:00', 'annonceur')$q$));
reset role;

select pg_temp.qui('hannut-u10-entraineur'); set role authenticated;
insert into r (etape, qui, action, attendu, obtenu) values
 ('G6', 'Entraîneur Hannut U10', 'annule un match déjà accepté', 'refusé', pg_temp.faire($q$select proposition_agir(pg_temp.id('p1'), 'annuler')$q$));
reset role;
select set_config('request.jwt.claims', '', false);

-- ======================================================================== RÉSULTAT
select n, etape, qui, action, attendu, obtenu,
       case when obtenu = attendu or (attendu = 'refusé' and obtenu like 'refusé%') then 'OK' else 'ÉCHEC' end as resultat
from r order by n;
