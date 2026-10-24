-- ============================================================================
-- FootCoach — ANNULER le tableau tactique (T1) : supprime la table « tableaux »
-- et tous les tableaux enregistrés. Aucune autre donnée n'est touchée.
-- ============================================================================
begin;
drop table if exists public.tableaux cascade;
drop function if exists public.guard_tableau();
commit;
