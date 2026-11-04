-- ============================================================================
-- FootLink — P1 : lien « suivi du match » pour les parents, sans compte — 2026-11-04
-- À exécuter dans Supabase → SQL Editor → Run. Annulation : ...-P1-lien-parents-ANNULER.sql
--
-- Un membre de l'encadrement crée un lien secret pour UN match (matches.lien_parents).
-- Quiconque a le lien voit, sans se connecter : score, statut, terrain (postes + « Prénom N. »),
-- remplaçants, buts. Jamais de chrono, de temps de jeu, de nom complet ni de notes.
-- Le lien se désactive à tout moment, et expire 3 jours après la date du match.
-- ============================================================================
begin;

alter table public.matches add column if not exists lien_parents text unique;

-- Créer (ou relire) le lien du match, ou le révoquer. Encadrement de l'équipe seulement.
create or replace function public.match_lien_parents(p_match uuid, p_revoquer boolean default false)
  returns text language plpgsql security definer set search_path = public as
$$ declare m matches;
begin
  select * into m from matches where id = p_match for update;
  if m.id is null or not is_team_staff(m.team_id) then raise exception 'Accès refusé'; end if;
  if p_revoquer then
    update matches set lien_parents = null where id = p_match;
    return null;
  end if;
  if m.lien_parents is null then
    update matches set lien_parents = encode(extensions.gen_random_bytes(12), 'hex') where id = p_match
      returning lien_parents into m.lien_parents;
  end if;
  return m.lien_parents;
end $$;

-- Données de la page publique : le strict nécessaire, rien d'autre.
create or replace function public.match_parents_public(p_lien text) returns jsonb
  language sql stable security definer set search_path = public as
$$
  with x as (
    select m.*, m.timeline_json::jsonb as tl, t.nom as t_nom, t.categorie as t_cat, t.format as t_fmt,
           t.logo as t_logo, t.couleur as t_couleur
    from matches m join teams t on t.id = m.team_id
    where m.lien_parents = p_lien and coalesce(p_lien, '') <> ''
      and m.date::timestamptz > now() - interval '3 days'
  )
  select jsonb_build_object(
    'equipe', x.t_nom, 'categorie', x.t_cat, 'format', x.t_fmt, 'logo', x.t_logo, 'couleur', x.t_couleur,
    'adversaire', x.adversaire, 'date', x.date, 'lieu', x.lieu, 'statut', x.statut,
    'score_nous', coalesce(x.score_nous, 0), 'score_eux', coalesce(x.score_eux, 0),
    'mi_temps', coalesce((x.tl->>'halfN')::int, 1),
    'pause_mt', coalesce((x.tl->>'halfTimePending')::boolean, false),
    'demarre', coalesce((x.tl->>'matchStarted')::boolean, false),
    'layout', coalesce(x.tl->'posteLayout'->'portrait', '{}'::jsonb),
    -- joueurs sur le terrain : poste → « Prénom N. »
    'terrain', coalesce((
      select jsonb_agg(jsonb_build_object('poste', a.key, 'joueur',
               p.prenom || coalesce(' ' || left(nullif(p.nom, ''), 1) || '.', '')))
      from jsonb_each_text(coalesce(x.tl->'assignment', '{}'::jsonb)) a
      join players p on p.id::text = a.value and p.team_id = x.team_id), '[]'::jsonb),
    -- remplaçants : sur le banc et pas sur le terrain
    'banc', coalesce((
      select jsonb_agg(p.prenom || coalesce(' ' || left(nullif(p.nom, ''), 1) || '.', '') order by p.prenom)
      from jsonb_each(coalesce(x.tl->'MP', '{}'::jsonb)) e
      join players p on p.id::text = e.key and p.team_id = x.team_id
      where (e.value->>'onField') = 'false'
        and p.id::text not in (select value from jsonb_each_text(coalesce(x.tl->'assignment', '{}'::jsonb)) where value is not null)), '[]'::jsonb),
    'buts', coalesce((
      select jsonb_agg(jsonb_build_object(
               't', coalesce((g->>'t')::int, 0), 'mt', coalesce((g->>'half')::int, 1),
               'adv', coalesce((g->>'adv')::boolean, false),
               'buteur', case
                 when coalesce((g->>'adv')::boolean, false) then null
                 when coalesce(g->>'scorer', '') in ('', 'But marqué', '?') then null
                 else trim(split_part(g->>'scorer', ' ', 1) || ' ' ||
                      coalesce(nullif(left(split_part(g->>'scorer', ' ', 2), 1), '') || '.', ''))
               end) order by coalesce((g->>'half')::int, 1), coalesce((g->>'t')::int, 0))
      from jsonb_array_elements(coalesce(x.tl->'goals', '[]'::jsonb)) g), '[]'::jsonb),
    'duree_mt', (x.tl->>'halfDuration')::int)
  from x
$$;

revoke execute on function public.match_lien_parents(uuid, boolean), public.match_parents_public(text) from public, anon;
grant execute on function public.match_lien_parents(uuid, boolean) to authenticated;
grant execute on function public.match_parents_public(text) to anon, authenticated;

commit;
