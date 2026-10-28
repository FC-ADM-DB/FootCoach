// ============ TOURNOIS : CALCULS COMMUNS (app + page publique tournoi.html) ============
// Fonctions pures, sans Supabase ni DOM : programme (poules / mini-championnat), classement,
// phase finale. Les équipes de la phase finale ne sont jamais enregistrées : elles sont
// déduites à l'affichage des codes source (« P:A:1 » = 1er de la poule A, « V:3 » =
// vainqueur du match n° 3), donc toujours à jour quand un score change.
const TC_POULES='ABCDEFGH';

// Matchs aller simple d'un groupe (méthode « du cercle ») : liste de tours
function tcRonde(ids){
  const l=ids.slice();if(l.length<2)return [];
  if(l.length%2)l.push(null);
  const n=l.length,tours=[];
  for(let r=0;r<n-1;r++){
    const t=[];
    for(let i=0;i<n/2;i++){const a=l[i],b=l[n-1-i];if(a&&b)t.push(r%2?[b,a]:[a,b]);}
    tours.push(t);
    l.splice(1,0,l.pop());
  }
  return tours;
}
// Répartition en poules (serpentin : A B C C B A…) si les poules ne sont pas déjà faites
function tcRepartir(equipes,nb){
  const ok=equipes.length&&equipes.every(e=>e.poule&&TC_POULES.indexOf(e.poule)>=0&&TC_POULES.indexOf(e.poule)<nb);
  if(ok&&nb>1)return equipes.map(e=>({id:e.id,poule:e.poule}));
  return equipes.map((e,i)=>{const k=Math.floor(i/nb),r=i%nb;return {id:e.id,poule:nb===1?'A':TC_POULES[k%2?nb-1-r:r]};});
}
const tcMin=h=>{const[a,b]=(h||'09:00').split(':').map(Number);return a*60+b;};
const tcHeure=m=>String(Math.floor(m/60)%24).padStart(2,'0')+':'+String(m%60).padStart(2,'0');
const tcRang=r=>r===1?'1er':r+'e';
function tcNomTour(nbMatchs){return nbMatchs===1?'Finale':nbMatchs===2?'Demi-finale':nbMatchs===4?'Quart de finale':'1/8 de finale';}
const tcAbrTour=n=>n===1?'F':n===2?'DF':n===4?'QF':'HF';

// Programme complet d'un tableau → {poules:[{id,poule}], matchs:[…]} prêts à enregistrer.
// Créneaux : « terrains » matchs en même temps, une équipe ne joue jamais deux fois
// dans le même créneau ; la phase finale suit les poules.
function tcProgramme(tb,equipes){
  const nb=tb.formule==='championnat'?1:Math.max(1,Math.min(tb.nb_poules||1,Math.floor(equipes.length/2)||1));
  const poules=tcRepartir(equipes,nb);
  // Tours de chaque poule, entremêlés (tour 1 de A, tour 1 de B, tour 2 de A…)
  const parPoule={};poules.forEach(p=>(parPoule[p.poule]=parPoule[p.poule]||[]).push(p.id));
  const toursP=Object.keys(parPoule).sort().map(k=>tcRonde(parPoule[k]).map(t=>t.map(m=>({a:m[0],b:m[1],poule:k}))));
  const file=[];const maxT=Math.max(0,...toursP.map(t=>t.length));
  for(let r=0;r<maxT;r++)toursP.forEach(t=>{if(t[r])file.push(...t[r].map(m=>({...m,tour:r+1})));});
  const T=Math.max(1,tb.terrains||1),pas=(tb.duree_match||12)+(tb.pause||0),d0=tcMin(tb.debut);
  const matchs=[];let creneau=0,ordre=0;
  while(file.length){
    const occ=new Set(),dans=[];
    for(let i=0;i<file.length&&dans.length<T;i++){const m=file[i];if(!occ.has(m.a)&&!occ.has(m.b)){occ.add(m.a);occ.add(m.b);dans.push(i);}}
    dans.sort((x,y)=>x-y).forEach((i,k)=>{const m=file[i];matchs.push({phase:'poule',poule:m.poule,tour:m.tour,equipe_a:m.a,equipe_b:m.b,terrain:(tb.terrain1||1)+k,heure:tcHeure(d0+creneau*pas),ordre:++ordre});});
    for(let j=dans.length-1;j>=0;j--)file.splice(dans[j],1);
    creneau++;
  }
  // Phase finale : qualifiés = les k premiers de chaque poule ; 1er contre dernier qualifié
  const Q=tb.formule==='championnat'?0:(tb.qualifies||0);
  if(Q>=2){
    const k=Math.max(1,Math.ceil(Q/nb)),cles=Object.keys(parPoule).sort(),seeds=[];
    for(let r=1;r<=k;r++)cles.forEach(p=>{if(seeds.length<Q)seeds.push('P:'+(nb===1?'':p)+':'+r);});
    let tour=1;
    let paires=[];for(let i=0;i<seeds.length/2;i++)paires.push([seeds[i],seeds[seeds.length-1-i]]);
    // Tableau classique : vainqueur du match i contre vainqueur du match n-1-i
    while(paires.length){
      const n=paires.length,cur=[];
      for(let i=0;i<n;i++){
        const o=++ordre;
        matchs.push({phase:'finale',tour,libelle:tcNomTour(n)+(n>1?' '+(i+1):''),source_a:paires[i][0],source_b:paires[i][1],
          terrain:(tb.terrain1||1)+(i%T),heure:tcHeure(d0+(creneau+Math.floor(i/T))*pas),ordre:o});
        cur.push(o);
      }
      creneau+=Math.ceil(n/T);
      if(n===1)break;
      paires=[];for(let i=0;i<n/2;i++)paires.push(['V:'+cur[i],'V:'+cur[n-1-i]]);
      tour++;
    }
  }
  return {poules,matchs};
}

// Classement de chaque poule (matchs de poule terminés) : points, différence, buts marqués
function tcClassement(tb,equipes,matchs){
  const lignes={};
  equipes.forEach(e=>lignes[e.id]={eq:e,poule:e.poule||'A',j:0,v:0,n:0,d:0,bp:0,bc:0,pts:0});
  matchs.filter(m=>m.phase==='poule'&&m.statut==='termine'&&m.score_a!=null&&m.score_b!=null).forEach(m=>{
    const a=lignes[m.equipe_a],b=lignes[m.equipe_b];if(!a||!b)return;
    a.j++;b.j++;a.bp+=m.score_a;a.bc+=m.score_b;b.bp+=m.score_b;b.bc+=m.score_a;
    if(m.score_a>m.score_b){a.v++;b.d++;}else if(m.score_a<m.score_b){b.v++;a.d++;}else{a.n++;b.n++;}
  });
  const pv=tb.pts_v??3,pn=tb.pts_n??1,pd=tb.pts_d??0,res={};
  Object.values(lignes).forEach(l=>{l.pts=l.v*pv+l.n*pn+l.d*pd;l.diff=l.bp-l.bc;(res[l.poule]=res[l.poule]||[]).push(l);});
  Object.values(res).forEach(t=>t.sort((x,y)=>y.pts-x.pts||y.diff-x.diff||y.bp-x.bp||x.eq.nom.localeCompare(y.eq.nom)));
  return res;
}
// Une poule est finie quand tous ses matchs sont terminés
const tcPouleFinie=(matchs,p)=>{const l=matchs.filter(m=>m.phase==='poule'&&(m.poule||'A')===p);return l.length>0&&l.every(m=>m.statut==='termine');};
// Vainqueur d'un match terminé ('a' / 'b'), égalité départagée par les tirs au but
function tcGagnant(m){
  if(!m||m.statut!=='termine'||m.score_a==null||m.score_b==null)return null;
  if(m.score_a!==m.score_b)return m.score_a>m.score_b?'a':'b';
  return m.vainqueur||null;
}
// Équipes réelles de chaque match (poules : enregistrées ; finale : déduites) → {idMatch:{a,b}}
function tcResoudre(tb,equipes,matchs){
  const cl=tcClassement(tb,equipes,matchs),parOrdre={},res={};
  matchs.forEach(m=>parOrdre[m.ordre]=m);
  const src=code=>{
    if(!code)return null;
    const p=code.split(':');
    if(p[0]==='P'){const poule=p[1]||'A',r=+p[2];if(!tcPouleFinie(matchs,poule))return null;return cl[poule]?.[r-1]?.eq.id||null;}
    if(p[0]==='V'){const m=parOrdre[+p[1]];const g=tcGagnant(m);if(!g)return null;const e=res[m.id]||{};return g==='a'?e.a:e.b;}
    return null;
  };
  matchs.slice().sort((x,y)=>(x.ordre||0)-(y.ordre||0)).forEach(m=>{
    res[m.id]=m.phase==='finale'?{a:m.equipe_a||src(m.source_a),b:m.equipe_b||src(m.source_b)}:{a:m.equipe_a,b:m.equipe_b};
  });
  return res;
}
// Libellé lisible d'un code source : « 1er poule A », « 2e », « Vainqueur DF1 »
function tcSource(code,matchs){
  if(!code)return '?';
  const p=code.split(':');
  if(p[0]==='P')return tcRang(+p[2])+(p[1]?' poule '+p[1]:'');
  if(p[0]==='V'){const m=matchs.find(x=>x.ordre===+p[1]);if(!m)return 'Vainqueur';const n=matchs.filter(x=>x.phase==='finale'&&x.tour===m.tour).length;
    const i=(m.libelle||'').match(/(\d+)$/);return 'Vainqueur '+tcAbrTour(n)+(i?i[1]:'');}
  return code;
}
