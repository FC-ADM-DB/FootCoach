// FootLink — Edge Function "notifier" (C3)
// Envoie les e-mails déposés par la base dans la file « notifications » (propositions de
// match, inscriptions aux tournois, messages entre clubs, convocations aux parents).
// Appelée par la base elle-même (pg_net, à chaque dépôt et toutes les 5 minutes) : elle
// ne reçoit aucune donnée et ne renvoie que des compteurs, donc l'appeler ne fait que
// vider la file → déployée SANS vérification du jeton (« Verify JWT » décoché).
// Secrets (Edge Functions → Secrets) :
//   SMTP_HOST / SMTP_PORT  serveur d'envoi (OVH : ssl0.ovh.net / 465 ; port 465 obligatoire,
//                          Supabase bloque le 587)
//   SMTP_USER              adresse d'envoi complète (notifications@footlink.be)
//   SMTP_PASSWORD          mot de passe de cette adresse
//   (anciens secrets GMAIL_USER / GMAIL_APP_PASSWORD encore acceptés, serveur Gmail)
//   APP_URL                adresse de l'app dans le pied des e-mails
//   NOTIF_REDIRECT         (facultatif, projet de test) : tout envoyer à cette adresse
// Sans mot de passe : mode simulation (rien n'est envoyé, file marquée « simule »).
// Les adresses fictives des données de test / démo ne reçoivent jamais rien.
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const FICTIVES = /@(test|demo)\.footcoach$/i;
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

Deno.serve(async () => {
  try { return await vider(); }
  catch (e) { return json({ error: String((e as Error)?.message ?? e) }, 500); }
});

async function vider(): Promise<Response> {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } });
  // Adresse de footlink.be (OVH) ; à défaut, l'ancien envoi par Gmail
  const smtpUser = Deno.env.get("SMTP_USER") ?? "";
  const user = smtpUser || (Deno.env.get("GMAIL_USER") ?? "");
  const pass = smtpUser ? (Deno.env.get("SMTP_PASSWORD") ?? "") : (Deno.env.get("GMAIL_APP_PASSWORD") ?? "");
  const host = smtpUser ? (Deno.env.get("SMTP_HOST") ?? "ssl0.ovh.net") : "smtp.gmail.com";
  const port = Number(Deno.env.get("SMTP_PORT") ?? "465");
  const appUrl = Deno.env.get("APP_URL") ?? "https://footlink.be";
  const redirect = Deno.env.get("NOTIF_REDIRECT") ?? "";

  const { data: lot, error } = await db.rpc("notif_reserver", { p_max: 40 });
  if (error) return json({ error: error.message }, 500);
  if (!lot?.length) return json({ envoyes: 0 });

  const smtp = pass && user ? new SMTPClient({
    connection: { hostname: host, port, tls: true, auth: { username: user, password: pass } },
  }) : null;
  const res = { envoyes: 0, simules: 0, echecs: 0 };
  for (const n of lot as { id: string; email: string; prenom: string; titre: string; texte: string }[]) {
    // Destinataire réel, redirection (test) ou simulation
    const vers = redirect || n.email;
    if (!smtp || !vers || (!redirect && FICTIVES.test(n.email))) {
      await db.rpc("notif_terminer", { p_id: n.id, p_statut: "simule" });
      res.simules++;
      continue;
    }
    const texte = `Bonjour ${n.prenom ?? ""},\n\n${n.texte}\n\nOuvrir FootLink : ${appUrl}\n\n—\n` +
      `Tu reçois cet e-mail car tu fais partie de l'encadrement d'une équipe ou d'un club sur FootLink ` +
      `(ou tu es parent d'un joueur). Pour ne plus recevoir d'e-mails : FootLink → Mon profil → décocher « Recevoir les e-mails ».` +
      (redirect ? `\n\n[TEST — destinataire réel : ${n.email}]` : "");
    const html = `<div style="font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:#1c1a17;max-width:560px">` +
      `<p>Bonjour ${esc(n.prenom ?? "")},</p><p>${esc(n.texte).replace(/\n/g, "<br>")}</p>` +
      `<p><a href="${esc(appUrl)}" style="display:inline-block;background:#00d68f;color:#0a1628;padding:10px 16px;border-radius:8px;text-decoration:none;font-weight:bold">Ouvrir FootLink</a></p>` +
      `<p style="font-size:12px;color:#6b665a">Pour ne plus recevoir d'e-mails : FootLink → Mon profil → décocher « Recevoir les e-mails ».` +
      (redirect ? `<br>[TEST — destinataire réel : ${esc(n.email)}]` : "") + `</p></div>`;
    try {
      await smtp.send({ from: `FootLink <${user}>`, to: vers, subject: `FootLink · ${n.titre}`, content: texte, html });
      await db.rpc("notif_terminer", { p_id: n.id, p_statut: "envoye" });
      res.envoyes++;
    } catch (e) {
      await db.rpc("notif_terminer", { p_id: n.id, p_statut: "echec", p_erreur: String(e?.message ?? e) });
      res.echecs++;
    }
  }
  // Une connexion refusée (mot de passe, serveur) fait aussi échouer la fermeture : sans ce
  // try, la fonction plantait (« Internal Server Error ») au lieu de rendre son bilan.
  try { if (smtp) await smtp.close(); } catch (_) { /* déjà fermée */ }
  return json(res);
}
