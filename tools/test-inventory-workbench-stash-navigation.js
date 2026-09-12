'use strict';
const assert=require('assert');
const Navigation=require('../launcher/web/modules/inventory-workbench-stash-navigation.js');
global.InventoryWorkbenchFeatureLoader={loadFeature:()=>Promise.resolve()};
let passed=0;
function fixture(headless=true,view='storage'){
 const events=[],c={view,epoch:1,storageReady:true,panelInstanceId:'p',runtimeConfig:{},closing:false};let source='container',blocked=false;
 const base={ready:true,busyOwner:null,refreshRequired:false};
 const authority={acquire:cb=>{events.push('acquire');cb({itemUse:{}});},release:()=>events.push('release'),canClose:()=>!blocked,
  debugState:()=>({session:headless?{state:'idle'}:null}),finalize:cb=>{events.push('finalize');cb(true);return true;},destroy:()=>events.push('destroy')};
 const storage={getSource:()=>source,getHeaderState:()=>({disabled:blocked}),debugState:()=>({coordinator:base}),switchSource:(next,_,cb)=>{if(blocked)return false;events.push(next);source=next;cb(true);return true;}};
 let nav;nav=Navigation.create({context:()=>c,storage,authorityModule:{create:()=>authority},active:()=>true,toast:message=>events.push(message),setClosing:value=>{c.closing=value;},finishClose:()=>{events.push('close');return true;},
  requestView:next=>{c.view=next;nav.onView(next);return true;}});
 return{nav,events,c,base,source:()=>source,block:value=>{blocked=value;}};
}
async function enter(f){assert(f.nav.request('stash'));await Promise.resolve();await Promise.resolve();}
async function test(name,run){await run();console.log('ok '+(++passed)+' - '+name);}
(async()=>{
 await test('direct storage Esc returns its source before closing',async()=>{const f=fixture();await enter(f);assert.strictEqual(f.source(),'stash');assert(f.nav.consumeEscape());assert.strictEqual(f.source(),'container');assert(!f.events.includes('close'));f.nav.destroy();});
 await test('Build-origin stash leaves Esc to the original view stack',async()=>{const f=fixture(false,'build');await enter(f);assert.strictEqual(f.c.view,'storage');assert.strictEqual(f.source(),'stash');assert.strictEqual(f.nav.consumeEscape(),false);f.nav.destroy();});
 await test('headless source is finalized before Build opens its own session',async()=>{const f=fixture();await enter(f);f.nav.prepareView('build',()=>f.events.push('build.open'));assert(f.events.indexOf('container')<f.events.indexOf('finalize'));assert(f.events.indexOf('finalize')<f.events.indexOf('build.open'));f.nav.destroy();});
 await test('borrowed Build source returns without finalizing the live Build generation',async()=>{const f=fixture(false,'build');await enter(f);f.nav.prepareView('build',()=>f.events.push('build.resume'));assert(f.events.includes('release'));assert(f.events.includes('build.resume'));assert(!f.events.includes('finalize'));f.nav.destroy();});
 await test('unknown source prevents both view transition and close',async()=>{const f=fixture();await enter(f);f.block(true);assert.strictEqual(f.nav.prepareView('build',()=>f.events.push('build.open')),false);assert.strictEqual(f.nav.finalizeClose('close'),false);assert(!f.events.includes('close'));assert(!f.events.includes('build.open'));f.nav.destroy();});
 await test('first Build-to-stash waits for bag readiness before mounting the source',async()=>{const f=fixture(false,'build');f.base.ready=false;await enter(f);assert.strictEqual(f.source(),'container');f.base.ready=true;await new Promise(resolve=>setTimeout(resolve,280));assert.strictEqual(f.source(),'stash');f.nav.destroy();});
 await test('first entry retains stash intent during the actual bootstrap read owner',async()=>{const f=fixture(false,'build');f.base.ready=false;f.base.busyOwner='bootstrap';await enter(f);assert(f.nav.switching());assert(!f.events.includes('release'));f.base.ready=true;f.base.busyOwner=null;await new Promise(resolve=>setTimeout(resolve,280));assert.strictEqual(f.source(),'stash');f.nav.destroy();});
 await test('destroy invalidates a pending first-entry callback',async()=>{const f=fixture(false,'build');f.base.ready=false;await enter(f);f.nav.destroy();f.base.ready=true;await new Promise(resolve=>setTimeout(resolve,280));assert.strictEqual(f.source(),'container');});
 console.log('Stash navigation: '+passed+'/'+passed+' passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
