-- ============================================================================
-- FootCoach — Propositions de match entre clubs (C2) — 2026-10-27
-- Nécessite C1 (annonces) et A1/A2 (clubs, rôles).
-- Une proposition : une équipe (« proposant ») répond à une annonce publiée d'un autre
-- club (« annonceur ») avec une date, une heure, un lieu (chez qui) et un message.
-- Proposition DIRECTE (sans annonce, annonce_id vide) : l'équipe proposante choisit une
-- équipe d'un autre club vérifié ; celle-ci joue le rôle de l'« annonceur » (elle répond).
-- Déroulé (statut) :
--   a_valider  préparée par un entraîneur/délégué, pas encore envoyée (invisible pour l'annonceur)
--   envoyee    au tour de l'annonceur de répondre
--   contre     contre-proposition de l'annonceur : au tour du proposant
--   acceptee   match créé dans le calendrier des DEUX équipes ; créneau de l'annonce pris
--   refusee / annulee
-- Qui agit : le coordinateur/CQ du club (« décide »). Un entraîneur/délégué qui agit
-- prépare une SUGGESTION (tour en attente) que son coordinateur/CQ valide ou écarte.
-- Toutes les actions passent par proposition_creer / proposition_agir (aucune écriture
-- directe dans les tables). Contacts (nom, email, téléphone) des coordinateurs/CQ de
-- l'autre club visibles dès qu'une proposition est envoyée (affichés à la demande : le
-- moyen de communication prioritaire est le message dans l'application,
-- proposition_message, avec compteur de non-lus par proposition).
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-10-27-C2-propositions-ANNULER.sql
-- ============================================================================
begin;

-- Téléphone facultatif sur le profil (contacts des propositions)
alter table public.profiles add column if not exists telephone text check (char_length(telephone) <= 30);

create table if not exists public.propositions (
  id uuid primary key default extensions.uuid_generate_v4(),
  annonce_id uuid references public.annonces(id) on delete cascade,   -- vide = proposition directe
  equipe_annonceur uuid not null references public.teams(id) on delete cascade,
  club_annonceur uuid not null references public.clubs(id) on delete cascade,
  equipe_proposante uuid not null references public.teams(id) on delete cascade,
  club_proposant uuid not null references public.clubs(id) on delete cascade,
  statut text not null default 'envoyee'
    check (statut in ('a_valider', 'envoyee', 'contre', 'acceptee', 'refusee', 'annulee')),
  jour date not null,
  heure time,
  lieu text not null default 'annonceur' check (lieu in ('annonceur', 'proposant')),   -- qui reçoit
  match_annonceur uuid references public.matches(id) on delete set null,
  match_proposant uuid references public.matches(id) on delete set null,
  cree_par uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists propositions_annonce_idx on public.propositions (annonce_id);
create index if not exists propositions_proposante_idx on public.propositions (equipe_proposante);
create index if not exists propositions_annonceur_idx on public.propositions (equipe_annonceur);
-- Une seule proposition en cours par équipe et par annonce
create unique index if not exists propositions_une_en_cours on public.propositions (annonce_id, equipe_proposante)
  where statut in ('a_valider', 'envoyee', 'contre');
alter table public.propositions alter column annonce_id drop not null;   -- rejouable (directes)
-- Directe : une seule en cours par couple d'équipes et par jour
create unique index if not exists propositions_directe_en_cours on public.propositions (equipe_proposante, equipe_annonceur, jour)
  where annonce_id is null and statut in ('a_valider', 'envoyee', 'contre');
alter table public.propositions enable row level security;

-- Historique : chaque action (et chaque suggestion en attente de validation)
create table if not exists public.proposition_tours (
  id uuid primary key default extensions.uuid_generate_v4(),
  proposition_id uuid not null references public.propositions(id) on delete cascade,
  cote text not null check (cote in ('annonceur', 'proposant')),
  action text not null,
  jour date,
  heure time,
  lieu text check (lieu in ('annonceur', 'proposant')),
  message text check (char_length(message) <= 1000),
  en_attente boolean not null default false,   -- suggestion d'un entraîneur, pas encore validée
  ecartee boolean not null default false,      -- suggestion écartée par le coordinateur
  auteur uuid references public.profiles(id) on delete set null,
  auteur_nom text,
  created_at timestamptz not null default now()
);
create index if not exists proposition_tours_prop_idx on public.proposition_tours (proposition_id, created_at);
-- Actions possibles (« message » = message libre entre les deux clubs, sans changer l'état)
alter table public.proposition_tours drop constraint if exists proposition_tours_action_check;
alter table public.proposition_tours add constraint proposition_tours_action_check
  check (action in ('proposition', 'envoyer', 'contre', 'accepter', 'refuser', 'annuler', 'message'));

-- Dernière lecture d'une proposition par personne (messages non lus)
create table if not exists public.proposition_lus (
  profile_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  proposition_id uuid not null references public.propositions(id) on delete cascade,
  lu_jusqua timestamptz not null default now(),
  primary key (profile_id, proposition_id)
);
alter table public.proposition_lus enable row level security;
drop policy if exists "Lus propositions personnels" on public.proposition_lus;
create policy "Lus propositions personnels" on public.proposition_lus for all to authenticated
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());
alter table public.proposition_tours enable row level security;

-- ------------------------------------------------------------ VISIBILITÉ
-- Côté de l'appelant : encadrement de l'équipe annonceuse ou proposante (club compris)
create or replace function public.prop_cote(p_id uuid) returns text
  language sql stable security definer set search_path = public as
$$ select case when is_team_staff(p.equipe_proposante) then 'proposant'
               when is_team_staff(p.equipe_annonceur) and p.statut <> 'a_valider' then 'annonceur' end
     from propositions p where p.id = p_id $$;

drop policy if exists "Propositions lecture" on public.propositions;
create policy "Propositions lecture" on public.propositions for select to authenticated
  using (prop_cote(id) is not null);
drop policy if exists "Tours lecture" on public.proposition_tours;
create policy "Tours lecture" on public.proposition_tours for select to authenticated
  using (prop_cote(proposition_id) is not null and (not en_attente or prop_cote(proposition_id) = cote));

create or replace function public.prop_nom_moi() returns text
  language sql stable security definer set search_path = public as
$$ select p.prenom || coalesce(' ' || left(nullif(p.nom, ''), 1) || '.', '') from profiles p where p.id = auth.uid() $$;

-- ------------------------------------------------------------ CRÉER
create or replace function public.proposition_creer(p_annonce uuid, p_team uuid, p_jour date, p_heure time,
                                                    p_lieu text, p_message text default null)
  returns uuid language plpgsql security definer set search_path = public as
$$ declare an annonces; v_club uuid; v_id uuid; v_statut text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not is_team_staff(p_team) then raise exception 'Tu n''encadres pas cette équipe'; end if;
  select t.club_id into v_club from teams t join clubs c on c.id = t.club_id where t.id = p_team and c.verifie;
  if v_club is null then raise exception 'L''équipe doit appartenir à un club vérifié'; end if;
  select * into an from annonces where id = p_annonce;
  if not found or an.statut <> 'publiee' or not can_see_annonce(p_annonce) then raise exception 'Annonce introuvable ou clôturée'; end if;
  if an.club_id = v_club then raise exception 'C''est une annonce de ton propre club'; end if;
  if p_jour is null or p_jour < current_date then raise exception 'Choisis une date à venir'; end if;
  if coalesce(p_lieu, '') not in ('annonceur', 'proposant') then raise exception 'Lieu invalide'; end if;
  v_statut := case when is_club_member(v_club) then 'envoyee' else 'a_valider' end;
  insert into propositions (annonce_id, equipe_annonceur, club_annonceur, equipe_proposante, club_proposant,
                            statut, jour, heure, lieu, cree_par)
  values (p_annonce, an.team_id, an.club_id, p_team, v_club, v_statut, p_jour, p_heure, p_lieu, auth.uid())
  returning id into v_id;
  insert into proposition_tours (proposition_id, cote, action, jour, heure, lieu, message, auteur, auteur_nom)
  values (v_id, 'proposant', 'proposition', p_jour, p_heure, p_lieu, nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
  return v_id;
exception when unique_violation then
  raise exception 'Une proposition de ton équipe est déjà en cours pour cette annonce';
end $$;

-- Proposition directe à une équipe d'un autre club vérifié (sans annonce)
create or replace function public.proposition_directe(p_team uuid, p_cible uuid, p_jour date, p_heure time,
                                                      p_lieu text, p_message text default null)
  returns uuid language plpgsql security definer set search_path = public as
$$ declare v_club uuid; v_club_cible uuid; v_id uuid; v_statut text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not is_team_staff(p_team) then raise exception 'Tu n''encadres pas cette équipe'; end if;
  select t.club_id into v_club from teams t join clubs c on c.id = t.club_id where t.id = p_team and c.verifie;
  if v_club is null then raise exception 'L''équipe doit appartenir à un club vérifié'; end if;
  select t.club_id into v_club_cible from teams t join clubs c on c.id = t.club_id where t.id = p_cible and c.verifie;
  if v_club_cible is null then raise exception 'Équipe introuvable (club non vérifié)'; end if;
  if v_club_cible = v_club then raise exception 'C''est une équipe de ton propre club'; end if;
  if p_jour is null or p_jour < current_date then raise exception 'Choisis une date à venir'; end if;
  if coalesce(p_lieu, '') not in ('annonceur', 'proposant') then raise exception 'Lieu invalide'; end if;
  v_statut := case when is_club_member(v_club) then 'envoyee' else 'a_valider' end;
  insert into propositions (annonce_id, equipe_annonceur, club_annonceur, equipe_proposante, club_proposant,
                            statut, jour, heure, lieu, cree_par)
  values (null, p_cible, v_club_cible, p_team, v_club, v_statut, p_jour, p_heure, p_lieu, auth.uid())
  returning id into v_id;
  insert into proposition_tours (proposition_id, cote, action, jour, heure, lieu, message, auteur, auteur_nom)
  values (v_id, 'proposant', 'proposition', p_jour, p_heure, p_lieu, nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
  return v_id;
exception when unique_violation then
  raise exception 'Une proposition de ton équipe est déjà en cours avec cette équipe ce jour-là';
end $$;

-- ------------------------------------------------------------ AGIR
-- p_action : envoyer | accepter | refuser | contre | annuler | valider_suggestion | ecarter_suggestion
-- Retour : le nouveau statut, 'suggestion' (préparée pour le coordinateur) ou 'ecartee'.
create or replace function public.proposition_agir(p_id uuid, p_action text, p_jour date default null,
                                                   p_heure time default null, p_lieu text default null,
                                                   p_message text default null)
  returns text language plpgsql security definer set search_path = public as
$$ declare p propositions; v_cote text; v_decide boolean; v_tour text; t proposition_tours;
           an annonces; v_date timestamptz; v_duree int; v_ma uuid; v_mp uuid; v_nom_a text; v_nom_p text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into p from propositions where id = p_id for update;
  if not found then raise exception 'Proposition introuvable'; end if;
  v_cote := prop_cote(p_id);
  if v_cote is null then raise exception 'Accès refusé'; end if;
  v_decide := is_club_member(case v_cote when 'annonceur' then p.club_annonceur else p.club_proposant end);
  if p.statut in ('acceptee', 'refusee', 'annulee') then raise exception 'Cette proposition est terminée'; end if;

  -- Suggestion d'un entraîneur : le coordinateur/CQ l'applique ou l'écarte
  if p_action in ('valider_suggestion', 'ecarter_suggestion') then
    -- Le coordinateur/CQ valide ou écarte ; l'entraîneur peut seulement RETIRER sa propre suggestion
    if not v_decide and not (p_action = 'ecarter_suggestion' and exists (select 1 from proposition_tours
         where proposition_id = p_id and cote = v_cote and en_attente and auteur = auth.uid())) then
      raise exception 'Réservé au coordinateur ou au CQ du club';
    end if;
    select * into t from proposition_tours where proposition_id = p_id and cote = v_cote and en_attente
      order by created_at desc limit 1;
    if not found then raise exception 'Aucune suggestion en attente'; end if;
    update proposition_tours set en_attente = false, ecartee = (p_action = 'ecarter_suggestion')
      where proposition_id = p_id and cote = v_cote and en_attente;
    if p_action = 'ecarter_suggestion' then return 'ecartee'; end if;
    p_action := t.action; p_jour := t.jour; p_heure := t.heure; p_lieu := t.lieu;
    p_message := coalesce(p_message, t.message);
  end if;

  if p_action = 'envoyer' then
    if v_cote <> 'proposant' or p.statut <> 'a_valider' then raise exception 'Rien à envoyer'; end if;
    if not v_decide then raise exception 'Réservé au coordinateur ou au CQ du club'; end if;
    update propositions set statut = 'envoyee', updated_at = now() where id = p_id;
    insert into proposition_tours (proposition_id, cote, action, message, auteur, auteur_nom)
    values (p_id, v_cote, 'envoyer', nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
    return 'envoyee';
  end if;

  if p_action = 'annuler' then
    if v_cote <> 'proposant' then raise exception 'Seule l''équipe qui propose peut annuler'; end if;
    if not v_decide and p.statut <> 'a_valider' then raise exception 'Réservé au coordinateur ou au CQ du club'; end if;
    update propositions set statut = 'annulee', updated_at = now() where id = p_id;
    insert into proposition_tours (proposition_id, cote, action, message, auteur, auteur_nom)
    values (p_id, v_cote, 'annuler', nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
    return 'annulee';
  end if;

  if p_action not in ('accepter', 'refuser', 'contre') then raise exception 'Action inconnue'; end if;
  v_tour := case p.statut when 'envoyee' then 'annonceur' when 'contre' then 'proposant' end;
  if v_tour is distinct from v_cote then raise exception 'Ce n''est pas à ton club de répondre maintenant'; end if;
  if p_action = 'contre' then
    if p_jour is null or p_jour < current_date then raise exception 'Choisis une date à venir'; end if;
    if coalesce(p_lieu, p.lieu) not in ('annonceur', 'proposant') then raise exception 'Lieu invalide'; end if;
  end if;

  -- Entraîneur / délégué : suggestion pour son coordinateur
  if not v_decide then
    update proposition_tours set en_attente = false, ecartee = true
      where proposition_id = p_id and cote = v_cote and en_attente;   -- une seule suggestion à la fois
    insert into proposition_tours (proposition_id, cote, action, jour, heure, lieu, message, en_attente, auteur, auteur_nom)
    values (p_id, v_cote, p_action, p_jour, p_heure, coalesce(p_lieu, p.lieu), nullif(trim(p_message), ''), true, auth.uid(), prop_nom_moi());
    return 'suggestion';
  end if;

  if p_action = 'refuser' then
    update propositions set statut = 'refusee', updated_at = now() where id = p_id;
    insert into proposition_tours (proposition_id, cote, action, message, auteur, auteur_nom)
    values (p_id, v_cote, 'refuser', nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
    return 'refusee';
  end if;

  if p_action = 'contre' then
    update propositions set jour = p_jour, heure = p_heure, lieu = coalesce(p_lieu, p.lieu),
      statut = case v_cote when 'annonceur' then 'contre' else 'envoyee' end, updated_at = now() where id = p_id;
    insert into proposition_tours (proposition_id, cote, action, jour, heure, lieu, message, auteur, auteur_nom)
    values (p_id, v_cote, 'contre', p_jour, p_heure, coalesce(p_lieu, p.lieu), nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
    return case v_cote when 'annonceur' then 'contre' else 'envoyee' end;
  end if;

  -- Accepter : match dans le calendrier des deux équipes, créneau pris
  if p.jour < current_date then raise exception 'La date proposée est passée : fais une contre-proposition'; end if;
  select * into an from annonces where id = p.annonce_id;
  v_date := (p.jour + coalesce(p.heure, time '10:00')) at time zone 'Europe/Brussels';
  select c.nom || ' ' || tm.nom into v_nom_a from teams tm join clubs c on c.id = tm.club_id where tm.id = p.equipe_annonceur;
  select c.nom || ' ' || tm.nom into v_nom_p from teams tm join clubs c on c.id = tm.club_id where tm.id = p.equipe_proposante;
  select coalesce(an.duree_mt, f.duree_mt, 30) into v_duree from teams tm left join formats f on f.code = tm.format where tm.id = p.equipe_annonceur;
  insert into matches (team_id, date, adversaire, lieu, statut, timeline_json)
  values (p.equipe_annonceur, v_date, v_nom_p, case p.lieu when 'annonceur' then 'domicile' else 'exterieur' end, 'prevu',
          jsonb_build_object('halfDuration', v_duree)) returning id into v_ma;
  insert into matches (team_id, date, adversaire, lieu, statut, timeline_json)
  values (p.equipe_proposante, v_date, v_nom_a, case p.lieu when 'proposant' then 'domicile' else 'exterieur' end, 'prevu',
          jsonb_build_object('halfDuration', v_duree)) returning id into v_mp;
  update propositions set statut = 'acceptee', match_annonceur = v_ma, match_proposant = v_mp, updated_at = now() where id = p_id;
  update annonce_creneaux set statut = 'pris' where annonce_id = p.annonce_id and jour = p.jour;
  insert into proposition_tours (proposition_id, cote, action, jour, heure, lieu, message, auteur, auteur_nom)
  values (p_id, v_cote, 'accepter', p.jour, p.heure, p.lieu, nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
  return 'acceptee';
end $$;

-- ------------------------------------------------------------ MESSAGES ENTRE CLUBS
-- Tout l'encadrement des deux équipes peut écrire (pas de validation : simple échange),
-- sauf tant que la proposition n'est pas envoyée (l'autre club ne la voit pas encore).
create or replace function public.proposition_message(p_id uuid, p_texte text)
  returns void language plpgsql security definer set search_path = public as
$$ declare v_cote text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  v_cote := prop_cote(p_id);
  if v_cote is null then raise exception 'Accès refusé'; end if;
  if char_length(trim(coalesce(p_texte, ''))) not between 1 and 1000 then raise exception 'Message vide ou trop long'; end if;
  if exists (select 1 from propositions where id = p_id and statut = 'a_valider') then
    raise exception 'La proposition n''est pas encore envoyée';
  end if;
  insert into proposition_tours (proposition_id, cote, action, message, auteur, auteur_nom)
  values (p_id, v_cote, 'message', trim(p_texte), auth.uid(), prop_nom_moi());
  insert into proposition_lus (profile_id, proposition_id, lu_jusqua) values (auth.uid(), p_id, now())
    on conflict (profile_id, proposition_id) do update set lu_jusqua = now();
end $$;

create or replace function public.proposition_lu(p_id uuid) returns void
  language sql security invoker set search_path = public as
$$ insert into proposition_lus (profile_id, proposition_id, lu_jusqua) values (auth.uid(), p_id, now())
   on conflict (profile_id, proposition_id) do update set lu_jusqua = now() $$;

-- ------------------------------------------------------------ CONTACTS ET LISTES
-- Coordinateurs / CQ de l'AUTRE club (proposition envoyée uniquement)
create or replace function public.proposition_contacts(p_id uuid)
  returns table(club text, nom text, role text, email text, telephone text)
  language sql stable security definer set search_path = public as
$$ select c.nom, pr.prenom || ' ' || pr.nom, cm.role, pr.email, pr.telephone
     from propositions p
     join clubs c on c.id = case prop_cote(p.id) when 'proposant' then p.club_annonceur else p.club_proposant end
     join club_members cm on cm.club_id = c.id
     join profiles pr on pr.id = cm.profile_id
    where p.id = p_id and prop_cote(p.id) is not null and p.statut <> 'a_valider'
    order by cm.role desc, pr.prenom $$;

-- Propositions visibles, avec noms des clubs / équipes et ce qu'il reste à faire pour moi
drop function if exists public.mes_propositions();   -- colonnes ajoutées (rejouable)
create or replace function public.mes_propositions()
  returns table(id uuid, annonce_id uuid, cote text, statut text, jour date, heure time, lieu text,
                annonce_type text, club_annonceur text, equipe_annonceur text, club_proposant text, equipe_proposante text,
                equipe_annonceur_id uuid, equipe_proposante_id uuid, decide boolean, a_moi boolean, suggestion text,
                match_id uuid, updated_at timestamptz, non_lus int)
  language sql stable security definer set search_path = public as
$$ select p.id, p.annonce_id, prop_cote(p.id), p.statut, p.jour, p.heure, p.lieu, an.type,
          ca.nom, ta.nom, cp.nom, tp.nom, p.equipe_annonceur, p.equipe_proposante,
          is_club_member(case prop_cote(p.id) when 'annonceur' then p.club_annonceur else p.club_proposant end),
          (p.statut = 'envoyee' and prop_cote(p.id) = 'annonceur') or (p.statut in ('contre', 'a_valider') and prop_cote(p.id) = 'proposant'),
          (select t.action from proposition_tours t where t.proposition_id = p.id and t.en_attente and t.cote = prop_cote(p.id)
            order by t.created_at desc limit 1),
          case prop_cote(p.id) when 'annonceur' then p.match_annonceur else p.match_proposant end,
          p.updated_at,
          (select count(*)::int from proposition_tours t where t.proposition_id = p.id and not t.en_attente
             and t.cote <> prop_cote(p.id)
             and t.created_at > coalesce((select l.lu_jusqua from proposition_lus l where l.profile_id = auth.uid() and l.proposition_id = p.id), '-infinity'))
     from propositions p
     left join annonces an on an.id = p.annonce_id   -- directe : pas d'annonce
     join teams ta on ta.id = p.equipe_annonceur join clubs ca on ca.id = p.club_annonceur
     join teams tp on tp.id = p.equipe_proposante join clubs cp on cp.id = p.club_proposant
    where prop_cote(p.id) is not null
    order by p.updated_at desc $$;

revoke execute on function public.prop_cote(uuid), public.prop_nom_moi(),
  public.proposition_creer(uuid, uuid, date, time, text, text),
  public.proposition_agir(uuid, text, date, time, text, text),
  public.proposition_contacts(uuid), public.mes_propositions(),
  public.proposition_message(uuid, text), public.proposition_lu(uuid),
  public.proposition_directe(uuid, uuid, date, time, text, text) from public, anon;
grant execute on function public.prop_cote(uuid), public.prop_nom_moi(),
  public.proposition_creer(uuid, uuid, date, time, text, text),
  public.proposition_agir(uuid, text, date, time, text, text),
  public.proposition_contacts(uuid), public.mes_propositions(),
  public.proposition_message(uuid, text), public.proposition_lu(uuid),
  public.proposition_directe(uuid, uuid, date, time, text, text) to authenticated;

commit;
