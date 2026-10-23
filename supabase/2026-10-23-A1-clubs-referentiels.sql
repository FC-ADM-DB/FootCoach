-- ============================================================================
-- FootCoach — Phase A1 : clubs, référentiels, rôles de club — 2026-10-23
-- UNIQUEMENT DES AJOUTS : aucune table existante n'est modifiée dans son usage,
-- l'app actuelle continue de fonctionner à l'identique. Les équipes existantes
-- seront rattachées à un club en phase A2.
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- À exécuter en une fois dans Supabase → SQL Editor → Run.
-- Annulation : 2026-10-23-A1-clubs-referentiels-ANNULER.sql
-- ============================================================================
begin;

-- ------------------------------------------------------------------ RÉFÉRENTIELS
-- Données configurables (plus codées en dur dans l'app).
create table public.pays (
  id serial primary key,
  code text not null unique,          -- 'BE'
  nom text not null
);

create table public.provinces (
  id serial primary key,
  pays_id int not null references public.pays(id),
  nom text not null,
  unique (pays_id, nom)
);

create table public.formats (
  code text primary key,              -- même code que teams.format ('5v5', '8v8'…)
  libelle text not null,              -- affiché : '5c5', '8c8'…
  nb_joueurs int,                     -- null pour Festifoot (variable)
  postes int[] not null default '{}', -- numéros de postes du terrain (Live)
  duree_mt int,                       -- durée d'une mi-temps par défaut (minutes)
  live boolean not null default true, -- false : calendrier + présences seulement
  ordre int not null default 0
);

create table public.categories (
  code text primary key,              -- 'U10'
  libelle text not null,
  format_defaut text references public.formats(code),
  ordre int not null default 0
);

create table public.niveaux (
  id serial primary key,
  libelle text not null unique,       -- 'Niveau 1', 'IP'…
  ordre int not null default 100,
  cree_par uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

insert into public.pays (code, nom) values ('BE', 'Belgique');
insert into public.provinces (pays_id, nom)
select p.id, v.nom from public.pays p, (values
  ('Anvers'), ('Brabant flamand'), ('Brabant wallon'), ('Bruxelles-Capitale'),
  ('Flandre occidentale'), ('Flandre orientale'), ('Hainaut'), ('Liège'),
  ('Limbourg'), ('Luxembourg'), ('Namur')) as v(nom)
where p.code = 'BE';

insert into public.formats (code, libelle, nb_joueurs, postes, duree_mt, live, ordre) values
  ('festifoot', 'Festifoot', null, '{}',                       null, false, 1),
  ('5v5',       '5c5',       5,    '{1,2,3,6,9}',              25,   true,  2),
  ('8v8',       '8c8',       8,    '{1,2,3,5,6,7,9,11}',       30,   true,  3),
  ('11v11',     '11c11',     11,   '{1,2,3,4,5,6,7,8,9,10,11}', 35,  true,  4);

insert into public.categories (code, libelle, format_defaut, ordre) values
  ('U5','U5','festifoot',5), ('U6','U6','festifoot',6), ('U7','U7','festifoot',7),
  ('U8','U8','5v5',8), ('U9','U9','5v5',9),
  ('U10','U10','8v8',10), ('U11','U11','8v8',11), ('U12','U12','8v8',12), ('U13','U13','8v8',13),
  ('U14','U14','11v11',14), ('U15','U15','11v11',15), ('U16','U16','11v11',16),
  ('U17','U17','11v11',17), ('U19','U19','11v11',19);

insert into public.niveaux (libelle, ordre) values
  ('Niveau 1',1), ('Niveau 2',2), ('Niveau 3',3), ('Niveau 4',4);

-- ------------------------------------------------------------------ CLUBS & RÔLES
create table public.platform_admins (
  profile_id uuid primary key references public.profiles(id) on delete cascade
);

create table public.clubs (
  id uuid primary key default extensions.uuid_generate_v4(),
  nom text not null,
  slug text not null unique,          -- identifiant d'adresse web : 'reh-braives'
  province_id int references public.provinces(id),
  adresse text,
  lat double precision,               -- pour la distance (module « Trouver un match »)
  lng double precision,
  logo text,
  couleur1 text,
  couleur2 text,
  matricule text unique,              -- matricule ACFF, facultatif
  verifie boolean not null default false,  -- badge : seul l'admin plateforme le pose
  cree_par uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

create table public.club_members (
  id uuid primary key default extensions.uuid_generate_v4(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('cq', 'coordinateur')),
  created_at timestamptz default now(),
  unique (club_id, profile_id, role)
);

-- Rattachement futur des équipes (rempli en phase A2 ; ignoré par l'app actuelle)
alter table public.teams add column if not exists club_id uuid references public.clubs(id) on delete set null;
alter table public.teams add column if not exists niveau_id int references public.niveaux(id) on delete set null;

-- ------------------------------------------------------------------ FONCTIONS D'AIDE
-- SECURITY DEFINER : lisent les tables de rôles sans repasser par leurs règles
-- (même principe que is_team_member, évite la récursion).
create or replace function public.is_platform_admin() returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from platform_admins where profile_id = auth.uid()) $$;

create or replace function public.is_club_member(c uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from club_members where club_id = c and profile_id = auth.uid()) $$;

create or replace function public.is_club_cq(c uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from club_members where club_id = c and profile_id = auth.uid() and role = 'cq') $$;

-- CQ ou coordinateur d'au moins un club (droit d'ajouter un niveau)
create or replace function public.is_any_club_staff() returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from club_members where profile_id = auth.uid()) $$;

-- Membre d'une équipe du club (pour voir la fiche de son club)
create or replace function public.is_in_club_team(c uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from teams t join team_members tm on tm.team_id = t.id
                 where t.club_id = c and tm.profile_id = auth.uid()) $$;

-- Création d'un club : le créateur en devient CQ, en une seule opération.
create or replace function public.create_club(p_nom text, p_province_id int default null,
                                              p_matricule text default null, p_adresse text default null)
  returns uuid language plpgsql security definer set search_path = public as
$$ declare v_id uuid; v_slug text; v_base text; n int := 1;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if coalesce(trim(p_nom), '') = '' then raise exception 'Nom du club obligatoire'; end if;
  v_base := trim(both '-' from regexp_replace(lower(translate(p_nom,
              'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ',
              'aaaaaaceeeeiiiinooooouuuuyyaaaaaaceeeeiiiinooooouuuuy')), '[^a-z0-9]+', '-', 'g'));
  if v_base = '' then v_base := 'club'; end if;
  v_slug := v_base;
  while exists (select 1 from clubs where slug = v_slug) loop
    n := n + 1; v_slug := v_base || '-' || n;
  end loop;
  insert into clubs (nom, slug, province_id, matricule, adresse, cree_par)
  values (trim(p_nom), v_slug, p_province_id, nullif(trim(p_matricule), ''), p_adresse, auth.uid())
  returning id into v_id;
  insert into club_members (club_id, profile_id, role) values (v_id, auth.uid(), 'cq');
  return v_id;
end $$;

-- Garde-fou : seul l'admin plateforme pose ou retire le badge « vérifié ».
-- SECURITY INVOKER volontairement : current_user doit être le rôle réel de l'appelant
-- (authenticated / anon). En SECURITY DEFINER il vaudrait « postgres » et le
-- garde-fou laisserait passer tout le monde (bug trouvé par les tests).
create or replace function public.guard_club_verifie() returns trigger
  language plpgsql set search_path = public as
$$ begin
  if new.verifie is distinct from old.verifie and not public.is_platform_admin()
     and current_user in ('authenticated', 'anon') then
    raise exception 'Seul l''administrateur FootCoach peut vérifier un club';
  end if;
  return new;
end $$;
create trigger clubs_guard_verifie before update on public.clubs
  for each row execute function public.guard_club_verifie();

-- Garde-fou : un club garde toujours au moins un CQ.
create or replace function public.guard_last_cq() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  if old.role = 'cq' and (tg_op = 'DELETE' or new.role <> 'cq')
     and exists (select 1 from clubs where id = old.club_id)
     and not exists (select 1 from club_members where club_id = old.club_id and role = 'cq' and id <> old.id) then
    raise exception 'Un club doit garder au moins un CQ';
  end if;
  return coalesce(new, old);
end $$;
create trigger club_members_guard_last_cq before update or delete on public.club_members
  for each row execute function public.guard_last_cq();

-- ------------------------------------------------------------------ RÈGLES (RLS)
alter table public.pays enable row level security;
alter table public.provinces enable row level security;
alter table public.formats enable row level security;
alter table public.categories enable row level security;
alter table public.niveaux enable row level security;
alter table public.platform_admins enable row level security;
alter table public.clubs enable row level security;
alter table public.club_members enable row level security;

-- Référentiels : lisibles par les utilisateurs connectés, modifiés par l'admin plateforme
create policy "Pays lisibles" on public.pays for select to authenticated using (true);
create policy "Pays admin" on public.pays for all to authenticated using (is_platform_admin()) with check (is_platform_admin());
create policy "Provinces lisibles" on public.provinces for select to authenticated using (true);
create policy "Provinces admin" on public.provinces for all to authenticated using (is_platform_admin()) with check (is_platform_admin());
create policy "Formats lisibles" on public.formats for select to authenticated using (true);
create policy "Formats admin" on public.formats for all to authenticated using (is_platform_admin()) with check (is_platform_admin());
create policy "Catégories lisibles" on public.categories for select to authenticated using (true);
create policy "Catégories admin" on public.categories for all to authenticated using (is_platform_admin()) with check (is_platform_admin());

-- Niveaux : liste commune ; CQ et coordinateurs peuvent en ajouter ; l'admin
-- plateforme modifie / fusionne / supprime.
create policy "Niveaux lisibles" on public.niveaux for select to authenticated using (true);
create policy "Niveaux ajout" on public.niveaux for insert to authenticated
  with check ((is_any_club_staff() or is_platform_admin()) and cree_par = auth.uid());
create policy "Niveaux admin modif" on public.niveaux for update to authenticated using (is_platform_admin()) with check (is_platform_admin());
create policy "Niveaux admin suppr" on public.niveaux for delete to authenticated using (is_platform_admin());

-- Admins plateforme : chacun voit seulement s'il en fait partie ; gérés en SQL
create policy "Admin plateforme soi-même" on public.platform_admins for select to authenticated using (profile_id = auth.uid());

-- Clubs : visibles par leurs membres (CQ, coordinateurs, membres d'une équipe du
-- club) et l'admin plateforme. Création via create_club(). Modifié par le CQ.
-- Suppression : admin plateforme uniquement (supprimerait toutes les données liées).
create policy "Clubs lisibles" on public.clubs for select to authenticated
  using (is_club_member(id) or is_in_club_team(id) or is_platform_admin());
create policy "Clubs modif CQ" on public.clubs for update to authenticated
  using (is_club_cq(id) or is_platform_admin()) with check (is_club_cq(id) or is_platform_admin());
create policy "Clubs suppr admin" on public.clubs for delete to authenticated using (is_platform_admin());

-- Membres du club : visibles par les membres du club ; gérés par le CQ ; chacun
-- peut quitter un rôle (sauf le dernier CQ, bloqué par le garde-fou).
create policy "Membres club lisibles" on public.club_members for select to authenticated
  using (is_club_member(club_id) or is_platform_admin());
create policy "Membres club ajout CQ" on public.club_members for insert to authenticated
  with check (is_club_cq(club_id) or is_platform_admin());
create policy "Membres club modif CQ" on public.club_members for update to authenticated
  using (is_club_cq(club_id) or is_platform_admin()) with check (is_club_cq(club_id) or is_platform_admin());
create policy "Membres club suppr" on public.club_members for delete to authenticated
  using (is_club_cq(club_id) or is_platform_admin() or profile_id = auth.uid());

-- ------------------------------------------------------------------ DURCISSEMENT (analyse Supabase)
-- Par défaut, toute fonction est appelable par tous, y compris les visiteurs sans
-- compte (/rest/v1/rpc/…). Sans compte elles répondent « non », mais on ferme :
-- - fonctions d'aide et actions : utilisateurs connectés seulement (les règles RLS
--   en ont besoin, elles s'exécutent avec le rôle de l'utilisateur) ;
-- - fonctions de trigger : personne (un trigger s'exécute sans ce droit) ;
-- - public_scores reste ouverte : la page publique des scores l'utilise.
do $$ declare f text; begin
  foreach f in array array[
    'is_team_member(uuid)', 'is_team_admin(uuid)', 'is_team_creator(uuid)', 'shares_team_with(uuid)',
    'find_profile_by_email(text)', 'delete_team(uuid)',
    'is_platform_admin()', 'is_club_member(uuid)', 'is_club_cq(uuid)', 'is_any_club_staff()',
    'is_in_club_team(uuid)', 'create_club(text, integer, text, text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['handle_new_user()', 'guard_last_cq()', 'guard_club_verifie()'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

commit;
