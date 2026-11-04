// ============ CLUBS SANS COMPTE (C5) ============
// Chargé après demandes.js (utilise sb, U, teams, myClubs, isClubStaff, esc, showToast,
// openModal, closeModal, askConfirm, prOuvrirDirect, prRenderListe, prDirect, rsTeam,
// renderClubPage, createClub, clubVue, CT).
// 1. Proposer un match PAR E-MAIL à un club qui n'a pas FootLink (il répond sur reponse.html
//    sans compte) ; suivi dans « Trouver un match » → Propositions.
// 2. Inviter un club à rejoindre FootLink (lien ?rejoindre=… : compte + fiche du club
//    pré-remplie ; le club qui invite est prévenu quand c'est fait).
let imListe=[];
const IM_CLE='fc_rejoindre';
const IM_STATUT={a_valider:['pgr','À envoyer'],envoyee:['pb','Envoyée'],contre:['pa','Autre date proposée'],acceptee:['pg','✓ Match confirmé'],refusee:['pr','Refusée'],annulee:['pgr','Annulée']};
const imJour=d=>d?new Date(d+'T12:00').toLocaleDateString('fr-BE',{weekday:'short',day:'numeric',month:'short'}):'';
const imClub=()=>{const c=clubVue||CT?.club_id||myClubs[0]?.club_id;return isClubStaff(c)?c:null;};

document.body.insertAdjacentHTML('beforeend',`
<div class="mo" id="modal-ic"><div class="modal"><div class="mh"></div>
  <div class="mt">Inviter un club sur FootLink</div>
  <div class="rs-line" style="margin:-6px 0 12px">Le club reçoit un e-mail avec un lien pour créer son compte et la fiche de son club. Vous serez prévenu quand il aura rejoint FootLink.</div>
  <div class="fg"><label class="fl">E-mail du responsable du club</label><input class="fi" id="ic-email" type="email" maxlength="200" placeholder="ex. secretariat@club.be"></div>
  <div class="frow"><div class="fg"><label class="fl">Son nom <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><input class="fi" id="ic-nom" maxlength="100"></div>
    <div class="fg"><label class="fl">Nom du club <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><input class="fi" id="ic-club" maxlength="80"></div></div>
  <div class="fg"><label class="fl">Message <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><textarea class="fi" id="ic-msg" rows="2" maxlength="500" placeholder="ex. Pour organiser nos matchs amicaux plus facilement"></textarea></div>
  <div class="mfoot"><button class="bcan" onclick="closeModal('modal-ic')">Annuler</button><button class="bp" onclick="icEnvoyer()">Envoyer l'invitation</button></div>
</div></div>`);

// ---- 1. Proposition par e-mail : option dans « Proposer un match » ----
const imOuvrirDirect=prOuvrirDirect;
prOuvrirDirect=async function(preset){
  await imOuvrirDirect.apply(this,arguments);
  const liste=document.getElementById('prd-liste');if(!liste||document.getElementById('im-toggle'))return;
  const fg=liste.closest('.fg');
  fg.insertAdjacentHTML('beforebegin',`<label class="tm-new-toggle" style="margin:0 0 8px"><input type="checkbox" id="im-toggle" onchange="imBascule(this.checked)"> Le club n'est pas encore sur FootLink (proposition par e-mail)</label>`);
  fg.insertAdjacentHTML('afterend',`<div id="im-champs" style="display:none">
    <div class="frow"><div class="fg"><label class="fl">Club adverse</label><input class="fi" id="im-club" maxlength="80" placeholder="ex. RFC Exemple"></div>
      <div class="fg"><label class="fl">Équipe <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><input class="fi" id="im-eq" maxlength="60" placeholder="ex. U9"></div></div>
    <div class="frow"><div class="fg"><label class="fl">E-mail du contact</label><input class="fi" id="im-email" type="email" maxlength="200" placeholder="ex. coach@club.be"></div>
      <div class="fg"><label class="fl">Nom du contact <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><input class="fi" id="im-nom" maxlength="100"></div></div>
    <div class="acc-help">Le club reçoit un e-mail et répond en un clic (accepter, refuser ou autre date), sans créer de compte. S'il accepte, le match s'ajoute à votre calendrier.</div></div>`);
};
function imBascule(on){
  const fg=document.getElementById('prd-liste')?.closest('.fg');if(fg)fg.style.display=on?'none':'';
  document.getElementById('im-champs').style.display=on?'':'none';
  const ok=document.getElementById('pr-ok');if(ok)ok.onclick=on?imEnvoyer:prEnvoyerDirect;
}
async function imEnvoyer(){
  const v=id=>document.getElementById(id)?.value.trim()||'';
  const jour=v('pr-jour'),club=v('im-club'),email=v('im-email');
  if(!club)return showToast('Nom du club adverse ?','err');
  if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))return showToast('Adresse e-mail du contact invalide','err');
  if(!jour)return showToast('Choisis une date','err');
  // Lieu : « proposant » (chez nous) / « annonceur » (chez eux) dans la fenêtre des propositions
  const lieu=document.getElementById('pr-lieu').value==='proposant'?'nous':'eux';
  const btn=document.getElementById('pr-ok');btn.disabled=true;
  const{error}=await sb.rpc('invitation_match_creer',{p_team:prDirect.team,p_club_externe:club,p_equipe_externe:v('im-eq')||null,
    p_email:email,p_contact:v('im-nom')||null,p_jour:jour,p_heure:v('pr-heure')||null,p_lieu:lieu,p_message:v('pr-msg')||null});
  btn.disabled=false;
  if(error)return showToast(/function|schema cache/i.test(error.message)?'Fonction pas encore disponible':error.message.replace(/^.*?:\s*/,''),'err');
  closeModal('modal-prop');
  showToast(isClubStaff(rsTeam(prDirect.team)?.club_id)?'✉️ Proposition envoyée par e-mail':'Proposition préparée : ton coordinateur doit l\'envoyer','ok');
  rsTab='propositions';goPage('reseau');
}

// ---- Suivi dans l'onglet Propositions ----
async function imCharger(){const{data,error}=await sb.rpc('mes_invitations_match');imListe=error?null:(data||[]);return imListe;}
// Les réponses par e-mail / lien d'annonce « à décider » comptent dans les pastilles (menu, accueil, onglet) :
// sans ça, une réponse à une annonce partagée n'était signalée nulle part
const imAFaire=i=>i.decide&&(i.statut==='contre'||i.statut==='a_valider');
const imMajCompte=prMajCompte;
prMajCompte=async function(){
  const n=await imMajCompte.apply(this,arguments);
  if(n===undefined)return n;
  await imCharger();
  const t=n+(imListe||[]).filter(imAFaire).length;
  ['umenu-prop-badge','home-prop-badge'].forEach(id=>{const b=document.getElementById(id);if(b){b.textContent=t>99?'99+':t;b.style.display=t?'':'none';}});
  return t;
};
const imRenderListe=prRenderListe;
prRenderListe=async function(){
  await imRenderListe.apply(this,arguments);
  const body=document.getElementById('rs-body');if(!body)return;
  const act=body.querySelector('.pr-actions');
  if(act&&imClub()&&!document.getElementById('ic-btn'))act.insertAdjacentHTML('beforeend','<button class="bsec rs-mini" id="ic-btn" onclick="icOuvrir()">✉️ Inviter un club</button>');
  const l=await imCharger();if(!l||!l.length)return;
  const carte=i=>{
    // Réponse arrivée par le lien partagé d'une annonce : « à accepter » (pas une contre-proposition)
    const viaAnnonce=i.origine==='annonce';
    const[c,lb]=viaAnnonce&&i.statut==='contre'?['pa','📣 Réponse à l\'annonce']:(IM_STATUT[i.statut]||['pgr',i.statut]);
    const quand=`${imJour(i.jour)}${i.heure?' · '+i.heure:''} · ${i.lieu==='nous'?'🏠 chez nous':'✈️ chez eux'}`;
    let act='';
    if(i.statut==='a_valider'&&i.decide)act+=`<button class="badd" onclick="imAgir('${i.id}','envoyer')">➤ Envoyer</button>`;
    if(i.statut==='contre'&&i.decide)act+=`<button class="badd" onclick="imAgir('${i.id}','accepter_contre')">${viaAnnonce?'Accepter ce match':'Accepter la nouvelle date'}</button><button class="bsec" onclick="imFormRefus('${i.id}')">Refuser</button>`;
    if(['a_valider','envoyee','contre'].includes(i.statut))act+=`<button class="bsec" onclick="imAgir('${i.id}','annuler')">Annuler</button>`;
    return `<div class="card rs-card${(i.statut==='contre'||i.statut==='a_valider')&&i.decide?' todo':''}" style="cursor:default">
      <div class="rs-top"><div style="flex:1;min-width:0"><div class="rs-club">✉️ ${esc(i.club_externe)}${i.equipe_externe?' · '+esc(i.equipe_externe):''}</div>
        <div class="rs-sub">${esc(i.equipe)} · ${esc(i.contact_nom?i.contact_nom+' — ':'')}${esc(i.contact_email)}</div></div><span class="pill ${c}">${lb}</span></div>
      ${viaAnnonce?'':`<div class="rs-line">📅 ${esc(quand)}</div>`}
      ${i.statut==='contre'||viaAnnonce?`<div class="rs-line" style="color:var(--amber)">${viaAnnonce?'📅 Créneau choisi :':'↪ Ils proposent :'} ${esc(imJour(i.reponse_jour))}${i.reponse_heure?' · '+i.reponse_heure:''} · ${i.reponse_lieu==='nous'?'🏠 chez nous':'✈️ chez eux'}</div>`:''}
      ${i.reponse_message?`<div class="rs-line">💬 « ${esc(i.reponse_message)} »</div>`:''}
      ${i.reponse_nom||i.reponse_tel?`<div class="rs-line">☎️ ${esc([i.reponse_nom,i.reponse_tel].filter(Boolean).join(' · '))}</div>`:''}
      ${act?`<div class="trn-ins-a">${act}</div>`:''}<div id="im-refus-${i.id}"></div></div>`;};
  const enCours=l.filter(i=>['a_valider','envoyee','contre'].includes(i.statut)),fini=l.filter(i=>!enCours.includes(i)).slice(0,10);
  body.insertAdjacentHTML('beforeend',`<div class="tb-sec-t" style="margin-top:14px">Propositions par e-mail (clubs sans FootLink)</div>${enCours.map(carte).join('')}${fini.map(carte).join('')}`);
};
// Refus d'une autre date : raison facultative, reprise dans l'e-mail envoyé au club
function imFormRefus(id){
  document.getElementById('im-refus-'+id).innerHTML=`<div style="margin-top:8px"><label class="fl">Raison du refus <span style="color:var(--text3);font-weight:400">(facultatif)</span></label>
    <textarea class="fi" id="imr-msg-${id}" rows="2" maxlength="300" placeholder="Ex. : pas de terrain ce jour-là…"></textarea>
    <button class="bred" style="margin-top:6px" onclick="imAgir('${id}','refuser_contre')">Confirmer le refus</button></div>`;
  document.getElementById('imr-msg-'+id).focus();
}
async function imAgir(id,action){
  if(action==='annuler'&&!await askConfirm('Annuler cette proposition ?'))return;
  const args={p_id:id,p_action:action};
  if(action==='refuser_contre')args.p_motif=document.getElementById('imr-msg-'+id)?.value.trim()||null;
  const{data,error}=await sb.rpc('invitation_match_agir',args);
  if(error)return showToast(error.message.replace(/^.*?:\s*/,'')||'Action impossible','err');
  showToast({envoyee:'✉️ Proposition envoyée',acceptee:'Match ajouté au calendrier : le club est prévenu',refusee:'Nouvelle date refusée : le club est prévenu',annulee:'Proposition annulée'}[data]||'OK','ok');
  if(data==='acceptee'&&typeof loadMatches==='function')loadMatches();
  prRenderListe();
}

// ---- 2. Inviter un club à rejoindre FootLink ----
function icOuvrir(){
  if(!imClub())return showToast('Réservé au CQ et aux coordinateurs','err');
  ['ic-email','ic-nom','ic-club','ic-msg'].forEach(id=>document.getElementById(id).value='');
  openModal('modal-ic');
}
async function icEnvoyer(){
  const v=id=>document.getElementById(id).value.trim();
  if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v('ic-email')))return showToast('Adresse e-mail invalide','err');
  const{error}=await sb.rpc('invitation_club_creer',{p_club:imClub(),p_email:v('ic-email'),p_contact:v('ic-nom')||null,p_club_nom:v('ic-club')||null,p_message:v('ic-msg')||null});
  if(error)return showToast(/function|schema cache/i.test(error.message)?'Fonction pas encore disponible':error.message.replace(/^.*?:\s*/,''),'err');
  closeModal('modal-ic');showToast('✉️ Invitation envoyée','ok');
}
// « Inviter un club » vit dans Gestion des clubs (à côté de « Créer un club »), pas dans Mon club
const imRenderPlateforme=renderPlateforme;
renderPlateforme=async function(){
  await imRenderPlateforme.apply(this,arguments);
  const nv=document.querySelector('.pt-new');
  if(nv&&imClub()&&!document.getElementById('ic-club-btn'))nv.insertAdjacentHTML('afterend','<button class="bsec pt-new" id="ic-club-btn" onclick="icOuvrir()">✉️ Inviter un club sur FootLink</button>');
  imPreremplir();
};

// ---- Arrivée par le lien d'invitation (?rejoindre=…) ----
// Le jeton est gardé sur l'appareil (il survit à la création du compte et à la
// confirmation par e-mail), comme le lien d'invitation des parents.
(function(){
  const t=new URLSearchParams(location.search).get('rejoindre');
  if(t){try{localStorage.setItem(IM_CLE,t);}catch(e){}history.replaceState(null,'',location.pathname);}
  imBanniere();
})();
const imJeton=()=>{try{return localStorage.getItem(IM_CLE);}catch(e){return null;}};
let imInfo=null;
async function imBanniere(){
  const t=imJeton();if(!t)return;
  const r=await fetch(`${SB_URL}/rest/v1/rpc/invitation_club_info`,{method:'POST',headers:{apikey:SB_KEY,Authorization:`Bearer ${SB_KEY}`,'Content-Type':'application/json'},body:JSON.stringify({p_token:t})}).catch(()=>null);
  imInfo=r&&r.ok?await r.json():null;
  if(!imInfo||!imInfo.valide){try{localStorage.removeItem(IM_CLE);}catch(e){}return;}
  const box=document.querySelector('#screen-auth .auth-box');
  if(box&&!document.getElementById('im-inv')){
    box.insertAdjacentHTML('afterbegin',`<div class="pa-inv" id="im-inv">🤝 <b>${esc(imInfo.club)}</b> vous invite à rejoindre FootLink.<br><span>Créez votre compte, puis la fiche de votre club.</span></div>`);
    // Inscription pré-remplie avec l'adresse invitée
    const re=document.getElementById('re');if(re&&!re.value)re.value=imInfo.email||'';
  }
}
function imPreremplir(){
  if(!imInfo||!imInfo.valide)return;
  const n=document.getElementById('cc-nom');if(n&&!n.value&&imInfo.club_nom)n.value=imInfo.club_nom;
}
// Club créé par la personne invitée : l'invitation est marquée utilisée (le club qui invite est prévenu)
const imCreateClub=createClub;
createClub=async function(){
  const avant=clubPageId;
  await imCreateClub.apply(this,arguments);
  const t=imJeton();
  if(t&&clubPageId&&clubPageId!==avant){
    await sb.rpc('invitation_club_utiliser',{p_token:t,p_club:clubPageId});
    try{localStorage.removeItem(IM_CLE);}catch(e){}imInfo=null;
  }
};

// ---- 3. Partager une annonce (post Facebook) ----
// Texte prêt à copier (la plupart des clubs cherchent encore leurs adversaires sur Facebook)
// + lien vers annonce.html : un club sans FootLink y choisit un créneau et laisse ses
// coordonnées ; sa réponse arrive dans « Propositions par e-mail » (à accepter).
let fbAnnonce=null,fbLien='';
document.body.insertAdjacentHTML('beforeend',`
<div class="mo" id="modal-fb"><div class="modal"><div class="mh"></div>
  <div class="mt">📣 Partager l'annonce</div>
  <div class="rs-line" style="margin:-6px 0 10px">Copie ce texte dans un groupe Facebook (ou WhatsApp). Les clubs répondent en un clic via le lien, même sans compte FootLink.</div>
  <div class="fb-contact"><span>Contact affiché :</span>
    <label><input type="checkbox" id="fb-nom" checked onchange="fbMaj()"> nom</label>
    <label><input type="checkbox" id="fb-tel" onchange="fbMaj()"> téléphone</label>
    <label><input type="checkbox" id="fb-mail" onchange="fbMaj()"> e-mail</label></div>
  <textarea class="fi fb-texte" id="fb-texte" rows="12"></textarea>
  <div class="trn-btns" style="margin-top:10px"><button class="bp" onclick="fbCopier()">📋 Copier le texte</button>
    <button class="bsec" onclick="fbFacebook()">Ouvrir Facebook</button>
    <button class="bsec" onclick="fbWhatsapp()">WhatsApp</button></div>
  <div class="mfoot"><button class="bcan" onclick="closeModal('modal-fb')">Fermer</button></div>
</div></div>`);
async function fbPartager(id){
  fbAnnonce=(typeof rsMine!=='undefined'?rsMine:[]).find(a=>a.id===id);if(!fbAnnonce)return;
  const{data,error}=await sb.rpc('annonce_partager',{p_annonce:id});
  if(error)return showToast(/function|schema cache/i.test(error.message)?'Partage pas encore disponible':error.message.replace(/^.*?:\s*/,''),'err');
  fbLien=location.origin+'/annonce.html?a='+data;
  document.getElementById('fb-tel').disabled=!UP?.telephone;document.getElementById('fb-tel').checked=!!UP?.telephone;
  fbMaj();openModal('modal-fb');
}
function fbTexte(){
  const a=fbAnnonce,t=rsTeam(a.team_id)||{},club=t.clubs?.nom||clubOf(a.club_id)?.nom||'';
  const fmt=a.format||t.format,cat=(a.categories||[]).length?a.categories.join(', '):t.categorie;
  const cr=(a.annonce_creneaux||[]).filter(c=>c.statut!=='pris'&&c.jour>=todayIso()).sort((x,y)=>(x.jour+(x.heure_debut||'')).localeCompare(y.jour+(y.heure_debut||'')));
  const lieu={domicile:`🏠 À domicile${clubOf(a.club_id)?.adresse?' ('+clubOf(a.club_id).adresse+')':''}`,exterieur:'✈️ Nous nous déplaçons',indifferent:'🏠✈️ À domicile ou en déplacement'}[a.lieu]||'';
  const niv=(a.niveaux||[]).map(n=>typeof nivLabel==='function'?nivLabel(n):'').filter(Boolean).join(', ');
  const contact=[document.getElementById('fb-nom').checked&&UP?`${UP.prenom} ${UP.nom||''}`.trim():'',
    document.getElementById('fb-tel').checked&&UP?.telephone?UP.telephone:'',
    document.getElementById('fb-mail').checked&&UP?.email?UP.email:''].filter(Boolean).join(' · ');
  return [`⚽ ${club} cherche un adversaire — ${t.nom||cat}${cat&&cat!==t.nom?' ('+cat+')':''}${fmt?' · '+formatLabel(fmt):''}`,
    `${AN_TYPES[a.type]||'Match amical'}`,'',
    ...cr.map(c=>'📅 '+creneauTxt(c)),
    lieu,niv?`📊 Niveau : ${niv}`:'',a.duree_mt?`⏱️ ${a.duree_mt} min par mi-temps`:'',
    a.message?`\n${a.message}`:'','',
    `👉 Répondez en un clic, sans inscription : ${fbLien}`,
    contact?`☎️ ${contact}`:'','',
    `FootLink, l'appli gratuite des clubs de foot de jeunes : ${location.origin}`].filter((l,i,arr)=>l!==''||arr[i-1]!=='').join('\n').trim();
}
function fbMaj(){document.getElementById('fb-texte').value=fbTexte();}
async function fbCopier(){
  const t=document.getElementById('fb-texte').value;
  try{await navigator.clipboard.writeText(t);showToast('Texte copié : colle-le dans ton post','ok');}
  catch(e){const ta=document.getElementById('fb-texte');ta.select();document.execCommand('copy');showToast('Texte copié','ok');}
}
// Facebook ne permet pas de pré-remplir le texte : on copie puis on ouvre le partage du lien
async function fbFacebook(){await fbCopier();window.open('https://www.facebook.com/sharer/sharer.php?u='+encodeURIComponent(fbLien),'_blank','noopener');}
function fbWhatsapp(){window.open('https://wa.me/?text='+encodeURIComponent(document.getElementById('fb-texte').value),'_blank','noopener');}
