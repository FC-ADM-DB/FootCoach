// ============ PROPOSITIONS DE MATCH ENTRE CLUBS (C2) ============
// Chargé après reseau.js (utilise rsTeamId, rsTeam, rsAnnonces, AN_TYPES, AN_LIEUX, fmtJour,
// fmtHeure, creneauTxt, todayIso, renderReseauPage, sb, U, UP, esc, showToast, askConfirm,
// openModal, closeModal, loadMatches…).
// Base : supabase/2026-10-27-C2-propositions.sql — toutes les actions passent par
// proposition_creer (sur une annonce) / proposition_directe (à une équipe choisie, sans
// annonce) / proposition_agir (machine à états, droits vérifiés par la base) :
// le coordinateur/CQ décide ; un entraîneur/délégué prépare une suggestion qu'il valide.
// Accord : match créé dans le calendrier des deux équipes.
// Communication entre clubs : d'abord par MESSAGE dans l'application (proposition_message,
// non-lus par proposition) ; email / téléphone seulement sur demande (« Afficher les coordonnées »).

const PR_STATUTS={a_valider:['pgr','À envoyer'],envoyee:['pb','Envoyée'],contre:['pb','Contre-proposition'],acceptee:['pg','✓ Acceptée'],refusee:['pr','Refusée'],annulee:['pgr','Annulée']};
const PR_ACTIONS={message:'',proposition:'a proposé',envoyer:'a envoyé la proposition',contre:'a fait une contre-proposition',accepter:'a accepté',refuser:'a refusé',annuler:'a annulé'};
// Statut affiché selon le côté : « Envoyée » sur une proposition REÇUE prêtait à confusion
function prStatut(p){
  if(p.statut==='envoyee')return p.cote==='annonceur'?['pb','Reçue']:['pb','Envoyée'];
  if(p.statut==='contre')return p.cote==='proposant'?['pb','Contre-proposition reçue']:['pb','Contre-proposition envoyée'];
  return PR_STATUTS[p.statut]||['pgr',p.statut];
}
let prChangerSugg=false;   // l'entraîneur veut modifier sa suggestion en attente
const PR_SUGG={accepter:'accepter',refuser:'refuser',contre:'contre-proposer'};
let prListe=[],prOuverte=null,prCompteT=null,prDetailT=null,prCoordVisibles=false;
const prAFaire=p=>(p.non_lus||0)>0||(p.decide?(p.a_moi||!!p.suggestion):(p.a_moi&&!p.suggestion));
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
  // Accueil : « Trouver un match » = propositions où c'est à nous d'agir (ou messages non lus) ;
  // « Calendrier » = propositions en cours (à voir dans la semaine)
  const hb=document.getElementById('home-prop-badge');if(hb){hb.textContent=n>99?'99+':n;hb.style.display=n?'':'none';}
  const nc=prListe.filter(x=>['a_valider','envoyee','contre'].includes(x.statut)&&x.jour>=todayIso()).length;
  const cb=document.getElementById('home-cal-badge');if(cb){cb.textContent=nc>99?'99+':nc;cb.style.display=nc?'':'none';}
  return n;
}
const prLoadApp=loadApp;
loadApp=async function(user){await prLoadApp(user);prMajCompte();clearInterval(prCompteT);
  prCompteT=setInterval(()=>{if(document.visibilityState==='visible')prMajCompte();},60000);};
if(U)prMajCompte();
const prGoPage=goPage;
goPage=function(name){prGoPage(name);if(name==='home')prMajCompte();};

// ------------------------------------------------------------ PROPOSER (depuis une annonce)
let prEquipeForm=null;   // équipe qui propose
function prOuvrirForm(annonceId){
  const a=rsAnnonces[annonceId];if(!a)return;
  // « Toutes les équipes » : on choisit l'équipe (par défaut la première compatible)
  const choix=rsTous()?rsEquipesClub():null;
  const T=choix?(a.compatibles?.[0]||choix[0]):rsTeam(rsTeamId);if(!T)return;
  prEquipeForm=T.id;
  const auj=todayIso(),cr=a.creneaux.filter(c=>c.jour>=auj&&c.statut==='libre');
  const lieuDef=a.lieu==='domicile'?'annonceur':a.lieu==='exterieur'?'proposant':'annonceur';
  document.getElementById('prop-body').innerHTML=`
    <div class="mt">Proposer un match</div>
    ${choix?`<div class="fg"><label class="fl">Notre équipe</label><select class="sel" onchange="prEquipeForm=this.value">${choix.map(t=>`<option value="${t.id}" ${t.id===T.id?'selected':''}>${esc(t.nom)} (${esc(t.categorie)})${a.compatibles?.includes(t)?' ✓':''}</option>`).join('')}</select></div>`:''}
    <div class="rs-line" style="margin-bottom:10px">${choix?'':esc(T.nom)+' '}→ <b>${esc(a.club_nom)}</b> · ${esc(a.equipe)} (${esc(AN_TYPES[a.type]||a.type)})</div>
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
  const{error}=await sb.rpc('proposition_creer',{p_annonce:annonceId,p_team:prEquipeForm,p_jour:jour,p_heure:heure,
    p_lieu:document.getElementById('pr-lieu').value,p_message:document.getElementById('pr-msg').value.trim()||null});
  btn.disabled=false;
  if(error)return showToast(error.message.replace(/^.*?:\s*/,''),'err');
  closeModal('modal-prop');
  showToast(isClubStaff(rsTeam(prEquipeForm)?.club_id)?'🤝 Proposition envoyée':'Proposition préparée : ton coordinateur doit l\'envoyer','ok');
  await prMajCompte();rsTab='propositions';renderReseauPage();
}

// ------------------------------------------------------------ PROPOSER DIRECTEMENT (sans annonce)
// preset : {team_id, jour, heure, depuisCal} (calendrier du club) ; l'adversaire est choisi
// parmi les équipes des autres clubs vérifiés (equipes_reseau : nom, catégorie, club).
let prDirect={team:null,cible:null,toutesCat:false,depuisCal:false},prEquipes=null;
async function prOuvrirDirect(preset={}){
  const st=rsStaffTeams();if(!st.length)return showToast('Il faut encadrer une équipe d\'un club','err');
  const T=rsTeam(preset.team_id||rsTeamId)||st[0];
  prDirect={team:T.id,cible:null,toutesCat:false,depuisCal:!!preset.depuisCal};
  const auj=todayIso();
  document.getElementById('prop-body').innerHTML=`
    <div class="mt">Proposer un match</div>
    <div class="fg"><label class="fl">Notre équipe</label><select class="sel" id="prd-team" onchange="prDirect.team=this.value;prDirect.cible=null;prDirListe()">${st.map(t=>`<option value="${t.id}" ${t.id===T.id?'selected':''}>${esc(t.nom)} (${esc(t.categorie)})</option>`).join('')}</select></div>
    <div class="fg"><label class="fl">Adversaire</label>
      <input class="fi" type="search" id="prd-q" placeholder="🔎 Club ou équipe…" oninput="prDirListe()">
      <label class="tm-new-toggle" style="margin:4px 0 0"><input type="checkbox" onchange="prDirect.toutesCat=this.checked;prDirListe()"> Toutes les catégories</label>
      <div class="prd-liste" id="prd-liste"><div class="spin"></div></div></div>
    <div class="frow">
      <div class="fg"><label class="fl">Date</label><input class="fi" type="date" id="pr-jour" min="${auj}" value="${esc(preset.jour||'')}"></div>
      <div class="fg"><label class="fl">Heure</label><input class="fi" type="time" id="pr-heure" value="${esc(preset.heure||'10:00')}"></div>
    </div>
    <div class="fg"><label class="fl">Où ?</label><select class="sel" id="pr-lieu">
      <option value="proposant">🏠 Chez nous</option><option value="annonceur">✈️ Chez eux</option></select></div>
    <div class="fg"><label class="fl">Message <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><textarea class="fi" id="pr-msg" rows="3" maxlength="1000" placeholder="ex : match amical, terrain synthétique…"></textarea></div>
    <div id="prd-aide"></div>
    <div class="mfoot"><button class="bcan" onclick="closeModal('modal-prop')">Annuler</button>
      <button class="bp" id="pr-ok" onclick="prEnvoyerDirect()">Envoyer</button></div>`;
  openModal('modal-prop');
  if(!prEquipes){const{data,error}=await sb.rpc('equipes_reseau');prEquipes=error?[]:(data||[]);}
  prDirListe();
}
function prDirListe(){
  const el=document.getElementById('prd-liste');if(!el||!prEquipes)return;
  const T=rsTeam(prDirect.team),q=(document.getElementById('prd-q')?.value||'').trim().toLowerCase();
  const club=isClubStaff(T?.club_id);
  document.getElementById('prd-aide').innerHTML=club?'':'<div class="acc-help">Tu es entraîneur ou délégué : la proposition sera <b>envoyée par ton coordinateur ou ton CQ</b> après sa validation.</div>';
  document.getElementById('pr-ok').textContent=club?'Envoyer':'Préparer';
  // Équipes des autres clubs (jamais le mien), même catégorie par défaut
  const l=prEquipes.filter(e=>!teams.some(t=>t.id===e.team_id&&t.club_id===T?.club_id))
    .filter(e=>prDirect.toutesCat||!T?.categorie||e.categorie===T.categorie)
    .filter(e=>!q||(e.club_nom+' '+e.equipe+' '+e.categorie).toLowerCase().includes(q))
    .sort((a,b)=>a.club_nom.localeCompare(b.club_nom)||a.equipe.localeCompare(b.equipe));
  el.innerHTML=l.length?l.slice(0,60).map(e=>`<button type="button" class="prd-eq${e.team_id===prDirect.cible?' on':''}" onclick="prDirect.cible='${e.team_id}';prDirListe()"><b>${esc(e.club_nom)}</b> · ${esc(e.equipe)} <span>${esc(rsCat(e.equipe,e.categorie).slice(3))}</span></button>`).join('')
    :`<div class="rs-line" style="padding:8px">${prEquipes.length?'Aucune équipe trouvée'+(prDirect.toutesCat?'':' dans la catégorie '+esc(T?.categorie||'')):'Aucune autre équipe dans le réseau pour l\'instant (clubs vérifiés).'}</div>`;
}
async function prEnvoyerDirect(){
  const jour=document.getElementById('pr-jour').value,heure=document.getElementById('pr-heure').value||null;
  if(!prDirect.cible)return showToast('Choisis l\'équipe adverse','err');
  if(!jour)return showToast('Choisis une date','err');
  const btn=document.getElementById('pr-ok');btn.disabled=true;
  const{error}=await sb.rpc('proposition_directe',{p_team:prDirect.team,p_cible:prDirect.cible,p_jour:jour,p_heure:heure,
    p_lieu:document.getElementById('pr-lieu').value,p_message:document.getElementById('pr-msg').value.trim()||null});
  btn.disabled=false;
  if(error)return showToast(/proposition_directe|function/i.test(error.message||'')?'Fonction pas encore disponible':error.message.replace(/^.*?:\s*/,''),'err');
  closeModal('modal-prop');
  showToast(isClubStaff(rsTeam(prDirect.team)?.club_id)?'🤝 Proposition envoyée':'Proposition préparée : ton coordinateur doit l\'envoyer','ok');
  await prMajCompte();
  if(prDirect.depuisCal&&typeof renderCalendrier==='function')renderCalendrier();
  else{rsTab='propositions';goPage('reseau');}
}

// ------------------------------------------------------------ ONGLET « PROPOSITIONS »
async function prRenderListe(){
  const body=document.getElementById('rs-body');
  body.innerHTML='<div class="spin"></div>';
  const n=await prMajCompte();
  if(n===undefined){body.innerHTML='<div class="empty"><div class="empty-i">🤝</div><div class="empty-t">Propositions bientôt disponibles</div></div>';return;}
  const carte=p=>{const [cl,lbl]=prStatut(p);
    const autreClub=p.cote==='proposant'?p.club_annonceur:p.club_proposant,autreEq=p.cote==='proposant'?p.equipe_annonceur:p.equipe_proposante;
    const monEq=p.cote==='proposant'?p.equipe_proposante:p.equipe_annonceur;
    const todo=prAFaire(p);
    return `<div class="card rs-card pr-card${todo?' todo':''}" onclick="prOuvrir('${p.id}')">
      <div class="rs-top"><div style="flex:1;min-width:0"><div class="rs-club">${p.cote==='proposant'?'Envoyée à':'Reçue de'} ${esc(autreClub)}</div>
        <div class="rs-sub">${esc(autreEq)} ↔ ${esc(monEq)} · ${p.annonce_id?esc(AN_TYPES[p.annonce_type]||''):'proposition directe'}</div></div><span class="pill ${cl}">${lbl}</span></div>
      <div class="rs-line">📅 ${esc(prQuand(p))} · ${prLieuTxt(p.lieu,p.cote)}</div>
      ${p.non_lus?`<div class="pr-msg-nb">💬 ${p.non_lus} nouveau${p.non_lus>1?'x':''} message${p.non_lus>1?'s':''}</div>`:''}
      ${todo&&!(p.non_lus&&!(p.decide?(p.a_moi||p.suggestion):(p.a_moi&&!p.suggestion)))?`<div class="pr-todo">${p.suggestion&&p.decide?'💡 Suggestion à valider':p.statut==='a_valider'?(p.decide?'➤ À envoyer':'⏳ En attente de ton coordinateur'):'👉 À vous de répondre'}</div>`:''}
    </div>`;};
  const enCours=prListe.filter(p=>['a_valider','envoyee','contre'].includes(p.statut)),finies=prListe.filter(p=>!enCours.includes(p));
  body.innerHTML='<div class="rs-ligne pr-actions"><button class="bsec rs-mini" onclick="prOuvrirDirect()">🤝 Proposer un match</button>'+(myClubs.length?'<button class="bsec rs-mini" onclick="ouvrirCalendrier()">📅 Calendrier</button>':'')+'</div>'+(prListe.length?'':`<div class="empty"><div class="empty-i">🤝</div><div class="empty-t">Aucune proposition</div><div class="empty-s">Ouvre une annonce et touche « Proposer un match », ou propose directement à une équipe.</div></div>`)+
    (enCours.length?`<div class="tb-sec-t">En cours</div>`+enCours.map(carte).join(''):'')+
    (finies.length?`<div class="tb-sec-t" style="margin-top:14px">Terminées</div>`+finies.slice(0,20).map(carte).join(''):'');
}
async function prOuvrir(id,silencieux){
  prOuverte=prListe.find(p=>p.id===id);if(!prOuverte)return;
  if(!silencieux){prCoordVisibles=false;prChangerSugg=false;document.getElementById('prop-body').innerHTML='<div class="spin"></div>';openModal('modal-prop');}
  const saisie=document.getElementById('prm-texte')?.value||'';
  const [t,c]=await Promise.all([
    sb.from('proposition_tours').select('*').eq('proposition_id',id).order('created_at'),
    sb.rpc('proposition_contacts',{p_id:id})]);
  if(prOuverte?.id!==id)return;
  prRenderDetail(t.data||[],c.data||[]);
  if(prOuverte.decide&&typeof calJourClub==='function')calJourClub(prOuverte);   // planning du club ce jour-là
  const ta=document.getElementById('prm-texte');if(ta&&saisie)ta.value=saisie;
  const h=document.getElementById('pr-hist');if(h)h.scrollTop=h.scrollHeight;
  // Fiche ouverte = messages lus
  if(prOuverte.non_lus){await sb.rpc('proposition_lu',{p_id:id});prOuverte.non_lus=0;prMajCompte();}
  clearInterval(prDetailT);
  prDetailT=setInterval(async()=>{
    if(!document.getElementById('modal-prop')?.classList.contains('open')||prOuverte?.id!==id){clearInterval(prDetailT);prDetailT=null;return;}
    if(document.activeElement?.id==='prc-msg'||document.getElementById('pr-contre')?.innerHTML)return;   // contre-proposition en cours de saisie
    await prMajCompte();prOuverte=prListe.find(p=>p.id===id)||prOuverte;
    if(prOuverte.non_lus)prOuvrir(id,true);
  },10000);
}
async function prEnvoyerMessage(){
  const p=prOuverte,ta=document.getElementById('prm-texte');if(!p||!ta)return;
  const texte=ta.value.trim();if(!texte)return;
  const btn=document.getElementById('prm-env');btn.disabled=true;
  const{error}=await sb.rpc('proposition_message',{p_id:p.id,p_texte:texte});
  btn.disabled=false;
  if(error)return showToast(error.message.replace(/^.*?:\s*/,''),'err');
  ta.value='';prOuvrir(p.id,true);
}
function prRenderDetail(tours,contacts){
  const p=prOuverte,[cl,lbl]=prStatut(p);
  const autreClub=p.cote==='proposant'?p.club_annonceur:p.club_proposant;
  const nous=c=>c===p.cote;
  const sugg=tours.filter(t=>t.en_attente).at(-1);
  const hist=tours.filter(t=>!t.en_attente&&!t.ecartee);
  const tourTxt=t=>t.action==='message'?`<div class="pr-bulle${nous(t.cote)?' nous':''}"><div class="pr-ba">${esc(t.auteur_nom||'?')} · ${nous(t.cote)?'nous':esc(autreClub)}</div>
      <div class="pr-bt">${esc(t.message||'')}</div><div class="pr-td">${new Date(t.created_at).toLocaleString('fr-BE',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}</div></div>`
    :`<div class="pr-tour${nous(t.cote)?' nous':''}"><div class="pr-tq"><b>${esc(t.auteur_nom||'?')}</b> (${nous(t.cote)?'nous':esc(autreClub)}) ${PR_ACTIONS[t.action]||t.action}
      ${t.jour&&['proposition','contre'].includes(t.action)?` : ${esc(prQuand(t))} · ${prLieuTxt(t.lieu,p.cote)}`:''}</div>
      ${t.message?`<div class="pr-tm">${esc(t.message)}</div>`:''}<div class="pr-td">${new Date(t.created_at).toLocaleString('fr-BE',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}</div></div>`;
  const enCours=['a_valider','envoyee','contre'].includes(p.statut);
  let actions='';
  if(enCours){
    if(sugg&&p.decide)actions+=`<div class="pr-sugg">💡 <b>${esc(sugg.auteur_nom||'')}</b> propose de <b>${PR_SUGG[sugg.action]||sugg.action}</b>${sugg.jour?` : ${esc(prQuand(sugg))} · ${prLieuTxt(sugg.lieu,p.cote)}`:''}${sugg.message?`<div class="pr-tm">${esc(sugg.message)}</div>`:''}
      <div class="rs-acts"><button class="bp rs-act" onclick="prAgir('valider_suggestion')">✓ Valider</button><button class="bsec" onclick="prAgir('ecarter_suggestion')">Écarter</button></div></div>`;
    else if(sugg)actions+=`<div class="pr-sugg">⏳ Ta suggestion (${PR_SUGG[sugg.action]||sugg.action}) attend la validation de ton coordinateur.
      ${prChangerSugg?'':`<div class="rs-acts"><button class="bsec" onclick="prChangerSugg=true;prOuvrir('${p.id}',true)">Changer ma suggestion</button><button class="bsec" onclick="prAgir('ecarter_suggestion')">Retirer</button></div>`}</div>`;
    if(p.statut==='a_valider'&&p.cote==='proposant')
      actions+=`<div class="rs-acts">${p.decide?`<button class="bp rs-act" onclick="prAgir('envoyer')">➤ Envoyer à ${esc(autreClub)}</button>`:'<div class="rs-line">⏳ En attente de ton coordinateur ou CQ.</div>'}<button class="bred" onclick="prAgir('annuler')">Annuler</button></div>`;
    else if(p.a_moi&&(!sugg||p.decide||prChangerSugg)){
      const pre=p.decide?'':'Suggérer : ';
      actions+=`<div class="rs-acts"><button class="bp rs-act" onclick="prAgir('accepter')">${pre}✓ Accepter</button>
        <button class="bsec" onclick="prFormContre()">${pre}↔ Autre date</button><button class="bred" onclick="prAgir('refuser')">${pre}Refuser</button></div>
        <div id="pr-contre"></div>`;
    }else if(!p.a_moi)actions+=`<div class="rs-line">⏳ En attente de la réponse de ${esc(autreClub)}.</div>`;
    if(p.cote==='proposant'&&p.statut!=='a_valider'&&p.decide)actions+=`<button class="bsec" style="margin-top:6px;font-size:12px" onclick="prAgir('annuler')">Annuler la proposition</button>`;
  }else if(p.statut==='acceptee')actions=`<div class="rs-ok">✓ Match ajouté au calendrier de l'équipe (onglet Matchs).</div>`;
  document.getElementById('prop-body').innerHTML=`
    <div class="mt">${p.cote==='proposant'?'Proposition à':'Proposition de'} ${esc(autreClub)}</div>
    <div class="pr-head"><span class="pill ${cl}">${lbl}</span><span>📅 ${esc(prQuand(p))}</span><span>${prLieuTxt(p.lieu,p.cote)}</span></div>
    ${p.decide&&enCours?'<div id="pr-jour-club"></div>':''}
    ${actions}
    <div class="tb-sec-t" style="margin-top:14px">Échanges avec ${esc(autreClub)}</div>
    <div class="pr-hist" id="pr-hist">${hist.map(tourTxt).join('')}</div>
    ${p.statut==='a_valider'?'<div class="rs-line">Les messages seront possibles une fois la proposition envoyée.</div>'
      :`<div class="msg-saisie"><textarea class="fi" id="prm-texte" rows="1" maxlength="1000" placeholder="Écrire à ${esc(autreClub)}…" oninput="this.style.height='auto';this.style.height=Math.min(this.scrollHeight,110)+'px'"></textarea>
      <button class="bp msg-env" id="prm-env" onclick="prEnvoyerMessage()" aria-label="Envoyer">➤</button></div>`}
    ${contacts.length?(prCoordVisibles?`<div class="tb-sec-t" style="margin-top:14px">Coordonnées ${esc(autreClub)}</div>${contacts.map(c=>`<div class="pr-ct"><div style="flex:1;min-width:0"><b>${esc(c.nom)}</b> <span class="rs-sub">· ${c.role==='cq'?'CQ':'Coordinateur'}</span></div>
      ${c.telephone?`<a class="bsec pr-ctb" href="tel:${esc(c.telephone.replace(/[^+\d]/g,''))}">📞</a><a class="bsec pr-ctb" href="https://wa.me/${esc(c.telephone.replace(/[^\d]/g,'').replace(/^0/,'32'))}" target="_blank" rel="noopener">💬</a>`:''}
      ${c.email?`<a class="bsec pr-ctb" href="mailto:${esc(c.email)}">✉️</a>`:''}</div>`).join('')}`
      :`<button class="bsec pr-coord" onclick="prCoordVisibles=true;prOuvrir('${p.id}',true)">📇 Afficher les coordonnées (téléphone, email)</button>`):''}
    ${prCoordVisibles&&UP&&!UP.telephone?`<div class="rs-line" style="margin-top:8px">💡 Ajoute ton téléphone dans <a href="#" onclick="event.preventDefault();closeModal('modal-prop');ouvrirProfil()">Mon profil</a> pour que l'autre club puisse t'appeler.</div>`:''}
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
  prChangerSugg=false;
  const{data,error}=await sb.rpc('proposition_agir',args);
  if(error)return showToast(error.message.replace(/^.*?:\s*/,''),'err');
  showToast({suggestion:'Suggestion envoyée à ton coordinateur',acceptee:'✓ Match ajouté au calendrier des deux équipes',refusee:'Proposition refusée',
    annulee:'Proposition annulée',envoyee:'Proposition envoyée',contre:'Contre-proposition envoyée',ecartee:p.decide?'Suggestion écartée':'Suggestion retirée'}[data]||'OK','ok');
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
