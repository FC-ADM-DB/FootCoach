// ============ TOURNOIS (C6, version « club organisateur ») ============
// Chargé après calendrier.js (utilise sb, teams, myClubs, isClubStaff, myTeamRole,
// isStaffRole, esc, showToast, askConfirm, openModal, closeModal, refs, goPage) et
// tournoi-calc.js (programme, classement, phase finale).
// - Organiser (tournoi, tableaux, équipes, programme) : CQ / coordinateur du club.
// - Saisir les scores : aussi l'encadrement des équipes du club (fonction tournoi_score).
// - Les autres membres du club consultent. Page publique : tournoi.html?t=<id>.
let trnListe=[],trnCur=null,trnTabs=[],trnEq=[],trnMatchs=[],trnTbId=null,trnVue='programme',trnPoll=null,trnScoreM=null;

const trnOrg=t=>!!t&&isClubStaff(t.club_id);
const trnPeutScorer=t=>!!t&&(trnOrg(t)||teams.some(x=>x.club_id===t.club_id&&isStaffRole(myTeamRole(x))));
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
  <div class="mfoot trn-s-foot"><button class="bcan" onclick="closeModal('modal-trn-score')">Annuler</button><button class="bsec" onclick="trnSauverScore('en_cours')">En cours</button><button class="bp" onclick="trnSauverScore('termine')">Terminé</button></div>
</div></div>`);

async function renderTournois(){
  if(trnCur)return renderTournoi();
  const el=document.getElementById('trn-content');
  const{data,error}=await sb.from('tournois').select('*').order('jour',{ascending:false});
  if(error){el.innerHTML=`<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Tournois indisponibles</div><div class="empty-s">${isMissingFn(error)||/tournois/.test(error.message||'')?'Le module n\'est pas encore installé dans la base.':esc(error.message)}</div></div>`;return;}
  trnListe=data||[];
  const peutCreer=myClubs.length>0;
  const auj=todayIso();
  const carte=t=>`<div class="card" onclick="trnOuvrir('${t.id}')"><div style="display:flex;align-items:center;gap:8px"><div style="flex:1;min-width:0"><div style="font-size:14px;font-weight:600">${esc(t.nom)}</div><div style="font-size:12px;color:var(--text2)">${esc(trnJour(t.jour))}${t.lieu?' · '+esc(t.lieu):''}</div></div>${t.publie?'<span class="pill pg">Publié</span>':'<span class="pill pgr">Brouillon</span>'}</div></div>`;
  const avenir=trnListe.filter(t=>t.jour>=auj).reverse(),passes=trnListe.filter(t=>t.jour<auj);
  el.innerHTML=`${peutCreer?`<div style="display:flex;justify-content:flex-end;margin-bottom:10px"><button class="badd" onclick="trnNouveau()">+ Tournoi</button></div>`:''}
    ${!trnListe.length?`<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Aucun tournoi</div><div class="empty-s">${peutCreer?'Crée le premier tournoi du club : catégories, équipes, programme, scores et page publique.':'Les tournois de ton club apparaîtront ici.'}</div></div>`:''}
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
    ${!tb?`<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Aucun tableau</div><div class="empty-s">${org?'Ajoute un tableau par catégorie (U9, U11…) avec « + Tableau ».':'L\'organisateur prépare le tournoi.'}</div></div>`:
    `<div class="rs-tabs">${vue('programme','Programme')}${vue('classement','Classement')}${vue('equipes','Équipes ('+trnEq.filter(e=>e.tableau_id===tb.id).length+')')}${org?vue('reglages','Réglages'):''}</div>
    <div id="trn-vue">${trnVue==='classement'?trnHtmlClassement(tb):trnVue==='equipes'?trnHtmlEquipes(tb,org):trnVue==='reglages'&&org?trnHtmlReglages(tb):trnHtmlProgramme(tb,org)}</div>`}`;
}

// ---- Programme ----
function trnHtmlProgramme(tb,org){
  const ms=trnMatchs.filter(m=>m.tableau_id===tb.id),eqs=trnEq.filter(e=>e.tableau_id===tb.id);
  if(!ms.length)return `<div class="empty"><div class="empty-i">📋</div><div class="empty-t">Pas encore de programme</div><div class="empty-s">${org?(eqs.length<2?'Ajoute au moins deux équipes (onglet Équipes), puis génère le programme dans Réglages.':'Choisis la formule dans Réglages puis « Générer le programme ».'):'L\'organisateur prépare le programme.'}</div></div>${org&&eqs.length>=2?`<div style="text-align:center"><button class="badd" onclick="trnVue='reglages';renderTournoi()">Aller aux réglages</button></div>`:''}`;
  const res=tcResoudre(tb,eqs,ms),score=trnPeutScorer(trnCur);
  const nos=new Set(eqs.filter(e=>e.team_id).map(e=>e.id));
  const carte=m=>{
    const r=res[m.id]||{},a=trnNomEq(r.a)||tcSource(m.source_a,ms),b=trnNomEq(r.b)||tcSource(m.source_b,ms);
    const pret=r.a&&r.b,g=tcGagnant(m);
    const sc=m.statut==='prevu'?'<span class="trn-vs">–</span>':`<span class="trn-score">${m.score_a??0} – ${m.score_b??0}</span>`;
    const st=m.statut==='en_cours'?'<span class="pill pr trn-live">En cours</span>':m.statut==='termine'?'<span class="pill pgr">Terminé</span>':'';
    const tab=m.statut==='termine'&&m.score_a===m.score_b&&m.vainqueur?`<div class="trn-tab-info">Tirs au but : ${esc(m.vainqueur==='a'?a:b)}</div>`:'';
    return `<div class="trn-m${score&&pret?' clic':''}${m.statut==='en_cours'?' live':''}" ${score&&pret?`onclick="trnOuvrirScore('${m.id}')"`:''}>
      <div class="trn-m-top"><span>${m.libelle?esc(m.libelle)+' · ':m.poule&&tb.formule!=='championnat'?'Poule '+esc(m.poule)+' · ':''}Terrain ${m.terrain??'?'}</span>${st}</div>
      <div class="trn-m-l"><span class="trn-eq${nos.has(r.a)?' nous':''}${g==='a'?' gagne':''}${r.a?'':' attente'}">${esc(a)}</span>${sc}<span class="trn-eq d${nos.has(r.b)?' nous':''}${g==='b'?' gagne':''}${r.b?'':' attente'}">${esc(b)}</span></div>${tab}</div>`;
  };
  const parH={};ms.forEach(m=>{const h=(m.heure||'').slice(0,5)||'—';(parH[h]=parH[h]||[]).push(m);});
  const heures=Object.keys(parH).sort();
  let html='',finale=false;
  heures.forEach(h=>{
    const l=parH[h].sort((x,y)=>(x.terrain||0)-(y.terrain||0));
    if(!finale&&l.some(m=>m.phase==='finale')&&!l.some(m=>m.phase==='poule')){finale=true;html+='<div class="trn-sh">Phase finale</div>';}
    html+=`<div class="trn-h">${h}</div>${l.map(carte).join('')}`;
  });
  return (score?'<div class="trn-aide">Touche un match pour saisir le score.</div>':'')+html;
}

// ---- Classement ----
function trnHtmlClassement(tb){
  const eqs=trnEq.filter(e=>e.tableau_id===tb.id),ms=trnMatchs.filter(m=>m.tableau_id===tb.id);
  if(!eqs.length)return '<div class="empty"><div class="empty-i">📊</div><div class="empty-t">Aucune équipe</div></div>';
  const cl=tcClassement(tb,eqs,ms),nb=Object.keys(cl).length;
  const k=tb.formule==='championnat'?0:Math.ceil((tb.qualifies||0)/Math.max(1,nb));
  const nos=new Set(eqs.filter(e=>e.team_id).map(e=>e.id));
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
      <span class="trn-e-n">${esc(e.nom)}${e.team_id?' <span class="pill pg">Notre équipe</span>':''}</span>
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
  const{error}=await sb.rpc('tournoi_score',{p_match:m.id,p_a:trnSA,p_b:trnSB,p_statut:statut,p_vainqueur:nul?trnSTab:null});
  if(error)return showToast('Score refusé','err');
  Object.assign(m,{score_a:trnSA,score_b:trnSB,statut,vainqueur:nul?trnSTab:null});
  closeModal('modal-trn-score');renderTournoi();
}

const trnGoPage=goPage;
goPage=function(name){trnGoPage(name);if(name==='tournois')renderTournois();};
// Tuile et menu « Tournois » : membres d'une équipe rattachée à un club (hors parents)
const trnRenderHome=renderHome;
renderHome=function(){trnRenderHome.apply(this,arguments);
  const vis=myClubs.length>0||teams.some(t=>t.club_id&&isStaffRole(myTeamRole(t)));
  ['home-trn','nav-tournois'].forEach(id=>{const b=document.getElementById(id);if(b)b.style.display=vis?'':'none';});};
