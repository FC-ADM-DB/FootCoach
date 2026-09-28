-- ============================================================================
-- FootCoach — ANNULER la sécurité des équipes du 2026-09-28
-- À utiliser seulement si l'app ne fonctionne plus après le script de sécurité :
-- remet teams et team_members dans leur état d'avant (RLS désactivée).
-- Les colonnes logo/created_by et les fonctions sont conservées (sans effet).
-- ============================================================================
begin;
alter table public.teams disable row level security;
alter table public.team_members disable row level security;
drop policy if exists "Profils des coéquipiers" on public.profiles;
commit;
