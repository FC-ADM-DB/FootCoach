-- ============================================================================
-- PRODUCTION — retire les clubs créés PAR ERREUR le 2026-11-20 par le script de la base
-- de test (supabase/tests/comptes-test-footlink.sql) : « Hannut », « Burdinne », « Geer »,
-- « Braives » (identifiants demo-hannut, demo-burdinne, demo-geer, demo-reh-braives),
-- avec leurs équipes, joueurs et rattachements.
-- NE TOUCHE PAS : le vrai club REH Braives (identifiant reh-braives), les clubs
-- « TEST … » de comptes-test-prod.sql, ni les 32 comptes (ils restent rattachés aux
-- clubs TEST).
--
-- ÉTAPE 1 : lancer seulement la requête « APERÇU » et vérifier la liste.
-- ÉTAPE 2 : lancer le bloc « SUPPRESSION ».
-- ============================================================================

-- APERÇU : doit lister au plus 4 clubs, tous créés aujourd'hui, sans CQ
select c.slug, c.nom, c.created_at,
       (select count(*) from teams t where t.club_id = c.id) as equipes,
       (select count(*) from players p join teams t on t.id = p.team_id where t.club_id = c.id) as joueurs,
       (select count(*) from club_members m where m.club_id = c.id and m.role = 'cq') as cq,
       (select count(*) from matches m join teams t on t.id = m.team_id where t.club_id = c.id) as matchs
from clubs c
where c.slug in ('demo-hannut', 'demo-burdinne', 'demo-geer', 'demo-reh-braives')
order by c.slug;

-- SUPPRESSION (une seule transaction ; refuse si un club a un CQ ou des matchs,
-- c'est-à-dire s'il a servi à autre chose qu'aux comptes de test)
begin;
do $$
declare v_clubs uuid[];
begin
  select array_agg(id) into v_clubs from clubs
  where slug in ('demo-hannut', 'demo-burdinne', 'demo-geer', 'demo-reh-braives');
  if v_clubs is null then raise notice 'Rien à supprimer'; return; end if;
  if exists (select 1 from club_members where club_id = any(v_clubs) and role = 'cq')
     or exists (select 1 from matches m join teams t on t.id = m.team_id where t.club_id = any(v_clubs)) then
    raise exception 'STOP : un de ces clubs a un CQ ou des matchs, vérifie avant de supprimer';
  end if;
  delete from team_members where team_id in (select id from teams where club_id = any(v_clubs));
  delete from players where team_id in (select id from teams where club_id = any(v_clubs));
  delete from teams where club_id = any(v_clubs);
  delete from club_members where club_id = any(v_clubs);
  delete from clubs where id = any(v_clubs);
end $$;
commit;

-- Vérification : doit afficher 0
select count(*) as clubs_restants from clubs
where slug in ('demo-hannut', 'demo-burdinne', 'demo-geer', 'demo-reh-braives');
