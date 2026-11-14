'use strict';
// Read-only browser check against the production Icons renderer and manifest.
const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const root = path.resolve(__dirname, '../..');
const web = path.join(root, 'launcher/web');
const output = path.resolve(root, process.argv[2] || 'tmp/ak47-fire-kylin/web-review');
if (!output.startsWith(path.join(root, 'tmp/ak47-fire-kylin') + path.sep)) throw new Error('Review output outside task directory');
fs.mkdirSync(output, { recursive: true });
const { chromium } = require(path.join(root, 'launcher/perf/node_modules/playwright'));
const markup = `<!doctype html><meta charset="utf-8"><title>Fire Kylin icon</title>
<style>body{background:#202936;color:#eee;font:16px Arial;margin:24px}.sample-icon,#icon,#phase{width:128px;height:128px;display:block}#phase{margin-top:24px}</style>
<h1>AK47 火麒麟 · 8 帧眼焰</h1><div id="icon"></div><div id="phase"></div>
<script>window.CF7_ICON_ROOT='/icons/';</script><script src="/modules/asset-timeline.js"></script><script src="/modules/icons.js"></script>
<script>Icons.load(function(){document.getElementById('icon').innerHTML=Icons.html('Codex-AK47火麒麟','sample-icon');Icons.enhance(document);window.ready=true;});</script>`;
const mime = {'.js':'text/javascript','.json':'application/json','.png':'image/png','.webp':'image/webp','.css':'text/css'};
const server = http.createServer((req,res) => {
    const pathname = decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    if (pathname === '/__review') { res.setHeader('Content-Type','text/html; charset=utf-8'); return res.end(markup); }
    if (pathname === '/favicon.ico') { res.statusCode=204;return res.end(); }
    const filename = path.resolve(web, '.' + pathname);
    if (!filename.startsWith(web + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) {res.statusCode=404;return res.end();}
    res.setHeader('Content-Type',mime[path.extname(filename)] || 'application/octet-stream');
    fs.createReadStream(filename).pipe(res);
});

(async () => {
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const browser = await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
    const page = await browser.newPage({viewport:{width:620,height:440}});
    const errors=[];page.on('pageerror',e=>errors.push(String(e)));
    try {
        await page.goto(`http://127.0.0.1:${server.address().port}/__review`);
        await page.waitForFunction(()=>window.ready && [...document.querySelectorAll('#icon img')].every(i=>i.complete&&i.naturalWidth));
        const metadata = await page.evaluate(()=>({animated:Icons.isAnimated('Codex-AK47火麒麟'),entry:Icons.entry('Codex-AK47火麒麟')}));
        if (!metadata.animated) throw new Error('Production icon is static');
        if (!metadata.entry.f2) throw new Error('Semantic frame 2 missing');
        const layers=metadata.entry.nestedAnimation.layers;
        if (layers.length !== 1 || layers[0].frames.length !== 8 || Number(layers[0].fps || metadata.entry.fps) !== 30) throw new Error('Wrong Web eye timeline');
        const live = await page.evaluate(()=>new Promise(resolve=>{
            const samples=[];const start=performance.now();let previous='';
            function tick(now){
                const key=[...document.querySelectorAll('#icon img')].map(i=>i.src).join('|');
                if(key!==previous){samples.push({ms:now-start,key});previous=key;}
                if(now-start>=750)resolve(samples);else requestAnimationFrame(tick);
            }
            requestAnimationFrame(tick);
        }));
        if (new Set(live.map(s=>s.key)).size < 4) throw new Error('Visible icon did not animate');
        await page.screenshot({path:path.join(output,'page.png')});
        await page.locator('#icon').screenshot({path:path.join(output,'live-icon.png')});
        const hashes=[];
        for(let index=0;index<8;index++){
            await page.evaluate(i=>{
                if(window.phasePreview) window.phasePreview.destroy();
                const entry=JSON.parse(JSON.stringify(Icons.entry('Codex-AK47火麒麟')));
                delete entry.f1;
                delete entry._normFrames;
                for(const layer of entry.nestedAnimation.layers){layer.frames=[layer.frames[i]];delete layer.timelineFrames;delete layer._normFrames;}
                window.phasePreview=Icons.createPreview(document.getElementById('phase'),entry,{className:'sample-icon',animate:false});
            },index);
            await page.waitForFunction(()=>[...document.querySelectorAll('#phase img')].every(i=>i.complete&&i.naturalWidth));
            const png=await page.locator('#phase').screenshot({path:path.join(output,`phase-${index}.png`)});
            hashes.push(crypto.createHash('sha256').update(png).digest('hex'));
        }
        if(new Set(hashes).size<4)throw new Error('Rendered phases are visually static');
        if(errors.length)throw new Error(errors.join('\n'));
        const result={passed:true,animated:metadata.animated,frames:8,fps:30,nominalCycleSeconds:8/30,
            semanticFrame2:metadata.entry.f2,distinctRenderedPhases:new Set(hashes).size,
            liveDistinctStates:new Set(live.map(s=>s.key)).size,live,errors};
        fs.writeFileSync(path.join(output,'result.json'),JSON.stringify(result,null,2)+'\n');
        process.stdout.write(JSON.stringify(result,null,2)+'\n');
    } finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error.stack||error);server.close();process.exitCode=1;});
