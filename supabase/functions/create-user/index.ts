// FootCoach — Edge Function "create-user"
// Crée un compte déjà confirmé (pas d'email de vérification) et lui donne accès à une
// équipe ; ou, avec action "reset_password", change le mot de passe d'un membre.
// Appelée depuis « Membres & accès » (sb.functions.invoke('create-user')).
// Sécurité : l'appelant doit être connecté ET admin de l'équipe visée (is_team_admin,
// vérifié avec SON jeton). La clé service_role n'existe que côté serveur, jamais dans l'app.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // 1. Qui appelle ? (avec le jeton de l'utilisateur connecté)
    const caller = createClient(url, anon, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: "Non connecté" }, 401);

    const body = await req.json();
    const admin = createClient(url, service);

    // ---- Action « reset_password » : nouveau mot de passe choisi par un admin ----
    // Autorisé si l'appelant est admin d'au moins une équipe de la personne, et que la
    // personne n'est pas admin d'une équipe dont l'appelant n'est pas admin (sinon un
    // admin pourrait prendre le compte d'un admin d'une autre équipe).
    if (body.action === "reset_password") {
      const target = String(body.profile_id ?? "");
      const password = String(body.password ?? "");
      if (!target || target === user.id) return json({ error: "Personne invalide" }, 400);
      if (password.length < 8) return json({ error: "Mot de passe : 8 caractères minimum" }, 400);
      const { data: tRows } = await admin.from("team_members").select("team_id, role").eq("profile_id", target);
      const { data: mine } = await admin.from("team_members").select("team_id").eq("profile_id", user.id).eq("role", "admin");
      type Row = { team_id: string; role?: string };
      const myAdmin = new Set(((mine ?? []) as Row[]).map((r: Row) => r.team_id));
      const shared = ((tRows ?? []) as Row[]).some((r: Row) => myAdmin.has(r.team_id));
      const adminElsewhere = ((tRows ?? []) as Row[]).some((r: Row) => r.role === "admin" && !myAdmin.has(r.team_id));
      if (!shared || adminElsewhere) return json({ error: "Tu ne peux pas réinitialiser le mot de passe de cette personne" }, 403);
      const { error } = await admin.auth.admin.updateUserById(target, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    // ---- Action par défaut : création d'un compte ----
    // 2. Données envoyées par l'app
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const prenom = String(body.prenom ?? "").trim();
    const nom = String(body.nom ?? "").trim();
    const team_id = String(body.team_id ?? "");
    const role = body.role === "admin" ? "admin" : "member";
    if (!email || !prenom || !nom || !team_id) return json({ error: "Prénom, nom, email et équipe sont obligatoires" }, 400);
    if (password.length < 8) return json({ error: "Mot de passe : 8 caractères minimum" }, 400);

    // 3. L'appelant est-il admin de cette équipe ?
    const { data: isAdmin, error: rpcErr } = await caller.rpc("is_team_admin", { t: team_id });
    if (rpcErr || !isAdmin) return json({ error: "Accès admin requis sur cette équipe" }, 403);

    // 4. Création du compte, déjà confirmé
    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { prenom, nom },
    });
    if (cErr) {
      const msg = /already|registered|exists/i.test(cErr.message)
        ? "Un compte existe déjà avec cet email : ajoute-le simplement sans créer de compte"
        : cErr.message;
      return json({ error: msg }, 400);
    }
    const id = created.user.id;

    // 5. Profil (au cas où aucun trigger ne le crée) + accès à l'équipe
    await admin.from("profiles").upsert({ id, prenom, nom, email });
    const { error: mErr } = await admin.from("team_members").insert({ team_id, profile_id: id, role });
    if (mErr) return json({ error: "Compte créé, mais accès à l'équipe non ajouté : " + mErr.message, id }, 500);

    return json({ id, email, prenom });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
