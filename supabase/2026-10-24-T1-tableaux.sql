-- ============================================================================
-- FootCoach — Tableau tactique (T1) : table « tableaux » — 2026-10-24
-- Un tableau = l'état d'un tableau tactique (pions, ballon, tracés, étapes) en JSON,
-- rattaché à une équipe, et éventuellement à un match et à une phase (avant / pause /
-- après). Un modèle (est_modele) n'a pas de match. Plusieurs tableaux par match.
-- - L'identifiant est généré par le téléphone (création possible hors ligne).
-- - Accès : ENCADREMENT de l'équipe uniquement (entraîneur, délégué, CQ/coordinateur
--   du club) ; ni parents, ni autres clubs, ni public.
-- - Données d'enfants : l'état ne contient que l'identifiant du joueur et le numéro de
--   poste, jamais le prénom (retrouvé à l'affichage, côté encadrement).
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-10-24-T1-tableaux-ANNULER.sql
-- ============================================================================
begin;

create table public.tableaux (
  id uuid primary key default extensions.uuid_generate_v4(),
  team_id uuid not null references public.teams(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete cascade,   -- rempli d'après l'équipe
  match_id uuid references public.matches(id) on delete cascade,
  phase text not null default 'libre' check (phase in ('avant', 'pause', 'apres', 'libre')),
  periode int check (periode between 1 and 10),                 -- n° de la pause (1 = mi-temps)
  titre text check (char_length(titre) <= 80),
  est_modele boolean not null default false,
  format text,
  etat jsonb not null default '{}'::jsonb,
  version int not null default 1,                               -- +1 à chaque modification (conflits hors ligne)
  cree_par uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  check (not est_modele or match_id is null)
);
create index tableaux_team_idx on public.tableaux (team_id);
create index tableaux_match_idx on public.tableaux (match_id);

-- Club d'après l'équipe ; un match doit appartenir à la même équipe ; version et date
create or replace function public.guard_tableau() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  select club_id into new.club_id from teams where id = new.team_id;
  if new.match_id is not null and not exists (select 1 from matches where id = new.match_id and team_id = new.team_id) then
    raise exception 'Le match n''appartient pas à cette équipe';
  end if;
  new.updated_at := now();
  if tg_op = 'UPDATE' then new.version := old.version + 1; end if;
  return new;
end $$;
create trigger tableaux_guard before insert or update on public.tableaux
  for each row execute function public.guard_tableau();

alter table public.tableaux enable row level security;
create policy "Tableaux encadrement" on public.tableaux for all to authenticated
  using (is_team_staff(team_id)) with check (is_team_staff(team_id));

revoke execute on function public.guard_tableau() from public, anon, authenticated;

commit;
