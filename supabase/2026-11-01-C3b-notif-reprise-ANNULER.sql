-- ============================================================================
-- FootLink — ANNULATION de C3b (reprise des e-mails bloqués) — 2026-11-01
-- Remet la réservation d'e-mails de C3 (sans reprise des envois interrompus).
-- ============================================================================
begin;
create or replace function public.notif_reserver(p_max int default 40)
returns table(id uuid, email text, prenom text, titre text, texte text)
language plpgsql security definer set search_path = public as
$$ begin
  return query
  update notifications n set statut = 'en_cours', essais = n.essais + 1
   from profiles pr
   where n.id in (select x.id from notifications x where x.statut = 'a_envoyer' and x.envoyer_apres <= now()
                  order by x.created_at limit p_max for update skip locked)
     and pr.id = n.profile_id
   returning n.id, pr.email, pr.prenom, n.titre, n.texte;
end $$;
revoke execute on function public.notif_reserver(int) from public, anon, authenticated;
grant execute on function public.notif_reserver(int) to service_role;
commit;
