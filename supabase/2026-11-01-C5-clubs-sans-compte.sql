-- ============================================================================
-- FootLink — Clubs sans compte (C5) — 2026-11-01
-- Nécessite C2 (propositions), C3 / C3b (notifications) et A1 (clubs).
-- 1. Proposition de match PAR E-MAIL à un club qui n'a pas FootLink : il répond
--    (accepter / refuser / autre date) sur une page web, sans compte, grâce à un lien
--    secret. À l'accord, le match s'ajoute au calendrier de notre équipe.
-- 2. Invitation à REJOINDRE FootLink : lien par e-mail ; la personne crée son compte et la
--    fiche de son club (pré-remplie), elle en devient CQ ; le club qui invite est prévenu.
-- Qui envoie : CQ / coordinateur d'un club VÉRIFIÉ (un entraîneur / délégué prépare une
-- proposition, son coordinateur l'envoie). Garde-fou anti-abus : 30 envois par club et par jour.
-- L'adresse e-mail du club extérieur ne sert qu'à cet échange.
-- La file d'e-mails accepte désormais des destinataires sans compte (email_externe).
-- Testé sur la base de test (supabase/tests/tests-securite.sql).
-- Annulation : 2026-11-01-C5-clubs-sans-compte-ANNULER.sql
-- ============================================================================
begin;

-- ------------------------------------------------------------------ FILE D'E-MAILS : DESTINATAIRES EXTERNES
alter table public.notifications alter column profile_id drop not null;
alter table public.notifications add column if not exists email_externe text check (char_length(email_externe) <= 200);
alter table public.notifications add column if not exists nom_externe text check (char_length(nom_externe) <= 100);
alter table public.notifications add column if not exists lien text check (char_length(lien) <= 300);     -- bouton de l'e-mail
alter table public.notifications add column if not exists bouton text check (char_length(bouton) <= 60);
alter table public.notifications drop constraint if exists notifications_destinataire;
alter table public.notifications add constraint notifications_destinataire check (profile_id is not null or email_externe is not null);

create or replace function public.notif_ajouter_externe(p_email text, p_nom text, p_type text, p_titre text, p_texte text,
                                                        p_lien text default null, p_bouton text default null)
  returns void language sql security definer set search_path = public as
$$ insert into notifications (email_externe, nom_externe, type, titre, texte, lien, bouton)
   values (lower(trim(p_email)), nullif(trim(p_nom), ''), p_type, left(p_titre, 200), left(p_texte, 4000), p_lien, p_bouton) $$;

-- Réservation d'un lot : comptes ET adresses externes (+ bouton de l'e-mail)
drop function if exists public.notif_reserver(int);
create function public.notif_reserver(p_max int default 40)
returns table(id uuid, email text, prenom text, titre text, texte text, lien text, bouton text, externe boolean)
language plpgsql security definer set search_path = public as
$$ begin
  update notifications set statut = 'echec', erreur = coalesce(erreur, 'envoi interrompu')
    where statut = 'en_cours' and essais >= 3 and envoyer_apres <= now();
  return query
  update notifications n set statut = 'en_cours', essais = n.essais + 1,
         envoyer_apres = now() + interval '10 minutes'          -- réservation de 10 minutes
   from (select x.id as nid, coalesce(pr.email, x.email_externe) as mail, coalesce(pr.prenom, x.nom_externe) as pren
         from notifications x left join profiles pr on pr.id = x.profile_id
         where (x.statut = 'a_envoyer' or (x.statut = 'en_cours' and x.essais < 3)) and x.envoyer_apres <= now()
         order by x.created_at limit p_max for update of x skip locked) s
   where n.id = s.nid
   returning n.id, s.mail, s.pren, n.titre, n.texte, n.lien, n.bouton, n.profile_id is null;
end $$;
revoke execute on function public.notif_reserver(int) from public, anon, authenticated;
grant execute on function public.notif_reserver(int) to service_role;

-- ------------------------------------------------------------------ 1. PROPOSITION DE MATCH PAR E-MAIL
create table public.invitations_match (
  id uuid primary key default extensions.uuid_generate_v4(),
  token text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  team_id uuid not null references public.teams(id) on delete cascade,        -- notre équipe
  club_id uuid not null references public.clubs(id) on delete cascade,
  club_externe text not null check (char_length(club_externe) between 1 and 80),
  equipe_externe text check (char_length(equipe_externe) <= 60),
  contact_nom text check (char_length(contact_nom) <= 100),
  contact_email text not null check (contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(contact_email) <= 200),
  jour date not null,
  heure time,
  lieu text not null default 'nous' check (lieu in ('nous', 'eux')),
  message text check (char_length(message) <= 1000),
  statut text not null check (statut in ('a_valider', 'envoyee', 'contre', 'acceptee', 'refusee', 'annulee')),
  -- Réponse du club extérieur (autre date / message / coordonnées)
  reponse_jour date, reponse_heure time, reponse_lieu text check (reponse_lieu in ('nous', 'eux')),
  reponse_message text check (char_length(reponse_message) <= 1000),
  reponse_nom text check (char_length(reponse_nom) <= 100),
  reponse_tel text check (char_length(reponse_tel) <= 30),
  match_id uuid references public.matches(id) on delete set null,
  cree_par uuid default auth.uid() references public.profiles(id) on delete set null,
  envoye_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index invitations_match_team_idx on public.invitations_match (team_id);
alter table public.invitations_match enable row level security;
create policy "Invitations de match lecture" on public.invitations_match for select to authenticated
  using (is_team_staff(team_id));

-- Destinataires internes : CQ / coordinateurs du club + encadrement de l'équipe
create or replace function public.notif_im_nous(i invitations_match) returns uuid[]
  language sql stable security definer set search_path = public as
$$ select array(select notif_club_staff(i.club_id) union select notif_team_staff(i.team_id)) $$;
create or replace function public.notif_im_resume(i invitations_match, p_reponse boolean default false) returns text
  language sql stable security definer set search_path = public as
$$ select notif_equipe(i.team_id) || ' contre ' || i.club_externe || coalesce(' ' || i.equipe_externe, '') || E'\n'
       || 'Le ' || notif_jour(case when p_reponse then coalesce(i.reponse_jour, i.jour) else i.jour end)
       || coalesce(' à ' || to_char(case when p_reponse then coalesce(i.reponse_heure, i.heure) else i.heure end, 'HH24:MI'), '')
       || case (case when p_reponse then coalesce(i.reponse_lieu, i.lieu) else i.lieu end)
            when 'nous' then ', chez ' || (select nom from clubs where id = i.club_id) else ', chez ' || i.club_externe end $$;

-- Préparer / envoyer une proposition à un club sans compte
create or replace function public.invitation_match_creer(p_team uuid, p_club_externe text, p_equipe_externe text,
    p_email text, p_contact text, p_jour date, p_heure time, p_lieu text, p_message text default null)
  returns uuid language plpgsql security definer set search_path = public as
$$ declare v_club uuid; v_id uuid; v_statut text;
begin
  if not is_team_staff(p_team) then raise exception 'Tu n''encadres pas cette équipe'; end if;
  select t.club_id into v_club from teams t join clubs c on c.id = t.club_id where t.id = p_team and c.verifie;
  if v_club is null then raise exception 'L''équipe doit appartenir à un club vérifié'; end if;
  if p_jour is null or p_jour < current_date then raise exception 'Choisis une date à venir'; end if;
  if coalesce(p_lieu, '') not in ('nous', 'eux') then raise exception 'Lieu invalide'; end if;
  if nullif(trim(p_club_externe), '') is null then raise exception 'Nom du club adverse obligatoire'; end if;
  if coalesce(trim(p_email), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Adresse e-mail invalide'; end if;
  v_statut := case when is_club_member(v_club) then 'envoyee' else 'a_valider' end;
  if v_statut = 'envoyee' and envois_externes_du_jour(v_club) >= 30 then raise exception 'Limite de 30 envois par jour atteinte'; end if;
  insert into invitations_match (team_id, club_id, club_externe, equipe_externe, contact_nom, contact_email, jour, heure, lieu, message, statut, envoye_le)
  values (p_team, v_club, trim(p_club_externe), nullif(trim(p_equipe_externe), ''), nullif(trim(p_contact), ''), lower(trim(p_email)),
          p_jour, p_heure, p_lieu, nullif(trim(p_message), ''), v_statut, case when v_statut = 'envoyee' then now() end)
  returning id into v_id;
  return v_id;
end $$;

-- Actions côté club : envoyer (préparée), annuler, accepter / refuser la contre-proposition
create or replace function public.invitation_match_agir(p_id uuid, p_action text)
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
    return 'acceptee';
  elsif p_action = 'refuser_contre' and i.statut = 'contre' then
    update invitations_match set statut = 'refusee', updated_at = now() where id = p_id;
    return 'refusee';
  end if;
  raise exception 'Action impossible';
end $$;

-- Page publique (lien secret de l'e-mail) : voir la proposition…
create or replace function public.invitation_match_voir(p_token text) returns jsonb
  language sql stable security definer set search_path = public as
$$ select jsonb_build_object('club', c.nom, 'logo', c.logo, 'couleur1', c.couleur1, 'couleur2', c.couleur2,
          'adresse', c.adresse, 'equipe', t.nom, 'categorie', t.categorie, 'format', t.format,
          'club_externe', i.club_externe, 'equipe_externe', i.equipe_externe, 'contact_nom', i.contact_nom,
          'jour', i.jour, 'heure', to_char(i.heure, 'HH24:MI'), 'lieu', i.lieu, 'message', i.message, 'statut', i.statut,
          'reponse_jour', i.reponse_jour, 'reponse_heure', to_char(i.reponse_heure, 'HH24:MI'), 'reponse_lieu', i.reponse_lieu)
   from invitations_match i join teams t on t.id = i.team_id join clubs c on c.id = i.club_id
   where i.token = p_token and i.statut <> 'a_valider' $$;

-- … et y répondre (sans compte) : accepter (le match est créé), refuser, proposer autre chose
create or replace function public.invitation_match_repondre(p_token text, p_action text, p_jour date default null,
    p_heure time default null, p_lieu text default null, p_message text default null, p_nom text default null, p_tel text default null)
  returns text language plpgsql security definer set search_path = public as
$$ declare i invitations_match; v_match uuid;
begin
  select * into i from invitations_match where token = p_token for update;
  if i.id is null or i.statut <> 'envoyee' then raise exception 'Cette proposition n''attend plus de réponse'; end if;
  if p_action = 'accepter' then
    if i.jour < current_date then raise exception 'La date est passée : propose une autre date'; end if;
    insert into matches (team_id, date, adversaire, lieu, statut, timeline_json)
    values (i.team_id, (i.jour + coalesce(i.heure, time '10:00')) at time zone 'Europe/Brussels',
            left(i.club_externe || coalesce(' ' || i.equipe_externe, ''), 80),
            case i.lieu when 'nous' then 'domicile' else 'exterieur' end, 'prevu', '{}'::jsonb)
    returning id into v_match;
    update invitations_match set statut = 'acceptee', match_id = v_match, reponse_message = nullif(trim(p_message), ''),
      reponse_nom = nullif(trim(p_nom), ''), reponse_tel = nullif(trim(p_tel), ''), updated_at = now() where id = i.id;
    return 'acceptee';
  elsif p_action = 'refuser' then
    update invitations_match set statut = 'refusee', reponse_message = nullif(trim(p_message), ''),
      reponse_nom = nullif(trim(p_nom), ''), updated_at = now() where id = i.id;
    return 'refusee';
  elsif p_action = 'contre' then
    if p_jour is null or p_jour < current_date then raise exception 'Choisis une date à venir'; end if;
    if coalesce(p_lieu, '') not in ('nous', 'eux') then raise exception 'Lieu invalide'; end if;
    update invitations_match set statut = 'contre', reponse_jour = p_jour, reponse_heure = p_heure, reponse_lieu = p_lieu,
      reponse_message = nullif(trim(p_message), ''), reponse_nom = nullif(trim(p_nom), ''), reponse_tel = nullif(trim(p_tel), ''),
      updated_at = now() where id = i.id;
    return 'contre';
  end if;
  raise exception 'Action inconnue';
end $$;

-- E-mails de la proposition par e-mail
create or replace function public.notif_invitations_match() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare v_club text := (select nom from clubs where id = new.club_id);
begin
  if tg_op = 'INSERT' and new.statut = 'a_valider' then
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
        'Réponse de ' || v_club, v_club || E' ne peut pas jouer à la date que vous avez proposée.\n\n' || notif_im_resume(new, true), null, null);
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
create trigger invitations_match_notif after insert or update of statut on public.invitations_match
  for each row execute function public.notif_invitations_match();

-- Liste pour l'app (encadrement de l'équipe)
create or replace function public.mes_invitations_match()
returns table(id uuid, team_id uuid, equipe text, club_externe text, equipe_externe text, contact_nom text, contact_email text,
              jour date, heure text, lieu text, message text, statut text, reponse_jour date, reponse_heure text, reponse_lieu text,
              reponse_message text, reponse_nom text, reponse_tel text, decide boolean, created_at timestamptz)
language sql stable security definer set search_path = public as
$$ select i.id, i.team_id, t.nom, i.club_externe, i.equipe_externe, i.contact_nom, i.contact_email, i.jour, to_char(i.heure, 'HH24:MI'),
          i.lieu, i.message, i.statut, i.reponse_jour, to_char(i.reponse_heure, 'HH24:MI'), i.reponse_lieu, i.reponse_message,
          i.reponse_nom, i.reponse_tel, is_club_member(i.club_id), i.created_at
   from invitations_match i join teams t on t.id = i.team_id
   where is_team_staff(i.team_id) order by i.created_at desc $$;

-- ------------------------------------------------------------------ 2. INVITER UN CLUB À REJOINDRE FOOTLINK
create table public.invitations_club (
  id uuid primary key default extensions.uuid_generate_v4(),
  token text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  club_id uuid not null references public.clubs(id) on delete cascade,          -- club qui invite
  email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 200),
  contact_nom text check (char_length(contact_nom) <= 100),
  club_nom text check (char_length(club_nom) <= 80),                             -- nom suggéré du club invité
  message text check (char_length(message) <= 500),
  statut text not null default 'envoyee' check (statut in ('envoyee', 'acceptee', 'annulee')),
  club_cree uuid references public.clubs(id) on delete set null,
  utilise_par uuid references public.profiles(id) on delete set null,
  cree_par uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.invitations_club enable row level security;
create policy "Invitations de club lecture" on public.invitations_club for select to authenticated
  using (is_club_member(club_id));

-- Garde-fou anti-abus : envois vers l'extérieur par club et par jour
create or replace function public.envois_externes_du_jour(c uuid) returns int
  language sql stable security definer set search_path = public as
$$ select (select count(*) from invitations_match where club_id = c and envoye_le >= current_date)::int
        + (select count(*) from invitations_club where club_id = c and created_at >= current_date)::int $$;

create or replace function public.invitation_club_creer(p_club uuid, p_email text, p_contact text default null,
                                                        p_club_nom text default null, p_message text default null)
  returns uuid language plpgsql security definer set search_path = public as
$$ declare v_id uuid;
begin
  if not is_club_member(p_club) then raise exception 'Réservé au coordinateur ou au CQ du club'; end if;
  if not exists (select 1 from clubs where id = p_club and verifie) then raise exception 'Ton club doit être vérifié'; end if;
  if coalesce(trim(p_email), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Adresse e-mail invalide'; end if;
  if envois_externes_du_jour(p_club) >= 30 then raise exception 'Limite de 30 envois par jour atteinte'; end if;
  insert into invitations_club (club_id, email, contact_nom, club_nom, message)
  values (p_club, lower(trim(p_email)), nullif(trim(p_contact), ''), nullif(trim(p_club_nom), ''), nullif(trim(p_message), ''))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.invitation_club_info(p_token text) returns jsonb
  language sql stable security definer set search_path = public as
$$ select jsonb_build_object('club', c.nom, 'club_nom', i.club_nom, 'email', i.email, 'valide', i.statut = 'envoyee')
   from invitations_club i join clubs c on c.id = i.club_id where i.token = p_token $$;

-- Utilisée après la création du club par la personne invitée (elle en est CQ)
create or replace function public.invitation_club_utiliser(p_token text, p_club uuid)
  returns void language plpgsql security definer set search_path = public as
$$ begin
  if not is_club_cq(p_club) then raise exception 'Accès refusé'; end if;
  update invitations_club set statut = 'acceptee', club_cree = p_club, utilise_par = auth.uid()
   where token = p_token and statut = 'envoyee';
end $$;

create or replace function public.notif_invitations_club() returns trigger
  language plpgsql security definer set search_path = public as
$$ declare v_club text := (select nom from clubs where id = new.club_id);
begin
  if tg_op = 'INSERT' then
    perform notif_ajouter_externe(new.email, new.contact_nom, 'ic_invitation', v_club || ' vous invite sur FootLink',
      v_club || E' utilise FootLink pour organiser ses équipes de jeunes et trouver des matchs, et vous invite à le rejoindre.\n\n'
        || 'FootLink est gratuit : effectifs, convocations, matchs en direct, tournois, propositions de match entre clubs.'
        || coalesce(E'\n\nMessage : « ' || new.message || ' »', '')
        || E'\n\nCréez votre compte puis la fiche de votre club :',
      '/?rejoindre=' || new.token, 'Rejoindre FootLink');
  elsif new.statut = 'acceptee' and old.statut <> 'acceptee' then
    perform notif_ajouter(array(select notif_club_staff(new.club_id)), 'ic_acceptee', 'Invitation acceptée',
      coalesce((select nom from clubs where id = new.club_cree), new.club_nom, 'Le club invité')
        || E' a rejoint FootLink suite à votre invitation. Une fois vérifié, il apparaîtra dans « Trouver un match ».');
  end if;
  return new;
end $$;
create trigger invitations_club_notif after insert or update of statut on public.invitations_club
  for each row execute function public.notif_invitations_club();

-- ------------------------------------------------------------------ DROITS
revoke execute on function public.notif_ajouter_externe(text, text, text, text, text, text, text),
  public.envois_externes_du_jour(uuid), public.notif_im_nous(invitations_match), public.notif_im_resume(invitations_match, boolean),
  public.notif_invitations_match(), public.notif_invitations_club() from public, anon, authenticated;
revoke execute on function public.invitation_match_creer(uuid, text, text, text, text, date, time, text, text),
  public.invitation_match_agir(uuid, text), public.mes_invitations_match(),
  public.invitation_club_creer(uuid, text, text, text, text), public.invitation_club_utiliser(text, uuid) from public, anon;
grant execute on function public.invitation_match_creer(uuid, text, text, text, text, date, time, text, text),
  public.invitation_match_agir(uuid, text), public.mes_invitations_match(),
  public.invitation_club_creer(uuid, text, text, text, text), public.invitation_club_utiliser(text, uuid) to authenticated;
-- Pages publiques (lien secret) : sans compte
revoke execute on function public.invitation_match_voir(text), public.invitation_match_repondre(text, text, date, time, text, text, text, text),
  public.invitation_club_info(text) from public;
grant execute on function public.invitation_match_voir(text), public.invitation_match_repondre(text, text, date, time, text, text, text, text),
  public.invitation_club_info(text) to anon, authenticated;

commit;
