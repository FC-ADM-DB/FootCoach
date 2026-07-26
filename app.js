const SB_URL='https://oejcfjthamzgnudofcwi.supabase.co';
const SB_KEY='sb_publishable_nhiVzYaIgNOqYkWyjsz7CQ_pkYNMYBx';
const sb=supabase.createClient(SB_URL,SB_KEY);

// STATE
let U=null,UP=null,teams=[],CT=null,players=[];
let matches=[],CM=null,mdMode=false,kioskMode=false;
let selColor_='#00d68f',selPoste=null,editPid=null;
let convs={},MP={},subLog=[],goals=[];
let chronoOn=false,chronoS=0,halfN=1,chronoIv=null,chronoStartedAt=null,halfDuration=30;
let matchListInterval=null,matchListTick=0,matchDetailInterval=null;
let sNous=0,sEux=0,goalAdv=false;
let isAdmin=false;

// Field positions: percent x,y on terrain (0-100), bottom=our goal, top=adversaire
const FORMATIONS={
  '8v8':[
    {n:1,l:'Gardien',x:50,y:88},
    {n:5,l:'Arr. gauche',x:20,y:72},
    {n:3,l:'Mil. C',x:50,y:68},
    {n:2,l:'Arr. droit',x:80,y:72},
    {n:6,l:'Mil. C',x:50,y:50},
    {n:11,l:'Att. gauche',x:20,y:28},
    {n:9,l:'Att. central',x:50,y:22},
    {n:7,l:'Att. droit',x:80,y:28}
  ],
  '5v5':[
    {n:1,l:'Gardien',x:50,y:88},
    {n:2,l:'Déf. droit',x:75,y:68},
    {n:3,l:'Déf. gauche',x:25,y:68},
    {n:6,l:'Milieu',x:50,y:48},
    {n:9,l:'Attaquant',x:50,y:25}
  ]
};
const POSTES_MAP={'8v8':[{n:1,l:'Gardien'},{n:2,l:'Arr. droit'},{n:3,l:'Mil. C'},{n:5,l:'Arr. gauche'},{n:6,l:'Mil. C'},{n:7,l:'Att. droit'},{n:9,l:'Att. central'},{n:11,l:'Att. gauche'}],'5v5':[{n:1,l:'Gardien'},{n:2,l:'Déf. droit'},{n:3,l:'Déf. gauche'},{n:6,l:'Milieu'},{n:9,l:'Attaquant'}]};
const HALF_MIN={'5v5':25,'8v8':30};
const COLORS=['#00d68f','#4d9fff','#ffb830','#c084fc','#fb923c','#ff5c7c'];
const pCol=p=>COLORS[(p.prenom.charCodeAt(0)||0)%COLORS.length];
const pInit=p=>((p.prenom[0]||'')+(p.nom[0]||'')).toUpperCase();
const fmt=s=>String(Math.floor(s/60)).padStart(2,'0')+':'+String(s%60).padStart(2,'0');
const plabel=(n,f)=>(POSTES_MAP[f||CT?.format||'8v8'].find(p=>p.n===n)?.l)||`#${n}`;

// Current formation positions (modifiable per match)
let fieldPositions=[], selectedBenchId=null;

// ============ AUTH ============
async function init(){const{data:{session}}=await sb.auth.getSession();if(session)await loadApp(session.user);}
async function doLogin(){
  const e=document.getElementById('li-email').value.trim(),p=document.getElementById('li-pwd').value;
  const btn=document.getElementById('btn-li');
  if(!e||!p)return showAErr('Remplis tous les champs.');
  btn.disabled=true;btn.textContent='…';
  try {
    const {data,error} = await sb.auth.signInWithPassword({email:e,password:p});
    if(error) return showAErr(error.message);
    await loadApp(data.user);
  } catch(err) {
    showAErr(err?.message || 'Connexion impossible. Vérifie ta connexion.');
  } finally {
    btn.disabled=false;btn.textContent='Se connecter';
  }
}
async function doRegister(){
  const pn=document.getElementById('rp').value.trim(),nn=document.getElementById('rn').value.trim();
  const e=document.getElementById('re').value.trim(),p=document.getElementById('rpw').value;
  const btn=document.getElementById('btn-reg');
  if(!pn||!nn||!e||!p)return showAErr('Remplis tous les champs.');
  if(p.length<8)return showAErr('8 caractères minimum.');
  btn.disabled=true;btn.textContent='…';
  try {
    const {error} = await sb.auth.signUp({email:e,password:p,options:{data:{prenom:pn,nom:nn}}});
    if(error) return showAErr(error.message);
    const el=document.getElementById('aerr');el.textContent='Compte créé ! Vérifie ton email.';el.style.color='var(--green)';el.classList.add('show');
  } catch(err) {
    showAErr(err?.message || 'Création impossible. Vérifie ta connexion.');
  } finally {
    btn.disabled=false;btn.textContent='Créer mon compte';
  }
}
function showAErr(m){const el=document.getElementById('aerr');el.textContent=m;el.style.color='';el.classList.add('show');}
function toggleForm(){const il=document.getElementById('form-login').style.display!=='none';document.getElementById('form-login').style.display=il?'none':'block';document.getElementById('form-reg').style.display=il?'block':'none';document.getElementById('form-reset').style.display='none';document.getElementById('aerr').classList.remove('show');}
function showResetForm(){document.getElementById('form-login').style.display='none';document.getElementById('form-reg').style.display='none';document.getElementById('form-reset').style.display='block';document.getElementById('aerr').classList.remove('show');}
function showLoginForm(){document.getElementById('form-login').style.display='block';document.getElementById('form-reg').style.display='none';document.getElementById('form-reset').style.display='none';document.getElementById('aerr').classList.remove('show');}
async function doResetPassword(){
  const e=document.getElementById('reset-email').value.trim();
  const btn=document.getElementById('btn-reset');
  if(!e) return showAErr('Email requis.');
  btn.disabled=true;btn.textContent='Envoi...';
  try {
    let response;
    if(typeof sb.auth.resetPasswordForEmail==='function'){
      response=await sb.auth.resetPasswordForEmail({email:e});
    } else if(sb.auth.api && typeof sb.auth.api.resetPasswordForEmail==='function'){
      response=await sb.auth.api.resetPasswordForEmail(e);
    } else {
      return showAErr('Impossible de réinitialiser : méthode manquante.');
    }
    const {data,error}=response;
    if(error) return showAErr(error.message);
    const el=document.getElementById('aerr');el.textContent='Email envoyé ! Vérifie ta boîte mail.';el.style.color='var(--green)';el.classList.add('show');
  } catch(err) {
    showAErr(err?.message || "Impossible d’envoyer l’email. Vérifie ta connexion.");
  } finally {
    btn.disabled=false;btn.textContent='Réinitialiser le mot de passe';
  }
}
async function loadApp(user){U=user;document.getElementById('screen-auth').classList.remove('active');document.getElementById('screen-app').classList.add('active');await loadProfile();await loadTeams();renderHome();}
async function loadProfile(){const{data}=await sb.from('profiles').select('*').eq('id',U.id).single();if(data){UP=data;document.getElementById('wname').textContent=`Bonjour ${data.prenom} !`;}}

// ============ TEAMS ============
async function loadTeams(){
  const{data}=await sb.from('teams').select('*,team_members!inner(profile_id,role)').eq('team_members.profile_id',U.id);
  teams=data||[];renderTeamsList();renderTsw();
  if(teams.length>0&&!CT)selTeam(teams[0]);
  else if(CT){const u=teams.find(t=>t.id===CT.id);if(u)selTeam(u);}
}
function selTeam(t){
  CT = t;
  document.getElementById('hdr-tname').textContent = CT?.nom || 'Choisir une équipe';
  document.getElementById('hdr-dot').style.background = CT?.couleur || '#00d68f';
  renderTsw();
  // refresh team-related data (no await to avoid blocking)
  loadPlayers();
  loadMatches();
}

async function deleteTeam(id,e){
  if(e && e.stopPropagation) e.stopPropagation();
  if(!isAdmin) return showToast('Accès admin requis','err');
  const team = teams.find(t=>t.id===id);
  if(!team) return;
  if(!confirm(`Supprimer l'équipe "${team?.nom}" ? Cette action est irréversible.`)) return;
  await sb.from('team_members').delete().eq('team_id',id);
  await sb.from('teams').delete().eq('id',id);
  if(CT?.id===id) CT=null;
  showToast('Équipe supprimée','ok');
  await loadTeams();
}
function renderTsw(){
  const box=document.getElementById('tsw-box');
  if(!teams.length){box.innerHTML=`<div style="padding:13px;text-align:center;color:var(--text2);font-size:13px">Aucune équipe</div>`;return;}
  box.innerHTML=teams.map(t=>`<div class="topt ${CT?.id===t.id?'active':''}" onclick="switchTeam('${t.id}')">
    <div class="tdot" style="background:${t.couleur}"></div>
    <div style="font-size:13px;font-weight:500;flex:1">${t.nom}</div>
    <div style="font-size:11px;color:var(--text2)">${t.categorie} · ${t.format}</div>
  </div>`).join('');
}
function switchTeam(id){const t=teams.find(t=>t.id===id);if(t){selTeam(t);closeTsw();}}
function openTsw(){renderTsw();document.getElementById('tsw').classList.add('open');}
function closeTsw(e){if(!e||e.target===document.getElementById('tsw'))document.getElementById('tsw').classList.remove('open');}
function openTeamModal(){selColor_='#00d68f';document.getElementById('t-nom').value='';document.querySelectorAll('.copt').forEach(el=>el.classList.toggle('on',el.dataset.c===selColor_));openModal('modal-team');}
function selColor(el){selColor_=el.dataset.c;document.querySelectorAll('.copt').forEach(o=>o.classList.remove('on'));el.classList.add('on');}
async function saveTeam(){
  const nom=document.getElementById('t-nom').value.trim(),cat=document.getElementById('t-cat').value,fmt=document.getElementById('t-fmt').value;
  if(!nom)return showToast('Donne un nom','err');
  const{data:sd}=await sb.from('seasons').select('id').order('debut',{ascending:false}).limit(1).single();
  const{data:t,error}=await sb.from('teams').insert({nom,categorie:cat,format:fmt,couleur:selColor_,saison_id:sd?.id}).select().single();
  if(error)return showToast('Erreur création','err');
  await sb.from('team_members').insert({team_id:t.id,profile_id:U.id,role:'admin'});
  closeModal('modal-team');showToast('Équipe créée !','ok');await loadTeams();selTeam(t);goPage('teams');
}

// ============ PLAYERS ============
async function loadPlayers(){
  if(!CT)return;
  const{data}=await sb.from('players').select('*').eq('team_id',CT.id).eq('actif',true).order('prenom');
  players=data||[];renderPlayers();updateStats();
}
function renderPlayers(){
  const el=document.getElementById('players-list');
  if(!CT){el.innerHTML=`<div class="empty"><div class="empty-i">👥</div><div class="empty-t">Aucune équipe</div></div>`;return;}
  if(!players.length){el.innerHTML=`<div class="empty"><div class="empty-i">👶</div><div class="empty-t">Effectif vide</div><div class="empty-s">Ajoute tes joueurs</div></div>`;return;}
  el.innerHTML=players.map(p=>{
    const col=pCol(p);
    return `<div class="pr-row">
      <div class="pinit" style="background:${col}22;color:${col}">${pInit(p)}</div>
      <div style="flex:1;min-width:0">
        <div class="pn">${p.prenom} ${p.nom}</div>
        <div class="ps">${p.numero_poste?plabel(p.numero_poste):'Poste non défini'}${p.date_naissance?' · '+new Date(p.date_naissance).toLocaleDateString('fr-BE',{day:'2-digit',month:'2-digit',year:'numeric'}):''}</div>
      </div>
      ${p.numero_poste?`<div class="pnum">${p.numero_poste}</div>`:''}
      <div class="bico" onclick="editPlayer('${p.id}',event)" style="margin-right:3px">✎</div>
      <div class="bico" onclick="delPlayer('${p.id}',event)">✕</div>
    </div>`;
  }).join('');
}
function openPlayerModal(){
  if(!CT)return showToast('Sélectionne une équipe','err');
  editPid=null;document.getElementById('mp-title').textContent='Nouveau joueur';document.getElementById('btn-sp').textContent='Ajouter';
  ['p-pn','p-nn','p-dob'].forEach(id=>document.getElementById(id).value='');
  selPoste=null;renderPM();openModal('modal-player');
}
function editPlayer(id,e){
  e.stopPropagation();const p=players.find(pl=>pl.id===id);if(!p)return;
  editPid=id;document.getElementById('mp-title').textContent='Modifier';document.getElementById('btn-sp').textContent='Enregistrer';
  document.getElementById('p-pn').value=p.prenom;document.getElementById('p-nn').value=p.nom;document.getElementById('p-dob').value=p.date_naissance||'';
  selPoste=p.numero_poste||null;renderPM();openModal('modal-player');
}
function clearPoste(){selPoste=null;renderPM();}
function renderPM(){
  document.getElementById('pm-modal').innerHTML=(POSTES_MAP[CT?.format||'8v8']).map(p=>
    `<button class="pb-btn ${selPoste===p.n?'on':''}" onclick="selP(${p.n})"><span class="pbn">${p.n}</span>${p.l}</button>`
  ).join('');
}
function selP(n){selPoste=n;renderPM();}
async function savePlayer(){
  const pn=document.getElementById('p-pn').value.trim(),nn=document.getElementById('p-nn').value.trim(),dob=document.getElementById('p-dob').value;
  if(!pn||!nn)return showToast('Prénom et nom obligatoires','err');
  if(editPid){
    const{error}=await sb.from('players').update({prenom:pn,nom:nn,numero_poste:selPoste||null,date_naissance:dob||null}).eq('id',editPid);
    if(error)return showToast('Erreur','err');
    closeModal('modal-player');showToast(`${pn} modifié !`,'ok');
  } else {
    const{error}=await sb.from('players').insert({team_id:CT.id,prenom:pn,nom:nn,numero_poste:selPoste||null,date_naissance:dob||null});
    if(error)return showToast('Erreur','err');
    closeModal('modal-player');showToast(`${pn} ajouté !`,'ok');
  }
  await loadPlayers();
}
async function delPlayer(id,e){
  e.stopPropagation();const p=players.find(pl=>pl.id===id);
  if(!confirm(`Supprimer ${p?.prenom} ${p?.nom} ?`))return;
  await sb.from('players').update({actif:false}).eq('id',id);
  showToast('Retiré','ok');await loadPlayers();
}

// ============ MATCHES ============
async function loadMatches(){
  if(!CT)return;
  const{data}=await sb.from('matches').select('*').eq('team_id',CT.id).order('date',{ascending:false});
  matches=data||[];renderMatchesList();renderHomeMatches();updateStats();
}
function getMatchChrono(m){
  if(!m.timeline_json)return 0;
  if(m.timeline_json.chronoOn && m.timeline_json.chronoStartedAt){
    return Math.floor((Date.now()-m.timeline_json.chronoStartedAt)/1000);
  }
  return m.timeline_json.chronoS||0;
}
function renderMatchesList(){
  const el=document.getElementById('matches-list');
  if(!matches.length){el.innerHTML=`<div class="empty"><div class="empty-i">📅</div><div class="empty-t">Aucun match</div><div class="empty-s">Crée ton premier match</div></div>`;return;}
  el.innerHTML=matches.map(m=>{
    const d=new Date(m.date).toLocaleDateString('fr-BE',{weekday:'short',day:'2-digit',month:'2-digit'});
    const h=new Date(m.date).toLocaleTimeString('fr-BE',{hour:'2-digit',minute:'2-digit'});
    let sc='–',cls='';
    if(m.score_nous!==null&&m.score_eux!==null){sc=`${m.score_nous}–${m.score_eux}`;cls=m.score_nous>m.score_eux?'win':m.score_nous<m.score_eux?'lose':'draw';}
    const stMap={prevu:'pb Prévu',en_cours:'pg En cours',termine:'pgr Terminé'};
    const[spCls,spTxt]=(stMap[m.statut]||'pgr ?').split(' ');
    const liveInfo = m.statut==='en_cours' ? `<div class="mc-live-info"><span class="mc-chrono">${fmt(getMatchChrono(m))}</span><span class="pill pg" style="font-size:10px;padding:2px 7px">En direct</span></div>` : '';
    return `<div class="mc ${m.statut==='en_cours'?'mc-live':''}" onclick="openMatchDetail('${m.id}')">
      <div class="mc-top"><span class="mc-vs">vs ${m.adversaire}</span><span class="mc-sc ${cls}">${sc}</span></div>
      ${liveInfo}
      <div class="mc-meta"><span>${d} · ${h}</span><span>${m.lieu==='domicile'?'🏠':'✈️'}</span><span class="pill ${spCls}" style="font-size:10px;padding:2px 7px">${spTxt}</span></div>
      ${isAdmin?`<button class="bsec" onclick="deleteMatch('${m.id}', event)" style="margin-top:10px;font-size:12px">Supprimer</button>`:''}
    </div>`;
  }).join('');
}
function renderHomeMatches(){
  const el=document.getElementById('home-next');
  const up=matches.filter(m=>m.statut==='prevu').slice(0,3);
  if(!up.length){el.innerHTML=`<div class="empty" style="padding:22px 0"><div class="empty-i">📅</div><div class="empty-t">Aucun match prévu</div></div>`;return;}
  el.innerHTML=up.map(m=>{
    const d=new Date(m.date).toLocaleDateString('fr-BE',{weekday:'long',day:'2-digit',month:'long'});
    const h=new Date(m.date).toLocaleTimeString('fr-BE',{hour:'2-digit',minute:'2-digit'});
    return `<div class="mc" onclick="goPage('match')"><div class="mc-top"><span class="mc-vs">vs ${m.adversaire}</span><span class="pill pb">Prévu</span></div><div class="mc-meta"><span>${d} · ${h}</span><span>${m.lieu==='domicile'?'🏠':'✈️'}</span></div></div>`;
  }).join('');
}
function openMatchCreateModal(){
  if(!CT)return showToast('Sélectionne une équipe','err');
  document.getElementById('m-adv').value='';
  document.getElementById('m-half').value=HALF_MIN[CT.format]||30;
  const now=new Date();now.setMinutes(0);document.getElementById('m-date').value=now.toISOString().slice(0,16);
  openModal('modal-mc');
}
async function saveMatch(){
  const adv=document.getElementById('m-adv').value.trim();
  const date=document.getElementById('m-date').value;
  const lieu=document.getElementById('m-lieu').value;
  const half=parseInt(document.getElementById('m-half').value)||HALF_MIN[CT.format]||30;
  if(!adv||!date||!half)return showToast('Remplis tous les champs','err');
  const{error}=await sb.from('matches').insert({team_id:CT.id,adversaire:adv,date,lieu,statut:'prevu',timeline_json:{halfDuration:half}});
  if(error)return showToast('Erreur','err');
  closeModal('modal-mc');showToast('Match créé !','ok');await loadMatches();
}

// ============ MATCH DETAIL ============
async function openMatchDetail(id){
  CM=matches.find(m=>m.id===id);if(!CM)return;
  document.getElementById('det-title').textContent=`vs ${CM.adversaire}`;
  document.getElementById('det-sub').textContent=new Date(CM.date).toLocaleDateString('fr-BE',{weekday:'long',day:'2-digit',month:'long',hour:'2-digit',minute:'2-digit'});
  const stMap={prevu:['pb','Prévu'],en_cours:['pg','En cours'],termine:['pgr','Terminé']};
  const[cls,txt]=stMap[CM.statut]||['pgr','?'];
  const sp=document.getElementById('det-status');sp.className='pill '+cls;sp.textContent=txt;
  document.getElementById('match-list-view').style.display='none';
  document.getElementById('match-detail-view').style.display='flex';

  if(CM.statut==='en_cours'&&CM.timeline_json){
    const tl=CM.timeline_json;
    halfDuration=tl.halfDuration||HALF_MIN[CT?.format||'8v8'];
    chronoOn=tl.chronoOn===true;
    chronoStartedAt=tl.chronoStartedAt||null;
    if(chronoOn && chronoStartedAt){
      chronoS=Math.floor((Date.now()-chronoStartedAt)/1000);
    } else {
      chronoS=tl.chronoS||0;
    }
    halfN=tl.halfN||1;
    sNous=CM.score_nous||0;sEux=CM.score_eux||0;
    subLog=tl.subLog||[];goals=tl.goals||[];
    MP=tl.MP||{};
    // ensure bench tracking keys exist
    Object.keys(MP).forEach(k=>{MP[k].benchSeconds=MP[k].benchSeconds||0;MP[k].benchSince=(MP[k].benchSince!==undefined?MP[k].benchSince:null)});
    fieldPositions=tl.fieldPositions||getDefaultPositions();
  } else {
    fieldPositions=getDefaultPositions();
    chronoS=0;halfN=1;
    halfDuration=HALF_MIN[CT?.format||'8v8'];
    sNous=CM.score_nous||0;sEux=CM.score_eux||0;
    subLog=[];goals=[];
    MP={};
  }
  selectedBenchId=null;
  document.getElementById('live-time').textContent=fmt(chronoS);
  document.getElementById('live-half').innerHTML=`${halfN===2?'2ème':'1ère'} mi-temps · <span id="live-half-dur">${halfDuration}</span> min`;
  document.getElementById('live-badge').textContent=halfN===2?'MT 2':'MT 1';
  document.getElementById('live-badge').style.cssText=halfN===2?'background:var(--amber-bg);color:var(--amber);':'';
  document.getElementById('sc-nous').textContent=sNous;
  document.getElementById('sc-eux').textContent=sEux;
  document.getElementById('sc-eux-lbl').textContent=CM.adversaire.slice(0,12);
  document.getElementById('sc-nous-lbl').textContent=CT.nom.slice(0,10);
  document.getElementById('match-delete-btn').style.display=isAdmin?'inline-flex':'none';
  document.getElementById('match-end-btn').style.display=CM.statut==='en_cours'?'inline-flex':'none';
  const chronoBtn=document.getElementById('btn-chrono');
  if(CM.statut==='termine'){
    if(chronoBtn){chronoBtn.textContent='Match terminé';chronoBtn.style.background='var(--bg3)';chronoBtn.disabled=true;}
  } else {
    if(chronoBtn){
      chronoBtn.disabled=false;
      if(!chronoOn){chronoBtn.textContent='▶ Start';chronoBtn.style.background='var(--green)';}
    }
  }
  await loadConvs();
  if(chronoOn){
    const btn=chronoBtn;
    if(btn){btn.textContent='⏸ Pause';btn.style.background='var(--amber)';}
    startChronoInterval();
  }
  if(matchDetailInterval)clearInterval(matchDetailInterval);
  if(CM.statut!=='termine'){
    matchDetailInterval=setInterval(refreshActiveMatch,2000);
  }
  if(CM.statut==='termine') switchTab('res');
  else switchTab('conv');
}
function getDefaultPositions(){
  const fmt=CT?.format||'8v8';
  return (FORMATIONS[fmt]||FORMATIONS['8v8']).map(p=>({...p}));
}
function closeMatchDetail(){
  document.getElementById('match-list-view').style.display='block';
  document.getElementById('match-detail-view').style.display='none';
  if(matchDetailInterval){clearInterval(matchDetailInterval);matchDetailInterval=null;}
  CM=null;chronoS=0;halfN=1;sNous=0;sEux=0;MP={};subLog=[];goals=[];fieldPositions=[];selectedBenchId=null;chronoOn=false;chronoStartedAt=null;clearInterval(chronoIv);chronoIv=null;
}
async function deleteMatch(id,e){
  if(e&&e.stopPropagation) e.stopPropagation();
  if(!isAdmin)return showToast('Accès admin requis','err');
  const m=matches.find(x=>x.id===id);
  if(!m)return;
  if(!confirm(`Supprimer le match vs ${m.adversaire} ?`))return;
  await sb.from('convocations').delete().eq('match_id',id);
  await sb.from('match_players').delete().eq('match_id',id);
  await sb.from('matches').delete().eq('id',id);
  showToast('Match supprimé','ok');
  if(CM?.id===id){closeMatchDetail();}
  await loadMatches();
}

function switchTab(tab){
  ['conv','live','tl','res'].forEach(t=>document.getElementById('tab-'+t).style.display=t===tab?'block':'none');
  document.querySelectorAll('.mtab').forEach((el,i)=>el.classList.toggle('active',['conv','live','tl','res'][i]===tab));
  if(tab==='live'){renderField();}
  if(tab==='tl'){renderTimeline();renderGoals();}
  if(tab==='res')renderResume();
}

function toggleKiosk(){
  if(!CM){showToast('Ouvre un match d\'abord','err');return;}
  kioskMode=!kioskMode;
  const screen=document.getElementById('kiosk-screen');
  if(kioskMode){
    if(CM.statut==='prevu'){showToast('Commence le match pour utiliser le kiosk','err');kioskMode=false;return;}
    screen.style.display='flex';
    renderKiosk();
  } else {
    screen.style.display='none';
  }
}

function renderKiosk(){
  if(!CM)return;
  document.getElementById('kiosk-title').textContent=`${CT?.nom||'Équipe'} vs ${CM.adversaire}`;
  document.getElementById('kiosk-sub').textContent=`${CM.statut==='termine'?'Match terminé':CM.statut==='en_cours'?'Match en cours':'Prévu'}`;
  document.getElementById('kiosk-our-name').textContent=CT?.nom.slice(0,10)||'Nous';
  document.getElementById('kiosk-adversaire').textContent=CM.adversaire;
  document.getElementById('kiosk-score-nous').textContent=sNous;
  document.getElementById('kiosk-score-eux').textContent=sEux;
  document.getElementById('kiosk-meta').innerHTML=`<span>${CM.lieu==='domicile'?'🏠 Domicile':'✈️ Extérieur'}</span><span>Mi-${halfN}</span><span>${fmt(chronoS)}</span>`;
  const el=document.getElementById('kiosk-goals');
  if(!goals.length){el.innerHTML='<div style="color:var(--text2);font-size:13px">Aucun but enregistré</div>';return;}
  el.innerHTML=goals.map(g=>`<div class="but-row"><span class="but-min">${g.min}'</span><div style="flex:1"><span style="font-size:13px;font-weight:600">${g.scorer}</span>${g.assist?`<div style="font-size:11px;color:var(--text2)">↳ ${g.assist}</div>`:''}</div><span class="pill ${g.adv?'pr':'pg'}" style="font-size:10px">${g.adv?'Concédé':'Marqué'}</span></div>`).join('');
}

// ============ CONVOCATIONS ============
async function loadConvs(){
  if(!CM||!players.length)return;
  const{data}=await sb.from('convocations').select('*').eq('match_id',CM.id);
  convs={};(data||[]).forEach(c=>{convs[c.player_id]=c.statut;});
  players.forEach(p=>{if(!convs[p.id])convs[p.id]='inconnu';});
  renderConvs();
}
function renderConvs(){
  const cl=document.getElementById('conv-list');
  cl.innerHTML=players.map(p=>{
    const st=convs[p.id]||'inconnu';
    const presentDisabled = !isAdmin && st!=='present';
    return `<div class="cv">
      <div class="pinit" style="width:30px;height:30px;border-radius:8px;font-size:11px;background:${pCol(p)}22;color:${pCol(p)}">${pInit(p)}</div>
      <div style="flex:1;font-size:13px;font-weight:500">${p.prenom} ${p.nom}</div>
      <div style="display:flex;gap:3px">
        <button class="cvb ${st==='present'?'ap':''} ${presentDisabled?'disabled':''}" onclick="setConv('${p.id}','present')" ${presentDisabled?'disabled':''}>✓</button>
        <button class="cvb ${st==='incertain'?'ai':''}" onclick="setConv('${p.id}','incertain')">?</button>
        <button class="cvb ${st==='absent'?'aa':''}" onclick="setConv('${p.id}','absent')">✗</button>
      </div>
    </div>`;
  }).join('');
  const area=document.getElementById('start-match-area');
  const maxOn=CT?.format==='5v5'?5:8;
  const presents=players.filter(p=>['present','inconnu'].includes(convs[p.id]||'inconnu'));
  if(CM.statut==='termine'){
    area.innerHTML=`<div style="background:var(--bg3);border-radius:var(--rsm);padding:12px;text-align:center;color:var(--text2);font-size:13px">Match terminé — voir l'onglet Résumé</div>`;
  } else if(CM.statut==='en_cours'){
    area.innerHTML=`<button class="bp" onclick="switchTab('live')" style="margin-top:0">▶ Reprendre le match en cours</button>`;
  } else {
    const canStart=presents.length>=maxOn;
    const hasComposition = Object.keys(MP||{}).length>0;
    area.innerHTML=`<div style="background:var(--bg3);border-radius:var(--rsm);padding:10px 12px;margin-bottom:10px;font-size:12px;color:${canStart?'var(--green)':'var(--amber)'}">
      ${presents.length} joueur${presents.length>1?'s':''} disponible${presents.length>1?'s':''} · minimum ${maxOn} requis pour un ${CT?.format||'8v8'}
    </div>
    ${hasComposition?`<button class="bp" onclick="startMatch()" style="margin-top:0" ${canStart?'':'disabled'}>▶ Démarrer le match</button>`:`<button class="bp" onclick="validateComposition()" style="margin-top:0" ${canStart?'':'disabled'}>✓ Valider la composition</button>`}`;
  }
}

function validateComposition(){
  if(!CM) return;
  if(CM.statut==='termine') return showToast('Match terminé — impossible','err');
  const maxOn=CT.format==='5v5'?5:8;
  const presents=players.filter(p=>['present','inconnu'].includes(convs[p.id]||'inconnu'));
  if(presents.length<maxOn) return showToast(`Minimum ${maxOn} joueurs requis`,'err');
  MP={};
  presents.forEach((p,i)=>{
    MP[p.id]={
      onField:i<maxOn,
      playSeconds:0,
      enteredAt:i<maxOn?0:null,
      segments:[],
      poste:p.numero_poste||null,
      benchSeconds:0,
      benchSince: i<maxOn? null : 0
    };
  });
  assignPlayersToPositions(presents.slice(0,maxOn));
  saveState();
  showToast('Composition validée','ok');
  renderConvs();
}
async function setConv(pid,st){
  if(!isAdmin && st==='present'){
    return showToast('Seul un administrateur peut convoquer un joueur.','err');
  }
  convs[pid]=st;renderConvs();
  await sb.from('convocations').upsert({match_id:CM.id,player_id:pid,statut:st},{onConflict:'match_id,player_id'});
}

// ============ START MATCH ============
function startMatch(){
  if(CM.statut==='termine') return showToast('Ce match est terminé, impossible de le redémarrer.','err');
  const maxOn=CT.format==='5v5'?5:8;
  const presents=players.filter(p=>['present','inconnu'].includes(convs[p.id]||'inconnu'));
  if(presents.length<maxOn) return showToast(`Minimum ${maxOn} joueurs requis`,'err');
  MP={};
  presents.forEach((p,i)=>{
    MP[p.id]={
      onField:i<maxOn,
      playSeconds:0,
      enteredAt:i<maxOn?0:null,
      segments:[],
      poste:p.numero_poste||null,
      // bench tracking
      benchSeconds:0,
      benchSince: i<maxOn? null : 0
    };
  });
  sNous=0;sEux=0;chronoS=0;halfN=1;subLog=[];goals=[];
  document.getElementById('sc-nous').textContent='0';document.getElementById('sc-eux').textContent='0';
  document.getElementById('sc-eux-lbl').textContent=CM.adversaire.slice(0,12);
  document.getElementById('sc-nous-lbl').textContent=CT.nom.slice(0,10);
  assignPlayersToPositions(presents.slice(0,maxOn));
  switchTab('live');
  sb.from('matches').update({statut:'en_cours',timeline_json:{halfDuration}}).eq('id',CM.id).then(()=>{
    CM.statut='en_cours';
    CM.timeline_json=CM.timeline_json||{};
    CM.timeline_json.halfDuration=halfDuration;
    const sp=document.getElementById('det-status');sp.className='pill pg';sp.textContent='En cours';
  });
}
function assignPlayersToPositions(onFieldPlayers){
  const fmt=CT?.format||'8v8';
  const formation=FORMATIONS[fmt]||FORMATIONS['8v8'];
  fieldPositions=formation.map((pos,i)=>(
    {...pos,playerId:onFieldPlayers[i]?.id||null}
  ));
}

// ============ CHRONO ============
function startChronoInterval(){
  if(chronoIv)clearInterval(chronoIv);
  chronoIv=setInterval(()=>{
    chronoS++;
    document.getElementById('live-time').textContent=fmt(chronoS);
    if(kioskMode)renderKiosk();
    renderField();
    syncCurrentMatchInMemory();
    if(document.getElementById('match-list-view').style.display==='block')renderMatchesList();
  },1000);
}
function toggleChrono(){
  if(CM?.statut==='termine') return showToast('Ce match est terminé.','err');
  const btn=document.getElementById('btn-chrono');
  document.getElementById('live-half-dur').textContent=halfDuration;
  if(!chronoOn){
    chronoOn=true;chronoStartedAt=Date.now();
    btn.textContent='⏸ Pause';btn.style.background='var(--amber)';
    Object.keys(MP).forEach(id=>{
      const mp=MP[id];
      if(mp.onField&&mp.enteredAt===null)mp.enteredAt=chronoS;
      if(!mp.onField && (mp.benchSince===null || mp.benchSince===undefined)) mp.benchSince=chronoS;
    });
    startChronoInterval();
    saveState();
  } else {
    chronoOn=false;chronoStartedAt=null;
    btn.textContent='▶ Start';btn.style.background='var(--green)';
    clearInterval(chronoIv);freezeTimes();renderField();saveState();
  }
}
function freezeTimes(){
  Object.keys(MP).forEach(id=>{
    const mp=MP[id];
    if(mp.enteredAt!==null&&mp.onField){mp.segments.push({from:mp.enteredAt,to:chronoS,half:halfN});mp.playSeconds+=chronoS-mp.enteredAt;mp.enteredAt=null;}
    if(mp && !mp.onField && mp.benchSince!==null){mp.benchSeconds=(mp.benchSeconds||0)+(chronoS-mp.benchSince);mp.benchSince=null}
  });
}
function switchHalf(){
  if(CM?.statut==='termine') return showToast('Ce match est terminé.','err');
  if(chronoOn)toggleChrono();freezeTimes();halfN=2;chronoS=0;
  document.getElementById('live-time').textContent='00:00';
  document.getElementById('live-half').innerHTML=`2ème mi-temps · <span id="live-half-dur">${halfDuration}</span> min`;
  document.getElementById('live-badge').textContent='MT 2';
  document.getElementById('live-badge').style.cssText='background:var(--amber-bg);color:var(--amber)';
  Object.keys(MP).forEach(id=>{if(MP[id].onField)MP[id].enteredAt=null;});
  renderField();saveState();showToast('2ème mi-temps !','ok');
}
function liveSecs(id){const mp=MP[id];if(!mp)return 0;return mp.playSeconds+(mp.enteredAt!==null?chronoS-mp.enteredAt:0);}
function getBenchSeconds(id){const mp=MP[id];if(!mp)return 0;let secs=(mp.benchSeconds||0);if(mp.benchSince!==null&&mp.benchSince!==undefined)secs+=chronoS-mp.benchSince;return secs;}
function syncCurrentMatchInMemory(){if(!CM)return;const idx=matches.findIndex(m=>m.id===CM.id);if(idx!==-1){matches[idx]={...matches[idx],score_nous:sNous,score_eux:sEux,statut:CM.statut};}}
function chgScore(who,d){
  if(who==='nous'){sNous=Math.max(0,sNous+d);document.getElementById('sc-nous').textContent=sNous;CM&&(CM.score_nous=sNous);} else {sEux=Math.max(0,sEux+d);document.getElementById('sc-eux').textContent=sEux;CM&&(CM.score_eux=sEux);}
  syncCurrentMatchInMemory();saveState();
  if(document.getElementById('tab-res').style.display==='block')renderResume();
}

// ============ TERRAIN DRAG & DROP ============
function renderField(){
  const container=document.getElementById('field-players');
  const svg=document.getElementById('terrain-svg');
  const rect=svg.getBoundingClientRect();
  const W=rect.width,H=rect.height;
  container.innerHTML='';
  container.style.cssText=`position:absolute;top:0;left:0;width:${W}px;height:${H}px;pointer-events:none`;
  const onIds=new Set(fieldPositions.filter(p=>p.playerId).map(p=>p.playerId));
  // compute bench seconds and sort bench players by how long they've been on the side (desc)
  const benchPlayersRaw=players.filter(p=>MP[p.id]&&!onIds.has(p.id)&&MP[p.id].onField===false);
  benchPlayersRaw.forEach(p=>{const mp=MP[p.id];p._benchSecs=(mp?.benchSeconds||0)+((mp?.benchSince!==null && mp?.benchSince!==undefined)?(chronoS-mp.benchSince):0)});
  const benchPlayers=benchPlayersRaw.sort((a,b)=>b._benchSecs - a._benchSecs);

  fieldPositions.forEach((pos,idx)=>{
    const x=W*pos.x/100,y=H*pos.y/100;
    const p=pos.playerId?players.find(pl=>pl.id===pos.playerId):null;
    const bubble=document.createElement('div');
    bubble.className='player-bubble';
    bubble.style.cssText=`left:${x}px;top:${y}px;pointer-events:auto`;
    bubble.dataset.posIdx=idx;
    bubble.dataset.type='field';
    if(p){
      const col=pCol(p);
      bubble.style.borderColor=col;
      bubble.style.background=`${col}15`;
      bubble.innerHTML=`<div style="display:flex;align-items:center;justify-content:space-between;gap:8px"><span style=\"font-size:10px;color:var(--text3);font-family:var(--mono)\">${pos.n}</span><span style=\"font-size:10px;color:${col};font-family:var(--mono)\">${p.numero_poste||''}</span></div>`;
      bubble.innerHTML+=`<div style="font-size:13px;font-weight:600;margin-top:2px">${p.prenom} ${p.nom.charAt(0)}.</div><div style="font-size:10px;color:var(--text2);font-family:var(--mono);margin-top:2px">${fmt(liveSecs(p.id))}</div>`;
    } else {
      bubble.innerHTML=`<span style="color:var(--text3)">#${pos.n} libre</span>`;
      bubble.style.borderStyle='dashed';bubble.style.borderColor='rgba(255,255,255,.2)';bubble.style.background='rgba(255,255,255,.03)';
    }
    bubble.addEventListener('click',()=>handleFieldClick(idx));
    makeDraggable(bubble,idx,'field');
    container.appendChild(bubble);
  });

  const benchArea=document.getElementById('bench-bubbles');
  benchArea.innerHTML='';
  if(!benchPlayers.length){benchArea.innerHTML='<span style="font-size:12px;color:var(--text3)">Aucun remplaçant</span>';return;}
  benchPlayers.forEach(p=>{
    const mp=MP[p.id];
    const bs=(mp?.benchSeconds||0)+((mp?.benchSince!==null && mp?.benchSince!==undefined)?(chronoS-mp.benchSince):0);
    const col=pCol(p);
    const bubble=document.createElement('div');
    bubble.className='player-bubble bench'+(selectedBenchId===p.id?' selected':'');
    bubble.style.cssText=`position:relative;transform:none;cursor:grab;touch-action:none;border-color:${col};background:${col}15;color:${col}`;
    bubble.dataset.playerId=p.id;bubble.dataset.type='bench';
    bubble.innerHTML=`<div style="display:flex;align-items:center;justify-content:space-between;gap:8px"><span style=\"font-weight:600;color:${col}\">${p.prenom} ${p.nom.charAt(0)}.</span><span style=\"font-size:10px;color:var(--text2)\">#${p.numero_poste||'?'}</span></div><span class=\"bench-time\">Sur le banc: ${fmt(bs)}</span>`;
    bubble.addEventListener('click',()=>handleBenchSelect(p.id));
    makeDraggableBench(bubble,p.id);
    benchArea.appendChild(bubble);
  });
}

function makeDraggable(el,posIdx,type){
  let startX,startY,origX,origY,dragging=false,pointerId=null;
  const onMove=e=>{
    if(e.pointerId!==pointerId) return;
    const dx=e.clientX-startX,dy=e.clientY-startY;
    if(!dragging&&Math.hypot(dx,dy)>6){dragging=true;el.classList.add('dragging');}
    if(dragging){
      el.style.left=(origX+dx)+'px';el.style.top=(origY+dy)+'px';
      highlightDropTargets(e.clientX,e.clientY,posIdx);
    }
  };
  const onUp=e=>{
    if(e.pointerId!==pointerId) return;
    window.removeEventListener('pointermove',onMove);
    window.removeEventListener('pointerup',onUp);
    window.removeEventListener('pointercancel',onUp);
    if(dragging){
      const target=findDropTarget(e.clientX,e.clientY,posIdx);
      el.classList.remove('dragging');
      el.style.zIndex=5;
      if(target!==null){doFieldSwap(posIdx,target);} else {renderField();}
    }
    dragging=false;pointerId=null;
  };
  el.addEventListener('pointerdown',e=>{
    if(e.pointerType==='mouse'&&e.button!==0)return;
    e.preventDefault();
    pointerId=e.pointerId;
    startX=e.clientX;startY=e.clientY;
    origX=parseFloat(el.style.left)||0;origY=parseFloat(el.style.top)||0;
    el.style.zIndex=20;el.style.transition='none';
    window.addEventListener('pointermove',onMove);
    window.addEventListener('pointerup',onUp);
    window.addEventListener('pointercancel',onUp);
  });
}

function makeDraggableBench(el,playerId){
  let startX,startY,clone,pointerId=null,dragging=false;
  const onMove=e=>{
    if(e.pointerId!==pointerId) return;
    const dx=e.clientX-startX,dy=e.clientY-startY;
    if(!dragging&&Math.hypot(dx,dy)>6){dragging=true;el.style.opacity='.4';}
    if(dragging&&clone){
      clone.style.left=(e.clientX-40)+'px';clone.style.top=(e.clientY-14)+'px';
      highlightFieldBubbles(e.clientX,e.clientY);
    }
  };
  const onUp=e=>{
    if(e.pointerId!==pointerId) return;
    window.removeEventListener('pointermove',onMove);
    window.removeEventListener('pointerup',onUp);
    window.removeEventListener('pointercancel',onUp);
    if(clone){clone.remove();clone=null;}
    el.style.opacity='1';
    if(dragging){
      const targetIdx=findFieldBubbleAt(e.clientX,e.clientY);
      if(targetIdx!==null){doBenchSwap(playerId,targetIdx);} else {renderField();}
    }
    dragging=false;pointerId=null;
  };
  el.addEventListener('pointerdown',e=>{
    if(e.pointerType==='mouse'&&e.button!==0)return;
    e.preventDefault();
    pointerId=e.pointerId;
    startX=e.clientX;startY=e.clientY;
    clone=el.cloneNode(true);
    clone.style.cssText=`position:fixed;left:${e.clientX-40}px;top:${e.clientY-14}px;z-index:100;opacity:.85;pointer-events:none;transform:none;min-width:60px`;
    document.body.appendChild(clone);
    window.addEventListener('pointermove',onMove);
    window.addEventListener('pointerup',onUp);
    window.addEventListener('pointercancel',onUp);
  });
}

function highlightDropTargets(cx,cy,excludeIdx){
  document.querySelectorAll('.player-bubble[data-type="field"]').forEach((b,i)=>{
    if(i===excludeIdx)return;
    const r=b.getBoundingClientRect();
    const hit=cx>=r.left&&cx<=r.right&&cy>=r.top&&cy<=r.bottom;
    b.classList.toggle('drag-over',hit);
  });
}
function highlightFieldBubbles(cx,cy){
  document.querySelectorAll('.player-bubble[data-type="field"]').forEach(b=>{
    const r=b.getBoundingClientRect();
    b.classList.toggle('drag-over',cx>=r.left&&cx<=r.right&&cy>=r.top&&cy<=r.bottom);
  });
}
function findDropTarget(cx,cy,excludeIdx){
  const bubbles=document.querySelectorAll('.player-bubble[data-type="field"]');
  for(let i=0;i<bubbles.length;i++){
    if(parseInt(bubbles[i].dataset.posIdx)===excludeIdx)continue;
    const r=bubbles[i].getBoundingClientRect();
    if(cx>=r.left&&cx<=r.right&&cy>=r.top&&cy<=r.bottom)return parseInt(bubbles[i].dataset.posIdx);
  }
  return null;
}
function findFieldBubbleAt(cx,cy){
  const bubbles=document.querySelectorAll('.player-bubble[data-type="field"]');
  for(let i=0;i<bubbles.length;i++){
    const r=bubbles[i].getBoundingClientRect();
    if(cx>=r.left&&cx<=r.right&&cy>=r.top&&cy<=r.bottom)return parseInt(bubbles[i].dataset.posIdx);
  }
  return null;
}

function doFieldSwap(idxA,idxB){
  const tmp=fieldPositions[idxA].playerId;
  fieldPositions[idxA].playerId=fieldPositions[idxB].playerId;
  fieldPositions[idxB].playerId=tmp;
  renderField();saveState();showToast('Position échangée','ok');
}

function doBenchSwap(benchPlayerId,fieldIdx){
  const oldId=fieldPositions[fieldIdx].playerId;
  if(oldId){
    const mpOut=MP[oldId];
    const mpIn=MP[benchPlayerId];
    if(!mpIn)return renderField();
    // close out time for player going out
    if(mpOut&&mpOut.enteredAt!==null){
      mpOut.segments.push({from:mpOut.enteredAt,to:chronoS,half:halfN});
      mpOut.playSeconds+=chronoS-mpOut.enteredAt;mpOut.enteredAt=null;
    }
    // mark bench start for player going out
    if(mpOut){mpOut.onField=false;mpOut.benchSince=chronoS}
    // player coming in: accumulate bench seconds and clear benchSince
    if(mpIn){
      mpIn.onField=true;
      if(mpIn.benchSince!==null && mpIn.benchSince!==undefined){mpIn.benchSeconds=(mpIn.benchSeconds||0)+(chronoS-mpIn.benchSince);mpIn.benchSince=null}
      mpIn.enteredAt=chronoS;
    }
    const pOut=players.find(p=>p.id===oldId);
    const pIn=players.find(p=>p.id===benchPlayerId);
    subLog.push({t:chronoS,half:halfN,out:(pOut?.prenom||'?')+' '+(pOut?.nom||''),in:(pIn?.prenom||'?')+' '+(pIn?.nom||'')});
    fieldPositions[fieldIdx].playerId=benchPlayerId;
    saveState();showToast(`${pIn?.prenom} entre pour ${pOut?.prenom}`,'ok');
  } else {
    if(MP[benchPlayerId]){
      // coming from bench into empty slot
      const mpIn=MP[benchPlayerId];
      mpIn.onField=true;
      if(mpIn.benchSince!==null && mpIn.benchSince!==undefined){mpIn.benchSeconds=(mpIn.benchSeconds||0)+(chronoS-mpIn.benchSince);mpIn.benchSince=null}
      mpIn.enteredAt=chronoS;
    }
    fieldPositions[fieldIdx].playerId=benchPlayerId;
    saveState();
  }
  renderField();
}

// ============ GOALS ============
function openGoalModal(adv){
  goalAdv=adv;
  document.getElementById('mg-title').textContent=adv?'But concédé 🔴':'But marqué ⚽';
  const sc=document.getElementById('g-scorer'),as=document.getElementById('g-assist');
  if(adv){sc.innerHTML='<option>Adversaire</option>';as.innerHTML='<option value="">—</option>';} 
  else{
    const opts=players.filter(p=>MP[p.id]).map(p=>`<option value="${p.id}">${p.prenom} ${p.nom}</option>`).join('');
    sc.innerHTML=opts;as.innerHTML='<option value="">Aucun</option>'+opts;
  }
  document.getElementById('g-min').value=Math.floor(chronoS/60)||'';
  openModal('modal-goal');
}
async function saveGoal(){
  const sid=document.getElementById('g-scorer').value;
  const aid=document.getElementById('g-assist').value;
  const t=chronoS;
  const min=Math.floor(t/60);
  const scorer=goalAdv?CM.adversaire:(players.find(p=>p.id===sid)?.prenom+' '+(players.find(p=>p.id===sid)?.nom||'')||'?');
  const assist=aid&&!goalAdv?(players.find(p=>p.id===aid)?.prenom||null):null;
  goals.push({t,min,scorer,assist,adv:goalAdv,half:halfN});
  if(goalAdv){sEux++;document.getElementById('sc-eux').textContent=sEux;} else {sNous++;document.getElementById('sc-nous').textContent=sNous;}
  closeModal('modal-goal');renderGoals();syncCurrentMatchInMemory();saveState();showToast('But enregistré !','ok');
}
function renderGoals(){
  const el=document.getElementById('goals-list');
  if(!goals.length){el.innerHTML='<div style="font-size:12px;color:var(--text3);padding:4px 0">Aucun but enregistré</div>';return;}
  el.innerHTML=goals.map(g=>{const time=g.t!==undefined?fmt(g.t):g.min!==undefined?`${g.min}'`:'--';return `<div class="but-row">
    <span class="but-min">${time}</span>
    <span>${g.adv?'🔴':'⚽'}</span>
    <div style="flex:1"><div style="font-size:13px;font-weight:500">${g.scorer}</div>${g.assist?`<div style="font-size:11px;color:var(--text2)">↳ ${g.assist}</div>`:''}</div>
    <span class="pill ${g.adv?'pr':'pg'}" style="font-size:10px">${g.adv?'Concédé':'Marqué'}</span>
  </div>`}).join('');
}

// ============ END MATCH ============
async function endMatch(){
  if(!confirm('Terminer et sauvegarder le match ?'))return;
  if(chronoOn)toggleChrono();freezeTimes();
  const entries=Object.keys(MP).map(pid=>({match_id:CM.id,player_id:pid,titulaire:!!MP[pid].segments.find(s=>s.from===0),poste_joue:MP[pid].poste,secondes_jeu:MP[pid].playSeconds,segments:MP[pid].segments}));
  await sb.from('match_players').upsert(entries,{onConflict:'match_id,player_id'});
  await sb.from('matches').update({statut:'termine',score_nous:sNous,score_eux:sEux,timeline_json:{chronoS,halfN,halfDuration,subLog,goals,MP,fieldPositions}}).eq('id',CM.id);
  CM.statut='termine';CM.score_nous=sNous;CM.score_eux=sEux;
  const sp=document.getElementById('det-status');sp.className='pill pgr';sp.textContent='Terminé';
  showToast('Match sauvegardé !','ok');await loadMatches();
  switchTab('res');
}
async function saveState(){
  if(!CM)return;
  syncCurrentMatchInMemory();
  await sb.from('matches').update({
    score_nous:sNous,
    score_eux:sEux,
    timeline_json:{chronoS,halfN,halfDuration,chronoOn,chronoStartedAt,subLog,goals,MP,fieldPositions},
    statut:CM.statut==='termine'?'termine':'en_cours'
  }).eq('id',CM.id);
}

// ============ SCORE EDIT (admin) ============
function openScoreEdit(){
  document.getElementById('se-nous').value=CM.score_nous||0;
  document.getElementById('se-eux').value=CM.score_eux||0;
  openModal('modal-score-edit');
}
async function saveScoreEdit(){
  const sn=parseInt(document.getElementById('se-nous').value)||0;
  const se=parseInt(document.getElementById('se-eux').value)||0;
  await sb.from('matches').update({score_nous:sn,score_eux:se}).eq('id',CM.id);
  CM.score_nous=sn;CM.score_eux=se;
  sNous=sn;sEux=se;
  closeModal('modal-score-edit');showToast('Score modifié !','ok');
  await loadMatches();
  if(document.getElementById('tab-res').style.display==='block')renderResume();
}

// ============ TIMELINE ============
async function refreshActiveMatch(){
  if(!CM)return;
  const {data,error}=await sb.from('matches').select('*').eq('id',CM.id).single();
  if(error||!data) return;
  const sameTimeline = data.timeline_json && CM.timeline_json && JSON.stringify(data.timeline_json)===JSON.stringify(CM.timeline_json);
  if(sameTimeline && data.score_nous===CM.score_nous && data.score_eux===CM.score_eux && data.statut===CM.statut) return;
  CM=data;
  if(CM.statut==='en_cours' && CM.timeline_json){
    const tl=CM.timeline_json;
    halfDuration=tl.halfDuration||HALF_MIN[CT?.format||'8v8'];
    chronoOn=tl.chronoOn===true;
    chronoStartedAt=tl.chronoStartedAt||null;
    if(chronoOn && chronoStartedAt){
      chronoS=Math.floor((Date.now()-chronoStartedAt)/1000);
    } else {
      chronoS=tl.chronoS||0;
    }
    halfN=tl.halfN||1;
    sNous=CM.score_nous||0;sEux=CM.score_eux||0;
    subLog=tl.subLog||[];goals=tl.goals||[];
    MP=tl.MP||{};
    Object.keys(MP).forEach(k=>{MP[k].benchSeconds=MP[k].benchSeconds||0;MP[k].benchSince=(MP[k].benchSince!==undefined?MP[k].benchSince:null)});
    fieldPositions=tl.fieldPositions||getDefaultPositions();
    document.getElementById('live-time').textContent=fmt(chronoS);
    document.getElementById('sc-nous').textContent=sNous;
    document.getElementById('sc-eux').textContent=sEux;
    document.getElementById('det-status').className='pill pg';
    document.getElementById('det-status').textContent='En cours';
    document.getElementById('live-half').innerHTML=`${halfN===2?'2ème':'1ère'} mi-temps · <span id="live-half-dur">${halfDuration}</span> min`;
    document.getElementById('live-badge').textContent=halfN===2?'MT 2':'MT 1';
    if(halfN===2) document.getElementById('live-badge').style.cssText='background:var(--amber-bg);color:var(--amber)';
    else document.getElementById('live-badge').style.cssText='';
  }
  if(document.getElementById('tab-conv').style.display==='block') renderConvs();
  if(document.getElementById('tab-live').style.display==='block') {renderField();renderGoals();}
  if(document.getElementById('tab-tl').style.display==='block') renderTimeline();
  if(document.getElementById('tab-res').style.display==='block') renderResume();
  if(CM.statut==='termine') switchTab('res');
}

function renderTimeline(){
  const present=players.filter(p=>MP[p.id]);
  const hS=(halfDuration||HALF_MIN[CT?.format||'8v8'])*60;
  const W=Math.min(380,window.innerWidth-32);
  const lW=54,rowH=24,padT=18,padB=18;
  const tW=W-lW;const svgH=padT+present.length*rowH+padB+10;
  const col=CT?.couleur||'#00d68f';const tc='#8ba4c8';const hX=lW+tW/2;
  const xOf=(s,h)=>lW+(h===2?tW/2:0)+Math.min(s,hS)/hS*(tW/2);
  let svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${svgH}" width="100%">`;
  svg+=`<text x="${lW+tW/4}" y="14" text-anchor="middle" font-size="9" fill="${tc}" font-family="DM Sans,sans-serif">1ère MT</text>`;
  svg+=`<text x="${lW+3*tW/4}" y="14" text-anchor="middle" font-size="9" fill="${tc}" font-family="DM Sans,sans-serif">2ème MT</text>`;
  svg+=`<line x1="${hX}" y1="17" x2="${hX}" y2="${svgH-padB}" stroke="rgba(255,255,255,0.08)" stroke-width="1.5" stroke-dasharray="4,3"/>`;
  [15,30].forEach(m=>[1,2].forEach(h=>{const x=xOf(m*60,h);svg+=`<line x1="${x}" y1="16" x2="${x}" y2="${svgH-padB}" stroke="rgba(255,255,255,0.04)" stroke-width="1"/>`;svg+=`<text x="${x}" y="${svgH-2}" text-anchor="middle" font-size="8" fill="${tc}">${m}'</text>`;}));
  present.forEach((p,i)=>{
    const y=padT+i*rowH;const cy=y+rowH/2;const mp=MP[p.id];
    svg+=`<text x="${lW-4}" y="${cy+4}" text-anchor="end" font-size="10" fill="${tc}" font-family="DM Sans,sans-serif">${p.prenom.slice(0,6)}</text>`;
    svg+=`<rect x="${lW}" y="${y+4}" width="${tW}" height="${rowH-8}" rx="3" fill="rgba(255,255,255,0.02)"/>`;
    (mp.segments||[]).forEach(seg=>{const x1=xOf(seg.from,seg.half),x2=xOf(seg.to,seg.half);svg+=`<rect x="${x1}" y="${y+5}" width="${Math.max(x2-x1,2)}" height="${rowH-10}" rx="3" fill="${col}" opacity="0.85"/>`;});
    if(mp.enteredAt!==null&&mp.onField){const x1=xOf(mp.enteredAt,halfN),x2=xOf(chronoS,halfN);svg+=`<rect x="${x1}" y="${y+5}" width="${Math.max(x2-x1,2)}" height="${rowH-10}" rx="3" fill="${col}" opacity="0.4"/>`;}
    const bench=fmt(getBenchSeconds(p.id));
    svg+=`<text x="${W-2}" y="${cy+4}" text-anchor="end" font-size="8" fill="${tc}" font-family="DM Mono,monospace">${fmt(liveSecs(p.id))}${bench!=='00:00'?' · '+bench:''}</text>`;
  });
  svg+=`</svg>`;
  document.getElementById('tl-chart').innerHTML=svg;
  const logEl=document.getElementById('sub-log');
  if(!subLog.length){logEl.innerHTML='<div style="font-size:12px;color:var(--text3)">Aucun remplacement</div>';return;}
  logEl.innerHTML=subLog.map(e=>`<div style="display:flex;align-items:center;gap:7px;padding:7px 0;border-bottom:1px solid var(--border);font-size:12px">
    <span style="font-size:11px;font-weight:600;color:var(--green);font-family:var(--mono);min-width:28px">${fmt(e.t)}</span>
    <span class="pill pb" style="font-size:10px">MT${e.half}</span>
    <span style="color:var(--red)">↑ ${e.out}</span>
    <span style="color:var(--text3)">→</span>
    <span style="color:var(--green)">↓ ${e.in}</span>
  </div>`).join('');
}

// ============ RESUME ============
function renderResume(){
  const el=document.getElementById('resume-content');
  if(!CM)return;
  const fin=CM.statut==='termine';
  const sn=CM.score_nous??sNous,se=CM.score_eux??sEux;
  const res=sn>se?'✅ Victoire':sn<se?'❌ Défaite':'🤝 Nul';
  let html=`<div class="ro-banner">
    <div style="font-size:14px;font-weight:600">${res}</div>
    <div class="ro-score" style="color:${sn>se?'var(--green)':sn<se?'var(--red)':'var(--amber)'}">${sn} – ${se}</div>
    <div style="font-size:12px;color:var(--text2)">vs ${CM.adversaire}</div>
  </div>`;
  if(isAdmin&&fin){html+=`<button onclick="openScoreEdit()" class="bsec" style="width:100%;margin-bottom:12px;font-size:13px">✎ Modifier le score</button>`;}
  if(goals.length){
    html+=`<div style="margin-bottom:12px"><div style="font-size:11px;color:var(--text2);text-transform:uppercase;letter-spacing:.04em;font-weight:500;margin-bottom:7px">Buts</div>`;
    html+=goals.map(g=>`<div class="but-row"><span class="but-min">${g.min}'</span><span>${g.adv?'🔴':'⚽'}</span><div style="flex:1"><div style="font-size:13px;font-weight:500">${g.scorer}</div>${g.assist?`<div style="font-size:11px;color:var(--text2)">↳ ${g.assist}</div>`:''}</div></div>`).join('');
    html+=`</div>`;
  }
  const mpPlayers=players.filter(p=>MP[p.id]);
  if(mpPlayers.length){
    html+=`<div style="font-size:11px;color:var(--text2);text-transform:uppercase;letter-spacing:.04em;font-weight:500;margin-bottom:7px">Temps de jeu</div>`;
    const sorted=[...mpPlayers].sort((a,b)=>liveSecs(b.id)-liveSecs(a.id));
    const max=Math.max(...sorted.map(p=>liveSecs(p.id)),1);
    html+=sorted.map(p=>{
      const s=liveSecs(p.id), b=getBenchSeconds(p.id), pct=Math.round(s/max*100);
      return `<div style="display:flex;align-items:center;gap:8px;padding:8px 0;border-bottom:1px solid var(--border)">
        <div style="flex:1;min-width:0">
          <div style="font-size:13px;font-weight:600;color:${pCol(p)}">${p.prenom} ${p.nom}</div>
          <div style="font-size:11px;color:var(--text2);margin-top:3px">Jeu: ${fmt(s)} · Banc: ${fmt(b)}</div>
        </div>
        <div style="width:80px;height:6px;background:var(--bg3);border-radius:99px;overflow:hidden;flex-shrink:0"><div style="width:${pct}%;height:100%;background:${CT?.couleur||'#00d68f'};border-radius:99px"></div></div>
      </div>`;
    }).join('');
  }
  el.innerHTML=html;
}

// ============ STATS ============
async function updateStats(){
  document.getElementById('sj').textContent=players.length;
  document.getElementById('sm').textContent=matches.length;
  document.getElementById('sv').textContent=matches.filter(m=>m.score_nous!==null&&m.score_nous>m.score_eux).length;
}
async function renderAdminPage(){
  const panel=document.getElementById('admin-team-members');
  if(!CT){panel.innerHTML=`<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Sélectionne d'abord une équipe</div></div>`;return;}
  if(!isAdmin){panel.innerHTML=`<div class="empty"><div class="empty-i">🔒</div><div class="empty-t">Accès administration réservé aux admins</div></div>`;return;}
  const {data,error}=await sb.from('team_members').select('id,role,profile_id,profiles(id,prenom,nom,email)').eq('team_id',CT.id);
  if(error){panel.innerHTML=`<div class="empty"><div class="empty-i">⚠️</div><div class="empty-t">Impossible de charger les membres</div></div>`;return;}
  if(!data.length){panel.innerHTML=`<div class="empty"><div class="empty-i">👥</div><div class="empty-t">Aucun membre</div><div class="empty-s">Ajoute un membre pour commencer</div></div>`;return;}
  panel.innerHTML=data.map(m=>{
    const profile=m.profiles||{};
    const name=profile.prenom?`${profile.prenom} ${profile.nom}`:'Profil inconnu';
    const email=profile.email||'—';
    return `<div class="admin-row">
      <div class="admin-info"><div class="admin-name">${name}</div><div class="admin-role">${email} · ${m.role==='admin'?'Admin':'Membre'}</div></div>
      <div class="admin-actions">
        ${m.role==='admin'?`<button class="bsec" onclick="changeMemberRole('${m.id}','member')">Rendre membre</button>`:`<button class="bsec" onclick="changeMemberRole('${m.id}','admin')">Promouvoir</button>`}
        <button class="bred" onclick="removeTeamMember('${m.id}')">Retirer</button>
      </div>
    </div>`;
  }).join('');
}
async function openTeamMemberModal(){
  if(!CT)return showToast('Sélectionne une équipe','err');
  if(!isAdmin)return showToast('Accès admin requis','err');
  document.getElementById('tm-email').value='';
  document.getElementById('tm-role').value='member';
  openModal('modal-member');
}
async function saveTeamMember(){
  const email=document.getElementById('tm-email').value.trim().toLowerCase();
  const role=document.getElementById('tm-role').value;
  if(!email)return showToast('Email requis','err');
  const {data:profile,error:pErr}=await sb.from('profiles').select('id,prenom,nom,email').eq('email',email).single();
  if(pErr||!profile)return showToast('Profil introuvable','err');
  const {error}=await sb.from('team_members').upsert({team_id:CT.id,profile_id:profile.id,role},{onConflict:'team_id,profile_id'});
  if(error)return showToast('Impossible d\'inviter','err');
  closeModal('modal-member');
  showToast('Membre invité','ok');
  await renderAdminPage();
}
async function changeMemberRole(memberId,newRole){
  if(!confirm(`Modifier le rôle de ce membre en ${newRole} ?`))return;
  await sb.from('team_members').update({role:newRole}).eq('id',memberId);
  showToast('Rôle mis à jour','ok');
  await renderAdminPage();
}
async function removeTeamMember(memberId){
  if(!confirm('Retirer ce membre de l\'équipe ?'))return;
  await sb.from('team_members').delete().eq('id',memberId);
  showToast('Membre retiré','ok');
  await renderAdminPage();
}
function renderHome(){
  if(UP){
    const h=new Date().getHours(),g=h<12?'Bonjour':h<18?'Bon après-midi':'Bonsoir';
    document.getElementById('wname').textContent=`${g} ${UP.prenom} !`;
    const d=new Date().toLocaleDateString('fr-BE',{weekday:'long',day:'numeric',month:'long'});
    document.getElementById('wsub').textContent=d.charAt(0).toUpperCase()+d.slice(1);
  }
}

function renderStatsPage(){
  const el=document.getElementById('stats-content');
  if(!CT){
    el.innerHTML=`<div class="empty"><div class="empty-i">🏆</div><div class="empty-t">Choisis une équipe</div><div class="empty-s">Les statistiques sont liées à l'équipe sélectionnée</div></div>`;
    return;
  }
  const played=matches.filter(m=>m.statut!=='prevu');
  const wins=played.filter(m=>m.score_nous!=null&&m.score_nous>m.score_eux).length;
  const draws=played.filter(m=>m.score_nous!=null&&m.score_nous===m.score_eux).length;
  const losses=played.filter(m=>m.score_nous!=null&&m.score_nous<m.score_eux).length;
  const gf=played.reduce((sum,m)=>sum+(m.score_nous||0),0);
  const ga=played.reduce((sum,m)=>sum+(m.score_eux||0),0);
  const nextMatch=matches.filter(m=>m.statut==='prevu').sort((a,b)=>new Date(a.date)-new Date(b.date))[0];
  const recent=played.slice().sort((a,b)=>new Date(b.date)-new Date(a.date)).slice(0,4);
  el.innerHTML=`
    <div class="stats-grid">
      <div class="stat-card"><div class="stat-num">${played.length}</div><div class="stat-label">Matchs joués</div></div>
      <div class="stat-card"><div class="stat-num">${wins}</div><div class="stat-label">Victoires</div></div>
      <div class="stat-card"><div class="stat-num">${draws}</div><div class="stat-label">Nuls</div></div>
      <div class="stat-card"><div class="stat-num">${losses}</div><div class="stat-label">Défaites</div></div>
      <div class="stat-card"><div class="stat-num">${gf}</div><div class="stat-label">Buts pour</div></div>
      <div class="stat-card"><div class="stat-num">${ga}</div><div class="stat-label">Buts contre</div></div>
    </div>
    <div class="sh" style="margin-top:8px"><span class="st">Prochain match</span></div>
    ${nextMatch?`<div class="mc"><div class="mc-top"><span class="mc-vs">vs ${nextMatch.adversaire}</span><span class="mc-sc pb">Prévu</span></div><div class="mc-meta"><span>${new Date(nextMatch.date).toLocaleDateString('fr-BE',{weekday:'short',day:'2-digit',month:'2-digit'})} · ${new Date(nextMatch.date).toLocaleTimeString('fr-BE',{hour:'2-digit',minute:'2-digit'})}</span><span>${nextMatch.lieu==='domicile'?'🏠':'✈️'}</span></div></div>`:`<div class="empty"><div class="empty-i">⏳</div><div class="empty-t">Aucun match prévu</div></div>`}
    <div class="sh" style="margin-top:14px"><span class="st">Derniers résultats</span></div>
    <div class="recent-list">
      ${recent.length?recent.map(m=>{
        const d=new Date(m.date);
        const score=m.score_nous!=null?`${m.score_nous}–${m.score_eux}`:'–';
        const outcome=m.score_nous>m.score_eux?'pg':m.score_nous<m.score_eux?'pr':'pb';
        return `<div class="recent-item"><div><div style="font-size:13px;font-weight:600">vs ${m.adversaire}</div><div style="font-size:11px;color:var(--text2)">${d.toLocaleDateString('fr-BE',{day:'2-digit',month:'2-digit'})} · ${m.lieu==='domicile'?'Domicile':'Ext.'}</div></div><div class="result ${outcome}">${score}</div></div>`;
      }).join(''):`<div class="empty"><div class="empty-i">📭</div><div class="empty-t">Pas encore de résultats</div><div class="empty-s">Joue un match pour voir l'historique</div></div>`}
    </div>`;
}

// ============ NAV ============
function goPage(name){
  document.querySelectorAll('.page').forEach(p=>p.classList.remove('active'));
  document.querySelectorAll('.ni').forEach(n=>n.classList.remove('active'));
  document.getElementById('page-'+name)?.classList.add('active');
  document.getElementById('nav-'+name)?.classList.add('active');
  if(matchListInterval){clearInterval(matchListInterval);matchListInterval=null;}
  if(name==='players')loadPlayers();
  if(name==='teams')renderTeamsList();
  if(name==='match'){
    loadMatches();
    matchListTick=0;
    matchListInterval=setInterval(()=>{
      if(document.getElementById('page-match').classList.contains('active')){
        renderMatchesList();
        matchListTick++;
        if(matchListTick%5===0)loadMatches();
      }
    },1000);
  }
  if(name==='admin')renderAdminPage();
  if(name==='stats')loadMatches().then(()=>renderStatsPage());
}
function goAdmin(){
  renderAdminPage();
  goPage('admin');
}
function toggleMode(){
  mdMode=!mdMode;
  const btn=document.getElementById('mode-btn'),b=document.getElementById('md-banner');
  if(mdMode){btn.textContent='🏠 Bureau';btn.classList.add('on');b.style.display='block';}
  else{btn.textContent='⚽ Match';btn.classList.remove('on');b.style.display='none';}
}
function signOut(){sb.auth.signOut().then(()=>{U=null;UP=null;teams=[];CT=null;players=[];matches=[];CM=null;selectedBenchId=null;document.getElementById('screen-app').classList.remove('active');document.getElementById('screen-auth').classList.add('active');document.getElementById('form-login').style.display='block';document.getElementById('form-reg').style.display='none';showToast('Déconnecté','ok');});}
function handleBenchSelect(playerId){selectedBenchId=playerId;showToast('Remplaçant sélectionné','ok');renderField();}
function clearBenchSelection(){selectedBenchId=null;renderField();}
function handleFieldClick(posIdx){const benchPlayers=players.filter(p=>MP[p.id]&&!MP[p.id].onField);if(!benchPlayers.length)return showToast('Aucun remplaçant disponible','err');const playerId=selectedBenchId||benchPlayers[0].id;doBenchSwap(playerId,posIdx);clearBenchSelection();}

// ============ MODALS & TOASTS ============
function openModal(id){document.getElementById(id).classList.add('open');}
function closeModal(id){document.getElementById(id).classList.remove('open');}
let tt;
function showToast(msg,type=''){const t=document.getElementById('toast');t.textContent=msg;t.className=`toast show ${type}`;clearTimeout(tt);tt=setTimeout(()=>t.classList.remove('show'),2800);}
document.querySelectorAll('.mo').forEach(o=>o.addEventListener('click',function(e){if(e.target===this)this.classList.remove('open');}));
document.getElementById('t-cat')?.addEventListener('change',function(){document.getElementById('t-fmt').value=['U8','U9'].includes(this.value)?'5v5':'8v8';});

if('serviceWorker' in navigator)navigator.serviceWorker.register('sw.js').catch(()=>{});
init();
