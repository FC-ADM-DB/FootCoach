-- ============================================================================
-- FootCoach — Phase C1 : annonces « Trouver un match » — 2026-10-23
-- Une équipe publie des créneaux libres (amical, tournoi, entraînement commun),
-- les autres clubs vérifiés les consultent. AUCUNE donnée de joueur n'est liée.
--
-- Circuit : un entraîneur/délégué prépare une annonce pour SON équipe et l'envoie
-- « à valider » ; le CQ/coordinateur du club la publie (ou la refuse avec un
-- commentaire) ; un CQ/coordinateur peut aussi publier directement.
-- Visibilité d'une annonce publiée : encadrement des clubs VÉRIFIÉS, selon la zone
-- choisie (toute la Belgique, la province, une distance en km, ou des équipes
-- choisies). Le club qui publie doit lui-même être vérifié.
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-10-23-C1-annonces-ANNULER.sql
-- ============================================================================
begin;

-- ------------------------------------------------------------------ TABLES
create table public.annonces (
  id uuid primary key default extensions.uuid_generate_v4(),
  team_id uuid not null references public.teams(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete cascade,  -- rempli d'après l'équipe
  type text not null default 'amical' check (type in ('amical', 'tournoi', 'entrainement')),
  lieu text not null default 'indifferent' check (lieu in ('domicile', 'exterieur', 'indifferent')),
  format text references public.formats(code),
  duree_mt int check (duree_mt between 5 and 60),
  categories text[] not null default '{}',   -- catégories acceptées (vide = toutes)
  niveaux int[] not null default '{}',       -- niveaux acceptés (vide = tous)
  zone text not null default 'province' check (zone in ('belgique', 'province', 'distance', 'equipes')),
  distance_km int check (distance_km between 1 and 500),
  message text check (char_length(message) <= 1000),
  statut text not null default 'brouillon'
    check (statut in ('brouillon', 'a_valider', 'refusee', 'publiee', 'cloturee')),
  commentaire_validation text,               -- motif d'un refus par le coordinateur
  cree_par uuid default auth.uid() references public.profiles(id) on delete set null,
  valide_par uuid references public.profiles(id) on delete set null,
  publiee_le timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  check (zone <> 'distance' or distance_km is not null)
);
create index annonces_statut_idx on public.annonces (statut);
create index annonces_club_idx on public.annonces (club_id);

create table public.annonce_creneaux (
  id uuid primary key default extensions.uuid_generate_v4(),
  annonce_id uuid not null references public.annonces(id) on delete cascade,
  jour date not null,
  heure_debut time,
  heure_fin time,
  statut text not null default 'libre' check (statut in ('libre', 'pris'))
);
create index annonce_creneaux_annonce_idx on public.annonce_creneaux (annonce_id);

-- Visibilité « équipes choisies »
create table public.annonce_cibles (
  annonce_id uuid not null references public.annonces(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  primary key (annonce_id, team_id)
);

-- ------------------------------------------------------------------ FONCTIONS D'AIDE
-- Distance à vol d'oiseau en km entre deux points (formule de haversine)
create or replace function public.km_entre(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
  returns float8 language sql immutable as
$$ select 2 * 6371 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2)
        + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))) $$;

-- Clubs VÉRIFIÉS dont l'utilisateur fait partie de l'encadrement (CQ, coordinateur,
-- ou entraîneur/délégué d'une de leurs équipes) : c'est son « point de vue » réseau.
create or replace function public.mes_clubs_reseau() returns setof uuid
  language sql stable security definer set search_path = public as
$$ select c.id from clubs c where c.verifie and (
     exists (select 1 from club_members cm where cm.club_id = c.id and cm.profile_id = auth.uid())
     or exists (select 1 from teams t join team_members tm on tm.team_id = t.id
                where t.club_id = c.id and tm.profile_id = auth.uid() and tm.role in ('entraineur', 'delegue'))) $$;

-- L'utilisateur peut-il voir cette annonce ?
-- - son équipe/son club : toutes les annonces (brouillons compris) ;
-- - sinon : annonce publiée, club annonceur vérifié, et zone qui le concerne.
create or replace function public.can_see_annonce(a uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (
  select 1 from annonces an join clubs ca on ca.id = an.club_id
  where an.id = a and (
    public.is_team_staff(an.team_id)
    or (an.statut = 'publiee' and ca.verifie and exists (
          select 1 from clubs mc where mc.id in (select public.mes_clubs_reseau()) and (
               an.zone = 'belgique'
            or (an.zone = 'province' and mc.province_id is not null and mc.province_id = ca.province_id)
            or (an.zone = 'distance' and mc.lat is not null and ca.lat is not null
                and public.km_entre(mc.lat, mc.lng, ca.lat, ca.lng) <= an.distance_km)
            or (an.zone = 'equipes' and exists (
                  select 1 from annonce_cibles ac join teams t on t.id = ac.team_id
                  where ac.annonce_id = an.id and t.club_id = mc.id)))))))
$$;

-- Garde-fous du circuit de validation (rôle réel de l'appelant : SECURITY INVOKER)
create or replace function public.guard_annonce() returns trigger
  language plpgsql set search_path = public as
$$ declare v_club uuid; v_verifie boolean; v_staff_club boolean;
begin
  select t.club_id into v_club from teams t where t.id = new.team_id;
  if v_club is null then raise exception 'L''équipe doit appartenir à un club pour publier une annonce'; end if;
  new.club_id := v_club;
  new.updated_at := now();
  if current_user not in ('authenticated', 'anon') then return new; end if;  -- SQL Editor / service
  v_staff_club := public.is_club_member(v_club);
  -- Publier ou refuser : CQ / coordinateur du club uniquement
  if new.statut in ('publiee', 'refusee') and (tg_op = 'INSERT' or new.statut is distinct from old.statut)
     and not v_staff_club then
    raise exception 'Seuls le CQ et les coordinateurs du club peuvent publier ou refuser une annonce';
  end if;
  -- Une annonce publiée ne se modifie que par le club (l'entraîneur peut la voir, pas la changer)
  if tg_op = 'UPDATE' and old.statut = 'publiee' and not v_staff_club then
    raise exception 'Annonce publiée : seuls le CQ et les coordinateurs peuvent la modifier';
  end if;
  if new.statut = 'publiee' then
    select verifie into v_verifie from clubs where id = v_club;
    if not coalesce(v_verifie, false) then
      raise exception 'Le club doit être vérifié par FootCoach pour publier une annonce';
    end if;
    if tg_op = 'INSERT' or old.statut is distinct from 'publiee' then
      new.publiee_le := now(); new.valide_par := auth.uid();
    end if;
  end if;
  return new;
end $$;
create trigger annonces_guard before insert or update on public.annonces
  for each row execute function public.guard_annonce();

-- Peut-on modifier les créneaux / cibles de cette annonce ? (club ; ou encadrement de
-- l'équipe tant qu'elle n'est pas publiée)
create or replace function public.can_edit_annonce(a uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from annonces an where an.id = a and (
     public.is_club_member(an.club_id)
     or (public.is_team_staff(an.team_id) and an.statut in ('brouillon', 'a_valider', 'refusee')))) $$;

-- Annonces visibles, avec les informations publiques utiles à la recherche (club,
-- équipe, province, distance depuis le club de l'équipe choisie). Aucune donnée de
-- joueur ni de contact. p_team : l'équipe pour laquelle on cherche (pour la distance).
create or replace function public.annonces_reseau(p_team uuid default null)
returns table(
  id uuid, team_id uuid, club_id uuid, type text, lieu text, format text, duree_mt int,
  categories text[], niveaux int[], zone text, distance_km int, message text, statut text,
  publiee_le timestamptz, equipe text, equipe_categorie text, equipe_niveau int,
  club_nom text, club_logo text, club_slug text, province text, distance_club numeric,
  creneaux jsonb, mon_club boolean
)
language sql stable security definer set search_path = public as
$$ select an.id, an.team_id, an.club_id, an.type, an.lieu, an.format, an.duree_mt,
          an.categories, an.niveaux, an.zone, an.distance_km, an.message, an.statut,
          an.publiee_le, t.nom::text, t.categorie::text, t.niveau_id,
          ca.nom::text, ca.logo::text, ca.slug::text, pr.nom::text,
          case when mc.lat is not null and ca.lat is not null
               then round(public.km_entre(mc.lat, mc.lng, ca.lat, ca.lng)::numeric, 0) end,
          coalesce((select jsonb_agg(jsonb_build_object('id', cr.id, 'jour', cr.jour,
                      'debut', cr.heure_debut, 'fin', cr.heure_fin, 'statut', cr.statut)
                      order by cr.jour, cr.heure_debut)
                    from annonce_creneaux cr where cr.annonce_id = an.id), '[]'::jsonb),
          public.is_team_staff(an.team_id)
   from annonces an
   join teams t on t.id = an.team_id
   join clubs ca on ca.id = an.club_id
   left join provinces pr on pr.id = ca.province_id
   left join clubs mc on mc.id = (select tt.club_id from teams tt where tt.id = p_team and public.is_team_staff(tt.id))
   where an.statut = 'publiee' and public.can_see_annonce(an.id)
   order by an.publiee_le desc $$;

-- Équipes des clubs vérifiés (pour la zone « équipes choisies ») : nom, catégorie, club
create or replace function public.equipes_reseau()
returns table(team_id uuid, equipe text, categorie text, club_nom text)
language sql stable security definer set search_path = public as
$$ select t.id, t.nom::text, t.categorie::text, c.nom::text
   from teams t join clubs c on c.id = t.club_id
   where c.verifie and exists (select 1 from public.mes_clubs_reseau())
   order by c.nom, t.categorie, t.nom $$;

-- ------------------------------------------------------------------ RÈGLES (RLS)
alter table public.annonces enable row level security;
alter table public.annonce_creneaux enable row level security;
alter table public.annonce_cibles enable row level security;

-- is_team_staff(team_id) en premier : l'auteur doit relire l'annonce qu'il vient de créer
-- (can_see_annonce ne voit pas encore une ligne insérée dans la même requête).
create policy "Annonces lecture" on public.annonces for select to authenticated
  using (is_team_staff(team_id) or can_see_annonce(id));
create policy "Annonces création" on public.annonces for insert to authenticated
  with check (is_team_staff(team_id) and cree_par = auth.uid());
create policy "Annonces modif" on public.annonces for update to authenticated
  using (is_team_staff(team_id)) with check (is_team_staff(team_id));
create policy "Annonces suppr" on public.annonces for delete to authenticated
  using (is_club_member(club_id) or (is_team_staff(team_id) and statut in ('brouillon', 'a_valider', 'refusee')));

create policy "Créneaux lecture" on public.annonce_creneaux for select to authenticated
  using (can_see_annonce(annonce_id));
create policy "Créneaux écriture" on public.annonce_creneaux for all to authenticated
  using (can_edit_annonce(annonce_id)) with check (can_edit_annonce(annonce_id));

-- Les cibles ne sont visibles que du club annonceur et des équipes visées
create policy "Cibles lecture" on public.annonce_cibles for select to authenticated
  using (is_team_staff(team_id) or exists (select 1 from annonces an where an.id = annonce_id and is_team_staff(an.team_id)));
create policy "Cibles écriture" on public.annonce_cibles for all to authenticated
  using (can_edit_annonce(annonce_id)) with check (can_edit_annonce(annonce_id));

-- ------------------------------------------------------------------ DROITS D'APPEL
do $$ declare f text; begin
  foreach f in array array['mes_clubs_reseau()', 'can_see_annonce(uuid)', 'can_edit_annonce(uuid)',
                           'annonces_reseau(uuid)', 'equipes_reseau()'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  execute 'revoke execute on function public.guard_annonce() from public, anon, authenticated';
end $$;

commit;
