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
let tbEtapeIdx=0;      // étape affichée / modifiée
const tbEtape=()=>tb.etat.etapes[Math.min(tbEtapeIdx,tb.etat.etapes.length-1)];
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
// Position de départ : chaque équipe dans SA moitié (sinon, avec les positions « plein
// terrain » du Live, nos attaquants et les défenseurs adverses se superposaient).
// Notre équipe : moitié basse (y 51 → 94) ; adversaires : en miroir, moitié haute (6 → 49).
const tbCampNous=(x,y)=>({x,y:+(51+y*0.48).toFixed(1)});
const tbCampEux=(x,y)=>({x:+(100-x).toFixed(1),y:+(49-y*0.48).toFixed(1)});
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
    const c=tbCampNous(q.x,q.y);
    pions.push({id:'n'+p.num,camp:'nous',num:p.num,x:c.x,y:c.y,joueur});
  });
  // Adversaires : même organisation, en miroir (leur gardien en haut)
  pos.forEach(p=>{const c=tbCampEux(p.x,p.y);pions.push({id:'e'+p.num,camp:'eux',num:p.num,x:c.x,y:c.y});});
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
  // Tableau ancien ou incomplet : on complète ce qui manque (options, ballon, tracés)
  tb.etat.terrain={adversaires:true,libelles:'prenoms',...(tb.etat.terrain||{})};tb.etat.consignes=tb.etat.consignes||[];
  tb.etat.etapes.forEach(e=>{e.pions=e.pions||[];e.ballon=e.ballon||{x:50,y:50};e.traits=e.traits||[];});
  tbOuvrirEcran();
}

// ------------------------------------------------------------ ÉCRAN
function tbOuvrirEcran(){
  tbHist=[];tbRedo=[];tbOutil='deplacer';tbEtapeIdx=0;tbStop();
  document.getElementById('tb-screen').style.display='flex';
  document.getElementById('tb-titre').value=tb.titre;
  document.getElementById('tb-phase').textContent=TB_PHASES[tb.phase]+(tb.phase==='pause'&&tb.periode?' '+tb.periode:'');
  if(!tbMQ){tbMQ=window.matchMedia('(orientation: landscape)');tbMQ.addEventListener?.('change',tbRender);}
  tbRender();
}
function fermerTableau(){
  tbStop();
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
  tbRenderTraits();tbMajOutils();tbRenderEtapes();
  tbMajStatut();
}
const tbObj=id=>id==='ballon'?tbEtape().ballon:tbEtape().pions.find(p=>p.id===id);

// ------------------------------------------------------------ DÉPLACEMENT (doigt, souris, clavier)
let tbDrag=null;
function tbDragStart(e){
  const el=e.currentTarget,o=tbObj(el.dataset.id);if(!o)return;
  e.preventDefault();el.setPointerCapture(e.pointerId);el.classList.add('drag');
  tbSnap();
  tbDrag={el,o,rect:document.getElementById('tb-pions').getBoundingClientRect(),x0:o.x,y0:o.y};
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
  // Simple toucher sans déplacement : pas d'étape d'historique inutile
  if(tbDrag.o.x===tbDrag.x0&&tbDrag.o.y===tbDrag.y0)tbHist.pop();
  tbDrag=null;tbRenderTraits();tbSauver();
}
function tbKey(e){
  const pas=e.shiftKey?6:2,d={ArrowLeft:[-pas,0],ArrowRight:[pas,0],ArrowUp:[0,-pas],ArrowDown:[0,pas]}[e.key];
  if(!d)return;
  e.preventDefault();
  const el=e.currentTarget,o=tbObj(el.dataset.id);if(!o)return;
  tbSnap();
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
  const nous=tbEtape().pions.filter(p=>p.camp==='nous').length,n=Math.max(2,Math.min(6,nous+delta));
  if(n===nous)return;
  const pos=tbPositions('festifoot',n);
  tbSnap();
  for(const et of tb.etat.etapes)et.pions=[...pos.map(p=>et.pions.find(x=>x.id==='n'+p.num)||{id:'n'+p.num,camp:'nous',num:p.num,...tbCampNous(p.x,p.y),joueur:null}),
            ...pos.map(p=>et.pions.find(x=>x.id==='e'+p.num)||{id:'e'+p.num,camp:'eux',num:p.num,...tbCampEux(p.x,p.y)})];
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

// ============ T2 : OUTILS DE DESSIN (course, passe, crayon, gomme, annuler/rétablir) ============
// Les tracés sont stockés dans l'étape (traits : [{id, type, pts:[[x,y],…]}]) en % du
// terrain, orientation portrait, comme les pions. Dessinés en pixels dans un SVG au-dessus
// du terrain (sous les pions) pour garder des flèches nettes quelle que soit la taille.
let tbOutil='deplacer',tbHist=[],tbRedo=[],tbTrace=null;
const TB_OUTILS={deplacer:'✋',course:'➜',passe:'⇢',crayon:'✏️',gomme:'🧽'};
const TB_COUL={course:'#ffffff',passe:'#facc15',crayon:'#fb923c'};
function tbSnap(){tbHist.push(JSON.stringify(tb.etat.etapes));if(tbHist.length>60)tbHist.shift();tbRedo=[];tbMajOutils();}
function tbAnnuler(){if(!tbHist.length)return;tbRedo.push(JSON.stringify(tb.etat.etapes));tb.etat.etapes=JSON.parse(tbHist.pop());tbRender();tbSauver();}
function tbRetablir(){if(!tbRedo.length)return;tbHist.push(JSON.stringify(tb.etat.etapes));tb.etat.etapes=JSON.parse(tbRedo.pop());tbRender();tbSauver();}
function tbEffacerTraits(){if(!tbEtape().traits.length)return;tbSnap();tbEtape().traits=[];tbRenderTraits();tbSauver();showToast('Tracés effacés (↶ pour annuler)','ok');}
function tbChoisirOutil(o){tbOutil=o;tbMajOutils();}
function tbMajOutils(){
  document.querySelectorAll('.tb-bar [data-outil]').forEach(b=>b.classList.toggle('on',b.dataset.outil===tbOutil));
  const u=document.getElementById('tb-undo'),r=document.getElementById('tb-redo');
  if(u)u.disabled=!tbHist.length;if(r)r.disabled=!tbRedo.length;
  // Dessin : la couche des tracés reçoit le doigt ; déplacer : ce sont les pions
  const dessin=tbOutil!=='deplacer';
  document.getElementById('tb-pions')?.classList.toggle('inactif',dessin);
  document.getElementById('tb-traits')?.classList.toggle('actif',dessin);
}
// Rendu des tracés en pixels
function tbRenderTraits(){
  const svg=document.getElementById('tb-traits'),wrap=document.getElementById('tb-wrap');if(!svg||!wrap||!tb)return;
  const W=wrap.clientWidth,H=wrap.clientHeight;svg.setAttribute('viewBox',`0 0 ${W} ${H}`);
  const px=([x,y])=>{const s=tbToScreen(x,y);return[s.x*W/100,s.y*H/100];};
  const fl=Math.max(9,Math.min(W,H)*0.035);   // taille de la pointe de flèche
  const traits=[...tbEtape().traits,...(tbTrace?[tbTrace]:[])];
  svg.innerHTML=traits.map(t=>{
    const P=t.pts.map(px),c=TB_COUL[t.type]||'#fff',w=t.type==='crayon'?3:3.5;
    const d='M'+P.map(p=>p[0].toFixed(1)+' '+p[1].toFixed(1)).join(' L');
    let tete='';
    if(t.type!=='crayon'&&P.length>1){
      const [x1,y1]=P[P.length-2],[x2,y2]=P[P.length-1],a=Math.atan2(y2-y1,x2-x1);
      const p1=[x2-fl*Math.cos(a-0.45),y2-fl*Math.sin(a-0.45)],p2=[x2-fl*Math.cos(a+0.45),y2-fl*Math.sin(a+0.45)];
      tete=`<polygon points="${x2},${y2} ${p1[0]},${p1[1]} ${p2[0]},${p2[1]}" fill="${c}"/>`;
    }
    // Trait invisible large : zone de toucher pour la gomme
    return `<g data-id="${t.id||''}"><path d="${d}" fill="none" stroke="transparent" stroke-width="24" stroke-linecap="round" class="tb-hit"/>
      <path d="${d}" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"${t.type==='passe'?' stroke-dasharray="8 7"':''} opacity=".95"/>${tete}</g>`;
  }).join('');
}
// Dessin au doigt sur la couche des tracés
function tbPoint(e){const r=document.getElementById('tb-traits').getBoundingClientRect();
  const p=tbFromScreen(tbClamp((e.clientX-r.left)/r.width*100),tbClamp((e.clientY-r.top)/r.height*100));
  return[+p.x.toFixed(1),+p.y.toFixed(1)];}
function tbTraitsDown(e){
  if(tbOutil==='deplacer')return;
  e.preventDefault();
  if(tbOutil==='gomme'){
    const g=e.target.closest('g[data-id]');if(!g)return;
    const id=g.dataset.id,et=tbEtape(),i=et.traits.findIndex(t=>t.id===id);if(i<0)return;
    tbSnap();et.traits.splice(i,1);tbRenderTraits();tbSauver();return;
  }
  e.currentTarget.setPointerCapture(e.pointerId);
  const p=tbPoint(e);tbTrace={id:tbUuid().slice(0,8),type:tbOutil,pts:[p,p]};
}
function tbTraitsMove(e){
  if(!tbTrace)return;
  const p=tbPoint(e);
  if(tbTrace.type==='crayon'){const l=tbTrace.pts[tbTrace.pts.length-1];if(Math.hypot(p[0]-l[0],p[1]-l[1])>=1)tbTrace.pts.push(p);}
  else tbTrace.pts[1]=p;   // flèche droite : départ → point actuel
  tbRenderTraits();
}
function tbTraitsUp(){
  if(!tbTrace)return;
  const t=tbTrace;tbTrace=null;
  const a=t.pts[0],b=t.pts[t.pts.length-1];
  // Trait trop court (simple toucher) : ignoré
  if(t.type==='crayon'?t.pts.length<3:Math.hypot(b[0]-a[0],b[1]-a[1])<3){tbRenderTraits();return;}
  tbSnap();tbEtape().traits.push(t);tbRenderTraits();tbSauver();
}
document.addEventListener('DOMContentLoaded',()=>{
  const svg=document.getElementById('tb-traits');if(!svg)return;
  svg.addEventListener('pointerdown',tbTraitsDown);
  svg.addEventListener('pointermove',tbTraitsMove);
  svg.addEventListener('pointerup',tbTraitsUp);
  svg.addEventListener('pointercancel',tbTraitsUp);
});
// Raccourcis clavier : Ctrl+Z / Ctrl+Y
document.addEventListener('keydown',e=>{
  if(!tb||document.getElementById('tb-screen')?.style.display!=='flex')return;
  if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'){e.preventDefault();e.shiftKey?tbRetablir():tbAnnuler();}
  else if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='y'){e.preventDefault();tbRetablir();}
});

// ============ T3 : ÉTAPES ET LECTURE ANIMÉE ============
// Une étape = positions des pions et du ballon + ses flèches. « Lire » fait glisser les
// pions d'une étape à la suivante (flèches de l'étape de départ affichées pendant le
// mouvement), avec une vitesse réglable. Maximum 10 étapes.
const TB_MAX_ETAPES=10;
const TB_VITESSES={lent:{d:1700,pause:900,ic:'🐢'},normal:{d:1100,pause:600,ic:'▶︎'},rapide:{d:650,pause:350,ic:'🐇'}};
let tbVitesse='normal',tbLecture=null;   // tbLecture : {stop:true/false} pendant la lecture
function tbRenderEtapes(){
  const el=document.getElementById('tb-etapes');if(!el||!tb)return;
  const n=tb.etat.etapes.length,lit=!!tbLecture;
  tbEtapeIdx=Math.max(0,Math.min(tbEtapeIdx,n-1));   // après ↶ / ↷ le nombre d'étapes peut changer
  el.innerHTML=tb.etat.etapes.map((_,i)=>`<button class="tb-et${i===tbEtapeIdx?' on':''}" onclick="tbAllerEtape(${i})" ${lit?'disabled':''} aria-label="Étape ${i+1}">${i+1}</button>`).join('')+
    (n<TB_MAX_ETAPES?`<button class="tb-et plus" onclick="tbAjouterEtape()" ${lit?'disabled':''} aria-label="Ajouter une étape">＋</button>`:'')+
    (n>1?`<button class="tb-et" onclick="tbSupprEtape()" ${lit?'disabled':''} aria-label="Supprimer l'étape ${tbEtapeIdx+1}">🗑</button>`:'')+
    `<span class="tb-sep"></span>
    <button class="tb-et lire${lit?' on':''}" onclick="tbLire()" aria-label="${lit?'Arrêter':'Lire l\'action'}">${lit?'⏸':'▶ Lire'}</button>
    <button class="tb-et" onclick="tbChangerVitesse()" aria-label="Vitesse : ${tbVitesse}">${TB_VITESSES[tbVitesse].ic==='▶︎'?'1×':TB_VITESSES[tbVitesse].ic}</button>`;
  document.getElementById('tb-screen').classList.toggle('lecture',lit);
}
function tbAllerEtape(i){if(tbLecture)return;tbEtapeIdx=i;tbRender();}
function tbAjouterEtape(){
  const E=tb.etat.etapes;if(E.length>=TB_MAX_ETAPES)return showToast(`${TB_MAX_ETAPES} étapes maximum`,'err');
  tbSnap();
  const copie=JSON.parse(JSON.stringify(tbEtape()));copie.traits=[];   // mêmes positions, sans flèches
  E.splice(tbEtapeIdx+1,0,copie);tbEtapeIdx++;
  tbRender();tbSauver();showToast(`Étape ${tbEtapeIdx+1} : déplace les joueurs`,'ok');
}
function tbSupprEtape(){
  const E=tb.etat.etapes;if(E.length<=1)return;
  tbSnap();E.splice(tbEtapeIdx,1);tbEtapeIdx=Math.max(0,Math.min(tbEtapeIdx,E.length-1));
  tbRender();tbSauver();showToast('Étape supprimée (↶ pour annuler)','ok');
}
function tbChangerVitesse(){const k=Object.keys(TB_VITESSES);tbVitesse=k[(k.indexOf(tbVitesse)+1)%k.length];
  showToast('Vitesse : '+tbVitesse,'ok');tbRenderEtapes();}
function tbStop(){if(tbLecture)tbLecture.stop=true;tbLecture=null;}
const tbAttendre=ms=>new Promise(r=>setTimeout(r,ms));
const tbEase=t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2;
async function tbLire(){
  if(tbLecture){tbStop();tbRender();return;}
  const E=tb.etat.etapes;
  if(E.length<2)return showToast('Ajoute une 2e étape (＋) puis déplace les joueurs','err');
  const lect={stop:false};tbLecture=lect;
  const V=TB_VITESSES[tbVitesse];
  tbEtapeIdx=0;tbRender();
  for(let i=0;i<E.length-1;i++){
    await tbAttendre(V.pause);if(lect.stop)return;
    await tbAnimer(E[i],E[i+1],V.d,lect);if(lect.stop)return;
    tbEtapeIdx=i+1;tbRender();
  }
  await tbAttendre(V.pause);
  if(!lect.stop){tbLecture=null;tbRender();}
}
// Glissement des pions et du ballon de l'étape A à l'étape B (éléments déjà affichés)
function tbAnimer(A,B,duree,lect){
  return new Promise(res=>{
    const els=[...document.querySelectorAll('#tb-pions .tb-pion')];
    const pos=(et,id)=>id==='ballon'?et.ballon:et.pions.find(p=>p.id===id);
    const t0=performance.now();
    const frame=now=>{
      if(lect.stop)return res();
      const k=tbEase(Math.min(1,(now-t0)/duree));
      for(const el of els){
        const a=pos(A,el.dataset.id),b=pos(B,el.dataset.id);if(!a||!b)continue;
        const s=tbToScreen(a.x+(b.x-a.x)*k,a.y+(b.y-a.y)*k);
        el.style.left=s.x+'%';el.style.top=s.y+'%';
      }
      if(k<1)requestAnimationFrame(frame);else res();
    };
    requestAnimationFrame(frame);
  });
}
