import {webcrypto,createHash} from 'node:crypto';
import {target,targetUrl,resultFile} from './target.mjs';
import fs from 'node:fs';
const RealThree=await import(targetUrl('web/assets/stage-diorama/base-gate/vendor/three.module.js'));
const core=await import(targetUrl('web/modules/interaction-core.mjs'));
const layouts=await import(targetUrl('web/modules/layout-core.mjs'));
import {loadGeometryGlb} from './load-glb.mjs';
export {RealThree};
export async function harness({reduced=false,applyLayout,loadDelay=false,rendererFailure=false}={}){
 const listeners=new Set(),rafs=new Map(),timers=new Map();let serial=0,now=0,lastScene,lastCamera,resolveLoad;
 class Element{constructor(){this.style={};this.dataset={};this.children=[];this.queries=new Map();this.handlers=new Map();this.captured=new Set();this.width=802;this.height=481;}setAttribute(k,v){this[k]=v;}querySelector(s){if(!this.queries.has(s))this.queries.set(s,new Element());return this.queries.get(s);}replaceChildren(...c){this.children=c;}append(...c){this.children.push(...c);}addEventListener(t,f){this.handlers.set(t,f);listeners.add(f);}removeEventListener(t,f){if(this.handlers.get(t)===f)this.handlers.delete(t);listeners.delete(f);}dispatch(t,e={}){this.handlers.get(t)?.({preventDefault(){},button:0,pointerId:1,pointerType:'mouse',clientX:0,clientY:0,...e});}focus(){}setPointerCapture(i){this.captured.add(i);}hasPointerCapture(i){return this.captured.has(i);}releasePointerCapture(i){this.captured.delete(i);this.dispatch('lostpointercapture',{pointerId:i});}getBoundingClientRect(){return {left:0,top:0,width:this.width,height:this.height};}remove(){this.removed=true;}}
 class Renderer{constructor(){if(rendererFailure)throw Error('mock WebGL unavailable');this.domElement=new Element();this.info={memory:{geometries:0,textures:0}};this.renderLists={dispose(){}};}setPixelRatio(){}setSize(w,h){this.domElement.width=w;this.domElement.height=h;}render(s,c){lastScene=s;lastCamera=c;}dispose(){this.disposed=true;}forceContextLoss(){this.lost=true;}}
 const loaded=loadGeometryGlb(target('web/assets/bookshelf/shelf/v3.glb'),RealThree);
 let loadFinished=false;
 class GLTFLoader{async parseAsync(){if(loadDelay&&!loadFinished)await new Promise(r=>resolveLoad=r);return {scene:loaded.root};}}
 const media=new Element();media.matches=reduced;
 const model=fs.readFileSync(target('web/assets/bookshelf/shelf/v3.glb'));
 const window={},document={createElement(){return new Element();}},fetch=async()=>({ok:true,json:async()=>({schema:'bookshelf-interactive.v4',model:'v3.glb',sha256:createHash('sha256').update(model).digest('hex'),audit:{bytes:model.length}}),arrayBuffer:async()=>model.buffer.slice(model.byteOffset,model.byteOffset+model.length)});
 let source=fs.readFileSync(target('web/modules/preview-shelf-scene.js'),'utf8').replace(/^import .*;\n/gm,'').replace("new URL('../assets/bookshelf/shelf/',import.meta.url)","new URL('https://qa.invalid/assets/')").replace('export async function createScene','async function createScene');
 const names=['THREE','GLTFLoader','validateEmbeddedGlb','chooseLayout','applyLayout',...Object.keys(core),'window','document','fetch','matchMedia','requestAnimationFrame','cancelAnimationFrame','setTimeout','clearTimeout','performance','crypto'];
 const values=[{...RealThree,WebGLRenderer:Renderer},GLTFLoader,()=>{},layouts.chooseLayout,applyLayout,...Object.values(core),window,document,fetch,()=>media,f=>{rafs.set(++serial,f);return serial;},id=>rafs.delete(id),(f,delay)=>{timers.set(++serial,{f,when:now+delay});return serial;},id=>timers.delete(id),{now:()=>now},webcrypto];
 const createScene=new Function(...names,source+'\nreturn createScene;')(...values);
 return {createScene,loaded,window,media,listeners,rafs,timers,get scene(){return lastScene},get camera(){return lastCamera},get now(){return now},finishLoad(){loadFinished=true;resolveLoad?.();},tick(ms=1000){now+=ms;const callbacks=[...rafs.values()];rafs.clear();callbacks.forEach(f=>f(now));for(const[id,t]of timers)if(t.when<=now){timers.delete(id);t.f();}},flush(){for(let i=0;i<30&&(rafs.size||timers.size);i++)this.tick(1000);}};
}
