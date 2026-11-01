-- ============================================================================
-- FootLink — Notifications (C3b) : reprise des e-mails bloqués — 2026-11-01
-- Nécessite C3. Si la fonction d'envoi s'arrête en plein envoi, l'e-mail réservé restait
-- « en_cours » pour toujours. Désormais une réservation vaut 10 minutes : passé ce délai,
-- l'e-mail est repris ; après 3 essais il est noté en échec (erreur « envoi interrompu »).
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-11-01-C3b-notif-reprise-ANNULER.sql
-- ============================================================================
begin;

create or replace function public.notif_reserver(p_max int default 40)
returns table(id uuid, email text, prenom text, titre text, texte text)
language plpgsql security definer set search_path = public as
$$ begin
  update notifications set statut = 'echec', erreur = coalesce(erreur, 'envoi interrompu')
    where statut = 'en_cours' and essais >= 3 and envoyer_apres <= now();
  return query
  update notifications n set statut = 'en_cours', essais = n.essais + 1,
         envoyer_apres = now() + interval '10 minutes'          -- réservation de 10 minutes
   from profiles pr
   where n.id in (select x.id from notifications x
                  where (x.statut = 'a_envoyer' or (x.statut = 'en_cours' and x.essais < 3))
                    and x.envoyer_apres <= now()
                  order by x.created_at limit p_max for update skip locked)
     and pr.id = n.profile_id
   returning n.id, pr.email, pr.prenom, n.titre, n.texte;
end $$;

revoke execute on function public.notif_reserver(int) from public, anon, authenticated;
grant execute on function public.notif_reserver(int) to service_role;

commit;
