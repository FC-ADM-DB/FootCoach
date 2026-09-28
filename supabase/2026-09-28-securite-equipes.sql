-- ============================================================================
-- FootCoach — Sécurité des équipes (RLS) — 2026-09-28
-- À exécuter en une fois dans Supabase → SQL Editor → Run.
-- Annulation : 2026-09-28-securite-equipes-ANNULER.sql
--
-- Constat : RLS désactivée sur teams et team_members (lisibles et modifiables sans
-- être connecté), la règle "Members select" provoquait une récursion infinie, et
-- plusieurs règles manquaient (modifier/retirer un membre, supprimer une équipe,
-- voir le profil des coéquipiers, voir l'équipe qu'on vient de créer).
-- ============================================================================
begin;

-- Colonnes utilisées par l'app (logo d'équipe, créateur de l'équipe)
alter table public.teams add column if not exists logo text;
alter table public.teams add column if not exists created_by uuid default auth.uid();

-- ---------------------------------------------------------------------------
-- Fonctions d'aide. SECURITY DEFINER : elles lisent team_members sans repasser par
-- ses propres règles — c'est ce qui évite l'erreur "infinite recursion".
-- ---------------------------------------------------------------------------
create or replace function public.is_team_member(t uuid) returns boolean
  language sql security definer stable set search_path = public as
$$ select exists(select 1 from team_members where team_id = t and profile_id = auth.uid()) $$;

create or replace function public.is_team_admin(t uuid) returns boolean
  language sql security definer stable set search_path = public as
$$ select exists(select 1 from team_members where team_id = t and profile_id = auth.uid() and role = 'admin') $$;

create or replace function public.is_team_creator(t uuid) returns boolean
  language sql security definer stable set search_path = public as
$$ select exists(select 1 from teams where id = t and created_by = auth.uid()) $$;

create or replace function public.shares_team_with(p uuid) returns boolean
  language sql security definer stable set search_path = public as
$$ select exists(select 1 from team_members a join team_members b on b.team_id = a.team_id
                 where a.profile_id = auth.uid() and b.profile_id = p) $$;

-- Recherche d'une personne par email (page Membres & accès) : réservée aux admins
-- d'au moins une équipe, ne renvoie que l'identité (pas tout le profil).
create or replace function public.find_profile_by_email(e text)
  returns table(id uuid, prenom text, nom text, email text)
  language sql security definer stable set search_path = public as
$$ select p.id, p.prenom::text, p.nom::text, p.email::text from profiles p
   where lower(p.email) = lower(trim(e))
     and exists(select 1 from team_members where profile_id = auth.uid() and role = 'admin') $$;

-- Suppression d'une équipe (admin uniquement) : ses accès puis l'équipe, en une fois.
create or replace function public.delete_team(t uuid) returns void
  language plpgsql security definer set search_path = public as
$$ begin
  if not public.is_team_admin(t) then raise exception 'Accès admin requis'; end if;
  delete from team_members where team_id = t;
  delete from teams where id = t;
end $$;

-- ---------------------------------------------------------------------------
-- TEAMS : visibles par leurs membres (et par le créateur, juste après la création),
-- modifiables et supprimables par leurs admins uniquement.
-- ---------------------------------------------------------------------------
drop policy if exists "Teams select" on public.teams;
drop policy if exists "Teams insert" on public.teams;
drop policy if exists "Teams update" on public.teams;
drop policy if exists "Teams delete" on public.teams;
create policy "Teams select" on public.teams for select to authenticated
  using (public.is_team_member(id) or created_by = auth.uid());
create policy "Teams insert" on public.teams for insert to authenticated
  with check (created_by = auth.uid());
create policy "Teams update" on public.teams for update to authenticated
  using (public.is_team_admin(id)) with check (public.is_team_admin(id));
create policy "Teams delete" on public.teams for delete to authenticated
  using (public.is_team_admin(id));
alter table public.teams enable row level security;

-- ---------------------------------------------------------------------------
-- TEAM_MEMBERS : chacun voit les membres de ses équipes ; seuls les admins ajoutent,
-- changent un rôle ou retirent quelqu'un. Exception : le créateur d'une équipe peut
-- s'y ajouter lui-même (1er admin). Chacun peut quitter une équipe.
-- ---------------------------------------------------------------------------
drop policy if exists "Members select" on public.team_members;
drop policy if exists "Members insert" on public.team_members;
drop policy if exists "Members update" on public.team_members;
drop policy if exists "Members delete" on public.team_members;
create policy "Members select" on public.team_members for select to authenticated
  using (profile_id = auth.uid() or public.is_team_member(team_id));
create policy "Members insert" on public.team_members for insert to authenticated
  with check (public.is_team_admin(team_id)
              or (profile_id = auth.uid() and public.is_team_creator(team_id)));
create policy "Members update" on public.team_members for update to authenticated
  using (public.is_team_admin(team_id)) with check (public.is_team_admin(team_id));
create policy "Members delete" on public.team_members for delete to authenticated
  using (public.is_team_admin(team_id) or profile_id = auth.uid());
alter table public.team_members enable row level security;

-- ---------------------------------------------------------------------------
-- PROFILES : en plus de son propre profil, on voit le nom/email des personnes qui
-- partagent une équipe avec soi (page Membres & accès).
-- ---------------------------------------------------------------------------
drop policy if exists "Profils des coéquipiers" on public.profiles;
create policy "Profils des coéquipiers" on public.profiles for select to authenticated
  using (public.shares_team_with(id));

commit;

-- Vérification (doit afficher rls_active = true partout) :
select relname as table, relrowsecurity as rls_active
from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'
order by relname;
