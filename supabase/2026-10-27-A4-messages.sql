-- ============================================================================
-- FootCoach — Messagerie encadrement ↔ parents (A4) — 2026-10-27
-- Nécessite A3 (parent_enfants, is_parent_of, player_team).
-- Deux sortes de discussions (« fils ») par équipe :
--   - groupe de l'équipe (player_id NULL) : encadrement + tous les parents de l'équipe ;
--   - discussion d'un enfant (player_id) : SES parents + l'encadrement de l'équipe.
-- Pas de notification push (service worker inchangé) : pastille de non-lus dans l'app,
-- calculée à partir de messages_lus (dernier message lu par fil et par personne).
-- Le nom affiché de l'auteur (« Prénom N. ») et son rôle sont figés à l'envoi : un CQ
-- qui n'est pas membre de l'équipe n'a pas besoin de lire les profils pour être nommé.
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-10-27-A4-messages-ANNULER.sql
-- ============================================================================
begin;

-- Qui voit un fil : groupe = tout membre de l'équipe ; enfant = encadrement ou ses parents
create or replace function public.peut_voir_fil(p_team uuid, p_player uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select case when p_player is null then is_team_member(p_team)
               else player_team(p_player) = p_team and (is_team_staff(p_team) or is_parent_of(p_player)) end $$;

create table if not exists public.messages (
  id uuid primary key default extensions.uuid_generate_v4(),
  team_id uuid not null references public.teams(id) on delete cascade,
  player_id uuid references public.players(id) on delete cascade,   -- NULL = groupe de l'équipe
  auteur uuid default auth.uid() references public.profiles(id) on delete set null,
  auteur_nom text,
  auteur_role text,
  texte text not null check (char_length(trim(texte)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists messages_fil_idx on public.messages (team_id, player_id, created_at);
alter table public.messages enable row level security;

-- Auteur = la personne connectée ; nom et rôle figés ; date du serveur
create or replace function public.guard_message() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  new.auteur := auth.uid();
  new.created_at := now();
  select p.prenom || coalesce(' ' || left(nullif(p.nom, ''), 1) || '.', '') into new.auteur_nom
    from profiles p where p.id = auth.uid();
  new.auteur_role := case when is_team_staff(new.team_id) then 'encadrement' else 'parent' end;
  return new;
end $$;
drop trigger if exists messages_guard on public.messages;
create trigger messages_guard before insert on public.messages
  for each row execute function public.guard_message();

drop policy if exists "Messages lecture" on public.messages;
create policy "Messages lecture" on public.messages for select to authenticated
  using (peut_voir_fil(team_id, player_id));
drop policy if exists "Messages envoi" on public.messages;
create policy "Messages envoi" on public.messages for insert to authenticated
  with check (peut_voir_fil(team_id, player_id));
-- Supprimer : son propre message, ou l'encadrement (modération). Pas de modification.
drop policy if exists "Messages suppression" on public.messages;
create policy "Messages suppression" on public.messages for delete to authenticated
  using (auteur = auth.uid() or is_team_staff(team_id));

-- ------------------------------------------------------------ LU / NON LU
create table if not exists public.messages_lus (
  profile_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  fil text not null,                         -- 'equipe' ou l'id de l'enfant
  lu_jusqua timestamptz not null default now(),
  primary key (profile_id, team_id, fil)
);
alter table public.messages_lus enable row level security;
drop policy if exists "Lus personnels" on public.messages_lus;
create policy "Lus personnels" on public.messages_lus for all to authenticated
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create or replace function public.marquer_lu(p_team uuid, p_player uuid) returns void
  language sql security invoker set search_path = public as
$$ insert into messages_lus (profile_id, team_id, fil, lu_jusqua)
   values (auth.uid(), p_team, coalesce(p_player::text, 'equipe'), now())
   on conflict (profile_id, team_id, fil) do update set lu_jusqua = now() $$;

-- Fils visibles avec leur dernier message et le nombre de non-lus (messages des autres
-- arrivés après la dernière lecture). Les règles de « messages » s'appliquent (INVOKER).
create or replace function public.mes_fils()
  returns table(team_id uuid, player_id uuid, dernier_texte text, dernier_auteur text, dernier_le timestamptz, non_lus int)
  language sql stable security invoker set search_path = public as
$$ select m.team_id, m.player_id,
          (array_agg(m.texte order by m.created_at desc))[1],
          (array_agg(m.auteur_nom order by m.created_at desc))[1],
          max(m.created_at),
          count(*) filter (where m.auteur is distinct from auth.uid()
                           and m.created_at > coalesce(l.lu_jusqua, '-infinity'))::int
     from messages m
     left join messages_lus l on l.profile_id = auth.uid() and l.team_id = m.team_id
                             and l.fil = coalesce(m.player_id::text, 'equipe')
    group by m.team_id, m.player_id, l.lu_jusqua $$;

revoke execute on function public.peut_voir_fil(uuid, uuid), public.guard_message(),
  public.marquer_lu(uuid, uuid), public.mes_fils() from public, anon;
grant execute on function public.peut_voir_fil(uuid, uuid), public.marquer_lu(uuid, uuid),
  public.mes_fils() to authenticated;

commit;
