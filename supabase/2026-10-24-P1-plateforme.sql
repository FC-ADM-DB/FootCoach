-- ============================================================================
-- FootCoach — Plateforme d'administration (admin plateforme) — 2026-10-24
-- Fonctions de lecture/gestion réservées à l'admin plateforme (platform_admins) :
-- elles refusent tout autre appelant. Vérifier un club, renommer un niveau ou
-- supprimer un club passent par les règles existantes (déjà ouvertes à l'admin).
-- Aucune donnée de joueur n'est exposée (seulement des compteurs).
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-10-24-P1-plateforme-ANNULER.sql
-- ============================================================================
begin;

create or replace function public.exiger_admin_plateforme() returns void
  language plpgsql stable security definer set search_path = public as
$$ begin
  if not public.is_platform_admin() then raise exception 'Réservé à l''administrateur FootCoach'; end if;
end $$;

-- Tous les clubs avec leur CQ et quelques compteurs
create or replace function public.admin_clubs()
returns table(id uuid, nom text, slug text, verifie boolean, logo text, province text, adresse text,
              position_connue boolean, matricule text, created_at timestamptz,
              cq text, cq_email text, nb_equipes int, nb_membres int, nb_annonces int)
language plpgsql stable security definer set search_path = public as
$$ begin
  perform public.exiger_admin_plateforme();
  return query
  select c.id, c.nom::text, c.slug::text, c.verifie, c.logo::text, pr.nom::text, c.adresse::text,
         (c.lat is not null and c.lng is not null), c.matricule::text, c.created_at,
         (select string_agg(p.prenom || ' ' || p.nom, ', ') from club_members cm join profiles p on p.id = cm.profile_id
           where cm.club_id = c.id and cm.role = 'cq')::text,
         (select string_agg(p.email, ', ') from club_members cm join profiles p on p.id = cm.profile_id
           where cm.club_id = c.id and cm.role = 'cq')::text,
         (select count(*) from teams t where t.club_id = c.id)::int,
         (select count(distinct x.pid) from (
             select cm.profile_id pid from club_members cm where cm.club_id = c.id
             union select tm.profile_id from team_members tm join teams t on t.id = tm.team_id where t.club_id = c.id) x)::int,
         (select count(*) from annonces a where a.club_id = c.id and a.statut = 'publiee')::int
  from clubs c left join provinces pr on pr.id = c.province_id
  order by c.verifie, c.created_at desc;
end $$;

-- Chiffres de la plateforme
create or replace function public.admin_stats()
returns table(clubs int, clubs_verifies int, clubs_en_attente int, equipes int, utilisateurs int, annonces_publiees int)
language plpgsql stable security definer set search_path = public as
$$ begin
  perform public.exiger_admin_plateforme();
  return query select
    (select count(*) from clubs)::int, (select count(*) from clubs where verifie)::int,
    (select count(*) from clubs where not verifie)::int, (select count(*) from teams)::int,
    (select count(*) from profiles)::int, (select count(*) from annonces where statut = 'publiee')::int;
end $$;

-- Niveaux avec leur utilisation et leur créateur
create or replace function public.admin_niveaux()
returns table(id int, libelle text, ordre int, nb_equipes int, nb_annonces int, cree_par text)
language plpgsql stable security definer set search_path = public as
$$ begin
  perform public.exiger_admin_plateforme();
  return query
  select n.id, n.libelle::text, n.ordre,
         (select count(*) from teams t where t.niveau_id = n.id)::int,
         (select count(*) from annonces a where n.id = any(a.niveaux))::int,
         (select p.prenom || ' ' || p.nom from profiles p where p.id = n.cree_par)::text
  from niveaux n order by n.ordre, n.libelle;
end $$;

-- Fusion de deux niveaux : les équipes et annonces du niveau « source » passent au
-- niveau « cible », puis la source est supprimée.
create or replace function public.admin_fusion_niveau(p_source int, p_cible int)
returns void language plpgsql security definer set search_path = public as
$$ begin
  perform public.exiger_admin_plateforme();
  if p_source = p_cible then raise exception 'Choisis deux niveaux différents'; end if;
  if not exists (select 1 from niveaux where id = p_cible) then raise exception 'Niveau cible introuvable'; end if;
  update teams set niveau_id = p_cible where niveau_id = p_source;
  update annonces set niveaux = (select array_agg(distinct x) from unnest(array_replace(niveaux, p_source, p_cible)) x)
   where p_source = any(niveaux);
  delete from niveaux where id = p_source;
end $$;

-- Fiche d'un club : personnes (encadrement du club + membres des équipes) …
create or replace function public.admin_club_membres(p_club uuid)
returns table(club_member_id uuid, profile_id uuid, prenom text, nom text, email text, role text, equipe text)
language plpgsql stable security definer set search_path = public as
$$ begin
  perform public.exiger_admin_plateforme();
  return query
  select cm.id, p.id, p.prenom::text, p.nom::text, p.email::text, cm.role::text, null::text
    from club_members cm join profiles p on p.id = cm.profile_id where cm.club_id = p_club
  union all
  select null::uuid, p.id, p.prenom::text, p.nom::text, p.email::text, tm.role::text, t.nom::text
    from team_members tm join teams t on t.id = tm.team_id join profiles p on p.id = tm.profile_id
   where t.club_id = p_club
  order by 7 nulls first, 3, 4;
end $$;

-- … et équipes (compteurs seulement, aucune donnée de joueur)
create or replace function public.admin_club_equipes(p_club uuid)
returns table(id uuid, nom text, categorie text, format text, niveau text, nb_membres int, nb_joueurs int, nb_matchs int)
language plpgsql stable security definer set search_path = public as
$$ begin
  perform public.exiger_admin_plateforme();
  return query
  select t.id, t.nom::text, t.categorie::text, t.format::text, n.libelle::text,
         (select count(*) from team_members tm where tm.team_id = t.id)::int,
         (select count(*) from players pl where pl.team_id = t.id and pl.actif)::int,
         (select count(*) from matches m where m.team_id = t.id)::int
  from teams t left join niveaux n on n.id = t.niveau_id
  where t.club_id = p_club order by t.categorie, t.nom;
end $$;

-- Recherche d'une personne par email : aussi pour l'admin plateforme (nommer le CQ
-- d'un club qui n'en a plus), en plus de l'encadrement des équipes et clubs.
create or replace function public.find_profile_by_email(e text)
  returns table(id uuid, prenom text, nom text, email text)
  language sql stable security definer set search_path = public as
$$ select p.id, p.prenom::text, p.nom::text, p.email::text from profiles p
   where lower(p.email) = lower(trim(e)) and (public.is_any_staff() or public.is_platform_admin()) $$;

do $$ declare f text; begin
  foreach f in array array['exiger_admin_plateforme()', 'admin_clubs()', 'admin_stats()', 'admin_niveaux()',
                           'admin_fusion_niveau(integer, integer)', 'admin_club_membres(uuid)', 'admin_club_equipes(uuid)',
                           'find_profile_by_email(text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

commit;
