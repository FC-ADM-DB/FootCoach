-- Vérification du scénario « Trouver un match » (scenario-matchs-prod.sql) — LECTURE SEULE
-- À lancer dans le SQL Editor de la production : une ligne par élément, OK / ÉCHEC / À VOIR.
with eq as (
  select t.id, replace(c.nom, 'TEST ', '') || ' ' || t.categorie as nom
  from teams t join clubs c on c.id = t.club_id where c.slug like 'comptes-test-%'
)
select 'Annonce' as quoi, e.nom as equipe, a.statut as etat,
       case a.statut when 'publiee' then 'OK' else 'ÉCHEC' end as resultat
from annonces a join eq e on e.id = a.team_id where a.message like '%[scénario]%'
union all
select 'Proposition ' || ea.nom || ' ← ' || ep.nom, to_char(p.jour, 'DD/MM') || ' ' || coalesce(to_char(p.heure, 'HH24:MI'), ''),
       p.statut,
       case when (ea.nom, ep.nom, p.statut) in (
         ('Hannut U10', 'Geer U10', 'acceptee'), ('Hannut U10', 'Braives U10', 'acceptee'),
         ('Burdinne U10', 'Hannut U10', 'refusee'), ('Geer U9', 'Hannut U9', 'acceptee'),
         ('Burdinne U9', 'Braives U9', 'a_valider'), ('Braives U10', 'Burdinne U10', 'envoyee'),
         ('Braives U9', 'Geer U9', 'envoyee')) then 'OK' else 'À VOIR' end
from propositions p join eq ea on ea.id = p.equipe_annonceur join eq ep on ep.id = p.equipe_proposante
union all
select 'Matchs créés (attendu : 6)', '', count(*)::text, case when count(*) = 6 then 'OK' else 'ÉCHEC' end
from matches m join eq e on e.id = m.team_id where m.date > now()
union all
select 'Clubs TEST vérifiés et géolocalisés (attendu : 4)', '', count(*)::text, case when count(*) = 4 then 'OK' else 'ÉCHEC' end
from clubs where slug like 'comptes-test-%' and verifie and lat is not null
order by 1, 2;
