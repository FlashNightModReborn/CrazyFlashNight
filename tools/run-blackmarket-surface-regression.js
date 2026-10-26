#!/usr/bin/env node
"use strict";
// Offline full-pool pixel regression. Supply @napi-rs/canvas through NODE_PATH.
// This tool writes only --out; it never rebuilds the catalog or changes the pool.
const fs = require("fs"), path = require("path"), vm = require("vm"), crypto = require("crypto");
const { Worker, isMainThread, parentPort, workerData } = require("worker_threads");
const ROOT = path.resolve(__dirname, "..");
const SURFACE = path.join(ROOT, "launcher/web/modules/minigames/blackmarket/visual/item-surface.js");
const POOL = require(path.join(ROOT, "launcher/web/modules/minigames/blackmarket/visual/visual-pool-manifest.js"));
const Core = require(path.join(ROOT, "launcher/web/modules/minigames/blackmarket/core/index.js"));
const COLOR_POLICY = Core.HIDDEN_COLOR_MODE;
const LEVELS = [.97, .84, .54, .18];
const OPTIONS = { seed: "audit-s1", paddingRatio: .065, autoRotate: true, sharpenSource: true, sharpenStrength: .18 };
const RUNTIME = { node: process.version, canvas: require("@napi-rs/canvas/package.json").version };
const hash = data => crypto.createHash("sha256").update(data).digest("hex");
const renderCoreHash = text => hash(text.slice(0, text.indexOf("    function createRenderer(")));
function arg(name) { const at = process.argv.indexOf(name); return at < 0 ? null : process.argv[at + 1]; }
function check(value, message) { if (!value) throw new Error(message); }
function count(mask) { let n=0;for(let i=0;i<mask.length;i++)n+=mask[i];return n; }
function components(mask,w,h) {
    const seen=new Uint8Array(mask.length),queue=new Int32Array(mask.length);let n=0;
    for(let i=0;i<mask.length;i++)if(mask[i]&&!seen[i]) {
        n++;let head=0,tail=1;queue[0]=i;seen[i]=1;
        while(head<tail){const p=queue[head++],x=p%w,y=Math.floor(p/w);
            for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){
                const xx=x+dx,yy=y+dy;if((!dx&&!dy)||xx<0||xx>=w||yy<0||yy>=h)continue;
                const q=yy*w+xx;if(mask[q]&&!seen[q]){seen[q]=1;queue[tail++]=q;}
            }
        }
    }return n;
}
async function workerRun() {
    const cv=require("@napi-rs/canvas");
    function compile(source) {const m={exports:{}};vm.compileFunction(source,["module","OffscreenCanvas"])(m,function(w,h){return cv.createCanvas(w,h);});return m.exports;}
    const baselineText=fs.readFileSync(workerData.baseline,"utf8");
    const baseline=compile(baselineText.replace("imageData: output,", "imageData: output, _probe:{objectMask:objectMask,coverage:coverage,envelope:envelope},")
        .replace("return { canvas: targetCanvas, metrics: rendered.metrics };", "return {canvas:targetCanvas,metrics:rendered.metrics,_probe:rendered._probe};"));
    const candidate=compile(fs.readFileSync(SURFACE,"utf8"));
    function raw(canvas) {return canvas.getContext("2d").getImageData(0,0,canvas.width,canvas.height).data;}
    async function thumb(canvas,id,kind) {
        const t=cv.createCanvas(160,240);t.getContext("2d").drawImage(canvas,0,0,160,240);
        fs.writeFileSync(path.join(workerData.out,"thumbs",id+"-"+kind+".webp"),await t.encode("webp",82));
    }
    for(const job of workerData.jobs) {
        const {id,entry}=job;
        try {
            const bytes=fs.readFileSync(path.join(ROOT,"launcher/web",entry.u));
            const image=await cv.loadImage(bytes);
            let candidateImage=image, mode=COLOR_POLICY, maskMode=entry.h, fallback=null, fallbackReason=null;
            const source=cv.createCanvas(image.width,image.height);source.getContext("2d").drawImage(image,0,0);
            const extraction=candidate.extractObjectMask(source.getContext("2d").getImageData(0,0,image.width,image.height),{sourceMaskMode:maskMode});
            if((!extraction.bounds.count || extraction.quality.status==="ambiguous") && entry.f) {
                const alt=await cv.loadImage(path.join(ROOT,"launcher/web",entry.f));
                const altCanvas=cv.createCanvas(alt.width,alt.height);altCanvas.getContext("2d").drawImage(alt,0,0);
                const altMask=candidate.extractObjectMask(altCanvas.getContext("2d").getImageData(0,0,alt.width,alt.height),{sourceMaskMode:entry.fm||"monochrome"});
                if(!extraction.bounds.count || altMask.source==="alpha" || altMask.source==="alpha-core-with-fringe") {
                    candidateImage=alt;mode="monochrome";maskMode=entry.fm||"monochrome";fallback=entry.f;
                    fallbackReason=!extraction.bounds.count?"empty-source":"ambiguous-source";
                }
            }
            if(job.reuse && !fallback && !job.reuse.fallback && job.reuse.sourceSha256===hash(bytes)) {
                // Reuse only when render-core bytes, primary u/h, primary image
                // bytes, baseline and every render option are identical.
                parentPort.postMessage({row:{...job.reuse,reused:true,testedModuleSha256:workerData.reuseModuleSha256}});continue;
            }
            const row={id,url:entry.u,names:job.names,sourceSha256:hash(bytes),fallback,fallbackReason,
                effectiveSourceSha256:hash(fs.readFileSync(path.join(ROOT,"launcher/web",fallback||entry.u))),
                sourceMaskMode:maskMode,hiddenColorMode:mode,colorChecks:[],reused:false,testedModuleSha256:workerData.moduleSha256,levels:[],extraSeedChecks:0};
            let previous=null, geometry=null;
            for(const coverage of LEVELS) {
                const oldStart=performance.now();
                const old=baseline.processBitmap(workerData.colorComparison?candidateImage:image,512,768,{...OPTIONS,coverage,hiddenColorMode:workerData.colorComparison&&fallback?"monochrome":entry.h,sourceMaskMode:workerData.colorComparison?maskMode:entry.h,diagnostics:true});
                const oldMs=performance.now()-oldStart;
                const od=old.diagnostics || {objectMask:old._probe.objectMask,mudMask:old._probe.envelope.mask};
                let oldCovered=0;for(let i=0;i<od.objectMask.length;i++)if(od.objectMask[i]&&od.mudMask[i])oldCovered++;
                const start=performance.now();
                const next=candidate.processBitmap(candidateImage,512,768,{...OPTIONS,coverage,hiddenColorMode:mode,sourceMaskMode:maskMode,diagnostics:true});
                const newMs=performance.now()-start;
                const d=next.diagnostics;let object=0,covered=0;
                if(workerData.colorComparison){check(hash(d.objectMask)===hash(od.objectMask),"color policy changed object geometry");check(hash(d.mudMask)===hash(od.mudMask),"color policy changed mud coverage");check(hash(d.revealMask)===hash(od.revealMask),"color policy changed revealed regions");}
                for(let i=0;i<d.objectMask.length;i++) {
                    if(d.objectMask[i]){object++;covered+=d.mudMask[i];check(d.budgetMask[i]===d.mudMask[i],"interior budget changed");}
                    if(previous&&previous[i])check(d.revealMask[i],"reveal is not nested");
                }
                check(object>0,"empty rendered foreground");check(covered===Math.round(object*coverage),"final pixel budget mismatch");
                check(next.metrics.coveredObjectPixels===covered,"reported covered pixels mismatch");
                check(Math.abs(next.metrics.actualCoverage-covered/object)<=5.01e-8,"reported coverage mismatch");
                check(next.metrics.unreachableObjectPixels===0,"unreachable object pixels");
                check(components(d.revealMask,512,768)<=next.metrics.componentCount,"reveal speckles exceed real parts");
                previous=d.revealMask;geometry={mask:d.objectMask,anchor:next.metrics.anchor};
                const record={coverage,old:{objectPixels:old.metrics.objectPixels,coveredPixels:oldCovered,
                    actualCoverage:old.metrics.objectPixels?oldCovered/old.metrics.objectPixels:null,reportedCoverage:old.metrics.actualCoverage,
                    sourceMask:old.metrics.sourceMask,elapsedMs:oldMs,rgbaSha256:hash(raw(old.canvas))},
                    candidate:{...next.metrics,totalElapsedMs:newMs,rgbaSha256:hash(raw(next.canvas))}};
                const pixels=raw(next.canvas);let exposed=0,maxSpread=0;
                for(let i=0;i<d.objectMask.length;i++)if(d.objectMask[i]&&!d.mudMask[i]&&pixels[i*4+3]>=200){const p=i*4;exposed++;maxSpread=Math.max(maxSpread,Math.max(pixels[p],pixels[p+1],pixels[p+2])-Math.min(pixels[p],pixels[p+1],pixels[p+2]));}
                check(exposed>0,"no opaque revealed pixels");check(maxSpread<=12,"saturated source leaked before purchase: "+maxSpread);
                row.colorChecks.push({coverage,exposedPixels:exposed,maxNeutralChannelSpread:maxSpread,geometryUnchanged:workerData.colorComparison,rgbaChanged:record.old.rgbaSha256!==record.candidate.rgbaSha256});
                if(workerData.colorComparison&&(entry.h!=="source"||fallback)){const op=raw(old.canvas);for(let i=0;i<d.objectMask.length;i++)if(d.objectMask[i])for(let ch=0;ch<4;ch++)check(pixels[i*4+ch]===op[i*4+ch],"existing neutral body changed");}
                let visible=0,maxVisibleSpread=0;for(let p=0;p<pixels.length;p+=4)if(pixels[p+3]>=200){visible++;maxVisibleSpread=Math.max(maxVisibleSpread,Math.max(pixels[p],pixels[p+1],pixels[p+2])-Math.min(pixels[p],pixels[p+1],pixels[p+2]));}
                check(visible>0&&maxVisibleSpread<=24,"visible fringe leaked original color: "+maxVisibleSpread);row.colorChecks[row.colorChecks.length-1].maxVisibleChannelSpread=maxVisibleSpread;
                row.levels.push(record);
                if(coverage===.54){await thumb(old.canvas,id,"old");await thumb(next.canvas,id,"new");}
                // Every input gets a second full render: deterministic RGBA, not just a scalar metric.
                if(coverage===.18){const repeat=candidate.processBitmap(candidateImage,512,768,{...OPTIONS,coverage,hiddenColorMode:mode,sourceMaskMode:maskMode});check(hash(raw(repeat.canvas))===record.candidate.rgbaSha256,"RGBA nondeterminism");}
            }
            const clean=candidate.processBitmap(candidateImage,512,768,{...OPTIONS,mud:false,hiddenColorMode:"source",sourceMaskMode:maskMode,preserveSourceAlpha:true,sharpenSource:false});
            check(clean.metrics.orientationDeg===row.levels[0].candidate.orientationDeg,"revealed geometry orientation drift");
            check(clean.metrics.coveredObjectPixels===0,"clean image retains mud");row.clean={rgbaSha256:hash(raw(clean.canvas)),metrics:clean.metrics};
            if(workerData.colorComparison){const beforeClean=baseline.processBitmap(candidateImage,512,768,{...OPTIONS,mud:false,hiddenColorMode:"source",sourceMaskMode:maskMode,preserveSourceAlpha:true,sharpenSource:false});check(hash(raw(beforeClean.canvas))===row.clean.rgbaSha256,"revealed source colors changed");row.clean.matchesPrevious=true;}
            for(const seed of ["regression-s2","regression-s3"]) {
                previous=null;
                for(const coverage of LEVELS) {
                    const masks=candidate.buildCoverageMasks(geometry.mask,512,768,geometry.anchor,coverage,seed);
                    check(masks.reachablePixels===masks.objectPixels,"seed sweep unreachable");
                    check(count(masks.mudInside)===Math.round(masks.objectPixels*coverage),"seed sweep budget");
                    check(components(masks.reveal,512,768)<=masks.componentCount,"seed sweep speckles");
                    if(previous)for(let i=0;i<previous.length;i++)if(previous[i])check(masks.reveal[i],"seed sweep nonnested");
                    previous=masks.reveal;row.extraSeedChecks++;
                }
            }
            parentPort.postMessage({row});
        } catch(error) {parentPort.postMessage({failure:{id,url:entry.u,error:error.stack||String(error)}});}
    }
}
async function main() {
    const out=arg("--out"),baseline=arg("--baseline"),colorComparison=arg("--comparison")==="color";
    check(out&&path.isAbsolute(out)&&baseline,"Usage: --out ABS_DIR --baseline OLD_ITEM_SURFACE_JS [--workers 4]");
    fs.mkdirSync(path.join(out,"thumbs"),{recursive:true});
    const groups=new Map();
    for(const entry of POOL.entries){const key=entry.u+"|"+entry.h;let g=groups.get(key);if(!g){g={id:String(groups.size).padStart(4,"0"),entry,names:[]};groups.set(key,g);}g.names.push(entry.n);}
    const jobs=[...groups.values()], workers=Math.min(8,Math.max(1,Number(arg("--workers"))||4));
    const result={baselinePath:baseline,baselineSha256:hash(fs.readFileSync(baseline)),candidateSha256:hash(fs.readFileSync(SURFACE)),
        renderCoreSha256:renderCoreHash(fs.readFileSync(SURFACE,"utf8")),
        renderOptions:OPTIONS,colorPolicy:COLOR_POLICY,comparison:colorComparison?"previous-candidate-color":"original-algorithm",coreSha256:hash(fs.readFileSync(path.join(ROOT,"launcher/web/modules/minigames/blackmarket/core/index.js"))),rasterRuntime:RUNTIME,
        poolSha256:hash(JSON.stringify(POOL)),poolEntries:POOL.entries.length,uniqueInputs:jobs.length,
        resolution:[512,768],fullRenderSeed:OPTIONS.seed,levels:LEVELS,extraMaskSeeds:["regression-s2","regression-s3"],
        evidence:"Offline native Canvas full RGBA renders; additional seeds test actual foreground graphs. Not WebView2/game E2E or human acceptance.",
        startedAt:new Date().toISOString(),rows:[],failures:[]};
    let reuseModuleSha256=null;
    if(arg("--reuse")) {
        check(arg("--reuse-source")&&arg("--reuse-pool"),"reuse requires the exact prior source and pool snapshots");
        const prior=JSON.parse(fs.readFileSync(arg("--reuse"),"utf8")),source=fs.readFileSync(arg("--reuse-source"),"utf8"),pool=JSON.parse(fs.readFileSync(arg("--reuse-pool"),"utf8"));
        check(prior.colorPolicy===COLOR_POLICY&&prior.comparison===result.comparison,"reuse color policy mismatch");
        check(hash(source)===prior.candidateSha256&&renderCoreHash(source)===result.renderCoreSha256,"reuse rendering core mismatch");
        check(hash(JSON.stringify(pool))===prior.poolSha256&&prior.baselineSha256===result.baselineSha256,"reuse pool/baseline receipt mismatch");
        check(JSON.stringify(prior.renderOptions)===JSON.stringify(OPTIONS)&&JSON.stringify(prior.rasterRuntime)===JSON.stringify(RUNTIME),"reuse render options/runtime mismatch");
        check(JSON.stringify(prior.levels)===JSON.stringify(LEVELS)&&prior.fullRenderSeed===OPTIONS.seed&&JSON.stringify(prior.resolution)==="[512,768]"
            &&JSON.stringify(prior.extraMaskSeeds)===JSON.stringify(result.extraMaskSeeds),"reuse render parameters mismatch");
        const previous=[...new Map(pool.entries.map(e=>[e.u+"|"+e.h,e])).values()];
        for(const job of jobs){const old=previous[Number(job.id)],row=prior.rows.find(r=>r.id===job.id);if(old&&row&&old.u===job.entry.u&&old.h===job.entry.h&&row.url===job.entry.u)job.reuse=row;}
        reuseModuleSha256=prior.candidateSha256;result.reuseReceipt={candidateSha256:prior.candidateSha256,finishedAt:prior.finishedAt,renderCoreSha256:result.renderCoreSha256};
    }
    const journal=path.join(out,"regression-progress.jsonl");fs.writeFileSync(journal,"");
    await Promise.all(Array.from({length:workers},(_,slot)=>new Promise((resolve,reject)=>{
        const worker=new Worker(__filename,{workerData:{out,baseline,colorComparison,moduleSha256:result.candidateSha256,reuseModuleSha256,jobs:jobs.filter((_,i)=>i%workers===slot)}});
        worker.on("message",message=>{fs.appendFileSync(journal,JSON.stringify(message)+"\n");if(message.row)result.rows.push(message.row);else result.failures.push(message.failure);
            const done=result.rows.length+result.failures.length;if(done%40===0||done===jobs.length)console.log(JSON.stringify({done,total:jobs.length,failures:result.failures.length}));});
        worker.on("error",reject);worker.on("exit",code=>code?reject(new Error("worker exit "+code)):resolve());
    })));
    result.rows.sort((a,b)=>a.id.localeCompare(b.id));result.finishedAt=new Date().toISOString();
    result.fullRenders=result.rows.length*(colorComparison?11:10);result.additionalMaskCases=result.rows.reduce((n,r)=>n+r.extraSeedChecks,0);
    result.reusedRows=result.rows.filter(r=>r.reused).length;result.newFullRenders=(result.rows.length-result.reusedRows)*(colorComparison?11:10);
    check(result.candidateSha256===hash(fs.readFileSync(SURFACE)),"candidate source changed during corpus run");
    fs.writeFileSync(path.join(out,"full-pool-regression.json"),JSON.stringify(result,null,2));
    console.log(JSON.stringify({complete:true,passed:result.rows.length,failed:result.failures.length,fullRenders:result.fullRenders,maskCases:result.additionalMaskCases,reusedRows:result.reusedRows,newFullRenders:result.newFullRenders}));
    if(result.failures.length)process.exitCode=1;
}
(isMainThread?main():workerRun()).catch(error=>{console.error(error.stack||error);process.exitCode=1;});
