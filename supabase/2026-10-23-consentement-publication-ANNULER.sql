-- ============================================================================
-- FootCoach — ANNULER le consentement « publication du prénom » du 2026-10-23
-- Remet la fonction public_scores du 2026-09-28 (prénoms de TOUS les buteurs
-- affichés) et supprime la colonne players.publication_ok.
-- ============================================================================
begin;
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
         coalesce((m.timeline_json::jsonb->>'chronoS')::int, 0),
         coalesce((m.timeline_json::jsonb->>'chronoOn')::boolean, false),
         (m.timeline_json::jsonb->>'chronoStartedAt')::bigint,
         coalesce((m.timeline_json::jsonb->>'halfN')::int, 1),
         (m.timeline_json::jsonb->>'halfDuration')::int,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    't', (g->>'t')::int,
                    'mt', coalesce((g->>'half')::int, 1),
                    'adv', coalesce((g->>'adv')::boolean, false),
                    -- « Prénom N. » seulement ; rien pour un but adverse ou sans buteur
                    'buteur', case
                      when coalesce((g->>'adv')::boolean,false) then null
                      when coalesce(g->>'scorer','') in ('','But marqué','?') then null
                      else trim(split_part(g->>'scorer',' ',1) || ' ' ||
                           coalesce(nullif(left(split_part(g->>'scorer',' ',2),1),'') || '.', ''))
                    end) order by coalesce((g->>'half')::int,1), (g->>'t')::int)
           from jsonb_array_elements(coalesce(m.timeline_json::jsonb->'goals','[]'::jsonb)) g
         ), '[]'::jsonb)
  from matches m
  join teams t on t.id = m.team_id
  where t.scores_publics
    and (m.date::timestamptz at time zone 'Europe/Brussels')::date = d
  order by m.date, t.nom
$$;
grant execute on function public.public_scores(date) to anon, authenticated;
alter table public.players drop column if exists publication_ok;
commit;
