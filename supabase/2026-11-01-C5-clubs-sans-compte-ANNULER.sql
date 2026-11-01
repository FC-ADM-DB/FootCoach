-- ============================================================================
-- FootLink — ANNULATION des clubs sans compte (C5) — 2026-11-01
-- Supprime les propositions par e-mail et les invitations de clubs (les matchs déjà
-- créés restent), les e-mails vers des adresses externes, et remet la file d'e-mails C3b.
-- ============================================================================
begin;
drop trigger if exists invitations_match_notif on public.invitations_match;
drop trigger if exists invitations_club_notif on public.invitations_club;
drop table if exists public.invitations_match cascade;
drop table if exists public.invitations_club cascade;
drop function if exists public.notif_invitations_match();
drop function if exists public.notif_invitations_club();
drop function if exists public.mes_invitations_match();
drop function if exists public.invitation_match_creer(uuid, text, text, text, text, date, time, text, text);
drop function if exists public.invitation_match_agir(uuid, text);
drop function if exists public.invitation_match_voir(text);
drop function if exists public.invitation_match_repondre(text, text, date, time, text, text, text, text);
drop function if exists public.invitation_club_creer(uuid, text, text, text, text);
drop function if exists public.invitation_club_info(text);
drop function if exists public.invitation_club_utiliser(text, uuid);
drop function if exists public.envois_externes_du_jour(uuid);
drop function if exists public.notif_ajouter_externe(text, text, text, text, text, text, text);

delete from public.notifications where profile_id is null;
drop function if exists public.notif_reserver(int);
create function public.notif_reserver(p_max int default 40)
returns table(id uuid, email text, prenom text, titre text, texte text)
language plpgsql security definer set search_path = public as
$$ begin
  update notifications set statut = 'echec', erreur = coalesce(erreur, 'envoi interrompu')
    where statut = 'en_cours' and essais >= 3 and envoyer_apres <= now();
  return query
  update notifications n set statut = 'en_cours', essais = n.essais + 1,
         envoyer_apres = now() + interval '10 minutes'
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

alter table public.notifications drop constraint if exists notifications_destinataire;
alter table public.notifications drop column if exists email_externe, drop column if exists nom_externe,
  drop column if exists lien, drop column if exists bouton;
alter table public.notifications alter column profile_id set not null;
commit;
