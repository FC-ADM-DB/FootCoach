-- ============================================================================
-- FootLink — Notifications (C3d) : nouveau club à vérifier — 2026-11-01
-- Nécessite C3. Quand quelqu'un crée un club (non vérifié), les admins plateforme
-- reçoivent un e-mail pour aller le vérifier dans « Gestion des clubs ». Un club créé
-- par un admin lui-même ne déclenche rien (l'auteur n'est jamais prévenu).
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-11-01-C3d-notif-nouveau-club-ANNULER.sql
-- ============================================================================
begin;

create or replace function public.notif_nouveau_club() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  if new.verifie then return new; end if;
  perform notif_ajouter(array(select profile_id from platform_admins), 'club_a_verifier',
    'Nouveau club à vérifier : ' || new.nom,
    'Un nouveau club vient d''être créé sur FootLink et attend ta vérification.' || E'\n\n'
      || 'Club : ' || new.nom || coalesce(E'\nMatricule : ' || new.matricule, '')
      || coalesce(E'\nAdresse : ' || new.adresse, '')
      || coalesce(E'\nCréé par : ' || (select trim(prenom || ' ' || nom) || ' (' || coalesce(email, '?') || ')'
                                       from profiles where id = new.cree_par), '')
      || E'\n\nVérifie-le dans FootLink : menu du compte → Gestion des clubs.');
  return new;
end $$;
create trigger clubs_notif_nouveau after insert on public.clubs
  for each row execute function public.notif_nouveau_club();
revoke execute on function public.notif_nouveau_club() from public, anon, authenticated;

commit;
