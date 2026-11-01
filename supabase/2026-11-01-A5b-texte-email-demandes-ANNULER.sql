-- Annulation de A5b : retour à l'ancien texte de l'e-mail
begin;

create or replace function public.notif_demandes_acces() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare v_nom text;
begin
  if tg_op = 'INSERT' then
    select trim(prenom || ' ' || nom) || ' (' || coalesce(email, '?') || ')' into v_nom from profiles where id = new.profile_id;
    perform notif_ajouter(demande_validateurs(new), 'acces_demande', 'Demande d''accès à valider',
      v_nom || E' demande l''accès :\n' || demande_libelle(new)
        || coalesce(E'\n\nMessage : « ' || new.message || ' »', '')
        || E'\n\nAccepte ou refuse dans FootLink : menu du compte → Membres & accès.');
  elsif new.statut <> old.statut and new.statut in ('acceptee', 'refusee') then
    perform notif_ajouter(array[new.profile_id],
      case new.statut when 'acceptee' then 'acces_accepte' else 'acces_refuse' end,
      case new.statut when 'acceptee' then 'Accès accepté' else 'Demande d''accès refusée' end,
      case new.statut when 'acceptee' then E'Ta demande est acceptée : tu es maintenant ' || demande_libelle(new) || E'.\n\nOuvre FootLink pour commencer.'
           else E'Ta demande d''accès (' || demande_libelle(new) || E') a été refusée.' || coalesce(E'\nMotif : ' || new.motif, '')
                || E'\n\nPour toute question, contacte le club.' end);
  end if;
  return new;
end $$;

commit;
