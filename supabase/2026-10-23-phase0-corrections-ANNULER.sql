-- ============================================================================
-- FootCoach — ANNULER les corrections de la phase 0 du 2026-10-23
-- Remet les règles des saisons et le trigger exactement comme avant.
-- ============================================================================
begin;
drop policy if exists "Saisons lisibles" on public.seasons;
create policy "Saisons créables" on public.seasons for insert to public with check (true);
create policy "Saisons lisibles" on public.seasons for select to public using (true);

create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer as
$$ begin
  insert into public.profiles (id, prenom, nom, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'prenom','Prénom'),
          coalesce(new.raw_user_meta_data->>'nom','Nom'), new.email);
  return new;
end; $$;
commit;
