'use strict';
// Real production resolver, SVG/PNG decoding and small-size pixels in Chromium.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const http = require('http');
const { chromium } = require('../../launcher/perf/node_modules/playwright');
const ROOT = path.resolve(__dirname, '../..');
const WEB = path.join(ROOT, 'launcher/web');
const OUT = path.join(ROOT, 'tmp/dog-portraits/web-' + Date.now());
const refs = ['敌人-制式军警犬','敌人-盗贼撕咬犬','敌人-军阀铁卫犬'];
const manifest = JSON.parse(fs.readFileSync(path.join(WEB,'assets/enemy-portraits/manifest.json'),'utf8'));
const units = JSON.parse(fs.readFileSync(path.join(ROOT,'data/units/units.json'),'utf8').replace(/^\uFEFF/,''));
for (let i=0;i<3;i++) assert.strictEqual(units.find(u=>u.id===475+i).spritename,refs[i]);
async function main() {
    fs.mkdirSync(OUT,{recursive:true});
    const server = http.createServer((req,res)=>{
        const file = path.resolve(WEB,'.'+new URL(req.url,'http://localhost').pathname);
        if (path.relative(WEB,file).startsWith('..')) {res.writeHead(403);res.end();return;}
        if (req.url==='/') {res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><title>Three native dog portraits</title>');return;}
        fs.readFile(file,(e,data)=>{
            if (e) {res.writeHead(404);res.end();return;}
            const mime={'.svg':'image/svg+xml','.png':'image/png','.json':'application/json','.js':'application/javascript'};
            res.setHeader('Content-Type',mime[path.extname(file)]||'application/octet-stream');res.end(data);
        });
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    let browser;
    try {
        const edge=[process.env['ProgramFiles(x86)']||'C:/Program Files (x86)',process.env.ProgramFiles||'C:/Program Files']
            .map(p=>path.join(p,'Microsoft/Edge/Application/msedge.exe')).find(fs.existsSync);
        browser=await chromium.launch({executablePath:edge,headless:true});
        const page=await browser.newPage({viewport:{width:1100,height:730}});
        const errors=[];page.on('pageerror',e=>errors.push(e.message));
        await page.goto('http://127.0.0.1:'+server.address().port+'/');
        await page.addScriptTag({url:'/modules/portrait-resolver.js'});
        const results=await page.evaluate(async({refs,entries})=>{
            document.body.style.cssText='margin:20px;background:#e9e6dd;font:20px "Microsoft YaHei";color:#263332';
            const output=[];
            const load=async url=>{const im=new Image();im.src=url;await im.decode();return im;};
            const pixels=(image,size)=>{
                const c=document.createElement('canvas');c.width=c.height=size;
                const g=c.getContext('2d',{willReadFrequently:true});g.drawImage(image,0,0,size,size);return g.getImageData(0,0,size,size).data;
            };
            for (const [index,ref] of refs.entries()) {
                const col=document.createElement('section');col.style.cssText='display:inline-block;vertical-align:top;width:350px';
                col.textContent=ref.replace('敌人-','');document.body.appendChild(col);
                const fallback=await load('/'+entries[ref].variants.default.subject.pngFallback.url);
                for (const consumer of ['arena','team']) {
                    for (const size of [512,80,48,32]) {
                        const box=document.createElement('div'),img=document.createElement('img');box.appendChild(img);col.appendChild(box);
                        box.style.cssText='display:inline-block;vertical-align:top;width:'+(size===512?320:size)+'px;height:'+(size===512?320:size)+'px;';
                        img.style.cssText='display:block;width:100%;height:100%;object-fit:contain';
                        if (consumer==='team') box.style.display='none';
                        await EnemyPortraits.mount(box,img,{portraitRef:ref,consumer});await img.decode();
                        await new Promise(resolve=>setTimeout(resolve,0));
                        const data=pixels(img,size),other=pixels(fallback,size);let visible=0,transparent=0,diff=0;
                        for(let p=0;p<data.length;p+=4){
                            if(data[p+3]>16)visible++;if(data[p+3]===0)transparent++;
                            for(let k=0;k<3;k++)diff+=Math.abs(data[p+k]*data[p+3]/255-other[p+k]*other[p+3]/255);
                            diff+=Math.abs(data[p+3]-other[p+3]);
                        }
                        output.push({ref,consumer,size,source:box.getAttribute('data-portrait-source'),visible,transparent,premultipliedRgbaMae:diff/data.length});
                    }
                }
            }
            return output;
        },{refs,entries:manifest.entries});
        for(const row of results){
            assert.strictEqual(row.source,'svg',JSON.stringify(row));
            assert(row.visible>row.size*row.size*.12 && row.transparent>row.size*row.size*.12,JSON.stringify(row));
            assert(row.premultipliedRgbaMae<8,JSON.stringify(row));
        }
        assert.deepStrictEqual(errors,[]);
        await page.screenshot({path:path.join(OUT,'three-dog-browser.png')});
        fs.writeFileSync(path.join(OUT,'result.json'),JSON.stringify({status:'PASS',cases:results.length,errors,results},null,2)+'\n');
        console.log(JSON.stringify({status:'PASS',cases:results.length,maxPremultipliedRgbaMae:Math.max(...results.map(r=>r.premultipliedRgbaMae)),evidence:OUT}));
    } finally {if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
