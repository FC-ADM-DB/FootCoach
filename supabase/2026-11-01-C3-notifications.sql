-- ============================================================================
-- FootLink — Notifications par e-mail (C3) — 2026-11-01
-- Nécessite C2 (propositions), C6 (tournois) et A3 (parents).
-- Principe : la base dépose les e-mails à envoyer dans une file (« notifications ») au
-- moment où quelque chose se passe ; la fonction Edge « notifier » les envoie par Gmail.
-- - Propositions de match : à préparer / à valider (coordinateur, CQ), reçue, contre-
--   proposition, acceptée (match créé), refusée, annulée (l'autre club), messages.
-- - Inscriptions aux tournois : à envoyer (coordinateur du club inscrit), reçue
--   (organisateur), acceptée / refusée / désistement / annulation, messages.
-- - Convocations : les parents d'un enfant convoqué (« présent ») pour un match à venir.
--   Envoi différé de 10 minutes : l'entraîneur a le temps de corriger sa sélection, un
--   enfant décoché avant l'envoi n'est plus prévenu.
-- Destinataires : ceux qui doivent agir (CQ / coordinateur pour ce qu'ils valident ou
-- envoient, encadrement de l'équipe concernée), jamais l'auteur de l'action, jamais une
-- personne qui a décoché « Recevoir les e-mails » dans Mon profil (profiles.notif_email).
-- La file n'est lisible que par son destinataire ; seules la base et la fonction d'envoi
-- (clé service) y écrivent.
-- Correctif des tournois (C6) inclus : supprimer un club qui a organisé un tournoi avec
-- ses propres équipes échouait (liens vérifiés pendant la suppression en cascade).
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-11-01-C3-notifications-ANNULER.sql
-- ============================================================================
begin;

-- ------------------------------------------------------------------ CORRECTIF C6
-- En supprimant un club, PostgreSQL efface ses tournois (et leurs tableaux) ET vide le
-- lien « équipe » des équipes de tournoi ; cette mise à jour vérifiait le lien vers un
-- tableau déjà effacé → erreur. Liens des tables de tournoi vérifiés en fin de transaction.
do $$ declare r record;
begin
  for r in select c.conrelid::regclass as t, c.conname from pg_constraint c
           where c.contype = 'f' and c.connamespace = 'public'::regnamespace and not c.condeferrable
             and c.conrelid::regclass::text in ('tournoi_cibles', 'tournoi_tableaux', 'tournoi_inscriptions',
                                                'tournoi_equipes', 'tournoi_matchs', 'tournoi_messages') loop
    execute format('alter table %s alter constraint %I deferrable initially deferred', r.t, r.conname);
  end loop;
end $$;

create extension if not exists pg_net;
create extension if not exists pg_cron;

alter table public.profiles add column if not exists notif_email boolean not null default true;

create table public.notifications (
  id uuid primary key default extensions.uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  titre text not null check (char_length(titre) <= 200),
  texte text not null check (char_length(texte) <= 4000),
  cle text,                                   -- regroupement (une seule en attente par clé)
  envoyer_apres timestamptz not null default now(),
  statut text not null default 'a_envoyer' check (statut in ('a_envoyer', 'en_cours', 'envoye', 'simule', 'echec', 'annule')),
  essais int not null default 0,
  erreur text,
  envoye_le timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_attente_idx on public.notifications (envoyer_apres) where statut = 'a_envoyer';
create unique index notifications_cle_attente on public.notifications (cle) where statut = 'a_envoyer' and cle is not null;
alter table public.notifications enable row level security;
create policy "Notifications personnelles" on public.notifications for select to authenticated
  using (profile_id = auth.uid());

-- Réglages propres au projet (adresse de la fonction d'envoi)
create table if not exists public.app_config (cle text primary key, valeur text);
alter table public.app_config enable row level security;   -- aucune règle : invisible pour l'app

-- ------------------------------------------------------------------ DESTINATAIRES
create or replace function public.notif_club_staff(c uuid) returns setof uuid
  language sql stable security definer set search_path = public as
$$ select profile_id from club_members where club_id = c $$;
create or replace function public.notif_team_staff(t uuid) returns setof uuid
  language sql stable security definer set search_path = public as
$$ select profile_id from team_members where team_id = t and role in ('entraineur', 'delegue', 'admin', 'member') $$;

-- Dépose un e-mail pour chaque destinataire (sauf l'auteur et ceux qui ont coupé les
-- e-mails). Avec une clé : remplace l'e-mail encore en attente de même clé (+ id du profil).
create or replace function public.notif_ajouter(p_dest uuid[], p_type text, p_titre text, p_texte text,
                                                p_cle text default null, p_delai interval default '0')
  returns int language plpgsql security definer set search_path = public as
$$ declare v_n int := 0; v_p uuid;
begin
  for v_p in select distinct x from unnest(p_dest) x
             join profiles pr on pr.id = x
             where x is not null and x is distinct from auth.uid() and pr.notif_email and pr.email is not null loop
    if p_cle is not null then
      update notifications set titre = p_titre, texte = p_texte, envoyer_apres = now() + p_delai
        where cle = p_cle || ':' || v_p and statut = 'a_envoyer';
      if found then v_n := v_n + 1; continue; end if;
    end if;
    insert into notifications (profile_id, type, titre, texte, cle, envoyer_apres)
    values (v_p, p_type, left(p_titre, 200), left(p_texte, 4000), p_cle || ':' || v_p, now() + p_delai);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Mise en forme : « samedi 3 avril », « 10:30 »
create or replace function public.notif_jour(d date) returns text language sql immutable as
$$ select (array['dimanche','lundi','mardi','mercredi','jeudi','vendredi','samedi'])[extract(dow from d)::int + 1]
          || ' ' || extract(day from d)::int || ' '
          || (array['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'])[extract(month from d)::int] $$;
create or replace function public.notif_equipe(t uuid) returns text
  language sql stable security definer set search_path = public as
$$ select c.nom || ' ' || tm.nom from teams tm join clubs c on c.id = tm.club_id where tm.id = t $$;

-- ------------------------------------------------------------------ PROPOSITIONS
-- Résumé d'une proposition pour le texte des e-mails
create or replace function public.notif_prop_resume(p propositions) returns text
  language sql stable security definer set search_path = public as
$$ select notif_equipe(p.equipe_proposante) || ' et ' || notif_equipe(p.equipe_annonceur) || E'\n'
       || 'Le ' || notif_jour(p.jour) || coalesce(' à ' || to_char(p.heure, 'HH24:MI'), '')
       || ', chez ' || notif_equipe(case p.lieu when 'annonceur' then p.equipe_annonceur else p.equipe_proposante end) $$;

-- Un côté de la proposition : CQ / coordinateurs du club + encadrement de l'équipe
create or replace function public.notif_prop_cote(p propositions, v_cote text) returns uuid[]
  language sql stable security definer set search_path = public as
$$ select array(select notif_club_staff(case v_cote when 'annonceur' then p.club_annonceur else p.club_proposant end)
                union select notif_team_staff(case v_cote when 'annonceur' then p.equipe_annonceur else p.equipe_proposante end)) $$;

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
    perform notif_ajouter(notif_prop_cote(new, 'proposant'), 'prop_refusee', 'Proposition de match refusée', E'L''autre club a refusé la proposition.\n\n' || r);
  elsif new.statut = 'annulee' and old.statut in ('envoyee', 'contre') then
    perform notif_ajouter(notif_prop_cote(new, 'annonceur'), 'prop_annulee', 'Proposition de match annulée', E'L''autre club a annulé sa proposition.\n\n' || r);
  end if;
  return new;
end $$;
create trigger propositions_notif after insert or update of statut on public.propositions
  for each row execute function public.notif_propositions();

-- Suggestion d'un entraîneur à valider, ou message entre les deux clubs
create or replace function public.notif_proposition_tours() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare p propositions; v_autre text;
begin
  select * into p from propositions where id = new.proposition_id;
  v_autre := case new.cote when 'annonceur' then 'proposant' else 'annonceur' end;
  if new.en_attente then
    perform notif_ajouter(array(select notif_club_staff(case new.cote when 'annonceur' then p.club_annonceur else p.club_proposant end)),
      'prop_suggestion', 'Réponse à valider (proposition de match)',
      coalesce(new.auteur_nom, 'Un entraîneur') || ' propose ' ||
      case new.action when 'accepter' then 'd''accepter' when 'refuser' then 'de refuser' else 'une autre date ou un autre lieu' end ||
      E'. Valide ou écarte sa suggestion.\n\n' || notif_prop_resume(p));
  elsif new.action = 'message' then
    perform notif_ajouter(notif_prop_cote(p, v_autre), 'prop_message', 'Nouveau message (proposition de match)',
      coalesce(new.auteur_nom, 'L''autre club') || E' a écrit :\n« ' || left(new.message, 500) || E' »\n\n' || notif_prop_resume(p),
      'propmsg:' || p.id, interval '2 minutes');
  end if;
  return new;
end $$;
create trigger proposition_tours_notif after insert on public.proposition_tours
  for each row execute function public.notif_proposition_tours();

-- ------------------------------------------------------------------ TOURNOIS
create or replace function public.notif_ins_resume(i tournoi_inscriptions) returns text
  language sql stable security definer set search_path = public as
$$ select t.nom || ' — ' || notif_jour(t.jour) || coalesce(', ' || t.lieu, '') || E'\n'
       || 'Catégorie ' || tb.nom || ' : ' || i.nom || E'\nOrganisé par ' || c.nom
   from tournois t join tournoi_tableaux tb on tb.id = i.tableau_id join clubs c on c.id = t.club_id where t.id = i.tournoi_id $$;
create or replace function public.notif_ins_inscrit(i tournoi_inscriptions) returns uuid[]
  language sql stable security definer set search_path = public as
$$ select array(select notif_club_staff(i.club_id) union select notif_team_staff(i.team_id)) $$;
create or replace function public.notif_ins_org(i tournoi_inscriptions) returns uuid[]
  language sql stable security definer set search_path = public as
$$ select array(select notif_club_staff((select club_id from tournois where id = i.tournoi_id))) $$;

create or replace function public.notif_inscriptions() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare r text := notif_ins_resume(new); v_org boolean;
begin
  if tg_op = 'INSERT' then
    if new.statut = 'a_valider' then
      perform notif_ajouter(array(select notif_club_staff(new.club_id)), 'ins_a_envoyer', 'Inscription à un tournoi à envoyer',
        E'Un entraîneur a préparé une inscription. Vérifie-la et envoie-la à l''organisateur.\n\n' || r);
    elsif new.statut = 'envoyee' then
      perform notif_ajouter(notif_ins_org(new), 'ins_recue', 'Nouvelle inscription à ton tournoi', E'Une équipe demande à participer.\n\n' || r);
    end if;
    return new;
  end if;
  if new.statut = old.statut then return new; end if;
  v_org := is_club_member((select club_id from tournois where id = new.tournoi_id));
  if new.statut = 'envoyee' then
    perform notif_ajouter(notif_ins_org(new), 'ins_recue', 'Nouvelle inscription à ton tournoi', E'Une équipe demande à participer.\n\n' || r);
  elsif new.statut = 'acceptee' then
    perform notif_ajouter(notif_ins_inscrit(new), 'ins_acceptee', 'Inscription acceptée', E'Votre équipe est inscrite au tournoi.\n\n' || r);
  elsif new.statut = 'refusee' then
    perform notif_ajouter(notif_ins_inscrit(new), 'ins_refusee', 'Inscription refusée', E'L''organisateur a refusé l''inscription.\n\n' || r);
  elsif new.statut = 'desistee' then
    if v_org then
      perform notif_ajouter(notif_ins_inscrit(new), 'ins_desistee', 'Équipe retirée du tournoi', E'L''organisateur a retiré votre équipe du tournoi.\n\n' || r);
    else
      perform notif_ajouter(notif_ins_org(new), 'ins_desistee', 'Désistement à ton tournoi', E'Une équipe se désiste : sa place est libre.\n\n' || r);
    end if;
  elsif new.statut = 'annulee' and old.statut = 'envoyee' then
    perform notif_ajouter(notif_ins_org(new), 'ins_annulee', 'Inscription annulée', E'Le club a annulé sa demande d''inscription.\n\n' || r);
  end if;
  return new;
end $$;
create trigger tournoi_inscriptions_notif after insert or update of statut on public.tournoi_inscriptions
  for each row execute function public.notif_inscriptions();

create or replace function public.notif_tournoi_messages() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare i tournoi_inscriptions;
begin
  select * into i from tournoi_inscriptions where id = new.inscription_id;
  -- Pas d'e-mail pour le message joint à une inscription encore « à valider »
  if i.statut = 'a_valider' then return new; end if;
  perform notif_ajouter(case new.cote when 'organisateur' then notif_ins_inscrit(i) else notif_ins_org(i) end,
    'ins_message', 'Nouveau message (tournoi)',
    coalesce(new.auteur_nom, 'L''autre club') || E' a écrit :\n« ' || left(new.texte, 500) || E' »\n\n' || notif_ins_resume(i),
    'insmsg:' || i.id, interval '2 minutes');
  return new;
end $$;
create trigger tournoi_messages_notif after insert on public.tournoi_messages
  for each row execute function public.notif_tournoi_messages();

-- ------------------------------------------------------------------ CONVOCATIONS
-- Enfant mis « présent » par l'encadrement pour un match à venir → ses parents (envoi
-- dans 10 minutes) ; décoché avant l'envoi → e-mail annulé. La réponse d'un parent ne
-- déclenche rien.
create or replace function public.notif_convocations() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare m matches; v_prenom text; v_cle text := 'convoc:' || new.match_id || ':' || new.player_id;
begin
  if tg_op = 'UPDATE' and new.statut is not distinct from old.statut then return new; end if;
  select * into m from matches where id = new.match_id;
  if m.id is null or m.statut <> 'prevu' or m.date < now() or not is_team_staff(m.team_id) then return new; end if;
  if new.statut = 'present' then
    select prenom into v_prenom from players where id = new.player_id;
    perform notif_ajouter(array(select profile_id from parent_enfants where player_id = new.player_id), 'convocation',
      v_prenom || ' est convoqué(e) — ' || notif_jour((m.date at time zone 'Europe/Brussels')::date),
      v_prenom || E' est convoqué(e) pour le match :\n' || notif_equipe(m.team_id) || ' contre ' || m.adversaire || E'\n'
        || 'Le ' || notif_jour((m.date at time zone 'Europe/Brussels')::date) || ' à ' || to_char(m.date at time zone 'Europe/Brussels', 'HH24:MI')
        || case m.lieu when 'domicile' then ' (à domicile)' when 'exterieur' then ' (à l''extérieur)' else '' end
        || E'\n\nRéponds dans FootLink : présent, absent ou incertain.',
      v_cle, interval '10 minutes');
  else
    update notifications set statut = 'annule' where cle like v_cle || ':%' and statut = 'a_envoyer';
  end if;
  return new;
end $$;
create trigger convocations_notif after insert or update of statut on public.convocations
  for each row execute function public.notif_convocations();

-- ------------------------------------------------------------------ ENVOI
-- La fonction Edge « notifier » réserve un lot, l'envoie, puis rend compte (clé service
-- uniquement). Un e-mail en échec est retenté 3 fois.
create or replace function public.notif_reserver(p_max int default 40)
returns table(id uuid, email text, prenom text, titre text, texte text)
language sql security definer set search_path = public as
$$ update notifications n set statut = 'en_cours', essais = n.essais + 1
   from profiles pr
   where n.id in (select x.id from notifications x where x.statut = 'a_envoyer' and x.envoyer_apres <= now()
                  order by x.created_at limit p_max for update skip locked)
     and pr.id = n.profile_id
   returning n.id, pr.email, pr.prenom, n.titre, n.texte $$;
create or replace function public.notif_terminer(p_id uuid, p_statut text, p_erreur text default null)
  returns void language sql security definer set search_path = public as
$$ update notifications set
     statut = case when p_statut = 'echec' and essais < 3 then 'a_envoyer' else p_statut end,
     envoyer_apres = case when p_statut = 'echec' then now() + interval '5 minutes' else envoyer_apres end,
     erreur = left(p_erreur, 500), envoye_le = case when p_statut in ('envoye', 'simule') then now() end
   where id = p_id $$;

-- Réveil de la fonction d'envoi : à chaque dépôt (immédiat) et toutes les 5 minutes
-- (envois différés, nouvelles tentatives). Sans adresse configurée, la file attend.
create or replace function public.notif_reveiller() returns void
  language plpgsql security definer set search_path = public, extensions as
$$ declare v_url text;
begin
  select valeur into v_url from app_config where cle = 'notifier_url';
  if v_url is null then return; end if;
  perform net.http_post(url := v_url, body := '{}'::jsonb, headers := '{"Content-Type":"application/json"}'::jsonb);
end $$;
create or replace function public.notif_reveil_trigger() returns trigger
  language plpgsql security definer set search_path = public as
$$ begin
  if exists (select 1 from notifications where statut = 'a_envoyer' and envoyer_apres <= now()) then
    perform notif_reveiller();
  end if;
  return null;
end $$;
create trigger notifications_reveil after insert on public.notifications
  for each statement execute function public.notif_reveil_trigger();
select cron.schedule('footlink-notifier', '*/5 * * * *', $$ select public.notif_reveiller() $$);

-- ------------------------------------------------------------------ DROITS
revoke execute on function public.notif_club_staff(uuid), public.notif_team_staff(uuid),
  public.notif_ajouter(uuid[], text, text, text, text, interval), public.notif_equipe(uuid),
  public.notif_prop_resume(propositions), public.notif_prop_cote(propositions, text),
  public.notif_ins_resume(tournoi_inscriptions), public.notif_ins_inscrit(tournoi_inscriptions),
  public.notif_ins_org(tournoi_inscriptions), public.notif_reserver(int), public.notif_terminer(uuid, text, text),
  public.notif_reveiller(), public.notif_reveil_trigger(), public.notif_propositions(), public.notif_proposition_tours(),
  public.notif_inscriptions(), public.notif_tournoi_messages(), public.notif_convocations()
  from public, anon, authenticated;
grant execute on function public.notif_reserver(int), public.notif_terminer(uuid, text, text) to service_role;

-- ------------------------------------------------------------------ ADRESSE DE LA FONCTION D'ENVOI
-- PRODUCTION. (Sur la base de test, cette ligne est remplacée par l'adresse du projet de test.)
insert into public.app_config (cle, valeur)
values ('notifier_url', 'https://oejcfjthamzgnudofcwi.supabase.co/functions/v1/notifier')
on conflict (cle) do update set valeur = excluded.valeur;

commit;
