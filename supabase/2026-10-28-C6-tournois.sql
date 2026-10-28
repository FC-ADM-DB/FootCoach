-- ============================================================================
-- FootLink — Tournois (C6) — 2026-10-28
-- Un tournoi est organisé par UN club, un jour donné, et contient un ou plusieurs
-- TABLEAUX (une catégorie chacun : U9, U11…). Chaque tableau a ses équipes, sa formule
-- (poules + phase finale, ou mini-championnat), ses matchs (terrain, heure, score) et
-- l'option « classement affiché ».
-- Organisation
-- - Organiser (créer, modifier, programme, accepter les inscriptions) : CQ /
--   coordinateur du club organisateur.
-- - Consulter dans l'app : membres du club organisateur et des clubs inscrits
--   (inscription acceptée). Aucune donnée de joueur dans ces tables.
-- Annonce et inscriptions (comme les propositions de match, C2)
-- - L'annonce est visible dans « Trouver un match » selon sa zone (Belgique, province,
--   distance ou clubs invités), tant que les inscriptions sont ouvertes.
-- - L'entraîneur / délégué d'un club invité PRÉPARE l'inscription ; le CQ / coordinateur
--   de son club l'ENVOIE ; l'organisateur l'accepte ou la refuse (équipe ajoutée au
--   tableau à l'accord). Messages entre les deux clubs sur chaque inscription.
-- - Catégorie pleine (places) : plus d'inscription possible ; un désistement libère la
--   place (« Place libre » gardée dans le programme, reprise par la prochaine équipe).
--   Rien n'est supprimé.
-- Scores
-- - Organisateur (et encadrement de ses équipes) : tous les matchs ; encadrement des
--   clubs inscrits : les matchs de leurs équipes (fonction tournoi_score).
-- - Option « validation des scores » : chaque score est à confirmer par l'autre équipe
--   (informatif, ne bloque pas le classement).
-- Public : tournoi_public(id) quand le tournoi est « publié » — scores seulement.
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
  -- Annonce / inscriptions
  inscriptions boolean not null default false,    -- annonce visible dans « Trouver un match »
  zone text not null default 'belgique' check (zone in ('belgique', 'province', 'distance', 'clubs')),
  distance_km int check (distance_km between 1 and 500),
  date_limite date,
  frais numeric(7,2) check (frais >= 0),
  frais_par text not null default 'equipe' check (frais_par in ('equipe', 'joueur')),
  paiement text check (char_length(paiement) <= 300),     -- modalités (virement, sur place…)
  max_par_club int check (max_par_club between 1 and 20), -- par tableau ; vide = pas de limite
  infos text check (char_length(infos) <= 2000),          -- règlement, accueil, buvette…
  contact text check (char_length(contact) <= 300),
  validation_scores boolean not null default false,       -- scores à confirmer par l'autre équipe
  cree_par uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz default now(),
  check (zone <> 'distance' or distance_km is not null)
);
create index tournois_club_idx on public.tournois (club_id);

-- Clubs invités (zone « clubs »)
create table public.tournoi_cibles (
  tournoi_id uuid not null references public.tournois(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  primary key (tournoi_id, club_id)
);

create table public.tournoi_tableaux (
  id uuid primary key default extensions.uuid_generate_v4(),
  tournoi_id uuid not null references public.tournois(id) on delete cascade,
  nom text not null check (char_length(nom) between 1 and 40),            -- ex. « U9 »
  format text,                                                             -- 5v5, 8v8…
  niveau text check (char_length(niveau) <= 40),
  annees text check (char_length(annees) <= 40),                           -- ex. « nés en 2018 »
  places int check (places between 2 and 64),                              -- vide = illimité
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

create table public.tournoi_inscriptions (
  id uuid primary key default extensions.uuid_generate_v4(),
  tournoi_id uuid not null references public.tournois(id) on delete cascade,
  tableau_id uuid not null references public.tournoi_tableaux(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,     -- club inscrit
  team_id uuid references public.teams(id) on delete set null,
  nom text not null check (char_length(nom) between 1 and 60),             -- nom affiché
  statut text not null check (statut in ('a_valider', 'envoyee', 'acceptee', 'refusee', 'annulee', 'desistee')),
  cree_par uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index tournoi_inscriptions_t_idx on public.tournoi_inscriptions (tournoi_id);
create unique index tournoi_inscriptions_en_cours on public.tournoi_inscriptions (tableau_id, team_id)
  where statut in ('a_valider', 'envoyee', 'acceptee');

create table public.tournoi_equipes (
  id uuid primary key default extensions.uuid_generate_v4(),
  tableau_id uuid not null references public.tournoi_tableaux(id) on delete cascade,
  nom text not null check (char_length(nom) between 1 and 60),
  team_id uuid references public.teams(id) on delete set null,             -- équipe FootLink
  club_id uuid references public.clubs(id) on delete set null,             -- son club
  inscription_id uuid references public.tournoi_inscriptions(id) on delete set null,
  libre boolean not null default false,                                    -- place libérée (désistement)
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
  confirme_a boolean not null default false,        -- score confirmé par l'équipe A / B (option)
  confirme_b boolean not null default false,
  ordre int not null default 0,
  updated_at timestamptz default now()
);
create index tournoi_matchs_tab_idx on public.tournoi_matchs (tableau_id);

create table public.tournoi_messages (
  id uuid primary key default extensions.uuid_generate_v4(),
  inscription_id uuid not null references public.tournoi_inscriptions(id) on delete cascade,
  cote text not null check (cote in ('organisateur', 'inscrit')),
  texte text not null check (char_length(texte) between 1 and 1000),
  auteur uuid default auth.uid() references public.profiles(id) on delete set null,
  auteur_nom text,
  created_at timestamptz default now()
);
create index tournoi_messages_i_idx on public.tournoi_messages (inscription_id);

-- ------------------------------------------------------------------ FONCTIONS D'ACCÈS
-- Club d'un tournoi / d'un tableau (SECURITY DEFINER : utilisables dans les policies)
create or replace function public.tournoi_club(t uuid) returns uuid
  language sql stable security definer set search_path = public as
$$ select club_id from tournois where id = t $$;
create or replace function public.tableau_tournoi(tb uuid) returns uuid
  language sql stable security definer set search_path = public as
$$ select tournoi_id from tournoi_tableaux where id = tb $$;
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

-- Lecture d'un tournoi : club organisateur, ou club dont une inscription est acceptée
create or replace function public.peut_voir_tournoi(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from tournois where id = t
                 and (is_club_member(club_id) or is_in_club_team(club_id)))
       or exists(select 1 from tournoi_inscriptions i where i.tournoi_id = t and i.statut = 'acceptee'
                 and (is_club_member(i.club_id) or is_in_club_team(i.club_id))) $$;

-- Annonce visible dans « Trouver un match » : inscriptions ouvertes, tournoi à venir,
-- organisateur vérifié, et un de MES clubs du réseau (autre que l'organisateur) dans la zone
create or replace function public.tournoi_visible_reseau(t uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (
  select 1 from tournois tr join clubs co on co.id = tr.club_id
  where tr.id = t and tr.inscriptions and tr.jour >= current_date and co.verifie
    and exists (select 1 from clubs mc where mc.id in (select public.mes_clubs_reseau()) and mc.id <> tr.club_id and (
         tr.zone = 'belgique'
      or (tr.zone = 'province' and mc.province_id is not null and mc.province_id = co.province_id)
      or (tr.zone = 'distance' and mc.lat is not null and co.lat is not null
          and public.km_entre(mc.lat, mc.lng, co.lat, co.lng) <= tr.distance_km)
      or (tr.zone = 'clubs' and exists (select 1 from tournoi_cibles tc where tc.tournoi_id = tr.id and tc.club_id = mc.id))))) $$;

-- Mon côté sur une inscription : 'organisateur', 'inscrit' (CQ / coordinateur du club
-- inscrit, ou encadrement de l'équipe inscrite), sinon null
create or replace function public.inscription_cote(i uuid) returns text
  language sql stable security definer set search_path = public as
$$ select case when is_club_member(t.club_id) then 'organisateur'
               when is_club_member(ins.club_id) or (ins.team_id is not null and is_team_staff(ins.team_id)) then 'inscrit' end
   from tournoi_inscriptions ins join tournois t on t.id = ins.tournoi_id where ins.id = i $$;

-- Places prises dans un tableau (les places libérées ne comptent pas)
create or replace function public.tableau_places_prises(tb uuid) returns int
  language sql stable security definer set search_path = public as
$$ select count(*)::int from tournoi_equipes where tableau_id = tb and not libre $$;

-- ------------------------------------------------------------------ GARDE-FOUS
-- Les équipes d'un match doivent appartenir au même tableau
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

-- Une équipe FootLink d'un AUTRE club n'entre dans un tableau que par une inscription
-- acceptée (sinon l'organisateur pourrait afficher le tournoi chez n'importe quel club).
create or replace function public.guard_tournoi_equipe() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare v_org uuid := public.tableau_club(new.tableau_id);
begin
  if new.team_id is not null then
    select club_id into new.club_id from teams where id = new.team_id;
  end if;
  if new.club_id is not null and new.club_id <> v_org and not exists (
       select 1 from tournoi_inscriptions where id = new.inscription_id and statut = 'acceptee'
         and club_id = new.club_id and tableau_id = new.tableau_id) then
    raise exception 'Une équipe d''un autre club entre par une inscription acceptée';
  end if;
  return new;
end $$;
create trigger tournoi_equipes_guard before insert or update on public.tournoi_equipes
  for each row execute function public.guard_tournoi_equipe();

-- ------------------------------------------------------------------ RÈGLES (RLS)
alter table public.tournois enable row level security;
alter table public.tournoi_cibles enable row level security;
alter table public.tournoi_tableaux enable row level security;
alter table public.tournoi_inscriptions enable row level security;
alter table public.tournoi_equipes enable row level security;
alter table public.tournoi_matchs enable row level security;
alter table public.tournoi_messages enable row level security;

create policy "Tournois lecture" on public.tournois for select to authenticated
  using (peut_voir_tournoi(id));
create policy "Tournois organisation" on public.tournois for all to authenticated
  using (is_club_member(club_id)) with check (is_club_member(club_id));

create policy "Cibles tournoi organisation" on public.tournoi_cibles for all to authenticated
  using (is_club_member(tournoi_club(tournoi_id))) with check (is_club_member(tournoi_club(tournoi_id)));

create policy "Tableaux tournoi lecture" on public.tournoi_tableaux for select to authenticated
  using (peut_voir_tournoi(tournoi_id));
create policy "Tableaux tournoi organisation" on public.tournoi_tableaux for all to authenticated
  using (is_club_member(tournoi_club(tournoi_id))) with check (is_club_member(tournoi_club(tournoi_id)));

create policy "Équipes tournoi lecture" on public.tournoi_equipes for select to authenticated
  using (peut_voir_tournoi(tableau_tournoi(tableau_id)));
create policy "Équipes tournoi organisation" on public.tournoi_equipes for all to authenticated
  using (is_club_member(tableau_club(tableau_id))) with check (is_club_member(tableau_club(tableau_id)));

create policy "Matchs tournoi lecture" on public.tournoi_matchs for select to authenticated
  using (peut_voir_tournoi(tableau_tournoi(tableau_id)));
create policy "Matchs tournoi organisation" on public.tournoi_matchs for all to authenticated
  using (is_club_member(tableau_club(tableau_id))) with check (is_club_member(tableau_club(tableau_id)));

-- Inscriptions et messages : lecture par les deux côtés ; écriture par les fonctions
create policy "Inscriptions tournoi lecture" on public.tournoi_inscriptions for select to authenticated
  using (inscription_cote(id) is not null);
create policy "Messages tournoi lecture" on public.tournoi_messages for select to authenticated
  using (inscription_cote(inscription_id) is not null);

-- ------------------------------------------------------------------ ANNONCES (RÉSEAU)
-- Tournois ouverts aux inscriptions que je peux voir, avec les places de chaque tableau
create or replace function public.tournois_reseau()
returns table(id uuid, nom text, jour date, lieu text, club_id uuid, club_nom text, club_logo text,
              km numeric, invite boolean, date_limite date, frais numeric, frais_par text, paiement text,
              max_par_club int, infos text, contact text, tableaux jsonb)
language sql stable security definer set search_path = public as
$$ select t.id, t.nom, t.jour, t.lieu, c.id, c.nom, c.logo,
     (select round(min(public.km_entre(mc.lat, mc.lng, c.lat, c.lng))::numeric, 1) from clubs mc
       where mc.id in (select public.mes_clubs_reseau()) and mc.lat is not null and c.lat is not null),
     exists (select 1 from tournoi_cibles tc where tc.tournoi_id = t.id and tc.club_id in (select public.mes_clubs_reseau())),
     t.date_limite, t.frais, t.frais_par, t.paiement, t.max_par_club, t.infos, t.contact,
     coalesce((select jsonb_agg(jsonb_build_object('id', tb.id, 'nom', tb.nom, 'format', tb.format, 'niveau', tb.niveau,
                 'annees', tb.annees, 'places', tb.places, 'prises', public.tableau_places_prises(tb.id)) order by tb.ordre, tb.nom)
               from tournoi_tableaux tb where tb.tournoi_id = t.id), '[]'::jsonb)
   from tournois t join clubs c on c.id = t.club_id
   where public.tournoi_visible_reseau(t.id)
   order by t.jour $$;

-- Clubs vérifiés du réseau (pour inviter des clubs précis)
create or replace function public.clubs_reseau() returns table(id uuid, nom text)
  language sql stable security definer set search_path = public as
$$ select c.id, c.nom::text from clubs c where c.verifie and exists (select 1 from public.mes_clubs_reseau()) order by c.nom $$;

-- Vérifie qu'une inscription peut (encore) être envoyée : délai, places, limite par club
create or replace function public.inscription_verifier(p_tableau uuid, p_club uuid, p_exclure uuid) returns void
  language plpgsql stable security definer set search_path = public as
$$ declare t tournois; tb tournoi_tableaux;
begin
  select * into tb from tournoi_tableaux where id = p_tableau;
  select * into t from tournois where id = tb.tournoi_id;
  if not t.inscriptions or t.jour < current_date then raise exception 'Les inscriptions sont fermées'; end if;
  if t.date_limite is not null and current_date > t.date_limite then raise exception 'La date limite d''inscription est passée'; end if;
  if tb.places is not null and public.tableau_places_prises(tb.id) >= tb.places then raise exception 'Catégorie complète'; end if;
  if t.max_par_club is not null and (select count(*) from tournoi_inscriptions
       where tableau_id = tb.id and club_id = p_club and statut in ('envoyee', 'acceptee') and id is distinct from p_exclure) >= t.max_par_club then
    raise exception 'Nombre maximum d''équipes par club atteint';
  end if;
end $$;

-- Inscrire une de mes équipes. Entraîneur / délégué → « à valider » par son
-- coordinateur ; CQ / coordinateur → envoyée directement à l'organisateur.
create or replace function public.tournoi_inscrire(p_tableau uuid, p_team uuid, p_message text default null)
  returns uuid language plpgsql security definer set search_path = public as
$$ declare v_t uuid := public.tableau_tournoi(p_tableau); v_club uuid; v_id uuid; v_statut text;
begin
  if v_t is null or not public.is_team_staff(p_team) then raise exception 'Accès refusé'; end if;
  select club_id into v_club from teams where id = p_team;
  if v_club is null or v_club = public.tournoi_club(v_t) or not exists (select 1 from clubs where id = v_club and verifie) then
    raise exception 'Équipe non autorisée';
  end if;
  if not public.tournoi_visible_reseau(v_t) then raise exception 'Tournoi non accessible'; end if;
  v_statut := case when public.is_club_member(v_club) then 'envoyee' else 'a_valider' end;
  if v_statut = 'envoyee' then perform public.inscription_verifier(p_tableau, v_club, null); end if;
  insert into tournoi_inscriptions (tournoi_id, tableau_id, club_id, team_id, nom, statut)
  values (v_t, p_tableau, v_club, p_team,
          (select left(c.nom || ' ' || tm.nom, 60) from teams tm join clubs c on c.id = tm.club_id where tm.id = p_team), v_statut)
  returning id into v_id;
  if nullif(trim(p_message), '') is not null then
    insert into tournoi_messages (inscription_id, cote, texte, auteur_nom)
    values (v_id, 'inscrit', left(trim(p_message), 1000), (select trim(prenom || ' ' || left(coalesce(nom, ''), 1) || '.') from profiles where id = auth.uid()));
  end if;
  return v_id;
end $$;

-- Actions sur une inscription (machine à états)
--  côté inscrit (CQ / coordinateur) : envoyer, annuler, desister ;
--    (l'entraîneur peut annuler sa propre inscription « à valider »)
--  côté organisateur : accepter, refuser, desister (retirer l'équipe)
create or replace function public.tournoi_inscription_agir(p_id uuid, p_action text)
  returns text language plpgsql security definer set search_path = public as
$$ declare i tournoi_inscriptions; v_org uuid; v_eq uuid; v_tb tournoi_tableaux;
begin
  select * into i from tournoi_inscriptions where id = p_id for update;
  if i.id is null then raise exception 'Inscription introuvable'; end if;
  v_org := public.tournoi_club(i.tournoi_id);
  if p_action = 'envoyer' and i.statut = 'a_valider' and public.is_club_member(i.club_id) then
    perform public.inscription_verifier(i.tableau_id, i.club_id, i.id);
    update tournoi_inscriptions set statut = 'envoyee', updated_at = now() where id = p_id;
    return 'envoyee';
  elsif p_action = 'annuler' and (
          (i.statut in ('a_valider', 'envoyee') and public.is_club_member(i.club_id))
       or (i.statut = 'a_valider' and i.cree_par = auth.uid())) then
    update tournoi_inscriptions set statut = 'annulee', updated_at = now() where id = p_id;
    return 'annulee';
  elsif p_action = 'refuser' and i.statut = 'envoyee' and public.is_club_member(v_org) then
    update tournoi_inscriptions set statut = 'refusee', updated_at = now() where id = p_id;
    return 'refusee';
  elsif p_action = 'accepter' and i.statut = 'envoyee' and public.is_club_member(v_org) then
    select * into v_tb from tournoi_tableaux where id = i.tableau_id;
    if v_tb.places is not null and public.tableau_places_prises(v_tb.id) >= v_tb.places then raise exception 'Catégorie complète'; end if;
    update tournoi_inscriptions set statut = 'acceptee', updated_at = now() where id = p_id;
    -- Une place libérée (désistement) est reprise : la nouvelle équipe garde sa poule et ses matchs
    select id into v_eq from tournoi_equipes where tableau_id = i.tableau_id and libre order by ordre limit 1;
    if v_eq is not null then
      update tournoi_equipes set libre = false, nom = i.nom, team_id = i.team_id, club_id = i.club_id, inscription_id = i.id where id = v_eq;
    else
      insert into tournoi_equipes (tableau_id, nom, team_id, club_id, inscription_id, poule, ordre)
      values (i.tableau_id, i.nom, i.team_id, i.club_id, i.id, case when v_tb.nb_poules = 1 then 'A' end,
              (select coalesce(max(ordre), 0) + 1 from tournoi_equipes where tableau_id = i.tableau_id));
    end if;
    return 'acceptee';
  elsif p_action = 'desister' and i.statut = 'acceptee' and (public.is_club_member(i.club_id) or public.is_club_member(v_org)) then
    update tournoi_inscriptions set statut = 'desistee', updated_at = now() where id = p_id;
    update tournoi_equipes set libre = true, nom = 'Place libre', team_id = null, club_id = null, inscription_id = null
      where inscription_id = p_id;
    return 'desistee';
  end if;
  raise exception 'Action impossible';
end $$;

-- Message sur une inscription (l'un ou l'autre club)
create or replace function public.tournoi_message(p_inscription uuid, p_texte text)
  returns void language plpgsql security definer set search_path = public as
$$ declare v_cote text := public.inscription_cote(p_inscription);
begin
  if v_cote is null then raise exception 'Accès refusé'; end if;
  if nullif(trim(p_texte), '') is null then raise exception 'Message vide'; end if;
  insert into tournoi_messages (inscription_id, cote, texte, auteur_nom)
  values (p_inscription, v_cote, left(trim(p_texte), 1000),
          (select trim(prenom || ' ' || left(coalesce(nom, ''), 1) || '.') from profiles where id = auth.uid()));
end $$;

-- Mes inscriptions (des deux côtés), avec « à traiter » pour les pastilles
create or replace function public.mes_inscriptions()
returns table(id uuid, tournoi_id uuid, tournoi_nom text, jour date, tableau_nom text, nom text,
              club_inscrit text, club_organisateur text, statut text, cote text, a_traiter boolean,
              created_at timestamptz, nb_messages int)
language sql stable security definer set search_path = public as
$$ select i.id, t.id, t.nom, t.jour, tb.nom, i.nom, ci.nom, co.nom, i.statut, public.inscription_cote(i.id),
     case public.inscription_cote(i.id)
       when 'organisateur' then i.statut = 'envoyee'
       when 'inscrit' then i.statut = 'a_valider' and public.is_club_member(i.club_id) end,
     i.created_at, (select count(*)::int from tournoi_messages m where m.inscription_id = i.id)
   from tournoi_inscriptions i
   join tournois t on t.id = i.tournoi_id join tournoi_tableaux tb on tb.id = i.tableau_id
   join clubs ci on ci.id = i.club_id join clubs co on co.id = t.club_id
   where public.inscription_cote(i.id) is not null
   order by t.jour, i.created_at $$;

-- ------------------------------------------------------------------ SCORES
-- Score d'un match.
--  - Organisateur et encadrement de ses équipes : tous les matchs (p_cote vide = table
--    de marque : score considéré confirmé par les deux équipes).
--  - Encadrement d'un club inscrit : les matchs de ses équipes, en indiquant son côté
--    (p_cote 'a' / 'b'). En phase finale (équipes déduites des résultats), il suffit
--    d'avoir une équipe dans le tableau.
--  - Option « validation des scores » : le côté qui saisit confirme ; l'autre équipe
--    doit confirmer (sauf équipe sans compte FootLink, confirmée d'office).
create or replace function public.tournoi_score(p_match uuid, p_a int, p_b int, p_statut text,
                                                p_vainqueur text default null, p_cote text default null)
  returns void language plpgsql security definer set search_path = public as
$$ declare m tournoi_matchs; v_org uuid; v_valid boolean; ea tournoi_equipes; eb tournoi_equipes;
  v_ca boolean; v_cb boolean;
begin
  select * into m from tournoi_matchs where id = p_match;
  if m.id is null then raise exception 'Accès refusé'; end if;
  if p_statut not in ('prevu', 'en_cours', 'termine') then raise exception 'Statut inconnu'; end if;
  v_org := public.tableau_club(m.tableau_id);
  select t.validation_scores into v_valid from tournois t join tournoi_tableaux tb on tb.tournoi_id = t.id where tb.id = m.tableau_id;
  select * into ea from tournoi_equipes where id = m.equipe_a;
  select * into eb from tournoi_equipes where id = m.equipe_b;
  if p_cote in ('a', 'b') then
    -- Côté annoncé : il faut encadrer l'équipe de ce côté (ou, en finale, une équipe du tableau)
    if not (
         (m.phase = 'poule' and p_cote = 'a' and ea.id is not null and ((ea.team_id is not null and is_team_staff(ea.team_id)) or (ea.club_id is not null and is_club_member(ea.club_id))))
      or (m.phase = 'poule' and p_cote = 'b' and eb.id is not null and ((eb.team_id is not null and is_team_staff(eb.team_id)) or (eb.club_id is not null and is_club_member(eb.club_id))))
      or (m.phase = 'finale' and exists (select 1 from tournoi_equipes e where e.tableau_id = m.tableau_id and not e.libre
            and ((e.team_id is not null and is_team_staff(e.team_id)) or (e.club_id is not null and is_club_member(e.club_id)))))
      or public.is_club_team_staff(v_org)) then
      raise exception 'Accès refusé';
    end if;
    v_ca := p_cote = 'a' or (m.phase = 'poule' and ea.team_id is null);
    v_cb := p_cote = 'b' or (m.phase = 'poule' and eb.team_id is null);
  elsif public.is_club_team_staff(v_org) then
    v_ca := true; v_cb := true;
  else
    raise exception 'Accès refusé';
  end if;
  if not v_valid then v_ca := true; v_cb := true; end if;
  update tournoi_matchs set score_a = p_a, score_b = p_b, statut = p_statut,
         vainqueur = case when p_vainqueur in ('a', 'b') then p_vainqueur end,
         confirme_a = v_ca, confirme_b = v_cb
   where id = p_match;
end $$;

-- Confirmer le score saisi par l'autre équipe (option « validation des scores »)
create or replace function public.tournoi_score_confirmer(p_match uuid, p_cote text)
  returns void language plpgsql security definer set search_path = public as
$$ declare m tournoi_matchs; e tournoi_equipes;
begin
  select * into m from tournoi_matchs where id = p_match;
  if m.id is null or p_cote not in ('a', 'b') then raise exception 'Accès refusé'; end if;
  if m.phase = 'poule' then
    select * into e from tournoi_equipes where id = case when p_cote = 'a' then m.equipe_a else m.equipe_b end;
    if e.id is null or not ((e.team_id is not null and is_team_staff(e.team_id)) or (e.club_id is not null and is_club_member(e.club_id))) then
      raise exception 'Accès refusé';
    end if;
  elsif not exists (select 1 from tournoi_equipes x where x.tableau_id = m.tableau_id and not x.libre
            and ((x.team_id is not null and is_team_staff(x.team_id)) or (x.club_id is not null and is_club_member(x.club_id)))) then
    raise exception 'Accès refusé';
  end if;
  update tournoi_matchs set confirme_a = confirme_a or p_cote = 'a', confirme_b = confirme_b or p_cote = 'b' where id = p_match;
end $$;

-- ------------------------------------------------------------------ PAGE PUBLIQUE
-- Tout le tournoi (s'il est publié) en un seul JSON. Noms d'équipes et scores seulement.
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
                     'score_a', m.score_a, 'score_b', m.score_b, 'statut', m.statut, 'vainqueur', m.vainqueur, 'ordre', m.ordre)
                     order by m.heure, m.terrain, m.ordre)
                   from tournoi_matchs m where m.tableau_id = tb.id), '[]'::jsonb)
      ) order by tb.ordre, tb.nom) from tournoi_tableaux tb where tb.tournoi_id = t.id), '[]'::jsonb)
  )
  from tournois t join clubs c on c.id = t.club_id
  where t.id = p_id and t.publie $$;

-- ------------------------------------------------------------------ DROITS D'EXÉCUTION
revoke execute on function public.guard_tournoi_match() from public, anon, authenticated;
revoke execute on function public.guard_tournoi_equipe() from public, anon, authenticated;
revoke execute on function public.inscription_verifier(uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.tournoi_club(uuid) from public, anon;
revoke execute on function public.tableau_tournoi(uuid) from public, anon;
revoke execute on function public.tableau_club(uuid) from public, anon;
revoke execute on function public.is_club_team_staff(uuid) from public, anon;
revoke execute on function public.peut_voir_tournoi(uuid) from public, anon;
revoke execute on function public.tournoi_visible_reseau(uuid) from public, anon;
revoke execute on function public.inscription_cote(uuid) from public, anon;
revoke execute on function public.tableau_places_prises(uuid) from public, anon;
revoke execute on function public.tournois_reseau() from public, anon;
revoke execute on function public.clubs_reseau() from public, anon;
revoke execute on function public.tournoi_inscrire(uuid, uuid, text) from public, anon;
revoke execute on function public.tournoi_inscription_agir(uuid, text) from public, anon;
revoke execute on function public.tournoi_message(uuid, text) from public, anon;
revoke execute on function public.mes_inscriptions() from public, anon;
revoke execute on function public.tournoi_score(uuid, int, int, text, text, text) from public, anon;
revoke execute on function public.tournoi_score_confirmer(uuid, text) from public, anon;
grant execute on function public.tournoi_club(uuid), public.tableau_tournoi(uuid), public.tableau_club(uuid),
  public.is_club_team_staff(uuid), public.peut_voir_tournoi(uuid), public.tournoi_visible_reseau(uuid),
  public.inscription_cote(uuid), public.tableau_places_prises(uuid), public.tournois_reseau(), public.clubs_reseau(),
  public.tournoi_inscrire(uuid, uuid, text), public.tournoi_inscription_agir(uuid, text),
  public.tournoi_message(uuid, text), public.mes_inscriptions(),
  public.tournoi_score(uuid, int, int, text, text, text), public.tournoi_score_confirmer(uuid, text) to authenticated;
revoke execute on function public.tournoi_public(uuid) from public;
grant execute on function public.tournoi_public(uuid) to anon, authenticated;

commit;
