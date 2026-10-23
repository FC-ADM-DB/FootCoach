-- ============================================================================
-- FootCoach — Phase 0 : petites corrections de sécurité — 2026-10-23
-- Testé sur la base de test (supabase/tests/tests-securite.sql : 40/40 OK).
-- À exécuter en une fois dans Supabase → SQL Editor → Run.
-- Annulation : 2026-10-23-phase0-corrections-ANNULER.sql
-- ============================================================================
begin;

-- 1. Saisons : n'importe qui (même sans compte) pouvait en créer. L'app ne crée
--    jamais de saison (elle lit la plus récente) : on retire la création, et la
--    lecture est réservée aux utilisateurs connectés.
drop policy if exists "Saisons créables" on public.seasons;
drop policy if exists "Saisons lisibles" on public.seasons;
create policy "Saisons lisibles" on public.seasons for select to authenticated using (true);

-- 2. Trigger de création du profil : chemin de recherche fixé (fonction SECURITY
--    DEFINER sans search_path = faiblesse signalée par Supabase). Même contenu.
create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  insert into public.profiles (id, prenom, nom, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'prenom','Prénom'),
          coalesce(new.raw_user_meta_data->>'nom','Nom'), new.email);
  return new;
end; $$;

commit;
