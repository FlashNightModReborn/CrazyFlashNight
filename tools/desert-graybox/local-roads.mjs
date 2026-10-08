import { createGroundRibbon } from './routes.mjs';

// The same route centre lines, drawn with a narrower symbolic width when close.
// This layer never replaces the regional source network or claims surveyed width.
export function createLocalRoads(THREE, model, data) {
  const group=new THREE.Group();group.name='LOCAL_ROUTE_PRESENTATION';group.visible=false;
  group.userData={candidate:true,notGameplayEntry:true,role:'narrow local presentation of unchanged source routes'};
  model.group.add(group);
  const places=new Map(data.places.map(p=>[p.id,p]));
  const material=new THREE.MeshStandardMaterial({color:'#776751',roughness:1,side:THREE.DoubleSide,polygonOffset:true,polygonOffsetFactor:-1,polygonOffsetUnits:-1});
  function clear(){for(const mesh of group.children)mesh.geometry.dispose();group.clear();}
  function show(placeId) {
    clear();const anchor=model.anchors.find(a=>a.id===placeId);if(!anchor){group.visible=false;return;}
    const box=new THREE.Box3().setFromObject(anchor.object),size=box.getSize(new THREE.Vector3());
    const extent=Math.max(size.x,size.z,2),radius=extent*2.4,p=places.get(placeId).xy;
    const terrain={...model.terrain,bounds:[p[0]-radius,p[0]+radius,p[1]-radius,p[1]+radius]};
    const width=Math.min(.10,Math.max(.045,extent*.015));
    // A local view also reveals existing minor branches omitted from the regional
    // overview (for example the refugee/depot exchange path). No route is invented.
    for(const route of data.routes.filter(r=>r.kind!=='boat')) {
      const points=route.points.map(p=>typeof p==='string'?places.get(p).xy:p);
      const ribbon=createGroundRibbon(THREE,points,terrain,{width,step:.08,lift:1.05,dashed:route.kind==='candidate'});
      if(!ribbon)continue;
      const mesh=new THREE.Mesh(ribbon.geometry,material);mesh.name='LOCAL_'+route.id;mesh.receiveShadow=true;
      mesh.userData={sourceRouteId:route.id,widthKm:width,symbolicWidth:true,centreLineUnchanged:true};group.add(mesh);
    }
    group.userData.placeId=placeId;group.visible=true;
  }
  return {group,show,hide(){group.visible=false;},dispose(){clear();material.dispose();group.removeFromParent();}};
}
