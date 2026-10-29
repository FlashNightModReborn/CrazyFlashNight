#!/usr/bin/env node
"use strict";
// Actual Chromium Worker/OffscreenCanvas and production-feature DOM checks.
// Supply playwright through NODE_PATH; no launcher or native game process is used.
const fs=require("fs"),path=require("path"),http=require("http"),crypto=require("crypto");
const {chromium}=require("playwright");
const root=path.resolve(__dirname,"../launcher/web");
const arg=n=>{const i=process.argv.indexOf(n);return i<0?null:process.argv[i+1];};
const out=arg("--out");if(!out||!path.isAbsolute(out))throw Error("--out ABS_DIR required");fs.mkdirSync(out,{recursive:true});
const mime={".html":"text/html; charset=utf-8",".js":"text/javascript; charset=utf-8",".css":"text/css",".png":"image/png",".webp":"image/webp",".svg":"image/svg+xml",".json":"application/json"};
const server=http.createServer((req,res)=>{
    const u=new URL(req.url,"http://localhost");
    if(u.pathname==="/surface-test.html"){res.setHeader("Content-Type",mime[".html"]);res.end('<!doctype html><meta charset="utf-8"><script src="/modules/minigames/blackmarket/core/index.js"></script><script src="/modules/minigames/blackmarket/visual/item-surface.js"></script><script src="/modules/minigames/blackmarket/visual/visual-pool-manifest.js"></script>');return;}
    const p=path.resolve(root,"."+decodeURIComponent(u.pathname));if(!p.startsWith(root+path.sep)){res.writeHead(403).end();return;}
    fs.stat(p,(err,st)=>{if(err||!st.isFile()){res.writeHead(404).end();return;}res.setHeader("Content-Type",mime[path.extname(p)]||"application/octet-stream");fs.createReadStream(p).pipe(res);});
});
(async()=>{
    await new Promise(r=>server.listen(0,"127.0.0.1",r));const base="http://127.0.0.1:"+server.address().port;
    const browser=await chromium.launch({headless:true,executablePath:arg("--chrome")||"C:/Program Files/Google/Chrome/Application/chrome.exe"});
    const result={browser:browser.version(),sourceSha256:crypto.createHash("sha256").update(fs.readFileSync(path.join(root,"modules/minigames/blackmarket/visual/item-surface.js"))).digest("hex"),evidence:"Real Chromium Canvas/Worker + product Web harness; not physical WebView2 or game/save E2E",coreSha256:crypto.createHash("sha256").update(fs.readFileSync(path.join(root,"modules/minigames/blackmarket/core/index.js"))).digest("hex"),panelSha256:crypto.createHash("sha256").update(fs.readFileSync(path.join(root,"modules/minigames/blackmarket/blackmarket-panel.js"))).digest("hex"),cases:[],harness:[]};
    try {
        if(!process.argv.includes("--only-color")){
        const page=await browser.newPage({viewport:{width:1280,height:900}});await page.goto(base+"/surface-test.html");
        result.cases=await page.evaluate(async()=>{
            const S=BlackMarketItemSurface, entries=BlackMarketVisualPool.entries;
            const workerUrl="/modules/minigames/blackmarket/visual/item-surface-worker.js", cases=[];
            const check=(v,m)=>{if(!v)throw Error(m);};
            const canvas=()=>{const c=document.createElement("canvas");c.getContext("2d",{willReadFrequently:true});return c;};
            function present(c){const output=canvas();output.width=c.width;output.height=c.height;const bitmap=c.transferToImageBitmap?c.transferToImageBitmap():c;output.getContext("2d").drawImage(bitmap,0,0);if(bitmap.close)bitmap.close();return output;}
            const digest=async c=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",c.getContext("2d").getImageData(0,0,c.width,c.height).data))).map(n=>n.toString(16).padStart(2,"0")).join("");
            const entry=entries.find(e=>e.n==="M4A1战术版");
            const spec=(e=entry,extra={})=>({assetUrl:"/"+e.u,fallbackAssetUrl:e.f?"/"+e.f:null,fallbackSourceMaskMode:e.fm||"monochrome",sourceKey:e.u,seed:"audit-s1",coverage:.84,renderWidth:512,renderHeight:768,autoRotate:true,paddingRatio:.065,sharpenSource:true,sharpenStrength:.18,hiddenColorMode:BlackMarketCore.HIDDEN_COLOR_MODE,sourceMaskMode:e.h,...extra});
            async function test(name,fn){const t=performance.now();try{const details=await fn();cases.push({name,pass:true,elapsedMs:performance.now()-t,details});}catch(e){cases.push({name,pass:false,error:e.stack||String(e)});}}
            const nativeFetch=window.fetch.bind(window);
            await test("real Worker matches direct Canvas for 9 sources at all 4 levels",async()=>{
                const r=S.createRenderer({workerUrl}),rows=[];
                try{for(const name of ["M4A1战术版","浅灰背心","M82A1","QBZ-191","地瓜手雷","炎魔斩","炎魔斩alter","烈炎矿石","四阶复合防御组件"]){
                    const e=entries.find(e=>e.n===name),blob=await(await nativeFetch("/"+e.u)).blob(),img=await createImageBitmap(blob);
                    const primaryMask=S.extractObjectMask((()=>{const c=canvas();c.width=img.width;c.height=img.height;c.getContext("2d").drawImage(img,0,0);return c.getContext("2d").getImageData(0,0,c.width,c.height);})(),{hiddenColorMode:e.h});
                    let directImage=img,mode=BlackMarketCore.HIDDEN_COLOR_MODE,maskMode=e.h;if(!primaryMask.bounds.count||primaryMask.quality.status==="ambiguous"){directImage=await createImageBitmap(await(await nativeFetch("/"+e.f)).blob());mode="monochrome";maskMode=e.fm||"monochrome";}
                    for(const coverage of [.97,.84,.54,.18]){const c=canvas(),m=await r.render(c,spec(e,{coverage})),direct=S.processBitmap(directImage,512,768,{...spec(e,{coverage}),hiddenColorMode:mode,sourceMaskMode:maskMode});
                        check(m.backend==="offscreen-worker","worker backend missing");check(await digest(c)===await digest(present(direct.canvas)),"Worker/main RGBA mismatch "+name+" "+coverage);check(m.coverageInvariant&&m.unreachableObjectPixels===0,"invalid coverage");rows.push({name,coverage,actual:m.actualCoverage,rgbaSha256:await digest(c),fallback:m.sourceFallback});}
                    img.close();if(directImage!==img)directImage.close();
                }}finally{r.destroy();}return rows;
            });
            await test("real Worker coalesces 12 views into 6 jobs",async()=>{
                const Native=window.Worker;let posts=0;window.Worker=class extends Native{postMessage(...args){posts++;return super.postMessage(...args);}};
                const r=S.createRenderer({workerUrl});try{const ps=[];for(let v=0;v<2;v++)for(let i=0;i<6;i++)ps.push(r.render(canvas(),spec(entry,{seed:"coalesced-"+i,offerId:v+"-"+i})));const ms=await Promise.all(ps);check(posts===6,"duplicate Worker jobs "+posts);check(new Set(ms.map(m=>m.offerId)).size===12,"view metadata mixed");return {posts,views:ms.length};}finally{r.destroy();window.Worker=Native;}
            });
            async function brokenWorker(code,delayFetch,timeoutMs){
                const url=URL.createObjectURL(new Blob([code],{type:"text/javascript"}));
                if(delayFetch)window.fetch=(...args)=>new Promise(r=>setTimeout(r,180)).then(()=>nativeFetch(...args));
                const r=S.createRenderer({workerUrl:url,timeoutMs:timeoutMs||15000});try{const m=await r.render(canvas(),spec());check(m.backend==="main-thread-fallback","did not recover");return {backend:m.backend,coverage:m.actualCoverage};}finally{r.destroy();window.fetch=nativeFetch;URL.revokeObjectURL(url);}
            }
            await test("startup exception before decode recovers",()=>brokenWorker('throw new Error("intentional startup fixture")',true));
            await test("crash after bitmap transfer recovers",()=>brokenWorker('self.onmessage=e=>{e.data.bitmap.close();throw new Error("intentional transferred crash");}',false));
            await test("silent Worker times out into fallback",()=>brokenWorker('self.onmessage=e=>{e.data.bitmap.close();};',false,700));
            await test("destroy settles a caller during delayed fetch",async()=>{
                let release;const gate=new Promise(r=>release=r);window.fetch=(...args)=>gate.then(()=>nativeFetch(...args));const r=S.createRenderer({workerUrl});
                try{const p=r.render(canvas(),spec()).catch(e=>e);r.destroy();const e=await p;check(e.name==="AbortError","caller stranded or wrong error");release();return e.name;}finally{release();window.fetch=nativeFetch;}
            });
            await test("failed fetch can retry with the same renderer",async()=>{
                let first=true;window.fetch=(...args)=>{if(first){first=false;return Promise.resolve(new Response("fixture",{status:503}));}return nativeFetch(...args);};const r=S.createRenderer({workerUrl});
                try{const e=await r.render(canvas(),spec()).catch(e=>e);check(e instanceof Error,"first fetch should reject");const m=await r.render(canvas(),spec());check(m.backend==="offscreen-worker","retry failed");return m.backend;}finally{r.destroy();window.fetch=nativeFetch;}
            });
            await test("superseded canvas cannot be repainted by the old job",async()=>{
                const r=S.createRenderer({workerUrl}),c=canvas(),ctx=c.getContext("2d"),draw=ctx.drawImage.bind(ctx);let paints=0;ctx.drawImage=(...args)=>{paints++;return draw(...args);};try{const old=r.render(c,spec(entry,{seed:"old"})).catch(e=>e);const next=r.render(c,spec(entry,{seed:"new"}));check((await old).name==="AbortError","old caller not cancelled");await next;const before=await digest(c);await new Promise(r=>setTimeout(r,120));check(paints===1&&before===await digest(c),"stale repaint; paints="+paints);return {hash:before,paints};}finally{r.destroy();}
            });
            await test("empty input recovery also keeps revealed source colors",async()=>{
                const e=entries.find(e=>e.n==="地瓜手雷"),r=S.createRenderer({workerUrl}),c=canvas();try{const m=await r.render(c,spec(e,{mud:false,hiddenColorMode:"source",preserveSourceAlpha:true,sharpenSource:false}));check(!!m.sourceFallback,"fallback not used");const img=await createImageBitmap(await(await nativeFetch("/"+e.f)).blob());const expected=S.processBitmap(img,512,768,{...spec(e),mud:false,hiddenColorMode:"source",sourceMaskMode:"monochrome",preserveSourceAlpha:true,sharpenSource:false});check(await digest(c)===await digest(present(expected.canvas)),"revealed fallback recolored");img.close();return {coverage:m.actualCoverage,fallback:m.sourceFallback};}finally{r.destroy();}
            });
            await test("unrevealed uncoated fallback stays gray",async()=>{
                const e=entries.find(e=>e.n==="地瓜手雷"),r=S.createRenderer({workerUrl}),c=canvas();try{const m=await r.render(c,spec(e,{mud:false,hiddenColorMode:"monochrome"}));check(!!m.sourceFallback,"fallback not used");const img=await createImageBitmap(await(await nativeFetch("/"+e.f)).blob());const expected=S.processBitmap(img,512,768,{...spec(e),mud:false,hiddenColorMode:"monochrome",sourceMaskMode:"monochrome"});check(await digest(c)===await digest(present(expected.canvas)),"unbought fallback restored source colors");img.close();return {fallback:m.sourceFallback,hiddenColorMode:"monochrome"};}finally{r.destroy();}
            });
            await test("unavailable alternate preserves the real opaque original",async()=>{
                const e=entries.find(e=>e.n==="炎魔斩"),r=S.createRenderer({workerUrl}),c=canvas();try{const m=await r.render(c,spec(e,{fallbackAssetUrl:"/icons/missing-surface-fixture.webp"}));check(m.sourceFallback==="ambiguous-alternate-unusable-primary-retained","original not retained");const img=await createImageBitmap(await(await nativeFetch("/"+e.u)).blob());const expected=S.processBitmap(img,512,768,spec(e));check(await digest(c)===await digest(present(expected.canvas)),"retained pixels differ");img.close();return m.sourceFallback;}finally{r.destroy();}
            });
            await test("Worker unavailable uses the same pixels on main thread",async()=>{
                const a=S.createRenderer({workerUrl}),b=S.createRenderer({}),ca=canvas(),cb=canvas();try{const [ma,mb]=await Promise.all([a.render(ca,spec()),b.render(cb,spec())]);check(mb.backend==="main-thread-fallback","fallback backend missing");check(await digest(ca)===await digest(cb),"fallback RGBA mismatch");return [ma.backend,mb.backend];}finally{a.destroy();b.destroy();}
            });
            return cases;
        });
        console.log(JSON.stringify({surfaceCases:result.cases.length,failed:result.cases.filter(c=>!c.pass)}));
        for(const viewport of [{width:1024,height:576},{width:1440,height:900}]) {
            const ui=await browser.newPage({viewport});const errors=[];ui.on("pageerror",e=>errors.push(e.message));
            await ui.goto(base+"/modules/minigames/blackmarket/dev/harness.html?qa=1&dump=1");
            await ui.waitForFunction(()=>window.__qaResult&&window.__qaResult.qa,{},{timeout:120000});
            const qa=await ui.evaluate(()=>window.__qaResult);result.harness.push({viewport,qa,errors});
            await ui.screenshot({path:path.join(out,"product-harness-"+viewport.width+".png"),fullPage:true});
            console.log(JSON.stringify({viewport,passed:qa.qa.passed,total:qa.qa.total,failed:qa.qa.results.filter(x=>!x.pass)}));await ui.close();
        }
        }
        // Controlled image selection in the browser harness only. Product core, panel,
        // Worker, inspection canvas and transaction state transitions remain real.
        result.colorUi=[];
        result.colorFixture={scope:"browser-only controlled source selection; production rendering and transaction flow",images:["烈炎矿石","四阶复合防御组件","汞合金","浮士德装备碎片","鼠年碎片","骨芯颅印"],debugLogHiddenForScreenshots:true};
        const color=await browser.newPage({viewport:{width:1440,height:900}}),colorErrors=[];
        color.on("pageerror",e=>colorErrors.push(e.message));
        await color.route("**/visual-pool-manifest.js",async route=>{
            const response=await route.fetch(),source=await response.text();
            const names=["烈炎矿石","四阶复合防御组件","汞合金","浮士德装备碎片","鼠年碎片","骨芯颅印"];
            await route.fulfill({response,body:source+"\nBlackMarketVisualPool.entries=BlackMarketVisualPool.entries.filter(e=>"+JSON.stringify(names)+".includes(e.n)).map(e=>({...e,g:'颜色验收材料'}));"});
        });
        await color.route("**/item-surface.js",async route=>{
            const response=await route.fetch(),source=await response.text();
            const observe=`if(typeof document!=='undefined'){window.__colorRequests=[];const create=BlackMarketItemSurface.createRenderer;BlackMarketItemSurface.createRenderer=function(options){const renderer=create(options),render=renderer.render;renderer.render=function(canvas,spec){return render.call(renderer,canvas,spec).then(metrics=>{window.__colorRequests.push({canvas,spec,metrics});return metrics;});};return renderer;};}`;
            await route.fulfill({response,body:source+"\n"+observe});
        });
        await color.goto(base+"/modules/minigames/blackmarket/dev/harness.html");
        await color.addStyleTag({content:"#debug-log{display:none!important}"});
        await color.waitForFunction(()=>window.__colorRequests&&window.__colorRequests.length>=6,{},{timeout:60000});
        for(const level of [0,3,5,10]){
            await color.evaluate(level=>{window.__colorRequests=[];Panels.open("blackmarket",{mode:"dev",shadowOnly:true,debug:true,panelInstanceId:"color-review-"+level,decryptLevel:level,tradePoints:500000});},level);
            await color.waitForFunction(()=>document.querySelectorAll('.blackmarket-item-surface[data-surface-state="ready"]').length===6&&window.__colorRequests.length>=6,{},{timeout:60000});
            await color.locator('[data-bm-action="open-debug"]').click();
            await color.locator('[data-bm-field="decryptLevel"]').selectOption(String(level));
            await color.evaluate(()=>{window.__colorRequests=[];});
            await color.locator('[data-bm-action="debug-apply"]').click();
            await color.waitForFunction(level=>document.querySelector('.blackmarket-machine.decrypt-'+level)&&document.querySelectorAll('.blackmarket-item-surface[data-surface-state="ready"]').length===6&&window.__colorRequests.length>=6,level,{timeout:60000});
            await color.locator('[data-bm-action="close-drawer"]').click();
            const details=await color.evaluate(level=>{
                const check=(v,m)=>{if(!v)throw Error(m);};
                const stats=c=>{const p=c.getContext("2d").getImageData(0,0,c.width,c.height).data;let count=0,max=0,colored=0;for(let i=0;i<p.length;i+=4)if(p[i+3]>=200){count++;const spread=Math.max(p[i],p[i+1],p[i+2])-Math.min(p[i],p[i+1],p[i+2]);max=Math.max(max,spread);if(spread>24)colored++;}return {count,max,colored};};
                window.__colorStats=stats;
                const rows=Array.from(document.querySelectorAll('[data-bm-surface]')).map(c=>{const r=window.__colorRequests.findLast(r=>r.canvas===c);check(r&&r.spec.hiddenColorMode==="monochrome","card not gray");check(r.spec.sourceMaskMode==="source","transparent source segmentation changed");const p=stats(c);check(p.count>0&&p.colored===0,"card leaked original colors "+JSON.stringify({url:r.spec.assetUrl,mode:r.spec.hiddenColorMode,mask:r.spec.sourceMaskMode,...p}));return {url:r.spec.assetUrl,coverage:r.metrics.actualCoverage,...p};});
                const mineral=window.__colorRequests.findLast(r=>r.spec.assetUrl.includes("de73beb8_2")&&document.contains(r.canvas));check(!!mineral,"mineral fixture absent");mineral.canvas.closest('[data-bm-action="select"]').click();
                check(rows.every(r=>Math.abs(r.coverage-({0:.97,3:.84,5:.54,10:.18})[level])<.0001),"wrong decrypt coverage");
                return {cards:rows};
            },level);
            await color.locator('[data-bm-action="inspect-selected"]').click();
            const inspection=await color.evaluate(()=>{const c=document.querySelector('[data-bm-inspection-canvas]'),p=window.__colorStats(c);if(!p.count||p.colored)throw Error('inspection leaked color');return p;});
            await color.locator('[data-bm-action="inspection-rotate"]').click();
            await color.locator('[data-bm-action="inspection-side"][aria-pressed="false"]').click();
            const switched=await color.evaluate(()=>window.__colorStats(document.querySelector('[data-bm-inspection-canvas]')));
            if(!switched.count||switched.colored)throw Error('rotated/switched inspection leaked color');
            if(level===5){await color.locator('[data-inspection-action="fit"]').click();await color.screenshot({path:path.join(out,"product-gray-inspection.png")});}
            await color.locator('[data-bm-action="close-inspection"]').click();
            if(level===5)await color.screenshot({path:path.join(out,"product-gray-before.png")});
            // Re-select the colorful mineral, then use the real purchase confirmation.
            await color.evaluate(()=>window.__colorRequests.findLast(r=>r.spec.assetUrl.includes("de73beb8_2")&&document.contains(r.canvas)).canvas.closest('[data-bm-action="select"]').click());
            await color.locator('[data-bm-action="confirm"]').click();
            await color.waitForFunction(()=>{const c=document.querySelector('.state-revealed [data-bm-surface]');return c&&c.getAttribute('data-surface-state')==='ready'&&window.__colorRequests.some(r=>r.canvas===c&&r.spec.hiddenColorMode==='source');},{},{timeout:60000});
            const revealed=await color.evaluate(()=>{const c=document.querySelector('.state-revealed [data-bm-surface]'),p=window.__colorStats(c),r=window.__colorRequests.findLast(r=>r.canvas===c);if(p.colored<100||r.spec.mud!==false||r.spec.hiddenColorMode!=="source")throw Error("purchase did not restore color");for(const other of document.querySelectorAll('.blackmarket-offer:not(.state-revealed) [data-bm-surface]')){const request=window.__colorRequests.findLast(r=>r.canvas===other);if(request&&request.spec.hiddenColorMode!=="monochrome")throw Error("unbought offer restored color");}return {url:r.spec.assetUrl,...p};});
            if(level===5){await color.waitForTimeout(1800);await color.screenshot({path:path.join(out,"product-color-revealed.png")});}
            result.colorUi.push({level,pass:true,...details,inspection,switched,revealed});
            console.log(JSON.stringify({colorProductLevel:level,pass:true,grayCards:details.cards.length,inspection:true,revealedColoredPixels:revealed.colored}));
        }
        result.colorUiErrors=colorErrors;if(colorErrors.length)throw Error("color UI page errors: "+colorErrors.join("; "));
        await color.close();
    } finally {fs.writeFileSync(path.join(out,"browser-regression.json"),JSON.stringify(result,null,2));await browser.close();server.close();}
    if(result.cases.some(c=>!c.pass)||result.harness.some(r=>r.qa.qa.failed))process.exitCode=1;
})().catch(error=>{console.error(error.stack||error);server.close();process.exitCode=1;});
