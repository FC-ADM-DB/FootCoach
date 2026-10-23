-- ============================================================================
-- FootCoach — DONNÉES FICTIVES pour la base de TEST (projet FootLink)
-- Verrou : refuse de s'exécuter si la base contient une équipe qui ne commence
-- pas par « TEST » (donc jamais sur la production). Rejouable (efface puis recrée).
-- Comptes : mot de passe « test-footcoach » (inutilisé par les tests SQL).
-- ============================================================================
do $$ begin
  if exists (select 1 from public.teams where nom not like 'TEST %') then
    raise exception 'STOP : cette base contient de vraies équipes, ce n''est pas la base de test.';
  end if;
end $$;

-- Nettoyage des données de test précédentes (cascade vers profils, membres, joueurs…)
-- Les clubs d'abord (le garde-fou « dernier CQ » bloquerait la suppression des comptes).
do $$ begin
  if to_regclass('public.clubs') is not null then
    execute $d$delete from public.clubs where nom like 'TEST %' or matricule = '4308'$d$;
  end if;
end $$;
delete from public.teams where nom like 'TEST %';
delete from auth.users where email like '%@test.footcoach';
delete from public.seasons where label like 'TEST %';

insert into public.seasons (id, label, debut, fin)
values ('20000000-0000-4000-a000-000000000001', 'TEST 2026-2027', '2026-07-01', '2027-06-30');

-- Comptes (le trigger handle_new_user crée les profils)
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated', u.email,
       extensions.crypt('test-footcoach', extensions.gen_salt('bf')), now(),
       jsonb_build_object('prenom', u.prenom, 'nom', u.nom), '{"provider":"email","providers":["email"]}'::jsonb, now(), now()
from (values
  ('00000000-0000-4000-a000-000000000001', 'coach.a@test.footcoach',  'Alice',  'CoachA'),
  ('00000000-0000-4000-a000-000000000002', 'membre.a@test.footcoach', 'Bruno',  'MembreA'),
  ('00000000-0000-4000-a000-000000000003', 'coach.b@test.footcoach',  'Chloé',  'CoachB'),
  ('00000000-0000-4000-a000-000000000004', 'externe@test.footcoach',  'Damien', 'Externe'),
  ('00000000-0000-4000-a000-000000000005', 'admin@test.footcoach',    'Eric',   'AdminPlateforme'),
  ('00000000-0000-4000-a000-000000000006', 'coord.a@test.footcoach',  'Fanny',  'CoordA'),
  ('00000000-0000-4000-a000-000000000007', 'parent.a@test.footcoach', 'Gaëlle', 'ParentA'),
  ('00000000-0000-4000-a000-000000000008', 'cq.c@test.footcoach',     'Hugo',   'CqC')
) as u(id, email, prenom, nom);

-- Équipes : A (club A) et B (club B)
insert into public.teams (id, nom, categorie, format, saison_id, created_by) values
  ('10000000-0000-4000-a000-0000000000a1', 'TEST U10 Club A', 'U10', '8v8', '20000000-0000-4000-a000-000000000001', '00000000-0000-4000-a000-000000000001'),
  ('10000000-0000-4000-a000-0000000000b1', 'TEST U9 Club B',  'U9',  '5v5', '20000000-0000-4000-a000-000000000001', '00000000-0000-4000-a000-000000000003'),
  -- équipe « historique » sans club, comme en production avant A2 (admin = l'admin plateforme)
  ('10000000-0000-4000-a000-0000000000c1', 'TEST U8 Historique', 'U8', '5v5', '20000000-0000-4000-a000-000000000001', '00000000-0000-4000-a000-000000000005'),
  ('10000000-0000-4000-a000-0000000000d1', 'TEST U10 Club C', 'U10', '8v8', '20000000-0000-4000-a000-000000000001', '00000000-0000-4000-a000-000000000008');

insert into public.team_members (team_id, profile_id, role) values
  ('10000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000001', 'admin'),
  ('10000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000002', 'member'),
  ('10000000-0000-4000-a000-0000000000b1', '00000000-0000-4000-a000-000000000003', 'admin'),
  ('10000000-0000-4000-a000-0000000000c1', '00000000-0000-4000-a000-000000000005', 'admin'),
  ('10000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000007', 'parent'),
  ('10000000-0000-4000-a000-0000000000d1', '00000000-0000-4000-a000-000000000008', 'admin');

insert into public.players (id, team_id, prenom, nom, date_naissance) values
  ('30000000-0000-4000-a000-0000000000a1', '10000000-0000-4000-a000-0000000000a1', 'Léo', 'Alpha', '2016-03-14'),
  ('30000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000b1', 'Tom', 'Bravo', '2017-09-02'),
  ('30000000-0000-4000-a000-0000000000a2', '10000000-0000-4000-a000-0000000000a1', 'Zoé', 'Charlie', '2016-05-20');

-- Match A : 3 buts — Léo (ancien but, sans pid, PAS d'autorisation), Zoé (pid,
-- autorisée), et un but adverse. Seul « Zoé C. » doit apparaître publiquement.
insert into public.matches (id, team_id, date, adversaire, lieu, statut, score_nous, score_eux, timeline_json) values
  ('40000000-0000-4000-a000-0000000000a1', '10000000-0000-4000-a000-0000000000a1', now(), 'Adversaire A', 'domicile', 'termine', 2, 1,
   '{"halfDuration":30,"goals":[{"t":300,"half":1,"adv":false,"scorer":"Léo Alpha"},{"t":600,"half":1,"adv":false,"scorer":"Zoé Charlie","pid":"30000000-0000-4000-a000-0000000000a2"},{"t":900,"half":2,"adv":true,"scorer":"Adversaire A"}]}'),
  ('40000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000b1', now(), 'Adversaire B', 'exterieur', 'prevu', null, null, null);

-- Autorisation de publication du prénom : seulement Zoé (si la colonne existe déjà)
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='players' and column_name='publication_ok') then
    execute $u$update public.players set publication_ok = true where id = '30000000-0000-4000-a000-0000000000a2'$u$;
  end if;
end $$;

insert into public.convocations (match_id, player_id, statut) values
  ('40000000-0000-4000-a000-0000000000a1', '30000000-0000-4000-a000-0000000000a1', 'present'),
  ('40000000-0000-4000-a000-0000000000b1', '30000000-0000-4000-a000-0000000000b1', 'present');

-- Équipe A publiée sur la page des scores (si la colonne existe déjà), B non publiée
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='teams' and column_name='scores_publics') then
    execute $u$update public.teams set scores_publics = true where id = '10000000-0000-4000-a000-0000000000a1'$u$;
  end if;
end $$;

-- Phase A1 (si déjà en place) : Club A (CQ = coach A, coordinateur = Fanny),
-- Club B (CQ = coach B), équipes rattachées, admin plateforme = Eric.
do $$ begin
  if to_regclass('public.clubs') is not null then
    execute $c$
      insert into public.platform_admins (profile_id) values ('00000000-0000-4000-a000-000000000005');
      insert into public.clubs (id, nom, slug, cree_par) values
        ('50000000-0000-4000-a000-0000000000a1', 'TEST Club A', 'test-club-a', '00000000-0000-4000-a000-000000000001'),
        ('50000000-0000-4000-a000-0000000000b1', 'TEST Club B', 'test-club-b', '00000000-0000-4000-a000-000000000003');
      insert into public.club_members (club_id, profile_id, role) values
        ('50000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000001', 'cq'),
        ('50000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000006', 'coordinateur'),
        ('50000000-0000-4000-a000-0000000000b1', '00000000-0000-4000-a000-000000000003', 'cq');
      update public.teams set club_id = '50000000-0000-4000-a000-0000000000a1' where id = '10000000-0000-4000-a000-0000000000a1';
      update public.teams set club_id = '50000000-0000-4000-a000-0000000000b1' where id = '10000000-0000-4000-a000-0000000000b1';
      update public.clubs set verifie = true, lat = 50.6326, lng = 5.5797,
        province_id = (select id from public.provinces where nom = 'Liège') where id = '50000000-0000-4000-a000-0000000000a1';
      update public.clubs set verifie = true, lat = 50.4669, lng = 4.8675,
        province_id = (select id from public.provinces where nom = 'Namur') where id = '50000000-0000-4000-a000-0000000000b1';
      insert into public.clubs (id, nom, slug, cree_par, lat, lng) values
        ('50000000-0000-4000-a000-0000000000c1', 'TEST Club C', 'test-club-c', '00000000-0000-4000-a000-000000000008', 50.6, 5.5);
      insert into public.club_members (club_id, profile_id, role) values
        ('50000000-0000-4000-a000-0000000000c1', '00000000-0000-4000-a000-000000000008', 'cq');
      update public.teams set club_id = '50000000-0000-4000-a000-0000000000c1' where id = '10000000-0000-4000-a000-0000000000d1';
    $c$;
  end if;
end $$;

-- Phase C1 (si déjà en place) : annonces de l'équipe A (club A, Liège)
--  AN1 Belgique (publiée) · AN2 province (publiée) · AN3 80 km (publiée) · AN4 30 km (publiée)
--  AN5 à valider (préparée par le délégué A) · AN6 équipes choisies = équipe B (publiée)
do $$ begin
  if to_regclass('public.annonces') is not null then
    execute $c$
      insert into public.annonces (id, team_id, type, zone, distance_km, categories, statut, cree_par) values
        ('60000000-0000-4000-a000-000000000001', '10000000-0000-4000-a000-0000000000a1', 'amical', 'belgique', null, '{U10}', 'publiee', '00000000-0000-4000-a000-000000000001'),
        ('60000000-0000-4000-a000-000000000002', '10000000-0000-4000-a000-0000000000a1', 'amical', 'province', null, '{U10}', 'publiee', '00000000-0000-4000-a000-000000000001'),
        ('60000000-0000-4000-a000-000000000003', '10000000-0000-4000-a000-0000000000a1', 'amical', 'distance', 80,   '{U10}', 'publiee', '00000000-0000-4000-a000-000000000001'),
        ('60000000-0000-4000-a000-000000000004', '10000000-0000-4000-a000-0000000000a1', 'amical', 'distance', 30,   '{U10}', 'publiee', '00000000-0000-4000-a000-000000000001'),
        ('60000000-0000-4000-a000-000000000005', '10000000-0000-4000-a000-0000000000a1', 'tournoi', 'belgique', null, '{U10}', 'a_valider', '00000000-0000-4000-a000-000000000002'),
        ('60000000-0000-4000-a000-000000000006', '10000000-0000-4000-a000-0000000000a1', 'amical', 'equipes', null, '{U10}', 'publiee', '00000000-0000-4000-a000-000000000001');
      insert into public.annonce_cibles (annonce_id, team_id) values
        ('60000000-0000-4000-a000-000000000006', '10000000-0000-4000-a000-0000000000b1');
      insert into public.annonce_creneaux (annonce_id, jour, heure_debut, heure_fin) values
        ('60000000-0000-4000-a000-000000000001', current_date + 7, '10:00', '12:00');
    $c$;
  end if;
end $$;

insert into public.player_notes (player_id, auteur_id, note) values
  ('30000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000001', 'Note de test (club A)');

select (select count(*) from public.profiles where email like '%@test.footcoach') as profils,
       (select count(*) from public.teams where nom like 'TEST %') as equipes,
       (select count(*) from public.players) as joueurs;
