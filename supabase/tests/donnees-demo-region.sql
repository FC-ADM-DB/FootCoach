-- ============================================================================
-- FootCoach — DONNÉES DE DÉMONSTRATION « région de Braives » (base de TEST FootLink)
-- Pour tester « Trouver un match » en conditions réalistes, via le lien de démo.
-- Clubs : noms de clubs formateurs de la région (presse locale), positions réelles
-- des communes (OpenStreetMap). Personnes, équipes, joueurs et annonces : FICTIFS.
-- Aucun matricule n'est inventé (laissés vides).
-- Verrou : refuse de s'exécuter si la base contient un compte qui n'est pas un compte
-- de test/démo (donc jamais sur la production). Rejouable (efface puis recrée).
-- Tous les comptes de démo : mot de passe « Demo-FootCoach-2026 ».
-- ============================================================================
do $$ begin
  if exists (select 1 from auth.users where email not like '%@test.footcoach' and email not like '%@demo.footcoach') then
    raise exception 'STOP : cette base contient de vrais comptes, ce n''est pas la base de test.';
  end if;
end $$;

-- Les clubs des tests de sécurité (« TEST … », club 4308) sortent du réseau pendant la
-- démo (non vérifiés) ; supabase/tests/donnees-test.sql les remet en place.
update public.clubs set verifie = false where nom like 'TEST %' or matricule = '4308';

-- Nettoyage de la démo précédente
delete from public.teams where club_id in (select id from public.clubs where slug like 'demo-%');
delete from public.clubs where slug like 'demo-%';
delete from auth.users where email like '%@demo.footcoach';

-- ------------------------------------------------------------------ COMPTES (fictifs)
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', md5(u.email)::uuid, 'authenticated', 'authenticated', u.email,
       extensions.crypt('Demo-FootCoach-2026', extensions.gen_salt('bf')), now(),
       jsonb_build_object('prenom', u.prenom, 'nom', u.nom), '{"provider":"email","providers":["email"]}'::jsonb, now(), now()
from (values
  ('david@demo.footcoach',        'David',    'Démo'),      -- vous : CQ de REH Braives (démo) + admin plateforme
  ('cq.hannut@demo.footcoach',    'Marc',     'Lemaire'),
  ('coach.hannut@demo.footcoach', 'Sophie',   'Renard'),    -- entraîneure U10 Hannut (circuit « à valider »)
  ('cq.waremme@demo.footcoach',   'Julien',   'Collard'),
  ('cq.wanze@demo.footcoach',     'Nathalie', 'Piron'),
  ('cq.verlaine@demo.footcoach',  'Olivier',  'Dumont'),
  ('cq.huy@demo.footcoach',       'Isabelle', 'Mathieu'),
  ('cq.amay@demo.footcoach',      'Pierre',   'Lambrecht'),
  ('cq.burdinne@demo.footcoach',  'Valérie',  'Hardy')
) as u(email, prenom, nom);

insert into public.platform_admins (profile_id) values (md5('david@demo.footcoach')::uuid)
on conflict do nothing;

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

-- ------------------------------------------------------------------ CLUBS
insert into public.clubs (id, nom, slug, province_id, adresse, lat, lng, couleur1, couleur2, verifie, cree_par)
select md5(c.slug)::uuid, c.nom, c.slug, (select id from public.provinces where nom = 'Liège'),
       c.commune, c.lat, c.lng, c.c1, c.c2, c.verifie, md5(c.cq)::uuid
from (values
  ('demo-reh-braives', 'REH Braives',     'Braives',  50.6301, 5.1435, '#fdea2e', '#b0212f', true,  'david@demo.footcoach'),
  ('demo-hannut',      'RFC Hannutois',   'Hannut',   50.6725, 5.0780, '#ffffff', '#1d4ed8', true,  'cq.hannut@demo.footcoach'),
  ('demo-waremme',     'Waremme',         'Waremme',  50.6977, 5.2546, '#ffffff', '#0f172a', true,  'cq.waremme@demo.footcoach'),
  ('demo-wanze',       'Wanze/Bas-Oha',   'Wanze',    50.5369, 5.2144, '#facc15', '#15803d', true,  'cq.wanze@demo.footcoach'),
  ('demo-verlaine',    'RCS Verlaine',    'Verlaine', 50.6075, 5.3184, '#ffffff', '#dc2626', true,  'cq.verlaine@demo.footcoach'),
  ('demo-huy',         'RFC Huy',         'Huy',      50.5181, 5.2408, '#ffffff', '#b91c1c', true,  'cq.huy@demo.footcoach'),
  ('demo-amay',        'Amay',            'Amay',     50.5540, 5.3054, '#ffffff', '#2563eb', false, 'cq.amay@demo.footcoach'),  -- NON vérifié
  ('demo-burdinne',    'Burdinne',        'Burdinne', 50.5813, 5.0724, '#ffffff', '#16a34a', true,  'cq.burdinne@demo.footcoach')
) as c(slug, nom, commune, lat, lng, c1, c2, verifie, cq);

insert into public.club_members (club_id, profile_id, role)
select md5(slug)::uuid, md5(cq)::uuid, 'cq' from (values
  ('demo-reh-braives','david@demo.footcoach'), ('demo-hannut','cq.hannut@demo.footcoach'),
  ('demo-waremme','cq.waremme@demo.footcoach'), ('demo-wanze','cq.wanze@demo.footcoach'),
  ('demo-verlaine','cq.verlaine@demo.footcoach'), ('demo-huy','cq.huy@demo.footcoach'),
  ('demo-amay','cq.amay@demo.footcoach'), ('demo-burdinne','cq.burdinne@demo.footcoach')) as x(slug, cq);

-- ------------------------------------------------------------------ ÉQUIPES
-- niveau : 1 à 4 (Niveau 1 = le plus fort), null = non précisé
insert into public.teams (id, nom, categorie, format, couleur, club_id, niveau_id, saison_id, created_by)
select md5(t.club || '/' || t.nom)::uuid, t.nom, t.cat, t.fmt, t.coul, md5(t.club)::uuid,
       (select id from public.niveaux where libelle = 'Niveau ' || t.niv),
       (select id from public.seasons order by debut desc nulls last limit 1), null
from (values
  ('demo-reh-braives','U10A','U10','8v8','#00d68f','2'), ('demo-reh-braives','U9','U9','5v5','#4d9fff',null),
  ('demo-hannut','U9','U9','5v5','#4d9fff',null), ('demo-hannut','U10','U10','8v8','#00d68f','2'), ('demo-hannut','U11','U11','8v8','#c084fc','2'),
  ('demo-waremme','U10','U10','8v8','#00d68f','1'), ('demo-waremme','U12','U12','8v8','#fb923c','1'),
  ('demo-wanze','U9','U9','5v5','#4d9fff',null), ('demo-wanze','U10','U10','8v8','#00d68f','2'),
  ('demo-verlaine','U8','U8','5v5','#ffb830',null), ('demo-verlaine','U10','U10','8v8','#00d68f','3'),
  ('demo-huy','U10','U10','8v8','#00d68f','1'), ('demo-huy','U11','U11','8v8','#c084fc','1'), ('demo-huy','U13','U13','8v8','#ff5c7c','1'),
  ('demo-amay','U9','U9','5v5','#4d9fff',null), ('demo-amay','U10','U10','8v8','#00d68f','3'),
  ('demo-burdinne','U7','U7','festifoot','#ffb830',null), ('demo-burdinne','U10','U10','8v8','#00d68f','4')
) as t(club, nom, cat, fmt, coul, niv);

-- Vous : entraîneur des équipes de REH Braives (démo) ; Sophie : entraîneure U10 Hannut
insert into public.team_members (team_id, profile_id, role) values
  (md5('demo-reh-braives/U10A')::uuid, md5('david@demo.footcoach')::uuid, 'entraineur'),
  (md5('demo-reh-braives/U9')::uuid,   md5('david@demo.footcoach')::uuid, 'entraineur'),
  (md5('demo-hannut/U10')::uuid,       md5('coach.hannut@demo.footcoach')::uuid, 'entraineur');

-- Quelques joueurs FICTIFS dans U10A (démo) pour tester convocations / Live
insert into public.players (team_id, prenom, nom, numero_poste, date_naissance)
select md5('demo-reh-braives/U10A')::uuid, p.prenom, p.nom, p.poste, p.dn::date from (values
  ('Arthur','Demo',1,'2016-02-11'), ('Lina','Exemple',2,'2016-05-03'), ('Noé','Fictif',3,'2016-08-21'),
  ('Jade','Test',5,'2016-01-30'),   ('Victor','Demo',6,'2016-11-12'), ('Zoé','Exemple',7,'2016-04-09'),
  ('Louis','Fictif',9,'2016-07-17'), ('Mila','Test',11,'2016-09-25'), ('Sacha','Demo',null,'2016-03-14'),
  ('Rose','Exemple',null,'2016-12-01'), ('Tom','Fictif',null,'2016-06-06')) as p(prenom, nom, poste, dn);

-- ------------------------------------------------------------------ ANNONCES (publiées par les CQ)
-- Distances depuis Braives (≈) : Hannut 7 km · Burdinne 6 · Waremme 8 · Verlaine 12 · Wanze 12 · Huy 14 · Amay 14
insert into public.annonces (id, team_id, type, lieu, format, duree_mt, categories, niveaux, zone, distance_km, message, statut, cree_par, valide_par, publiee_le)
select md5(a.cle)::uuid, md5(a.equipe)::uuid, a.type, a.lieu, a.fmt, a.duree, a.cats::text[], a.nivs::int[], a.zone, a.km, a.msg,
       a.statut, md5(a.auteur)::uuid, case when a.statut = 'publiee' then md5(a.auteur)::uuid end,
       case when a.statut = 'publiee' then now() - (random() * interval '3 days') end
from (values
  ('an-hannut-u10', 'demo-hannut/U10', 'amical', 'domicile', '8v8', 30, '{U10}', '{2,3}', 'belgique', null,
   'Terrain synthétique, vestiaires et goûter après le match.', 'publiee', 'cq.hannut@demo.footcoach'),
  ('an-waremme-u10', 'demo-waremme/U10', 'amical', 'indifferent', '8v8', 30, '{U10,U11}', '{}', 'distance', 20,
   null, 'publiee', 'cq.waremme@demo.footcoach'),
  ('an-wanze-u9', 'demo-wanze/U9', 'tournoi', 'domicile', '5v5', 12, '{U9}', '{}', 'province', null,
   'Tournoi de Noël : 8 équipes, matchs de 2×12 min, buvette sur place.', 'publiee', 'cq.wanze@demo.footcoach'),
  ('an-verlaine-u10', 'demo-verlaine/U10', 'entrainement', 'domicile', '8v8', null, '{U10}', '{}', 'distance', 10,
   'Entraînement commun le mercredi, puis petit match.', 'publiee', 'cq.verlaine@demo.footcoach'),
  ('an-huy-u11', 'demo-huy/U11', 'amical', 'exterieur', '8v8', 30, '{U11}', '{1,2}', 'belgique', null,
   null, 'publiee', 'cq.huy@demo.footcoach'),
  ('an-burdinne-u10', 'demo-burdinne/U10', 'amical', 'domicile', '8v8', 25, '{U10}', '{}', 'equipes', null,
   'Petit club, ambiance familiale : on cherche des équipes proches.', 'publiee', 'cq.burdinne@demo.footcoach'),
  ('an-hannut-u10-avalider', 'demo-hannut/U10', 'amical', 'exterieur', '8v8', 30, '{U10}', '{}', 'province', null,
   'Proposition de Sophie, à valider par le CQ.', 'a_valider', 'coach.hannut@demo.footcoach')
) as a(cle, equipe, type, lieu, fmt, duree, cats, nivs, zone, km, msg, statut, auteur);

insert into public.annonce_creneaux (annonce_id, jour, heure_debut, heure_fin)
select md5(c.cle)::uuid, current_date + c.j, c.debut::time, c.fin::time from (values
  ('an-hannut-u10', 8, '10:00', '12:00'), ('an-hannut-u10', 15, '14:00', '16:00'),
  ('an-waremme-u10', 8, '09:30', '11:30'), ('an-waremme-u10', 22, '10:00', '12:00'),
  ('an-wanze-u9', 22, '09:00', '17:00'),
  ('an-verlaine-u10', 4, '17:30', '19:00'),
  ('an-huy-u11', 15, '10:00', '12:00'),
  ('an-burdinne-u10', 9, '10:30', '12:00'), ('an-burdinne-u10', 16, '10:30', '12:00'),
  ('an-hannut-u10-avalider', 29, '10:00', '12:00')) as c(cle, j, debut, fin);

-- Burdinne cible directement U10A de REH Braives (zone « équipes choisies »)
insert into public.annonce_cibles (annonce_id, team_id)
values (md5('an-burdinne-u10')::uuid, md5('demo-reh-braives/U10A')::uuid);

-- Résumé
select c.nom as club, c.verifie,
       (select count(*) from public.teams t where t.club_id = c.id) as equipes,
       (select count(*) from public.annonces a where a.club_id = c.id and a.statut = 'publiee') as annonces_publiees,
       round(public.km_entre(50.6301, 5.1435, c.lat, c.lng)::numeric, 1) as km_de_braives
from public.clubs c where c.slug like 'demo-%' order by km_de_braives;
