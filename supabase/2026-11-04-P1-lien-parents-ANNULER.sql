-- Annule P1 (lien « suivi du match » parents) : supprime les fonctions et la colonne.
begin;
drop function if exists public.match_parents_public(text);
drop function if exists public.match_lien_parents(uuid, boolean);
alter table public.matches drop column if exists lien_parents;
commit;
