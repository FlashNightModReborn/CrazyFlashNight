// Camera bookmarks contain numbers only, never references into a disposable model.
export function captureCamera(camera, controls) {
  return {
    position: camera.position.toArray(), quaternion: camera.quaternion.toArray(), up: camera.up.toArray(),
    target: controls.target.toArray(), near: camera.near, far: camera.far, zoom: camera.zoom,
    left: camera.left, right: camera.right, top: camera.top, bottom: camera.bottom,
    fov: camera.fov, aspect: camera.aspect, minDistance: controls.minDistance, maxDistance: controls.maxDistance,
  };
}

export function restoreCamera(camera, controls, view) {
  camera.position.fromArray(view.position); camera.quaternion.fromArray(view.quaternion); camera.up.fromArray(view.up);
  for (const key of ['near','far','zoom','left','right','top','bottom','fov','aspect']) if (view[key] !== undefined) camera[key] = view[key];
  camera.updateProjectionMatrix(); camera.updateMatrixWorld(true);
  controls.target.fromArray(view.target); controls.minDistance=view.minDistance; controls.maxDistance=view.maxDistance;
  controls.update();
}

export function createLocalLocator(svg, data) {
  const ns='http://www.w3.org/2000/svg', places=new Map(data.places.map(p=>[p.id,p]));
  const [x0,x1,y0,y1]=data.views.region.bounds, w=168,h=116,pad=9;
  const project=xy=>[pad+(xy[0]-x0)/(x1-x0)*(w-pad*2),h-pad-(xy[1]-y0)/(y1-y0)*(h-pad*2)];
  const node=(tag,attrs)=>{const e=document.createElementNS(ns,tag);for(const[k,v]of Object.entries(attrs))e.setAttribute(k,v);svg.appendChild(e);return e;};
  svg.setAttribute('viewBox',`0 0 ${w} ${h}`);
  for(const area of data.areas.filter(a=>['mountains','forestenvironment','wastecity','fallencity'].includes(a.id))) {
    node('polygon',{points:area.polygon.map(p=>project(p).join(',')).join(' '),fill:area.id==='forestenvironment'?'#536047':'#645b4c',opacity:.6});
  }
  for(const route of data.routes.filter(r=>r.views?.includes('region')&&r.kind!=='boat')) {
    const points=route.points.map(p=>typeof p==='string'?places.get(p)?.xy:p).filter(Boolean);
    node('polyline',{points:points.map(p=>project(p).join(',')).join(' '),fill:'none',stroke:'#968363','stroke-width':.65,opacity:.8});
  }
  const ids=[...new Set(data.stageMapping.filter(n=>n.place).map(n=>n.place))];
  for(const id of ids){const[x,y]=project(places.get(id).xy);node('circle',{cx:x,cy:y,r:1.6,fill:'#b7ab8d'});}
  const halo=node('circle',{r:6,fill:'none',stroke:'#e9c97b','stroke-width':1.1});
  const dot=node('circle',{r:2.8,fill:'#f4d790'});
  return {
    update(id) { const p=places.get(id);if(!p)return;const[x,y]=project(p.xy);for(const e of[halo,dot]){e.setAttribute('cx',x);e.setAttribute('cy',y);}svg.setAttribute('aria-label',p.name+'在荒漠区域中的位置，北向上');svg.dataset.place=id; },
  };
}
