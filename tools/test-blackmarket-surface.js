#!/usr/bin/env node
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const sourcePath = path.join(__dirname, "../launcher/web/modules/minigames/blackmarket/visual/item-surface.js");
const Surface = require(sourcePath);
let passed = 0;
async function test(name, run) { await run(); passed++; console.log("PASS " + name); }
function image(w, h, predicate) {
    const data = new Uint8ClampedArray(w*h*4);
    for(let y=0;y<h;y++)for(let x=0;x<w;x++)if(predicate(x,y))data.set([180,126,65,255],(y*w+x)*4);
    return {width:w,height:h,data};
}
function components(mask,w,h) {
    const seen=new Uint8Array(mask.length), queue=new Int32Array(mask.length);let count=0;
    for(let i=0;i<mask.length;i++) {
        if(!mask[i]||seen[i])continue;count++;let head=0,tail=1;queue[0]=i;seen[i]=1;
        while(head<tail){const n=queue[head++],x=n%w,y=Math.floor(n/w);for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){
            const xx=x+dx,yy=y+dy;if((!dx&&!dy)||xx<0||xx>=w||yy<0||yy>=h)continue;
            const next=yy*w+xx;if(mask[next]&&!seen[next]){seen[next]=1;queue[tail++]=next;}
        }}
    }return count;
}
function verifyFinal(img, seed) {
    let previous=null;
    for(const coverage of [.97,.84,.54,.18,0]) {
        const result=Surface.renderSurfaceImageData(img,{seed,coverage,diagnostics:true});
        const d=result.diagnostics;assert(d,"final render must expose opt-in diagnostics");
        let object=0,covered=0;
        for(let i=0;i<d.objectMask.length;i++) {
            if(d.objectMask[i]) {object++;covered+=d.mudMask[i];assert.strictEqual(d.mudMask[i],d.budgetMask[i],"decoration changed interior coverage");}
            if(previous&&previous[i])assert(d.revealMask[i],"cleaning level concealed an already revealed pixel");
        }
        assert.strictEqual(covered,Math.round(object*coverage));
        assert.strictEqual(result.metrics.coveredObjectPixels,covered);
        assert(Math.abs(result.metrics.actualCoverage-covered/object)<1e-7);
        assert.strictEqual(result.metrics.unreachableObjectPixels,0);
        assert(result.metrics.coverageInvariant);
        if(coverage>0)assert(components(d.revealMask,img.width,img.height)<=components(d.objectMask,img.width,img.height),"reveal broke into extra speckles");
        previous=d.revealMask;
    }
}
const flush=()=>new Promise(resolve=>setImmediate(resolve));
class FakeBitmap {
    constructor(w=32,h=48){this.width=w;this.height=h;this.closed=0;}
    close(){this.closed++;}
}
class FakeCanvas {
    constructor(w=32,h=48){this.width=w;this.height=h;this.attributes={};this.draws=0;}
    setAttribute(k,v){this.attributes[k]=v;}
    getBoundingClientRect(){return {width:this.width,height:this.height};}
    getContext(){const canvas=this;return {
        clearRect(){},save(){},restore(){},translate(){},rotate(){},
        drawImage(bitmap){assert(!bitmap.closed,"closed bitmap was drawn");canvas.draws++;},
        createImageData(w,h){return {width:w,height:h,data:new Uint8ClampedArray(w*h*4)};},
        putImageData(){},
        getImageData(x,y,w,h){return image(w,h,(xx,yy)=>xx>=w*.25&&xx<w*.75&&yy>=h*.2&&yy<h*.8);}
    };}
    transferToImageBitmap(){return new FakeBitmap(this.width,this.height);}
}
function environment(options={}) {
    const state={workers:[],posts:[],fetches:0,decoded:[]};let release;
    const gate=options.deferred?new Promise(resolve=>{release=resolve;}):Promise.resolve();
    class Worker {
        constructor(){if(options.constructorError)throw new Error("worker unavailable");this.terminated=false;state.workers.push(this);}
        terminate(){this.terminated=true;}
        postMessage(m){assert(!this.terminated,"posted to a terminated Worker");state.posts.push({worker:this,message:m});}
        reply(post,extra={}){const bitmap=new FakeBitmap(post.message.width,post.message.height);this.onmessage({data:{id:post.message.id,bitmap,metrics:{actualCoverage:.84},...extra}});return bitmap;}
    }
    const fetch=url=>{state.fetches++;return gate.then(()=>{if(options.rejectUrl===url)throw new Error("asset unavailable");return {ok:true,blob:()=>Promise.resolve({})};});};
    const createImageBitmap=()=>{const b=new FakeBitmap();state.decoded.push(b);return Promise.resolve(b);};
    const m={exports:{}};
    vm.compileFunction(fs.readFileSync(sourcePath,"utf8"),["module","Worker","fetch","createImageBitmap","OffscreenCanvas"])(m,Worker,fetch,createImageBitmap,FakeCanvas);
    return {state,release,renderer:m.exports.createRenderer({workerUrl:"fixture-worker.js",timeoutMs:options.timeoutMs||2000})};
}
function spec(key,overrides={}) {return {assetUrl:key,sourceKey:key,seed:key,coverage:.84,renderWidth:128,renderHeight:180,...overrides};}
async function main() {
    await test("all source strategies share neutral hidden colors without changing geometry",()=>{
        const Core=require("../launcher/web/modules/minigames/blackmarket/core/index.js");
        const im=image(64,80,(x,y)=>x>8&&x<55&&y>8&&y<70);
        for(let i=0;i<im.data.length;i+=4)if(im.data[i+3])im.data.set(i%8?[255,48,10,255]:[5,220,255,255],i);
        for(const sourceMaskMode of ["source","proxy","monochrome"]){
            const options={seed:"color-policy",coverage:.54,sourceMaskMode,diagnostics:true};
            const old=Surface.renderSurfaceImageData(im,{...options,hiddenColorMode:"source"});
            const next=Surface.renderSurfaceImageData(im,{...options,hiddenColorMode:Core.HIDDEN_COLOR_MODE});
            assert.deepStrictEqual(next.diagnostics,old.diagnostics);
            let checked=0;
            for(let i=0;i<next.diagnostics.revealMask.length;i++)if(next.diagnostics.revealMask[i]){
                const p=i*4;assert(Math.max(...next.imageData.data.slice(p,p+3))-Math.min(...next.imageData.data.slice(p,p+3))<=10);checked++;
            }
            assert(checked>0);
            const clean=Surface.renderSurfaceImageData(im,{...options,mud:false,hiddenColorMode:"source"});
            assert.deepStrictEqual(clean.imageData.data,im.data,"purchase must restore original RGB");
        }
    });
    await test("translucent pixels outside the budget mask are neutralized without alpha changes",()=>{
        const im=image(64,80,(x,y)=>x>8&&x<55&&y>8&&y<70);
        im.data.set([0,255,240,20],0);im.data.set([255,30,5,70],4);
        const opts={seed:"fringe",coverage:0,sourceMaskMode:"source",diagnostics:true};
        const before=Surface.renderSurfaceImageData(im,{...opts,hiddenColorMode:"source"});
        const after=Surface.renderSurfaceImageData(im,{...opts,hiddenColorMode:"monochrome"});
        assert.deepStrictEqual(after.diagnostics,before.diagnostics);
        for(const p of [0,4]){assert.strictEqual(after.imageData.data[p+3],im.data[p+3]);assert(Math.max(...after.imageData.data.slice(p,p+3))-Math.min(...after.imageData.data.slice(p,p+3))<=10);}
    });
    await test("product resolves all source modes as gray while preserving mask strategies",()=>{
        const Core=require("../launcher/web/modules/minigames/blackmarket/core/index.js"),seen=new Set();
        for(let i=0;i<80;i++){
            const session=Core.createTestProductSession({decryptLevel:10},"color-mode-"+i);
            for(const pair of session.product.open().pairs)for(const offer of pair.offers){
                const visual=session.surface.resolveSurface(offer.visualHandle);
                assert.strictEqual(visual.hiddenColorMode,"monochrome");seen.add(visual.sourceMaskMode);
            }
        }
        assert.deepStrictEqual([...seen].sort(),["monochrome","proxy","source"]);
    });
    await test("alpha occupancy does not turn a real body into background",()=>{
        const im=image(64,64,(x,y)=>x>0&&x<63&&y>0&&y<63);
        for(let y=1;y<63;y++)for(let x=1;x<63;x++)if(x<10||y<10||x>53||y>53)im.data[(y*64+x)*4+3]=65;
        const r=Surface.extractObjectMask(im,{hiddenColorMode:"proxy"});
        assert.strictEqual(r.source,"alpha-core-with-fringe");assert.strictEqual(r.mask[32*64+32],1);assert.strictEqual(r.mask[3*64+3],0);
        assert(r.quality.shadowPixelsRemoved>0);assert(r.confidence<.8,"inventory crops must not claim complete silhouette confidence");
    });
    await test("transparent source keeps remote one-pixel parts and existing holes",()=>{
        const im=image(80,80,(x,y)=>(x>20&&x<60&&y>20&&y<60&&!(x>30&&x<45&&y>30&&y<45))||(x===2&&y===3));
        const r=Surface.extractObjectMask(im);assert.strictEqual(r.mask[3*80+2],1);assert.strictEqual(r.mask[36*80+36],0);
        for(let i=0;i<r.mask.length;i++)assert.strictEqual(r.mask[i],im.data[i*4+3]?1:0);
    });
    await test("thin foreground retains exact final mud through all levels",()=>verifyFinal(image(180,260,(x,y)=>x>=87&&x<90&&y>=12&&y<248),"thin"));
    await test("separated real parts reveal continuously without unreachable pixels",()=>verifyFinal(image(180,260,(x,y)=>((x>=40&&x<82)||(x>=98&&x<140))&&y>=50&&y<210),"parts"));
    await test("one-pixel neck and concave hole preserve topology",()=>verifyFinal(image(180,260,(x,y)=>
        (x>=20&&x<70&&y>=50&&y<100)||(x>=110&&x<160&&y>=150&&y<210)||(y===99&&x>=69&&x<=130)||(x===130&&y>=99&&y<=150)),"neck"));
    await test("full-resolution one-pixel diagonal remains reachable",()=>{
        const w=160,h=160,mask=new Uint8Array(w*h);for(let n=5;n<155;n++)mask[n*w+n]=1;
        for(const c of [.97,.84,.54,.18]){const r=Surface.buildCoverageMasks(mask,w,h,{x:5,y:5},c,"diagonal");assert.strictEqual(r.reachablePixels,150);assert.strictEqual(r.componentCount,1);assert.strictEqual(components(r.reveal,w,h),1);}
    });
    await test("many seeds preserve finite ranks and nested reveal sets",()=>{
        const im=image(88,96,(x,y)=>((x>=12&&x<35)||(x>=41&&x<64))&&y>=12&&y<80);
        for(let n=0;n<8;n++)verifyFinal(im,"parts-"+n);
    });
    await test("same seed produces identical final RGBA and zero/full budgets",()=>{
        const im=image(88,96,(x,y)=>(x-43)**2+(y-47)**2<30**2);
        const a=Surface.renderSurfaceImageData(im,{seed:"stable",coverage:.54});
        const b=Surface.renderSurfaceImageData(im,{seed:"stable",coverage:.54});assert.deepStrictEqual(a.imageData.data,b.imageData.data);
        assert.strictEqual(a.diagnostics,undefined);
        const mask=Surface.extractObjectMask(im).mask;
        for(const c of [0,1]){const r=Surface.buildCoverageMasks(mask,88,96,{x:43,y:47},c,"stable");assert.strictEqual(r.coveredPixels,Math.round(r.objectPixels*c));}
        assert.throws(()=>Surface.buildCoverageMasks(mask,88,96,{x:43,y:47},NaN,"bad"),/finite/);
    });
    await test("12 callers share six Worker jobs and keep per-view metadata",async()=>{
        const e=environment(),promises=[];
        for(let round=0;round<2;round++)for(let n=0;n<6;n++)promises.push(e.renderer.render(new FakeCanvas(),spec("k"+n,{offerId:round+"-"+n,preserveSourceAlpha:true})));
        await flush();assert.strictEqual(e.state.fetches,6);assert.strictEqual(e.state.posts.length,6);
        for(const post of e.state.posts){assert.strictEqual(post.message.options.preserveSourceAlpha,true);post.worker.reply(post);}
        const rs=await Promise.all(promises);assert.strictEqual(new Set(rs.map(r=>r.offerId)).size,12);
        const cached=await e.renderer.render(new FakeCanvas(),spec("k0",{offerId:"cached",preserveSourceAlpha:true}));assert.strictEqual(cached.offerId,"cached");assert.strictEqual(e.state.posts.length,6);e.renderer.destroy();
    });
    await test("Worker startup failure before decode routes to current fallback",async()=>{
        const e=environment({deferred:true}),c=new FakeCanvas();const p=e.renderer.render(c,spec("startup"));
        e.state.workers[0].onerror();e.release();const r=await p;
        assert.strictEqual(r.backend,"main-thread-fallback");assert.strictEqual(e.state.posts.length,0);assert.strictEqual(c.attributes["data-surface-state"],"ready");e.renderer.destroy();
    });
    await test("crashed transferred jobs recover once and discard late results",async()=>{
        const e=environment(),c=new FakeCanvas(),p=e.renderer.render(c,spec("crash"));await flush();const post=e.state.posts[0];post.worker.onerror();
        const r=await p;assert.strictEqual(r.backend,"main-thread-fallback");assert.strictEqual(c.draws,1);const late=post.worker.reply(post);assert.strictEqual(late.closed,1);assert.strictEqual(c.draws,1);e.renderer.destroy();
    });
    await test("constructor failure and Worker error messages reach fallback",async()=>{
        const a=environment({constructorError:true});assert.strictEqual((await a.renderer.render(new FakeCanvas(),spec("ctor"))).backend,"main-thread-fallback");a.renderer.destroy();
        const b=environment(),p=b.renderer.render(new FakeCanvas(),spec("job-error"));await flush();const post=b.state.posts[0];post.worker.reply(post,{error:"decode rejected"});assert.strictEqual((await p).backend,"main-thread-fallback");b.renderer.destroy();
    });
    await test("empty primary retries only its declared same-item fallback",async()=>{
        const e=environment(),p=e.renderer.render(new FakeCanvas(),spec("empty",{fallbackAssetUrl:"same-item-f1",fallbackHiddenColorMode:"monochrome"}));
        await flush();e.state.posts[0].worker.reply(e.state.posts[0],{error:"empty",code:"empty-source"});await flush();
        assert.strictEqual(e.state.fetches,2);assert.strictEqual(e.state.posts.length,2);
        const retry=e.state.posts[1];assert.strictEqual(retry.message.options.hiddenColorMode,"monochrome");retry.worker.reply(retry);
        const r=await p;assert.strictEqual(r.sourceFallback,"empty-primary-to-same-item-inventory-frame");e.renderer.destroy();
    });
    await test("revealed fallback retains source color and the inventory mask policy",async()=>{
        const e=environment(),p=e.renderer.render(new FakeCanvas(),spec("empty-clean",{mud:false,hiddenColorMode:"source",fallbackAssetUrl:"same-item-f1"}));
        await flush();e.state.posts[0].worker.reply(e.state.posts[0],{error:"empty",code:"empty-source"});await flush();
        const retry=e.state.posts[1];assert.strictEqual(retry.message.options.hiddenColorMode,"source");assert.strictEqual(retry.message.options.sourceMaskMode,"monochrome");retry.worker.reply(retry);await p;e.renderer.destroy();
    });
    await test("unrevealed uncoated fallback preserves its requested gray policy",async()=>{
        const e=environment(),p=e.renderer.render(new FakeCanvas(),spec("empty-withdrawn",{mud:false,hiddenColorMode:"monochrome",fallbackAssetUrl:"same-item-f1"}));
        await flush();e.state.posts[0].worker.reply(e.state.posts[0],{error:"empty",code:"empty-source"});await flush();
        const retry=e.state.posts[1];assert.strictEqual(retry.message.options.hiddenColorMode,"monochrome");assert.strictEqual(retry.message.options.mud,false);retry.worker.reply(retry);await p;e.renderer.destroy();
    });
    await test("ambiguous primary is replaced only after a transparent alternate succeeds",async()=>{
        const e=environment(),c=new FakeCanvas(),p=e.renderer.render(c,spec("opaque",{fallbackAssetUrl:"same-item-f2",fallbackSourceMaskMode:"source"}));
        await flush();const original=e.state.posts[0].worker.reply(e.state.posts[0],{metrics:{sourceMask:"ambiguous-opaque",sourceQuality:{status:"ambiguous"}}});
        await flush();assert.strictEqual(c.draws,0);assert.strictEqual(original.closed,0);const retry=e.state.posts[1];assert.strictEqual(retry.message.options.sourceMaskMode,"source");
        retry.worker.reply(retry,{metrics:{sourceMask:"alpha",sourceQuality:{status:"usable-alpha"}}});const m=await p;
        assert.strictEqual(original.closed,1);assert.strictEqual(c.draws,1);assert.strictEqual(m.sourceFallback,"ambiguous-primary-to-same-item-transparent-frame");e.renderer.destroy();
    });
    await test("opaque or unavailable alternate retains the original instead of erasing it",async()=>{
        for(const unavailable of [false,true]){
            const e=environment({rejectUrl:unavailable?"bad-alternate":null}),c=new FakeCanvas(),p=e.renderer.render(c,spec("opaque",{fallbackAssetUrl:"bad-alternate",fallbackSourceMaskMode:"source"}));
            await flush();const original=e.state.posts[0].worker.reply(e.state.posts[0],{metrics:{sourceMask:"ambiguous-opaque",sourceQuality:{status:"ambiguous"}}});await flush();
            if(!unavailable){const retry=e.state.posts[1];retry.worker.reply(retry,{metrics:{sourceMask:"ambiguous-opaque",sourceQuality:{status:"ambiguous"}}});}
            const m=await p;assert.strictEqual(c.draws,1);assert.strictEqual(m.sourceMask,"ambiguous-opaque");assert.strictEqual(m.sourceFallback,"ambiguous-alternate-unusable-primary-retained");assert.strictEqual(original.closed,0);e.renderer.destroy();assert.strictEqual(original.closed,1);
        }
    });
    await test("destroy releases a held ambiguous result and aborts the caller",async()=>{
        const e=environment(),p=e.renderer.render(new FakeCanvas(),spec("opaque",{fallbackAssetUrl:"same-item-f2"})).catch(error=>error);
        await flush();const original=e.state.posts[0].worker.reply(e.state.posts[0],{metrics:{sourceMask:"ambiguous-opaque",sourceQuality:{status:"ambiguous"}}});e.renderer.destroy();
        assert.strictEqual((await p).name,"AbortError");assert.strictEqual(original.closed,1);await flush();
    });
    await test("stalled Worker has a bounded fallback rather than an eternal promise",async()=>{
        const e=environment({timeoutMs:100}),r=await e.renderer.render(new FakeCanvas(),spec("timeout"));assert.strictEqual(r.backend,"main-thread-fallback");assert(e.state.workers[0].terminated);e.renderer.destroy();
    });
    await test("destroy settles decoding callers and closes late decoded bitmaps",async()=>{
        const e=environment({deferred:true}),p=e.renderer.render(new FakeCanvas(),spec("destroy")).then(()=>{throw new Error("unexpected success");},error=>error);
        e.renderer.destroy();assert.strictEqual((await p).name,"AbortError");e.release();await flush();assert(e.state.decoded.every(b=>b.closed===1));assert.strictEqual(e.state.posts.length,0);
    });
    await test("superseded canvas cannot be painted by an old result",async()=>{
        const e=environment(),c=new FakeCanvas(),old=e.renderer.render(c,spec("old")).catch(error=>error);await flush();const first=e.state.posts[0];
        const next=e.renderer.render(c,spec("new"));assert.strictEqual((await old).name,"AbortError");await flush();const late=first.worker.reply(first);assert.strictEqual(late.closed,1);assert.strictEqual(c.draws,0);
        const second=e.state.posts[1];second.worker.reply(second);await next;assert.strictEqual(c.draws,1);e.renderer.destroy();
    });
    await test("completion callback failures do not strand successful callers",async()=>{
        const e=environment(),p=e.renderer.render(new FakeCanvas(),spec("callback",{onComplete(){throw new Error("UI callback failed");}}));await flush();e.state.posts[0].worker.reply(e.state.posts[0]);assert.strictEqual((await p).backend,"offscreen-worker");e.renderer.destroy();
    });
    console.log("[blackmarket-surface] "+passed+"/"+passed+" passed");
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
