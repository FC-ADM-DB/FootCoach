// ============ CALENDRIER DU CLUB (coordinateur / CQ) ============
// Chargé après propositions.js (utilise sb, teams, myClubs, isClubStaff, esc, goPage,
// prMajCompte, prListe, prOuvrir, todayIso…).
// Semaine par équipe : une ligne par équipe du club, une colonne par jour. On y voit les
// matchs prévus (plein), les propositions en cours (pointillé) et les créneaux libres des
// annonces du club, pour juger si une proposition peut se faire. Pas d'alerte de conflit
// (choix de l'utilisateur) : le coordinateur juge lui-même.

let calClub=null,calLundi=null;
const calIso=d=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
function calDebutSemaine(d){const x=new Date(d);x.setHours(0,0,0,0);x.setDate(x.getDate()-((x.getDay()+6)%7));return x;}
function ouvrirCalendrier(jour){
  if(jour)calLundi=calDebutSemaine(new Date(jour+'T12:00'));
  goPage('calendrier');
}
const calGoPage=goPage;
goPage=function(name){calGoPage(name);if(name==='calendrier')renderCalendrier();};
function calSemaine(delta){calLundi=new Date(calLundi);calLundi.setDate(calLundi.getDate()+7*delta);renderCalendrier();}

async function renderCalendrier(){
  const el=document.getElementById('cal-content');if(!el)return;
  const clubs=myClubs.filter(c=>c.clubs);
  if(!clubs.length){el.innerHTML='<div class="empty"><div class="empty-i">📅</div><div class="empty-t">Réservé aux coordinateurs et CQ</div></div>';return;}
  if(!calClub||!clubs.some(c=>c.club_id===calClub))calClub=(clubs.find(c=>c.club_id===CT?.club_id)||clubs[0]).club_id;
  if(!calLundi)calLundi=calDebutSemaine(new Date());
  const jours=[...Array(7)].map((_,i)=>{const d=new Date(calLundi);d.setDate(d.getDate()+i);return d;});
  const debut=calIso(jours[0]),fin=calIso(jours[6]);
  const eqs=teams.filter(t=>t.club_id===calClub).sort((a,b)=>a.nom.localeCompare(b.nom));
  const ids=eqs.map(t=>t.id);
  el.innerHTML='<div class="spin"></div>';
  const finExcl=new Date(jours[6]);finExcl.setDate(finExcl.getDate()+1);
  const [m,an]=await Promise.all([
    ids.length?sb.from('matches').select('id,team_id,date,adversaire,lieu,statut').in('team_id',ids).gte('date',jours[0].toISOString()).lt('date',finExcl.toISOString()).order('date'):{data:[]},
    sb.from('annonces').select('id,team_id,annonce_creneaux(jour,heure_debut,heure_fin,statut)').eq('club_id',calClub).eq('statut','publiee'),
    typeof prMajCompte==='function'?prMajCompte():null]);
  const props=(typeof prListe!=='undefined'?prListe:[]).filter(p=>['a_valider','envoyee','contre'].includes(p.statut)&&p.jour>=debut&&p.jour<=fin);
  const h=d=>new Date(d).toLocaleTimeString('fr-BE',{hour:'2-digit',minute:'2-digit'});
  const cell=(t,j)=>{
    const iso=calIso(j),items=[];
    (m.data||[]).filter(x=>x.team_id===t.id&&calIso(new Date(x.date))===iso).forEach(x=>items.push({k:h(x.date),html:
      `<div class="cal-it ${x.lieu==='domicile'?'dom':'ext'}${x.statut==='termine'?' fini':''}">${h(x.date)} ${x.lieu==='domicile'?'🏠':'✈️'} ${esc(x.adversaire)}</div>`}));
    props.forEach(p=>{
      const mien=p.cote==='annonceur'?p.equipe_annonceur_id:p.equipe_proposante_id;if(mien!==t.id||p.jour!==iso)return;
      const autre=p.cote==='annonceur'?`${p.club_proposant} ${p.equipe_proposante}`:`${p.club_annonceur} ${p.equipe_annonceur}`;
      const etat=p.statut==='a_valider'?'à envoyer':prAFaire(p)?'à répondre':'en attente';
      items.push({k:fmtHeure(p.heure)||'99',html:`<div class="cal-it prop" onclick="prOuvrir('${p.id}')">${fmtHeure(p.heure)||'?'} ${p.lieu===p.cote?'🏠':'✈️'} ${esc(autre)} <small>${etat}</small></div>`});
    });
    (an.data||[]).filter(a=>a.team_id===t.id).forEach(a=>(a.annonce_creneaux||[]).filter(c=>c.jour===iso&&c.statut==='libre').forEach(c=>
      items.push({k:fmtHeure(c.heure_debut)||'98',html:`<div class="cal-it libre">${fmtHeure(c.heure_debut)||''}${c.heure_fin?'–'+fmtHeure(c.heure_fin):''} 📢 Annonce publiée <small>attente de proposition</small></div>`})));
    // Case d'aujourd'hui ou future : publier une annonce pour cette équipe ce jour-là
    const plus=iso>=todayIso()&&isTeamStaff(t)?`<button class="cal-add" onclick="calAnnonce('${t.id}','${iso}')" aria-label="Annonce pour trouver un match">+</button>`:'';
    return `<td class="${iso===todayIso()?'auj':''}${[5,6].includes(j.getDay()===0?6:j.getDay()-1)?' we':''}">${items.sort((a,b)=>a.k.localeCompare(b.k)).map(i=>i.html).join('')}${plus}</td>`;
  };
  const titre=`${jours[0].toLocaleDateString('fr-BE',{day:'numeric',month:'short'})} – ${jours[6].toLocaleDateString('fr-BE',{day:'numeric',month:'short',year:'numeric'})}`;
  el.innerHTML=`${clubs.length>1?`<div class="club-chooser">${clubs.map(c=>`<button class="${c.club_id===calClub?'on':''}" onclick="calClub='${c.club_id}';renderCalendrier()">${esc(c.clubs.nom)}</button>`).join('')}</div>`:''}
    <div class="cal-nav"><button class="bsec" onclick="calSemaine(-1)" aria-label="Semaine précédente">‹</button>
      <div class="cal-titre">${titre}</div>
      <button class="bsec" onclick="calSemaine(1)" aria-label="Semaine suivante">›</button>
      <button class="bsec" onclick="calLundi=calDebutSemaine(new Date());renderCalendrier()">Aujourd'hui</button></div>
    <div class="cal-leg"><span class="cal-it dom">🏠 domicile</span><span class="cal-it ext">✈️ extérieur</span><span class="cal-it prop">proposition en cours</span><span class="cal-it libre">📢 annonce publiée</span></div>
    <div class="rs-line" style="margin-bottom:8px">Touche <b>+</b> dans une case pour chercher un adversaire ce jour-là ou publier une annonce.</div>
    ${eqs.length?`<div class="cal-wrap"><table class="cal"><thead><tr><th></th>${jours.map(j=>`<th class="${calIso(j)===todayIso()?'auj':''}">${j.toLocaleDateString('fr-BE',{weekday:'short'})}<br><b>${j.getDate()}</b></th>`).join('')}</tr></thead>
      <tbody>${eqs.map(t=>`<tr><th><div class="cal-eq">${esc(t.nom)}</div><div class="cal-cat">${esc(t.categorie||'')}</div></th>${jours.map(j=>cell(t,j)).join('')}</tr>`).join('')}</tbody></table></div>`
      :'<div class="empty"><div class="empty-t">Aucune équipe dans ce club</div></div>'}`;
}

// Fiche d'une proposition : planning du club ce jour-là (pour le coordinateur / CQ)
async function calJourClub(p){
  const box=document.getElementById('pr-jour-club');if(!box)return;
  const club=p.cote==='annonceur'?teams.find(t=>t.id===p.equipe_annonceur_id)?.club_id:teams.find(t=>t.id===p.equipe_proposante_id)?.club_id;
  const ids=teams.filter(t=>t.club_id===club).map(t=>t.id);if(!ids.length){box.innerHTML='';return;}
  const d0=new Date(p.jour+'T00:00'),d1=new Date(d0);d1.setDate(d1.getDate()+1);
  const{data}=await sb.from('matches').select('team_id,date,adversaire,lieu').in('team_id',ids).gte('date',d0.toISOString()).lt('date',d1.toISOString()).order('date');
  const nom=id=>teams.find(t=>t.id===id)?.nom||'';
  box.innerHTML=`<div class="pr-jc"><b>📅 Ce jour-là au club :</b> ${(data||[]).length?(data||[]).map(x=>`${new Date(x.date).toLocaleTimeString('fr-BE',{hour:'2-digit',minute:'2-digit'})} ${esc(nom(x.team_id))} ${x.lieu==='domicile'?'🏠':'✈️'} ${esc(x.adversaire)}`).join(' · '):'aucun autre match'}
    <a href="#" onclick="event.preventDefault();closeModal('modal-prop');ouvrirCalendrier('${p.jour}')">voir la semaine ›</a></div>`;
}

// Entrée « Calendrier du club » du menu : seulement pour les CQ / coordinateurs
const calOpenUserMenu=openUserMenu;
openUserMenu=function(){const m=document.getElementById('umenu-cal');if(m)m.style.display=myClubs.length?'flex':'none';calOpenUserMenu();};

// « + » d'une case : chercher un adversaire parmi les annonces (équipe, jour, tranche
// horaire facultative) ou publier sa propre annonce pré-remplie
function calAnnonce(teamId,jour){
  const t=teams.find(x=>x.id===teamId);
  const d=new Date(jour+'T12:00').toLocaleDateString('fr-BE',{weekday:'long',day:'numeric',month:'long'});
  document.getElementById('cal-choix-body').innerHTML=`<div class="mh"></div>
    <div class="mt">Trouver un match</div>
    <div class="rs-line" style="margin:-6px 0 14px"><b>${esc(t?.nom||'')}</b> · ${esc(d)}</div>
    <div class="fg"><label class="fl">Tranche horaire <span style="color:var(--text3);font-weight:400">(facultatif)</span></label>
      <div class="rs-heures"><span>Entre</span><input class="fi" type="time" id="calc-de"><span>et</span><input class="fi" type="time" id="calc-a"></div></div>
    <button class="bp cal-choix-b" onclick="calChoix('voir','${teamId}','${jour}')">🔎 Voir les annonces qui correspondent</button>
    <button class="bsec cal-choix-b" onclick="calChoix('publier','${teamId}','${jour}')">📢 Publier notre annonce</button>
    <div class="mfoot"><button class="bcan" onclick="closeModal('modal-cal-choix')">Annuler</button></div>`;
  openModal('modal-cal-choix');
}
function calChoix(action,teamId,jour){
  const de=document.getElementById('calc-de').value,a=document.getElementById('calc-a').value;
  if(de&&a&&a<de)return showToast('L\'heure de fin est avant l\'heure de début','err');
  closeModal('modal-cal-choix');
  if(action==='voir')return rsChercherPour(teamId,jour,de,a);
  anOpen(null,{team_id:teamId,jour,debut:de,fin:a});
}
// Tuile « Calendrier » de l'accueil : seulement pour les CQ / coordinateurs
const calRenderHome=renderHome;
renderHome=function(){calRenderHome.apply(this,arguments);const b=document.getElementById('home-cal');if(b)b.style.display=myClubs.length?'':'none';};
if(U&&document.getElementById('home-cal'))document.getElementById('home-cal').style.display=myClubs.length?'':'none';
