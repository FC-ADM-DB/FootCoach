// ============ MESSAGERIE ENCADREMENT ↔ PARENTS (A4) ============
// Chargé après parents.js (utilise sb, U, CT, teams, players, esc, showToast, askConfirm,
// isTeamStaff, isParentOnly, paMesEnfants, switchTeam, goPage…).
// Base : supabase/2026-10-27-A4-messages.sql (messages, messages_lus, mes_fils, marquer_lu).
// Par équipe : un groupe (encadrement + tous les parents) et une discussion par enfant
// (ses parents + l'encadrement). Pas de notification push (service worker inchangé) :
// pastille de non-lus sur « Messages », mise à jour toutes les 30 s quand l'app est
// ouverte ; la discussion ouverte se rafraîchit toutes les 5 s.

let msgFils=[],msgOuvert=null,msgListe=[],msgTimer=null,msgBadgeT=null,msgDispo=true;
const msgCle=(team,player)=>team+'|'+(player||'equipe');
const msgHeure=d=>{const x=new Date(d),auj=new Date();
  return x.toDateString()===auj.toDateString()?x.toLocaleTimeString('fr-BE',{hour:'2-digit',minute:'2-digit'})
    :x.toLocaleDateString('fr-BE',{day:'numeric',month:'short'})+' '+x.toLocaleTimeString('fr-BE',{hour:'2-digit',minute:'2-digit'});};

// ------------------------------------------------------------ PASTILLE
async function msgMajBadge(){
  if(!U||!msgDispo)return;
  const{data,error}=await sb.rpc('mes_fils');
  if(error){if(/mes_fils|function/i.test(error.message||''))msgDispo=false;return;}   // SQL A4 pas installé
  msgFils=data||[];
  const n=msgFils.reduce((s,f)=>s+(f.non_lus||0),0);
  const b=document.getElementById('msg-badge');
  [b,document.getElementById('home-msg-badge')].forEach(x=>{if(x){x.textContent=n>99?'99+':n;x.style.display=n?'':'none';}});
  if(document.getElementById('page-messages')?.classList.contains('active')&&!msgOuvert)msgRenderListe(true);
}
function msgDemarrer(){
  clearInterval(msgBadgeT);
  msgMajBadge();
  msgBadgeT=setInterval(()=>{if(document.visibilityState==='visible')msgMajBadge();},30000);
}
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')msgMajBadge();});
const msgLoadApp=loadApp;
loadApp=async function(user){await msgLoadApp(user);msgDemarrer();};
if(U)msgDemarrer();   // déjà connecté avant le chargement de ce fichier

// ------------------------------------------------------------ PAGE
const msgGoPage=goPage;
goPage=function(name){
  if(name!=='messages'){clearInterval(msgTimer);msgTimer=null;msgOuvert=null;}
  msgGoPage(name);
  if(name==='messages'){msgOuvert=null;msgRenderListe();}
};
// Discussions de l'équipe affichée : groupe + enfants (encadrement : enfants ayant des
// parents rattachés ou des messages ; parent : ses enfants)
async function msgRenderListe(sansRecharger){
  const el=document.getElementById('msg-content');if(!el)return;
  document.getElementById('msg-titre').textContent='Messages';
  if(!CT){el.innerHTML=clubVue?choisirEquipeHtml('💬','Chaque équipe a sa conversation avec ses familles','messages'):'<div class="empty"><div class="empty-i">💬</div><div class="empty-t">Choisis une équipe</div></div>';return;}
  if(!msgDispo){el.innerHTML='<div class="empty"><div class="empty-i">💬</div><div class="empty-t">Messagerie bientôt disponible</div></div>';return;}
  if(!sansRecharger){el.innerHTML='<div class="spin"></div>';await msgMajBadge();}
  const staff=isTeamStaff(CT);
  let enfants=[];
  if(staff){
    const{data}=await sb.from('parent_enfants').select('player_id').in('player_id',players.map(p=>p.id));
    const avec=new Set([...(data||[]).map(x=>x.player_id),...msgFils.filter(f=>f.team_id===CT.id&&f.player_id).map(f=>f.player_id)]);
    enfants=players.filter(p=>avec.has(p.id)).map(p=>({id:p.id,titre:`${p.prenom} ${p.nom?p.nom[0]+'.':''}`,sous:'Parents de '+p.prenom}));
  }else if(typeof paMesEnfants==='function'){
    enfants=paMesEnfants().map(e=>({id:e.id,titre:e.prenom,sous:'Avec l\'encadrement'}));
  }
  const fil=p=>msgFils.find(f=>f.team_id===CT.id&&(f.player_id||null)===(p||null));
  const ligne=(p,titre,sous,ic)=>{const f=fil(p);
    return `<div class="msg-fil" onclick="msgOuvrir(${p?`'${p}'`:'null'})">
      <div class="msg-ic">${ic}</div>
      <div style="flex:1;min-width:0"><div class="msg-ft">${esc(titre)}</div>
        <div class="msg-fs">${f?esc((f.dernier_auteur?f.dernier_auteur+' : ':'')+f.dernier_texte):esc(sous)}</div></div>
      <div class="msg-fr">${f?`<span>${msgHeure(f.dernier_le)}</span>`:''}${f?.non_lus?`<b class="msg-nb">${f.non_lus}</b>`:''}</div></div>`;};
  // Non-lus dans une autre équipe
  const autres=teams.filter(t=>t.id!==CT.id).map(t=>({t,n:msgFils.filter(f=>f.team_id===t.id).reduce((s,f)=>s+f.non_lus,0)})).filter(x=>x.n);
  el.innerHTML=autres.map(x=>`<button class="msg-autre" onclick="switchTeam('${x.t.id}');goPage('messages')">💬 ${x.n} nouveau${x.n>1?'x':''} message${x.n>1?'s':''} dans ${esc(x.t.nom)} ›</button>`).join('')+
    ligne(null,'Groupe de l\'équipe','Encadrement et tous les parents de '+CT.nom,'👥')+
    (enfants.length?`<div class="tb-sec-t" style="margin:14px 0 7px">${staff?'Discussions avec les familles':'Mon enfant'}</div>`+enfants.map(e=>ligne(e.id,e.titre,e.sous,'👦')).join('')
        +(staff?'<div class="rs-line" style="margin-top:10px">Les autres familles apparaîtront quand un parent sera rattaché (fiche du joueur → « Inviter un parent »).</div>':'')
      :staff?'<div class="rs-line" style="margin-top:12px">Les discussions privées apparaissent quand des parents sont rattachés (fiche du joueur → « Inviter un parent »).</div>':'');
}

// ------------------------------------------------------------ DISCUSSION
async function msgOuvrir(player){
  msgOuvert={team:CT.id,player:player||null};msgListe=[];
  const el=document.getElementById('msg-content');
  const titre=player?(players.find(p=>p.id===player)?.prenom||(typeof paMesEnfants==='function'?paMesEnfants().find(e=>e.id===player)?.prenom:'')||'Enfant'):'Groupe de l\'équipe';
  document.getElementById('msg-titre').textContent=player?(isTeamStaff(CT)?'Parents de '+titre:titre+' · encadrement'):titre;
  el.innerHTML=`<button class="bsec logo-btn" style="margin-bottom:10px" onclick="msgFermer()">← Discussions</button>
    <div class="msg-liste" id="msg-liste"><div class="spin"></div></div>
    <div class="msg-saisie">
      <textarea class="fi" id="msg-texte" rows="1" maxlength="2000" placeholder="Écrire un message…" oninput="this.style.height='auto';this.style.height=Math.min(this.scrollHeight,120)+'px'"></textarea>
      <button class="bp msg-env" id="msg-env" onclick="msgEnvoyer()" aria-label="Envoyer">➤</button>
    </div>`;
  await msgCharger();
  clearInterval(msgTimer);
  msgTimer=setInterval(()=>{if(document.visibilityState==='visible')msgCharger();},5000);
}
function msgFermer(){clearInterval(msgTimer);msgTimer=null;msgOuvert=null;msgRenderListe();}
async function msgCharger(){
  const o=msgOuvert;if(!o)return;
  let q=sb.from('messages').select('id,auteur,auteur_nom,auteur_role,texte,created_at').eq('team_id',o.team).order('created_at',{ascending:false}).limit(150);
  q=o.player?q.eq('player_id',o.player):q.is('player_id',null);
  const{data,error}=await q;
  if(msgOuvert!==o)return;
  const box=document.getElementById('msg-liste');if(!box)return;
  if(error){box.innerHTML='<div class="rs-warn">Messages indisponibles (hors ligne ?)</div>';return;}
  const liste=(data||[]).reverse();
  const neuf=liste.length!==msgListe.length||liste.at(-1)?.id!==msgListe.at(-1)?.id;
  if(!neuf&&box.querySelector('.msg-b,.msg-vide'))return;
  msgListe=liste;
  const enBas=box.scrollHeight-box.scrollTop-box.clientHeight<60;
  const staff=isTeamStaff(CT);
  let jour='';
  box.innerHTML=liste.length?liste.map(m=>{
    const moi=m.auteur===U.id,d=new Date(m.created_at).toLocaleDateString('fr-BE',{weekday:'long',day:'numeric',month:'long'});
    const sep=d!==jour?(jour=d,`<div class="msg-jour">${d}</div>`):'';
    return sep+`<div class="msg-b${moi?' moi':''}">
      ${moi?'':`<div class="msg-a">${esc(m.auteur_nom||'?')} ${m.auteur_role==='encadrement'?'<span class="msg-role">Encadrement</span>':'<span class="msg-role p">Parent</span>'}</div>`}
      <div class="msg-t">${esc(m.texte)}</div>
      <div class="msg-h">${new Date(m.created_at).toLocaleTimeString('fr-BE',{hour:'2-digit',minute:'2-digit'})}${moi||staff?` · <a href="#" onclick="event.preventDefault();msgSupprimer('${m.id}')">supprimer</a>`:''}</div></div>`;}).join('')
    :'<div class="msg-vide">Aucun message pour l\'instant. Écris le premier !</div>';
  if(enBas||neuf)box.scrollTop=box.scrollHeight;
  // Discussion affichée = lue
  await sb.rpc('marquer_lu',{p_team:o.team,p_player:o.player});
  msgMajBadge();
}
async function msgEnvoyer(){
  const o=msgOuvert,ta=document.getElementById('msg-texte');if(!o||!ta)return;
  const texte=ta.value.trim();if(!texte)return;
  const btn=document.getElementById('msg-env');btn.disabled=true;
  const{error}=await sb.from('messages').insert({team_id:o.team,player_id:o.player,texte});
  btn.disabled=false;
  if(error)return showToast('Message non envoyé (hors ligne ?)','err');
  ta.value='';ta.style.height='auto';msgListe=[];
  await msgCharger();
}
async function msgSupprimer(id){
  if(!await askConfirm('Supprimer ce message ?'))return;
  const{data,error}=await sb.from('messages').delete().eq('id',id).select('id');
  if(error||!data?.length)return showToast('Suppression refusée','err');
  msgListe=[];msgCharger();
}
