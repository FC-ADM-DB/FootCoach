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
  ('00000000-0000-4000-a000-000000000004', 'externe@test.footcoach',  'Damien', 'Externe')
) as u(id, email, prenom, nom);

-- Équipes : A (club A) et B (club B)
insert into public.teams (id, nom, categorie, format, saison_id, created_by) values
  ('10000000-0000-4000-a000-0000000000a1', 'TEST U10 Club A', 'U10', '8v8', '20000000-0000-4000-a000-000000000001', '00000000-0000-4000-a000-000000000001'),
  ('10000000-0000-4000-a000-0000000000b1', 'TEST U9 Club B',  'U9',  '5v5', '20000000-0000-4000-a000-000000000001', '00000000-0000-4000-a000-000000000003');

insert into public.team_members (team_id, profile_id, role) values
  ('10000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000001', 'admin'),
  ('10000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000002', 'member'),
  ('10000000-0000-4000-a000-0000000000b1', '00000000-0000-4000-a000-000000000003', 'admin');

insert into public.players (id, team_id, prenom, nom, date_naissance) values
  ('30000000-0000-4000-a000-0000000000a1', '10000000-0000-4000-a000-0000000000a1', 'Léo', 'Alpha', '2016-03-14'),
  ('30000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000b1', 'Tom', 'Bravo', '2017-09-02');

insert into public.matches (id, team_id, date, adversaire, lieu, statut) values
  ('40000000-0000-4000-a000-0000000000a1', '10000000-0000-4000-a000-0000000000a1', now(), 'Adversaire A', 'domicile', 'prevu'),
  ('40000000-0000-4000-a000-0000000000b1', '10000000-0000-4000-a000-0000000000b1', now(), 'Adversaire B', 'exterieur', 'prevu');

insert into public.convocations (match_id, player_id, statut) values
  ('40000000-0000-4000-a000-0000000000a1', '30000000-0000-4000-a000-0000000000a1', 'present'),
  ('40000000-0000-4000-a000-0000000000b1', '30000000-0000-4000-a000-0000000000b1', 'present');

-- Équipe A publiée sur la page des scores (si la colonne existe déjà), B non publiée
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='teams' and column_name='scores_publics') then
    execute $u$update public.teams set scores_publics = true where id = '10000000-0000-4000-a000-0000000000a1'$u$;
  end if;
end $$;

insert into public.player_notes (player_id, auteur_id, note) values
  ('30000000-0000-4000-a000-0000000000a1', '00000000-0000-4000-a000-000000000001', 'Note de test (club A)');

select (select count(*) from public.profiles where email like '%@test.footcoach') as profils,
       (select count(*) from public.teams where nom like 'TEST %') as equipes,
       (select count(*) from public.players) as joueurs;
