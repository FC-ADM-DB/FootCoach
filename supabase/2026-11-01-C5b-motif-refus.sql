-- ============================================================================
-- FootLink — Raison facultative d'un refus (C5b) — 2026-11-01
-- Nécessite C2 (propositions), C3 (notifications) et C5 (clubs sans compte).
-- 1. Proposition entre clubs FootLink : la raison saisie au refus est enregistrée dans la
--    discussion AVANT le changement de statut, pour figurer aussi dans l'e-mail « refusée ».
-- 2. Proposition par e-mail / réponse à une annonce : refuser la nouvelle date d'un club
--    extérieur accepte une raison (colonne motif_refus), reprise dans l'e-mail au club.
-- Annulation : 2026-11-01-C5b-motif-refus-ANNULER.sql
-- ============================================================================
begin;

-- 1. Raison du refus dans l'e-mail (propositions entre clubs FootLink)
create or replace function public.proposition_agir(p_id uuid, p_action text, p_jour date default null,
                                                   p_heure time default null, p_lieu text default null,
                                                   p_message text default null)
  returns text language plpgsql security definer set search_path = public as
$$ declare p propositions; v_cote text; v_decide boolean; v_tour text; t proposition_tours;
           an annonces; v_date timestamptz; v_duree int; v_ma uuid; v_mp uuid; v_nom_a text; v_nom_p text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into p from propositions where id = p_id for update;
  if not found then raise exception 'Proposition introuvable'; end if;
  v_cote := prop_cote(p_id);
  if v_cote is null then raise exception 'Accès refusé'; end if;
  v_decide := is_club_member(case v_cote when 'annonceur' then p.club_annonceur else p.club_proposant end);
  if p.statut in ('acceptee', 'refusee', 'annulee') then raise exception 'Cette proposition est terminée'; end if;

  -- Suggestion d'un entraîneur : le coordinateur/CQ l'applique ou l'écarte
  if p_action in ('valider_suggestion', 'ecarter_suggestion') then
    -- Le coordinateur/CQ valide ou écarte ; l'entraîneur peut seulement RETIRER sa propre suggestion
    if not v_decide and not (p_action = 'ecarter_suggestion' and exists (select 1 from proposition_tours
         where proposition_id = p_id and cote = v_cote and en_attente and auteur = auth.uid())) then
      raise exception 'Réservé au coordinateur ou au CQ du club';
    end if;
    select * into t from proposition_tours where proposition_id = p_id and cote = v_cote and en_attente
      order by created_at desc limit 1;
    if not found then raise exception 'Aucune suggestion en attente'; end if;
    update proposition_tours set en_attente = false, ecartee = (p_action = 'ecarter_suggestion')
      where proposition_id = p_id and cote = v_cote and en_attente;
    if p_action = 'ecarter_suggestion' then return 'ecartee'; end if;
    p_action := t.action; p_jour := t.jour; p_heure := t.heure; p_lieu := t.lieu;
    p_message := coalesce(p_message, t.message);
  end if;

  if p_action = 'envoyer' then
    if v_cote <> 'proposant' or p.statut <> 'a_valider' then raise exception 'Rien à envoyer'; end if;
    if not v_decide then raise exception 'Réservé au coordinateur ou au CQ du club'; end if;
    update propositions set statut = 'envoyee', updated_at = now() where id = p_id;
    insert into proposition_tours (proposition_id, cote, action, message, auteur, auteur_nom)
    values (p_id, v_cote, 'envoyer', nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
    return 'envoyee';
  end if;

  if p_action = 'annuler' then
    if v_cote <> 'proposant' then raise exception 'Seule l''équipe qui propose peut annuler'; end if;
    if not v_decide and p.statut <> 'a_valider' then raise exception 'Réservé au coordinateur ou au CQ du club'; end if;
    update propositions set statut = 'annulee', updated_at = now() where id = p_id;
    insert into proposition_tours (proposition_id, cote, action, message, auteur, auteur_nom)
    values (p_id, v_cote, 'annuler', nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
    return 'annulee';
  end if;

  if p_action not in ('accepter', 'refuser', 'contre') then raise exception 'Action inconnue'; end if;
  v_tour := case p.statut when 'envoyee' then 'annonceur' when 'contre' then 'proposant' end;
  if v_tour is distinct from v_cote then raise exception 'Ce n''est pas à ton club de répondre maintenant'; end if;
  if p_action = 'contre' then
    if p_jour is null or p_jour < current_date then raise exception 'Choisis une date à venir'; end if;
    if coalesce(p_lieu, p.lieu) not in ('annonceur', 'proposant') then raise exception 'Lieu invalide'; end if;
  end if;

  -- Entraîneur / délégué : suggestion pour son coordinateur
  if not v_decide then
    update proposition_tours set en_attente = false, ecartee = true
      where proposition_id = p_id and cote = v_cote and en_attente;   -- une seule suggestion à la fois
    insert into proposition_tours (proposition_id, cote, action, jour, heure, lieu, message, en_attente, auteur, auteur_nom)
    values (p_id, v_cote, p_action, p_jour, p_heure, coalesce(p_lieu, p.lieu), nullif(trim(p_message), ''), true, auth.uid(), prop_nom_moi());
    return 'suggestion';
  end if;

  if p_action = 'refuser' then
    -- La raison est enregistrée AVANT le changement de statut : le trigger d'e-mail la lit
    insert into proposition_tours (proposition_id, cote, action, message, auteur, auteur_nom)
    values (p_id, v_cote, 'refuser', nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
    update propositions set statut = 'refusee', updated_at = now() where id = p_id;
    return 'refusee';
  end if;

  if p_action = 'contre' then
    update propositions set jour = p_jour, heure = p_heure, lieu = coalesce(p_lieu, p.lieu),
      statut = case v_cote when 'annonceur' then 'contre' else 'envoyee' end, updated_at = now() where id = p_id;
    insert into proposition_tours (proposition_id, cote, action, jour, heure, lieu, message, auteur, auteur_nom)
    values (p_id, v_cote, 'contre', p_jour, p_heure, coalesce(p_lieu, p.lieu), nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
    return case v_cote when 'annonceur' then 'contre' else 'envoyee' end;
  end if;

  -- Accepter : match dans le calendrier des deux équipes, créneau pris
  if p.jour < current_date then raise exception 'La date proposée est passée : fais une contre-proposition'; end if;
  select * into an from annonces where id = p.annonce_id;
  v_date := (p.jour + coalesce(p.heure, time '10:00')) at time zone 'Europe/Brussels';
  select c.nom || ' ' || tm.nom into v_nom_a from teams tm join clubs c on c.id = tm.club_id where tm.id = p.equipe_annonceur;
  select c.nom || ' ' || tm.nom into v_nom_p from teams tm join clubs c on c.id = tm.club_id where tm.id = p.equipe_proposante;
  select coalesce(an.duree_mt, f.duree_mt, 30) into v_duree from teams tm left join formats f on f.code = tm.format where tm.id = p.equipe_annonceur;
  insert into matches (team_id, date, adversaire, lieu, statut, timeline_json)
  values (p.equipe_annonceur, v_date, v_nom_p, case p.lieu when 'annonceur' then 'domicile' else 'exterieur' end, 'prevu',
          jsonb_build_object('halfDuration', v_duree)) returning id into v_ma;
  insert into matches (team_id, date, adversaire, lieu, statut, timeline_json)
  values (p.equipe_proposante, v_date, v_nom_a, case p.lieu when 'proposant' then 'domicile' else 'exterieur' end, 'prevu',
          jsonb_build_object('halfDuration', v_duree)) returning id into v_mp;
  update propositions set statut = 'acceptee', match_annonceur = v_ma, match_proposant = v_mp, updated_at = now() where id = p_id;
  update annonce_creneaux set statut = 'pris' where annonce_id = p.annonce_id and jour = p.jour;
  insert into proposition_tours (proposition_id, cote, action, jour, heure, lieu, message, auteur, auteur_nom)
  values (p_id, v_cote, 'accepter', p.jour, p.heure, p.lieu, nullif(trim(p_message), ''), auth.uid(), prop_nom_moi());
  return 'acceptee';
end $$;

create or replace function public.notif_propositions() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare r text := notif_prop_resume(new);
begin
  if tg_op = 'INSERT' then
    if new.statut = 'a_valider' then
      perform notif_ajouter(array(select notif_club_staff(new.club_proposant)), 'prop_a_envoyer',
        'Proposition de match à envoyer', E'Un entraîneur a préparé une proposition de match. Vérifie-la et envoie-la à l''autre club.\n\n' || r);
    elsif new.statut = 'envoyee' then
      perform notif_ajouter(notif_prop_cote(new, 'annonceur'), 'prop_recue',
        'Nouvelle proposition de match', E'Une proposition de match vous attend.\n\n' || r);
    end if;
    return new;
  end if;
  if new.statut = old.statut then
    -- Contre-proposition qui ne change pas le statut : impossible (tour par tour) ; rien à faire
    return new;
  end if;
  if old.statut = 'a_valider' and new.statut = 'envoyee' then
    perform notif_ajouter(notif_prop_cote(new, 'annonceur'), 'prop_recue', 'Nouvelle proposition de match', E'Une proposition de match vous attend.\n\n' || r);
  elsif new.statut = 'contre' then
    perform notif_ajouter(notif_prop_cote(new, 'proposant'), 'prop_contre', 'Contre-proposition reçue', E'L''autre club propose une autre date ou un autre lieu.\n\n' || r);
  elsif old.statut = 'contre' and new.statut = 'envoyee' then
    perform notif_ajouter(notif_prop_cote(new, 'annonceur'), 'prop_contre', 'Contre-proposition reçue', E'L''autre club propose une autre date ou un autre lieu.\n\n' || r);
  elsif new.statut = 'acceptee' then
    perform notif_ajouter(notif_prop_cote(new, 'annonceur') || notif_prop_cote(new, 'proposant'), 'prop_acceptee',
      'Match confirmé', E'La proposition est acceptée : le match est ajouté au calendrier des deux équipes.\n\n' || r);
  elsif new.statut = 'refusee' then
    perform notif_ajouter(notif_prop_cote(new, 'proposant'), 'prop_refusee', 'Proposition de match refusée', E'L''autre club a refusé la proposition.'
      || coalesce(E'\n\nRaison : « ' || (select message from proposition_tours where proposition_id = new.id and action = 'refuser'
                                         order by created_at desc limit 1) || ' »', '') || E'\n\n' || r);
  elsif new.statut = 'annulee' and old.statut in ('envoyee', 'contre') then
    perform notif_ajouter(notif_prop_cote(new, 'annonceur'), 'prop_annulee', 'Proposition de match annulée', E'L''autre club a annulé sa proposition.\n\n' || r);
  end if;
  return new;
end $$;

-- 2. Raison du refus d'une nouvelle date (clubs sans compte)
alter table public.invitations_match add column if not exists motif_refus text check (char_length(motif_refus) <= 300);

drop function if exists public.invitation_match_agir(uuid, text);
create function public.invitation_match_agir(p_id uuid, p_action text, p_motif text default null)
  returns text language plpgsql security definer set search_path = public as
$$ declare i invitations_match; v_match uuid;
begin
  select * into i from invitations_match where id = p_id for update;
  if i.id is null or not is_team_staff(i.team_id) then raise exception 'Accès refusé'; end if;
  if p_action = 'annuler' and i.statut in ('a_valider', 'envoyee', 'contre') and (is_club_member(i.club_id) or (i.statut = 'a_valider' and i.cree_par = auth.uid())) then
    update invitations_match set statut = 'annulee', updated_at = now() where id = p_id;
    return 'annulee';
  end if;
  if not is_club_member(i.club_id) then raise exception 'Réservé au coordinateur ou au CQ du club'; end if;
  if p_action = 'envoyer' and i.statut = 'a_valider' then
    if envois_externes_du_jour(i.club_id) >= 30 then raise exception 'Limite de 30 envois par jour atteinte'; end if;
    update invitations_match set statut = 'envoyee', envoye_le = now(), updated_at = now() where id = p_id;
    return 'envoyee';
  elsif p_action = 'accepter_contre' and i.statut = 'contre' then
    if coalesce(i.reponse_jour, i.jour) < current_date then raise exception 'La date proposée est passée'; end if;
    insert into matches (team_id, date, adversaire, lieu, statut, timeline_json)
    values (i.team_id, (coalesce(i.reponse_jour, i.jour) + coalesce(i.reponse_heure, i.heure, time '10:00')) at time zone 'Europe/Brussels',
            left(i.club_externe || coalesce(' ' || i.equipe_externe, ''), 80),
            case coalesce(i.reponse_lieu, i.lieu) when 'nous' then 'domicile' else 'exterieur' end, 'prevu', '{}'::jsonb)
    returning id into v_match;
    update invitations_match set statut = 'acceptee', match_id = v_match, updated_at = now() where id = p_id;
    -- Réponse à une annonce : le créneau de ce jour est pris
    if i.annonce_id is not null then
      update annonce_creneaux set statut = 'pris' where annonce_id = i.annonce_id and jour = coalesce(i.reponse_jour, i.jour);
    end if;
    return 'acceptee';
  elsif p_action = 'refuser_contre' and i.statut = 'contre' then
    update invitations_match set statut = 'refusee', motif_refus = nullif(left(trim(p_motif), 300), ''), updated_at = now() where id = p_id;
    return 'refusee';
  end if;
  raise exception 'Action impossible';
end $$;
revoke execute on function public.invitation_match_agir(uuid, text, text) from public, anon;
grant execute on function public.invitation_match_agir(uuid, text, text) to authenticated;

create or replace function public.notif_invitations_match() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare v_club text := (select nom from clubs where id = new.club_id);
begin
  if tg_op = 'INSERT' and new.origine = 'annonce' then
    perform notif_ajouter(notif_im_nous(new), 'im_annonce', 'Réponse à votre annonce : ' || new.club_externe,
      new.club_externe || coalesce(' ' || new.equipe_externe, '') || E' répond à votre annonce (lien partagé) :\n'
        || notif_im_resume(new, true)
        || coalesce(E'\n\nContact : ' || new.reponse_nom, '') || coalesce(' · ' || new.reponse_tel, '') || E' · ' || new.contact_email
        || coalesce(E'\nMessage : « ' || new.reponse_message || ' »', '')
        || E'\n\nAccepte ou refuse dans FootLink : Trouver un match → Propositions.');
  elsif tg_op = 'INSERT' and new.statut = 'a_valider' then
    perform notif_ajouter(array(select notif_club_staff(new.club_id)), 'im_a_envoyer', 'Proposition de match à envoyer',
      E'Un entraîneur a préparé une proposition de match par e-mail. Vérifie-la et envoie-la.\n\n' || notif_im_resume(new));
  elsif new.statut = 'envoyee' and (tg_op = 'INSERT' or old.statut is distinct from 'envoyee') then
    perform notif_ajouter_externe(new.contact_email, new.contact_nom, 'im_proposition',
      'Proposition de match de ' || v_club,
      v_club || E' vous propose un match :\n' || notif_im_resume(new)
        || coalesce(E'\n\nMessage : « ' || new.message || ' »', '')
        || E'\n\nRépondez en un clic (accepter, refuser ou proposer une autre date), sans créer de compte :',
      '/reponse.html?t=' || new.token, 'Répondre à la proposition');
  elsif tg_op = 'UPDATE' and new.statut <> old.statut then
    if new.statut = 'acceptee' and old.statut = 'envoyee' then
      perform notif_ajouter(notif_im_nous(new), 'im_acceptee', 'Match confirmé : ' || new.club_externe,
        new.club_externe || E' a accepté votre proposition : le match est ajouté au calendrier.\n\n' || notif_im_resume(new)
          || coalesce(E'\n\nContact : ' || new.reponse_nom, '') || coalesce(' · ' || new.reponse_tel, '')
          || coalesce(E'\nMessage : « ' || new.reponse_message || ' »', ''));
    elsif new.statut = 'acceptee' and old.statut = 'contre' then
      perform notif_ajouter_externe(new.contact_email, coalesce(new.reponse_nom, new.contact_nom), 'im_confirme',
        'Match confirmé avec ' || v_club,
        v_club || E' accepte votre proposition : le match est confirmé.\n\n' || notif_im_resume(new, true), null, null);
    elsif new.statut = 'refusee' and old.statut = 'envoyee' then
      perform notif_ajouter(notif_im_nous(new), 'im_refusee', 'Proposition refusée : ' || new.club_externe,
        new.club_externe || E' a refusé la proposition.\n\n' || notif_im_resume(new)
          || coalesce(E'\n\nMessage : « ' || new.reponse_message || ' »', ''));
    elsif new.statut = 'refusee' and old.statut = 'contre' then
      perform notif_ajouter_externe(new.contact_email, coalesce(new.reponse_nom, new.contact_nom), 'im_contre_refusee',
        'Réponse de ' || v_club, v_club || E' ne peut pas jouer à la date que vous avez proposée.'
          || coalesce(E'\n\nRaison : « ' || new.motif_refus || ' »', '') || E'\n\n' || notif_im_resume(new, true), null, null);
    elsif new.statut = 'contre' then
      perform notif_ajouter(notif_im_nous(new), 'im_contre', 'Autre date proposée : ' || new.club_externe,
        new.club_externe || E' propose une autre date :\n' || notif_im_resume(new, true)
          || coalesce(E'\n\nContact : ' || new.reponse_nom, '') || coalesce(' · ' || new.reponse_tel, '')
          || coalesce(E'\nMessage : « ' || new.reponse_message || ' »', '')
          || E'\n\nAccepte ou refuse dans FootLink : Trouver un match → Propositions.');
    end if;
  end if;
  return new;
end $$;

commit;
