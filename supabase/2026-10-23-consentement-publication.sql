-- ============================================================================
-- FootCoach — Consentement « publication du prénom » — 2026-10-23
-- Décision RGPD : sur la page publique des scores, le prénom (« Prénom N. ») d'un
-- buteur n'apparaît QUE si la case « publication autorisée » est cochée sur sa fiche.
-- Sinon : « ⚽ 12' » sans prénom. Décochée par défaut pour tous les joueurs.
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- À exécuter en une fois dans Supabase → SQL Editor → Run.
-- Annulation : 2026-10-23-consentement-publication-ANNULER.sql
-- ============================================================================
begin;

alter table public.players add column if not exists publication_ok boolean not null default false;

create or replace function public.public_scores(d date)
returns table(
  match_id text, equipe text, categorie text, logo text, couleur text,
  adversaire text, date_match timestamptz, lieu text, statut text,
  score_nous int, score_eux int,
  chrono_s int, chrono_on boolean, chrono_started_at bigint, mi_temps int, duree_mt int,
  buts jsonb
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
                    -- « Prénom N. » seulement si le joueur a la publication autorisée.
                    -- Joueur retrouvé par son identifiant (nouveaux buts, champ pid) ou,
                    -- pour les anciens buts sans pid, par son nom complet dans l'équipe.
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
         ), '[]'::jsonb)
  from matches m
  join teams t on t.id = m.team_id
  where t.scores_publics
    and (m.date at time zone 'Europe/Brussels')::date = d
  order by m.date, t.nom
$$;

grant execute on function public.public_scores(date) to anon, authenticated;

commit;
