-- ============================================================================
-- FootLink — ANNULATION des notifications par e-mail (C3) — 2026-11-01
-- Retire la file d'e-mails, les déclencheurs, la tâche planifiée et la case « Recevoir
-- les e-mails » du profil. Les extensions pg_net / pg_cron restent installées (sans effet).
-- ============================================================================
begin;
do $$ begin
  if exists (select 1 from cron.job where jobname = 'footlink-notifier') then perform cron.unschedule('footlink-notifier'); end if;
end $$;
drop trigger if exists propositions_notif on public.propositions;
drop trigger if exists proposition_tours_notif on public.proposition_tours;
drop trigger if exists tournoi_inscriptions_notif on public.tournoi_inscriptions;
drop trigger if exists tournoi_messages_notif on public.tournoi_messages;
drop trigger if exists convocations_notif on public.convocations;
drop table if exists public.notifications;
drop table if exists public.app_config;
drop function if exists public.notif_reveil_trigger();
drop function if exists public.notif_reveiller();
drop function if exists public.notif_terminer(uuid, text, text);
drop function if exists public.notif_reserver(int);
drop function if exists public.notif_convocations();
drop function if exists public.notif_tournoi_messages();
drop function if exists public.notif_inscriptions();
drop function if exists public.notif_ins_org(public.tournoi_inscriptions);
drop function if exists public.notif_ins_inscrit(public.tournoi_inscriptions);
drop function if exists public.notif_ins_resume(public.tournoi_inscriptions);
drop function if exists public.notif_proposition_tours();
drop function if exists public.notif_propositions();
drop function if exists public.notif_prop_cote(public.propositions, text);
drop function if exists public.notif_prop_resume(public.propositions);
drop function if exists public.notif_equipe(uuid);
drop function if exists public.notif_jour(date);
drop function if exists public.notif_ajouter(uuid[], text, text, text, text, interval);
drop function if exists public.notif_team_staff(uuid);
drop function if exists public.notif_club_staff(uuid);
alter table public.profiles drop column if exists notif_email;
commit;
