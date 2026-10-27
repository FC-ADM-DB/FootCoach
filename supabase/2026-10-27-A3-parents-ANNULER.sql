-- ============================================================================
-- FootCoach — ANNULATION de l'accès parents (A3) — 2026-10-27
-- Supprime les invitations, les liens parent ↔ enfant et les réponses des parents.
-- Les comptes parents restent membres « parent » de leur équipe (comme avant A3).
-- ============================================================================
begin;
drop function if exists public.parent_repondre(uuid, uuid, text);
drop function if exists public.rejoindre_invitation(text);
drop function if exists public.invitation_info(text);
drop function if exists public.equipe_prenoms(uuid);
drop policy if exists "Joueurs parent lecture" on public.players;
drop table if exists public.invitations_parent;
drop table if exists public.parent_enfants;
drop function if exists public.is_parent_of(uuid);
drop function if exists public.player_team(uuid);
alter table public.convocations drop column if exists reponse_parent,
  drop column if exists reponse_par, drop column if exists reponse_le;
commit;
