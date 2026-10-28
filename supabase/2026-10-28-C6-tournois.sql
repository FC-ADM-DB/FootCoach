-- ============================================================================
-- FootLink — Tournois (C6, version « club organisateur ») — 2026-10-28
-- Un tournoi est organisé par UN club, un jour donné, et contient un ou plusieurs
-- TABLEAUX (une catégorie chacun : U9, U11…). Chaque tableau a ses équipes (les
-- nôtres ou celles d'autres clubs, saisies par leur nom), sa formule (poules + phase
-- finale, ou mini-championnat), ses matchs (terrain, heure, score) et l'option
-- « classement affiché ».
-- - Organiser (créer, modifier, programme) : CQ / coordinateur du club.
-- - Saisir les scores : aussi les entraîneurs / délégués des équipes du club
--   (fonction tournoi_score, qui ne touche qu'au score et au statut).
-- - Consulter dans l'app : tout membre d'une équipe du club (aucune donnée de joueur).
-- - Public : tournoi_public(id) quand le tournoi est « publié » — scores seulement.
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-10-28-C6-tournois-ANNULER.sql
-- ============================================================================
begin;

create table public.tournois (
  id uuid primary key default extensions.uuid_generate_v4(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  nom text not null check (char_length(nom) between 1 and 80),
  jour date not null,
  lieu text check (char_length(lieu) <= 160),
  publie boolean not null default false,          -- page publique accessible
  cree_par uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);
create index tournois_club_idx on public.tournois (club_id);

create table public.tournoi_tableaux (
  id uuid primary key default extensions.uuid_generate_v4(),
  tournoi_id uuid not null references public.tournois(id) on delete cascade,
  nom text not null check (char_length(nom) between 1 and 40),            -- ex. « U9 »
  format text,                                                             -- 5v5, 8v8…
  formule text not null default 'poules' check (formule in ('poules', 'championnat')),
  nb_poules int not null default 1 check (nb_poules between 1 and 8),
  qualifies int not null default 0 check (qualifies in (0, 2, 4, 8)),      -- équipes en phase finale
  classement boolean not null default true,                                -- classement affiché
  debut time not null default '09:00',
  duree_match int not null default 12 check (duree_match between 3 and 90),
  pause int not null default 3 check (pause between 0 and 60),
  terrains int not null default 2 check (terrains between 1 and 12),
  terrain1 int not null default 1 check (terrain1 between 1 and 30),       -- n° du 1er terrain utilisé
  pts_v int not null default 3, pts_n int not null default 1, pts_d int not null default 0,
  ordre int not null default 0
);
create index tournoi_tableaux_t_idx on public.tournoi_tableaux (tournoi_id);

create table public.tournoi_equipes (
  id uuid primary key default extensions.uuid_generate_v4(),
  tableau_id uuid not null references public.tournoi_tableaux(id) on delete cascade,
  nom text not null check (char_length(nom) between 1 and 60),
  team_id uuid references public.teams(id) on delete set null,             -- une de nos équipes
  poule text check (poule ~ '^[A-H]$'),
  ordre int not null default 0
);
create index tournoi_equipes_tab_idx on public.tournoi_equipes (tableau_id);

create table public.tournoi_matchs (
  id uuid primary key default extensions.uuid_generate_v4(),
  tableau_id uuid not null references public.tournoi_tableaux(id) on delete cascade,
  phase text not null default 'poule' check (phase in ('poule', 'finale')),
  poule text,
  tour int not null default 1,                       -- finale : 1 = 1er tour… (le dernier = finale)
  libelle text check (char_length(libelle) <= 40),   -- ex. « Demi-finale 1 »
  equipe_a uuid references public.tournoi_equipes(id) on delete set null,
  equipe_b uuid references public.tournoi_equipes(id) on delete set null,
  -- Phase finale : équipes déduites du classement / des résultats (codes « P:A:1 » =
  -- 1er de la poule A, « V:3 » = vainqueur du match n° 3 du tableau), jamais figées.
  source_a text check (char_length(source_a) <= 40),
  source_b text check (char_length(source_b) <= 40),
  terrain int,
  heure time,
  score_a int check (score_a between 0 and 99),
  score_b int check (score_b between 0 and 99),
  statut text not null default 'prevu' check (statut in ('prevu', 'en_cours', 'termine')),
  vainqueur text check (vainqueur in ('a', 'b')),   -- égalité en phase finale : vainqueur aux tirs au but
  ordre int not null default 0,
  updated_at timestamptz default now()
);
create index tournoi_matchs_tab_idx on public.tournoi_matchs (tableau_id);

-- Club d'un tournoi / d'un tableau (SECURITY DEFINER : utilisables dans les policies)
create or replace function public.tournoi_club(t uuid) returns uuid
  language sql stable security definer set search_path = public as
$$ select club_id from tournois where id = t $$;
create or replace function public.tableau_club(tb uuid) returns uuid
  language sql stable security definer set search_path = public as
$$ select t.club_id from tournoi_tableaux tb2 join tournois t on t.id = tb2.tournoi_id where tb2.id = tb $$;

-- Encadrement d'au moins une équipe du club (entraîneur, délégué) ou CQ / coordinateur
create or replace function public.is_club_team_staff(c uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select public.is_club_member(c)
       or exists(select 1 from teams t join team_members tm on tm.team_id = t.id
                 where t.club_id = c and tm.profile_id = auth.uid()
                   and tm.role in ('entraineur', 'delegue')) $$;

-- Les équipes d'un match doivent appartenir au même tableau ; une équipe « à nous »
-- doit être une équipe du club organisateur.
create or replace function public.guard_tournoi_match() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  if (new.equipe_a is not null and not exists (select 1 from tournoi_equipes where id = new.equipe_a and tableau_id = new.tableau_id))
     or (new.equipe_b is not null and not exists (select 1 from tournoi_equipes where id = new.equipe_b and tableau_id = new.tableau_id)) then
    raise exception 'Équipe d''un autre tableau';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger tournoi_matchs_guard before insert or update on public.tournoi_matchs
  for each row execute function public.guard_tournoi_match();

create or replace function public.guard_tournoi_equipe() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  if new.team_id is not null and not exists (
       select 1 from teams where id = new.team_id and club_id = public.tableau_club(new.tableau_id)) then
    raise exception 'Cette équipe n''est pas une équipe du club organisateur';
  end if;
  return new;
end $$;
create trigger tournoi_equipes_guard before insert or update on public.tournoi_equipes
  for each row execute function public.guard_tournoi_equipe();

alter table public.tournois enable row level security;
alter table public.tournoi_tableaux enable row level security;
alter table public.tournoi_equipes enable row level security;
alter table public.tournoi_matchs enable row level security;

-- Lecture : membres du club (staff du club ou n'importe quel rôle dans une de ses équipes)
create policy "Tournois lecture" on public.tournois for select to authenticated
  using (is_club_member(club_id) or is_in_club_team(club_id));
create policy "Tournois organisation" on public.tournois for all to authenticated
  using (is_club_member(club_id)) with check (is_club_member(club_id));

create policy "Tableaux tournoi lecture" on public.tournoi_tableaux for select to authenticated
  using (is_club_member(tournoi_club(tournoi_id)) or is_in_club_team(tournoi_club(tournoi_id)));
create policy "Tableaux tournoi organisation" on public.tournoi_tableaux for all to authenticated
  using (is_club_member(tournoi_club(tournoi_id))) with check (is_club_member(tournoi_club(tournoi_id)));

create policy "Équipes tournoi lecture" on public.tournoi_equipes for select to authenticated
  using (is_club_member(tableau_club(tableau_id)) or is_in_club_team(tableau_club(tableau_id)));
create policy "Équipes tournoi organisation" on public.tournoi_equipes for all to authenticated
  using (is_club_member(tableau_club(tableau_id))) with check (is_club_member(tableau_club(tableau_id)));

create policy "Matchs tournoi lecture" on public.tournoi_matchs for select to authenticated
  using (is_club_member(tableau_club(tableau_id)) or is_in_club_team(tableau_club(tableau_id)));
create policy "Matchs tournoi organisation" on public.tournoi_matchs for all to authenticated
  using (is_club_member(tableau_club(tableau_id))) with check (is_club_member(tableau_club(tableau_id)));

-- Score d'un match : organisateur OU encadrement d'une équipe du club. Ne modifie que
-- le score et le statut (pas les équipes, l'heure ou le terrain).
create or replace function public.tournoi_score(p_match uuid, p_a int, p_b int, p_statut text, p_vainqueur text default null)
  returns void language plpgsql security definer set search_path = public as
$$ declare c uuid;
begin
  select tableau_club(tableau_id) into c from tournoi_matchs where id = p_match;
  if c is null or not is_club_team_staff(c) then raise exception 'Accès refusé'; end if;
  if p_statut not in ('prevu', 'en_cours', 'termine') then raise exception 'Statut inconnu'; end if;
  update tournoi_matchs set score_a = p_a, score_b = p_b, statut = p_statut,
         vainqueur = case when p_vainqueur in ('a', 'b') then p_vainqueur end where id = p_match;
end $$;

-- Page publique : tout le tournoi (s'il est publié) en un seul JSON. Noms d'équipes et
-- scores seulement — aucune donnée de joueur n'existe dans ces tables.
create or replace function public.tournoi_public(p_id uuid) returns jsonb
  language sql stable security definer set search_path = public as
$$ select jsonb_build_object(
    'nom', t.nom, 'jour', t.jour, 'lieu', t.lieu,
    'club', jsonb_build_object('nom', c.nom, 'logo', c.logo, 'couleur1', c.couleur1, 'couleur2', c.couleur2),
    'tableaux', coalesce((select jsonb_agg(jsonb_build_object(
        'id', tb.id, 'nom', tb.nom, 'formule', tb.formule, 'nb_poules', tb.nb_poules,
        'qualifies', tb.qualifies, 'classement', tb.classement, 'terrain1', tb.terrain1,
        'pts_v', tb.pts_v, 'pts_n', tb.pts_n, 'pts_d', tb.pts_d,
        'equipes', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'nom', e.nom, 'poule', e.poule) order by e.poule, e.ordre)
                             from tournoi_equipes e where e.tableau_id = tb.id), '[]'::jsonb),
        'matchs', coalesce((select jsonb_agg(jsonb_build_object(
                     'id', m.id, 'phase', m.phase, 'poule', m.poule, 'tour', m.tour, 'libelle', m.libelle,
                     'equipe_a', m.equipe_a, 'equipe_b', m.equipe_b, 'source_a', m.source_a, 'source_b', m.source_b,
                     'terrain', m.terrain, 'heure', to_char(m.heure, 'HH24:MI'),
                     'score_a', m.score_a, 'score_b', m.score_b, 'statut', m.statut, 'vainqueur', m.vainqueur, 'ordre', m.ordre) order by m.heure, m.terrain, m.ordre)
                   from tournoi_matchs m where m.tableau_id = tb.id), '[]'::jsonb)
      ) order by tb.ordre, tb.nom) from tournoi_tableaux tb where tb.tournoi_id = t.id), '[]'::jsonb)
  )
  from tournois t join clubs c on c.id = t.club_id
  where t.id = p_id and t.publie $$;

revoke execute on function public.guard_tournoi_match() from public, anon, authenticated;
revoke execute on function public.guard_tournoi_equipe() from public, anon, authenticated;
revoke execute on function public.tournoi_club(uuid) from public, anon;
revoke execute on function public.tableau_club(uuid) from public, anon;
revoke execute on function public.is_club_team_staff(uuid) from public, anon;
revoke execute on function public.tournoi_score(uuid, int, int, text, text) from public, anon;
grant execute on function public.tournoi_club(uuid) to authenticated;
grant execute on function public.tableau_club(uuid) to authenticated;
grant execute on function public.is_club_team_staff(uuid) to authenticated;
grant execute on function public.tournoi_score(uuid, int, int, text, text) to authenticated;
revoke execute on function public.tournoi_public(uuid) from public;
grant execute on function public.tournoi_public(uuid) to anon, authenticated;

commit;
