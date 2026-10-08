import { createGroundRibbon } from './routes.mjs';

// Sparse land-use traces, not random decorative population or new stage locations.
export function createEnvironment(THREE,data,mode,terrain) {
  const group=new THREE.Group();group.name=`ENVIRONMENT_${mode}`;
  group.userData={role:'Candidate environmental traces derived from existing areas and routes',notGameplayEntry:true};
  const metrics={fields:0,canalFragments:0,roadsidePads:0,foothillRocks:0,forestRemains:0,crossings:[]};
  if(mode==='base')return {group,metrics};
  const places=new Map(data.places.map(p=>[p.id,p])),xy=p=>typeof p==='string'?places.get(p).xy:p;
  const roads=data.routes.filter(r=>r.kind!=='boat').map(r=>({id:r.id,points:r.points.map(xy)}));
  const materials={};
  for(const [id,color] of Object.entries({canal:0x777973,bank:0xbbb29e,field:0x9f9c8e,pad:0xa7a89d,rock:0x969992,concrete:0x969ea0,dark:0x626a6d}))materials[id]=new THREE.MeshStandardMaterial({color,roughness:1,side:THREE.DoubleSide});
  const cube=new THREE.BoxGeometry(1,1,1),rockGeometry=new THREE.IcosahedronGeometry(1,0);
  const step=mode==='region'?.25:.075,width=mode==='region'?.11:.04;
  function sub(id,role,sourceRef){const g=new THREE.Group();g.name='ENV_'+id;g.userData={environmentId:id,designRole:role,sourceRef,candidate:true};group.add(g);return g;}
  function inside(p,poly){let hit=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++)if((poly[i][1]>p[1])!==(poly[j][1]>p[1])&&p[0]<(poly[j][0]-poly[i][0])*(p[1]-poly[i][1])/(poly[j][1]-poly[i][1])+poly[i][0])hit=!hit;return hit;}
  function inView(p,pad=0){const b=terrain.bounds;return p[0]>=b[0]+pad&&p[0]<=b[1]-pad&&p[1]>=b[2]+pad&&p[1]<=b[3]-pad;}
  function distance(p,a,b){const dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy||1)));return Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy);}
  function roadDistance(p){let d=Infinity;for(const r of roads)for(let i=1;i<r.points.length;i++)d=Math.min(d,distance(p,r.points[i-1],r.points[i]));return d;}
  function avoidsPlaces(p,r){return data.places.filter(n=>!['cluster','water','junction'].includes(n.kind)).every(n=>Math.hypot(p[0]-n.xy[0],p[1]-n.xy[1])>r);}
  function ribbon(target,id,points,stripWidth,material,options={}){
    const built=createGroundRibbon(THREE,points,terrain,{width:stripWidth,step,lift:mode==='region'?.7:.25,...options});if(!built)return;
    const mesh=new THREE.Mesh(built.geometry,materials[material]);mesh.name=id;mesh.userData={environmentId:target.userData.environmentId,sourceRef:target.userData.sourceRef};target.add(mesh);
  }
  function solid(target,id,p,w,d,hM,material='concrete',rotation=0,liftM=0,geometry=cube){
    if(!inView(p))return;
    const mesh=new THREE.Mesh(geometry,materials[material]);mesh.name=id;mesh.position.copy(terrain.world(p,hM/2+liftM));mesh.scale.set(w,hM/1000*terrain.verticalExaggeration,d);mesh.rotation.y=rotation;mesh.userData={environmentId:target.userData.environmentId,sourceRef:target.userData.sourceRef};target.add(mesh);return mesh;
  }

  const canal=sub('canal-remains','失养渠岸与断口','water:old-canal');
  const oldCanal=data.water.find(w=>w.id==='old-canal');
  if(oldCanal){
    const ps=oldCanal.points.map(xy);
    for(let i=1;i<ps.length;i++){
      const a=ps[i-1],b=ps[i],length=Math.hypot(b[0]-a[0],b[1]-a[1]);
      const count=Math.ceil(length/(mode==='region'?1.8:.9));
      for(let j=0;j<count;j++){
        const t=(j+.5)/count,p=[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];
        if(j%5===2||!inView(p)||roadDistance(p)<.6||!avoidsPlaces(p,mode==='region'?3:1.6))continue;
        const ta=(j+.12)/count,tb=(j+.84)/count;
        const start=[a[0]+(b[0]-a[0])*ta,a[1]+(b[1]-a[1])*ta],end=[a[0]+(b[0]-a[0])*tb,a[1]+(b[1]-a[1])*tb];
        if([0,.25,.5,.75,1].some(t=>roadDistance([start[0]+(end[0]-start[0])*t,start[1]+(end[1]-start[1])*t])<.6))continue;
        ribbon(canal,'dry-channel-'+i+'-'+j,[start,end],width*2.2,'canal');
        const off=[-(b[1]-a[1])/length*width*1.4,(b[0]-a[0])/length*width*1.4];
        ribbon(canal,'channel-bank-'+i+'-'+j,[start.map((v,k)=>v+off[k]),end.map((v,k)=>v+off[k])],width*.7,'bank');metrics.canalFragments++;
      }
    }
  }
  const fieldGroup=sub('field-remains','旧田网与失养地块','area:oldirrigation');
  const area=data.areas.find(a=>a.id==='oldirrigation');
  if(area){let id=0;
    for(let x=7;x<28;x+=3)for(let y=1;y<16;y+=2.8){
      const p=[x+(id%2)*.28,y],w=1.8,d=1.4;id++;
      if(!inside(p,area.polygon)||!inView(p,1)||roadDistance(p)<1.3||!avoidsPlaces(p,mode==='region'?4:2.8))continue;
      const corners=[[p[0]-w/2,p[1]-d/2],[p[0]+w/2,p[1]-d/2],[p[0]+w/2,p[1]+d/2],[p[0]-w/2,p[1]+d/2]];
      if(!corners.every(q=>inside(q,area.polygon)&&roadDistance(q)>.4))continue;
      ribbon(fieldGroup,'abandoned-plot-'+id,[[p[0]-w/2,p[1]],[p[0]+w/2,p[1]]],d,'field');
      ribbon(fieldGroup,'field-bank-'+id,[corners[0],corners[1],corners[2]],width*.7,'bank');
      if(id%3===0)ribbon(fieldGroup,'broken-furrow-'+id,[[p[0]-.4,p[1]-.6],[p[0]-.4,p[1]+.55]],width*.55,'canal');metrics.fields++;
    }
  }

  const logistics=sub('logistics-junctions','物流分岔与路侧空场','routes:assault,industry-fort,depot-spur');
  for(const [i,p]of [[0,[28.7,20]],[1,[16.4,12]],[2,[47.2,31]]]){
    if(!inView(p,1)||!avoidsPlaces(p,2))continue;
    ribbon(logistics,'empty-hardstand-'+i,[[p[0]-.65,p[1]],[p[0]+.65,p[1]]],.65,'pad');
    ribbon(logistics,'yard-side-'+i,[[p[0]-.68,p[1]+.36],[p[0]+.68,p[1]+.36]],width,'dark');metrics.roadsidePads++;
  }
  const piedmont=sub('piedmont-rubble','山前碎石与裸露坡面','place:foothill;water:surface-river');
  const river=data.water.find(w=>w.kind==='surface').points.map(xy);
  for(let i=0;i<18;i++){
    const p=[-51+(i%6)*3.2,65+Math.floor(i/6)*5.4+(i%2)*1.3];
    if(!inView(p)||!avoidsPlaces(p,3)||roadDistance(p)<1.3||river.some((q,j)=>j&&distance(p,river[j-1],q)<2))continue;
    solid(piedmont,'slope-rock-'+i,p,.7+(i%3)*.25,.4,35+(i%4)*12,'rock',i*.17,0,rockGeometry);metrics.foothillRocks++;
  }
  const remains=sub('forest-fringe-remains','旧聚落至林缘的退化带','route:ruins-forest;area:forestenvironment');
  for(let i=0;i<7;i++){
    const p=[21-i*.85, -30.9-i*.5];
    if(!inView(p)||roadDistance(p)<.55)continue;
    solid(remains,'old-foundation-'+i,p,.48,.35,4,'dark');
    solid(remains,'broken-wall-'+i,[p[0]-.2,p[1]],.05,.36,12+(i%3)*5,'concrete');metrics.forestRemains++;
  }

  function crossing(a,b,c,d){const rx=b[0]-a[0],ry=b[1]-a[1],sx=d[0]-c[0],sy=d[1]-c[1],cross=rx*sy-ry*sx;if(Math.abs(cross)<1e-8)return null;const qx=c[0]-a[0],qy=c[1]-a[1],t=(qx*sy-qy*sx)/cross,u=(qx*ry-qy*rx)/cross;return t>=0&&t<=1&&u>=0&&u<=1?[a[0]+t*rx,a[1]+t*ry]:null;}
  const bridges=sub('water-crossings','跨水桥涵接口候选','road and surface-river intersections');
  for(const road of roads)for(let i=1;i<road.points.length;i++)for(let j=1;j<river.length;j++){
    const a=road.points[i-1],b=road.points[i],p=crossing(a,b,river[j-1],river[j]);
    if(!p||!inView(p,.6)||metrics.crossings.some(c=>Math.hypot(c.xy[0]-p[0],c.xy[1]-p[1])<.8))continue;
    const dx=b[0]-a[0],dy=b[1]-a[1],angle=Math.atan2(dy,dx),len=Math.hypot(dx,dy),u=[dx/len,dy/len];
    const width=mode==='region'?.48:.22,span=mode==='region'?1.3:.65;
    solid(bridges,'bridge-deck-'+metrics.crossings.length,p,span,width,4,'concrete',angle,6);
    for(const sign of [-1,1])solid(bridges,'abutment-'+metrics.crossings.length+'-'+sign,[p[0]+u[0]*span*.38*sign,p[1]+u[1]*span*.38*sign],.15,width,9,'rock',angle);
    metrics.crossings.push({xy:p,routeId:road.id,status:'candidate interface, approach grades and structural capacity not verified'});
  }
  group.userData.metrics=metrics;return {group,metrics};
}
