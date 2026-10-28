-- ============================================================================
-- FootCoach — DONNÉES FICTIVES pour la base de TEST (projet FootLink)
-- Verrou : refuse de s'exécuter si la base contient une équipe qui ne commence
-- pas par « TEST » (donc jamais sur la production). Rejouable (efface puis recrée).
-- Comptes : mot de passe « test-footcoach » (inutilisé par les tests SQL).
-- ============================================================================
do $$ begin
  -- Base de production = de vrais comptes (ni @test ni @demo.footcoach) : on refuse.
  if exists (select 1 from auth.users where email not like '%@test.footcoach' and email not like '%@demo.footcoach') then
    raise exception 'STOP : cette base contient de vraies équipes, ce n''est pas la base de test.';
  end if;
end $$;

-- Les tests partent d'un état connu : la démo « région » est effacée (la relancer
-- ensuite avec supabase/tests/donnees-demo-region.sql).
do $d$ begin
  if to_regclass('public.clubs') is not null then
    delete from public.teams where club_id in (select id from public.clubs where slug like 'demo-%');
    delete from public.clubs where slug like 'demo-%';
  end if;
end $d$;
delete from auth.users where email like '%@demo.footcoach';

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

-- Comptes créés en SQL : champs « jeton » vides (et non NULL) + identité email,
-- sinon la connexion répond « Database error querying schema ».
update auth.users set
  confirmation_token = coalesce(confirmation_token, ''), recovery_token = coalesce(recovery_token, ''),
  email_change_token_new = coalesce(email_change_token_new, ''), email_change = coalesce(email_change, ''),
  email_change_token_current = coalesce(email_change_token_current, ''), phone_change = coalesce(phone_change, ''),
  phone_change_token = coalesce(phone_change_token, ''), reauthentication_token = coalesce(reauthentication_token, '')
where email like '%@demo.footcoach' or email like '%@test.footcoach';
insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text, jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', now(), now(), now()
from auth.users u
where (u.email like '%@demo.footcoach' or u.email like '%@test.footcoach')
  and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email');

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

-- Accès parents (A3, si en place) : match A2 à venir pour l'équipe A ; Parent A
-- rattachée à Léo ; une invitation valable (Zoé) et une expirée (Léo).
do $a3$ begin
  if to_regclass('public.parent_enfants') is not null then
    execute $c$
      insert into public.matches (id, team_id, date, adversaire, lieu, statut) values
        ('40000000-0000-4000-a000-0000000000a2', '10000000-0000-4000-a000-0000000000a1', now() + interval '3 days', 'Adversaire A2', 'domicile', 'prevu');
      insert into public.parent_enfants (player_id, profile_id) values
        ('30000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000007');
      insert into public.invitations_parent (token, player_id, cree_par) values
        ('test-invitation-zoe', '30000000-0000-4000-a000-0000000000a2', '00000000-0000-4000-a000-000000000001');
      insert into public.invitations_parent (token, player_id, cree_par, expire_le) values
        ('test-invitation-expiree', '30000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000001', now() - interval '1 day');
    $c$;
  end if;
end $a3$;
-- Messagerie (A4, si en place) : un message dans le groupe de l'équipe A, un dans la
-- discussion de Léo, un dans celle de Zoé.
do $a4$ begin
  if to_regclass('public.messages') is not null then
    execute $c$
      insert into public.messages (id, team_id, player_id, texte) values
        ('80000000-0000-4000-a000-000000000001', '10000000-0000-4000-a000-0000000000a1', null, 'RDV 9h15 au terrain'),
        ('80000000-0000-4000-a000-000000000002', '10000000-0000-4000-a000-0000000000a1', '30000000-0000-4000-a000-0000000000a1', 'Léo a oublié sa gourde'),
        ('80000000-0000-4000-a000-000000000003', '10000000-0000-4000-a000-0000000000a1', '30000000-0000-4000-a000-0000000000a2', 'Message pour les parents de Zoé');
    $c$;
  end if;
end $a4$;
-- Propositions (C2, si en place) : P1 envoyée par l'équipe B sur AN1 (avec une
-- suggestion « accepter » du délégué A en attente), P2 préparée « à valider » sur AN2.
do $c2$ begin
  if to_regclass('public.propositions') is not null then
    execute $c$
      insert into public.propositions (id, annonce_id, equipe_annonceur, club_annonceur, equipe_proposante, club_proposant, statut, jour, heure, lieu) values
        ('90000000-0000-4000-a000-000000000001', '60000000-0000-4000-a000-000000000001', '10000000-0000-4000-a000-0000000000a1', '50000000-0000-4000-a000-0000000000a1',
         '10000000-0000-4000-a000-0000000000b1', '50000000-0000-4000-a000-0000000000b1', 'envoyee', current_date + 10, '10:00', 'annonceur'),
        ('90000000-0000-4000-a000-000000000002', '60000000-0000-4000-a000-000000000002', '10000000-0000-4000-a000-0000000000a1', '50000000-0000-4000-a000-0000000000a1',
         '10000000-0000-4000-a000-0000000000b1', '50000000-0000-4000-a000-0000000000b1', 'a_valider', current_date + 12, '14:00', 'proposant');
      insert into public.proposition_tours (proposition_id, cote, action, jour, heure, lieu, en_attente, auteur) values
        ('90000000-0000-4000-a000-000000000001', 'proposant', 'proposition', current_date + 10, '10:00', 'annonceur', false, '00000000-0000-4000-a000-000000000003'),
        ('90000000-0000-4000-a000-000000000001', 'annonceur', 'accepter', null, null, null, true, '00000000-0000-4000-a000-000000000002'),
        ('90000000-0000-4000-a000-000000000002', 'proposant', 'proposition', current_date + 12, '14:00', 'proposant', false, '00000000-0000-4000-a000-000000000003');
    $c$;
  end if;
end $c2$;
-- Tableau tactique (si la table existe) : TB1 pour l'équipe A, match A, avant le match
do $tb$ begin
  if to_regclass('public.tableaux') is not null then
    execute $c$insert into public.tableaux (id, team_id, match_id, phase, etat, cree_par) values
      ('70000000-0000-4000-a000-000000000001', '10000000-0000-4000-a000-0000000000a1', '40000000-0000-4000-a000-0000000000a1',
       'avant', '{"v":1,"etapes":[{"pions":[{"id":"n1","camp":"nous","x":50,"y":88,"num":1,"joueur":"30000000-0000-4000-a000-0000000000a1"}]}]}',
       '00000000-0000-4000-a000-000000000001')$c$;
  end if;
end $tb$;

-- Tournois (C6, si en place) : TO1 publié (club A, tableau U10 : notre équipe A contre
-- « Visiteurs FC », 1 match), TO2 non publié.
do $c6$ begin
  if to_regclass('public.tournois') is not null then
    execute $c$
      insert into public.tournois (id, club_id, nom, jour, publie, cree_par) values
        ('a0000000-0000-4000-a000-000000000001', '50000000-0000-4000-a000-0000000000a1', 'TEST Tournoi publié', current_date + 30, true, '00000000-0000-4000-a000-000000000001'),
        ('a0000000-0000-4000-a000-000000000002', '50000000-0000-4000-a000-0000000000a1', 'TEST Tournoi brouillon', current_date + 40, false, '00000000-0000-4000-a000-000000000001');
      insert into public.tournoi_tableaux (id, tournoi_id, nom, format) values
        ('a1000000-0000-4000-a000-000000000001', 'a0000000-0000-4000-a000-000000000001', 'U10', '8v8');
      insert into public.tournoi_equipes (id, tableau_id, nom, team_id, poule) values
        ('a2000000-0000-4000-a000-000000000001', 'a1000000-0000-4000-a000-000000000001', 'TEST U10 Club A', '10000000-0000-4000-a000-0000000000a1', 'A'),
        ('a2000000-0000-4000-a000-000000000002', 'a1000000-0000-4000-a000-000000000001', 'Visiteurs FC', null, 'A');
      insert into public.tournoi_matchs (id, tableau_id, poule, equipe_a, equipe_b, terrain, heure) values
        ('a3000000-0000-4000-a000-000000000001', 'a1000000-0000-4000-a000-000000000001', 'A',
         'a2000000-0000-4000-a000-000000000001', 'a2000000-0000-4000-a000-000000000002', 1, '09:00');
    $c$;
  end if;
end $c6$;

insert into public.player_notes (player_id, auteur_id, note) values
  ('30000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000001', 'Note de test (club A)');

select (select count(*) from public.profiles where email like '%@test.footcoach') as profils,
       (select count(*) from public.teams where nom like 'TEST %') as equipes,
       (select count(*) from public.players) as joueurs;
