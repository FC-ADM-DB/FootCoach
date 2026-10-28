// ============ TROUVER UN MATCH (phase C1 : annonces entre clubs) ============
// Chargé après app.js (utilise sb, teams, CT, refs, myClubs, isTeamStaff, isClubStaff,
// esc, showToast, askConfirm, openModal/closeModal, formatLabel, HALF_MIN…).
// Les droits sont vérifiés par la base (supabase/2026-10-23-C1-annonces.sql) :
// - consulter : encadrement d'un club VÉRIFIÉ, selon la zone de l'annonce ;
// - entraîneur/délégué : prépare une annonce pour son équipe, l'envoie « à valider » ;
// - CQ/coordinateur : publie, refuse (avec commentaire), clôture.
// Aucune donnée de joueur n'est utilisée ici.

const AN_TYPES={amical:'Match amical',tournoi:'Tournoi',entrainement:'Entraînement commun'};
const AN_LIEUX={domicile:'Chez nous',exterieur:'Chez eux',indifferent:'Chez nous ou chez eux'};
const AN_STATUTS={brouillon:['pgr','Brouillon'],a_valider:['pb','À valider'],refusee:['pr','Refusée'],publiee:['pg','Publiée'],cloturee:['pgr','Clôturée']};
const AN_ZONES={belgique:'Toute la Belgique',province:'Ma province',distance:'Distance maximale',equipes:'Équipes choisies'};

let rsTab='annonces',rsTeamId=null,rsMine=[],rsDonnees=[];
// Filtres de recherche (mémorisés sur l'appareil, simple confort)
const RS_FILTRES0={cat:'',type:'',compat:false,q:'',periode:'',date:'',jsem:'',hDe:'',hA:'',lieu:'',format:'',niveau:'',km:'',tri:'date'};
let rsFiltres={...RS_FILTRES0};
try{Object.assign(rsFiltres,JSON.parse(localStorage.getItem('fc_rs_filtres')||'{}'));}catch(e){}
const rsGarderFiltres=()=>{try{localStorage.setItem('fc_rs_filtres',JSON.stringify(rsFiltres));}catch(e){}};
let rsAnnonces={};   // annonces affichées, par id (formulaire de proposition, propositions.js)
// Formulaire d'annonce en cours d'édition
let anEdit=null,anCreneaux=[],anCats=new Set(),anNivs=new Set(),anCibles=new Set(),anEquipesReseau=null;

// Équipes que j'encadre ET rattachées à un club (seules elles peuvent publier)
const rsStaffTeams=()=>teams.filter(t=>t.club_id&&isTeamStaff(t));
const rsTeam=id=>teams.find(t=>t.id===id);
const fmtJour=j=>{const d=new Date(j+'T00:00');return d.toLocaleDateString('fr-BE',{weekday:'short',day:'numeric',month:'short'});};
const fmtHeure=h=>h?String(h).slice(0,5):'';
const creneauTxt=c=>`${fmtJour(c.jour)}${c.debut||c.heure_debut?' '+fmtHeure(c.debut||c.heure_debut):''}${c.fin||c.heure_fin?'–'+fmtHeure(c.fin||c.heure_fin):''}`;
const nivLabel=id=>refs.niveaux.find(n=>n.id===id)?.libelle||'';
const todayIso=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;};

async function renderReseauPage(){
  const el=document.getElementById('reseau-content');
  const st=rsStaffTeams();
  if(!st.length){el.innerHTML=`<div class="empty"><div class="empty-i">🤝</div><div class="empty-t">Réservé à l'encadrement</div><div class="empty-s">Il faut encadrer une équipe rattachée à un club (page Mon club).</div></div>`;return;}
  if(!rsTeamId||!st.some(t=>t.id===rsTeamId))rsTeamId=(st.find(t=>t.id===CT?.id)||st[0]).id;
  const canVal=myClubs.length>0;
  // Annonces de mes équipes / de mon club (pour « Mes annonces » et le compteur « À valider »)
  const{data}=await sb.from('annonces').select('*,annonce_creneaux(*)').in('team_id',st.map(t=>t.id)).order('created_at',{ascending:false});
  rsMine=data||[];
  const nVal=rsMine.filter(a=>a.statut==='a_valider'&&isClubStaff(a.club_id)).length;
  const tab=(k,l)=>`<button class="${rsTab===k?'on':''}" onclick="rsTab='${k}';renderReseauPage()">${l}</button>`;
  const nProp=typeof prListe!=='undefined'?prListe.filter(prAFaire).length:0;
  el.innerHTML=`<div class="rs-tabs">${tab('annonces','Annonces')}${tab('propositions',`Propositions${nProp?` <span class="rs-count">${nProp}</span>`:''}`)}${tab('mine','Mes annonces')}${canVal?tab('valider',`À valider${nVal?` <span class="rs-count">${nVal}</span>`:''}`):''}</div><div id="rs-body"><div class="spin"></div></div>`;
  if(rsTab==='annonces')return rsRenderAnnonces();
  if(rsTab==='propositions')return typeof prRenderListe==='function'?prRenderListe():null;
  rsRenderMine(rsTab==='valider');
}

// ------------------------------------------------------------ ONGLET « ANNONCES »
async function rsRenderAnnonces(){
  const body=document.getElementById('rs-body');
  const st=rsStaffTeams(),T=rsTeam(rsTeamId);
  const verifie=!!T?.clubs?.verifie;
  const opt=(v,l,cur)=>`<option value="${esc(v)}" ${String(v)===String(cur)?'selected':''}>${esc(l)}</option>`;
  const sel=(k,items,tout)=>`<select class="sel" onchange="rsFiltre('${k}',this.value)">${opt('',tout,rsFiltres[k])}${items.map(([v,l])=>opt(v,l,rsFiltres[k])).join('')}</select>`;
  const head=`<div class="rs-filters">
    <label class="rs-lbl">Pour l'équipe<select class="sel" onchange="rsTeamId=this.value;rsRenderAnnonces()">${st.map(t=>opt(t.id,t.nom+' ('+t.categorie+')',rsTeamId)).join('')}</select></label>
    <input class="fi" type="search" placeholder="🔎 Club ou équipe…" value="${esc(rsFiltres.q)}" oninput="rsFiltres.q=this.value;rsGarderFiltres();rsFiltrer()">
    <div class="frow">
      ${sel('periode',[['7','7 prochains jours'],['we','Prochain week-end'],['15','2 prochaines semaines'],['30','30 prochains jours'],['date','Date précise…']],'Toutes les dates')}
      ${sel('jsem',[['6','Samedi'],['0','Dimanche'],['3','Mercredi'],['sem','En semaine (lun–ven)']],'Tous les jours')}
    </div>
    ${rsFiltres.periode==='date'?`<input class="fi" type="date" min="${todayIso()}" value="${esc(rsFiltres.date)}" onchange="rsFiltre('date',this.value)">`:''}
    <div class="rs-heures"><span>Entre</span><input class="fi" type="time" value="${esc(rsFiltres.hDe)}" onchange="rsFiltre('hDe',this.value)" aria-label="Heure de début"><span>et</span><input class="fi" type="time" value="${esc(rsFiltres.hA)}" onchange="rsFiltre('hA',this.value)" aria-label="Heure de fin">${rsFiltres.hDe||rsFiltres.hA?`<button class="bsec" onclick="rsFiltres.hDe=rsFiltres.hA='';rsGarderFiltres();rsRenderAnnonces()" aria-label="Effacer l'heure">✕</button>`:''}</div>
    <details class="rs-plus" ${rsNbFiltres()?'open':''}><summary>Plus de filtres<span id="rs-nbf"></span></summary>
      <div class="rs-plus-in">
        <div class="frow">
          ${sel('cat',refs.categories.map(c=>[c.code,c.libelle]),'Toutes catégories')}
          ${sel('type',Object.entries(AN_TYPES),'Tous types')}
        </div>
        <div class="frow">
          ${sel('lieu',[['chez_nous','Chez nous'],['chez_eux','Chez eux']],'Lieu : peu importe')}
          ${sel('format',refs.formats.map(f=>[f.code,f.libelle]),'Tous formats')}
        </div>
        <div class="frow">
          ${sel('niveau',refs.niveaux.map(n=>[n.id,n.libelle]),'Tous niveaux')}
          ${sel('km',[['10','≤ 10 km'],['20','≤ 20 km'],['30','≤ 30 km'],['50','≤ 50 km'],['100','≤ 100 km']],'Toutes distances')}
        </div>
        <label class="tm-new-toggle" style="margin:0"><input type="checkbox" ${rsFiltres.compat?'checked':''} onchange="rsFiltre('compat',this.checked)"> Compatibles avec ${esc(T?.nom||'mon équipe')} seulement</label>
        <button class="bsec" style="min-height:38px;font-size:13px" onclick="rsFiltres={...RS_FILTRES0};rsGarderFiltres();rsRenderAnnonces()">Réinitialiser les filtres</button>
      </div></details>
    <div class="rs-tri"><span id="rs-nb"></span>
      <select class="sel" onchange="rsFiltre('tri',this.value)">${opt('date','Trier : date la plus proche',rsFiltres.tri)}${opt('distance','Trier : distance',rsFiltres.tri)}${opt('club','Trier : club (A–Z)',rsFiltres.tri)}</select></div>
  </div>`;
  if(!verifie){body.innerHTML=head+`<div class="empty"><div class="empty-i">⏳</div><div class="empty-t">Club pas encore vérifié</div><div class="empty-s">Le club doit être vérifié par FootCoach pour voir et publier des annonces.</div></div>`;return;}
  body.innerHTML=head+'<div id="rs-list"><div class="spin"></div></div>';
  const{data,error}=await sb.rpc('annonces_reseau',{p_team:rsTeamId});
  if(error){document.getElementById('rs-list').innerHTML=`<div class="empty"><div class="empty-i">⚠️</div><div class="empty-t">Annonces indisponibles</div></div>`;return;}
  rsDonnees=(data||[]).filter(a=>!a.mon_club);
  rsFiltrer();
}
// Depuis le calendrier du club : annonces pour cette équipe, ce jour-là, dans la tranche
function rsChercherPour(teamId,jour,hDe,hA){
  rsTeamId=teamId;rsTab='annonces';
  Object.assign(rsFiltres,{periode:'date',date:jour,jsem:'',hDe:hDe||'',hA:hA||'',q:''});
  rsGarderFiltres();goPage('reseau');
}
// Changement d'un filtre à liste (la période change l'en-tête : champ « date précise »)
function rsFiltre(k,v){rsFiltres[k]=v;rsGarderFiltres();if(k==='periode')rsRenderAnnonces();else rsFiltrer();}
const rsNbFiltres=()=>['cat','type','lieu','format','niveau','km','compat'].filter(k=>rsFiltres[k]).length;
const rsIso=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
// Créneau retenu par les filtres de date : libre, pas passé, dans la période, bon jour
function rsCrOk(c){
  const auj=todayIso();
  if(c.jour<auj||c.statut!=='libre')return false;
  const f=rsFiltres,j=new Date(c.jour+'T12:00').getDay();
  const dansJours=n=>{const x=new Date();x.setDate(x.getDate()+n);return c.jour<=rsIso(x);};
  if(f.periode==='7'&&!dansJours(7))return false;
  if(f.periode==='15'&&!dansJours(14))return false;
  if(f.periode==='30'&&!dansJours(30))return false;
  if(f.periode==='we'){   // samedi + dimanche qui viennent (ou celui en cours)
    const x=new Date(),sam=new Date(x);sam.setDate(x.getDate()+(x.getDay()===0?-1:6-x.getDay()));
    const dim=new Date(sam);dim.setDate(sam.getDate()+1);
    if(c.jour<rsIso(sam)||c.jour>rsIso(dim))return false;}
  if(f.periode==='date'&&f.date&&c.jour!==f.date)return false;
  if(f.jsem==='sem'?(j===0||j===6):(f.jsem!==''&&j!==+f.jsem))return false;
  // Tranche horaire : le créneau doit la chevaucher (créneau sans heure = gardé, à discuter)
  const hd=fmtHeure(c.heure_debut),hf=fmtHeure(c.heure_fin)||hd;
  if(f.hDe&&hf&&hf<f.hDe)return false;
  if(f.hA&&hd&&hd>f.hA)return false;
  return true;
}
function rsFiltrer(){
  const el=document.getElementById('rs-list');if(!el)return;
  const T=rsTeam(rsTeamId),f=rsFiltres,q=(f.q||'').trim().toLowerCase();
  const dateFiltree=!!(f.periode||f.jsem||f.hDe||f.hA);
  let list=rsDonnees
    // annonces sans créneau à venir (ou hors période / jour choisis) : masquées
    .filter(a=>a.creneaux.length?a.creneaux.some(rsCrOk):!dateFiltree)
    .filter(a=>!q||(a.club_nom+' '+a.equipe+' '+a.equipe_categorie+' '+(a.province||'')).toLowerCase().includes(q))
    .filter(a=>!f.type||a.type===f.type)
    .filter(a=>!f.cat||!a.categories.length||a.categories.includes(f.cat))
    // lieu vu de mon côté : « chez nous » = l'annonceur accepte de se déplacer
    .filter(a=>!f.lieu||a.lieu==='indifferent'||a.lieu===(f.lieu==='chez_nous'?'exterieur':'domicile'))
    .filter(a=>!f.format||!a.format||a.format===f.format)
    .filter(a=>!f.niveau||a.equipe_niveau===+f.niveau)
    .filter(a=>!f.km||(a.distance_club!=null&&+a.distance_club<=+f.km));
  list=list.map(a=>({...a,raisons:rsRaisons(a,T),prochain:a.creneaux.filter(rsCrOk).map(c=>c.jour+(c.heure_debut||'')).sort()[0]||'9999'}));
  if(f.compat)list=list.filter(a=>!a.raisons.length);
  list.sort(f.tri==='distance'?(x,y)=>(x.distance_club??1e9)-(y.distance_club??1e9)
    :f.tri==='club'?(x,y)=>x.club_nom.localeCompare(y.club_nom):(x,y)=>x.prochain.localeCompare(y.prochain));
  const nb=document.getElementById('rs-nb');if(nb)nb.textContent=`${list.length} annonce${list.length>1?'s':''}`;
  const nf=document.getElementById('rs-nbf');if(nf){const n=rsNbFiltres();nf.innerHTML=n?` <span class="rs-count">${n}</span>`:'';}
  el.innerHTML=list.length?list.map(a=>rsCarte(a,T)).join('')
    :rsDonnees.length?`<div class="empty"><div class="empty-i">🔎</div><div class="empty-t">Aucune annonce avec ces filtres</div><div class="empty-s">Élargis la période ou réinitialise les filtres.</div></div>`
    :`<div class="empty"><div class="empty-i">🔎</div><div class="empty-t">Aucune annonce pour l'instant</div><div class="empty-s">Publie la tienne dans « Mes annonces ».</div></div>`;
}
// Pourquoi une annonce ne correspond pas à mon équipe (aucune règle imposée :
// l'annonce reste visible avec la raison, le coordinateur décide)
function rsRaisons(a,T){
  const r=[];if(!T)return r;
  if(a.categories.length&&!a.categories.includes(T.categorie))r.push(`catégorie ${T.categorie} non demandée (${a.categories.join(', ')})`);
  if(a.format&&a.format!==T.format)r.push(`format ${formatLabel(a.format)} (ton équipe : ${formatLabel(T.format)})`);
  if(a.niveaux.length&&!a.niveaux.includes(T.niveau_id))r.push(`niveau demandé : ${a.niveaux.map(nivLabel).join(', ')}`);
  return r;
}
function rsCarte(a,T){
  const cr=a.creneaux.filter(rsCrOk);   // seulement les créneaux qui correspondent aux filtres
  const logo=safeLogo({logo:a.club_logo});
  rsAnnonces[a.id]=a;
  return `<div class="card rs-card">
    <div class="rs-top"><div class="rs-logo">${logo?`<img class="team-logo" src="${logo}" alt="">`:'🏟'}</div>
      <div style="flex:1;min-width:0"><div class="rs-club">${esc(a.club_nom)}</div><div class="rs-sub">${esc([a.province,a.distance_club!=null?'à '+a.distance_club+' km':''].filter(Boolean).join(' · '))}</div></div>
      <span class="pill pb">${esc(AN_TYPES[a.type]||a.type)}</span></div>
    <div class="rs-team">${esc(a.equipe)} · ${esc(a.equipe_categorie)}${a.equipe_niveau?' · '+esc(nivLabel(a.equipe_niveau)):''}</div>
    <div class="rs-line">📍 ${esc(AN_LIEUX[a.lieu])}${a.format?' · '+esc(formatLabel(a.format)):''}${a.duree_mt?` · 2×${a.duree_mt} min`:''}</div>
    <div class="rs-line">🎯 Catégories : ${esc(a.categories.join(', ')||'toutes')} · Niveaux : ${esc(a.niveaux.map(nivLabel).join(', ')||'tous')}</div>
    ${cr.length?`<div class="rs-chips">${cr.map(c=>`<span>${esc(creneauTxt(c))}</span>`).join('')}</div>`:''}
    ${a.message?`<div class="rs-msg">${esc(a.message)}</div>`:''}
    ${a.raisons.length?`<div class="rs-warn">⚠️ Hors critères pour ${esc(T.nom)} : ${esc(a.raisons.join(' ; '))}</div>`:`<div class="rs-ok">✓ Compatible avec ${esc(T?.nom||'ton équipe')}</div>`}
    <button class="bp rs-prop" onclick="prOuvrirForm('${a.id}')">🤝 Proposer un match</button>
  </div>`;
}

// ------------------------------------------------------------ « MES ANNONCES » / « À VALIDER »
function rsRenderMine(validation){
  const body=document.getElementById('rs-body');
  let list=rsMine;
  if(validation)list=list.filter(a=>a.statut==='a_valider'&&isClubStaff(a.club_id));
  const btn=validation?'':`<button class="bp" style="margin:0 0 12px" onclick="anOpen(null)">+ Nouvelle annonce</button>`;
  if(!list.length){body.innerHTML=btn+`<div class="empty"><div class="empty-i">${validation?'✅':'📣'}</div><div class="empty-t">${validation?'Rien à valider':'Aucune annonce'}</div><div class="empty-s">${validation?'Les annonces préparées par les entraîneurs apparaîtront ici.':'Publie tes créneaux libres pour trouver des adversaires.'}</div></div>`;return;}
  body.innerHTML=btn+list.map(a=>{
    const t=rsTeam(a.team_id),club=isClubStaff(a.club_id);
    const [cls,lbl]=AN_STATUTS[a.statut]||['pgr',a.statut];
    const cr=(a.annonce_creneaux||[]).sort((x,y)=>(x.jour+(x.heure_debut||'')).localeCompare(y.jour+(y.heure_debut||'')));
    const acts=[];
    const ed=club||['brouillon','a_valider','refusee'].includes(a.statut);
    if(ed&&a.statut!=='cloturee')acts.push(`<button class="bsec" onclick="anOpen('${a.id}')">Modifier</button>`);
    if(!club&&['brouillon','refusee'].includes(a.statut))acts.push(`<button class="bp rs-act" onclick="anStatut('${a.id}','a_valider')">Envoyer au coordinateur</button>`);
    if(club&&['brouillon','a_valider','refusee'].includes(a.statut))acts.push(`<button class="bp rs-act" onclick="anStatut('${a.id}','publiee')">Publier</button>`);
    if(club&&a.statut==='a_valider')acts.push(`<button class="bred" onclick="anRefus('${a.id}')">Refuser</button>`);
    if(club&&a.statut==='publiee')acts.push(`<button class="bsec" onclick="anStatut('${a.id}','cloturee')">Clôturer</button>`);
    if(club||['brouillon','a_valider','refusee'].includes(a.statut))acts.push(`<button class="bred" onclick="anSuppr('${a.id}')">Supprimer</button>`);
    return `<div class="card rs-card">
      <div class="rs-top"><div style="flex:1;min-width:0"><div class="rs-club">${esc(t?.nom||'Équipe')} · ${esc(AN_TYPES[a.type]||a.type)}</div>
        <div class="rs-sub">${esc(AN_ZONES[a.zone])}${a.zone==='distance'?' '+a.distance_km+' km':''} · ${esc(AN_LIEUX[a.lieu])}</div></div>
        <span class="pill ${cls}">${lbl}</span></div>
      ${cr.length?`<div class="rs-chips">${cr.map(c=>`<span class="${c.statut==='pris'?'pris':''}">${esc(creneauTxt(c))}</span>`).join('')}</div>`:'<div class="rs-line" style="color:var(--amber)">Aucun créneau</div>'}
      ${a.statut==='refusee'&&a.commentaire_validation?`<div class="rs-warn">Refusée par le coordinateur : ${esc(a.commentaire_validation)}</div>`:''}
      <div class="rs-acts">${acts.join('')}</div>
    </div>`;}).join('');
}
async function anStatut(id,statut){
  const msg={a_valider:'Envoyer cette annonce au coordinateur pour validation ?',publiee:'Publier cette annonce ? Elle sera visible des autres clubs selon sa zone.',cloturee:'Clôturer cette annonce ? Elle ne sera plus visible.'}[statut];
  if(msg&&!await askConfirm(msg))return;
  const upd={statut};if(statut!=='refusee')upd.commentaire_validation=null;
  const{data,error}=await sb.from('annonces').update(upd).eq('id',id).select();
  if(error)return showToast(error.message||'Action refusée','err');
  if(!data?.length)return showToast('Action refusée','err');
  showToast({a_valider:'Envoyée au coordinateur',publiee:'Annonce publiée',cloturee:'Annonce clôturée'}[statut]||'OK','ok');
  renderReseauPage();
}
let anRefusId=null;
function anRefus(id){anRefusId=id;document.getElementById('refus-txt').value='';openModal('modal-refus');}
async function anRefusOk(){
  const c=document.getElementById('refus-txt').value.trim();
  if(!c)return showToast('Indique la raison du refus à l\'entraîneur','err');
  const{data,error}=await sb.from('annonces').update({statut:'refusee',commentaire_validation:c}).eq('id',anRefusId).select();
  if(error||!data?.length)return showToast(error?.message||'Refus impossible','err');
  closeModal('modal-refus');showToast('Annonce refusée, l\'entraîneur verra ton commentaire','ok');renderReseauPage();
}
async function anSuppr(id){
  if(!await askConfirm('Supprimer définitivement cette annonce ?'))return;
  const{data,error}=await sb.from('annonces').delete().eq('id',id).select();
  if(error||!data?.length)return showToast(error?.message||'Suppression refusée','err');
  showToast('Annonce supprimée','ok');renderReseauPage();
}

// ------------------------------------------------------------ FORMULAIRE D'ANNONCE
// preset (calendrier du club) : {team_id, jour} pour une nouvelle annonce
let anDepuisCal=false;
function anOpen(id,preset){
  const a=id?rsMine.find(x=>x.id===id):null;
  anDepuisCal=!!preset;
  const t=rsTeam(a?.team_id||preset?.team_id||rsTeamId)||rsStaffTeams()[0];
  anEdit={id:a?.id||null,team_id:t.id,type:a?.type||'amical',lieu:a?.lieu||'indifferent',
    format:a?.format||t.format,duree_mt:a?.duree_mt||HALF_MIN[t.format]||'',zone:a?.zone||'province',
    distance_km:a?.distance_km||30,message:a?.message||'',statut:a?.statut||'brouillon',commentaire:a?.commentaire_validation||''};
  anCats=new Set(a?a.categories:[t.categorie]);anNivs=new Set(a?a.niveaux:[]);
  anCreneaux=a?(a.annonce_creneaux||[]).map(c=>({jour:c.jour,debut:fmtHeure(c.heure_debut),fin:fmtHeure(c.heure_fin)})):[{jour:preset?.jour||'',debut:preset?.debut||'',fin:preset?.fin||''}];
  anCibles=new Set();
  if(a?.zone==='equipes')sb.from('annonce_cibles').select('team_id').eq('annonce_id',a.id).then(({data})=>{(data||[]).forEach(r=>anCibles.add(r.team_id));anRenderZone();});
  anRenderForm();openModal('modal-annonce');
}
function anCollect(){
  const g=id=>document.getElementById(id);
  if(!g('an-team'))return;
  anEdit.team_id=g('an-team').value;anEdit.format=g('an-fmt').value;anEdit.duree_mt=parseInt(g('an-duree').value)||null;
  anEdit.zone=g('an-zone').value;anEdit.message=g('an-msg').value.trim();
  if(g('an-km'))anEdit.distance_km=parseInt(g('an-km').value)||null;
  anCreneaux=[...document.querySelectorAll('.an-cr')].map(r=>({jour:r.querySelector('[data-k=jour]').value,debut:r.querySelector('[data-k=debut]').value,fin:r.querySelector('[data-k=fin]').value}));
}
function anRenderForm(){
  const st=rsStaffTeams(),t=rsTeam(anEdit.team_id),club=isClubStaff(t?.club_id);
  const seg=(k,obj)=>`<div class="acc-seg an-seg">${Object.entries(obj).map(([v,l])=>`<button type="button" class="${anEdit[k]===v?'on on-admin':''}" onclick="anCollect();anEdit.${k}='${v}';anRenderForm()">${esc(l)}</button>`).join('')}</div>`;
  document.getElementById('annonce-form').innerHTML=`<div class="mh"></div>
    <div class="mt">${anEdit.id?'Modifier l\'annonce':'Nouvelle annonce'}</div>
    ${anEdit.statut==='refusee'&&anEdit.commentaire?`<div class="rs-warn" style="margin-bottom:12px">Refusée par le coordinateur : ${esc(anEdit.commentaire)}</div>`:''}
    <div class="fg"><label class="fl">Équipe</label><select class="sel" id="an-team" onchange="anOnTeam()">${st.map(x=>`<option value="${x.id}" ${x.id===anEdit.team_id?'selected':''}>${esc(x.nom)} (${esc(x.categorie)})</option>`).join('')}</select></div>
    <div class="fg"><label class="fl">Type</label>${seg('type',AN_TYPES)}</div>
    <div class="fg"><label class="fl">Lieu</label>${seg('lieu',AN_LIEUX)}</div>
    <div class="frow">
      <div class="fg"><label class="fl">Format</label><select class="sel" id="an-fmt">${refs.formats.map(f=>`<option value="${esc(f.code)}" ${f.code===anEdit.format?'selected':''}>${esc(f.libelle)}</option>`).join('')}</select></div>
      <div class="fg"><label class="fl">Mi-temps (min)</label><input class="fi" id="an-duree" type="number" min="5" max="60" value="${anEdit.duree_mt||''}"></div>
    </div>
    <div class="fg"><label class="fl">Catégories acceptées</label><div class="an-chips">${refs.categories.map(c=>`<button type="button" class="${anCats.has(c.code)?'on':''}" onclick="anToggle(anCats,'${esc(c.code)}',this)">${esc(c.libelle)}</button>`).join('')}</div></div>
    <div class="fg"><label class="fl">Niveaux acceptés <span style="color:var(--text3);font-weight:400">(aucun = tous)</span></label><div class="an-chips">${refs.niveaux.map(n=>`<button type="button" class="${anNivs.has(n.id)?'on':''}" onclick="anToggle(anNivs,${n.id},this)">${esc(n.libelle)}</button>`).join('')}</div></div>
    <div class="fg"><label class="fl">Visible par</label><select class="sel" id="an-zone" onchange="anCollect();anRenderZone()">${Object.entries(AN_ZONES).map(([v,l])=>`<option value="${v}" ${v===anEdit.zone?'selected':''}>${esc(l)}</option>`).join('')}</select><div id="an-zone-x"></div></div>
    <div class="fg"><label class="fl">Créneaux libres</label><div id="an-crs"></div><button type="button" class="bsec logo-btn" style="margin-top:8px" onclick="anCollect();anCreneaux.push({jour:'',debut:'',fin:''});anRenderCreneaux()">+ Ajouter un créneau</button></div>
    <div class="fg"><label class="fl">Message <span style="color:var(--text3);font-weight:400">(optionnel)</span></label><textarea class="fi" id="an-msg" rows="3" maxlength="1000" placeholder="Terrain synthétique, vestiaires, goûter offert…">${esc(anEdit.message)}</textarea></div>
    <div class="mfoot an-foot">
      <button class="bcan" onclick="closeModal('modal-annonce')">Annuler</button>
      <button class="bsec" onclick="anSave('brouillon')">Brouillon</button>
      ${club?`<button class="bp" onclick="anSave('publiee')">Publier</button>`:`<button class="bp" onclick="anSave('a_valider')">Envoyer au coordinateur</button>`}
    </div>`;
  anRenderZone();anRenderCreneaux();
}
function anToggle(set,v,btn){if(set.has(v))set.delete(v);else set.add(v);btn.classList.toggle('on',set.has(v));}
function anOnTeam(){
  anCollect();const t=rsTeam(anEdit.team_id);
  if(t){anEdit.format=t.format;anEdit.duree_mt=HALF_MIN[t.format]||anEdit.duree_mt;anCats=new Set([t.categorie]);}
  anRenderForm();
}
async function anRenderZone(){
  const x=document.getElementById('an-zone-x');if(!x)return;
  const z=document.getElementById('an-zone').value;anEdit.zone=z;
  if(z==='distance'){x.innerHTML=`<div style="display:flex;align-items:center;gap:8px;margin-top:8px"><input class="fi" id="an-km" type="number" min="1" max="500" value="${anEdit.distance_km||30}" style="width:110px"><span style="color:var(--text2);font-size:13px">km autour de notre terrain</span></div>`;return;}
  if(z==='province'){x.innerHTML=`<div class="rs-line" style="margin-top:6px">Clubs de la même province que le vôtre.</div>`;return;}
  if(z==='belgique'){x.innerHTML=`<div class="rs-line" style="margin-top:6px">Tous les clubs vérifiés de Belgique.</div>`;return;}
  // Équipes choisies : liste des équipes des autres clubs vérifiés
  if(!anEquipesReseau){x.innerHTML='<div class="spin"></div>';const{data}=await sb.rpc('equipes_reseau');anEquipesReseau=data||[];}
  const myClub=rsTeam(anEdit.team_id)?.club_id;
  const autres=anEquipesReseau.filter(e=>!teams.some(t=>t.id===e.team_id&&t.club_id===myClub));
  x.innerHTML=`<input class="fi" id="an-cib-q" placeholder="Rechercher un club ou une équipe" style="margin-top:8px" oninput="anFiltreCibles()"><div class="an-cibles" id="an-cibles">${autres.map(e=>`<label data-q="${esc((e.club_nom+' '+e.equipe+' '+e.categorie).toLowerCase())}"><input type="checkbox" ${anCibles.has(e.team_id)?'checked':''} onchange="this.checked?anCibles.add('${e.team_id}'):anCibles.delete('${e.team_id}')"> ${esc(e.club_nom)} · ${esc(e.equipe)} (${esc(e.categorie)})</label>`).join('')||'<div class="rs-line">Aucune autre équipe dans le réseau pour l\'instant.</div>'}</div>`;
}
function anFiltreCibles(){const q=document.getElementById('an-cib-q').value.toLowerCase();document.querySelectorAll('#an-cibles label').forEach(l=>l.style.display=l.dataset.q.includes(q)?'':'none');}
function anRenderCreneaux(){
  document.getElementById('an-crs').innerHTML=anCreneaux.map((c,i)=>`<div class="an-cr">
    <input class="fi" type="date" data-k="jour" value="${esc(c.jour)}" min="${todayIso()}">
    <input class="fi" type="time" data-k="debut" value="${esc(c.debut)}">
    <input class="fi" type="time" data-k="fin" value="${esc(c.fin)}">
    <button type="button" class="bred" onclick="anCollect();anCreneaux.splice(${i},1);anRenderCreneaux()" aria-label="Retirer">✕</button></div>`).join('');
}
async function anSave(statut){
  anCollect();
  const cr=anCreneaux.filter(c=>c.jour);
  if(!cr.length)return showToast('Ajoute au moins un créneau (date)','err');
  if(anEdit.zone==='distance'&&!(anEdit.distance_km>0))return showToast('Indique la distance maximale en km','err');
  if(anEdit.zone==='equipes'&&!anCibles.size)return showToast('Choisis au moins une équipe','err');
  const row={team_id:anEdit.team_id,type:anEdit.type,lieu:anEdit.lieu,format:anEdit.format||null,duree_mt:anEdit.duree_mt||null,
    categories:[...anCats],niveaux:[...anNivs],zone:anEdit.zone,distance_km:anEdit.zone==='distance'?anEdit.distance_km:null,
    message:anEdit.message||null,statut};
  if(statut!=='refusee')row.commentaire_validation=null;
  let id=anEdit.id,res;
  if(id)res=await sb.from('annonces').update(row).eq('id',id).select();
  else res=await sb.from('annonces').insert({...row,cree_par:U.id}).select();
  if(res.error)return showToast(res.error.message||'Enregistrement refusé','err');
  if(!res.data?.length)return showToast('Enregistrement refusé','err');
  id=res.data[0].id;
  // Créneaux et équipes ciblées : remplacés par ceux du formulaire
  await sb.from('annonce_creneaux').delete().eq('annonce_id',id);
  const e1=(await sb.from('annonce_creneaux').insert(cr.map(c=>({annonce_id:id,jour:c.jour,heure_debut:c.debut||null,heure_fin:c.fin||null})))).error;
  await sb.from('annonce_cibles').delete().eq('annonce_id',id);
  let e2=null;if(anEdit.zone==='equipes')e2=(await sb.from('annonce_cibles').insert([...anCibles].map(t=>({annonce_id:id,team_id:t})))).error;
  if(e1||e2)showToast('Annonce enregistrée, mais créneaux/équipes incomplets : réessaie','err');
  else showToast({brouillon:'Brouillon enregistré',a_valider:'Envoyée au coordinateur pour validation',publiee:'Annonce publiée'}[statut],'ok');
  closeModal('modal-annonce');
  if(anDepuisCal&&typeof renderCalendrier==='function')renderCalendrier();   // reste sur le calendrier
  else{rsTab='mine';renderReseauPage();}
}
