// Bookshelf presentation only; Host/AS2 retain reading, original games and save authority.
import * as THREE from '../assets/stage-diorama/base-gate/vendor/three.module.js';
import {GLTFLoader} from '../assets/stage-diorama/base-gate/vendor/GLTFLoader.js';
import {validateEmbeddedGlb} from './bookshelf-shelf-config.js';
import {chooseLayout} from './bookshelf/shelf/layout-core.mjs';
import {applyLayout} from './bookshelf/shelf/layout-three.js';
import {initialState,reduce,fitSpan,gestureMoved,ease} from './bookshelf/shelf/interaction-core.mjs';
const rootUrl=new URL('../assets/bookshelf/shelf/',import.meta.url);
const labels={dust:'尘都诡谈',babylon:'光明巴比伦',guardian:'守护之力','sail-twins':'风帆双子','crazy-flasher':'闪客快打 CF1–6 合集'};
function release(root){const gs=new Set(),ms=new Set(),ts=new Set();root.traverse(n=>{if(n.geometry)gs.add(n.geometry);for(const m of [].concat(n.material||[])){ms.add(m);for(const v of Object.values(m))if(v?.isTexture)ts.add(v);}});gs.forEach(g=>g.dispose());ms.forEach(m=>m.dispose());ts.forEach(t=>{t.source?.data?.close?.();t.dispose();});}
export async function createScene(options,onLost,onSelect,signal){
 const ab=new AbortController(),abort=()=>ab.abort();signal?.addEventListener('abort',abort,{once:true});
 if(signal?.aborted)throw new DOMException('Aborted','AbortError');
 const deadline=setTimeout(()=>ab.abort(),15000);let root,modelHash;
 try{
  const [response,receipt]=await Promise.all([fetch(new URL('v3.glb',rootUrl),{signal:ab.signal}),fetch(new URL('v4-manifest.json',rootUrl),{signal:ab.signal})]);
  if(!response.ok||!receipt.ok)throw Error('shelf_asset_unavailable');
  const manifest=await receipt.json(),bytes=await response.arrayBuffer();
  if(manifest.schema!=='bookshelf-interactive.v4'||manifest.model!=='v3.glb'||!(/^[a-f0-9]{64}$/.test(manifest.sha256))||manifest.audit?.bytes!==bytes.byteLength)throw Error('shelf_manifest_invalid');
  modelHash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
  if(modelHash!==manifest.sha256)throw Error('shelf_model_changed');
  validateEmbeddedGlb(bytes);if(ab.signal.aborted)throw new DOMException('Aborted','AbortError');
  root=(await new GLTFLoader().parseAsync(bytes,rootUrl.href)).scene;
  if(ab.signal.aborted){release(root);throw new DOMException('Aborted','AbortError');}
 }catch(e){signal?.removeEventListener('abort',abort);throw e;}finally{clearTimeout(deadline);}
 const scene=new THREE.Scene();scene.background=new THREE.Color('#131b23');scene.add(root);
 let renderer;try{renderer=new THREE.WebGLRenderer({antialias:true,powerPreference:'low-power'});}catch(error){release(root);signal?.removeEventListener('abort',abort);throw error;}renderer.setPixelRatio(1);renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.12;
 const canvas=renderer.domElement;canvas.className='bookshelf-shelf-canvas';canvas.tabIndex=0;canvas.setAttribute('aria-label','拖动浏览书架，滚轮缩放，单击物件查看；Escape 收回，Home 回总览');canvas.style.touchAction='none';
 const camera=new THREE.OrthographicCamera(-20,20,12,-12,.01,2000),bounds=new THREE.Box3(),center=new THREE.Vector3();
 const hemi=new THREE.HemisphereLight(0xcbdfff,0x404352,2);scene.add(hemi);const key=new THREE.DirectionalLight(0xffeedb,3);key.position.set(-20,40,30);scene.add(key);const fill=new THREE.DirectionalLight(0xb7d5ff,1);fill.position.set(20,20,15);scene.add(fill);
 const entries=new Map(),names={dust:'BOOK_dust',babylon:'BOOK_babylon',guardian:'BOOK_guardian','sail-twins':'BOOK_sail-twins','crazy-flasher':'COLLECTION_CF1_6'};
 for(const[id,name]of Object.entries(names)){const n=root.getObjectByName(name);if(n)entries.set(id,n);}
 const drawer=root.getObjectByName('ARCHIVE_ALL_DRAWER');
 let disposed=false,frames=0,w=options?.width||802,h=options?.height||481,layout='',state=initialState(),raf=0,animation=null,resizeTimer=0,layoutLockedUntil=0,drawerRest=0,focus=null,focusSource=null,collection=null,collectionSource=null,focusReady=false;
 let baseSpan=1,overviewZoom=1;const ray=new THREE.Raycaster(),pointers=new Map();let pointerStart=null,last=null,dragged=false,multi=false,pinch=0;
 const reduced=matchMedia('(prefers-reduced-motion: reduce)');
 const ui=document.createElement('div');ui.className='v4-scene-ui';ui.innerHTML='<div class="v4-browser-tools"><button data-cmd="home">回总览</button><button data-cmd="minus" aria-label="缩小">−</button><button data-cmd="plus" aria-label="放大">＋</button><button data-cmd="drawer">全部档案</button></div><section class="v4-inspector" hidden aria-label="物件检视"><strong class="v4-selection"></strong><p class="v4-help"></p><div class="v4-disc-list"></div><div class="v4-actions"><button data-cmd="return">收回</button><button data-cmd="open">直接打开 / 查看详情</button></div><div class="v4-archive-detail"></div></section><span class="v4-layout-label"></span>';
 const inspector=ui.querySelector('.v4-inspector'),detail=ui.querySelector('.v4-archive-detail');
 let archiveData=[],archiveSignature='';const liveLabels=new Map();
 function labelFor(group,prefix,title,subtitle){
  let mesh;group.traverse(node=>{if(node.isMesh&&(node.userData?.name||node.name).replace(/[._\s]/g,'').startsWith(prefix.replace(/\s/g,'')))mesh=node;});
  if(!mesh)return;
  const surface=document.createElement('canvas');surface.width=1024;surface.height=256;
  const context=surface.getContext?.('2d');if(!context)return;
  context.fillStyle='#dfd8c4';context.fillRect(0,0,1024,256);context.fillStyle='#25323c';
  context.font='bold 96px "Microsoft YaHei",sans-serif';context.fillText(title.length>24?title.slice(0,23)+'…':title,38,116,948);
  context.font='52px "Microsoft YaHei",sans-serif';context.fillText(subtitle,38,209,948);
  let record=liveLabels.get(mesh);
  if(!record){record={material:mesh.material,texture:mesh.material.map};mesh.material=mesh.material.clone();liveLabels.set(mesh,record);}
  else mesh.material.map.dispose();
  mesh.material.map=new THREE.CanvasTexture(surface);mesh.material.map.flipY=false;mesh.material.map.colorSpace=THREE.SRGBColorSpace;mesh.material.needsUpdate=true;
 }
 function render(){if(!disposed){renderer.render(scene,camera);frames++;}}
 function measure(){bounds.makeEmpty();root.updateMatrixWorld(true);root.traverse(n=>{if(n.isMesh&&n.visible){let visible=true;for(let p=n.parent;p;p=p.parent)if(!p.visible)visible=false;if(visible)bounds.expandByObject(n);}});bounds.getCenter(center);}
 function cameraUpdate(resetSpan=true){
  const target=focus?focus.position.clone():center.clone();if(collection&&!focus)target.copy(collection.position);
  const dist=160,dir=new THREE.Vector3(Math.sin(state.yaw)*Math.cos(state.pitch),Math.sin(state.pitch),Math.cos(state.yaw)*Math.cos(state.pitch));
  camera.position.copy(target).addScaledVector(dir,dist);camera.lookAt(target);camera.updateMatrixWorld(true);
  const box=focus?new THREE.Box3().setFromObject(focus):collection?new THREE.Box3().setFromObject(collection):bounds;
  const points=[];for(const x of[box.min.x,box.max.x])for(const y of[box.min.y,box.max.y])for(const z of[box.min.z,box.max.z])points.push(new THREE.Vector3(x,y,z).applyMatrix4(camera.matrixWorldInverse));
  if(resetSpan)baseSpan=fitSpan(points,w/h,focus||collection?1.65:1.15);
  const span=baseSpan/state.zoom;camera.left=-span*w/h/2;camera.right=span*w/h/2;camera.top=span/2;camera.bottom=-span/2;camera.updateProjectionMatrix();
 }
 function updateUI(){
  inspector.hidden=state.mode==='overview';ui.querySelector('.v4-layout-label').textContent='拖动旋转 · 滚轮缩放 · Home 回总览';
  ui.querySelector('.v4-selection').textContent=state.drawer?'全部常驻角色档案':state.disc?state.disc.toUpperCase():labels[state.selected]||archiveData.find(x=>x.id===state.selected)?.name||'物件';
  ui.querySelector('.v4-help').textContent=state.drawer?'选择档案查看角色详情。':state.selected?.startsWith('slot:')?'先查看角色详情，再选择是否切换角色。':focusReady?'拖动物件旋转查看；随时收回或直接打开。':'正在抽出，完成后可旋转；可随时收回。';
  const discs=ui.querySelector('.v4-disc-list');discs.replaceChildren();if(state.selected==='crazy-flasher'){for(let i=1;i<=6;i++){const b=document.createElement('button');b.textContent='CF'+i;b.dataset.disc='cf'+i;b.setAttribute('aria-pressed',String(state.disc==='cf'+i));discs.append(b);}}
  detail.replaceChildren();if(state.drawer){for(const item of archiveData){const b=document.createElement('button');b.textContent=item.name+(item.active?' · 当前角色':'')+' · 查看详情';b.dataset.archive=item.id;detail.append(b);}}else if(state.selected?.startsWith('slot:')){const item=archiveData.find(x=>x.id===state.selected);detail.textContent=(item?.name||'角色档案')+(item?.active?'\n当前角色':'');}
  ui.querySelector('[data-cmd="open"]').hidden=state.drawer||!state.selected;
  ui.querySelector('[data-cmd="drawer"]').disabled=!archiveData.length;
 }
 function cancelAnimation(){if(raf)cancelAnimationFrame(raf);raf=0;animation=null;}
 function restoreObjects(){for(const id of pointers.keys()){if(canvas.hasPointerCapture?.(id))canvas.releasePointerCapture(id);}pointers.clear();pointerStart=null;last=null;dragged=true;multi=true;pinch=0;cancelAnimation();if(focus){scene.remove(focus);focus=null;}if(focusSource){focusSource.visible=true;focusSource=null;}if(collection){scene.remove(collection);collection=null;}if(collectionSource){collectionSource.visible=true;collectionSource=null;}focusReady=false;if(drawer)drawer.position.z=drawerRest;}
 // A detached clone shares GPU assets; only the original tree disposes them.
 function extracted(source){root.updateMatrixWorld(true);const pivot=new THREE.Group(),clone=source.clone(true);clone.visible=true;const box=new THREE.Box3().setFromObject(source),c=box.getCenter(new THREE.Vector3());source.getWorldPosition(clone.position);source.getWorldQuaternion(clone.quaternion);source.getWorldScale(clone.scale);clone.position.sub(c);pivot.position.copy(c);pivot.add(clone);scene.add(pivot);source.visible=false;return pivot;}
 function animateExtract(pivot,done){
  const start=pivot.position.clone(),front=Math.max(bounds.max.z+8,start.z+8),mid=start.clone().setZ(front),end=new THREE.Vector3(center.x,center.y,front+3),epoch=state.epoch;focusReady=false;
  const finish=()=>{pivot.position.copy(end);focusReady=true;cameraUpdate();updateUI();render();done?.();};
  if(reduced.matches){finish();return;}
  const started=performance.now();animation={epoch};
  function tick(now){raf=0;if(disposed||state.epoch!==epoch||!animation)return;const t=Math.min(1,(now-started)/620);if(t<.45)pivot.position.lerpVectors(start,mid,ease(t/.45));else pivot.position.lerpVectors(mid,end,ease((t-.45)/.55));cameraUpdate();render();if(t<1)raf=requestAnimationFrame(tick);else{animation=null;finish();}}raf=requestAnimationFrame(tick);
 }
 function select(id){if(disposed)return;if(id==='slot:__more__'){drawers(true);return;}if(!entries.has(id)&&!archiveData.some(item=>item.id===id))return;if(state.mode==='overview'||state.mode==='drawer')overviewZoom=state.zoom;restoreObjects();state=reduce(state,{type:'SELECT',id});state.zoom=id.startsWith('slot:')?overviewZoom:1;
  if(id.startsWith('slot:')){focusReady=true;cameraUpdate();updateUI();render();return;}
  const source=entries.get(id);if(id==='crazy-flasher'){collectionSource=source;collection=extracted(source);animateExtract(collection);}else{focusSource=source;focus=extracted(source);animateExtract(focus);}updateUI();render();
 }
 function selectDisc(id){if(!/^cf[1-6]$/.test(id)||state.selected!=='crazy-flasher'||disposed)return;
  // Deterministic interruption: start from clean source and fully place the collection first.
  restoreObjects();state=reduce(state,{type:'SELECT',id:'crazy-flasher'});state=reduce(state,{type:'DISC',id});state.zoom=1;collectionSource=entries.get('crazy-flasher');collection=extracted(collectionSource);collection.position.set(center.x,center.y,bounds.max.z+8);collection.updateMatrixWorld(true);
  const source=collection.getObjectByName('DISC_CF'+id.slice(2));if(!source)return;focusSource=source;focus=extracted(source);animateExtract(focus);updateUI();render();
 }
 function goHome(reset=true){if(state.mode==='overview'||state.mode==='drawer')overviewZoom=state.zoom;restoreObjects();state=reduce(state,{type:reset?'HOME':'RETURN'});state.zoom=reset?1:overviewZoom;if(reset)overviewZoom=1;const next=chooseLayout(w/h,reset?'':layout);if(next!==layout&&(reset||performance.now()>=layoutLockedUntil)){apply(next);return;}cameraUpdate();updateUI();render();}
 function drawers(open){if(state.mode==='overview'||state.mode==='drawer')overviewZoom=state.zoom;const start=drawer?.position.z??drawerRest;restoreObjects();state=reduce(state,{type:'DRAWER',open});state.zoom=overviewZoom;const end=drawerRest+(open?3.15:0);if(drawer){drawer.position.z=reduced.matches?end:start;if(!reduced.matches&&start!==end){const epoch=state.epoch,began=performance.now();animation={epoch};function tick(now){raf=0;if(disposed||state.epoch!==epoch||!animation)return;const t=Math.min(1,(now-began)/360);drawer.position.z=start+(end-start)*ease(t);render();if(t<1)raf=requestAnimationFrame(tick);else animation=null;}raf=requestAnimationFrame(tick);}}cameraUpdate();updateUI();render();}
 function setArchives(items){
  if(disposed)return;
  const next=items.filter(item=>!item.more&&item.id!=='slot:__more__').map(item=>({id:item.id,name:item.name,active:!!item.active}));
  const signature=JSON.stringify(next);if(signature===archiveSignature)return;
  archiveSignature=signature;archiveData=next;
  for(const id of entries.keys())if(id.startsWith('slot:'))entries.delete(id);
  ['current','recent02','recent03'].forEach((suffix,index)=>{
   const node=root.getObjectByName('ARCHIVE_SHORTCUT_'+suffix),item=archiveData[index];
   if(node){node.visible=!!item;if(item){entries.set(item.id,node);labelFor(node,'Character folder label',item.name,item.active?'当前角色':'角色档案');}}
  });
  for(let index=0;index<5;index++){
   const folder=root.getObjectByName('DIRECTORY_FOLDER_'+(index+1)),item=archiveData[index];
   if(folder){folder.visible=!!item;if(item)labelFor(folder,'Demo directory label',item.name,item.active?'当前角色':'角色档案');}
  }
  if(drawer&&archiveData.length)entries.set('slot:__more__',drawer);
  if(state.selected?.startsWith('slot:')&&!archiveData.some(item=>item.id===state.selected))goHome(false);
  else{updateUI();render();}
 }
 function pick(e){const r=canvas.getBoundingClientRect();if(!r.width||!r.height)return '';ray.setFromCamera(new THREE.Vector2((e.clientX-r.left)/r.width*2-1,1-(e.clientY-r.top)/r.height*2),camera);const nodes=[...entries.values()].filter(n=>n.visible);for(const hit of ray.intersectObjects(nodes,true)){for(const[id,node]of entries){for(let n=hit.object;n;n=n.parent)if(n===node)return id;}}return '';}
 const coords=e=>({x:e.clientX,y:e.clientY});
 function down(e){if(e.button!==0&&e.pointerType!=='touch')return;canvas.focus({preventScroll:true});pointers.set(e.pointerId,coords(e));canvas.setPointerCapture?.(e.pointerId);if(pointers.size===1){pointerStart=coords(e);last=coords(e);dragged=false;multi=false;}else{multi=true;dragged=true;pinch=distance();}e.preventDefault();}
 function distance(){const p=[...pointers.values()];return p.length<2?0:Math.hypot(p[0].x-p[1].x,p[0].y-p[1].y);}
 function move(e){if(!pointers.has(e.pointerId)){canvas.style.cursor=pick(e)?'pointer':'grab';return;}pointers.set(e.pointerId,coords(e));if(pointers.size>1){const d=distance();if(pinch&&d)state=reduce(state,{type:'ZOOM',factor:d/pinch});pinch=d;cameraUpdate();render();return;}if(multi)return;const p=coords(e);if(gestureMoved(pointerStart,p))dragged=true;if(dragged){const dx=(p.x-last.x)*.007,dy=(p.y-last.y)*.006;if((focus||collection)&&focusReady){state=reduce(state,{type:'ROTATE',dx,dy});const object=focus||collection;object.rotation.set(state.objectPitch,state.objectYaw,0);cameraUpdate();}else if(!animation){state=reduce(state,{type:'ORBIT',dx:-dx,dy});cameraUpdate();}render();}last=p;}
 function up(e){if(!pointers.has(e.pointerId))return;const wasClick=!dragged&&!multi&&pointerStart&&!gestureMoved(pointerStart,coords(e));pointers.delete(e.pointerId);if(canvas.hasPointerCapture?.(e.pointerId))canvas.releasePointerCapture(e.pointerId);if(wasClick){const id=pick(e);if(id)select(id);}if(!pointers.size){pointerStart=null;last=null;multi=false;pinch=0;}}
 function cancel(e){pointers.delete(e.pointerId);dragged=true;multi=true;if(!pointers.size){pointerStart=null;last=null;pinch=0;}}
 function wheel(e){e.preventDefault();state=reduce(state,{type:'ZOOM',factor:Math.exp(-e.deltaY*.001)});cameraUpdate();render();}
 function keyboard(e){if(e.key==='Escape'){if(state.mode!=='overview'){goHome(false);e.preventDefault();e.stopPropagation?.();}else restoreObjects();}if(e.target&&e.target!==canvas)return;if(e.key==='Home'){goHome();e.preventDefault();}if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){state=reduce(state,{type:'ORBIT',dx:e.key==='ArrowLeft'?-.06:e.key==='ArrowRight'?.06:0,dy:e.key==='ArrowUp'?.03:e.key==='ArrowDown'?-.03:0});cameraUpdate();render();e.preventDefault();}}
 function uiClick(e){const b=e.target.closest('button');if(!b||b.disabled)return;if(b.dataset.disc)return selectDisc(b.dataset.disc);if(b.dataset.archive){const id=b.dataset.archive;if(archiveData.some(item=>item.id===id)){goHome(false);onSelect?.(id);}return;}switch(b.dataset.cmd){case 'home':goHome();break;case 'return':goHome(false);break;case 'drawer':drawers(!state.drawer);break;case 'plus':case 'minus':state=reduce(state,{type:'ZOOM',factor:b.dataset.cmd==='plus'?1.15:1/1.15});cameraUpdate();render();break;case 'open':{const id=state.selected,disc=state.disc;goHome(false);onSelect?.(id,disc);break;}}}
 function lost(e){e.preventDefault();if(!disposed)onLost?.();}
 const listeners=[['pointerdown',down],['pointermove',move],['pointerup',up],['pointercancel',cancel],['lostpointercapture',cancel],['wheel',wheel,{passive:false}],['keydown',keyboard],['webglcontextlost',lost]];listeners.forEach(a=>canvas.addEventListener(...a));ui.addEventListener('click',uiClick);ui.addEventListener('keydown',keyboard);
 function apply(key){restoreObjects();state=reduce(state,{type:'RETURN'});applyLayout(root,key,THREE);layout=key;drawerRest=drawer?.position.z||0;measure();cameraUpdate();updateUI();render();}
 function resize(width,height){if(disposed||!(width>0&&height>0))return;w=width;h=height;renderer.setSize(w,h,false);if(!layout){apply(chooseLayout(w/h));return;}cameraUpdate();render();clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{if(disposed||performance.now()<layoutLockedUntil||state.mode!=='overview')return;const next=chooseLayout(w/h,layout);if(next!==layout)apply(next);},350);}
 function lockLayout(ms=800){layoutLockedUntil=performance.now()+ms;clearTimeout(resizeTimer);}
 const mediaChange=()=>{if(animation)goHome(false);};reduced.addEventListener?.('change',mediaChange);
 function dispose(){if(disposed)return;disposed=true;cancelAnimation();clearTimeout(resizeTimer);ab.abort();signal?.removeEventListener('abort',abort);listeners.forEach(a=>canvas.removeEventListener(...a));ui.removeEventListener('click',uiClick);ui.removeEventListener('keydown',keyboard);reduced.removeEventListener?.('change',mediaChange);pointers.clear();restoreObjects();release(scene);for(const record of liveLabels.values()){record.material.dispose();record.texture?.source?.data?.close?.();record.texture?.dispose();}liveLabels.clear();renderer.renderLists.dispose();renderer.dispose();renderer.forceContextLoss();canvas.remove();ui.remove();}
 const api={canvas,ui,render,dispose,setArchives,drawers,select,selectDisc,home:()=>goHome(),returnToOverview:()=>goHome(false),lockLayout,archiveMax:()=>3,view:{resize},targets(){return Object.fromEntries([...entries].map(([id,n])=>{const p=new THREE.Box3().setFromObject(n).getCenter(new THREE.Vector3()).project(camera);return[id,{x:(p.x+1)/2*w,y:(1-p.y)/2*h}];}));},stats(){return{...state,layout,width:w,height:h,frames,animating:!!animation,raf:!!raf,focusReady,entries:[...entries.keys()],archives:archiveData.length,drawOpen:state.drawer,loadedHashes:{'v3.glb':modelHash},calls:renderer.info.render?.calls,triangles:renderer.info.render?.triangles,geometries:renderer.info.memory.geometries,textures:renderer.info.memory.textures}}};try{resize(w,h);}catch(error){dispose();throw error;}return api;
}
