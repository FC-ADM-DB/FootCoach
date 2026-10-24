// ============ TABLEAU TACTIQUE (T1 : terrain, pions préremplis, déplacement, sauvegarde) ============
// Chargé après app.js (utilise sb, CT, CM, players, convs, assignment, posteLayout,
// getPostes, POSTE_LAYOUT_DEFAULTS, pitchSvgMarkup, isAdmin, esc, showToast…).
// Base : table « tableaux » (supabase/2026-10-24-T1-tableaux.sql), encadrement seulement.
// Coordonnées des pions en % du terrain, TOUJOURS en orientation portrait (notre but
// en bas) ; l'affichage paysage les fait pivoter (même convention que le Live).
// Données d'enfants : l'état ne stocke que l'id du joueur et le numéro de poste ; le
// prénom est retrouvé à l'affichage dans l'effectif (encadrement uniquement).

let tb=null;            // tableau ouvert : {id, team_id, match_id, phase, periode, titre, format, etat, version}
let tbLand=false,tbMQ=null,tbSaveT=null,tbEtat='ok';   // tbEtat : 'ok' | 'attente' (non synchronisé)
const TB_PHASES={avant:'Avant le match',pause:'Pause',apres:'Après le match',libre:'Tableau'};
const tbUuid=()=>crypto.randomUUID?crypto.randomUUID():'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const r=Math.random()*16|0;return(c==='x'?r:(r&3|8)).toString(16);});
const tbEtape=()=>tb.etat.etapes[0];   // T1 : une seule étape (les étapes animées arrivent en T3)
const tbClamp=v=>Math.max(2,Math.min(98,v));
// Portrait (stockage) ↔ affichage
const tbToScreen=(x,y)=>tbLand?{x:y,y:100-x}:{x,y};
const tbFromScreen=(x,y)=>tbLand?{x:100-y,y:x}:{x,y};

// ------------------------------------------------------------ PRÉREMPLISSAGE
// Positions de départ par format : celles du Live ; Festifoot (sans postes) : N pions
function tbPositions(fmt,n){
  const d=POSTE_LAYOUT_DEFAULTS[fmt]?.portrait;
  if(d)return Object.entries(d).map(([k,p])=>({num:+k,x:p.x,y:p.y}));
  const base=[{x:50,y:86},{x:28,y:62},{x:72,y:62},{x:50,y:40},{x:30,y:30},{x:70,y:30}];
  return base.slice(0,n||3).map((p,i)=>({num:i+1,...p}));
}
function tbNouvelEtat(fmt,matchLayout,assign,nFesti){
  const pos=tbPositions(fmt,nFesti);
  const lay=matchLayout&&Object.keys(matchLayout).length?matchLayout:null;
  // Joueurs présents non placés : rangés sur leur poste préféré
  const libres=players.filter(p=>!convs||!Object.keys(convs).length||convs[p.id]==='present');
  const pions=[];
  pos.forEach(p=>{
    const q=lay?.[p.num]||p;
    let joueur=assign?.[p.num]||null;
    if(!joueur&&!assign)joueur=libres.find(j=>j.numero_poste===p.num&&!pions.some(x=>x.joueur===j.id))?.id||null;
    pions.push({id:'n'+p.num,camp:'nous',num:p.num,x:q.x,y:q.y,joueur});
  });
  // Adversaires : même organisation, en miroir (leur gardien en haut)
  pos.forEach(p=>pions.push({id:'e'+p.num,camp:'eux',num:p.num,x:100-p.x,y:100-p.y}));
  return{v:1,terrain:{adversaires:true,libelles:'prenoms'},consignes:[],etapes:[{pions,ballon:{x:50,y:50},traits:[]}]};
}

// ------------------------------------------------------------ OUVERTURE
// Liste des tableaux du match ouvert, avec création d'un nouveau
async function openTableauxMatch(){
  if(!CM||!CT)return showToast('Ouvre d\'abord un match','err');
  if(!isAdmin)return showToast('Réservé à l\'encadrement','err');
  const box=document.getElementById('tb-liste');box.innerHTML='<div class="spin"></div>';
  openModal('modal-tableaux');
  const{data,error}=await sb.from('tableaux').select('id,titre,phase,periode,updated_at').eq('match_id',CM.id).order('updated_at',{ascending:false});
  const def=CM.statut==='termine'?'apres':CM.statut==='en_cours'?'pause':'avant';
  box.innerHTML=(error?'<div class="rs-warn">Tableaux indisponibles (hors ligne ?)</div>':'')+
    ((data||[]).map(t=>`<button class="tb-item" onclick="closeModal('modal-tableaux');openTableau('${t.id}')">
      <span class="pill pb">${esc(TB_PHASES[t.phase])}${t.phase==='pause'&&t.periode?' '+t.periode:''}</span>
      <span class="tb-item-t">${esc(t.titre||'Sans titre')}</span><span class="acc-arrow">›</span></button>`).join('')||'<div class="rs-line" style="margin-bottom:8px">Aucun tableau pour ce match.</div>')+
    `<div class="tb-new">${['avant','pause','apres'].map(p=>`<button class="${p===def?'bp':'bsec'}" onclick="closeModal('modal-tableaux');nouveauTableau('${p}')">+ ${TB_PHASES[p]}</button>`).join('')}</div>`;
}
function nouveauTableau(phase){
  const fmt=CT.format;
  // À la pause : composition DU MOMENT (assignment / posteLayout du match ouvert)
  const live=CM&&Object.keys(assignment||{}).length;
  tb={id:tbUuid(),team_id:CT.id,match_id:CM?.id||null,phase,periode:phase==='pause'?(halfN||1):null,
      titre:'',format:fmt,version:0,
      etat:tbNouvelEtat(fmt,live?posteLayout?.portrait:null,live?assignment:null,formatHasLive(fmt)?0:3)};
  tbOuvrirEcran();tbSauver();
}
async function openTableau(id){
  // Copie locale d'abord (hors ligne), sinon la base
  const loc=tbLireLocal(id);
  let row=null;
  try{const r=await sb.from('tableaux').select('*').eq('id',id).single();row=r.data;}catch(e){}
  if(loc&&(!row||loc.version>=row.version))row=loc;
  if(!row)return showToast('Tableau introuvable','err');
  tb={id:row.id,team_id:row.team_id,match_id:row.match_id,phase:row.phase,periode:row.periode,titre:row.titre||'',format:row.format||CT.format,etat:row.etat,version:row.version||0};
  if(!tb.etat?.etapes?.length)tb.etat=tbNouvelEtat(tb.format,null,null,3);
  tbOuvrirEcran();
}

// ------------------------------------------------------------ ÉCRAN
function tbOuvrirEcran(){
  document.getElementById('tb-screen').style.display='flex';
  document.getElementById('tb-titre').value=tb.titre;
  document.getElementById('tb-phase').textContent=TB_PHASES[tb.phase]+(tb.phase==='pause'&&tb.periode?' '+tb.periode:'');
  if(!tbMQ){tbMQ=window.matchMedia('(orientation: landscape)');tbMQ.addEventListener?.('change',tbRender);}
  tbRender();
}
function fermerTableau(){
  tbSauver(true);
  document.getElementById('tb-screen').style.display='none';
}
function tbRender(){
  if(!tb)return;
  tbLand=!!tbMQ?.matches;
  const et=tbEtape(),opt=tb.etat.terrain;
  const wrap=document.getElementById('tb-wrap');
  wrap.classList.toggle('landscape',tbLand);
  tbTaille();
  const svg=document.getElementById('tb-svg');
  svg.setAttribute('viewBox',tbLand?'0 0 420 300':'0 0 300 420');svg.innerHTML=pitchSvgMarkup(tbLand);
  // Barre d'options
  document.getElementById('tb-adv').classList.toggle('on',opt.adversaires);
  document.getElementById('tb-lib').textContent=opt.libelles==='prenoms'?'Aa Prénoms':'# Numéros';
  document.getElementById('tb-festi').style.display=formatHasLive(tb.format)?'none':'flex';
  // Pions + ballon
  const lay=document.getElementById('tb-pions');
  lay.innerHTML=et.pions.filter(p=>p.camp==='nous'||opt.adversaires).map(p=>{
    const s=tbToScreen(p.x,p.y);
    const j=p.joueur?players.find(x=>x.id===p.joueur):null;
    const nom=opt.libelles==='prenoms'&&j?j.prenom:'';
    const lbl=p.camp==='nous'?`Joueur ${p.num}${j?' '+j.prenom:''}`:`Adversaire ${p.num}`;
    return `<div class="tb-pion ${p.camp}" data-id="${p.id}" tabindex="0" role="button" aria-label="${esc(lbl)}, utiliser les flèches pour déplacer" style="left:${s.x}%;top:${s.y}%">
      <span class="tb-num">${p.num}</span>${nom?`<span class="tb-nom">${esc(nom)}</span>`:''}</div>`;}).join('')+
    `<div class="tb-pion ballon" data-id="ballon" tabindex="0" role="button" aria-label="Ballon, utiliser les flèches pour déplacer" style="left:${tbToScreen(et.ballon.x,et.ballon.y).x}%;top:${tbToScreen(et.ballon.x,et.ballon.y).y}%">⚽</div>`;
  lay.querySelectorAll('.tb-pion').forEach(el=>{
    el.addEventListener('pointerdown',tbDragStart);
    el.addEventListener('keydown',tbKey);
  });
  tbMajStatut();
}
const tbObj=id=>id==='ballon'?tbEtape().ballon:tbEtape().pions.find(p=>p.id===id);

// ------------------------------------------------------------ DÉPLACEMENT (doigt, souris, clavier)
let tbDrag=null;
function tbDragStart(e){
  const el=e.currentTarget,o=tbObj(el.dataset.id);if(!o)return;
  e.preventDefault();el.setPointerCapture(e.pointerId);el.classList.add('drag');
  tbDrag={el,o,rect:document.getElementById('tb-pions').getBoundingClientRect()};
  el.addEventListener('pointermove',tbDragMove);
  el.addEventListener('pointerup',tbDragEnd,{once:true});
  el.addEventListener('pointercancel',tbDragEnd,{once:true});
}
function tbDragMove(e){
  if(!tbDrag)return;
  const r=tbDrag.rect;
  const sx=tbClamp((e.clientX-r.left)/r.width*100),sy=tbClamp((e.clientY-r.top)/r.height*100);
  const p=tbFromScreen(sx,sy);tbDrag.o.x=p.x;tbDrag.o.y=p.y;
  tbDrag.el.style.left=sx+'%';tbDrag.el.style.top=sy+'%';   // pas de redessin complet : fluide
}
function tbDragEnd(e){
  if(!tbDrag)return;
  tbDrag.el.classList.remove('drag');tbDrag.el.removeEventListener('pointermove',tbDragMove);
  tbDrag=null;tbSauver();
}
function tbKey(e){
  const pas=e.shiftKey?6:2,d={ArrowLeft:[-pas,0],ArrowRight:[pas,0],ArrowUp:[0,-pas],ArrowDown:[0,pas]}[e.key];
  if(!d)return;
  e.preventDefault();
  const el=e.currentTarget,o=tbObj(el.dataset.id);if(!o)return;
  const s=tbToScreen(o.x,o.y),n={x:tbClamp(s.x+d[0]),y:tbClamp(s.y+d[1])};
  const p=tbFromScreen(n.x,n.y);o.x=p.x;o.y=p.y;
  el.style.left=n.x+'%';el.style.top=n.y+'%';
  tbSauver();
}

// ------------------------------------------------------------ OPTIONS
function tbToggleAdv(){tb.etat.terrain.adversaires=!tb.etat.terrain.adversaires;tbRender();tbSauver();}
function tbToggleLib(){tb.etat.terrain.libelles=tb.etat.terrain.libelles==='prenoms'?'numeros':'prenoms';tbRender();tbSauver();}
// Festifoot : nombre de joueurs par équipe réglable (2 à 6)
function tbFesti(delta){
  const et=tbEtape(),nous=et.pions.filter(p=>p.camp==='nous').length,n=Math.max(2,Math.min(6,nous+delta));
  if(n===nous)return;
  const pos=tbPositions('festifoot',n);
  et.pions=[...pos.map(p=>et.pions.find(x=>x.id==='n'+p.num)||{id:'n'+p.num,camp:'nous',num:p.num,x:p.x,y:p.y,joueur:null}),
            ...pos.map(p=>et.pions.find(x=>x.id==='e'+p.num)||{id:'e'+p.num,camp:'eux',num:p.num,x:100-p.x,y:100-p.y})];
  tbRender();tbSauver();
}

// ------------------------------------------------------------ SAUVEGARDE (copie locale puis base)
// Toujours une copie sur le téléphone d'abord : rien n'est perdu sans réseau ; l'envoi
// est retenté à la prochaine modification ou réouverture (synchronisation complète : T6).
const tbCle=id=>'fc_tb_'+id;
function tbLireLocal(id){try{return JSON.parse(localStorage.getItem(tbCle(id))||'null');}catch(e){return null;}}
function tbSauver(immediat){
  if(!tb)return;
  tb.titre=document.getElementById('tb-titre')?.value.trim()||'';
  const row={id:tb.id,team_id:tb.team_id,match_id:tb.match_id,phase:tb.phase,periode:tb.periode,titre:tb.titre||null,format:tb.format,etat:tb.etat};
  try{localStorage.setItem(tbCle(tb.id),JSON.stringify({...row,version:tb.version,local:true}));}catch(e){}
  tbEtat='attente';tbMajStatut();
  clearTimeout(tbSaveT);
  const envoi=async()=>{
    const{data,error}=await sb.from('tableaux').upsert(row).select('version').single();
    if(error){tbEtat='attente';tbMajStatut();return;}
    tb.version=data.version;tbEtat='ok';
    try{localStorage.removeItem(tbCle(tb.id));}catch(e){}
    tbMajStatut();
  };
  if(immediat)envoi();else tbSaveT=setTimeout(envoi,700);
}
function tbMajStatut(){
  const el=document.getElementById('tb-statut');if(!el)return;
  el.textContent=tbEtat==='ok'?'✓ Enregistré':'⏳ Enregistrement…';
  el.classList.toggle('attente',tbEtat!=='ok');
}

// Taille du terrain : la plus grande qui tient dans la place disponible, aux proportions
// exactes du dessin (300×420 ou 420×300) — sinon les pions ne tomberaient plus au bon endroit.
function tbTaille(){
  const zone=document.querySelector('.tb-field'),wrap=document.getElementById('tb-wrap');if(!zone||!wrap)return;
  const W=zone.clientWidth,H=zone.clientHeight,r=tbLand?420/300:300/420;
  let w=W,h=W/r;if(h>H){h=H;w=H*r;}
  wrap.style.width=Math.floor(w)+'px';wrap.style.height=Math.floor(h)+'px';
}
window.addEventListener('resize',()=>{if(tb&&document.getElementById('tb-screen').style.display==='flex')tbRender();});
