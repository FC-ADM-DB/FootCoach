-- ============================================================================
-- FootCoach — Accès parents (A3) — 2026-10-27
-- 1. Lien parent ↔ enfant (parent_enfants) : un parent peut avoir plusieurs enfants.
-- 2. Invitations par lien (invitations_parent) : l'encadrement génère un lien depuis la
--    fiche du joueur ; le parent l'ouvre, se connecte, et devient « parent » de l'équipe,
--    rattaché à CET enfant. Lien limité (2 utilisations, 30 jours) et révocable.
-- 3. Un parent lit la fiche de SON enfant uniquement (jamais celles des autres).
-- 4. Réponse aux convocations (Présent / Absent / Incertain) pour son enfant, tant que
--    le match n'a pas commencé ; l'encadrement garde le dernier mot (colonnes reponse_*).
-- 5. Prénoms de l'équipe (« Prénom N. ») pour les membres de l'équipe : liste des
--    convoqués, buteurs (choix de l'utilisateur, A3).
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-10-27-A3-parents-ANNULER.sql
-- ============================================================================
begin;

-- Équipe d'un joueur, sans passer par les règles de « players » (évite toute récursion
-- entre les règles de players et de parent_enfants)
create or replace function public.player_team(p uuid) returns uuid
  language sql stable security definer set search_path = public as
$$ select team_id from players where id = p $$;

-- ------------------------------------------------------------ 1. LIEN PARENT ↔ ENFANT
create table if not exists public.parent_enfants (
  id uuid primary key default extensions.uuid_generate_v4(),
  player_id uuid not null references public.players(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  unique (player_id, profile_id)
);
create index if not exists parent_enfants_profile_idx on public.parent_enfants (profile_id);
alter table public.parent_enfants enable row level security;

create or replace function public.is_parent_of(p uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from parent_enfants where player_id = p and profile_id = auth.uid()) $$;

drop policy if exists "Liens parent lecture" on public.parent_enfants;
create policy "Liens parent lecture" on public.parent_enfants for select to authenticated
  using (profile_id = auth.uid() or is_team_staff(player_team(player_id)));
drop policy if exists "Liens parent ajout" on public.parent_enfants;
create policy "Liens parent ajout" on public.parent_enfants for insert to authenticated
  with check (is_team_staff(player_team(player_id)));
drop policy if exists "Liens parent retrait" on public.parent_enfants;
create policy "Liens parent retrait" on public.parent_enfants for delete to authenticated
  using (is_team_staff(player_team(player_id)) or profile_id = auth.uid());

-- ------------------------------------------------------------ 2. INVITATIONS
create table if not exists public.invitations_parent (
  token text primary key default encode(extensions.gen_random_bytes(16), 'hex'),
  player_id uuid not null references public.players(id) on delete cascade,
  cree_par uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz default now(),
  expire_le timestamptz not null default now() + interval '30 days',
  utilisations int not null default 0,
  max_utilisations int not null default 2 check (max_utilisations between 1 and 10),
  revoquee boolean not null default false
);
create index if not exists invitations_parent_player_idx on public.invitations_parent (player_id);
alter table public.invitations_parent enable row level security;
drop policy if exists "Invitations encadrement" on public.invitations_parent;
create policy "Invitations encadrement" on public.invitations_parent for all to authenticated
  using (is_team_staff(player_team(player_id))) with check (is_team_staff(player_team(player_id)));

-- Avant connexion : seulement l'équipe et le club (aucune donnée de l'enfant)
create or replace function public.invitation_info(p_token text)
  returns table(equipe text, club text, valide boolean)
  language sql stable security definer set search_path = public as
$$ select t.nom, c.nom,
          (not i.revoquee and i.expire_le > now() and i.utilisations < i.max_utilisations)
     from invitations_parent i join players p on p.id = i.player_id
     join teams t on t.id = p.team_id left join clubs c on c.id = t.club_id
    where i.token = p_token $$;

-- Rattachement : rôle « parent » dans l'équipe (sans jamais rétrograder un membre de
-- l'encadrement) + lien avec l'enfant. Une utilisation n'est comptée que pour un
-- nouveau lien (rouvrir le lien ne « consomme » rien).
drop function if exists public.rejoindre_invitation(text);   -- colonnes de retour renommées (rejouable)
create or replace function public.rejoindre_invitation(p_token text)
  returns table(equipe_id uuid, joueur_id uuid, prenom text)
  language plpgsql security definer set search_path = public as
$$ declare i invitations_parent; v_team uuid; v_prenom text; n int;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into i from invitations_parent where token = p_token for update;
  if not found then raise exception 'Invitation inconnue'; end if;
  select p.team_id, p.prenom into v_team, v_prenom from players p where p.id = i.player_id;
  if exists (select 1 from parent_enfants pe where pe.player_id = i.player_id and pe.profile_id = auth.uid()) then
    return query select v_team, i.player_id, v_prenom; return;
  end if;
  if i.revoquee or i.expire_le <= now() or i.utilisations >= i.max_utilisations then
    raise exception 'Invitation expirée ou déjà utilisée : demande un nouveau lien à l''entraîneur';
  end if;
  insert into team_members (team_id, profile_id, role) values (v_team, auth.uid(), 'parent')
    on conflict (team_id, profile_id) do nothing;
  insert into parent_enfants (player_id, profile_id) values (i.player_id, auth.uid())
    on conflict do nothing;
  get diagnostics n = row_count;
  if n > 0 then update invitations_parent set utilisations = utilisations + 1 where token = p_token; end if;
  return query select v_team, i.player_id, v_prenom;
end $$;

-- ------------------------------------------------------------ 3. FICHE DE SON ENFANT
drop policy if exists "Joueurs parent lecture" on public.players;
create policy "Joueurs parent lecture" on public.players for select to authenticated
  using (is_parent_of(id));

-- ------------------------------------------------------------ 4. RÉPONSES DES PARENTS
alter table public.convocations
  add column if not exists reponse_parent text check (reponse_parent in ('present', 'absent', 'incertain')),
  add column if not exists reponse_par uuid references public.profiles(id) on delete set null,
  add column if not exists reponse_le timestamptz;

create or replace function public.parent_repondre(p_match uuid, p_player uuid, p_statut text)
  returns void language plpgsql security definer set search_path = public as
$$ begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if p_statut not in ('present', 'absent', 'incertain') then raise exception 'Réponse invalide'; end if;
  if not is_parent_of(p_player) then raise exception 'Ce joueur n''est pas ton enfant'; end if;
  if not exists (select 1 from matches m where m.id = p_match and m.team_id = player_team(p_player)) then
    raise exception 'Match introuvable pour cette équipe';
  end if;
  if exists (select 1 from matches m where m.id = p_match and (m.statut <> 'prevu'
             or coalesce((m.timeline_json->>'matchStarted')::boolean, false))) then
    raise exception 'Le match a commencé : réponse fermée';
  end if;
  insert into convocations (match_id, player_id, statut, reponse_parent, reponse_par, reponse_le)
  values (p_match, p_player, p_statut, p_statut, auth.uid(), now())
  on conflict (match_id, player_id) do update
    set statut = excluded.statut, reponse_parent = excluded.reponse_parent,
        reponse_par = excluded.reponse_par, reponse_le = excluded.reponse_le, updated_at = now();
end $$;

-- ------------------------------------------------------------ 5. PRÉNOMS DE L'ÉQUIPE
create or replace function public.equipe_prenoms(p_team uuid)
  returns table(id uuid, label text)
  language sql stable security definer set search_path = public as
$$ select p.id, p.prenom || coalesce(' ' || left(nullif(p.nom, ''), 1) || '.', '')
     from players p where p.team_id = p_team and is_team_member(p_team) $$;

-- ------------------------------------------------------------ DROITS
revoke execute on function public.player_team(uuid), public.is_parent_of(uuid),
  public.invitation_info(text), public.rejoindre_invitation(text),
  public.parent_repondre(uuid, uuid, text), public.equipe_prenoms(uuid) from public, anon;
grant execute on function public.player_team(uuid), public.is_parent_of(uuid),
  public.invitation_info(text), public.rejoindre_invitation(text),
  public.parent_repondre(uuid, uuid, text), public.equipe_prenoms(uuid) to authenticated;
grant execute on function public.invitation_info(text) to anon;

commit;
