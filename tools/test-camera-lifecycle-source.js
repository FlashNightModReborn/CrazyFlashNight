'use strict';
// Production AS2 control-flow fixture. Native MovieClip rebinding/timeline/pixels
// are deliberately left to CameraLifecycleHost; these results never claim E2E.
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert/strict');
const root = process.env.CF7_CAMERA_SOURCE_ROOT || path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root,p),'utf8').replace(/^\uFEFF/,'');
let checks=0;
const check=(v,label)=>{assert.ok(v,label);checks++;};
const equal=(a,b,label)=>{assert.equal(a,b,label);checks++;};
function blockEnd(s,p) {
  let depth=1, quote='', i=p+1;
  for(;depth;i++) {
    let c=s[i], two=s.slice(i,i+2);
    if(quote==='//'){if(c==='\n')quote='';}
    else if(quote==='/*'){if(two==='*/'){quote='';i++;}}
    else if(quote){if(c==='\\')i++;else if(c===quote)quote='';}
    else if(two==='//'){quote='//';i++;}
    else if(two==='/*'){quote='/*';i++;}
    else if(c==='"'||c==="'")quote=c;
    else if(c==='{')depth++;else if(c==='}')depth--;
    if(i>=s.length)throw Error('unbalanced source body');
  }
  return i;
}
const types=s=>s.replace(/\b(var\s+[\w\u0080-\uffff]+|[\w\u0080-\uffff]+)\s*:\s*(?:Number|Boolean|String|Object|Array|Function|MovieClip|Void|HorizontalScroller|SceneManager)\b/g,'$1');
const ctx=vm.createContext({Math,trace(){},_global:{ASSetPropFlags(){}},Stage:{width:1024,height:576}});
function packageSet(full,value){let n=ctx;for(const p of full.split('.').slice(0,-1))n=n[p]??={};n[full.split('.').at(-1)]=value;}
function loadClass(file,full) {
  const src=read(file), name=full.split('.').at(-1), fields=[], methods=[];
  for(const m of src.matchAll(/(?:public|private)\s+(static\s+)?var\s+(\w+)\s*:\s*\w+\s*(?:=\s*([^;]+))?;/g))fields.push({static:!!m[1],name:m[2],init:m[3]});
  const re=/(?:(?:public|private)\s+)?(static\s+)?function\s+(\w+)\s*\(([^)]*)\)\s*(?::\s*\w+)?\s*\{/g;
  let m;
  while((m=re.exec(src))){const start=src.indexOf('{',m.index),end=blockEnd(src,start);methods.push({static:!!m[1],name:m[2],args:types(m[3]),body:types(src.slice(start+1,end-1)).replace(/currentFocus\.snapPending === true/g,'currentFocus?.snapPending === true').replace(/a\._parent/g,'a?._parent')});re.lastIndex=end;}
  const statics={};ctx.__statics=statics;ctx.__fields=fields.filter(f=>!f.static).map(f=>f.name);
  const ctor=methods.find(m=>m.name===name);
  ctx.__ctorBody=ctor?ctor.body:'';
  const C=vm.runInContext('(function(S,fields,body){return function '+name+'(){for(var k of fields)this[k]=undefined;with(S){with(this){eval(body);}}};})(__statics,__fields,__ctorBody)',ctx);
  ctx[name]=C;packageSet(full,C);
  for(const f of fields.filter(f=>f.static)){statics[f.name]=undefined;Object.defineProperty(C,f.name,{get:()=>statics[f.name],set:v=>statics[f.name]=v});if(f.init)statics[f.name]=vm.runInContext(f.init,ctx);}
  for(const m of methods.filter(m=>m.name!==name)){
    ctx.__statics=statics;ctx.__body=m.body;ctx.__args=m.args;
    const fn=vm.runInContext('(function(S,body,args){return Function("S","return function("+args+"){with(S){with(this){"+body+"}}}")(S);})(__statics,__body,__args)',ctx);
    if(m.static){statics[m.name]=fn;C[m.name]=fn;}else C.prototype[m.name]=fn;
  }
  return C;
}
// Function() in the VM remains in that VM's global scope; fixture objects model
// display slots only and make no claim about AVM1 aliases or clip-event survival.
function clip(parent,name,depth,init={}) {
  const c={_parent:parent,_name:name,_x:0,_y:0,_xscale:100,_yscale:100,_visible:true,_depth:depth,_slots:new Map(),...init};
  c.getDepth=()=>c._depth;c.getNextHighestDepth=()=>Math.max(0,...c._slots.keys())+1;
  c.getInstanceAtDepth=d=>c._slots.get(d);
  c.createEmptyMovieClip=(name,d)=>clip(c,name,d);
  c.attachMovie=(link,name,d,data)=>clip(c,name,d,data);
  c.swapDepths=other=>{const old=c._depth,d=typeof other==='number'?other:other._depth,occupant=parent._slots.get(d);parent._slots.delete(old);if(occupant){occupant._depth=old;parent._slots.set(old,occupant);}c._depth=d;parent._slots.set(d,c);};
  c.removeMovieClip=()=>{parent._slots.delete(c._depth);if(parent[name]===c)delete parent[name];c._parent=undefined;};
  if(parent){parent[name]=c;parent._slots.set(depth,c);}return c;
}
const worldRoot=clip(null,'root',0);worldRoot._currentframe=146;ctx._root=worldRoot;
packageSet('org.flashNight.arki.scene.StageRunSession',{cameraObservationActive:()=>false,cameraDiag(){}});
const zoom={resetState(){},setCurrentScale(){},updateScale:t=>({newScale:1,offsetX:0,offsetY:0})};
packageSet('org.flashNight.arki.camera.ZoomController',zoom);ctx.ZoomController=zoom;
ctx.ParallaxBackground={refreshOnZoom(){},updateParallax(){}};
packageSet('org.flashNight.arki.camera.ParallaxBackground',ctx.ParallaxBackground);
const HS=loadClass('scripts/类定义/org/flashNight/arki/camera/HorizontalScroller.as','org.flashNight.arki.camera.HorizontalScroller');
const SP=loadClass('scripts/类定义/org/flashNight/arki/scene/SharedScenePlacement.as','org.flashNight.arki.scene.SharedScenePlacement');ctx.SharedScenePlacement=SP;
worldRoot.天空盒=clip(worldRoot,'天空盒',50);worldRoot.天空盒.地平线高度=240;
worldRoot.帧计时器={当前帧数:0,offsetTolerance:0};worldRoot.启用后景=false;worldRoot.basicZoomScale=1;worldRoot.cameraZoomToggle=false;worldRoot.控制目标='hero';
function init(w){w.背景长=2400;w.背景高=800;const h=w.createEmptyMovieClip('hero',1);h._x=1200;h._y=400;HS.onSceneChanged(w,undefined,w.__stageReturnWorldIdentity);return h;}
function step(){worldRoot.帧计时器.当前帧数++;HS.update();}
function info(){return HS.getInstance().getDebugInfo();}
let w=clip(worldRoot,'gameworld',51,{__stageReturnWorldIdentity:{}}),h=init(w),id=w.__stageReturnWorldIdentity,scope=HS.sceneScope(w,id);
check(!HS.hasInitialPose(w,id,scope),'Ready does not manufacture a pose');step();equal(w._x,-788,'first frame uses direction-aware target composition');check(HS.hasInitialPose(w,id,scope),'successful frame commits exact pose');
w.__stageReturnWorldIdentity={};check(!HS.hasInitialPose(w,id,scope),'old pose rejects replaced live identity before Ready');w.__stageReturnWorldIdentity=id;
HS.releaseScene(w,id,scope);HS.onSceneChanged(w,undefined,id);equal(HS.sceneScope(w,id),undefined,'retired camera is not revived by late Ready');scope=HS.bindExplicitScene(w,id,h,{},true);check(scope,'new explicit owner can create another epoch in the live world');HS.followPlayer(false);HS.onPlayerBound(w,id,h);step();
h._x+=4;for(let i=0;i<12;i++)step();check(w._x<-790,'fractional progress survives integer writes');equal(w._x,Math.round(w._x),'presentation stays integer');
let ftarget=clip(w,'focus',2);ftarget._x=1800;ftarget._y=400;
let handle=HS.pushFocus(ftarget,10,true,5,0,37,9,3,{});step();equal(info().focus.offsetTolerance,0,'tol zero retained');equal(info().focus.easeFactor,5,'snap does not overwrite ease');equal(handle.snapPending,false,'snap consumed once');
const before=w._x;ftarget._x+=20;step();check(Math.abs(w._x-before)<10,'subsequent focus frames ease');
HS.onSceneChanged(w,undefined,id);equal(HS.sceneScope(w,id),scope,'duplicate Ready does not reset scope');equal(info().focusDepth,1,'duplicate Ready preserves focus');
check(!HS.releaseFocus({scope}),'unregistered current-scope handle rejected');check(HS.releaseFocus(handle),'exact handle release');step();equal(info().focusDepth,0,'released handle removed');
const finite=HS.pushFocus(ftarget,1,false,5,0,0,0,0,{}),permanent=HS.pushFocus(ftarget,0,false,5,0,0,0,0,{});step();equal(info().focusDepth,1,'expired hidden lower focus compacted');HS.releaseFocus(permanent);step();equal(info().focusDepth,0,'expired lower focus cannot return');
let explicit=clip(w,'virtual',3);explicit._x=1000;explicit._y=400;scope=HS.bindExplicitScene(w,id,explicit,{},true);step();HS.onPlayerBound(w,id,h);step();equal(info().selected,explicit,'player update cannot steal explicit camera');explicit.removeMovieClip();step();equal(info().state,'WAIT_TARGET','invalid explicit camera waits for owner');HS.followPlayer(false);step();equal(info().selected,h,'followPlayer selects latest player');
const oldScope=HS.sceneScope(w,id);check(!HS.releaseScene(w,{},oldScope),'foreign world identity rejected');equal(HS.sceneScope(w,id),oldScope,'rejected release leaves scope unchanged');
HS.releaseScene(w,id,oldScope);check(HS.releaseScene(w,id,oldScope),'duplicate exact release is idempotent');w.removeMovieClip();
const anchor=clip(worldRoot,'gameworld层级定位器',-16381),menu=clip(worldRoot,'修改工具界面',-16373);
for(let cycle=0;cycle<10;cycle++) {
  id={};w=SP.attach(worldRoot,'fixture',{__stageReturnWorldIdentity:id});check(w,'world attach with idle anchor');equal(w.getDepth(),-16381,'stable original low slot');check(w.getDepth()<menu.getDepth(),'world below menu');init(w);step();scope=HS.sceneScope(w,id);
  check(!SP.preflightDetach(w,{}),'foreign teardown identity refused');check(SP.preflightDetach(w,id),'exact teardown pairing accepted');check(SP.returnSlot(w,id),'return original slot before removal');equal(anchor.getDepth(),-16381,'anchor back in original slot');check(HS.releaseScene(w,id,scope),'release matching camera scope');w.removeMovieClip();SP.detached(w,id);check(SP.canReuse(worldRoot,146),'same-frame reuse after successful detach');
}
check(SP.retireIdle(worldRoot),'retire exact idle anchor before navigation');equal(worldRoot.gameworld层级定位器,undefined,'retired anchor physically absent');
const beforeSlots=worldRoot._slots.size;equal(SP.attach(worldRoot,'fixture',{__stageReturnWorldIdentity:{}}),undefined,'missing anchor rejected');equal(worldRoot._slots.size,beforeSlots,'failed attach creates no high visible world');
const flow=read('scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as');check(!flow.includes('gameworld层级定位器.removeMovieClip()'),'ordinary cleanup does not delete paired anchor');check(flow.includes('cleanupBlockedReason === "loot_pending"'),'structural errors are not scheduled as loot retries');
const timer=read('scripts/通信/通信_fs_帧计时器.as').split('_root.cleanupForRestart = function')[1];check(timer.indexOf('preflightCleanup()')<timer.indexOf('StageManager.instance.dispose()'),'restart preflight before first manager destruction');
const reveal=read('scripts/类定义/org/flashNight/arki/ui/SceneTransitionService.as');check(reveal.indexOf('hasInitialPose(s.readyWorld,s.readyIdentity,s.cameraScope)')<reveal.indexOf('s.phase = "reveal"'),'initial pose is required before reveal');
const save=read('scripts/类定义/org/flashNight/neur/Server/SaveManager.as');check(!save.includes('EventBus.instance.publish("SceneReady");'),'anonymous synthetic Ready removed');
const report={kind:'production-source-camera-control-flow-fixture',checks,gameE2e:false,nativeMovieClipSemantics:false,slotsTouched:false};
fs.mkdirSync(path.join(root,'tmp/camera-lifecycle'),{recursive:true});fs.writeFileSync(path.join(root,'tmp/camera-lifecycle/source-results.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
