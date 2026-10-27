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
function tbCreer(phase,modele){
  const fmt=CT.format;
  // À la pause : composition DU MOMENT (assignment / posteLayout du match ouvert)
  const live=CM&&Object.keys(assignment||{}).length;
  tb={id:tbUuid(),team_id:CT.id,match_id:CM?.id||null,phase,periode:phase==='pause'?tbPeriode():null,
      titre:'',format:fmt,version:0,
      etat:tbNouvelEtat(fmt,live?posteLayout?.portrait:null,live?assignment:null,formatHasLive(fmt)?0:3)};
  if(modele)tbAppliquerModele(modele);
  tbOuvrirEcran();tbSauver();
}
async function openTableau(id,lire){
  // Copie locale d'abord (hors ligne), sinon la base
  const loc=tbLireLocal(id);
  let row=null;
  try{const r=await sb.from('tableaux').select('*').eq('id',id).single();row=r.data;}catch(e){}
  if(loc&&(!row||loc.version>=row.version))row=loc;
  if(!row)return showToast('Tableau introuvable','err');
  tb={id:row.id,team_id:row.team_id,match_id:row.match_id,phase:row.phase,periode:row.periode,titre:row.titre||'',format:row.format||CT.format,etat:row.etat,version:row.version||0,est_modele:!!row.est_modele};
  if(!tb.etat?.etapes?.length)tb.etat=tbNouvelEtat(tb.format,null,null,3);
  // Tableau ancien ou incomplet : on complète ce qui manque (options, ballon, tracés)
  tb.etat.terrain={adversaires:true,libelles:'prenoms',...(tb.etat.terrain||{})};tb.etat.consignes=tb.etat.consignes||[];
  tb.etat.etapes.forEach(e=>{e.pions=e.pions||[];e.ballon=e.ballon||{x:50,y:50};e.traits=e.traits||[];});
  tbOuvrirEcran();
  if(lire&&tb.etat.etapes.length>1)tbLire();   // « ▶ Rejouer » depuis le Bilan
}

// ------------------------------------------------------------ ÉCRAN
function tbOuvrirEcran(){
  tbHist=[];tbRedo=[];tbOutil='deplacer';tbEtapeIdx=0;tbStop();
  document.getElementById('tb-screen').style.display='flex';
  document.getElementById('tb-titre').value=tb.titre;
  document.getElementById('tb-phase').textContent=tb.est_modele?'★ Modèle':TB_PHASES[tb.phase]+(tb.phase==='pause'&&tb.periode?' '+tb.periode:'');
  document.getElementById('tb-mod').style.display=tb.est_modele?'none':'';
  if(!tbMQ){tbMQ=window.matchMedia('(orientation: landscape)');tbMQ.addEventListener?.('change',tbRender);}
  tbRender();
}
function fermerTableau(){
  tbStop();
  const envoi=tbSauver(true);
  document.getElementById('tb-screen').style.display='none';
  tbMajMatch();envoi?.then(()=>tbMajMatch());   // titre / nouveau tableau visibles dans la liste
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
  const row={id:tb.id,team_id:tb.team_id,match_id:tb.match_id,phase:tb.phase,periode:tb.periode,titre:tb.titre||null,format:tb.format,etat:tb.etat,est_modele:!!tb.est_modele};
  try{localStorage.setItem(tbCle(tb.id),JSON.stringify({...row,version:tb.version,local:true}));}catch(e){}
  tbEtat='attente';tbMajStatut();
  clearTimeout(tbSaveT);
  const cur=tb;
  const envoi=async()=>{
    const{data,error}=await sb.from('tableaux').upsert(row).select('version').single();
    if(error){if(tb===cur){tbEtat='attente';tbMajStatut();}return;}
    cur.version=data.version;
    try{localStorage.removeItem(tbCle(cur.id));}catch(e){}
    if(tb===cur){tbEtat='ok';tbMajStatut();}
  };
  if(immediat)return envoi();
  tbSaveT=setTimeout(envoi,700);
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
  tbSnap();
  const et=tbEtape(),suiv=tb.etat.etapes[tbEtapeIdx+1];
  et.traits.push(t);
  // 1re passe de l'étape : le ballon se place tout seul au départ des pointillés (pas
  // besoin de le déplacer à la main) ; l'étape suivante suit si son ballon n'avait pas bougé.
  const bouge=t.type==='passe'&&et.traits.filter(x=>x.type==='passe').length===1;
  if(bouge){
    const nv={x:a[0],y:a[1]};
    if(suiv&&tbDist(suiv.ballon,et.ballon)<0.5)suiv.ballon={...nv};
    // Étapes précédentes où le ballon n'a pas encore servi (même place, pas de passe) : il
    // y est donné au PASSEUR (pion le plus proche du départ), à sa position de chaque étape.
    // Le ballon l'accompagne donc pendant sa course au lieu de l'attendre au point de passe
    // (ou de glisser tout seul depuis le rond central à la lecture).
    const passeur=et.pions.filter(p=>p.camp==='nous'||tb.etat.terrain.adversaires)
      .map(p=>({p,d:tbDist(p,nv)})).filter(o=>o.d<TB_SEUIL).sort((x,y)=>x.d-y.d)[0]?.p;
    const dx=passeur?nv.x-passeur.x:0,dy=passeur?nv.y-passeur.y:0;
    let ancien=et.ballon;   // place du ballon avant modification, dans l'étape qui suit j
    for(let j=tbEtapeIdx-1;j>=0;j--){
      const e=tb.etat.etapes[j];
      if(tbDist(e.ballon,ancien)>=0.5||e.traits.some(x=>x.type==='passe'))break;
      ancien=e.ballon;
      const q=passeur&&e.pions.find(x=>x.id===passeur.id);
      e.ballon=q?{x:tbClamp(+(q.x+dx).toFixed(1)),y:tbClamp(+(q.y+dy).toFixed(1))}:{...nv};
    }
    et.ballon=nv;
  }
  if(suiv){
    const avant={...suiv.ballon};
    tbSuivreFleches(et,suiv,[t]);
    // Le ballon de l'étape suivante a changé : les étapes d'après où il n'avait pas servi
    // (même place, aucune passe avant) le reçoivent aussi
    if(tbDist(avant,suiv.ballon)>=0.5)
      for(let j=tbEtapeIdx+2;j<tb.etat.etapes.length;j++){
        const e=tb.etat.etapes[j],p=tb.etat.etapes[j-1];
        if(tbDist(e.ballon,avant)>=0.5||p.traits.some(x=>x.type==='passe'))break;
        e.ballon={...suiv.ballon};
      }
  }
  bouge?tbRender():tbRenderTraits();tbSauver();
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
  const src=tbEtape(),copie=JSON.parse(JSON.stringify(src));copie.traits=[];   // mêmes positions, sans flèches
  const n=tbSuivreFleches(src,copie,src.traits);
  E.splice(tbEtapeIdx+1,0,copie);tbEtapeIdx++;
  tbRender();tbSauver();
  showToast(n?`Étape ${tbEtapeIdx+1} : les joueurs ont suivi leurs flèches`:`Étape ${tbEtapeIdx+1} : déplace les joueurs`,'ok');
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
  if(E.length<2&&!E[0].traits.some(t=>t.type!=='crayon'))return showToast('Trace des flèches ou ajoute une 2e étape (＋)','err');
  const lect={stop:false};tbLecture=lect;
  const V=TB_VITESSES[tbVitesse];
  tbEtapeIdx=0;tbRender();
  for(let i=0;i<E.length-1;i++){
    await tbAttendre(V.pause);if(lect.stop)return;
    await tbAnimer(E[i],E[i+1],V.d,lect);if(lect.stop)return;
    tbEtapeIdx=i+1;tbRender();
  }
  // Flèches de la DERNIÈRE étape : jouées aussi (vers une étape « virtuelle » où chacun est
  // au bout de sa flèche), sinon une passe tracée sur l'étape finale n'était jamais animée.
  const der=E[E.length-1],fin=JSON.parse(JSON.stringify(der));
  if(tbSuivreFleches(der,fin,der.traits)){
    await tbAttendre(V.pause);if(lect.stop)return;
    await tbAnimer(der,fin,V.d,lect);if(lect.stop)return;
  }
  await tbAttendre(V.pause);
  if(!lect.stop){tbLecture=null;tbRender();}
}
// Glissement des pions et du ballon de l'étape A à l'étape B (éléments déjà affichés)
function tbAnimer(A,B,duree,lect){
  return new Promise(res=>{
    const els=[...document.querySelectorAll('#tb-pions .tb-pion')];
    const pos=(et,id)=>id==='ballon'?et.ballon:et.pions.find(p=>p.id===id);
    const ballon=tbTrajetBallon(A,B);
    const t0=performance.now();
    const frame=now=>{
      if(lect.stop)return res();
      const k=tbEase(Math.min(1,(now-t0)/duree));
      for(const el of els){
        const a=pos(A,el.dataset.id),b=pos(B,el.dataset.id);if(!a||!b)continue;
        const s=el.dataset.id==='ballon'?(q=>tbToScreen(q.x,q.y))(ballon(k)):tbToScreen(a.x+(b.x-a.x)*k,a.y+(b.y-a.y)*k);
        el.style.left=s.x+'%';el.style.top=s.y+'%';
      }
      if(k<1)requestAnimationFrame(frame);else res();
    };
    requestAnimationFrame(frame);
  });
}

// ============ T4 : INTÉGRATION AU MATCH ============
// Avant : section « Tableaux tactiques » sous les convocations.
// Pause : bouton « ⏸ Tableau » dans la barre du chrono, visible quand le chrono est arrêté
//   (mi-temps, arrêt de jeu) ; reprend le tableau de cette pause s'il existe, sinon en crée
//   un avec la composition du moment.
// Après : dans le Bilan, chaque tableau peut être rejoué (▶) + tableau d'analyse.
// Encadrement seulement (isAdmin) : les parents et spectateurs ne voient rien.
// Pause en cours : « Mi-temps » passe déjà halfN à 2, la pause est donc celle de la 1re période
const tbPeriode=()=>halfTimePending?Math.max(1,halfN-1):(halfN||1);
const tbLibelle=t=>TB_PHASES[t.phase]+(t.phase==='pause'&&t.periode?' '+t.periode:'');
// Tableaux du match : base + copies locales pas encore envoyées (hors ligne, ou juste créées)
async function tbTableauxMatch(matchId){
  let rows=[],horsLigne=false;
  try{const{data,error}=await sb.from('tableaux').select('id,titre,phase,periode,updated_at,etat').eq('match_id',matchId).order('created_at');
    if(error)horsLigne=true;else rows=data||[];}catch(e){horsLigne=true;}
  try{for(let i=0;i<localStorage.length;i++){const k=localStorage.key(i);if(!k||!k.startsWith('fc_tb_'))continue;
    const l=JSON.parse(localStorage.getItem(k)||'null');if(!l||l.match_id!==matchId)continue;
    const j=rows.findIndex(r=>r.id===l.id);
    if(j<0)rows.push({...l,local:true});else rows[j]={...rows[j],...l,local:true};}}catch(e){}
  return{rows,horsLigne};
}
let tbMajJeton=0;
async function tbMajMatch(){
  const conv=document.getElementById('tb-match-conv'),res=document.getElementById('tb-match-res');
  tbMajPause();
  if(!conv||!res)return;
  if(!CM||!isAdmin){conv.innerHTML='';res.innerHTML='';return;}
  const vis=id=>document.getElementById(id)?.style.display!=='none';
  if(!vis('tab-conv')&&!vis('tab-res'))return;
  const jeton=++tbMajJeton,matchId=CM.id;
  const{rows,horsLigne}=await tbTableauxMatch(matchId);
  if(jeton!==tbMajJeton||CM?.id!==matchId)return;   // réponse arrivée après un changement de match
  const ligne=(t,lire)=>{const n=t.etat?.etapes?.length||1;
    return `<button class="tb-item" onclick="openTableau('${t.id}'${lire&&n>1?',true':''})">
      <span class="pill pb">${esc(tbLibelle(t))}</span>
      <span class="tb-item-t">${esc(t.titre||'Sans titre')}</span>
      ${t.local?'<span title="Pas encore envoyé">⏳</span>':''}
      ${lire&&n>1?`<span class="tb-rejouer">▶ ${n} étapes</span>`:'<span class="acc-arrow">›</span>'}</button>`;};
  const titre='<div class="tb-sec-t">📋 Tableaux tactiques</div>';
  const warn=horsLigne?'<div class="rs-line" style="margin-bottom:6px">Hors ligne : seuls les tableaux de cet appareil sont affichés.</div>':'';
  const fini=CM.statut==='termine';
  conv.innerHTML=titre+warn+rows.map(t=>ligne(t,false)).join('')+
    `<button class="bsec tb-add" onclick="nouveauTableau('avant')">+ Préparer un tableau</button>`;
  res.innerHTML=titre+warn+(rows.length?rows.map(t=>ligne(t,true)).join(''):'<div class="rs-line" style="margin-bottom:6px">Aucun tableau pour ce match.</div>')+
    `<button class="bsec tb-add" onclick="nouveauTableau('${fini?'apres':'avant'}')">+ ${fini?'Tableau d\'analyse':'Préparer un tableau'}</button>`;
}
// Bouton de la pause : seulement chrono arrêté, match commencé et pas terminé
function tbMajPause(){
  const b=document.getElementById('btn-tb-pause');if(!b)return;
  b.style.display=CM&&isAdmin&&matchStarted&&!chronoOn&&CM.statut!=='termine'?'':'none';
}
async function tbOuvrirPause(){
  if(!CM)return;
  const p=tbPeriode(),matchId=CM.id;
  const{rows}=await tbTableauxMatch(matchId);
  const ex=rows.filter(t=>t.phase==='pause'&&t.periode===p).pop();
  if(ex)openTableau(ex.id);else nouveauTableau('pause');
}
// Mise à jour à chaque changement d'onglet, et quand le bouton Start/Pause du chrono change
// (chrono lancé ou arrêté, ici ou depuis un autre appareil)
(function(){
  const sw=switchTab;
  switchTab=function(t){const r=sw.apply(this,arguments);tbMajMatch();return r;};
  const src=document.getElementById('btn-chrono');
  if(src&&window.MutationObserver)new MutationObserver(tbMajPause).observe(src,{childList:true,characterData:true,subtree:true});
})();

// ============ FLÈCHES → ÉTAPE SUIVANTE ============
// Une flèche qui part d'un pion décrit son déplacement : dans l'étape suivante, le pion est
// placé au bout de la flèche (course = trait plein), le ballon au bout d'une passe (pointillés).
// Un joueur qui court avec le ballon à ses pieds (sans passe) l'emmène avec lui.
// On ne touche pas à un pion déjà déplacé à la main dans l'étape suivante.
const TB_SEUIL=8;                                       // rayon de « départ depuis le pion » (% du terrain)
const tbDist=(a,b)=>Math.hypot(a.x-b.x,(a.y-b.y)*1.4); // y corrigé : le terrain est 1,4× plus long que large
function tbSuivreFleches(src,dst,traits){
  const vis=p=>p.camp==='nous'||tb.etat.terrain.adversaires;
  const intact=(a,b)=>b&&tbDist(a,b)<0.5;
  const bout=t=>({x:t.pts[t.pts.length-1][0],y:t.pts[t.pts.length-1][1]});
  const dep=t=>({x:t.pts[0][0],y:t.pts[0][1]});
  const passes=src.traits.filter(t=>t.type==='passe');
  let n=0;
  for(const t of traits.filter(t=>t.type==='course')){
    const a=dep(t);
    const p=src.pions.filter(vis).map(p=>({p,d:tbDist(p,a)})).filter(o=>o.d<TB_SEUIL).sort((x,y)=>x.d-y.d)[0]?.p;
    if(!p)continue;
    const q=dst.pions.find(x=>x.id===p.id),b=bout(t);
    if(!intact(p,q))continue;
    // Conduite de balle : le ballon garde le même écart avec le joueur
    if(!passes.length&&tbDist(src.ballon,p)<TB_SEUIL&&intact(src.ballon,dst.ballon))
      dst.ballon={x:tbClamp(+(b.x+src.ballon.x-p.x).toFixed(1)),y:tbClamp(+(b.y+src.ballon.y-p.y).toFixed(1))};
    q.x=b.x;q.y=b.y;n++;
  }
  // Passes : le ballon suit les pointillés, dans l'ordre où ils ont été tracés (une-deux
  // possible) et finit au bout de la dernière passe. Le ballon étant placé automatiquement,
  // les passes font toujours foi (avant, un ballon déjà placé ailleurs dans l'étape suivante
  // bloquait le déplacement : la passe de l'étape 1 n'était pas jouée à la lecture).
  if(passes.length&&traits.some(t=>t.type==='passe')){
    const b=bout(passes[passes.length-1]);
    if(!intact(b,dst.ballon)){dst.ballon={x:b.x,y:b.y};n++;}
  }
  return n;
}
// Trajet du ballon pendant la lecture A → B : le long des pointillés de A s'il y en a,
// sinon en ligne droite.
function tbTrajetBallon(A,B){
  const passes=A.traits.filter(t=>t.type==='passe');
  const pt=p=>({x:p[0],y:p[1]});
  let P=[A.ballon,B.ballon];
  // Toujours le long des passes de A ; si le ballon de B est ailleurs, il le rejoint ensuite
  if(passes.length)P=[A.ballon,...passes.flatMap(t=>[pt(t.pts[0]),pt(t.pts.at(-1))]),B.ballon];
  P=P.filter((p,i)=>!i||tbDist(p,P[i-1])>0.3);
  const L=[0];for(let i=1;i<P.length;i++)L.push(L[i-1]+tbDist(P[i],P[i-1]));
  const tot=L[L.length-1];
  return k=>{
    if(!tot)return P[0];
    const d=k*tot;let i=1;while(i<P.length-1&&L[i]<d)i++;
    const seg=L[i]-L[i-1]||1,f=Math.max(0,Math.min(1,(d-L[i-1])/seg));
    return{x:P[i-1].x+(P[i].x-P[i-1].x)*f,y:P[i-1].y+(P[i].y-P[i-1].y)*f};
  };
}

// ============ T5 : MODÈLES ET EXPORT IMAGE ============
// Modèles propres à chaque équipe (est_modele = true, sans match). Un modèle ne garde
// aucun joueur : à l'utilisation, les pions reprennent les joueurs du match par poste.
let tbModeles=[];
async function nouveauTableau(phase){
  let mods=[];
  try{const{data}=await sb.from('tableaux').select('id,titre,format,etat,updated_at').eq('team_id',CT.id).eq('est_modele',true).order('titre');
    mods=(data||[]).filter(m=>(m.format||CT.format)===CT.format);}catch(e){}
  if(!mods.length)return tbCreer(phase);   // pas de modèle (ou hors ligne) : directement
  tbModeles=mods;tbRenderModeles(phase);openModal('modal-tb-nouveau');
}
function tbRenderModeles(phase){
  document.getElementById('tb-nouveau-liste').innerHTML=
    `<button class="bp" style="margin:0 0 12px" onclick="closeModal('modal-tb-nouveau');tbCreer('${phase}')">${phase==='pause'?'Composition du moment':'Composition du match'}</button>
    <div class="tb-sec-t">Ou partir d'un modèle</div>`+
    tbModeles.map(m=>`<div class="tb-mod-l">
      <button class="tb-item" onclick="closeModal('modal-tb-nouveau');tbCreer('${phase}',tbModeles.find(x=>x.id==='${m.id}'))">
        <span class="tb-item-t">★ ${esc(m.titre||'Sans titre')}</span><span class="pill pb">${m.etat?.etapes?.length||1} ét.</span></button>
      <button class="tb-btn" onclick="closeModal('modal-tb-nouveau');openTableau('${m.id}')" aria-label="Modifier le modèle ${esc(m.titre||'')}">✎</button>
      <button class="tb-btn" onclick="tbSupprModele('${m.id}','${phase}')" aria-label="Supprimer le modèle ${esc(m.titre||'')}">🗑</button>
    </div>`).join('');
}
// Copie des étapes du modèle dans le nouveau tableau ; joueurs repris de la composition
function tbAppliquerModele(m){
  const comp=Object.fromEntries(tb.etat.etapes[0].pions.filter(p=>p.camp==='nous').map(p=>[p.num,p.joueur]));
  const etat=JSON.parse(JSON.stringify(m.etat||{}));
  if(!etat.etapes?.length)return;
  etat.etapes.forEach(e=>(e.pions||[]).forEach(p=>{if(p.camp==='nous')p.joueur=comp[p.num]||null;}));
  etat.terrain={...tb.etat.terrain,...(etat.terrain||{})};etat.consignes=etat.consignes||[];
  tb.etat=etat;tb.titre=m.titre||'';
}
async function tbSupprModele(id,phase){
  const m=tbModeles.find(x=>x.id===id);
  if(!await askConfirm(`Supprimer le modèle « ${m?.titre||'Sans titre'} » ?`))return;
  const{error}=await sb.from('tableaux').delete().eq('id',id).eq('est_modele',true);
  if(error)return showToast('Suppression impossible (hors ligne ?)','err');
  tbModeles=tbModeles.filter(x=>x.id!==id);showToast('Modèle supprimé','ok');
  if(tbModeles.length)tbRenderModeles(phase);else closeModal('modal-tb-nouveau');
}
async function tbEnregistrerModele(){
  if(!tb)return;
  const titre=document.getElementById('tb-titre').value.trim();
  if(!titre){showToast('Donne d\'abord un titre au tableau (en haut)','err');document.getElementById('tb-titre').focus();return;}
  const etat=JSON.parse(JSON.stringify(tb.etat));
  etat.etapes.forEach(e=>e.pions.forEach(p=>{if(p.camp==='nous')p.joueur=null;}));   // aucun enfant dans un modèle
  const{error}=await sb.from('tableaux').insert({id:tbUuid(),team_id:tb.team_id,match_id:null,phase:'libre',periode:null,
    titre,format:tb.format,etat,est_modele:true});
  if(error)return showToast('Modèle non enregistré (hors ligne ?)','err');
  showToast(`★ Modèle « ${titre} » enregistré pour l'équipe`,'ok');
}

// Export image (PNG) de l'étape affichée : toujours en portrait, NUMÉROS SEULEMENT (aucun
// prénom ne sort de l'app), puis partage (WhatsApp, mail…) ou téléchargement.
async function tbExporter(){
  if(!tb)return;
  const et=tbEtape(),opt=tb.etat.terrain,S=3,W=300*S,HT=96,H=420*S+HT;
  const cv=document.createElement('canvas');cv.width=W;cv.height=H;
  const g=cv.getContext('2d');
  g.fillStyle='#0a1628';g.fillRect(0,0,W,H);
  // En-tête : titre, équipe / adversaire, étape
  const n=tb.etat.etapes.length;
  g.fillStyle='#fff';g.font='700 34px "DM Sans",sans-serif';g.textBaseline='middle';
  g.fillText((tb.titre||(tb.est_modele?'Modèle':TB_PHASES[tb.phase])).slice(0,40),24,34);
  g.fillStyle='#94a3b8';g.font='500 24px "DM Sans",sans-serif';
  const sous=[CT?.nom,CM&&tb.match_id===CM.id?'vs '+CM.adversaire:'',n>1?`Étape ${tbEtapeIdx+1}/${n}`:''].filter(Boolean).join(' · ');
  g.fillText(sous.slice(0,60),24,72);
  // Terrain : même dessin que le Live
  const img=new Image();
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 420" width="${W}" height="${420*S}"><rect width="300" height="420" fill="#0f1f3d" rx="12"/>${pitchSvgMarkup(false)}</svg>`;
  await new Promise((ok,ko)=>{img.onload=ok;img.onerror=ko;img.src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(svg);}).catch(()=>{});
  try{g.drawImage(img,0,HT,W,420*S);}catch(e){}
  const X=x=>x/100*W,Y=y=>HT+y/100*420*S;
  // Tracés
  for(const t of et.traits){
    const P=t.pts.map(p=>[X(p[0]),Y(p[1])]),c=TB_COUL[t.type]||'#fff';
    g.strokeStyle=c;g.fillStyle=c;g.lineWidth=t.type==='crayon'?7:8;g.lineCap='round';g.lineJoin='round';
    g.setLineDash(t.type==='passe'?[20,18]:[]);
    g.beginPath();P.forEach((p,i)=>i?g.lineTo(p[0],p[1]):g.moveTo(p[0],p[1]));g.stroke();g.setLineDash([]);
    if(t.type!=='crayon'&&P.length>1){
      const [x1,y1]=P[P.length-2],[x2,y2]=P[P.length-1],a=Math.atan2(y2-y1,x2-x1),f=30;
      g.beginPath();g.moveTo(x2,y2);g.lineTo(x2-f*Math.cos(a-0.45),y2-f*Math.sin(a-0.45));g.lineTo(x2-f*Math.cos(a+0.45),y2-f*Math.sin(a+0.45));g.closePath();g.fill();
    }
  }
  // Pions (numéros seulement) puis ballon
  for(const p of et.pions.filter(p=>p.camp==='nous'||opt.adversaires)){
    const nous=p.camp==='nous',r=nous?40:36;
    g.beginPath();g.arc(X(p.x),Y(p.y),r,0,Math.PI*2);
    g.fillStyle=nous?'#00d68f':'#ff5c7c';g.fill();
    g.lineWidth=5;g.strokeStyle=nous?'#fff':'rgba(255,255,255,.7)';g.stroke();
    g.fillStyle=nous?'#0a1628':'#fff';g.font=`700 ${nous?40:34}px "DM Mono",monospace`;g.textAlign='center';
    g.fillText(String(p.num),X(p.x),Y(p.y)+2);g.textAlign='left';
  }
  g.font='60px sans-serif';g.textAlign='center';g.fillText('⚽',X(et.ballon.x),Y(et.ballon.y)+4);g.textAlign='left';
  const blob=await new Promise(r=>cv.toBlob(r,'image/png'));
  if(!blob)return showToast('Image impossible à créer','err');
  const nom=(tb.titre||'tableau').replace(/[^\p{L}\p{N}]+/gu,'-').replace(/^-|-$/g,'').toLowerCase()||'tableau';
  const file=new File([blob],nom+'.png',{type:'image/png'});
  try{
    if(navigator.canShare?.({files:[file]})){await navigator.share({files:[file],title:tb.titre||'Tableau tactique'});return;}
  }catch(e){if(e.name==='AbortError')return;}
  const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=file.name;
  document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(a.href),5000);
  showToast('Image téléchargée','ok');
}
