-- ============================================================================
-- FootCoach — STRUCTURE DE RÉFÉRENCE de la production au 2026-10-23
-- Reconstituée depuis supabase/outils/export-schema.sql (aucune donnée).
-- Sert à recréer une base identique pour les tests (projet FootLink) :
-- NE PAS exécuter sur la production (les tables y existent déjà).
-- ============================================================================
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;
set search_path = public, extensions;

-- ---------------------------------------------------------------- TABLES
create table public.seasons (
  id uuid primary key default uuid_generate_v4(),
  label text not null,
  debut date,
  fin date,
  created_at timestamptz default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  prenom text not null,
  nom text not null,
  email text,
  created_at timestamptz default now()
);

create table public.teams (
  id uuid primary key default uuid_generate_v4(),
  nom text not null,
  categorie text not null,
  format text not null default '8v8',
  couleur text default '#1D9E75',
  saison_id uuid references public.seasons(id),
  created_at timestamptz default now(),
  logo text,
  created_by uuid default auth.uid()
);

create table public.team_members (
  id uuid primary key default uuid_generate_v4(),
  team_id uuid references public.teams(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete cascade,
  role text not null default 'delegue',
  created_at timestamptz default now(),
  unique (team_id, profile_id)
);

create table public.players (
  id uuid primary key default uuid_generate_v4(),
  team_id uuid references public.teams(id) on delete cascade,
  prenom text not null,
  nom text not null,
  -- colonne calculée (l'export l'affichait comme une valeur par défaut)
  initiales text generated always as (upper(left(prenom, 1)) || upper(left(nom, 1))) stored,
  numero_poste integer,
  date_naissance date,
  actif boolean default true,
  created_at timestamptz default now()
);

create table public.matches (
  id uuid primary key default uuid_generate_v4(),
  team_id uuid references public.teams(id) on delete cascade,
  date timestamptz not null,
  adversaire text not null,
  lieu text,
  score_nous integer,
  score_eux integer,
  commentaire text,
  tactique_json jsonb,
  timeline_json jsonb,
  statut text default 'prevu',
  created_at timestamptz default now()
);

create table public.convocations (
  id uuid primary key default uuid_generate_v4(),
  match_id uuid references public.matches(id) on delete cascade,
  player_id uuid references public.players(id) on delete cascade,
  statut text default 'inconnu',
  raison text,
  commentaire text,
  updated_at timestamptz default now(),
  unique (match_id, player_id)
);

create table public.match_players (
  id uuid primary key default uuid_generate_v4(),
  match_id uuid references public.matches(id) on delete cascade,
  player_id uuid references public.players(id) on delete cascade,
  titulaire boolean default false,
  poste_joue integer,
  secondes_jeu integer default 0,
  segments jsonb,
  created_at timestamptz default now(),
  unique (match_id, player_id)
);

create table public.player_notes (
  id uuid primary key default uuid_generate_v4(),
  player_id uuid references public.players(id) on delete cascade,
  auteur_id uuid references public.profiles(id),
  date date default current_date,
  note text not null,
  created_at timestamptz default now()
);

create table public.trainings (
  id uuid primary key default uuid_generate_v4(),
  team_id uuid references public.teams(id) on delete cascade,
  date date not null,
  duree_min integer default 90,
  theme text,
  contenu jsonb,
  terrain_json jsonb,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table public.training_attendance (
  id uuid primary key default uuid_generate_v4(),
  training_id uuid references public.trainings(id) on delete cascade,
  player_id uuid references public.players(id) on delete cascade,
  present boolean default true,
  commentaire text,
  unique (training_id, player_id)
);

-- ---------------------------------------------------------------- FONCTIONS (copie conforme)
create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer as
$$ begin
  insert into public.profiles (id, prenom, nom, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'prenom','Prénom'),
          coalesce(new.raw_user_meta_data->>'nom','Nom'), new.email);
  return new;
end; $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_team_member(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members where team_id = t and profile_id = auth.uid()) $$;

create or replace function public.is_team_admin(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members where team_id = t and profile_id = auth.uid() and role = 'admin') $$;

create or replace function public.is_team_creator(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from teams where id = t and created_by = auth.uid()) $$;

create or replace function public.shares_team_with(p uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from team_members a join team_members b on b.team_id = a.team_id
                 where a.profile_id = auth.uid() and b.profile_id = p) $$;

create or replace function public.find_profile_by_email(e text)
  returns table(id uuid, prenom text, nom text, email text)
  language sql stable security definer set search_path = public as
$$ select p.id, p.prenom::text, p.nom::text, p.email::text from profiles p
   where lower(p.email) = lower(trim(e))
     and exists(select 1 from team_members where profile_id = auth.uid() and role = 'admin') $$;

create or replace function public.delete_team(t uuid) returns void
  language plpgsql security definer set search_path = public as
$$ begin
  if not public.is_team_admin(t) then raise exception 'Accès admin requis'; end if;
  delete from team_members where team_id = t;
  delete from teams where id = t;
end $$;

-- ---------------------------------------------------------------- RLS + RÈGLES (copie conforme)
alter table public.seasons enable row level security;
alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.players enable row level security;
alter table public.matches enable row level security;
alter table public.convocations enable row level security;
alter table public.match_players enable row level security;
alter table public.player_notes enable row level security;
alter table public.trainings enable row level security;
alter table public.training_attendance enable row level security;

create policy "Saisons créables" on public.seasons for insert to public with check (true);
create policy "Saisons lisibles" on public.seasons for select to public using (true);

create policy "Profil personnel" on public.profiles for all to public using (auth.uid() = id);
create policy "Profils des coéquipiers" on public.profiles for select to authenticated using (shares_team_with(id));

create policy "Teams select" on public.teams for select to authenticated using (is_team_member(id) or created_by = auth.uid());
create policy "Teams insert" on public.teams for insert to authenticated with check (created_by = auth.uid());
create policy "Teams update" on public.teams for update to authenticated using (is_team_admin(id)) with check (is_team_admin(id));
create policy "Teams delete" on public.teams for delete to authenticated using (is_team_admin(id));

create policy "Members select" on public.team_members for select to authenticated using (profile_id = auth.uid() or is_team_member(team_id));
create policy "Members insert" on public.team_members for insert to authenticated with check (is_team_admin(team_id) or (profile_id = auth.uid() and is_team_creator(team_id)));
create policy "Members update" on public.team_members for update to authenticated using (is_team_admin(team_id)) with check (is_team_admin(team_id));
create policy "Members delete" on public.team_members for delete to authenticated using (is_team_admin(team_id) or profile_id = auth.uid());

create policy "Joueurs de mes équipes" on public.players for all to public
  using (exists (select 1 from team_members where team_members.team_id = players.team_id and team_members.profile_id = auth.uid()));
create policy "Matchs de mes équipes" on public.matches for all to public
  using (exists (select 1 from team_members where team_members.team_id = matches.team_id and team_members.profile_id = auth.uid()));
create policy "Convocations accessibles" on public.convocations for all to public
  using (exists (select 1 from matches m join team_members tm on tm.team_id = m.team_id where m.id = convocations.match_id and tm.profile_id = auth.uid()));
create policy "Stats match accessibles" on public.match_players for all to public
  using (exists (select 1 from matches m join team_members tm on tm.team_id = m.team_id where m.id = match_players.match_id and tm.profile_id = auth.uid()));
create policy "Notes accessibles" on public.player_notes for all to public
  using (exists (select 1 from players p join team_members tm on tm.team_id = p.team_id where p.id = player_notes.player_id and tm.profile_id = auth.uid()));
create policy "Séances accessibles" on public.trainings for all to public
  using (exists (select 1 from team_members where team_members.team_id = trainings.team_id and team_members.profile_id = auth.uid()));
create policy "Présences accessibles" on public.training_attendance for all to public
  using (exists (select 1 from trainings t join team_members tm on tm.team_id = t.team_id where t.id = training_attendance.training_id and tm.profile_id = auth.uid()));
