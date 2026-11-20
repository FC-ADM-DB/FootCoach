-- ============================================================================
-- PRODUCTION — correctifs des données de TEST (2026-11-20), constatés pendant les captures
-- Ne touche QUE les clubs « TEST … » (comptes-test-prod.sql) et les comptes footlink.be+…
--  1. Équipes TEST renommées « U10 », « U9 »… : l'adversaire d'un match s'affichait
--     « TEST Geer TEST Geer U10 » (nom du club + nom d'équipe qui contenait déjà le club).
--  2. Nom de l'adversaire corrigé dans les matchs déjà créés par le scénario.
--  3. Chaque compte parent est relié à un enfant de son équipe (accueil du parent vide sinon).
-- Rejouable.
-- ============================================================================
begin;

-- 1. Équipes
update teams t set nom = t.categorie
from clubs c where c.id = t.club_id and c.slug like 'comptes-test-%' and t.nom <> t.categorie;

-- 2. Matches : « TEST Geer TEST Geer U10 » → « TEST Geer U10 »
update matches m set adversaire = regexp_replace(m.adversaire, '^(TEST \S+) TEST \S+ ', '\1 ')
where m.adversaire ~ '^TEST \S+ TEST \S+ '
  and m.team_id in (select t.id from teams t join clubs c on c.id = t.club_id where c.slug like 'comptes-test-%');

-- 3. Parents ↔ enfant (le premier joueur de l'équipe par ordre alphabétique)
insert into parent_enfants (player_id, profile_id)
select (select p.id from players p where p.team_id = tm.team_id and p.actif order by p.prenom, p.nom limit 1), tm.profile_id
from team_members tm join auth.users u on u.id = tm.profile_id
where tm.role = 'parent' and u.email like 'footlink.be+%@gmail.com'
  and exists (select 1 from players p where p.team_id = tm.team_id and p.actif)
on conflict do nothing;

commit;

-- Vérification
select c.nom as club, t.nom as equipe,
       (select count(*) from matches m where m.team_id = t.id and m.adversaire ~ 'TEST \S+ TEST') as noms_en_double,
       (select string_agg(pl.prenom || ' ' || pl.nom, ', ') from parent_enfants pe join players pl on pl.id = pe.player_id
         join auth.users u on u.id = pe.profile_id where pl.team_id = t.id and u.email like 'footlink.be+%') as enfant_du_parent_test
from teams t join clubs c on c.id = t.club_id
where c.slug like 'comptes-test-%' and t.categorie in ('U9', 'U10')
order by c.nom, t.categorie;
