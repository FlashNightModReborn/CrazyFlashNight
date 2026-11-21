#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path'),http=require('http'),assert=require('assert');
const ROOT=path.resolve(__dirname,'..'),OUT=path.join(ROOT,'tmp/u7-egg-stage');
fs.mkdirSync(OUT,{recursive:true});
let passed=0;
function check(value,message){assert(value,message);passed++}
function serve(req,res){
    const file=path.resolve(ROOT,'.'+decodeURIComponent((req.url||'/').split('?')[0]));
    if(!file.startsWith(ROOT+path.sep)){res.writeHead(403);res.end();return}
    fs.readFile(file,(error,bytes)=>{
        if(error){res.writeHead(404);res.end();return}
        const type={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.wav':'audio/wav','.woff2':'font/woff2'}[path.extname(file)]||'application/octet-stream';
        res.setHeader('Content-Type',type+'; charset=utf-8');res.end(bytes);
    });
}
async function ready(page){
    await page.waitForFunction(()=>window.EggStageSelectPanel&&EggStageSelectPanel.debugState().phase==='editing'&&EggStageSelectPanel.debugState().layout);
    await page.waitForFunction(()=>Array.from(document.querySelectorAll('.egg-panel img')).every(image=>image.complete&&image.naturalWidth>0));
}
async function runViewport(browser,address,viewport){
    const page=await browser.newPage({viewport}),errors=[];
    page.on('pageerror',error=>errors.push(String(error)));
    await page.goto(address+'/launcher/web/modules/egg-stage-select/dev/harness.html');
    await ready(page);
    check(await page.evaluate(()=>document.getAnimations().length>0),'normal motion runs the authored intro '+viewport.width);
    await page.waitForTimeout(1700);
    const initial=await page.evaluate(()=>{
        const state=EggStageSelectPanel.debugState(),panel=document.querySelector('.egg-panel').getBoundingClientRect();
        return {layout:state.layout,panel:{x:panel.x,y:panel.y,width:panel.width,height:panel.height},
            cards:Array.from(document.querySelectorAll('.egg-entry')).map(card=>{
                const rect=card.getBoundingClientRect(),image=card.querySelector('img');
                return {id:image.getAttribute('src'),x:(rect.x-panel.x)/(panel.width/540),y:(rect.y-panel.y)/(panel.width/540),
                    width:rect.width/(panel.width/540),height:rect.height/(panel.width/540),naturalWidth:image.naturalWidth};
            }),
            texts:document.querySelector('.egg-texts').textContent,header:!!document.querySelector('.appearance-service-header'),
            status:document.getElementById('egg-status').textContent,overflow:document.documentElement.scrollWidth>innerWidth};
    });
    check(Math.abs(initial.panel.width/initial.panel.height-540/370)<0.01,'original panel aspect ratio');
    check(initial.cards.length===3&&initial.cards.every(card=>Math.abs(card.x-initial.layout.previews[Object.keys(initial.layout.previews).find(key=>card.id.endsWith(key+'.png'))].x)<0.1),'three original preview positions '+viewport.width+' '+JSON.stringify(initial));
    check(initial.cards.every(card=>Math.abs(card.width-initial.layout.previews[Object.keys(initial.layout.previews).find(key=>card.id.endsWith(key+'.png'))].width)<0.1),'original preview widths '+viewport.width);
    check(initial.texts.includes('密林深处')&&initial.texts.includes('阴暗处似乎有神秘人士正在运货')&&initial.texts.includes('机器游荡区')&&initial.texts.includes('密林中央'),'original Chinese titles and descriptions');
    check(!initial.header&&initial.status===''&&!initial.overflow,'generic header/footer removed and no document overflow');
    const expectedScale=Math.min(viewport.width/540,viewport.height/370);
    check(Math.abs(initial.panel.width-540*expectedScale)<0.2&&Math.abs(initial.panel.height-370*expectedScale)<0.2,'panel uses the shared scale without distortion');
    await page.screenshot({path:path.join(OUT,'egg-'+viewport.width+'x'+viewport.height+'.png')});
    await page.locator('.egg-entry').first().click();
    check(await page.locator('#egg-confirm').isVisible(),'preview opens the original confirmation surface');
    check(await page.locator('#egg-confirm-text').textContent()==='确认选择该关卡吗？','original confirmation text');
    check(await page.locator('.egg-entry.selected').count()===1,'selected preview remains visible');
    await page.waitForTimeout(650);
    check(await page.locator('.egg-entry').evaluateAll(cards=>cards.every(card=>Number(getComputedStyle(card).opacity)>.9)),'confirmation does not replay or hide preview intro');
    await page.screenshot({path:path.join(OUT,'egg-confirm-'+viewport.width+'x'+viewport.height+'.png')});
    await page.locator('#egg-confirm-cancel').click();
    await page.waitForFunction(()=>document.getElementById('egg-confirm').hidden);
    check(await page.evaluate(()=>__sent.filter(message=>message.cmd==='enter').length===0),'cancel never enters a stage');
    await page.locator('.egg-entry').nth(2).click();
    await page.locator('#egg-confirm-enter').focus();await page.keyboard.press('Enter');
    await page.waitForFunction(()=>EggStageSelectPanel.debugState().phase==='closed');
    check(await page.evaluate(()=>__sent.filter(message=>message.cmd==='enter').length===1&&__sent.filter(message=>message.cmd==='close').length===1),'confirm enters and closes exactly once');
    const sounds=await page.evaluate(()=>performance.getEntriesByType('resource').map(entry=>entry.name));
    check(['panel-enter.wav','confirm-open.wav','confirm-cancel.wav'].every(name=>sounds.some(url=>url.endsWith('/'+name))),'original timeline audio resources are consumed');
    await page.evaluate(()=>{__locked=true;__open()});
    await ready(page);await page.waitForTimeout(1700);
    const locked=page.locator('.egg-entry').nth(1);
    await locked.hover();
    check(await page.locator('#egg-lock-notice').isVisible(),'locked preview retains its original hover hint');
    await locked.click();
    check(await page.locator('#egg-confirm').isHidden(),'locked preview cannot open confirmation');
    check((await page.locator('#egg-status').textContent()).includes('彩蛋进度达到 4'),'locked reason remains readable');
    await page.screenshot({path:path.join(OUT,'egg-locked-'+viewport.width+'x'+viewport.height+'.png')});
    check(errors.length===0,'no browser exceptions: '+errors.join(';'));
    await page.close();
}
async function runReduced(browser,address){
    const page=await browser.newPage({viewport:{width:1024,height:576},reducedMotion:'reduce'});
    await page.goto(address+'/launcher/web/modules/egg-stage-select/dev/harness.html');await ready(page);
    check(await page.evaluate(()=>document.getAnimations().length===0),'reduced motion has no active animations');
    await page.locator('.egg-entry').first().click();
    check(await page.locator('#egg-confirm').isVisible(),'reduced motion still opens confirmation');
    await page.locator('#egg-confirm-cancel').click();
    await page.waitForFunction(()=>document.getElementById('egg-confirm').hidden);
    await page.screenshot({path:path.join(OUT,'egg-reduced.png')});
    await page.close();
}
async function main(){
    const {chromium}=require('../launcher/perf/node_modules/playwright');
    const server=http.createServer(serve);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const executablePath=[process.env.CF7_BROWSER_EXE,'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe','C:/Program Files/Microsoft/Edge/Application/msedge.exe'].find(candidate=>candidate&&fs.existsSync(candidate));
    const browser=await chromium.launch({executablePath,headless:true});
    try{
        for(const viewport of [{width:1024,height:576},{width:1366,height:768},{width:1920,height:1080}])await runViewport(browser,'http://127.0.0.1:'+server.address().port,viewport);
        await runReduced(browser,'http://127.0.0.1:'+server.address().port);
        const result={ok:true,passed,viewports:3,reducedMotion:true};fs.writeFileSync(path.join(OUT,'result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
    }finally{await browser.close();await new Promise(resolve=>server.close(resolve))}
}
main().catch(error=>{console.error(error.stack);process.exitCode=1});
