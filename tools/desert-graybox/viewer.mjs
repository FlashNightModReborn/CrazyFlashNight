import { THREE, createGraybox, disposeGraybox } from './model.mjs';
import { OrbitControls } from '../../launcher/web/assets/stage-diorama/base-gate/vendor/OrbitControls.js';
import { GAME_FRAME, gameFrame } from './composition.mjs';
import { createStyleStudy } from './style-study.mjs';
import { createLocalDetail } from './local-detail.mjs';
import { createLocalGround } from './local-ground.mjs';
import { createLocalRoads } from './local-roads.mjs';
import { captureCamera, restoreCamera, createLocalLocator } from './local-navigation.mjs';

const $ = id => document.getElementById(id);
const host = $('viewport'), loading = $('loading'), labels = $('label-layer'), lines = $('label-lines');
const data = await fetch('/layout.json').then(r => { if (!r.ok) throw new Error('Layout unavailable'); return r.json(); });
const places = new Map(data.places.map(n => [n.id,n]));
let renderer, scene, camera, controls, model, outline, frame = 0, mode = 'region', selected = 'base', projection = 'orthographic';
let labelItems = [], pointerStart = null, framing = null, usingGameFrame = true;
let study = null, hemisphere, sun;
let local = null, localDetail = null, localGround = null, localRoads = null;
const stagePlaces=[...new Set(data.stageMapping.filter(n=>n.id.startsWith('stage_')&&n.place).map(n=>n.place))];
const locator=createLocalLocator($('locator-map'),data);
const comparisonFrame = new URLSearchParams(location.search).has('compare');
if (comparisonFrame) document.body.classList.add('comparison-frame');
const isStudy = () => mode === 'region' && $('appearance').value === 'study';
const primaryPlaces = data.stageMapping.filter(n=>n.place).map(n=>n.place);
const raycaster = new THREE.Raycaster(), pointer = new THREE.Vector2();
const names = {region:'区域总览',city:'城市接合',base:'基地近区'};
const direction = new THREE.Vector3(.62,.94,1.15).normalize();
function fail(error) { console.error(error); loading.hidden=false; loading.textContent='灰模未能显示：'+error.message;host.dataset.state='error'; }
function invalidate() { if (!frame) frame=requestAnimationFrame(render); }
function render() {
  frame=0;if(!renderer||!model)return;
  if (scene.fog) { const distance = camera.position.distanceTo(controls.target); scene.fog.near=distance+45; scene.fog.far=distance+180; }
  renderer.render(scene,camera);updateLabels();
}
function captureView() {
  return {mode,selected,projection,usingGameFrame,camera:captureCamera(camera,controls),surroundings:model.surroundings.visible,
    framing:framing?{min:framing.box.min.toArray(),max:framing.box.max.toArray(),north:framing.north,minimum:framing.minimum}:null};
}
function restoreView(view) {
  projection=view.projection;$('projection').value=projection;connectCamera();
  usingGameFrame=view.usingGameFrame;framing=view.framing?{box:new THREE.Box3(new THREE.Vector3().fromArray(view.framing.min),new THREE.Vector3().fromArray(view.framing.max)),north:view.framing.north,minimum:view.framing.minimum}:null;
  model.surroundings.visible=view.surroundings;
  for(const name of ['cut-earth-sidewalls','solid-bottom'])model.terrain.group.getObjectByName(name).visible=!view.surroundings;
  restoreCamera(camera,controls,view.camera);invalidate();
}
function updateShadow() {
  const [x0,x1,y0,y1]=model.terrain.bounds;
  let extent=Math.max(x1-x0,y1-y0),target=new THREE.Vector3((x0+x1)/2,0,-(y0+y1)/2);
  if(local&&activeAnchor()) {
    const box=new THREE.Box3().setFromObject(activeAnchor().object),size=box.getSize(new THREE.Vector3());
    extent=Math.max(size.x,size.y*2,size.z,1)*1.5;target=box.getCenter(new THREE.Vector3());
  }
  sun.target.position.copy(target);sun.position.copy(target).add(new THREE.Vector3(-.8,1.1,.7).multiplyScalar(extent));
  sun.shadow.camera.left=sun.shadow.camera.bottom=-extent*.75;
  sun.shadow.camera.right=sun.shadow.camera.top=extent*.75;
  sun.shadow.camera.near=.01;sun.shadow.camera.far=extent*4;sun.shadow.camera.updateProjectionMatrix();
  sun.shadow.bias=-.000012;sun.shadow.normalBias=local?Math.max(.00008,extent*.000016):.008;sun.shadow.radius=2;
  if(!isStudy()){sun.position.set(-60,140,80);sun.target.position.set(0,0,0);}
  renderer.shadowMap.needsUpdate=true;
}
function refreshLocalGeometry() {
  localDetail?.hide();localGround?.hide();localRoads?.hide();
  if(local&&isStudy()){localDetail?.show(selected);localGround?.show(selected);localRoads?.show(selected);}
  syncTraffic();
}
function syncTraffic(){model.routes.group.visible=$('traffic').checked&&!(local&&isStudy());if(localRoads)localRoads.group.visible=$('traffic').checked&&!!local&&isStudy();}
function updateLocalUI() {
  $('local-bar').hidden=$('local-locator').hidden=!local;host.dataset.local=String(!!local);
  if(!local)return;
  const index=stagePlaces.indexOf(selected),zone=activeAnchor()?.object.children.find(o=>o.userData.subareaId===local.zoneId);
  $('local-title').textContent=places.get(selected).name+(zone?' · '+zone.userData.designRole:'');
  $('local-whole').hidden=!local.zoneId;
  $('local-index').textContent=index<0?'地点近看':`${index+1} / ${stagePlaces.length}`;
  $('previous-place').disabled=index<=0;$('next-place').disabled=index<0||index>=stagePlaces.length-1;
  locator.update(selected);$('view-status').textContent=(zone?'功能分区':'地点近看')+' · '+places.get(selected).name;
}
function endLocal() {
  localDetail?.hide();localGround?.hide();localRoads?.hide();local=null;syncTraffic();updateLocalUI();createLabels();updateSelection();updateShadow();
}
function returnToOverview() {
  if(!local)return;const bookmark=local.bookmark;endLocal();selected=bookmark.selected;
  if(mode!==bookmark.mode)setMode(bookmark.mode,false);
  restoreView(bookmark);createLabels();updateSelection();updateShadow();
  $('view-status').textContent=names[mode]+(isStudy()?' · 风格样板 · 地理位置保留':' · 可继续修改的灰模');
}
function returnToPlace() {
  if(!local)return;
  if(local.placeView)restoreView(local.placeView);
  local.zoneId=null;local.placeView=null;createLabels();updateSelection();updateLocalUI();
}
function focusZone(zone) {
  if(!local)focusPlace();
  if(!local)return;
  if(!local.zoneId)local.placeView=captureView();
  local.zoneId=zone.userData.subareaId;
  for(const b of $('subarea-buttons').children)b.setAttribute('aria-pressed',String(b.dataset.zone===local.zoneId));
  for(const item of labelItems)item.button.setAttribute('aria-pressed',String(item.zone?.userData.subareaId===local.zoneId));
  highlight(zone);const anchor=activeAnchor(),box=new THREE.Box3().setFromObject(zone);
  if(!box.isEmpty()){const dir=camera.position.clone().sub(controls.target).normalize();box.expandByScalar((anchor.focusSpan||1)*.025);frameBox(box,false,(anchor.focusSpan||1)*.32,dir);}
  updateLocalUI();invalidate();
}
function applyAppearance() {
  localDetail?.hide();localGround?.hide();
  const enabled=isStudy(); study?.setEnabled(enabled); host.dataset.study=String(enabled);
  $('appearance').disabled=mode!=='region';
  $('study-note').textContent=mode==='region'?'风格样板保留地理位置，试验地貌色域、建筑剪影与接地阴影。可切回空间灰模，比较同一镜头。':'风格样板先在区域总览试验；此处保留原空间灰模，检查局部关系。';
  hemisphere.intensity=enabled?.7:2.1; sun.intensity=enabled?2.3:2.2;
  hemisphere.color.set(enabled?'#d5e0ec':'#ffffff'); hemisphere.groundColor.set(enabled?'#514032':'#68717a');
  sun.color.set(enabled?'#fff0d6':'#ffffff'); sun.castShadow=enabled;
  renderer.shadowMap.enabled=enabled; renderer.shadowMap.needsUpdate=true;
  renderer.setClearColor(enabled?'#736552':'#c8cace');
  scene.fog=enabled?new THREE.Fog('#867967',1000,2000):null;
  refreshLocalGeometry();updateShadow();
  for (const group of [model.terrain.group,model.surroundings]) group.traverse(o=>{if(o.isMesh)o.castShadow=false;});
  $('view-status').textContent=names[mode]+(enabled?' · 风格样板 · 地理位置保留':' · 可继续修改的灰模');
  $('scale-note').textContent=enabled?'荒漠 · 区域景观样板':('1024 × 576 · '+(mode==='base'?'近区占地候选':'地标体量放大')+' · 高程显示 ×'+model.terrain.verticalExaggeration);
  createLabels();updateSelection();updateLocalUI();invalidate();
}
function cameraFor(kind) {
  return kind==='orthographic'?new THREE.OrthographicCamera(-100,100,60,-60,.005,4000):new THREE.PerspectiveCamera(28,1,.005,4000);
}
function connectCamera() {
  controls?.dispose();camera=cameraFor(projection);controls=new OrbitControls(camera,renderer.domElement);
  controls.enableDamping=false;controls.minPolarAngle=.02;controls.maxPolarAngle=Math.PI*.49;
  controls.screenSpacePanning=true;controls.addEventListener('change',invalidate);
}
function frameBox(box, north=false, minimum=0, viewDirection=null) {
  usingGameFrame=false;
  framing={box:box.clone(),north,minimum};
  const target=box.getCenter(new THREE.Vector3()), size=box.getSize(new THREE.Vector3());
  const dir=viewDirection|| (north?new THREE.Vector3(0,1,.0001):direction.clone());
  const aspect=GAME_FRAME.aspect;
  camera.position.copy(target).addScaledVector(dir,Math.max(size.length()*2,1));camera.up.set(0,1,0);camera.lookAt(target);camera.updateMatrixWorld(true);
  const inv=camera.matrixWorldInverse, coords=[];
  for(const x of [box.min.x,box.max.x])for(const y of [box.min.y,box.max.y])for(const z of [box.min.z,box.max.z])coords.push(new THREE.Vector3(x,y,z).applyMatrix4(inv));
  const width=Math.max(...coords.map(p=>p.x))-Math.min(...coords.map(p=>p.x));
  const height=Math.max(...coords.map(p=>p.y))-Math.min(...coords.map(p=>p.y));
  const vertical=Math.max(height,width/aspect,minimum/aspect,.1)*1.15;
  if(camera.isOrthographicCamera){camera.left=-vertical*aspect/2;camera.right=vertical*aspect/2;camera.top=vertical/2;camera.bottom=-vertical/2;camera.zoom=1;}
  else{camera.aspect=aspect;const distance=vertical/2/Math.tan(THREE.MathUtils.degToRad(camera.fov/2))+size.length()*.35;camera.position.copy(target).addScaledVector(dir,distance);}
  camera.near=Math.max(.00005,size.length()/10000);camera.far=Math.max(size.length()*20,10);camera.updateProjectionMatrix();
  controls.target.copy(target);controls.minDistance=Math.max(.0005,size.length()*.005);controls.maxDistance=Math.max(10,size.length()*8);controls.update();invalidate();
}
function overview(north=false) {
  if(local)endLocal();
  model.surroundings.visible=false;
  for(const name of ['cut-earth-sidewalls','solid-bottom'])model.terrain.group.getObjectByName(name).visible=true;
  const box=new THREE.Box3().setFromObject(model.terrain.group);frameBox(box,north);
}
function compose() {
  if(local)endLocal();
  const fitted=gameFrame(THREE,model,data,mode,projection);usingGameFrame=true;framing=null;
  model.surroundings.visible=true;
  for(const name of ['cut-earth-sidewalls','solid-bottom'])model.terrain.group.getObjectByName(name).visible=false;
  camera.position.copy(fitted.position);camera.up.set(0,1,0);camera.lookAt(fitted.target);
  if(camera.isOrthographicCamera){camera.left=-fitted.horizontal/2;camera.right=fitted.horizontal/2;camera.top=fitted.vertical/2;camera.bottom=-fitted.vertical/2;camera.zoom=1;}
  else{camera.aspect=GAME_FRAME.aspect;camera.fov=fitted.fov;}
  camera.near=fitted.near;camera.far=fitted.far;camera.updateProjectionMatrix();
  controls.target.copy(fitted.target);controls.minDistance=fitted.horizontal*.002;controls.maxDistance=fitted.horizontal*10;controls.update();invalidate();
}
function resize() {
  if(!renderer)return;const w=host.clientWidth,h=host.clientHeight;
  renderer.setSize(GAME_FRAME.width,GAME_FRAME.height,false);
  if(camera?.isPerspectiveCamera){camera.aspect=GAME_FRAME.aspect;camera.updateProjectionMatrix();}
  else if(camera){const v=camera.top-camera.bottom;camera.left=-v*GAME_FRAME.aspect/2;camera.right=v*GAME_FRAME.aspect/2;camera.updateProjectionMatrix();}
  invalidate();
}
function activeAnchor() { return model.anchors.find(a=>a.id===selected); }
function highlight(object) {
  if(outline){outline.geometry.dispose();outline.material.dispose();scene.remove(outline);outline=null;}
  if(object&&!isStudy()){outline=new THREE.BoxHelper(object,0x638fa8);outline.material.depthTest=false;outline.material.transparent=true;outline.material.opacity=.8;outline.renderOrder=10;scene.add(outline);}
}
function updateSelection() {
  const n=places.get(selected);$('place').value=selected;$('place-name').textContent=n.name;$('place-description').textContent=n.detail;
  const [x,y]=n.xy;$('coordinates').textContent=(x<0?'西 ':'东 ')+Math.abs(x)+' km · '+(y<0?'南 ':'北 ')+Math.abs(y)+' km（候选锚点）';
  const anchor=activeAnchor();$('focus').disabled=!anchor;
  highlight(anchor?.object);
  const zones=anchor?.object.children.filter(o=>o.isGroup&&o.userData.designRole)||[];
  $('subareas').hidden=!zones.length;$('subarea-buttons').replaceChildren();
  for(const zone of zones){const button=document.createElement('button');button.type='button';button.textContent=zone.userData.designRole;button.dataset.zone=zone.userData.subareaId;button.title=zone.userData.designDescription||zone.userData.label||zone.userData.designRole;button.setAttribute('aria-pressed',String(local?.zoneId===zone.userData.subareaId));button.addEventListener('click',()=>focusZone(zone));$('subarea-buttons').appendChild(button);}
  for(const item of labelItems)item.button.setAttribute('aria-pressed',String(item.zone?local?.zoneId===item.zone.userData.subareaId:item.anchor.id===selected));
  invalidate();
}
function labelPriority(id) {
  if(id===selected)return -100;
  const primary=primaryPlaces.indexOf(id);if(primary>=0)return primary-30;
  const fixed=['base','fort','secret','forest','snow','frontbase','waste','fallen','commune','field2','frontgate'];
  const i=fixed.indexOf(id);return i<0?50:i;
}
function createLabels() {
  labels.replaceChildren();labelItems=[];
  if(local) {
    const zones=activeAnchor()?.object.children.filter(o=>o.isGroup&&o.userData.designRole)||[];
    for(const zone of zones) {
      const box=new THREE.Box3().setFromObject(zone);if(box.isEmpty())continue;
      const b=document.createElement('button');b.type='button';b.className='map-label local-label';b.textContent=zone.userData.designRole;b.dataset.zone=zone.userData.subareaId;
      b.title=zone.userData.designDescription||zone.userData.designRole;b.setAttribute('aria-pressed',String(local.zoneId===zone.userData.subareaId));b.addEventListener('click',()=>focusZone(zone));labels.appendChild(b);
      labelItems.push({anchor:{id:selected,world:box.getCenter(new THREE.Vector3()),object:zone},button:b,zone});
    }
    return;
  }
  for(const anchor of model.anchors){
    if(['well','storage','eastjunction','supplygroup'].includes(anchor.id))continue;
    const b=document.createElement('button');b.type='button';b.className='map-label';b.textContent=anchor.name;b.dataset.place=anchor.id;
    b.dataset.context=String(!primaryPlaces.includes(anchor.id));
    b.title=anchor.name+' · 点击放大';b.setAttribute('aria-pressed',String(anchor.id===selected));b.addEventListener('click',()=>choose(anchor.id,true));labels.appendChild(b);
    labelItems.push({anchor,button:b});
  }
}
function updateLabels() {
  const w=host.clientWidth,h=host.clientHeight;lines.replaceChildren();lines.setAttribute('viewBox',`0 0 ${w} ${h}`);
  const north=new THREE.Vector3(0,0,-1).transformDirection(camera.matrixWorldInverse);
  const angle=Math.atan2(north.x,north.y)*180/Math.PI;
  const arrow=['↑','↗','→','↘','↓','↙','←','↖'][(Math.round(angle/45)+8)%8];$('north-note').textContent='地理北 '+arrow;
  labels.hidden=!$('labels').checked;lines.hidden=!$('labels').checked;if(labels.hidden)return;
  const occupied=[{x:0,y:h-54,w,h:54}];
  if(local){occupied.push({x:0,y:0,w,h:48});occupied.push({x:w-Math.min(178,w*.25)-12,y:h-150,w:Math.min(178,w*.25)+12,h:150});}
  const items=labelItems.slice().sort((a,b)=>labelPriority(a.anchor.id)-labelPriority(b.anchor.id));
  const maxLabels=w<500?7:mode==='region'?14:12;let count=0;
  for(const item of items){
    const {anchor,button}=item;const pos=anchor.world.clone().project(camera);
    button.hidden=true;
    if(local?.zoneId&&item.zone?.userData.subareaId!==local.zoneId)continue;
    if(isStudy()&&usingGameFrame&&anchor.id!==selected&&!primaryPlaces.includes(anchor.id)&&!['snow','forest','waste','fallen'].includes(anchor.id))continue;
    if(pos.z<-1||pos.z>1||pos.x<-1.05||pos.x>1.05||pos.y<-1.05||pos.y>1.05||count>=maxLabels)continue;
    const q={x:(pos.x+1)/2*w,y:(1-pos.y)/2*h};button.hidden=false;const bw=button.offsetWidth,bh=button.offsetHeight;
    const offsets=[[0,-25],[0,28],[bw/2+12,0],[-bw/2-12,0],[0,-62],[0,64],[bw/2+12,-45],[-bw/2-12,-45],[0,-98],[0,100],[bw/2+24,70],[-bw/2-24,70]];let best=null;
    for(const [dx,dy] of offsets){const x=Math.max(4,Math.min(w-bw-4,q.x+dx-bw/2)),y=Math.max(4,Math.min(h-bh-55,q.y+dy-bh/2));const box={x,y,w:bw,h:bh};if(occupied.every(r=>x+bw+5<r.x||r.x+r.w+5<x||y+bh+5<r.y||r.y+r.h+5<y)){best=box;break;}}
    if(!best){button.hidden=true;continue;}count++;occupied.push(best);button.style.left=best.x+bw/2+'px';button.style.top=best.y+bh/2+'px';
    const target={x:best.x+bw/2,y:best.y+bh/2};const dx=target.x-q.x,dy=target.y-q.y,k=Math.max(Math.abs(dx)/(bw/2),Math.abs(dy)/(bh/2),1);
    const line=document.createElementNS('http://www.w3.org/2000/svg','line');Object.entries({x1:q.x,y1:q.y,x2:target.x-dx/k,y2:target.y-dy/k,stroke:isStudy()?(anchor.id===selected?'#edcd82':'#c5b79c'):(anchor.id===selected?'#26485f':'#505b64'),'stroke-width':1,opacity:.8}).forEach(([a,v])=>line.setAttribute(a,v));lines.appendChild(line);
    if(isStudy()) {const dot=document.createElementNS('http://www.w3.org/2000/svg','circle');Object.entries({cx:q.x,cy:q.y,r:anchor.id===selected?4:2.5,fill:'#2e2922',stroke:anchor.id===selected?'#e9c274':'#ba9d6c','stroke-width':1.3}).forEach(([a,v])=>dot.setAttribute(a,v));lines.appendChild(dot);}
  }
}
function choose(id, focus=false) {
  const priorLocal=local,sourceView=priorLocal?.bookmark||captureView();
  selected=id;
  const changedMode=!activeAnchor();
  if(changedMode)setMode(places.get(id).views.includes('base')?'base':places.get(id).views.includes('city')?'city':'region',false);
  if(priorLocal)local={bookmark:priorLocal.bookmark,placeId:id,zoneId:null,placeView:null};
  updateSelection();
  const projected=activeAnchor()?.world.clone().project(camera);
  if(focus||priorLocal||changedMode||projected&&(Math.abs(projected.x)>.92||Math.abs(projected.y)>.88||Math.abs(projected.z)>1))focusPlace(sourceView);
}
function focusPlace(bookmark=null) {
  const anchor=activeAnchor();if(!anchor)return;
  if(!local)local={bookmark:bookmark||captureView(),placeId:selected,zoneId:null,placeView:null};
  local.placeId=selected;local.zoneId=null;local.placeView=null;
  refreshLocalGeometry();updateShadow();createLabels();updateLocalUI();
  highlight(anchor.object);for(const b of $('subarea-buttons').children)b.setAttribute('aria-pressed','false');
  const box=new THREE.Box3().setFromObject(anchor.object);if(box.isEmpty())box.setFromCenterAndSize(anchor.world,new THREE.Vector3(.5,.1,.5));
  const size=box.getSize(new THREE.Vector3()),extent=Math.max(size.x,size.y,size.z,.1);
  const span=Math.min(anchor.focusSpan||extent,extent*1.15),dir=camera.position.clone().sub(controls.target).normalize();box.expandByScalar(extent*.055);frameBox(box,false,span,dir);
}
function setMode(next, resetSelected=true) {
  localDetail?.dispose();localGround?.dispose();localRoads?.dispose();localDetail=null;localGround=null;localRoads=null;local=null;updateLocalUI();
  study?.dispose();study=null;
  if(model)disposeGraybox(model);mode=next;if(resetSelected)selected='base';
  model=createGraybox(data,mode);scene.add(model.group);model.routes.waterGroup.visible=$('water').checked;
  if(mode==='region'){study=createStyleStudy(THREE,model,data);localDetail=createLocalDetail(THREE,model,data);localGround=createLocalGround(THREE,model,data);localRoads=createLocalRoads(THREE,model,data);}
  model.routes.group.visible=$('traffic').checked;
  document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.mode===mode)));
  const symbol=mode==='base'?'近区占地候选':'地标体量放大';$('scale-note').textContent='1024 × 576 · '+symbol+' · 高程显示 ×'+model.terrain.verticalExaggeration;
  $('view-status').textContent=names[mode]+' · 可继续修改的灰模';$('model-link').href='/models/desert-'+mode+'.glb';
  createLabels();applyAppearance();compose();host.dataset.state='ready';loading.hidden=true;
}
function fillPicker(){
  const mapped=new Set();const games=document.createElement('optgroup');games.label='关卡与导航';
  for(const n of data.stageMapping.filter(n=>n.place)){const o=document.createElement('option');o.value=n.place;o.textContent=n.name;games.appendChild(o);mapped.add(n.place);}$('place').appendChild(games);
  const extras=document.createElement('optgroup');extras.label='地理与局部地标';
  for(const n of data.places.filter(n=>!mapped.has(n.id)&&n.views.length)){const o=document.createElement('option');o.value=n.id;o.textContent=n.name;extras.appendChild(o);}$('place').appendChild(extras);
}
try {
  renderer=new THREE.WebGLRenderer({antialias:true,powerPreference:'low-power'});renderer.setPixelRatio(1);
  renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.NoToneMapping;renderer.setClearColor(0xc8cace);
  renderer.domElement.setAttribute('aria-label','可旋转的荒漠三维灰模');host.prepend(renderer.domElement);
  renderer.shadowMap.type=THREE.PCFSoftShadowMap;renderer.shadowMap.autoUpdate=false;
  scene=new THREE.Scene();hemisphere=new THREE.HemisphereLight(0xffffff,0x68717a,2.1);scene.add(hemisphere);
  sun=new THREE.DirectionalLight(0xffffff,2.2);sun.position.set(-60,140,80);sun.shadow.mapSize.set(4096,4096);scene.add(sun,sun.target);
  connectCamera();fillPicker();resize();setMode('region');
  document.querySelectorAll('[data-mode]').forEach(b=>b.addEventListener('click',()=>setMode(b.dataset.mode)));
  $('appearance').addEventListener('change',applyAppearance);
  $('projection').addEventListener('change',()=>{
    if(usingGameFrame){projection=$('projection').value;connectCamera();compose();return;}
    const dir=camera.position.clone().sub(controls.target).normalize();
    const nextBox=framing.box.clone().translate(controls.target.clone().sub(framing.box.getCenter(new THREE.Vector3())));
    const saved={...framing,box:nextBox};projection=$('projection').value;connectCamera();frameBox(saved.box,saved.north,saved.minimum,dir);
  });
  $('overview').addEventListener('click',compose);$('whole').addEventListener('click',()=>overview());$('north').addEventListener('click',()=>overview(true));
  $('place').addEventListener('change',()=>choose($('place').value));$('focus').addEventListener('click',()=>focusPlace());
  $('return-view').addEventListener('click',returnToOverview);$('local-whole').addEventListener('click',returnToPlace);
  for(const [id,step] of [['previous-place',-1],['next-place',1]])$(id).addEventListener('click',()=>{const i=stagePlaces.indexOf(selected);if(i>=0&&stagePlaces[i+step])choose(stagePlaces[i+step],true);});
  window.addEventListener('keydown',e=>{if(e.key!=='Escape'||!local||/INPUT|SELECT|TEXTAREA/.test(e.target.tagName))return;e.preventDefault();if(local.zoneId)returnToPlace();else returnToOverview();});
  $('labels').addEventListener('change',invalidate);$('water').addEventListener('change',()=>{model.routes.waterGroup.visible=$('water').checked;invalidate();});
  $('traffic').addEventListener('change',()=>{syncTraffic();invalidate();});
  renderer.domElement.addEventListener('pointerdown',e=>{pointerStart=[e.clientX,e.clientY];});
  renderer.domElement.addEventListener('pointerup',e=>{if(!pointerStart||Math.hypot(e.clientX-pointerStart[0],e.clientY-pointerStart[1])>5)return;const r=renderer.domElement.getBoundingClientRect();pointer.set((e.clientX-r.left)/r.width*2-1,-(e.clientY-r.top)/r.height*2+1);raycaster.setFromCamera(pointer,camera);for(const hit of raycaster.intersectObjects(model.landmarks.pickMeshes,true)){let o=hit.object;while(o&&!o.userData.placeId)o=o.parent;if(o&&places.has(o.userData.placeId)){choose(o.userData.placeId,true);break;}}});
  renderer.domElement.addEventListener('webglcontextlost',e=>{e.preventDefault();fail(new Error('三维画面已中断，请刷新此页'));});
  new ResizeObserver(resize).observe(host);
  window.addEventListener('pagehide',()=>{cancelAnimationFrame(frame);controls.dispose();localDetail?.dispose();localGround?.dispose();localRoads?.dispose();study?.dispose();disposeGraybox(model);sun.shadow.dispose();renderer.dispose();});
} catch(error) {fail(error);}
