// ============ TOURNOIS (C6, version « club organisateur ») ============
// Chargé après calendrier.js (utilise sb, teams, myClubs, isClubStaff, myTeamRole,
// isStaffRole, esc, showToast, askConfirm, openModal, closeModal, refs, goPage) et
// tournoi-calc.js (programme, classement, phase finale).
// - Organiser (tournoi, tableaux, équipes, programme) : CQ / coordinateur du club.
// - Saisir les scores : aussi l'encadrement des équipes du club (fonction tournoi_score).
// - Les autres membres du club consultent. Page publique : tournoi.html?t=<id>.
let trnListe=[],trnCur=null,trnTabs=[],trnEq=[],trnMatchs=[],trnTbId=null,trnVue='programme',trnPoll=null,trnScoreM=null,trnScoreCote=null;
let trnInscr=[],trnReseau=[],trnCibles=[],trnClubsReseau=[];

const trnOrg=t=>!!t&&isClubStaff(t.club_id);
// Table de marque : organisateur et encadrement des équipes du club organisateur
const trnPeutScorer=t=>!!t&&(trnOrg(t)||teams.some(x=>x.club_id===t.club_id&&isStaffRole(myTeamRole(x))));
// Équipes du tournoi que j'encadre (mon équipe, ou une équipe de mon club si je suis CQ / coordinateur)
const trnMienne=e=>!!e&&!e.libre&&((e.team_id&&teams.some(t=>t.id===e.team_id&&isTeamStaff(t)))||(e.club_id&&isClubStaff(e.club_id)));
const trnNotre=e=>!!e&&!!e.team_id&&teams.some(t=>t.id===e.team_id);
const trnCoteDe=r=>{const ea=trnEq.find(e=>e.id===r.a),eb=trnEq.find(e=>e.id===r.b);return trnMienne(ea)?'a':trnMienne(eb)?'b':null;};
const trnJour=j=>new Date(j+'T12:00').toLocaleDateString('fr-BE',{weekday:'long',day:'numeric',month:'long',year:'numeric'});
const trnTb=()=>trnTabs.find(x=>x.id===trnTbId)||null;
const trnNomEq=id=>trnEq.find(e=>e.id===id)?.nom||null;
const trnLien=t=>location.origin+location.pathname.replace(/[^/]*$/,'')+'tournoi.html?t='+t.id;

// Fenêtres (injectées une fois : le module reste autonome)
document.body.insertAdjacentHTML('beforeend',`
<div class="mo" id="modal-trn"><div class="modal"><div class="mh"></div>
  <div class="mt" id="trn-m-titre">Nouveau tournoi</div>
  <div class="fg"><label class="fl">Nom</label><input class="fi" id="trn-nom" maxlength="80" placeholder="ex. Tournoi de Pâques"></div>
  <div class="fg"><label class="fl">Date</label><input class="fi" id="trn-jour" type="date"></div>
  <div class="fg"><label class="fl">Lieu <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><input class="fi" id="trn-lieu" maxlength="160" placeholder="ex. Stade communal de Braives"></div>
  <div class="fg" id="trn-club-fg"><label class="fl">Club organisateur</label><select class="sel" id="trn-club"></select></div>
  <div class="mfoot"><button class="bcan" onclick="closeModal('modal-trn')">Annuler</button><button class="bp" onclick="trnEnregistrer()">Enregistrer</button></div>
</div></div>
<div class="mo" id="modal-trn-tab"><div class="modal"><div class="mh"></div>
  <div class="mt">Nouveau tableau</div>
  <div class="fg"><label class="fl">Nom <span style="color:var(--text3);font-weight:400">(une catégorie)</span></label><input class="fi" id="trn-tab-nom" maxlength="40" placeholder="ex. U9"></div>
  <div class="fg"><label class="fl">Format</label><select class="sel" id="trn-tab-format"></select></div>
  <div class="mfoot"><button class="bcan" onclick="closeModal('modal-trn-tab')">Annuler</button><button class="bp" onclick="trnCreerTableau()">Créer</button></div>
</div></div>
<div class="mo" id="modal-trn-score"><div class="modal"><div class="mh"></div>
  <div class="mt" id="trn-s-titre">Score</div>
  <div class="trn-sc">
    <div class="trn-sc-eq"><div class="trn-sc-nom" id="trn-s-a"></div><div class="trn-sc-ctl"><button onclick="trnPlus('a',-1)">−</button><b id="trn-s-va">0</b><button onclick="trnPlus('a',1)">+</button></div></div>
    <div class="trn-sc-eq"><div class="trn-sc-nom" id="trn-s-b"></div><div class="trn-sc-ctl"><button onclick="trnPlus('b',-1)">−</button><b id="trn-s-vb">0</b><button onclick="trnPlus('b',1)">+</button></div></div>
  </div>
  <div id="trn-s-tab" class="trn-tab-but" style="display:none"><div class="fl">Égalité : vainqueur aux tirs au but</div><div class="trn-seg"><button id="trn-s-ta" onclick="trnTab('a')"></button><button id="trn-s-tb" onclick="trnTab('b')"></button></div></div>
  <div class="trn-aide" id="trn-s-valid" style="display:none">Validation des scores activée : l'autre équipe devra confirmer.</div>
  <div class="mfoot trn-s-foot"><button class="bcan" onclick="closeModal('modal-trn-score')">Annuler</button><button class="bsec" onclick="trnSauverScore('en_cours')">En cours</button><button class="bp" onclick="trnSauverScore('termine')">Terminé</button></div>
</div></div>
<div class="mo" id="modal-trn-ins"><div class="modal"><div class="mh"></div>
  <div class="mt" id="trn-i-titre">Inscription</div>
  <div class="fg"><label class="fl">Catégorie</label><select class="sel" id="trn-i-tab"></select></div>
  <div class="fg"><label class="fl">Notre équipe</label><select class="sel" id="trn-i-team" onchange="trnInsLibelle()"></select></div>
  <div class="fg"><label class="fl">Message à l'organisateur <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><textarea class="fi" id="trn-i-msg" rows="3" maxlength="1000" placeholder="ex. Nous viendrons avec 9 joueurs"></textarea></div>
  <div class="trn-aide" id="trn-i-aide"></div>
  <div class="mfoot"><button class="bcan" onclick="closeModal('modal-trn-ins')">Annuler</button><button class="bp" id="trn-i-ok" onclick="trnInscrire()">Envoyer</button></div>
</div></div>
<div class="mo" id="modal-trn-msg"><div class="modal"><div class="mh"></div>
  <div class="mt" id="trn-msg-titre">Messages</div>
  <div class="trn-msgs" id="trn-msg-liste"></div>
  <div class="trn-ajout"><textarea class="fi" id="trn-msg-txt" rows="2" maxlength="1000" placeholder="Écrire un message…"></textarea><button class="badd" onclick="trnEnvoyerMsg()">Envoyer</button></div>
  <div class="mfoot"><button class="bcan" onclick="closeModal('modal-trn-msg')">Fermer</button></div>
</div></div>`);

async function renderTournois(){
  if(trnCur)return renderTournoi();
  const el=document.getElementById('trn-content');
  const{data,error}=await sb.from('tournois').select('*').order('jour',{ascending:false});
  if(error){el.innerHTML=`<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Tournois indisponibles</div><div class="empty-s">${isMissingFn(error)||/tournois/.test(error.message||'')?'Le module n\'est pas encore installé dans la base.':esc(error.message)}</div></div>`;return;}
  trnListe=data||[];
  await trnMajInscriptions();
  const peutCreer=myClubs.length>0;
  const auj=todayIso();
  // Tournoi d'un autre club (inscription acceptée) : « Organisé par … »
  const orgNom=t=>teams.some(x=>x.club_id===t.club_id)?'':(trnInscr.find(i=>i.tournoi_id===t.id)?.club_organisateur||'un autre club');
  const carte=t=>{const o=orgNom(t);return `<div class="card" onclick="trnOuvrir('${t.id}')"><div style="display:flex;align-items:center;gap:8px"><div style="flex:1;min-width:0"><div style="font-size:14px;font-weight:600">${esc(t.nom)}</div><div style="font-size:12px;color:var(--text2)">${esc(trnJour(t.jour))}${t.lieu?' · '+esc(t.lieu):''}</div>${o?`<div style="font-size:12px;color:var(--blue)">Organisé par ${esc(o)} · nous sommes inscrits</div>`:''}</div>${o?'<span class="pill pb">Invité</span>':t.inscriptions?'<span class="pill pg">Inscriptions ouvertes</span>':t.publie?'<span class="pill pg">Publié</span>':'<span class="pill pgr">Brouillon</span>'}</div></div>`;};
  const avenir=trnListe.filter(t=>t.jour>=auj).reverse(),passes=trnListe.filter(t=>t.jour<auj);
  el.innerHTML=`${peutCreer?`<div style="display:flex;justify-content:flex-end;margin-bottom:10px"><button class="badd" onclick="trnNouveau()">+ Tournoi</button></div>`:''}
    ${!trnListe.length?`<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Aucun tournoi</div><div class="empty-s">${peutCreer?'Crée le premier tournoi du club : catégories, équipes, programme, scores et page publique.':'Les tournois de ton club apparaîtront ici.'}</div></div>`:''}
    <div class="trn-aide">Pour t'inscrire au tournoi d'un autre club : « Trouver un match » → onglet Tournois.</div>
    ${avenir.length?`<div class="trn-sh">À venir</div>${avenir.map(carte).join('')}`:''}
    ${passes.length?`<div class="trn-sh">Passés</div>${passes.map(carte).join('')}`:''}`;
}

function trnNouveau(t){
  document.getElementById('trn-m-titre').textContent=t?'Modifier le tournoi':'Nouveau tournoi';
  document.getElementById('trn-nom').value=t?.nom||'';
  document.getElementById('trn-jour').value=t?.jour||'';
  document.getElementById('trn-lieu').value=t?.lieu||'';
  const sel=document.getElementById('trn-club');
  sel.innerHTML=myClubs.map(c=>`<option value="${c.club_id}">${esc(c.clubs?.nom||'Club')}</option>`).join('');
  sel.value=t?.club_id||clubVue||CT?.club_id||myClubs[0]?.club_id||'';
  document.getElementById('trn-club-fg').style.display=!t&&myClubs.length>1?'':'none';
  document.getElementById('modal-trn').dataset.id=t?.id||'';
  openModal('modal-trn');
}
async function trnEnregistrer(){
  const id=document.getElementById('modal-trn').dataset.id;
  const nom=document.getElementById('trn-nom').value.trim(),jour=document.getElementById('trn-jour').value,lieu=document.getElementById('trn-lieu').value.trim()||null;
  if(!nom||!jour)return showToast('Nom et date obligatoires','err');
  if(id){
    const{error}=await sb.from('tournois').update({nom,jour,lieu}).eq('id',id);
    if(error)return showToast('Modification refusée','err');
    closeModal('modal-trn');Object.assign(trnCur,{nom,jour,lieu});renderTournoi();return;
  }
  const club_id=document.getElementById('trn-club').value;
  const{data,error}=await sb.from('tournois').insert({club_id,nom,jour,lieu}).select().single();
  if(error)return showToast('Création refusée : '+error.message,'err');
  closeModal('modal-trn');showToast('Tournoi créé','ok');
  trnOuvrir(data.id);
}

async function trnCharger(id){
  const[{data:t},{data:tabs}]=await Promise.all([
    sb.from('tournois').select('*').eq('id',id).maybeSingle(),
    sb.from('tournoi_tableaux').select('*').eq('tournoi_id',id).order('ordre').order('nom')]);
  if(!t)return false;
  trnCur=t;trnTabs=tabs||[];
  const ids=trnTabs.map(x=>x.id);
  if(ids.length){
    const[{data:e},{data:m}]=await Promise.all([
      sb.from('tournoi_equipes').select('*').in('tableau_id',ids).order('poule').order('ordre').order('nom'),
      sb.from('tournoi_matchs').select('*').in('tableau_id',ids).order('heure').order('terrain')]);
    trnEq=e||[];trnMatchs=m||[];
  } else {trnEq=[];trnMatchs=[];}
  if(!trnTabs.some(x=>x.id===trnTbId))trnTbId=trnTabs[0]?.id||null;
  await Promise.all([trnMajInscriptions(),trnChargerAnnonce()]);
  return true;
}
async function trnOuvrir(id){
  if(!await trnCharger(id))return showToast('Tournoi introuvable','err');
  trnVue='programme';renderTournoi();
  // Scores des autres appareils (table de marque, entraîneurs) : rafraîchis toutes les 10 s
  clearInterval(trnPoll);
  trnPoll=setInterval(async()=>{
    if(!trnCur||!document.getElementById('page-tournois').classList.contains('active')||document.querySelector('.mo.open'))return;
    if(await trnCharger(trnCur.id))renderTournoi();
  },10000);
}
function trnFermer(){trnCur=null;clearInterval(trnPoll);trnPoll=null;renderTournois();}

function renderTournoi(){
  const el=document.getElementById('trn-content'),t=trnCur,org=trnOrg(t),tb=trnTb();
  const vue=(k,l)=>`<button class="${trnVue===k?'on':''}" onclick="trnVue='${k}';renderTournoi()">${l}</button>`;
  el.innerHTML=`<div class="trn-hdr">
      <button class="bsec" onclick="trnFermer()">← Tournois</button>
      <div style="flex:1;min-width:0"><div class="trn-titre">${esc(t.nom)}</div><div class="trn-sous">${esc(trnJour(t.jour))}${t.lieu?' · '+esc(t.lieu):''}</div></div>
    </div>
    <div class="trn-actions">
      ${org?`<button class="bsec" onclick="trnNouveau(trnCur)">✎ Modifier</button>
      <button class="bsec ${t.publie?'trn-on':''}" onclick="trnPublier()">${t.publie?'🌐 Publié':'🌐 Publier'}</button>`:''}
      ${t.publie?`<button class="bsec" onclick="trnPartager()">🔗 Lien public</button>`:''}
      ${org?`<button class="bsec trn-del" onclick="trnSupprimer()" aria-label="Supprimer le tournoi">🗑</button>`:''}
    </div>
    <div class="club-chooser">${trnTabs.map(x=>`<button class="${x.id===trnTbId?'on':''}" onclick="trnTbId='${x.id}';renderTournoi()">${esc(x.nom)}</button>`).join('')}${org?`<button onclick="trnNouveauTableau()">+ Tableau</button>`:''}</div>
    ${(()=>{
      const nIns=trnInscr.filter(i=>i.tournoi_id===t.id&&i.cote==='organisateur'&&i.statut==='envoyee').length;
      const onglets=(tb?vue('programme','Programme')+vue('classement','Classement')+vue('equipes','Équipes ('+trnEq.filter(e=>e.tableau_id===tb.id&&!e.libre).length+(tb.places?' / '+tb.places:'')+')')+(org?vue('reglages','Réglages'):''):'')
        +(org?vue('inscriptions',`📣 Inscriptions${nIns?` <span class="rs-count">${nIns}</span>`:''}`):'');
      if(trnVue==='inscriptions'&&org)return `<div class="rs-tabs">${onglets}</div><div id="trn-vue">${trnHtmlInscriptions(t)}</div>`;
      if(!tb)return `${onglets?`<div class="rs-tabs">${onglets}</div>`:''}<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Aucun tableau</div><div class="empty-s">${org?'Ajoute un tableau par catégorie (U9, U11…) avec « + Tableau ».':'L\'organisateur prépare le tournoi.'}</div></div>`;
      return `<div class="rs-tabs">${onglets}</div>
        <div id="trn-vue">${trnVue==='classement'?trnHtmlClassement(tb):trnVue==='equipes'?trnHtmlEquipes(tb,org):trnVue==='reglages'&&org?trnHtmlReglages(tb):trnHtmlProgramme(tb,org)}</div>`;
    })()}`;
}

// ---- Programme ----
function trnHtmlProgramme(tb,org){
  const ms=trnMatchs.filter(m=>m.tableau_id===tb.id),eqs=trnEq.filter(e=>e.tableau_id===tb.id);
  if(!ms.length)return `<div class="empty"><div class="empty-i">📋</div><div class="empty-t">Pas encore de programme</div><div class="empty-s">${org?(eqs.length<2?'Ajoute au moins deux équipes (onglet Équipes), puis génère le programme dans Réglages.':'Choisis la formule dans Réglages puis « Générer le programme ».'):'L\'organisateur prépare le programme.'}</div></div>${org&&eqs.length>=2?`<div style="text-align:center"><button class="badd" onclick="trnVue='reglages';renderTournoi()">Aller aux réglages</button></div>`:''}`;
  const res=tcResoudre(tb,eqs,ms),score=trnPeutScorer(trnCur);
  const nos=new Set(eqs.filter(trnNotre).map(e=>e.id));
  const carte=m=>{
    const r=res[m.id]||{},a=trnNomEq(r.a)||tcSource(m.source_a,ms),b=trnNomEq(r.b)||tcSource(m.source_b,ms);
    const pret=r.a&&r.b,g=tcGagnant(m),cote=pret?trnCoteDe(r):null,peut=pret&&(score||cote);
    // Validation des scores (option) : qui doit encore confirmer ?
    let conf='';
    if(trnCur.validation_scores&&m.statut==='termine'&&!(m.confirme_a&&m.confirme_b)){
      const manque=!m.confirme_a?'a':'b',nomM=manque==='a'?a:b;
      const ea=trnEq.find(e=>e.id===(manque==='a'?r.a:r.b));
      conf=`<div class="trn-conf">⏳ À confirmer par ${esc(nomM)}${trnMienne(ea)?` <button class="bsec" onclick="event.stopPropagation();trnConfirmer('${m.id}','${manque}')">✓ Confirmer</button>`:''}</div>`;
    }
    const sc=m.statut==='prevu'?'<span class="trn-vs">–</span>':`<span class="trn-score">${m.score_a??0} – ${m.score_b??0}</span>`;
    const st=m.statut==='en_cours'?'<span class="pill pr trn-live">En cours</span>':m.statut==='termine'?'<span class="pill pgr">Terminé</span>':'';
    const tab=m.statut==='termine'&&m.score_a===m.score_b&&m.vainqueur?`<div class="trn-tab-info">Tirs au but : ${esc(m.vainqueur==='a'?a:b)}</div>`:'';
    return `<div class="trn-m${peut?' clic':''}${m.statut==='en_cours'?' live':''}" ${peut?`onclick="trnOuvrirScore('${m.id}')"`:''}>
      <div class="trn-m-top"><span>${m.libelle?esc(m.libelle)+' · ':m.poule&&tb.formule!=='championnat'?'Poule '+esc(m.poule)+' · ':''}Terrain ${m.terrain??'?'}</span>${st}</div>
      <div class="trn-m-l"><span class="trn-eq${nos.has(r.a)?' nous':''}${g==='a'?' gagne':''}${r.a?'':' attente'}">${esc(a)}</span>${sc}<span class="trn-eq d${nos.has(r.b)?' nous':''}${g==='b'?' gagne':''}${r.b?'':' attente'}">${esc(b)}</span></div>${tab}${conf}</div>`;
  };
  const parH={};ms.forEach(m=>{const h=(m.heure||'').slice(0,5)||'—';(parH[h]=parH[h]||[]).push(m);});
  const heures=Object.keys(parH).sort();
  let html='',finale=false;
  heures.forEach(h=>{
    const l=parH[h].sort((x,y)=>(x.terrain||0)-(y.terrain||0));
    if(!finale&&l.some(m=>m.phase==='finale')&&!l.some(m=>m.phase==='poule')){finale=true;html+='<div class="trn-sh">Phase finale</div>';}
    html+=`<div class="trn-h">${h}</div>${l.map(carte).join('')}`;
  });
  const mesEq=eqs.some(trnMienne);
  return (score?'<div class="trn-aide">Touche un match pour saisir le score.</div>':mesEq?'<div class="trn-aide">Touche un match de ton équipe pour saisir le score.</div>':'')+html;
}

// ---- Classement ----
function trnHtmlClassement(tb){
  const eqs=trnEq.filter(e=>e.tableau_id===tb.id),ms=trnMatchs.filter(m=>m.tableau_id===tb.id);
  if(!eqs.length)return '<div class="empty"><div class="empty-i">📊</div><div class="empty-t">Aucune équipe</div></div>';
  const cl=tcClassement(tb,eqs,ms),nb=Object.keys(cl).length;
  const k=tb.formule==='championnat'?0:Math.ceil((tb.qualifies||0)/Math.max(1,nb));
  const nos=new Set(eqs.filter(trnNotre).map(e=>e.id));
  let html=tb.classement?'':'<div class="trn-aide">🔒 Classement masqué sur la page publique (réglage du tableau).</div>';
  Object.keys(cl).sort().forEach(p=>{
    html+=`${nb>1?`<div class="trn-sh">Poule ${esc(p)}</div>`:''}<div class="trn-cl"><div class="trn-cl-l trn-cl-h"><span>#</span><span>Équipe</span><span>J</span><span>V</span><span>N</span><span>D</span><span>+/-</span><span>Pts</span></div>
      ${cl[p].map((l,i)=>`<div class="trn-cl-l${i<k?' q':''}${nos.has(l.eq.id)?' nous':''}"><span>${i+1}</span><span class="n">${esc(l.eq.nom)}</span><span>${l.j}</span><span>${l.v}</span><span>${l.n}</span><span>${l.d}</span><span>${l.diff>0?'+':''}${l.diff}</span><b>${l.pts}</b></div>`).join('')}</div>`;
  });
  if(k)html+=`<div class="trn-aide">En vert : qualifiés pour la phase finale (${k} par poule).</div>`;
  // Vainqueur du tableau quand la finale est jouée
  const f=ms.filter(m=>m.phase==='finale').sort((x,y)=>(y.ordre||0)-(x.ordre||0))[0];
  const g=tcGagnant(f);if(g){const r=tcResoudre(tb,eqs,ms)[f.id];html=`<div class="trn-champion">🏆 ${esc(trnNomEq(g==='a'?r.a:r.b)||'')}</div>`+html;}
  return html;
}

// ---- Équipes ----
function trnHtmlEquipes(tb,org){
  const eqs=trnEq.filter(e=>e.tableau_id===tb.id),aProg=trnMatchs.some(m=>m.tableau_id===tb.id);
  const poules=tb.formule==='poules'&&tb.nb_poules>1;
  const opts=p=>TC_POULES.slice(0,tb.nb_poules).split('').map(x=>`<option${x===p?' selected':''}>${x}</option>`).join('');
  const dispo=teams.filter(x=>x.club_id===trnCur.club_id&&!eqs.some(e=>e.team_id===x.id));
  return `${eqs.map(e=>`<div class="trn-e">
      <span class="trn-e-n${e.libre?' trn-libre':''}">${esc(e.nom)}${trnNotre(e)?' <span class="pill pg">Notre équipe</span>':e.inscription_id?' <span class="pill pb">Inscrite</span>':''}</span>
      ${poules?(org?`<select class="sel trn-e-p" onchange="trnPoule('${e.id}',this.value)" aria-label="Poule">${opts(e.poule)}</select>`:`<span class="pill pb">Poule ${esc(e.poule||'?')}</span>`):''}
      ${org?`<button class="bico" onclick="trnRetirerEquipe('${e.id}')" aria-label="Retirer">✕</button>`:''}</div>`).join('')||'<div class="trn-aide">Aucune équipe pour l\'instant.</div>'}
    ${org?`<div class="trn-ajout">
      <input class="fi" id="trn-e-nom" maxlength="60" placeholder="Nom de l'équipe (ex. RFC Hannut U9)" onkeydown="if(event.key==='Enter')trnAjouterEquipe()">
      <button class="badd" onclick="trnAjouterEquipe()">Ajouter</button></div>
      ${dispo.length?`<div class="trn-nos">Nos équipes : ${dispo.map(x=>`<button class="bsec" onclick="trnAjouterEquipe('${x.id}')">+ ${esc(x.nom)}</button>`).join('')}</div>`:''}
      ${aProg?'<div class="trn-aide">⚠️ Le programme existe déjà : après un changement d\'équipes ou de poules, regénère-le dans Réglages.</div>':poules?'<div class="trn-aide">Poules réparties automatiquement à la génération si tu ne les choisis pas.</div>':''}`:''}`;
}
async function trnAjouterEquipe(teamId){
  const tb=trnTb();if(!tb)return;
  const t=teamId?teams.find(x=>x.id===teamId):null;
  const inp=document.getElementById('trn-e-nom');
  const nom=t?t.nom:(inp?.value||'').trim();
  if(!nom)return showToast('Nom de l\'équipe ?','err');
  const n=trnEq.filter(e=>e.tableau_id===tb.id).length;
  const{error}=await sb.from('tournoi_equipes').insert({tableau_id:tb.id,nom,team_id:t?t.id:null,ordre:n,poule:tb.nb_poules>1?null:'A'});
  if(error)return showToast('Ajout refusé','err');
  await trnCharger(trnCur.id);renderTournoi();
  document.getElementById('trn-e-nom')?.focus();
}
async function trnRetirerEquipe(id){
  // Équipe inscrite par un autre club : on enregistre un désistement (place libre gardée)
  const e=trnEq.find(x=>x.id===id);
  if(e?.inscription_id){if(await askConfirm(`Retirer « ${e.nom} » ? Sa place devient « Place libre » (reprise par la prochaine inscription acceptée).`))trnAgir(e.inscription_id,'desister');return;}
  if(trnMatchs.some(m=>m.equipe_a===id||m.equipe_b===id)&&!await askConfirm('Cette équipe a déjà des matchs au programme. La retirer quand même ? (regénère ensuite le programme)'))return;
  const{error}=await sb.from('tournoi_equipes').delete().eq('id',id);
  if(error)return showToast('Suppression refusée','err');
  await trnCharger(trnCur.id);renderTournoi();
}
async function trnPoule(id,p){
  const{error}=await sb.from('tournoi_equipes').update({poule:p}).eq('id',id);
  if(error)return showToast('Modification refusée','err');
  const e=trnEq.find(x=>x.id===id);if(e)e.poule=p;
}

// ---- Réglages + génération du programme ----
function trnHtmlReglages(tb){
  const fmts=(refs.formats||[]).map(f=>`<option value="${esc(f.code)}"${f.code===tb.format?' selected':''}>${esc(f.libelle||f.code)}</option>`).join('');
  const q=v=>[0,2,4,8].map(n=>`<option value="${n}"${n===v?' selected':''}>${n?n+' équipes':'Pas de phase finale'}</option>`).join('');
  return `<div class="trn-form">
    <div class="trn-2"><div class="fg"><label class="fl">Nom du tableau</label><input class="fi" id="tr-nom" value="${esc(tb.nom)}" maxlength="40"></div>
      <div class="fg"><label class="fl">Format</label><select class="sel" id="tr-format">${fmts}</select></div></div>
    <div class="trn-3"><div class="fg"><label class="fl">Places (équipes max)</label><input class="fi" id="tr-places" type="number" min="2" max="64" value="${tb.places??''}" placeholder="illimité"></div>
      <div class="fg"><label class="fl">Niveau</label><input class="fi" id="tr-niveau" maxlength="40" value="${esc(tb.niveau||'')}" placeholder="ex. 2"></div>
      <div class="fg"><label class="fl">Années</label><input class="fi" id="tr-annees" maxlength="40" value="${esc(tb.annees||'')}" placeholder="ex. nés en 2017"></div></div>
    <div class="fg"><label class="fl">Formule</label><div class="trn-seg"><button id="tr-f-p" class="${tb.formule==='poules'?'on':''}" onclick="trnFormule('poules')">Poules + phase finale</button><button id="tr-f-c" class="${tb.formule==='championnat'?'on':''}" onclick="trnFormule('championnat')">Mini-championnat</button></div>
      <div class="trn-aide" style="margin-top:6px">${tb.formule==='championnat'?'Toutes les équipes se rencontrent une fois ; le classement final désigne le vainqueur.':'Matchs de poule (chacun contre chacun), puis les premiers de chaque poule en phase finale.'}</div></div>
    ${tb.formule==='poules'?`<div class="trn-2"><div class="fg"><label class="fl">Nombre de poules</label><select class="sel" id="tr-poules">${[1,2,3,4,5,6,7,8].map(n=>`<option${n===tb.nb_poules?' selected':''}>${n}</option>`).join('')}</select></div>
      <div class="fg"><label class="fl">Phase finale</label><select class="sel" id="tr-qual">${q(tb.qualifies)}</select></div></div>`:''}
    <div class="trn-2"><div class="fg"><label class="fl">Premier match</label><input class="fi" id="tr-debut" type="time" value="${(tb.debut||'09:00').slice(0,5)}"></div>
      <div class="fg"><label class="fl">Durée d'un match (min)</label><input class="fi" id="tr-duree" type="number" min="3" max="90" value="${tb.duree_match}"></div></div>
    <div class="trn-2"><div class="fg"><label class="fl">Pause entre matchs (min)</label><input class="fi" id="tr-pause" type="number" min="0" max="60" value="${tb.pause}"></div>
      <div class="fg"><label class="fl">Terrains</label><div class="trn-terr"><input class="fi" id="tr-terr" type="number" min="1" max="12" value="${tb.terrains}" aria-label="Nombre de terrains"><span>à partir du n°</span><input class="fi" id="tr-terr1" type="number" min="1" max="30" value="${tb.terrain1}" aria-label="Premier terrain"></div></div></div>
    <div class="fg"><label class="fl">Points</label><div class="trn-pts"><label>Victoire <input class="fi" id="tr-pv" type="number" min="0" max="9" value="${tb.pts_v}"></label><label>Nul <input class="fi" id="tr-pn" type="number" min="0" max="9" value="${tb.pts_n}"></label><label>Défaite <input class="fi" id="tr-pd" type="number" min="0" max="9" value="${tb.pts_d}"></label></div></div>
    <label class="trn-chk"><input type="checkbox" id="tr-cl"${tb.classement?' checked':''}> Afficher le classement sur la page publique</label>
    <div class="trn-btns"><button class="bp" onclick="trnSauverReglages()">Enregistrer</button><button class="badd" onclick="trnGenerer()">⚙️ Générer le programme</button></div>
    <button class="bsec trn-del" style="margin-top:18px" onclick="trnSupprimerTableau()">Supprimer ce tableau</button>
  </div>`;
}
const trnVal=id=>document.getElementById(id)?.value;
function trnLireReglages(tb){
  const n=(id,def)=>{const v=parseInt(trnVal(id),10);return isNaN(v)?def:v;};
  return {nom:(trnVal('tr-nom')||tb.nom).trim()||tb.nom,format:trnVal('tr-format')||tb.format,
    nb_poules:tb.formule==='poules'?n('tr-poules',tb.nb_poules):1,qualifies:tb.formule==='poules'?n('tr-qual',tb.qualifies):0,
    debut:trnVal('tr-debut')||'09:00',duree_match:Math.min(90,Math.max(3,n('tr-duree',tb.duree_match))),pause:Math.min(60,Math.max(0,n('tr-pause',tb.pause))),
    terrains:Math.min(12,Math.max(1,n('tr-terr',tb.terrains))),terrain1:Math.min(30,Math.max(1,n('tr-terr1',tb.terrain1))),
    places:(()=>{const v=parseInt(trnVal('tr-places'),10);return isNaN(v)?null:Math.min(64,Math.max(2,v));})(),
    niveau:(trnVal('tr-niveau')||'').trim()||null,annees:(trnVal('tr-annees')||'').trim()||null,
    pts_v:n('tr-pv',3),pts_n:n('tr-pn',1),pts_d:n('tr-pd',0),classement:!!document.getElementById('tr-cl')?.checked};
}
async function trnSauverReglages(silencieux){
  const tb=trnTb();if(!tb)return false;
  const v=trnLireReglages(tb);
  const{error}=await sb.from('tournoi_tableaux').update(v).eq('id',tb.id);
  if(error){showToast('Enregistrement refusé','err');return false;}
  Object.assign(tb,v);
  if(!silencieux){showToast('Réglages enregistrés','ok');renderTournoi();}
  return true;
}
async function trnFormule(f){
  const tb=trnTb();if(!tb||tb.formule===f)return;
  if(!await trnSauverReglages(true))return;
  const{error}=await sb.from('tournoi_tableaux').update({formule:f}).eq('id',tb.id);
  if(error)return showToast('Modification refusée','err');
  tb.formule=f;renderTournoi();
}
async function trnGenerer(){
  const tb=trnTb();if(!tb)return;
  if(!await trnSauverReglages(true))return;
  const eqs=trnEq.filter(e=>e.tableau_id===tb.id);
  if(eqs.length<2)return showToast('Il faut au moins deux équipes','err');
  const anciens=trnMatchs.filter(m=>m.tableau_id===tb.id);
  if(anciens.length&&!await askConfirm(anciens.some(m=>m.statut!=='prevu')?'Des scores sont déjà saisis. Regénérer le programme les effacera. Continuer ?':'Remplacer le programme actuel ?'))return;
  const{poules,matchs}=tcProgramme(tb,eqs);
  if(tb.qualifies>poules.length)showToast('Plus de qualifiés que d\'équipes : phase finale réduite','err');
  if(anciens.length){const{error}=await sb.from('tournoi_matchs').delete().eq('tableau_id',tb.id);if(error)return showToast('Suppression de l\'ancien programme refusée','err');}
  // Poules choisies / réparties
  for(const p of poules){const e=eqs.find(x=>x.id===p.id);if(e&&e.poule!==p.poule)await sb.from('tournoi_equipes').update({poule:p.poule}).eq('id',p.id);}
  // Phase finale impossible si plus de qualifiés que d'équipes : on ne garde que les poules
  const lignes=matchs.filter(m=>m.phase==='poule'||tb.qualifies<=eqs.length).map(m=>({...m,tableau_id:tb.id}));
  const{error}=await sb.from('tournoi_matchs').insert(lignes);
  if(error)return showToast('Création du programme refusée : '+error.message,'err');
  await trnCharger(trnCur.id);
  const fin=lignes.reduce((h,m)=>m.heure>h?m.heure:h,'');
  showToast(`Programme créé : ${lignes.length} matchs, dernier à ${fin}`,'ok');
  trnVue='programme';renderTournoi();
}
async function trnSupprimerTableau(){
  const tb=trnTb();if(!tb)return;
  if(!await askConfirm(`Supprimer le tableau « ${tb.nom} », ses équipes et ses matchs ?`))return;
  const{error}=await sb.from('tournoi_tableaux').delete().eq('id',tb.id);
  if(error)return showToast('Suppression refusée','err');
  trnTbId=null;await trnCharger(trnCur.id);trnVue='programme';renderTournoi();
}
function trnNouveauTableau(){
  document.getElementById('trn-tab-nom').value='';
  document.getElementById('trn-tab-format').innerHTML=(refs.formats||[]).map(f=>`<option value="${esc(f.code)}">${esc(f.libelle||f.code)}</option>`).join('');
  openModal('modal-trn-tab');
}
async function trnCreerTableau(){
  const nom=document.getElementById('trn-tab-nom').value.trim(),format=document.getElementById('trn-tab-format').value||null;
  if(!nom)return showToast('Nom du tableau ?','err');
  // Durées par défaut selon le format (5c5 plus court)
  const duree=format==='5v5'?10:format==='11v11'?20:12;
  const{data,error}=await sb.from('tournoi_tableaux').insert({tournoi_id:trnCur.id,nom,format,duree_match:duree,ordre:trnTabs.length}).select().single();
  if(error)return showToast('Création refusée','err');
  closeModal('modal-trn-tab');trnTbId=data.id;await trnCharger(trnCur.id);trnVue='equipes';renderTournoi();
}

// ---- Tournoi : publier, partager, supprimer ----
async function trnPublier(){
  const v=!trnCur.publie;
  const{error}=await sb.from('tournois').update({publie:v}).eq('id',trnCur.id);
  if(error)return showToast('Modification refusée','err');
  trnCur.publie=v;showToast(v?'Tournoi publié : la page publique est accessible':'Page publique désactivée','ok');renderTournoi();
}
async function trnPartager(){
  const l=trnLien(trnCur);
  try{await navigator.clipboard.writeText(l);showToast('Lien copié : à partager aux parents et aux clubs','ok');}
  catch(e){window.open(l,'_blank');}
}
async function trnSupprimer(){
  if(!await askConfirm(`Supprimer le tournoi « ${trnCur.nom} » et tout son contenu ? Action irréversible.`))return;
  const{error}=await sb.from('tournois').delete().eq('id',trnCur.id);
  if(error)return showToast('Suppression refusée','err');
  showToast('Tournoi supprimé','ok');trnFermer();
}

// ---- Saisie d'un score ----
let trnSA=0,trnSB=0,trnSTab=null;
function trnOuvrirScore(id){
  const m=trnMatchs.find(x=>x.id===id),tb=trnTb();if(!m||!tb)return;
  const r=tcResoudre(tb,trnEq.filter(e=>e.tableau_id===tb.id),trnMatchs.filter(x=>x.tableau_id===tb.id))[id]||{};
  trnScoreM=m;trnSA=m.score_a??0;trnSB=m.score_b??0;trnSTab=m.vainqueur||null;
  // Mon côté (équipe que j'encadre) ; sinon table de marque du club organisateur
  trnScoreCote=trnCoteDe(r);
  document.getElementById('trn-s-valid').style.display=trnCur.validation_scores&&trnScoreCote?'':'none';
  document.getElementById('trn-s-titre').textContent=(m.libelle||((m.poule&&tb.formule!=='championnat')?'Poule '+m.poule:tb.nom))+' · '+(m.heure||'').slice(0,5)+' · Terrain '+(m.terrain??'?');
  const a=trnNomEq(r.a)||'?',b=trnNomEq(r.b)||'?';
  document.getElementById('trn-s-a').textContent=a;document.getElementById('trn-s-b').textContent=b;
  document.getElementById('trn-s-ta').textContent=a;document.getElementById('trn-s-tb').textContent=b;
  trnMajScore();openModal('modal-trn-score');
}
function trnPlus(c,d){if(c==='a')trnSA=Math.max(0,Math.min(99,trnSA+d));else trnSB=Math.max(0,Math.min(99,trnSB+d));trnMajScore();}
function trnTab(c){trnSTab=c;trnMajScore();}
function trnMajScore(){
  document.getElementById('trn-s-va').textContent=trnSA;document.getElementById('trn-s-vb').textContent=trnSB;
  // Phase finale : il faut un vainqueur, donc les tirs au but en cas d'égalité
  const nul=trnScoreM?.phase==='finale'&&trnSA===trnSB;
  document.getElementById('trn-s-tab').style.display=nul?'':'none';
  document.getElementById('trn-s-ta').classList.toggle('on',trnSTab==='a');
  document.getElementById('trn-s-tb').classList.toggle('on',trnSTab==='b');
}
async function trnSauverScore(statut){
  const m=trnScoreM;if(!m)return;
  const nul=m.phase==='finale'&&trnSA===trnSB;
  if(statut==='termine'&&nul&&!trnSTab)return showToast('Égalité : choisis le vainqueur aux tirs au but','err');
  const{error}=await sb.rpc('tournoi_score',{p_match:m.id,p_a:trnSA,p_b:trnSB,p_statut:statut,p_vainqueur:nul?trnSTab:null,p_cote:trnScoreCote});
  if(error)return showToast('Score refusé','err');
  closeModal('modal-trn-score');
  await trnCharger(trnCur.id);renderTournoi();
}
async function trnConfirmer(id,cote){
  const{error}=await sb.rpc('tournoi_score_confirmer',{p_match:id,p_cote:cote});
  if(error)return showToast('Confirmation refusée','err');
  showToast('Score confirmé','ok');await trnCharger(trnCur.id);renderTournoi();
}

// ============ ANNONCE ET INSCRIPTIONS ============
// Côté organisateur : onglet « 📣 Inscriptions » du tournoi (annonce + demandes reçues).
// Côté club invité : « Trouver un match » → onglet Tournois (annonces + mes inscriptions).
// Circuit (comme les propositions) : l'entraîneur prépare, son coordinateur envoie,
// l'organisateur accepte / refuse ; un désistement libère la place sans rien supprimer.
const TRN_STATUT={a_valider:['pgr','À valider par le coordinateur'],envoyee:['pb','Envoyée — réponse de l\'organisateur attendue'],acceptee:['pg','✓ Acceptée'],refusee:['pr','Refusée'],annulee:['pgr','Annulée'],desistee:['pgr','Désistée']};
const trnFrais=x=>x.frais!=null&&x.frais!==''?`${String(Number(x.frais).toFixed(2)).replace('.',',').replace(',00','')} € par ${x.frais_par==='joueur'?'joueur':'équipe'}`:'';

async function trnMajInscriptions(){
  const{data,error}=await sb.rpc('mes_inscriptions');
  trnInscr=error?[]:(data||[]);
  const n=trnInscr.filter(i=>i.a_traiter).length;
  const b=document.getElementById('home-trn-badge');if(b){b.textContent=n;b.style.display=n?'':'none';}
  return trnInscr;
}
async function trnChargerAnnonce(){
  if(!trnOrg(trnCur))return;
  const[{data:c},cl]=await Promise.all([
    sb.from('tournoi_cibles').select('club_id').eq('tournoi_id',trnCur.id),
    trnClubsReseau.length?Promise.resolve({data:trnClubsReseau}):sb.rpc('clubs_reseau')]);
  trnCibles=(c||[]).map(x=>x.club_id);trnClubsReseau=cl.data||[];
}

function trnHtmlInscriptions(t){
  const club=clubOf(t.club_id)||{};
  const autres=trnClubsReseau.filter(c=>c.id!==t.club_id);
  const opt=(v,l,cur)=>`<option value="${v}"${v===cur?' selected':''}>${l}</option>`;
  const ins=trnInscr.filter(i=>i.tournoi_id===t.id&&i.cote==='organisateur');
  const ligne=i=>{const[c,l]=TRN_STATUT[i.statut]||['pgr',i.statut];
    return `<div class="trn-ins"><div class="trn-ins-h"><div style="flex:1;min-width:0"><b>${esc(i.nom)}</b><div class="trn-sous">${esc(i.tableau_nom)} · ${new Date(i.created_at).toLocaleDateString('fr-BE',{day:'numeric',month:'short'})}</div></div><span class="pill ${c}">${esc(l.replace(' — réponse de l\'organisateur attendue',''))}</span></div>
      <div class="trn-ins-a">${i.statut==='envoyee'?`<button class="badd" onclick="trnAgir('${i.id}','accepter')">Accepter</button><button class="bsec" onclick="trnAgir('${i.id}','refuser')">Refuser</button>`:''}
      ${i.statut==='acceptee'?`<button class="bsec" onclick="trnAgirConfirme('${i.id}','desister','Retirer cette équipe ? Sa place devient « Place libre » dans le programme.')">Retirer (désistement)</button>`:''}
      <button class="bsec" onclick="trnMsgOuvrir('${i.id}')">💬 Messages${i.nb_messages?' ('+i.nb_messages+')':''}</button></div></div>`;};
  const places=trnTabs.map(tb=>{const n=trnEq.filter(e=>e.tableau_id===tb.id&&!e.libre).length;return `<span class="trn-place${tb.places&&n>=tb.places?' plein':''}">${esc(tb.nom)} : ${n}${tb.places?' / '+tb.places:''}${tb.places&&n>=tb.places?' · complet':''}</span>`;}).join('');
  return `<div class="trn-annonce">
    <label class="trn-chk trn-ouv"><input type="checkbox" id="ta-ouv"${t.inscriptions?' checked':''}> <b>Annonce visible et inscriptions ouvertes</b></label>
    ${club.verifie===false?'<div class="trn-aide">⚠️ Ton club n\'est pas encore vérifié : l\'annonce ne sera visible qu\'après vérification.</div>':''}
    <div class="trn-places">${places||'<span class="trn-aide">Ajoute d\'abord les catégories (+ Tableau).</span>'}</div>
    <div class="trn-aide">Une catégorie pleine (places dans ses Réglages) n'accepte plus d'inscription ; un désistement rouvre la place.</div>
    <div class="trn-2"><div class="fg"><label class="fl">Visible par</label><select class="sel" id="ta-zone" onchange="document.getElementById('ta-km-fg').style.display=this.value==='distance'?'':'none';document.getElementById('ta-clubs-fg').style.display=this.value==='clubs'?'':'none'">
        ${opt('belgique','Toute la Belgique',t.zone)}${opt('province','Ma province',t.zone)}${opt('distance','Les clubs à moins de… km',t.zone)}${opt('clubs','Seulement les clubs invités',t.zone)}</select></div>
      <div class="fg" id="ta-km-fg" style="${t.zone==='distance'?'':'display:none'}"><label class="fl">Distance (km)</label><input class="fi" id="ta-km" type="number" min="1" max="500" value="${t.distance_km??30}"></div></div>
    <div class="fg" id="ta-clubs-fg" style="${t.zone==='clubs'?'':'display:none'}"><label class="fl">Clubs invités</label>
      <div class="trn-clubs">${autres.map(c=>`<label><input type="checkbox" class="ta-club" value="${c.id}"${trnCibles.includes(c.id)?' checked':''}> ${esc(c.nom)}</label>`).join('')||'<span class="trn-aide">Aucun autre club vérifié pour l\'instant.</span>'}</div></div>
    <div class="trn-2"><div class="fg"><label class="fl">Date limite d'inscription</label><input class="fi" id="ta-limite" type="date" value="${t.date_limite||''}"></div>
      <div class="fg"><label class="fl">Équipes max par club et par catégorie</label><input class="fi" id="ta-max" type="number" min="1" max="20" value="${t.max_par_club??''}" placeholder="pas de limite"></div></div>
    <label class="trn-chk"><input type="checkbox" id="ta-payant"${t.frais!=null?' checked':''} onchange="document.getElementById('ta-frais-bloc').style.display=this.checked?'':'none'"> Frais d'inscription</label>
    <div class="trn-2" id="ta-frais-bloc" style="${t.frais!=null?'':'display:none'}"><div class="fg"><label class="fl">Montant (€)</label><div class="trn-terr"><input class="fi" id="ta-frais" type="number" min="0" step="0.5" value="${t.frais??''}" style="width:100px"><select class="sel" id="ta-frais-par" style="width:auto">${opt('equipe','par équipe',t.frais_par)}${opt('joueur','par joueur',t.frais_par)}</select></div></div>
      <div class="fg"><label class="fl">Paiement</label><input class="fi" id="ta-paie" maxlength="300" value="${esc(t.paiement||'')}" placeholder="ex. virement BE.. avant le 20/03, ou sur place"></div></div>
    <div class="fg"><label class="fl">Contact</label><input class="fi" id="ta-contact" maxlength="300" value="${esc(t.contact||'')}" placeholder="ex. Marc, 0470 12 34 56, tournoi@club.be"></div>
    <div class="fg"><label class="fl">Infos pour les clubs</label><textarea class="fi" id="ta-infos" rows="4" maxlength="2000" placeholder="Accueil, règlement, durée des matchs, buvette, parking, coupes et médailles…">${esc(t.infos||'')}</textarea></div>
    <label class="trn-chk"><input type="checkbox" id="ta-valid"${t.validation_scores?' checked':''}> Validation des scores : le score saisi par une équipe est à confirmer par l'autre (informatif, ne bloque pas le classement)</label>
    <button class="bp" onclick="trnSauverAnnonce()">Enregistrer l'annonce</button>
  </div>
  <div class="trn-sh">Demandes à traiter</div>${ins.filter(i=>i.statut==='envoyee').map(ligne).join('')||'<div class="trn-aide">Aucune demande en attente.</div>'}
  ${ins.some(i=>i.statut==='acceptee')?`<div class="trn-sh">Équipes inscrites</div>${ins.filter(i=>i.statut==='acceptee').map(ligne).join('')}`:''}
  ${ins.some(i=>['refusee','annulee','desistee'].includes(i.statut))?`<details class="trn-hist"><summary>Historique (${ins.filter(i=>['refusee','annulee','desistee'].includes(i.statut)).length})</summary>${ins.filter(i=>['refusee','annulee','desistee'].includes(i.statut)).map(ligne).join('')}</details>`:''}`;
}
async function trnSauverAnnonce(){
  const v=id=>document.getElementById(id)?.value;
  const zone=v('ta-zone'),num=(id,min,max)=>{const x=parseFloat(v(id));return isNaN(x)?null:Math.min(max,Math.max(min,x));};
  const payant=document.getElementById('ta-payant').checked;
  if(payant&&num('ta-frais',0,99999)==null)return showToast('Indique le montant des frais (ou décoche « Frais d\'inscription »)','err');
  const maj={inscriptions:document.getElementById('ta-ouv').checked,zone,distance_km:zone==='distance'?Math.round(num('ta-km',1,500)||30):trnCur.distance_km,
    date_limite:v('ta-limite')||null,max_par_club:num('ta-max',1,20),
    // Frais : option (case décochée = aucun montant ni modalité de paiement affichés)
    frais:payant?num('ta-frais',0,99999):null,frais_par:v('ta-frais-par')||'equipe',
    paiement:payant?(v('ta-paie')||'').trim()||null:null,contact:(v('ta-contact')||'').trim()||null,infos:(v('ta-infos')||'').trim()||null,
    validation_scores:document.getElementById('ta-valid').checked};
  if(maj.max_par_club!=null)maj.max_par_club=Math.round(maj.max_par_club);
  if(maj.date_limite&&maj.date_limite>trnCur.jour)return showToast('La date limite doit précéder le tournoi','err');
  const{error}=await sb.from('tournois').update(maj).eq('id',trnCur.id);
  if(error)return showToast('Enregistrement refusé','err');
  if(zone==='clubs'){
    const sel=[...document.querySelectorAll('.ta-club:checked')].map(x=>x.value);
    if(!sel.length)showToast('Aucun club invité : coche au moins un club','err');
    await sb.from('tournoi_cibles').delete().eq('tournoi_id',trnCur.id);
    if(sel.length)await sb.from('tournoi_cibles').insert(sel.map(club_id=>({tournoi_id:trnCur.id,club_id})));
    trnCibles=sel;
  }
  Object.assign(trnCur,maj);
  showToast(maj.inscriptions?'Annonce enregistrée : visible dans « Trouver un match »':'Annonce enregistrée (inscriptions fermées)','ok');renderTournoi();
}

async function trnAgir(id,action){
  const{data,error}=await sb.rpc('tournoi_inscription_agir',{p_id:id,p_action:action});
  if(error){const m=error.message||'';return showToast(/complète|maximum|limite|fermées/i.test(m)?m:'Action impossible (réservée au coordinateur / CQ)','err');}
  const msg={envoyee:'Inscription envoyée à l\'organisateur',acceptee:'Équipe acceptée et ajoutée au tableau',refusee:'Inscription refusée',annulee:'Inscription annulée',desistee:'Désistement enregistré : la place est libre'}[data]||'OK';
  showToast(msg,'ok');
  await trnMajInscriptions();
  if(trnCur&&document.getElementById('page-tournois').classList.contains('active')){await trnCharger(trnCur.id);renderTournoi();}
  if(document.getElementById('page-reseau')?.classList.contains('active'))trnReseauRender();
}
async function trnAgirConfirme(id,action,q){if(await askConfirm(q))trnAgir(id,action);}

// ---- Messages d'une inscription ----
let trnMsgId=null;
async function trnMsgOuvrir(id){
  trnMsgId=id;const i=trnInscr.find(x=>x.id===id);
  document.getElementById('trn-msg-titre').textContent=i?(i.cote==='organisateur'?i.nom:i.club_organisateur+' · '+i.tournoi_nom):'Messages';
  document.getElementById('trn-msg-txt').value='';
  await trnMsgCharger();openModal('modal-trn-msg');
}
async function trnMsgCharger(){
  const i=trnInscr.find(x=>x.id===trnMsgId);
  const{data}=await sb.from('tournoi_messages').select('*').eq('inscription_id',trnMsgId).order('created_at');
  const box=document.getElementById('trn-msg-liste');
  box.innerHTML=(data||[]).map(m=>`<div class="msg-b${m.cote===i?.cote?' moi':''}"><div class="msg-a">${esc(m.auteur_nom||'?')} <span class="msg-role${m.cote==='organisateur'?'':' p'}">${m.cote==='organisateur'?'Organisateur':'Club inscrit'}</span></div><div class="msg-t">${esc(m.texte)}</div><div class="msg-h">${new Date(m.created_at).toLocaleString('fr-BE',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}</div></div>`).join('')||'<div class="trn-aide">Aucun message.</div>';
  box.scrollTop=box.scrollHeight;
}
async function trnEnvoyerMsg(){
  const t=document.getElementById('trn-msg-txt').value.trim();if(!t)return;
  const{error}=await sb.rpc('tournoi_message',{p_inscription:trnMsgId,p_texte:t});
  if(error)return showToast('Message refusé','err');
  document.getElementById('trn-msg-txt').value='';await trnMsgCharger();trnMajInscriptions();
}

// ---- « Trouver un match » → onglet Tournois (club invité) ----
async function trnReseauRender(){
  const body=document.getElementById('rs-body');if(!body)return;
  const[{data,error}]=await Promise.all([sb.rpc('tournois_reseau'),trnMajInscriptions()]);
  if(error){body.innerHTML='<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Tournois indisponibles</div><div class="empty-s">Le module n\'est pas encore installé dans la base.</div></div>';return;}
  trnReseau=data||[];
  const mes=trnInscr.filter(i=>i.cote==='inscrit');
  const actions=i=>{
    let b='';
    if(i.statut==='a_valider')b+=i.a_traiter?`<button class="badd" onclick="trnAgir('${i.id}','envoyer')">➤ Envoyer à ${esc(i.club_organisateur)}</button><button class="bsec" onclick="trnAgir('${i.id}','annuler')">Annuler</button>`:`<button class="bsec" onclick="trnAgir('${i.id}','annuler')">Annuler</button>`;
    if(i.statut==='envoyee')b+=`<button class="bsec" onclick="trnAgir('${i.id}','annuler')">Annuler</button>`;
    if(i.statut==='acceptee')b+=`<button class="badd" onclick="goPage('tournois');trnOuvrir('${i.tournoi_id}')">Voir le tournoi</button><button class="bsec" onclick="trnAgirConfirme('${i.id}','desister','Désister cette équipe ? L\\'organisateur en sera informé et la place sera libérée.')">Se désister</button>`;
    return b+`<button class="bsec" onclick="trnMsgOuvrir('${i.id}')">💬${i.nb_messages?' '+i.nb_messages:''}</button>`;
  };
  const insCarte=i=>{const[c,l]=TRN_STATUT[i.statut]||['pgr',i.statut];
    return `<div class="trn-ins${i.a_traiter?' a-traiter':''}"><div class="trn-ins-h"><div style="flex:1;min-width:0"><b>${esc(i.tournoi_nom)}</b><div class="trn-sous">${esc(i.club_organisateur)} · ${esc(trnJour(i.jour))}</div><div class="trn-sous">${esc(i.tableau_nom)} · ${esc(i.nom)}</div></div><span class="pill ${c}">${esc(i.a_traiter?'À envoyer':l)}</span></div><div class="trn-ins-a">${actions(i)}</div></div>`;};
  const carte=t=>{
    const tabs=t.tableaux||[],ouvert=tabs.some(x=>!x.places||x.prises<x.places)&&(!t.date_limite||t.date_limite>=todayIso());
    const lignes=[t.date_limite?`📅 Inscription avant le ${new Date(t.date_limite+'T12:00').toLocaleDateString('fr-BE',{day:'numeric',month:'long'})}`:'',
      trnFrais(t)?'💶 '+trnFrais(t):'',t.paiement?'💳 '+t.paiement:'',t.max_par_club?`👥 ${t.max_par_club} équipe${t.max_par_club>1?'s':''} max par club et par catégorie`:'',t.contact?'☎️ '+t.contact:''].filter(Boolean);
    return `<div class="card trn-an" style="cursor:default">
      <div class="trn-ins-h"><div style="flex:1;min-width:0"><div style="font-size:15px;font-weight:700">${esc(t.nom)}</div><div class="trn-sous">${esc(t.club_nom)}${t.km!=null?' · '+String(t.km).replace('.',',')+' km':''} · ${esc(trnJour(t.jour))}</div>${t.lieu?`<div class="trn-sous">📍 ${esc(t.lieu)}</div>`:''}</div>${t.invite?'<span class="pill pb">Invitation</span>':''}</div>
      <div class="trn-places">${tabs.map(x=>{const plein=x.places&&x.prises>=x.places;return `<span class="trn-place${plein?' plein':''}">${esc(x.nom)}${x.format?' · '+esc(formatLabel(x.format)):''}${x.niveau?' · niv. '+esc(x.niveau):''}${x.annees?' · '+esc(x.annees):''} — ${plein?'complet':x.places?(x.places-x.prises)+' place'+(x.places-x.prises>1?'s':'')+' sur '+x.places:'places libres'}</span>`;}).join('')}</div>
      ${lignes.map(l=>`<div class="trn-sous">${esc(l)}</div>`).join('')}
      ${t.infos?`<div class="trn-infos">${esc(t.infos)}</div>`:''}
      <div style="margin-top:10px">${ouvert?`<button class="badd" onclick="trnInsOuvrir('${t.id}')">S'inscrire</button>`:'<span class="pill pgr">Inscriptions closes</span>'}</div></div>`;
  };
  body.innerHTML=`${mes.length?`<div class="trn-sh">Mes inscriptions</div>${mes.map(insCarte).join('')}`:''}
    <div class="trn-sh">Tournois ouverts aux inscriptions</div>
    ${trnReseau.map(carte).join('')||'<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Aucun tournoi ouvert</div><div class="empty-s">Les tournois des autres clubs (selon leur zone) apparaîtront ici.</div></div>'}`;
}
let trnInsT=null;
function trnInsOuvrir(id){
  const t=trnReseau.find(x=>x.id===id);if(!t)return;trnInsT=t;
  const tabs=(t.tableaux||[]).filter(x=>!x.places||x.prises<x.places);
  const mes=teams.filter(x=>x.club_id&&x.club_id!==t.club_id&&isTeamStaff(x));
  if(!mes.length)return showToast('Aucune équipe que tu encadres ne peut s\'inscrire','err');
  document.getElementById('trn-i-titre').textContent='Inscription · '+t.nom;
  document.getElementById('trn-i-tab').innerHTML=tabs.map(x=>`<option value="${x.id}">${esc(x.nom)}${x.places?' ('+(x.places-x.prises)+' place'+(x.places-x.prises>1?'s':'')+')':''}</option>`).join('');
  // Équipe proposée : celle dont la catégorie correspond au 1er tableau, sinon l'équipe courante
  document.getElementById('trn-i-team').innerHTML=mes.map(x=>`<option value="${x.id}">${esc(x.nom)} (${esc(x.categorie)})</option>`).join('');
  const sameCat=mes.find(x=>tabs[0]&&x.categorie===tabs[0].nom);if(sameCat)document.getElementById('trn-i-team').value=sameCat.id;else if(CT&&mes.some(x=>x.id===CT.id))document.getElementById('trn-i-team').value=CT.id;
  document.getElementById('trn-i-msg').value='';
  trnInsLibelle();openModal('modal-trn-ins');
}
function trnInsLibelle(){
  const team=teams.find(x=>x.id===document.getElementById('trn-i-team').value);
  const direct=team&&isClubStaff(team.club_id);
  document.getElementById('trn-i-ok').textContent=direct?'Envoyer l\'inscription':'Préparer l\'inscription';
  document.getElementById('trn-i-aide').textContent=direct?'L\'inscription part directement chez l\'organisateur, qui l\'accepte ou la refuse.':'Ton coordinateur / CQ la vérifie et l\'envoie à l\'organisateur (comme les propositions de match).';
}
async function trnInscrire(){
  const tb=document.getElementById('trn-i-tab').value,team=document.getElementById('trn-i-team').value;
  if(!tb||!team)return showToast('Choisis la catégorie et l\'équipe','err');
  const{error}=await sb.rpc('tournoi_inscrire',{p_tableau:tb,p_team:team,p_message:document.getElementById('trn-i-msg').value});
  if(error){const m=error.message||'';return showToast(/duplicate|unique/i.test(m)?'Cette équipe est déjà inscrite dans cette catégorie':/complète|maximum|limite|fermées/i.test(m)?m:'Inscription refusée','err');}
  closeModal('modal-trn-ins');
  const t=teams.find(x=>x.id===team);
  showToast(isClubStaff(t?.club_id)?'Inscription envoyée à l\'organisateur':'Inscription préparée : ton coordinateur doit l\'envoyer','ok');
  trnReseauRender();
}

const trnGoPage=goPage;
goPage=function(name){trnGoPage(name);if(name==='tournois')renderTournois();};
// Tuile et menu « Tournois » : membres d'une équipe rattachée à un club (hors parents)
const trnRenderHome=renderHome;
renderHome=function(){trnRenderHome.apply(this,arguments);
  const vis=myClubs.length>0||teams.some(t=>t.club_id&&isStaffRole(myTeamRole(t)));
  ['home-trn','nav-tournois'].forEach(id=>{const b=document.getElementById(id);if(b)b.style.display=vis?'':'none';});
  if(vis)trnMajInscriptions();};
