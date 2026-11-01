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
// Envoi SMTP écrit ici (TLS direct, AUTH LOGIN) : la bibliothèque denomailer plantait la
// fonction sans message quand le serveur refusait quelque chose (e-mail bloqué « en_cours »).
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const FICTIVES = /@(test|demo)\.footcoach$/i;
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const b64 = (s: string) => {
  const o = new TextEncoder().encode(s);
  let bin = "";
  for (const x of o) bin += String.fromCharCode(x);
  return btoa(bin);
};
const lignes76 = (s: string) => s.replace(/.{1,76}/g, "$&\r\n");

// ---- Petit client SMTP : une connexion par lot, une erreur claire à chaque étape ----
class Smtp {
  #c!: Deno.TlsConn;
  #tampon = "";
  async ouvrir(host: string, port: number, user: string, pass: string) {
    this.#c = await Deno.connectTls({ hostname: host, port });
    await this.#attendre(220, "accueil");
    await this.#cmd("EHLO footlink.be", 250, "EHLO");
    await this.#cmd("AUTH LOGIN", 334, "AUTH");
    await this.#cmd(b64(user), 334, "identifiant");
    await this.#cmd(b64(pass), 235, "mot de passe refusé");
  }
  async envoyer(from: string, to: string, sujet: string, texte: string, html: string) {
    await this.#cmd(`MAIL FROM:<${from}>`, 250, "MAIL FROM");
    await this.#cmd(`RCPT TO:<${to}>`, 250, "destinataire refusé");
    await this.#cmd("DATA", 354, "DATA");
    const sep = "fl" + crypto.randomUUID().replace(/-/g, "");
    const msg = [
      `From: FootLink <${from}>`, `To: <${to}>`,
      `Subject: =?UTF-8?B?${b64(sujet)}?=`,
      `Date: ${new Date().toUTCString()}`,
      `Message-ID: <${crypto.randomUUID()}@footlink.be>`,
      "MIME-Version: 1.0", `Content-Type: multipart/alternative; boundary="${sep}"`, "",
      `--${sep}`, "Content-Type: text/plain; charset=UTF-8", "Content-Transfer-Encoding: base64", "", lignes76(b64(texte)),
      `--${sep}`, "Content-Type: text/html; charset=UTF-8", "Content-Transfer-Encoding: base64", "", lignes76(b64(html)),
      `--${sep}--`, "",
    ].join("\r\n");
    await this.#ecrire(msg + "\r\n.\r\n");
    await this.#attendre(250, "message refusé");
  }
  async fermer() {
    try { await this.#ecrire("QUIT\r\n"); } catch (_) { /* déjà fermée */ }
    try { this.#c?.close(); } catch (_) { /* déjà fermée */ }
  }
  async #cmd(l: string, code: number, etape: string) { await this.#ecrire(l + "\r\n"); await this.#attendre(code, etape); }
  async #ecrire(s: string) {
    const o = new TextEncoder().encode(s);
    let n = 0;
    while (n < o.length) n += await this.#c.write(o.subarray(n));
  }
  // Réponse complète (lignes « 250-… » puis « 250 … »), avec délai maximum de 20 s
  async #attendre(code: number, etape: string) {
    const fin = Date.now() + 20000;
    const buf = new Uint8Array(4096);
    for (;;) {
      const m = this.#tampon.match(/(?:^|\r\n)(\d{3}) [^\r\n]*\r\n/);
      if (m) {
        const rep = this.#tampon.slice(0, m.index! + m[0].length);
        this.#tampon = this.#tampon.slice(rep.length);
        if (Number(m[1]) !== code) throw new Error(`${etape} : ${rep.trim().slice(0, 200)}`);
        return;
      }
      if (Date.now() > fin) throw new Error(`${etape} : pas de réponse du serveur`);
      const n = await Promise.race([this.#c.read(buf), new Promise<null>((r) => setTimeout(() => r(null), 20000))]);
      if (n === null) throw new Error(`${etape} : connexion fermée par le serveur`);
      this.#tampon += new TextDecoder().decode(buf.subarray(0, n));
    }
  }
}

Deno.serve(async () => {
  try { return await vider(); }
  catch (e) { return json({ error: String((e as Error)?.message ?? e) }, 500); }
});

async function vider(): Promise<Response> {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } });
  // Adresse de footlink.be (OVH) ; à défaut, l'ancien envoi par Gmail
  const smtpUser = (Deno.env.get("SMTP_USER") ?? "").trim();
  const user = smtpUser || (Deno.env.get("GMAIL_USER") ?? "").trim();
  const pass = smtpUser ? (Deno.env.get("SMTP_PASSWORD") ?? "") : (Deno.env.get("GMAIL_APP_PASSWORD") ?? "");
  const host = smtpUser ? (Deno.env.get("SMTP_HOST") ?? "ssl0.ovh.net").trim() : "smtp.gmail.com";
  const port = Number(Deno.env.get("SMTP_PORT") ?? "465");
  const appUrl = Deno.env.get("APP_URL") ?? "https://footlink.be";
  const redirect = Deno.env.get("NOTIF_REDIRECT") ?? "";

  const { data: lot, error } = await db.rpc("notif_reserver", { p_max: 40 });
  if (error) return json({ error: error.message }, 500);
  if (!lot?.length) return json({ envoyes: 0 });

  const res = { envoyes: 0, simules: 0, echecs: 0, erreur: "" };
  let smtp: Smtp | null = null;
  if (pass && user) {
    // Connexion refusée (mot de passe, serveur) : tout le lot est noté en échec (retenté plus tard)
    try { smtp = new Smtp(); await smtp.ouvrir(host, port, user, pass); }
    catch (e) { res.erreur = String((e as Error)?.message ?? e); await smtp?.fermer(); smtp = null; }
  }
  for (const n of lot as { id: string; email: string; prenom: string; titre: string; texte: string }[]) {
    // Destinataire réel, redirection (test) ou simulation
    const vers = redirect || n.email;
    if (res.erreur) {
      await db.rpc("notif_terminer", { p_id: n.id, p_statut: "echec", p_erreur: res.erreur });
      res.echecs++;
      continue;
    }
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
      await smtp.envoyer(user, vers, `FootLink · ${n.titre}`, texte.replace(/\n/g, "\r\n"), html);
      await db.rpc("notif_terminer", { p_id: n.id, p_statut: "envoye" });
      res.envoyes++;
    } catch (e) {
      await db.rpc("notif_terminer", { p_id: n.id, p_statut: "echec", p_erreur: String((e as Error)?.message ?? e) });
      res.echecs++;
      // Connexion cassée : on arrête ce lot (le reste repartira au prochain réveil)
      if (/connexion fermée|pas de réponse/.test(String(e))) { res.erreur = String((e as Error)?.message ?? e); }
    }
  }
  await smtp?.fermer();
  return json(res);
}
