// ============ DEMANDES D'ACCÈS (A5) ============
// Chargé après tournois.js (utilise sb, U, teams, myClubs, esc, showToast, openModal,
// closeModal, renderHome, majAccueilNouveau, rechargerAcces).
// Une personne connectée demande un rôle dans un club vérifié (coordinateur, entraîneur,
// délégué, parent d'un joueur) ; le CQ / coordinateur du club, ou l'encadrement de
// l'équipe (rôles d'équipe), accepte ou refuse. L'accès est donné par la base (demande_traiter).
let daAnnuaire=[],daListe=[];
const DA_ROLE={coordinateur:'Coordinateur du club',entraineur:'Entraîneur',delegue:'Délégué',parent:'Parent'};
const DA_STATUT={en_attente:['pb','En attente'],acceptee:['pg','✓ Acceptée'],refusee:['pr','Refusée'],annulee:['pgr','Annulée']};
const daLibelle=d=>`${DA_ROLE[d.role]||d.role}${d.team_nom?' · '+d.team_nom:''}${d.enfant?' · enfant : '+d.enfant:''} — ${d.club_nom}`;

document.body.insertAdjacentHTML('beforeend',`
<div class="mo" id="modal-da"><div class="modal"><div class="mh"></div>
  <div class="mt">Demander un accès</div>
  <div class="fg"><label class="fl">Club</label><select class="sel" id="da-club" onchange="daMajEquipes()"></select></div>
  <div class="fg"><label class="fl">Je suis</label><select class="sel" id="da-role" onchange="daMajChamps()">
    <option value="parent">Parent d'un joueur</option><option value="entraineur">Entraîneur d'une équipe</option>
    <option value="delegue">Délégué d'une équipe</option><option value="coordinateur">Coordinateur du club</option></select></div>
  <div class="fg" id="da-team-fg"><label class="fl">Équipe</label><select class="sel" id="da-team"></select></div>
  <div class="fg" id="da-enfant-fg"><label class="fl">Prénom et nom de ton enfant</label><input class="fi" id="da-enfant" maxlength="80" placeholder="ex. Léo Dupont"></div>
  <div class="fg"><label class="fl">Message <span style="color:var(--text3);font-weight:400">(facultatif)</span></label><textarea class="fi" id="da-msg" rows="2" maxlength="500" placeholder="ex. Je suis la maman de Léo, U9"></textarea></div>
  <div class="trn-aide" id="da-aide"></div>
  <div class="mfoot"><button class="bcan" onclick="closeModal('modal-da')">Annuler</button><button class="bp" onclick="daEnvoyer()">Envoyer la demande</button></div>
</div></div>
<div class="mo" id="modal-da-val"><div class="modal"><div class="mh"></div>
  <div class="mt">Demandes d'accès à traiter</div>
  <div id="da-val-liste"></div>
  <div class="mfoot"><button class="bcan" onclick="closeModal('modal-da-val')">Fermer</button></div>
</div></div>`);

async function daCharger(){
  const{data,error}=await sb.rpc('mes_demandes_acces');
  daListe=error?[]:(data||[]);
  return daListe;
}

// ---- Côté demandeur ----
async function daOuvrir(type){
  if(!daAnnuaire.length){const{data,error}=await sb.rpc('annuaire_clubs');if(error)return showToast('Demandes d\'accès pas encore disponibles','err');daAnnuaire=data||[];}
  if(!daAnnuaire.length)return showToast('Aucun club disponible pour l\'instant','err');
  document.getElementById('da-club').innerHTML='<option value="">— Choisis ton club —</option>'+daAnnuaire.map(c=>`<option value="${c.club_id}">${esc(c.club_nom)}</option>`).join('');
  document.getElementById('da-role').value=type==='parent'?'parent':'entraineur';
  document.getElementById('da-enfant').value='';document.getElementById('da-msg').value='';
  daMajEquipes();openModal('modal-da');
}
function daMajEquipes(){
  const c=daAnnuaire.find(x=>x.club_id===document.getElementById('da-club').value);
  document.getElementById('da-team').innerHTML=c?(c.equipes||[]).map(t=>`<option value="${t.id}">${esc(t.nom)}${t.categorie&&t.categorie!==t.nom?' ('+esc(t.categorie)+')':''}</option>`).join(''):'<option value="">Choisis d\'abord le club</option>';
  daMajChamps();
}
function daMajChamps(){
  const r=document.getElementById('da-role').value;
  document.getElementById('da-team-fg').style.display=r==='coordinateur'?'none':'';
  document.getElementById('da-enfant-fg').style.display=r==='parent'?'':'none';
  document.getElementById('da-aide').textContent=r==='coordinateur'?'Le CQ ou un coordinateur du club validera ta demande.':
    r==='parent'?'L\'encadrement de l\'équipe te reliera à ton enfant. Tu ne verras que sa fiche, jamais celle des autres enfants.':
    'Le club ou l\'encadrement de l\'équipe validera ta demande.';
}
async function daEnvoyer(){
  const club=document.getElementById('da-club').value,role=document.getElementById('da-role').value;
  const team=role==='coordinateur'?null:document.getElementById('da-team').value||null;
  const enfant=document.getElementById('da-enfant').value.trim(),msg=document.getElementById('da-msg').value.trim();
  if(!club)return showToast('Choisis ton club','err');
  if(role!=='coordinateur'&&!team)return showToast('Choisis l\'équipe','err');
  if(role==='parent'&&!enfant)return showToast('Indique le prénom de ton enfant','err');
  const{error}=await sb.rpc('demande_creer',{p_club:club,p_role:role,p_team:team,p_enfant:role==='parent'?enfant:null,p_message:msg||null});
  if(error)return showToast(/déjà|Choisis|Indique|introuvable/i.test(error.message)?error.message:'Demande refusée','err');
  closeModal('modal-da');showToast('Demande envoyée : tu recevras un e-mail dès qu\'elle est traitée','ok');
  daMajMes();
}
async function daAnnuler(id){
  const{error}=await sb.rpc('demande_traiter',{p_id:id,p_action:'annuler'});
  if(error)return showToast('Annulation impossible','err');
  showToast('Demande annulée','ok');daMajMes();
}
// Mes demandes (accueil d'un compte sans rôle)
async function daMajMes(){
  const el=document.getElementById('da-mes');if(!el)return;
  const mes=(await daCharger()).filter(d=>d.cote==='moi'&&d.statut!=='annulee').slice(0,5);
  el.innerHTML=mes.length?`<div class="an-c"><div class="an-h">📨 Mes demandes d'accès</div>${mes.map(d=>{const[c,l]=DA_STATUT[d.statut]||['pgr',d.statut];
    return `<div class="da-l"><div style="flex:1;min-width:0"><div class="da-n">${esc(daLibelle(d))}</div>${d.motif?`<div class="trn-sous">Motif : ${esc(d.motif)}</div>`:''}</div><span class="pill ${c}">${l}</span>${d.statut==='en_attente'?`<button class="bsec" onclick="daAnnuler('${d.id}')">Annuler</button>`:''}</div>`;}).join('')}
    ${mes.some(d=>d.statut==='acceptee')?'<button class="badd" style="margin-top:8px" onclick="rechargerAcces()">Ouvrir mon accès</button>':''}</div>`:'';
}

// ---- Côté validateur (CQ / coordinateur, encadrement de l'équipe) ----
async function daMajValidation(){
  const n=(await daCharger()).filter(d=>d.cote==='a_valider').length;
  let b=document.getElementById('da-bandeau');
  if(!b){const h=document.querySelector('#page-home .wbanner');if(!h)return;h.insertAdjacentHTML('afterend','<div id="da-bandeau"></div>');b=document.getElementById('da-bandeau');}
  b.innerHTML=n?`<button class="da-bandeau" onclick="daOuvrirValidation()">📥 ${n} demande${n>1?'s':''} d'accès à traiter <span>›</span></button>`:'';
  const m=document.getElementById('umenu-da');if(m){m.style.display=n?'flex':'none';const c=document.getElementById('umenu-da-n');if(c)c.textContent=n;}
}
async function daOuvrirValidation(){
  await daCharger();renderDaValidation();openModal('modal-da-val');
}
function renderDaValidation(){
  const l=daListe.filter(d=>d.cote==='a_valider');
  document.getElementById('da-val-liste').innerHTML=l.map(d=>`<div class="da-v" id="da-v-${d.id}">
      <div class="da-n">${esc(d.demandeur)}</div><div class="trn-sous">${esc(d.demandeur_email||'')}</div>
      <div class="da-r">${esc(daLibelle(d))}</div>
      ${d.message?`<div class="trn-infos" style="margin-top:6px">${esc(d.message)}</div>`:''}
      ${d.role==='parent'?`<div class="fg" style="margin:8px 0 0"><label class="fl">Relier à l'enfant</label><select class="sel" id="da-joueur-${d.id}"><option value="">Chargement…</option></select></div>`:''}
      <div class="trn-ins-a"><button class="badd" onclick="daDecider('${d.id}','accepter')">Accepter</button><button class="bsec" onclick="daDecider('${d.id}','refuser')">Refuser</button></div>
    </div>`).join('')||'<div class="trn-aide">Aucune demande en attente.</div>';
  // Parent : l'effectif de l'équipe pour choisir l'enfant (le validateur y a accès)
  l.filter(d=>d.role==='parent').forEach(async d=>{
    const{data}=await sb.from('players').select('id,prenom,nom').eq('team_id',d.team_id).eq('actif',true).order('prenom');
    const sel=document.getElementById('da-joueur-'+d.id);if(!sel)return;
    const proche=(data||[]).find(p=>(p.prenom+' '+p.nom).toLowerCase().includes((d.enfant||'').toLowerCase().split(' ')[0]));
    sel.innerHTML='<option value="">— Choisis l\'enfant —</option>'+(data||[]).map(p=>`<option value="${p.id}"${proche&&proche.id===p.id?' selected':''}>${esc(p.prenom+' '+p.nom)}</option>`).join('');
  });
}
async function daDecider(id,action){
  const d=daListe.find(x=>x.id===id);let joueur=null,motif=null;
  if(action==='accepter'&&d?.role==='parent'){joueur=document.getElementById('da-joueur-'+id)?.value||null;if(!joueur)return showToast('Choisis l\'enfant à relier','err');}
  if(action==='refuser'&&typeof askConfirm==='function'&&!await askConfirm(`Refuser la demande de ${d?.demandeur||'cette personne'} ?`))return;
  const{error}=await sb.rpc('demande_traiter',{p_id:id,p_action:action,p_player:joueur,p_motif:motif});
  if(error)return showToast(/Choisis/.test(error.message)?error.message:'Action refusée','err');
  showToast(action==='accepter'?'Accès donné : la personne est prévenue par e-mail':'Demande refusée','ok');
  await daCharger();renderDaValidation();daMajValidation();
}

// Accueil : bandeau des demandes à traiter, ou « mes demandes » pour un compte sans rôle
const daRenderHome=renderHome;
renderHome=function(){daRenderHome.apply(this,arguments);if(U){daMajValidation();daMajMes();}};
const daMajAccueilNouveau=majAccueilNouveau;
majAccueilNouveau=function(){daMajAccueilNouveau.apply(this,arguments);if(U)daMajMes();};
