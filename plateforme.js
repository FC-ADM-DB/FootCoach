// ============ PLATEFORME D'ADMINISTRATION (admin plateforme uniquement) ============
// Chargé après app.js. Les droits sont vérifiés par la base : fonctions admin_*
// (supabase/2026-10-24-P1-plateforme.sql) et règles des tables clubs / niveaux.
// Ici : vérifier les clubs, voir tous les clubs, gérer les niveaux (renommer, fusionner).

let isPlatformAdmin=false,ptTab='attente',ptClubs=[],ptQ='';
let ptView=null,ptLogo=null,ptLogoChanged=false;  // ptView : id du club dont la fiche est ouverte
async function loadPlatformAdmin(){
  isPlatformAdmin=false;
  try{
    const{data}=await sb.from('platform_admins').select('profile_id').eq('profile_id',U.id);
    isPlatformAdmin=!!data?.length;
  }catch(e){}
  const m=document.getElementById('umenu-plateforme');
  if(m)m.style.display=isPlatformAdmin?'flex':'none';
  // Lien vers la démo (base de test) : pour l'admin, et pas depuis la démo elle-même
  const d=document.getElementById('umenu-demo');if(d)d.style.display=isPlatformAdmin&&!SB_DEMO?'flex':'none';
}
const ptDate=d=>d?new Date(d).toLocaleDateString('fr-BE',{day:'numeric',month:'short',year:'numeric'}):'';

async function renderPlateforme(){
  const el=document.getElementById('plateforme-content');
  if(!isPlatformAdmin){el.innerHTML=`<div class="empty"><div class="empty-i">🔒</div><div class="empty-t">Réservé à l'administrateur FootCoach</div></div>`;return;}
  if(ptView==='nouveau')return ptRenderCreation();
  if(ptView)return ptRenderFiche(ptView);
  el.innerHTML='<div class="spin"></div>';
  const [st,cl]=await Promise.all([sb.rpc('admin_stats'),sb.rpc('admin_clubs')]);
  if(st.error||cl.error){el.innerHTML=`<div class="empty"><div class="empty-i">⚠️</div><div class="empty-t">Gestion des clubs indisponible</div><div class="empty-s">${esc((st.error||cl.error).message)}</div></div>`;return;}
  const s=st.data?.[0]||{};ptClubs=cl.data||[];
  // Chiffres en une ligne de petites pastilles (les grandes tuiles prenaient trop de place)
  const tile=(n,l,c)=>`<span class="pt-stat${c?' '+c:''}"><b>${n??'—'}</b> ${l}</span>`;
  const tab=(k,l)=>`<button class="${ptTab===k?'on':''}" onclick="ptTab='${k}';renderPlateforme()">${l}</button>`;
  el.innerHTML=`<div class="pt-stats">${tile(s.clubs,'clubs')}${tile(s.clubs_verifies,'vérifiés')}${s.clubs_en_attente?tile(s.clubs_en_attente,'à vérifier','warn'):''}${tile(s.equipes,'équipes')}${tile(s.utilisateurs,'utilisateurs')}${tile(s.annonces_publiees,'annonces')}</div>
    <button class="bp pt-new" onclick="ptView='nouveau';renderPlateforme()">+ Créer un club</button>
    <div class="rs-tabs">${tab('attente',`À vérifier${s.clubs_en_attente?` <span class="rs-count">${s.clubs_en_attente}</span>`:''}`)}${tab('clubs','Tous les clubs')}${tab('niveaux','Niveaux')}</div>
    <div id="pt-body"></div>`;
  if(ptTab==='niveaux')return ptRenderNiveaux();
  if(ptTab==='clubs')document.getElementById('pt-body').innerHTML=`<input class="fi" type="search" placeholder="🔎 Rechercher un club, une commune, un CQ" value="${esc(ptQ)}" oninput="ptQ=this.value;ptRenderClubs()" style="margin-bottom:10px"><div id="pt-list"></div>`;
  else document.getElementById('pt-body').innerHTML='<div id="pt-list"></div>';
  ptRenderClubs();
}
function ptRenderClubs(){
  const el=document.getElementById('pt-list');if(!el)return;
  let list=ptTab==='attente'?ptClubs.filter(c=>!c.verifie):ptClubs;
  const q=ptQ.trim().toLowerCase();
  if(ptTab==='clubs'&&q)list=list.filter(c=>`${c.nom} ${c.adresse||''} ${c.province||''} ${c.cq||''} ${c.cq_email||''}`.toLowerCase().includes(q));
  if(!list.length){el.innerHTML=`<div class="empty"><div class="empty-i">${ptTab==='attente'?'✅':'🔎'}</div><div class="empty-t">${ptTab==='attente'?'Aucun club en attente':'Aucun club trouvé'}</div></div>`;return;}
  el.innerHTML=list.map(c=>{
    const l=safeLogo(c);
    const lieu=(c.adresse||'').split(',').pop().trim()||c.province||'';
    return `<div class="pt-row" onclick="ptView='${c.id}';renderPlateforme()">
      <div class="rs-logo">${l?`<img class="team-logo" src="${l}" alt="">`:'🏟'}</div>
      <div style="flex:1;min-width:0"><div class="rs-club">${esc(c.nom)}</div><div class="rs-sub">${esc(lieu||'—')} · ${c.nb_equipes} équipe${c.nb_equipes>1?'s':''}</div></div>
      ${c.verifie?'<span class="pill pg">✓</span>':'<span class="pill pgr">⏳ À vérifier</span>'}
      <span class="acc-arrow">›</span></div>`;}).join('');
}
async function ptVerifier(id,v){
  const c=ptClubs.find(x=>x.id===id)||{nom:document.getElementById('pc-nom')?.value||'ce club'};
  const msg=v?`Vérifier « ${c?.nom} » ? Il pourra publier et voir les annonces des autres clubs.`
             :`Retirer la vérification de « ${c?.nom} » ? Il ne verra plus les annonces et les siennes ne seront plus visibles.`;
  if(!await askConfirm(msg))return;
  const{data,error}=await sb.from('clubs').update({verifie:v}).eq('id',id).select('id');
  if(error||!data?.length)return showToast(error?.message||'Action refusée','err');
  showToast(v?'Club vérifié':'Vérification retirée','ok');renderPlateforme();
}
async function ptSupprClub(id){
  const c=ptClubs.find(x=>x.id===id)||{nom:document.getElementById('pc-nom')?.value||'ce club'};
  if(!await askConfirm(`Supprimer définitivement le club « ${c?.nom} » ? (il n'a aucune équipe)`))return;
  const{data,error}=await sb.from('clubs').delete().eq('id',id).select('id');
  if(error||!data?.length)return showToast(error?.message||'Suppression refusée','err');
  showToast('Club supprimé','ok');ptView=null;renderPlateforme();
}

// ------------------------------------------------------------ NIVEAUX
async function ptRenderNiveaux(){
  const body=document.getElementById('pt-body');body.innerHTML='<div class="spin"></div>';
  const{data,error}=await sb.rpc('admin_niveaux');
  if(error){body.innerHTML=`<div class="empty"><div class="empty-t">Niveaux indisponibles</div></div>`;return;}
  const nv=data||[];
  body.innerHTML=`<div class="acc-help">Les CQ et coordinateurs peuvent ajouter des niveaux. Renomme-les ou <b>fusionne les doublons</b> (« IP » et « Interprov. ») : les équipes et annonces passent sur le niveau gardé.</div>`+
  nv.map(n=>`<div class="card rs-card">
    <div class="pt-niv">
      <input class="fi" id="pt-nv-${n.id}" value="${esc(n.libelle)}">
      <button class="bsec" onclick="ptRenommer(${n.id})">Renommer</button>
    </div>
    <div class="rs-line">${n.nb_equipes} équipe${n.nb_equipes>1?'s':''} · ${n.nb_annonces} annonce${n.nb_annonces>1?'s':''}${n.cree_par?' · ajouté par '+esc(n.cree_par):''}</div>
    <div class="pt-niv">
      <select class="sel" id="pt-fus-${n.id}"><option value="">Fusionner dans…</option>${nv.filter(x=>x.id!==n.id).map(x=>`<option value="${x.id}">${esc(x.libelle)}</option>`).join('')}</select>
      <button class="bsec" onclick="ptFusion(${n.id})">Fusionner</button>
      ${n.nb_equipes+n.nb_annonces===0?`<button class="bred" onclick="ptSupprNiveau(${n.id})">Supprimer</button>`:''}
    </div>
  </div>`).join('');
}
async function ptRenommer(id){
  const v=document.getElementById('pt-nv-'+id).value.trim();
  if(!v)return showToast('Nom vide','err');
  const{data,error}=await sb.from('niveaux').update({libelle:v}).eq('id',id).select('id');
  if(error||!data?.length)return showToast(/unique|duplicate/i.test(error?.message||'')?'Ce nom existe déjà : fusionne plutôt les deux niveaux':(error?.message||'Refusé'),'err');
  showToast('Niveau renommé','ok');await loadRefs();ptRenderNiveaux();
}
async function ptFusion(id){
  const cible=parseInt(document.getElementById('pt-fus-'+id).value);
  if(!cible)return showToast('Choisis le niveau à garder','err');
  const src=document.getElementById('pt-nv-'+id).value,dst=document.querySelector(`#pt-fus-${id} option[value="${cible}"]`)?.textContent;
  if(!await askConfirm(`Fusionner « ${src} » dans « ${dst} » ?\n\nLes équipes et annonces de « ${src} » passeront sur « ${dst} », puis « ${src} » sera supprimé.`))return;
  const{error}=await sb.rpc('admin_fusion_niveau',{p_source:id,p_cible:cible});
  if(error)return showToast(error.message,'err');
  showToast('Niveaux fusionnés','ok');await loadRefs();ptRenderNiveaux();
}
async function ptSupprNiveau(id){
  if(!await askConfirm('Supprimer ce niveau (il n\'est utilisé nulle part) ?'))return;
  const{data,error}=await sb.from('niveaux').delete().eq('id',id).select('id');
  if(error||!data?.length)return showToast(error?.message||'Suppression refusée','err');
  showToast('Niveau supprimé','ok');await loadRefs();ptRenderNiveaux();
}

// ------------------------------------------------------------ FICHE D'UN CLUB
const PT_ROLE={cq:'CQ',coordinateur:'Coordinateur',entraineur:'Entraîneur',delegue:'Délégué',parent:'Parent'};
async function ptRenderFiche(id){
  const el=document.getElementById('plateforme-content');el.innerHTML='<div class="spin"></div>';
  const [cl,mb,eq]=await Promise.all([sb.from('clubs').select('*').eq('id',id).single(),
    sb.rpc('admin_club_membres',{p_club:id}),sb.rpc('admin_club_equipes',{p_club:id})]);
  const c=cl.data;
  const retour=`<button class="bsec logo-btn" style="margin-bottom:12px" onclick="ptView=null;renderPlateforme()">← Tous les clubs</button>`;
  if(!c){el.innerHTML=retour+`<div class="empty"><div class="empty-t">Club introuvable</div></div>`;return;}
  ptLogo=safeLogo(c);ptLogoChanged=false;
  const membres=mb.data||[],equipes=eq.data||[];
  const encadrement=membres.filter(m=>m.club_member_id);
  const opt=(v,l,cur)=>`<option value="${v}" ${v===cur?'selected':''}>${esc(l)}</option>`;
  el.innerHTML=retour+`
  <div class="card club-head">
    <div class="club-logo" style="background:${ptLogo?'transparent':esc(c.couleur1||'var(--bg3)')}">${ptLogo?`<img class="team-logo" src="${ptLogo}" alt="">`:'🏟'}</div>
    <div style="flex:1;min-width:0"><div style="font-size:17px;font-weight:700">${esc(c.nom)}</div>
      <div style="font-size:12px;color:var(--text2);margin-top:2px">Inscrit le ${esc(ptDate(c.created_at))} · ${equipes.length} équipe${equipes.length>1?'s':''}</div>
      <div style="margin-top:6px">${c.verifie?'<span class="pill pg">✓ Club vérifié</span>':'<span class="pill pgr">⏳ En attente de vérification</span>'}</div></div>
  </div>
  <div class="rs-acts" style="margin:10px 0">
    ${c.verifie?`<button class="bsec" onclick="ptVerifier('${c.id}',false)">Retirer la vérification</button>`:`<button class="bp rs-act" onclick="ptVerifier('${c.id}',true)">✓ Vérifier ce club</button>`}
    ${equipes.length===0?`<button class="bred" onclick="ptSupprClub('${c.id}')">Supprimer le club</button>`:''}
  </div>
  <div class="card">
    <div class="club-sec">Informations du club</div>
    <div class="fg"><label class="fl">Nom</label><input class="fi" id="pc-nom" value="${esc(c.nom)}"></div>
    <div class="frow">
      <div class="fg"><label class="fl">Province</label><select class="sel" id="pc-prov">${opt('','—',null)}${refs.provinces.map(p=>opt(p.id,p.nom,c.province_id)).join('')}</select></div>
      <div class="fg"><label class="fl">Matricule</label><input class="fi" id="pc-mat" value="${esc(c.matricule||'')}" inputmode="numeric"></div>
    </div>
    <div class="fg"><label class="fl">Adresse du terrain</label><input class="fi" id="pc-adr" value="${esc(c.adresse||'')}">
      <div style="font-size:11px;margin-top:5px;color:${c.lat!=null?'var(--green)':'var(--amber)'}">${c.lat!=null?'📍 Position connue':'⚠️ Position inconnue'}</div></div>
    <div class="frow">
      <div class="fg"><label class="fl">Couleur 1</label><input class="fi club-color" type="color" id="pc-c1" value="${esc(c.couleur1||'#fdea2e')}"></div>
      <div class="fg"><label class="fl">Couleur 2</label><input class="fi club-color" type="color" id="pc-c2" value="${esc(c.couleur2||'#b0212f')}"></div>
    </div>
    <div class="fg"><label class="fl">Logo</label><div class="logo-row">
      <div class="logo-prev" id="pc-logo-prev">${ptLogo?`<img class="team-logo" src="${ptLogo}" alt="">`:'<span>Aucun</span>'}</div>
      <label class="bsec logo-btn">Choisir une image<input type="file" accept="image/*" onchange="ptPickLogo(this)" hidden></label>
    </div></div>
    <button class="bp" onclick="ptSaveClub('${c.id}')">Enregistrer</button>
  </div>
  <div class="card">
    <div class="club-sec">Encadrement du club</div>
    ${encadrement.length?encadrement.map(m=>`<div class="club-mem"><div style="flex:1;min-width:0"><div class="admin-name">${esc(m.prenom+' '+m.nom)}</div><div class="admin-role">${esc(m.email||'—')}</div></div>
      <span class="pill ${m.role==='cq'?'pg':'pb'}" style="font-size:11px">${PT_ROLE[m.role]||m.role}</span>
      <button class="bred club-del" onclick="ptRetirerMembre('${m.club_member_id}','${c.id}')">Retirer</button></div>`).join(''):'<div class="rs-line" style="color:var(--amber)">⚠️ Aucun CQ : nommes-en un ci-dessous.</div>'}
    <div class="club-add">
      <input class="fi" id="pc-email" type="email" placeholder="email du compte FootCoach">
      <select class="sel" id="pc-role"><option value="cq">CQ</option><option value="coordinateur">Coordinateur</option></select>
      <button class="bsec logo-btn" onclick="ptAjouterMembre('${c.id}')">Ajouter</button>
    </div>
  </div>
  <div class="card">
    <div class="club-sec">Équipes et membres</div>
    ${equipes.length?equipes.map(t=>{
      const mt=membres.filter(m=>!m.club_member_id&&m.equipe===t.nom);
      return `<div class="pt-team">
        <div class="rs-team">${esc(t.nom)} <span class="rs-sub">· ${esc(t.categorie)} · ${esc(formatLabel(t.format))}${t.niveau?' · '+esc(t.niveau):''}</span></div>
        <div class="rs-line">${t.nb_joueurs} joueur${t.nb_joueurs>1?'s':''} · ${t.nb_matchs} match${t.nb_matchs>1?'s':''} · ${t.nb_membres} membre${t.nb_membres>1?'s':''}</div>
        ${mt.map(m=>`<div class="pt-mb">${esc(m.prenom+' '+m.nom)} <span class="rs-sub">· ${esc(m.email||'')}</span> <span class="acc-chip ${m.role==='entraineur'?'e':'d'}">${PT_ROLE[m.role]||m.role}</span></div>`).join('')}
      </div>`;}).join(''):'<div class="rs-line">Aucune équipe.</div>'}
  </div>`;
}
function ptPickLogo(input){
  const file=input.files&&input.files[0];input.value='';
  if(!file||!file.type.startsWith('image/'))return showToast('Choisis une image','err');
  const url=URL.createObjectURL(file);const img=new Image();
  img.onload=()=>{
    const max=160,r=Math.min(1,max/Math.max(img.width,img.height));
    const cv=document.createElement('canvas');cv.width=Math.max(1,Math.round(img.width*r));cv.height=Math.max(1,Math.round(img.height*r));
    cv.getContext('2d').drawImage(img,0,0,cv.width,cv.height);URL.revokeObjectURL(url);
    ptLogo=cv.toDataURL('image/png');ptLogoChanged=true;
    document.getElementById('pc-logo-prev').innerHTML=`<img class="team-logo" src="${ptLogo}" alt="">`;
  };
  img.onerror=()=>{URL.revokeObjectURL(url);showToast('Image illisible','err');};
  img.src=url;
}
async function ptSaveClub(id){
  const g=x=>document.getElementById(x);
  const nom=g('pc-nom').value.trim();if(!nom)return showToast('Nom du club obligatoire','err');
  const upd={nom,province_id:parseInt(g('pc-prov').value)||null,matricule:g('pc-mat').value.trim()||null,
    adresse:g('pc-adr').value.trim()||null,couleur1:g('pc-c1').value,couleur2:g('pc-c2').value};
  if(ptLogoChanged)upd.logo=ptLogo;
  // Position recalculée si l'adresse change (sans jamais bloquer l'enregistrement)
  const{data:avant}=await sb.from('clubs').select('adresse,lat').eq('id',id).single();
  let pos=null;
  if(upd.adresse&&(upd.adresse!==(avant?.adresse||'')||avant?.lat==null)){
    pos=await geocodeAdresse(upd.adresse);
    if(pos){upd.lat=pos.lat;upd.lng=pos.lng;}else if(upd.adresse!==(avant?.adresse||'')){upd.lat=null;upd.lng=null;}
  }
  const{data,error}=await sb.from('clubs').update(upd).eq('id',id).select('id');
  if(error)return showToast(/matricule|unique|duplicate/i.test(error.message)?'Ce matricule est déjà utilisé par un autre club':error.message,'err');
  if(!data?.length)return showToast('Enregistrement refusé','err');
  showToast('Club enregistré'+(pos?' (📍 '+pos.label+')':(upd.lat===null?' — adresse introuvable':'')),upd.lat===null?'err':'ok');
  ptRenderFiche(id);
}
async function ptAjouterMembre(club){
  const email=document.getElementById('pc-email').value.trim().toLowerCase(),role=document.getElementById('pc-role').value;
  if(!email)return showToast('Email requis','err');
  const r=await sb.rpc('find_profile_by_email',{e:email});
  const p=Array.isArray(r.data)?r.data[0]:r.data;
  if(!p)return showToast('Aucun compte FootCoach avec cet email','err');
  const{data,error}=await sb.from('club_members').insert({club_id:club,profile_id:p.id,role}).select('id');
  if(error)return showToast(/duplicate|unique/i.test(error.message)?'Cette personne a déjà ce rôle':error.message,'err');
  if(!data?.length)return showToast('Ajout refusé','err');
  showToast(`${p.prenom||'Personne'} ajouté(e) comme ${PT_ROLE[role]}`,'ok');ptRenderFiche(club);
}
async function ptRetirerMembre(id,club){
  if(!await askConfirm('Retirer cette personne de l\'encadrement du club ?'))return;
  const{data,error}=await sb.from('club_members').delete().eq('id',id).select('id');
  if(error)return showToast(/au moins un CQ/i.test(error.message)?'Un club doit garder au moins un CQ : nomme d\'abord un autre CQ':error.message,'err');
  if(!data?.length)return showToast('Retrait refusé','err');
  showToast('Rôle retiré','ok');ptRenderFiche(club);
}

// ------------------------------------------------------------ CRÉATION D'UN CLUB
// Passe par create_club() (même fonction que pour un CQ) : l'admin en devient CQ le temps
// de la création ; si l'email du vrai CQ est donné, il est nommé CQ et l'admin se retire.
function ptRenderCreation(){
  const el=document.getElementById('plateforme-content');
  el.innerHTML=`<button class="bsec logo-btn" style="margin-bottom:12px" onclick="ptView=null;renderPlateforme()">← Tous les clubs</button>
  <div class="card">
    <div class="club-sec">Nouveau club</div>
    <div class="fg"><label class="fl">Nom *</label><input class="fi" id="pn-nom" placeholder="ex : RFC Hannut"></div>
    <div class="frow">
      <div class="fg"><label class="fl">Province</label><select class="sel" id="pn-prov"><option value="">—</option>${refs.provinces.map(p=>`<option value="${p.id}">${esc(p.nom)}</option>`).join('')}</select></div>
      <div class="fg"><label class="fl">Matricule</label><input class="fi" id="pn-mat" inputmode="numeric"></div>
    </div>
    <div class="fg"><label class="fl">Adresse du terrain *</label><input class="fi" id="pn-adr" placeholder="rue, n°, code postal, commune"></div>
    <div class="fg"><label class="fl">Email du CQ (compte FootCoach existant)</label><input class="fi" id="pn-cq" type="email" placeholder="facultatif — sinon tu restes CQ provisoire">
      <div style="font-size:11px;color:var(--text3);margin-top:5px">Le CQ peut aussi être nommé plus tard depuis la fiche du club.</div></div>
    <label style="display:flex;align-items:center;gap:8px;font-size:13px;margin:4px 0 12px"><input type="checkbox" id="pn-verif" checked> Marquer le club comme vérifié</label>
    <button class="bp" id="pn-ok" onclick="ptCreerClub()">Créer le club</button>
  </div>`;
  document.getElementById('pn-nom').focus();
}
async function ptCreerClub(){
  const g=x=>document.getElementById(x);
  const nom=g('pn-nom').value.trim(),adr=g('pn-adr').value.trim(),email=g('pn-cq').value.trim().toLowerCase();
  if(!nom)return showToast('Nom du club obligatoire','err');
  if(!adr)return showToast('Adresse du terrain obligatoire','err');
  const btn=g('pn-ok');btn.disabled=true;btn.textContent='Création…';
  const fin=()=>{btn.disabled=false;btn.textContent='Créer le club';};
  // CQ vérifié AVANT la création : pas de club créé à moitié pour une faute de frappe
  let cq=null;
  if(email){
    const r=await sb.rpc('find_profile_by_email',{e:email});
    cq=Array.isArray(r.data)?r.data[0]:r.data;
    if(!cq){fin();return showToast('Aucun compte FootCoach avec cet email','err');}
  }
  const{data:id,error}=await sb.rpc('create_club',{p_nom:nom,p_province_id:parseInt(g('pn-prov').value)||null,p_matricule:g('pn-mat').value.trim()||null,p_adresse:adr});
  if(error){fin();return showToast(/matricule|unique|duplicate/i.test(error.message)?'Ce matricule est déjà utilisé par un autre club':error.message,'err');}
  const msgs=[];
  const pos=await geocodeAdresse(adr);   // sans bloquer : la position peut être corrigée dans la fiche
  const upd=pos?{lat:pos.lat,lng:pos.lng}:{};
  if(g('pn-verif').checked)upd.verifie=true;
  if(Object.keys(upd).length){const u=await sb.from('clubs').update(upd).eq('id',id);if(u.error)msgs.push('mise à jour : '+u.error.message);}
  if(!pos)msgs.push('adresse introuvable sur la carte');
  if(cq&&cq.id!==U.id){
    const a=await sb.from('club_members').insert({club_id:id,profile_id:cq.id,role:'cq'}).select('id');
    if(a.error||!a.data?.length)msgs.push('CQ non nommé');
    else await sb.from('club_members').delete().eq('club_id',id).eq('profile_id',U.id);   // l'admin se retire
  }
  showToast(`Club « ${nom} » créé`+(msgs.length?' — '+msgs.join(', '):''),msgs.length?'err':'ok');
  ptView=id;renderPlateforme();
}
