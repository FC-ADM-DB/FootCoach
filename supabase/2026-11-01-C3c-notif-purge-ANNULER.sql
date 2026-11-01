-- ============================================================================
-- FootLink — ANNULATION de C3c (purge des e-mails de plus de 12 mois) — 2026-11-01
-- ============================================================================
begin;
do $$ begin
  if exists (select 1 from cron.job where jobname = 'footlink-notif-purge') then perform cron.unschedule('footlink-notif-purge'); end if;
end $$;
commit;
