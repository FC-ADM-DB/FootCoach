-- ============================================================================
-- FootLink — Notifications (C3c) : historique des e-mails limité à 12 mois — 2026-11-01
-- Nécessite C3. La politique de confidentialité annonce que l'historique des e-mails de
-- notification est conservé 12 mois au maximum : une tâche planifiée (chaque nuit, 3 h)
-- supprime les e-mails envoyés, simulés, annulés ou en échec de plus de 12 mois.
-- Annulation : 2026-11-01-C3c-notif-purge-ANNULER.sql
-- ============================================================================
begin;
select cron.schedule('footlink-notif-purge', '0 3 * * *',
  $$ delete from public.notifications
     where statut in ('envoye', 'simule', 'annule', 'echec') and created_at < now() - interval '12 months' $$);
commit;
