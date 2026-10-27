// ============ PROPOSITIONS DE MATCH ENTRE CLUBS (C2) ============
// Chargé après reseau.js (utilise rsTeamId, rsTeam, rsAnnonces, AN_TYPES, AN_LIEUX, fmtJour,
// fmtHeure, creneauTxt, todayIso, renderReseauPage, sb, U, UP, esc, showToast, askConfirm,
// openModal, closeModal, loadMatches…).
// Base : supabase/2026-10-27-C2-propositions.sql — toutes les actions passent par
// proposition_creer / proposition_agir (machine à états, droits vérifiés par la base) :
// le coordinateur/CQ décide ; un entraîneur/délégué prépare une suggestion qu'il valide.
// Accord : match créé dans le calendrier des deux équipes.

const PR_STATUTS={a_valider:['pgr','À envoyer'],envoyee:['pb','Envoyée'],contre:['pb','Contre-proposition'],acceptee:['pg','✓ Acceptée'],refusee:['pr','Refusée'],annulee:['pgr','Annulée']};
const PR_ACTIONS={proposition:'a proposé',envoyer:'a envoyé la proposition',contre:'a fait une contre-proposition',accepter:'a accepté',refuser:'a refusé',annuler:'a annulé'};
const PR_SUGG={accepter:'accepter',refuser:'refuser',contre:'contre-proposer'};
let prListe=[],prOuverte=null,prCompteT=null;
const prAFaire=p=>p.decide?(p.a_moi||!!p.suggestion):(p.a_moi&&!p.suggestion);
const prLieuTxt=(lieu,cote)=>lieu===cote?'🏠 Chez nous':'✈️ Chez eux';
const prQuand=p=>`${fmtJour(p.jour)}${p.heure?' · '+fmtHeure(p.heure):''}`;

// ------------------------------------------------------------ PASTILLE (onglet + menu)
async function prMajCompte(){
  if(!U)return;
  const{data,error}=await sb.rpc('mes_propositions');
  if(error)return;   // SQL C2 pas installé
  prListe=data||[];
  const n=prListe.filter(prAFaire).length;
  const b=document.getElementById('umenu-prop-badge');if(b){b.textContent=n;b.style.display=n?'':'none';}
  return n;
}
const prLoadApp=loadApp;
loadApp=async function(user){await prLoadApp(user);prMajCompte();clearInterval(prCompteT);
  prCompteT=setInterval(()=>{if(document.visibilityState==='visible')prMajCompte();},60000);};
if(U)prMajCompte();

// ------------------------------------------------------------ PROPOSER (depuis une annonce)
function prOuvrirForm(annonceId){
  const a=rsAnnonces[annonceId],T=rsTeam(rsTeamId);if(!a||!T)return;
  const auj=todayIso(),cr=a.creneaux.filter(c=>c.jour>=auj&&c.statut==='libre');
  const lieuDef=a.lieu==='domicile'?'annonceur':a.lieu==='exterieur'?'proposant':'annonceur';
  document.getElementById('prop-body').innerHTML=`
    <div class="mt">Proposer un match</div>
    <div class="rs-line" style="margin-bottom:10px">${esc(T.nom)} → <b>${esc(a.club_nom)}</b> · ${esc(a.equipe)} (${esc(AN_TYPES[a.type]||a.type)})</div>
    ${cr.length?`<label class="fl">Créneaux proposés par ${esc(a.club_nom)}</label><div class="rs-chips pr-cr">${cr.map(c=>`<span onclick="prChoisirCreneau('${c.jour}','${fmtHeure(c.debut)}',this)">${esc(creneauTxt(c))}</span>`).join('')}</div>`:''}
    <div class="frow">
      <div class="fg"><label class="fl">Date</label><input class="fi" type="date" id="pr-jour" min="${auj}" value="${cr[0]?.jour||''}"></div>
      <div class="fg"><label class="fl">Heure</label><input class="fi" type="time" id="pr-heure" value="${fmtHeure(cr[0]?.debut)||'10:00'}"></div>
    </div>
    <div class="fg"><label class="fl">Où ?</label><select class="sel" id="pr-lieu">
      <option value="annonceur" ${lieuDef==='annonceur'?'selected':''}>✈️ Chez ${esc(a.club_nom)}</option>
      <option value="proposant" ${lieuDef==='proposant'?'selected':''}>🏠 Chez nous (${esc(T.clubs?.nom||T.nom)})</option></select></div>
    <div class="fg"><label class="fl">Message <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><textarea class="fi" id="pr-msg" rows="3" maxlength="1000" placeholder="ex : terrain synthétique, goûter après le match…"></textarea></div>
    ${isClubStaff(T.club_id)?'':'<div class="acc-help">Tu es entraîneur ou délégué : la proposition sera <b>envoyée par ton coordinateur ou ton CQ</b> après sa validation.</div>'}
    <div class="mfoot"><button class="bcan" onclick="closeModal('modal-prop')">Annuler</button>
      <button class="bp" id="pr-ok" onclick="prEnvoyerForm('${a.id}')">${isClubStaff(T.club_id)?'Envoyer':'Préparer'}</button></div>`;
  openModal('modal-prop');
}
function prChoisirCreneau(jour,heure,el){
  document.getElementById('pr-jour').value=jour;if(heure)document.getElementById('pr-heure').value=heure;
  el.parentElement.querySelectorAll('span').forEach(s=>s.classList.toggle('on',s===el));
}
async function prEnvoyerForm(annonceId){
  const jour=document.getElementById('pr-jour').value,heure=document.getElementById('pr-heure').value||null;
  if(!jour)return showToast('Choisis une date','err');
  const btn=document.getElementById('pr-ok');btn.disabled=true;
  const{error}=await sb.rpc('proposition_creer',{p_annonce:annonceId,p_team:rsTeamId,p_jour:jour,p_heure:heure,
    p_lieu:document.getElementById('pr-lieu').value,p_message:document.getElementById('pr-msg').value.trim()||null});
  btn.disabled=false;
  if(error)return showToast(error.message.replace(/^.*?:\s*/,''),'err');
  closeModal('modal-prop');
  showToast(isClubStaff(rsTeam(rsTeamId)?.club_id)?'🤝 Proposition envoyée':'Proposition préparée : ton coordinateur doit l\'envoyer','ok');
  await prMajCompte();rsTab='propositions';renderReseauPage();
}

// ------------------------------------------------------------ ONGLET « PROPOSITIONS »
async function prRenderListe(){
  const body=document.getElementById('rs-body');
  body.innerHTML='<div class="spin"></div>';
  const n=await prMajCompte();
  if(n===undefined){body.innerHTML='<div class="empty"><div class="empty-i">🤝</div><div class="empty-t">Propositions bientôt disponibles</div></div>';return;}
  const carte=p=>{const [cl,lbl]=PR_STATUTS[p.statut]||['pgr',p.statut];
    const autreClub=p.cote==='proposant'?p.club_annonceur:p.club_proposant,autreEq=p.cote==='proposant'?p.equipe_annonceur:p.equipe_proposante;
    const monEq=p.cote==='proposant'?p.equipe_proposante:p.equipe_annonceur;
    const todo=prAFaire(p);
    return `<div class="card rs-card pr-card${todo?' todo':''}" onclick="prOuvrir('${p.id}')">
      <div class="rs-top"><div style="flex:1;min-width:0"><div class="rs-club">${p.cote==='proposant'?'Envoyée à':'Reçue de'} ${esc(autreClub)}</div>
        <div class="rs-sub">${esc(autreEq)} ↔ ${esc(monEq)} · ${esc(AN_TYPES[p.annonce_type]||'')}</div></div><span class="pill ${cl}">${lbl}</span></div>
      <div class="rs-line">📅 ${esc(prQuand(p))} · ${prLieuTxt(p.lieu,p.cote)}</div>
      ${todo?`<div class="pr-todo">${p.suggestion&&p.decide?'💡 Suggestion à valider':p.statut==='a_valider'?(p.decide?'➤ À envoyer':'⏳ En attente de ton coordinateur'):'👉 À vous de répondre'}</div>`:''}
    </div>`;};
  const enCours=prListe.filter(p=>['a_valider','envoyee','contre'].includes(p.statut)),finies=prListe.filter(p=>!enCours.includes(p));
  body.innerHTML=(prListe.length?'':`<div class="empty"><div class="empty-i">🤝</div><div class="empty-t">Aucune proposition</div><div class="empty-s">Ouvre une annonce et touche « Proposer un match ».</div></div>`)+
    (enCours.length?`<div class="tb-sec-t">En cours</div>`+enCours.map(carte).join(''):'')+
    (finies.length?`<div class="tb-sec-t" style="margin-top:14px">Terminées</div>`+finies.slice(0,20).map(carte).join(''):'');
}
async function prOuvrir(id){
  prOuverte=prListe.find(p=>p.id===id);if(!prOuverte)return;
  document.getElementById('prop-body').innerHTML='<div class="spin"></div>';openModal('modal-prop');
  const [t,c]=await Promise.all([
    sb.from('proposition_tours').select('*').eq('proposition_id',id).order('created_at'),
    sb.rpc('proposition_contacts',{p_id:id})]);
  prRenderDetail(t.data||[],c.data||[]);
}
function prRenderDetail(tours,contacts){
  const p=prOuverte,[cl,lbl]=PR_STATUTS[p.statut]||['pgr',p.statut];
  const autreClub=p.cote==='proposant'?p.club_annonceur:p.club_proposant;
  const nous=c=>c===p.cote;
  const sugg=tours.filter(t=>t.en_attente).at(-1);
  const hist=tours.filter(t=>!t.en_attente&&!t.ecartee);
  const tourTxt=t=>`<div class="pr-tour${nous(t.cote)?' nous':''}"><div class="pr-tq"><b>${esc(t.auteur_nom||'?')}</b> (${nous(t.cote)?'nous':esc(autreClub)}) ${PR_ACTIONS[t.action]||t.action}
      ${t.jour&&['proposition','contre'].includes(t.action)?` : ${esc(prQuand(t))} · ${prLieuTxt(t.lieu,p.cote)}`:''}</div>
      ${t.message?`<div class="pr-tm">${esc(t.message)}</div>`:''}<div class="pr-td">${new Date(t.created_at).toLocaleString('fr-BE',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}</div></div>`;
  const enCours=['a_valider','envoyee','contre'].includes(p.statut);
  let actions='';
  if(enCours){
    if(sugg&&p.decide)actions+=`<div class="pr-sugg">💡 <b>${esc(sugg.auteur_nom||'')}</b> propose de <b>${PR_SUGG[sugg.action]||sugg.action}</b>${sugg.jour?` : ${esc(prQuand(sugg))} · ${prLieuTxt(sugg.lieu,p.cote)}`:''}${sugg.message?`<div class="pr-tm">${esc(sugg.message)}</div>`:''}
      <div class="rs-acts"><button class="bp rs-act" onclick="prAgir('valider_suggestion')">✓ Valider</button><button class="bsec" onclick="prAgir('ecarter_suggestion')">Écarter</button></div></div>`;
    else if(sugg)actions+=`<div class="pr-sugg">⏳ Ta suggestion (${PR_SUGG[sugg.action]||sugg.action}) attend la validation de ton coordinateur.</div>`;
    if(p.statut==='a_valider'&&p.cote==='proposant')
      actions+=`<div class="rs-acts">${p.decide?`<button class="bp rs-act" onclick="prAgir('envoyer')">➤ Envoyer à ${esc(autreClub)}</button>`:'<div class="rs-line">⏳ En attente de ton coordinateur ou CQ.</div>'}<button class="bred" onclick="prAgir('annuler')">Annuler</button></div>`;
    else if(p.a_moi){
      const pre=p.decide?'':'Suggérer : ';
      actions+=`<div class="rs-acts"><button class="bp rs-act" onclick="prAgir('accepter')">${pre}✓ Accepter</button>
        <button class="bsec" onclick="prFormContre()">${pre}↔ Autre date</button><button class="bred" onclick="prAgir('refuser')">${pre}Refuser</button></div>
        <div id="pr-contre"></div>`;
    }else actions+=`<div class="rs-line">⏳ En attente de la réponse de ${esc(autreClub)}.</div>`;
    if(p.cote==='proposant'&&p.statut!=='a_valider'&&p.decide)actions+=`<button class="bsec" style="margin-top:6px;font-size:12px" onclick="prAgir('annuler')">Annuler la proposition</button>`;
  }else if(p.statut==='acceptee')actions=`<div class="rs-ok">✓ Match ajouté au calendrier de l'équipe (onglet Matchs).</div>`;
  document.getElementById('prop-body').innerHTML=`
    <div class="mt">${p.cote==='proposant'?'Proposition à':'Proposition de'} ${esc(autreClub)}</div>
    <div class="pr-head"><span class="pill ${cl}">${lbl}</span><span>📅 ${esc(prQuand(p))}</span><span>${prLieuTxt(p.lieu,p.cote)}</span></div>
    ${actions}
    ${contacts.length?`<div class="tb-sec-t" style="margin-top:14px">Contacts ${esc(autreClub)}</div>${contacts.map(c=>`<div class="pr-ct"><div style="flex:1;min-width:0"><b>${esc(c.nom)}</b> <span class="rs-sub">· ${c.role==='cq'?'CQ':'Coordinateur'}</span></div>
      ${c.telephone?`<a class="bsec pr-ctb" href="tel:${esc(c.telephone.replace(/[^+\d]/g,''))}">📞</a><a class="bsec pr-ctb" href="https://wa.me/${esc(c.telephone.replace(/[^\d]/g,'').replace(/^0/,'32'))}" target="_blank" rel="noopener">💬</a>`:''}
      ${c.email?`<a class="bsec pr-ctb" href="mailto:${esc(c.email)}">✉️</a>`:''}</div>`).join('')}`:''}
    ${UP&&!UP.telephone?`<div class="rs-line" style="margin-top:8px">💡 Ajoute ton téléphone dans <a href="#" onclick="event.preventDefault();closeModal('modal-prop');ouvrirProfil()">Mon profil</a> pour que l'autre club puisse t'appeler.</div>`:''}
    <div class="tb-sec-t" style="margin-top:14px">Historique</div>${hist.map(tourTxt).join('')}
    <div class="mfoot"><button class="bcan" onclick="closeModal('modal-prop')">Fermer</button></div>`;
}
function prFormContre(){
  const p=prOuverte;
  document.getElementById('pr-contre').innerHTML=`<div class="card" style="margin-top:8px">
    <div class="frow"><div class="fg"><label class="fl">Date</label><input class="fi" type="date" id="prc-jour" min="${todayIso()}" value="${p.jour}"></div>
      <div class="fg"><label class="fl">Heure</label><input class="fi" type="time" id="prc-heure" value="${fmtHeure(p.heure)||'10:00'}"></div></div>
    <div class="fg"><label class="fl">Où ?</label><select class="sel" id="prc-lieu"><option value="${p.cote}" ${p.lieu===p.cote?'selected':''}>🏠 Chez nous</option>
      <option value="${p.cote==='proposant'?'annonceur':'proposant'}" ${p.lieu!==p.cote?'selected':''}>✈️ Chez eux</option></select></div>
    <div class="fg"><label class="fl">Message</label><textarea class="fi" id="prc-msg" rows="2" maxlength="1000"></textarea></div>
    <button class="bp" onclick="prAgir('contre')">${p.decide?'Envoyer la contre-proposition':'Suggérer cette date'}</button></div>`;
}
async function prAgir(action){
  const p=prOuverte;if(!p)return;
  const conf={refuser:'Refuser cette proposition ?',annuler:'Annuler cette proposition ?',accepter:p.decide?'Accepter ? Le match sera ajouté au calendrier des deux équipes.':null}[action];
  if(conf&&!await askConfirm(conf))return;
  const args={p_id:p.id,p_action:action};
  if(action==='contre'){
    args.p_jour=document.getElementById('prc-jour').value;args.p_heure=document.getElementById('prc-heure').value||null;
    args.p_lieu=document.getElementById('prc-lieu').value;args.p_message=document.getElementById('prc-msg').value.trim()||null;
    if(!args.p_jour)return showToast('Choisis une date','err');
  }
  const{data,error}=await sb.rpc('proposition_agir',args);
  if(error)return showToast(error.message.replace(/^.*?:\s*/,''),'err');
  showToast({suggestion:'Suggestion envoyée à ton coordinateur',acceptee:'✓ Match ajouté au calendrier des deux équipes',refusee:'Proposition refusée',
    annulee:'Proposition annulée',envoyee:'Proposition envoyée',contre:'Contre-proposition envoyée',ecartee:'Suggestion écartée'}[data]||'OK','ok');
  if(data==='acceptee'&&typeof loadMatches==='function')loadMatches();
  await prMajCompte();
  prOuverte=prListe.find(x=>x.id===p.id);
  if(prOuverte)prOuvrir(p.id);else closeModal('modal-prop');
  if(rsTab==='propositions')prRenderListe();
}

// ------------------------------------------------------------ MON PROFIL (téléphone)
function ouvrirProfil(){
  document.getElementById('pf-prenom').value=UP?.prenom||'';document.getElementById('pf-nom').value=UP?.nom||'';
  document.getElementById('pf-tel').value=UP?.telephone||'';openModal('modal-profil');
}
async function enregistrerProfil(){
  const upd={prenom:document.getElementById('pf-prenom').value.trim(),nom:document.getElementById('pf-nom').value.trim(),
    telephone:document.getElementById('pf-tel').value.trim()||null};
  if(!upd.prenom||!upd.nom)return showToast('Prénom et nom requis','err');
  const{error}=await sb.from('profiles').update(upd).eq('id',U.id);
  if(error)return showToast(/telephone/i.test(error.message)?'Téléphone pas encore disponible':error.message,'err');
  Object.assign(UP||{},upd);renderNavUser();closeModal('modal-profil');showToast('Profil enregistré','ok');
}
