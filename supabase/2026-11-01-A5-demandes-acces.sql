-- ============================================================================
-- FootLink — Demandes d'accès depuis l'app (A5) — 2026-11-01
-- Nécessite A2 (rôles), A3 (parents) et C3 (notifications).
-- Une personne connectée choisit un club VÉRIFIÉ et demande un rôle :
--   coordinateur du club, entraîneur ou délégué d'une équipe, parent d'un joueur
--   (le parent écrit le prénom / nom de son enfant ; le validateur choisit l'enfant dans
--   l'effectif au moment d'accepter — le demandeur ne voit jamais l'effectif).
-- Qui valide : CQ et coordinateurs du club ; pour un rôle d'équipe, aussi l'encadrement
-- (entraîneur, délégué) de cette équipe. Coordinateur : club seulement.
-- À l'accord, l'accès est donné automatiquement (club_members / team_members /
-- parent_enfants). E-mails : demande à valider (validateurs), réponse (demandeur).
-- Le demandeur ne voit que les noms des clubs vérifiés et de leurs équipes.
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-11-01-A5-demandes-acces-ANNULER.sql
-- ============================================================================
begin;

create table public.demandes_acces (
  id uuid primary key default extensions.uuid_generate_v4(),
  profile_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  team_id uuid references public.teams(id) on delete cascade,
  role text not null check (role in ('coordinateur', 'entraineur', 'delegue', 'parent')),
  enfant text check (char_length(enfant) <= 80),            -- parent : prénom / nom écrit par le parent
  message text check (char_length(message) <= 500),
  statut text not null default 'en_attente' check (statut in ('en_attente', 'acceptee', 'refusee', 'annulee')),
  player_id uuid references public.players(id) on delete set null,   -- parent : enfant choisi à l'accord
  motif text check (char_length(motif) <= 300),             -- refus : explication facultative
  traite_par uuid references public.profiles(id) on delete set null,
  traite_le timestamptz,
  created_at timestamptz not null default now(),
  check ((role = 'coordinateur') = (team_id is null)),
  check (role <> 'parent' or enfant is not null)
);
create index demandes_acces_club_idx on public.demandes_acces (club_id) where statut = 'en_attente';
create unique index demandes_acces_une_en_attente on public.demandes_acces
  (profile_id, club_id, coalesce(team_id, '00000000-0000-0000-0000-000000000000'::uuid), role, coalesce(lower(enfant), ''))
  where statut = 'en_attente';
alter table public.demandes_acces enable row level security;

-- Peut-on valider cette demande ?
create or replace function public.demande_validable(d uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from demandes_acces x where x.id = d and (
     is_club_member(x.club_id) or (x.role <> 'coordinateur' and x.team_id is not null and is_team_staff(x.team_id)))) $$;

create policy "Demandes d'accès lecture" on public.demandes_acces for select to authenticated
  using (profile_id = auth.uid() or demande_validable(id));

-- Clubs vérifiés et leurs équipes (noms seulement) pour choisir où demander l'accès
create or replace function public.annuaire_clubs()
returns table(club_id uuid, club_nom text, equipes jsonb)
language sql stable security definer set search_path = public as
$$ select c.id, c.nom::text,
     coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'nom', t.nom, 'categorie', t.categorie) order by t.categorie, t.nom)
               from teams t where t.club_id = c.id), '[]'::jsonb)
   from clubs c where c.verifie and auth.uid() is not null order by c.nom $$;

-- Destinataires des e-mails d'une demande
create or replace function public.demande_validateurs(x demandes_acces) returns uuid[]
  language sql stable security definer set search_path = public as
$$ select array(select notif_club_staff(x.club_id)
                union select notif_team_staff(x.team_id) where x.role <> 'coordinateur' and x.team_id is not null) $$;
create or replace function public.demande_libelle(x demandes_acces) returns text
  language sql stable security definer set search_path = public as
$$ select case x.role when 'coordinateur' then 'coordinateur du club'
                      when 'entraineur' then 'entraîneur de l''équipe ' || t.nom
                      when 'delegue' then 'délégué de l''équipe ' || t.nom
                      else 'parent de « ' || x.enfant || ' » (équipe ' || t.nom || ')' end
          || ' — ' || c.nom
   from clubs c left join teams t on t.id = x.team_id where c.id = x.club_id $$;

-- Demander un accès
create or replace function public.demande_creer(p_club uuid, p_role text, p_team uuid default null,
                                                p_enfant text default null, p_message text default null)
  returns uuid language plpgsql security definer set search_path = public as
$$ declare v_id uuid; x demandes_acces;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from clubs where id = p_club and verifie) then raise exception 'Club introuvable'; end if;
  if p_role not in ('coordinateur', 'entraineur', 'delegue', 'parent') then raise exception 'Rôle inconnu'; end if;
  if p_role = 'coordinateur' then p_team := null;
  elsif p_team is null or not exists (select 1 from teams where id = p_team and club_id = p_club) then
    raise exception 'Choisis une équipe de ce club';
  end if;
  if p_role = 'parent' and nullif(trim(p_enfant), '') is null then raise exception 'Indique le prénom de ton enfant'; end if;
  -- Déjà l'accès demandé ?
  if (p_role = 'coordinateur' and exists (select 1 from club_members where club_id = p_club and profile_id = auth.uid()))
     or (p_role in ('entraineur', 'delegue') and exists (select 1 from team_members where team_id = p_team and profile_id = auth.uid()
                                                          and role in ('entraineur', 'delegue'))) then
    raise exception 'Tu as déjà cet accès';
  end if;
  insert into demandes_acces (club_id, team_id, role, enfant, message)
  values (p_club, p_team, p_role, nullif(trim(p_enfant), ''), nullif(trim(p_message), ''))
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'Cette demande est déjà en attente';
end $$;

-- Accepter ou refuser (validateurs) ; annuler (demandeur)
create or replace function public.demande_traiter(p_id uuid, p_action text, p_player uuid default null, p_motif text default null)
  returns text language plpgsql security definer set search_path = public as
$$ declare x demandes_acces;
begin
  select * into x from demandes_acces where id = p_id for update;
  if x.id is null or x.statut <> 'en_attente' then raise exception 'Demande introuvable ou déjà traitée'; end if;
  if p_action = 'annuler' then
    if x.profile_id <> auth.uid() then raise exception 'Accès refusé'; end if;
    update demandes_acces set statut = 'annulee', traite_le = now() where id = p_id;
    return 'annulee';
  end if;
  if not demande_validable(p_id) then raise exception 'Accès refusé'; end if;
  if p_action = 'refuser' then
    update demandes_acces set statut = 'refusee', motif = nullif(trim(p_motif), ''), traite_par = auth.uid(), traite_le = now() where id = p_id;
    return 'refusee';
  elsif p_action <> 'accepter' then
    raise exception 'Action inconnue';
  end if;
  if x.role = 'coordinateur' then
    insert into club_members (club_id, profile_id, role) values (x.club_id, x.profile_id, 'coordinateur')
      on conflict do nothing;
  elsif x.role in ('entraineur', 'delegue') then
    insert into team_members (team_id, profile_id, role) values (x.team_id, x.profile_id, x.role)
      on conflict (team_id, profile_id) do update set role = excluded.role;
  else
    if p_player is null or not exists (select 1 from players where id = p_player and team_id = x.team_id) then
      raise exception 'Choisis l''enfant dans l''effectif de l''équipe';
    end if;
    -- Parent : rôle « parent » dans l'équipe sauf s'il y a déjà un rôle (on ne rétrograde pas)
    insert into team_members (team_id, profile_id, role) values (x.team_id, x.profile_id, 'parent')
      on conflict (team_id, profile_id) do nothing;
    insert into parent_enfants (player_id, profile_id) values (p_player, x.profile_id)
      on conflict (player_id, profile_id) do nothing;
  end if;
  update demandes_acces set statut = 'acceptee', player_id = p_player, traite_par = auth.uid(), traite_le = now() where id = p_id;
  return 'acceptee';
end $$;

-- Liste pour l'app : mes demandes + celles que je peux valider (avec qui demande)
create or replace function public.mes_demandes_acces()
returns table(id uuid, cote text, club_id uuid, club_nom text, team_id uuid, team_nom text, role text, enfant text,
              message text, statut text, motif text, demandeur text, demandeur_email text, created_at timestamptz)
language sql stable security definer set search_path = public as
$$ select d.id, case when d.profile_id = auth.uid() then 'moi' else 'a_valider' end,
          d.club_id, c.nom::text, d.team_id, t.nom::text, d.role, d.enfant, d.message, d.statut, d.motif,
          trim(p.prenom || ' ' || p.nom), p.email, d.created_at
   from demandes_acces d join clubs c on c.id = d.club_id left join teams t on t.id = d.team_id
   join profiles p on p.id = d.profile_id
   where d.profile_id = auth.uid() or (d.statut = 'en_attente' and demande_validable(d.id))
   order by d.created_at desc $$;

-- E-mails : nouvelle demande → validateurs ; réponse → demandeur
create or replace function public.notif_demandes_acces() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare v_nom text;
begin
  if tg_op = 'INSERT' then
    select trim(prenom || ' ' || nom) || ' (' || coalesce(email, '?') || ')' into v_nom from profiles where id = new.profile_id;
    perform notif_ajouter(demande_validateurs(new), 'acces_demande', 'Demande d''accès à valider',
      v_nom || E' demande l''accès :\n' || demande_libelle(new)
        || coalesce(E'\n\nMessage : « ' || new.message || ' »', '')
        || E'\n\nAccepte ou refuse dans FootLink : menu du compte → Membres & accès.');
  elsif new.statut <> old.statut and new.statut in ('acceptee', 'refusee') then
    perform notif_ajouter(array[new.profile_id],
      case new.statut when 'acceptee' then 'acces_accepte' else 'acces_refuse' end,
      case new.statut when 'acceptee' then 'Accès accepté' else 'Demande d''accès refusée' end,
      case new.statut when 'acceptee' then E'Ta demande est acceptée : tu es maintenant ' || demande_libelle(new) || E'.\n\nOuvre FootLink pour commencer.'
           else E'Ta demande d''accès (' || demande_libelle(new) || E') a été refusée.' || coalesce(E'\nMotif : ' || new.motif, '')
                || E'\n\nPour toute question, contacte le club.' end);
  end if;
  return new;
end $$;
create trigger demandes_acces_notif after insert or update of statut on public.demandes_acces
  for each row execute function public.notif_demandes_acces();

revoke execute on function public.demande_validateurs(demandes_acces), public.demande_libelle(demandes_acces),
  public.notif_demandes_acces() from public, anon, authenticated;
revoke execute on function public.demande_validable(uuid), public.annuaire_clubs(), public.demande_creer(uuid, text, uuid, text, text),
  public.demande_traiter(uuid, text, uuid, text), public.mes_demandes_acces() from public, anon;
grant execute on function public.demande_validable(uuid), public.annuaire_clubs(), public.demande_creer(uuid, text, uuid, text, text),
  public.demande_traiter(uuid, text, uuid, text), public.mes_demandes_acces() to authenticated;

commit;
