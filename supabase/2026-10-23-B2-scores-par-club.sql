-- ============================================================================
-- FootCoach — Phase B2 : page publique des scores par club — 2026-10-23
-- - public_scores(d, p_club) : filtre facultatif par club (identifiant d'adresse,
--   ex. 'reh-braives') ; renvoie aussi le nom du club. Mêmes protections qu'avant :
--   équipes « Scores publics » seulement, prénom des buteurs seulement avec accord.
-- - public_club(p_slug) : nom, logo et couleurs du club pour habiller la page.
-- Aucune table n'est ouverte aux visiteurs.
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-10-23-B2-scores-par-club-ANNULER.sql
-- ============================================================================
begin;

drop function if exists public.public_scores(date);

create function public.public_scores(d date, p_club text default null)
returns table(
  match_id text, equipe text, categorie text, logo text, couleur text,
  adversaire text, date_match timestamptz, lieu text, statut text,
  score_nous int, score_eux int,
  chrono_s int, chrono_on boolean, chrono_started_at bigint, mi_temps int, duree_mt int,
  buts jsonb, club_nom text, club_slug text
)
language sql security definer stable set search_path = public as
$$
  select m.id::text, t.nom::text, t.categorie::text, t.logo::text, t.couleur::text,
         m.adversaire::text, m.date::timestamptz, m.lieu::text, m.statut::text,
         coalesce(m.score_nous,0)::int, coalesce(m.score_eux,0)::int,
         coalesce((m.timeline_json->>'chronoS')::int, 0),
         coalesce((m.timeline_json->>'chronoOn')::boolean, false),
         (m.timeline_json->>'chronoStartedAt')::bigint,
         coalesce((m.timeline_json->>'halfN')::int, 1),
         (m.timeline_json->>'halfDuration')::int,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    't', (g->>'t')::int,
                    'mt', coalesce((g->>'half')::int, 1),
                    'adv', coalesce((g->>'adv')::boolean, false),
                    -- « Prénom N. » seulement si le joueur a la publication autorisée
                    'buteur', (
                      select trim(p.prenom || ' ' || coalesce(nullif(left(p.nom,1),'') || '.', ''))
                      from players p
                      where p.team_id = m.team_id and p.publication_ok
                        and not coalesce((g->>'adv')::boolean, false)
                        and (p.id::text = g->>'pid'
                             or (g->>'pid' is null and p.prenom || ' ' || p.nom = g->>'scorer'))
                      limit 1)
                  ) order by coalesce((g->>'half')::int,1), (g->>'t')::int)
           from jsonb_array_elements(coalesce(m.timeline_json->'goals','[]'::jsonb)) g
         ), '[]'::jsonb),
         c.nom::text, c.slug::text
  from matches m
  join teams t on t.id = m.team_id
  left join clubs c on c.id = t.club_id
  where t.scores_publics
    and (m.date at time zone 'Europe/Brussels')::date = d
    and (p_club is null or c.slug = p_club)
  order by m.date, c.nom, t.nom
$$;

-- Identité visuelle d'un club (informations publiques de toute façon : nom, logo, couleurs)
create or replace function public.public_club(p_slug text)
returns table(nom text, slug text, logo text, couleur1 text, couleur2 text, verifie boolean)
language sql security definer stable set search_path = public as
$$ select c.nom::text, c.slug::text, c.logo::text, c.couleur1::text, c.couleur2::text, c.verifie
   from clubs c where c.slug = p_slug $$;

revoke execute on function public.public_scores(date, text) from public;
revoke execute on function public.public_club(text) from public;
grant execute on function public.public_scores(date, text) to anon, authenticated;
grant execute on function public.public_club(text) to anon, authenticated;

commit;
