// ============ ACCÈS PARENTS (A3) ============
// Chargé après app.js (utilise sb, U, CT, teams, matches, players, esc, showToast,
// openModal, closeModal, askConfirm, myTeamRole, isTeamStaff, loadTeams, selTeam…).
// Base : supabase/2026-10-27-A3-parents.sql (parent_enfants, invitations_parent,
// parent_repondre, equipe_prenoms, invitation_info, rejoindre_invitation).
// - Invitation : l'encadrement crée un lien depuis la fiche du joueur ; le parent l'ouvre,
//   crée son compte ou se connecte, et il est rattaché à cet enfant.
// - Parent d'une équipe (sans rôle d'encadrement) : accueil simplifié (ses enfants,
//   prochains matchs avec réponse Présent / Absent / Incertain, derniers résultats) et
//   fiche de match en lecture seule (score, chrono en direct, buteurs, convoqués, temps
//   de jeu de SON enfant). Jamais le Live éditable, l'effectif, les notes ni les tableaux.

const PA_CLE='fc_invitation';
let paEnfants=[],paPrenoms={},paConvs={},paMatch=null,paTimer=null;
const isParentOnly=t=>!!t&&myTeamRole(t)==='parent'&&!isTeamStaff(t);
const paMesEnfants=()=>paEnfants.filter(e=>e.team_id===CT?.id);
const PA_STATUTS=[['present','✓ Présent','ap'],['incertain','? Incertain','ai'],['absent','✗ Absent','aa']];
const PA_LBL={present:'Présent',absent:'Absent',incertain:'Incertain',inconnu:'Pas de réponse'};

// ------------------------------------------------------------ INVITATION (arrivée par le lien)
// Le jeton est gardé sur l'appareil : il survit à la création du compte et à la
// confirmation par email, puis il est utilisé à la première connexion.
(function(){
  const t=new URLSearchParams(location.search).get('invitation');
  if(t){
    try{localStorage.setItem(PA_CLE,t);}catch(e){}
    history.replaceState(null,'',location.pathname);   // lien propre (pas de jeton dans l'historique)
  }
  paBanniereInvitation();
})();
async function paBanniereInvitation(){
  let t=null;try{t=localStorage.getItem(PA_CLE);}catch(e){}
  if(!t)return;
  const box=document.querySelector('#screen-auth .auth-box');if(!box||document.getElementById('pa-inv'))return;
  const{data}=await sb.rpc('invitation_info',{p_token:t});
  const i=Array.isArray(data)?data[0]:data;
  const el=document.createElement('div');el.id='pa-inv';el.className='pa-inv';
  el.innerHTML=!i?'⚠️ Lien d\'invitation inconnu : demande un nouveau lien à l\'entraîneur.'
    :!i.valide?'⚠️ Ce lien d\'invitation a expiré ou a déjà servi : demande un nouveau lien à l\'entraîneur.'
    :`👪 Invitation parent — <b>${esc(i.equipe)}</b>${i.club?' · '+esc(i.club):''}<br><span>Crée ton compte (ou connecte-toi si tu en as déjà un) pour suivre ton enfant.</span>`;
  box.prepend(el);
}
async function paUtiliserInvitation(){
  let t=null;try{t=localStorage.getItem(PA_CLE);}catch(e){}
  if(!t)return null;
  const{data,error}=await sb.rpc('rejoindre_invitation',{p_token:t});
  try{localStorage.removeItem(PA_CLE);}catch(e){}
  document.getElementById('pa-inv')?.remove();
  if(error){showToast(error.message.replace(/^.*?:\s*/,'')||'Invitation impossible','err');return null;}
  const r=Array.isArray(data)?data[0]:data;
  if(r)showToast(`👪 Tu suis maintenant ${r.prenom}`,'ok');
  return r;
}
// Connexion : invitation utilisée AVANT le chargement des équipes, puis l'équipe de
// l'enfant est sélectionnée
const paLoadApp=loadApp;
loadApp=async function(user){
  U=user;
  const r=await paUtiliserInvitation().catch(()=>null);
  await paLoadApp(user);
  await paChargerEnfants();
  if(r){const t=teams.find(x=>x.id===r.equipe_id);if(t){selTeam(t);goPage('home');}}
  paMaj();
};

// ------------------------------------------------------------ MODE PARENT
async function paChargerEnfants(){
  paEnfants=[];
  if(!U)return;
  try{
    const{data}=await sb.from('parent_enfants').select('player_id,players(id,prenom,nom,team_id)').eq('profile_id',U.id);
    paEnfants=(data||[]).filter(x=>x.players).map(x=>({id:x.players.id,prenom:x.players.prenom,nom:x.players.nom,team_id:x.players.team_id}));
  }catch(e){}
}
const paSelTeam=selTeam;
selTeam=function(t){paSelTeam(t);paMaj();};
function paMaj(){
  const on=isParentOnly(CT);
  document.body.classList.toggle('parent-mode',on);
  if(on){paChargerPrenoms();paRenderAccueil();}
}
async function paChargerPrenoms(){
  if(!CT)return;
  const tid=CT.id;
  const{data}=await sb.rpc('equipe_prenoms',{p_team:tid});
  if(CT?.id!==tid)return;
  paPrenoms={};(data||[]).forEach(x=>paPrenoms[x.id]=x.label);
}
// loadMatches() rafraîchit l'accueil : en mode parent, c'est l'accueil parent
const paRenderHomeMatches=renderHomeMatches;
renderHomeMatches=function(){if(isParentOnly(CT))return paRenderAccueil();return paRenderHomeMatches();};
// Ouvrir un match : fiche parent en lecture seule
const paOpenMatchDetail=openMatchDetail;
openMatchDetail=function(id){if(isParentOnly(CT))return paOuvrirMatch(id);return paOpenMatchDetail(id);};

const paDate=m=>{const d=new Date(m.date);
  return d.toLocaleDateString('fr-BE',{weekday:'long',day:'numeric',month:'long'})+' · '+d.toLocaleTimeString('fr-BE',{hour:'2-digit',minute:'2-digit'});};
const paCommence=m=>m.statut!=='prevu'||!!m.timeline_json?.matchStarted;
async function paChargerConvs(ids){
  const enf=paMesEnfants().map(e=>e.id);
  if(!ids.length||!enf.length)return;
  const{data}=await sb.from('convocations').select('match_id,player_id,statut,reponse_parent,reponse_le').in('match_id',ids).in('player_id',enf);
  (data||[]).forEach(c=>paConvs[c.match_id+'|'+c.player_id]=c);
}
function paBoutons(m,e){
  const c=paConvs[m.id+'|'+e.id],st=c?.statut||'inconnu';
  if(paCommence(m))return `<div class="pa-rep"><span class="pa-enf">${esc(e.prenom)}</span><span class="pill pgr">${PA_LBL[st]||st}</span></div>`;
  return `<div class="pa-rep"><span class="pa-enf">${esc(e.prenom)}</span>
    <div class="pa-btns">${PA_STATUTS.map(([v,l,cl])=>`<button class="cvb ${st===v?cl:''}" onclick="event.stopPropagation();paRepondre('${m.id}','${e.id}','${v}')">${l}</button>`).join('')}</div></div>
    ${c?.reponse_parent&&c.reponse_parent!==st?`<div class="pa-note">L'entraîneur a indiqué « ${PA_LBL[st]} » (ta réponse : ${PA_LBL[c.reponse_parent]})</div>`:''}`;
}
async function paRepondre(matchId,playerId,statut){
  const{error}=await sb.rpc('parent_repondre',{p_match:matchId,p_player:playerId,p_statut:statut});
  if(error)return showToast(error.message.replace(/^.*?:\s*/,'')||'Réponse impossible','err');
  paConvs[matchId+'|'+playerId]={...(paConvs[matchId+'|'+playerId]||{}),statut,reponse_parent:statut,reponse_le:new Date().toISOString()};
  showToast('Réponse envoyée à l\'entraîneur','ok');
  paRenderAccueil(true);if(paMatch?.id===matchId)paRenderMatch();
}
// Temps de jeu d'un enfant (temps arrêté au dernier enregistrement du match)
function paTempsJeu(m,pid){
  const tl=m.timeline_json||{},mp=tl.MP?.[pid];if(!mp)return null;
  const chrono=tl.chronoOn&&tl.chronoStartedAt?Math.floor((Date.now()-tl.chronoStartedAt)/1000):(tl.chronoS||0);
  return Math.max(0,(mp.playSeconds||0)+(mp.enteredAt!=null&&!tl.halfTimePending?chrono-mp.enteredAt:0));
}
const paNomBut=g=>g.pid&&paPrenoms[g.pid]?paPrenoms[g.pid]:(g.scorer||'').split(' ').filter(Boolean).map((w,i)=>i?w[0]+'.':w).slice(0,2).join(' ')||'?';
async function paRenderAccueil(sansRecharger){
  const el=document.getElementById('pa-home');if(!el||!isParentOnly(CT))return;
  const enf=paMesEnfants();
  const futurs=matches.filter(m=>m.statut!=='termine').sort((a,b)=>new Date(a.date)-new Date(b.date)).slice(0,5);
  const passes=matches.filter(m=>m.statut==='termine').sort((a,b)=>new Date(b.date)-new Date(a.date)).slice(0,3);
  if(!sansRecharger)await paChargerConvs(futurs.map(m=>m.id));
  el.innerHTML=`
    <div class="sh"><span class="st">${enf.length>1?'Mes enfants':'Mon enfant'}</span></div>
    ${enf.length?`<div class="pa-enfants">${enf.map(e=>`<div class="pa-chip">👦 ${esc(e.prenom)}</div>`).join('')}</div>`
      :'<div class="rs-line" style="margin-bottom:12px">Aucun enfant rattaché dans cette équipe : demande un lien d\'invitation à l\'entraîneur.</div>'}
    <div class="sh"><span class="st">Prochains matchs</span></div>
    ${futurs.length?futurs.map(m=>`<div class="mc" onclick="paOuvrirMatch('${m.id}')">
      <div class="mc-top"><span class="mc-vs">vs ${esc(m.adversaire)}</span>${m.statut==='en_cours'?'<span class="pill pg">● En cours</span>':'<span class="pill pb">Prévu</span>'}</div>
      <div class="mc-meta"><span>${paDate(m)}</span><span>${m.lieu==='domicile'?'🏠 Domicile':'✈️ Extérieur'}</span></div>
      ${enf.map(e=>paBoutons(m,e)).join('')}</div>`).join('')
      :'<div class="empty" style="padding:18px 0"><div class="empty-i">📅</div><div class="empty-t">Aucun match prévu</div></div>'}
    <div class="sh"><span class="st">Derniers résultats</span></div>
    ${passes.length?passes.map(m=>{const sn=m.score_nous,se=m.score_eux;
      const tj=enf.map(e=>{const s=paTempsJeu(m,e.id);return s!=null?`${esc(e.prenom)} : ${Math.round(s/60)} min`:'';}).filter(Boolean).join(' · ');
      return `<div class="mc" onclick="paOuvrirMatch('${m.id}')"><div class="mc-top"><span class="mc-vs">vs ${esc(m.adversaire)}</span>
        <span class="pill ${sn>se?'pg':sn<se?'pr':'pb'}">${sn??'–'} – ${se??'–'}</span></div>
        <div class="mc-meta"><span>${new Date(m.date).toLocaleDateString('fr-BE',{day:'numeric',month:'short'})}</span>${tj?`<span>⏱ ${tj}</span>`:''}</div></div>`;}).join('')
      :'<div class="rs-line">Pas encore de résultat.</div>'}`;
}

// ------------------------------------------------------------ FICHE DE MATCH (lecture seule)
async function paOuvrirMatch(id){
  paMatch=matches.find(m=>m.id===id);if(!paMatch)return;
  await paChargerConvs([id]);
  const{data}=await sb.from('convocations').select('player_id,statut').eq('match_id',id);
  paMatch._convoques=(data||[]).filter(c=>c.statut==='present').map(c=>c.player_id);
  paRenderMatch();openModal('modal-parent-match');
  clearInterval(paTimer);
  // Match en cours : score et chrono rafraîchis (lecture seule, sans les remplacements)
  paTimer=setInterval(async()=>{
    if(!document.getElementById('modal-parent-match')?.classList.contains('open')){clearInterval(paTimer);paTimer=null;return;}
    if(paMatch.statut==='en_cours'||paMatch.timeline_json?.matchStarted&&paMatch.statut!=='termine'){
      const{data:m}=await sb.from('matches').select('*').eq('id',paMatch.id).single();
      if(m){m._convoques=paMatch._convoques;paMatch=m;}
    }
    paRenderMatch();
  },3000);
}
function paRenderMatch(){
  const m=paMatch,el=document.getElementById('pa-match');if(!m||!el)return;
  const tl=m.timeline_json||{},enf=paMesEnfants();
  const live=m.statut!=='termine'&&tl.matchStarted;
  const chrono=tl.chronoOn&&tl.chronoStartedAt?Math.floor((Date.now()-tl.chronoStartedAt)/1000):(tl.chronoS||0);
  const mm=String(Math.floor(chrono/60)).padStart(2,'0')+':'+String(chrono%60).padStart(2,'0');
  const buts=(tl.goals||[]).slice().sort((a,b)=>(a.half||1)-(b.half||1)||(a.t||0)-(b.t||0));
  const sn=m.score_nous??tl.sNous??buts.filter(g=>!g.adv).length,se=m.score_eux??tl.sEux??buts.filter(g=>g.adv).length;
  const conv=(m._convoques||[]).map(id=>paPrenoms[id]).filter(Boolean).sort();
  el.innerHTML=`
    <div class="mt">vs ${esc(m.adversaire)}</div>
    <div class="rs-line" style="margin-bottom:10px">${paDate(m)} · ${m.lieu==='domicile'?'🏠 Domicile':'✈️ Extérieur'}</div>
    ${m.statut!=='prevu'||live?`<div class="pa-score"><div class="pa-sc">${sn} – ${se}</div>
      ${live?`<div class="pa-live">● ${tl.halfTimePending?'Mi-temps':tl.chronoOn?mm+' · MT '+(tl.halfN||1):'Pause · '+mm}</div>`:'<div class="rs-line">Terminé</div>'}</div>`:''}
    ${enf.map(e=>`<div class="pa-bloc">${paBoutons(m,e)}${(()=>{const s=paTempsJeu(m,e.id);return s!=null&&(live||m.statut==='termine')?`<div class="pa-note">⏱ Temps de jeu de ${esc(e.prenom)} : <b>${Math.round(s/60)} min</b></div>`:'';})()}</div>`).join('')}
    ${buts.length?`<div class="tb-sec-t" style="margin-top:12px">Buts</div>${buts.map(g=>`<div class="pa-but">${g.adv?'🔴':'⚽'} <span>${butMin(g)}</span> ${g.adv?esc(m.adversaire):esc(paNomBut(g))}</div>`).join('')}`:''}
    ${conv.length?`<div class="tb-sec-t" style="margin-top:12px">Convoqués (${conv.length})</div><div class="pa-conv">${conv.map(n=>`<span>${esc(n)}</span>`).join('')}</div>`:''}`;
}
function paFermerMatch(){clearInterval(paTimer);paTimer=null;paMatch=null;closeModal('modal-parent-match');}

// ------------------------------------------------------------ CÔTÉ ENCADREMENT : fiche du joueur
// Section « Parents » de la fiche : parents rattachés (retirer) et lien d'invitation.
async function paRenderParentsJoueur(pid){
  const el=document.getElementById('p-parents');if(!el)return;
  if(!pid||!isTeamStaff(CT)){el.innerHTML='';return;}
  el.innerHTML='<div class="spin"></div>';
  const [l,i]=await Promise.all([
    sb.from('parent_enfants').select('id,profile_id,profiles(prenom,nom,email)').eq('player_id',pid),
    sb.from('invitations_parent').select('token,expire_le,utilisations,max_utilisations,revoquee').eq('player_id',pid)]);
  if(l.error){el.innerHTML='';return;}   // SQL A3 pas encore installé
  const actives=(i.data||[]).filter(x=>!x.revoquee&&new Date(x.expire_le)>new Date()&&x.utilisations<x.max_utilisations);
  el.innerHTML=`<label class="fl">Parents</label>
    ${(l.data||[]).map(p=>`<div class="club-mem"><div style="flex:1;min-width:0"><div class="admin-name">${esc(((p.profiles?.prenom||'')+' '+(p.profiles?.nom||'')).trim()||'Parent')}</div><div class="admin-role">${esc(p.profiles?.email||'')}</div></div>
      <button class="bred club-del" onclick="paRetirerParent('${p.id}','${pid}')">Retirer</button></div>`).join('')||'<div class="rs-line" style="margin-bottom:6px">Aucun parent rattaché.</div>'}
    <div style="display:flex;gap:6px;flex-wrap:wrap">
      <button class="bsec logo-btn" onclick="paInviter('${pid}')">🔗 Inviter un parent</button>
      ${actives.length?`<button class="bsec logo-btn" onclick="paRevoquer('${pid}')">Désactiver ${actives.length>1?'les '+actives.length+' liens envoyés':'le lien envoyé'}</button>`:''}
    </div>`;
}
async function paInviter(pid){
  const p=players.find(x=>x.id===pid);
  const{data,error}=await sb.from('invitations_parent').insert({player_id:pid}).select('token').single();
  if(error)return showToast('Lien impossible à créer','err');
  const url=location.origin+location.pathname+'?invitation='+data.token;
  const texte=`Bonjour ! Voici le lien pour suivre ${p?.prenom||'votre enfant'} (${CT?.nom||''}) dans FootLink : convocations, résultats et temps de jeu.`;
  try{if(navigator.share){await navigator.share({title:'Invitation FootLink',text:texte,url});paRenderParentsJoueur(pid);return;}}
  catch(e){if(e.name==='AbortError'){paRenderParentsJoueur(pid);return;}}
  try{await navigator.clipboard.writeText(texte+' '+url);showToast('Lien copié : colle-le dans WhatsApp ou un SMS','ok');}
  catch(e){await askConfirm('Lien d\'invitation (valable 30 jours, 2 parents) :\n\n'+url);}
  paRenderParentsJoueur(pid);
}
async function paRevoquer(pid){
  if(!await askConfirm('Désactiver les liens d\'invitation déjà envoyés pour ce joueur ?'))return;
  await sb.from('invitations_parent').update({revoquee:true}).eq('player_id',pid).eq('revoquee',false);
  showToast('Liens désactivés','ok');paRenderParentsJoueur(pid);
}
async function paRetirerParent(id,pid){
  if(!await askConfirm('Retirer ce parent ? Il ne suivra plus cet enfant.'))return;
  const{data,error}=await sb.from('parent_enfants').delete().eq('id',id).select('id');
  if(error||!data?.length)return showToast('Retrait refusé','err');
  showToast('Parent retiré','ok');paRenderParentsJoueur(pid);
}
const paEditPlayer=editPlayer;
editPlayer=function(id,e){paEditPlayer(id,e);paRenderParentsJoueur(id);};
const paOpenPlayerModal=openPlayerModal;
openPlayerModal=function(){paOpenPlayerModal();paRenderParentsJoueur(null);};

// init() (app.js) a pu se connecter AVANT le chargement de ce fichier : dans ce cas les
// enveloppes ci-dessus n'ont pas servi pour ce premier chargement — on rattrape.
if(U)(async()=>{
  const r=await paUtiliserInvitation().catch(()=>null);
  if(r)await loadTeams();
  await paChargerEnfants();
  if(r){const t=teams.find(x=>x.id===r.equipe_id);if(t){selTeam(t);goPage('home');}}
  paMaj();
})();
