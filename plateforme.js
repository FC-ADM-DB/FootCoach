// ============ PLATEFORME D'ADMINISTRATION (admin plateforme uniquement) ============
// Chargé après app.js. Les droits sont vérifiés par la base : fonctions admin_*
// (supabase/2026-10-24-P1-plateforme.sql) et règles des tables clubs / niveaux.
// Ici : vérifier les clubs, voir tous les clubs, gérer les niveaux (renommer, fusionner).

let isPlatformAdmin=false,ptTab='attente',ptClubs=[],ptQ='';
async function loadPlatformAdmin(){
  isPlatformAdmin=false;
  try{
    const{data}=await sb.from('platform_admins').select('profile_id').eq('profile_id',U.id);
    isPlatformAdmin=!!data?.length;
  }catch(e){}
  const m=document.getElementById('umenu-plateforme');
  if(m)m.style.display=isPlatformAdmin?'flex':'none';
}
const ptDate=d=>d?new Date(d).toLocaleDateString('fr-BE',{day:'numeric',month:'short',year:'numeric'}):'';

async function renderPlateforme(){
  const el=document.getElementById('plateforme-content');
  if(!isPlatformAdmin){el.innerHTML=`<div class="empty"><div class="empty-i">🔒</div><div class="empty-t">Réservé à l'administrateur FootCoach</div></div>`;return;}
  el.innerHTML='<div class="spin"></div>';
  const [st,cl]=await Promise.all([sb.rpc('admin_stats'),sb.rpc('admin_clubs')]);
  if(st.error||cl.error){el.innerHTML=`<div class="empty"><div class="empty-i">⚠️</div><div class="empty-t">Plateforme indisponible</div><div class="empty-s">${esc((st.error||cl.error).message)}</div></div>`;return;}
  const s=st.data?.[0]||{};ptClubs=cl.data||[];
  const tile=(n,l,c)=>`<div class="pt-tile${c?' '+c:''}"><div class="pt-n">${n??'—'}</div><div class="pt-l">${l}</div></div>`;
  const tab=(k,l)=>`<button class="${ptTab===k?'on':''}" onclick="ptTab='${k}';renderPlateforme()">${l}</button>`;
  el.innerHTML=`<div class="pt-tiles">${tile(s.clubs,'Clubs')}${tile(s.clubs_verifies,'Vérifiés')}${tile(s.clubs_en_attente,'À vérifier',s.clubs_en_attente?'warn':'')}${tile(s.equipes,'Équipes')}${tile(s.utilisateurs,'Utilisateurs')}${tile(s.annonces_publiees,'Annonces')}</div>
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
    return `<div class="card rs-card">
      <div class="rs-top"><div class="rs-logo">${l?`<img class="team-logo" src="${l}" alt="">`:'🏟'}</div>
        <div style="flex:1;min-width:0"><div class="rs-club">${esc(c.nom)}</div><div class="rs-sub">${esc([c.province,c.matricule?'matricule '+c.matricule:''].filter(Boolean).join(' · ')||'Province non précisée')}</div></div>
        ${c.verifie?'<span class="pill pg">✓ Vérifié</span>':'<span class="pill pgr">⏳ En attente</span>'}</div>
      <div class="rs-line">📍 ${esc(c.adresse||'Adresse non renseignée')} ${c.position_connue?'':'<span style="color:var(--amber)">· position inconnue</span>'}</div>
      <div class="rs-line">👤 CQ : ${esc(c.cq||'aucun')} ${c.cq_email?`· <a href="mailto:${esc(c.cq_email)}" style="color:var(--blue)">${esc(c.cq_email)}</a>`:''}</div>
      <div class="rs-line">⚽ ${c.nb_equipes} équipe${c.nb_equipes>1?'s':''} · ${c.nb_membres} membre${c.nb_membres>1?'s':''} · ${c.nb_annonces} annonce${c.nb_annonces>1?'s':''} publiée${c.nb_annonces>1?'s':''} · inscrit le ${esc(ptDate(c.created_at))}</div>
      <div class="rs-acts">
        ${c.verifie?`<button class="bsec" onclick="ptVerifier('${c.id}',false)">Retirer la vérification</button>`:`<button class="bp rs-act" onclick="ptVerifier('${c.id}',true)">✓ Vérifier ce club</button>`}
        ${c.nb_equipes===0?`<button class="bred" onclick="ptSupprClub('${c.id}')">Supprimer</button>`:''}
      </div>
    </div>`;}).join('');
}
async function ptVerifier(id,v){
  const c=ptClubs.find(x=>x.id===id);
  const msg=v?`Vérifier « ${c?.nom} » ? Il pourra publier et voir les annonces des autres clubs.`
             :`Retirer la vérification de « ${c?.nom} » ? Il ne verra plus les annonces et les siennes ne seront plus visibles.`;
  if(!await askConfirm(msg))return;
  const{data,error}=await sb.from('clubs').update({verifie:v}).eq('id',id).select('id');
  if(error||!data?.length)return showToast(error?.message||'Action refusée','err');
  showToast(v?'Club vérifié':'Vérification retirée','ok');renderPlateforme();
}
async function ptSupprClub(id){
  const c=ptClubs.find(x=>x.id===id);
  if(!await askConfirm(`Supprimer définitivement le club « ${c?.nom} » ? (il n'a aucune équipe)`))return;
  const{data,error}=await sb.from('clubs').delete().eq('id',id).select('id');
  if(error||!data?.length)return showToast(error?.message||'Suppression refusée','err');
  showToast('Club supprimé','ok');renderPlateforme();
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
