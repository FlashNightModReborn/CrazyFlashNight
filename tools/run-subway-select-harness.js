#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path'),http=require('http'),assert=require('assert');
const ROOT=path.resolve(__dirname,'..'),OUT=path.join(ROOT,'tmp/u7-subway');
fs.mkdirSync(OUT,{recursive:true});
let passed=0;
function check(value,message){assert(value,message);passed++}
function serve(req,res){
    const file=path.resolve(ROOT,'.'+decodeURIComponent((req.url||'/').split('?')[0]));
    if(!file.startsWith(ROOT+path.sep)){res.writeHead(403);res.end();return}
    fs.readFile(file,(error,bytes)=>{
        if(error){res.writeHead(404);res.end();return}
        const type={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.woff2':'font/woff2'}[path.extname(file)]||'application/octet-stream';
        res.setHeader('Content-Type',type+'; charset=utf-8');res.end(bytes);
    });
}
async function runViewport(browser,address,viewport){
    const page=await browser.newPage({viewport}),errors=[];
    page.on('pageerror',error=>errors.push(String(error)));
    await page.goto(address+'/launcher/web/modules/subway-select/dev/harness.html');
    await page.waitForFunction(()=>window.SubwaySelectPanel&&SubwaySelectPanel.debugState().phase==='editing');
    await page.waitForFunction(()=>document.querySelectorAll('.subway-route').length===17);
    await page.waitForLoadState('networkidle');
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    const initial=await page.evaluate(()=>{
        const map=document.querySelector('.subway-map').getBoundingClientRect();
        const stations=Array.from(document.querySelectorAll('.subway-station')).map(station=>{
            const rect=station.getBoundingClientRect(),image=station.querySelector('img');
            return {id:station.getAttribute('data-station'),frame:station.getAttribute('data-frame'),src:image.getAttribute('src'),
                inside:rect.left>=map.left-1&&rect.right<=map.right+1&&rect.top>=map.top-1&&rect.bottom<=map.bottom+1};
        });
        const visibleRoutes=Array.from(document.querySelectorAll('.subway-route[data-unlocked="true"]'))
            .map(route=>route.getAttribute('data-route')).sort((a,b)=>Number(a)-Number(b));
        return {ratio:map.width/map.height,mapHeight:map.height,stations:stations,visibleRoutes:visibleRoutes,
            visibleNames:document.querySelectorAll('.subway-station.is-name-visible').length,
            header:!!document.querySelector('.subway-panel .appearance-service-header'),
            status:document.getElementById('subway-status').textContent,
            scrollWidth:document.documentElement.scrollWidth,viewport:innerWidth,
            routeWidth:document.querySelector('.subway-map-art').naturalWidth,routeHeight:document.querySelector('.subway-map-art').naturalHeight};
    });
    check(Math.abs(initial.ratio-392/352)<0.01,'original route aspect ratio '+viewport.width+' '+JSON.stringify(initial));
    check(initial.routeWidth===392&&initial.routeHeight===352,'original route SVG loaded');
    check(initial.mapHeight>=460,'removing the header enlarges the map into the freed space');
    check(!initial.header&&initial.visibleNames===0&&initial.status==='','no header, progress text or default station labels');
    check(JSON.stringify(initial.stations.map(station=>station.frame))===JSON.stringify(['4','1','2','3']),'all four authored station frames projected');
    check(initial.stations.every(station=>station.src==='assets/subway/station-'+station.frame+'.svg'&&station.inside),'station art and labels fit original map '+viewport.width);
    check(JSON.stringify(initial.visibleRoutes)===JSON.stringify(['2','6']),'only routes whose station pair is unlocked regain color');
    check(initial.scrollWidth<=initial.viewport,'panel has no horizontal document overflow');
    await page.screenshot({path:path.join(OUT,'subway-'+viewport.width+'x'+viewport.height+'.png')});
    await page.locator('.subway-route[data-route="4"]').focus();
    check(await page.locator('.subway-route[data-route="4"]').getAttribute('class').then(value=>value.includes('hovered')),'route focus is tracked on the authored path');
    check(await page.locator('.subway-route[data-route="4"] .subway-route-outline').first().evaluate(path=>getComputedStyle(path).strokeOpacity)==='1','route hover draws a white outline');
    check(await page.evaluate(()=>Array.from(document.querySelectorAll('.subway-station.is-name-visible')).map(node=>node.getAttribute('data-station')).join('|'))==='总备处站|新市场站','route hover reveals only its contacting stations');
    await page.locator('.subway-route[data-route="4"]').press('Enter');
    check(await page.evaluate(()=>SubwaySelectPanel.debugState().selected.type==='route'&&SubwaySelectPanel.debugState().selected.id==='4'),'click selects the route');
    check(await page.locator('#subway-feature-title').textContent()==='线路 4'&&await page.locator('#subway-feature-text').textContent()==='该线路介绍待补充。','route selection reads the JSON description slot');
    await page.mouse.move(0,0);
    check(await page.evaluate(()=>document.querySelectorAll('.subway-station.is-name-visible').length===2),'selected route keeps contacting station names visible');
    await page.screenshot({path:path.join(OUT,'subway-selected-'+viewport.width+'x'+viewport.height+'.png')});
    await page.locator('.subway-station[data-station="环线东北站"]').click();
    check(await page.evaluate(()=>SubwaySelectPanel.debugState().selected.type==='station'&&SubwaySelectPanel.debugState().selected.id==='环线东北站'),'clicking a station replaces route selection');
    check(await page.locator('#subway-feature-title').textContent()==='环线东北站'&&await page.locator('#subway-feature-text').textContent()==='该站点介绍待补充。','station selection reads the JSON description slot');
    check(await page.evaluate(()=>document.querySelector('.subway-station.is-name-visible').getAttribute('data-station'))==='环线东北站','selected station shows only its own name');
    await page.locator('.subway-route[data-route="8"]').focus();
    check(await page.evaluate(()=>document.querySelectorAll('.subway-station.is-name-visible').length===4),'route focus reveals every station touching that route');
    const card=page.locator('#subway-entries .stage-door-entry').first();
    check(await card.evaluate(node=>node.tagName==='ARTICLE'&&node.getAttribute('role')==='listitem'),'destination card is information content, not a button');
    check(await page.locator('#subway-confirm').count()===0,'direct entry has no secondary confirmation surface');
    await card.locator('.stage-door-entry-name').click();
    check(await page.evaluate(()=>SubwaySelectPanel.debugState().phase==='editing'&&__sent.filter(message=>message.cmd==='enter').length===0),'clicking card content does not enter');
    const enter=card.locator('.subway-entry-enter');
    const geometry=await enter.evaluate(node=>{const button=node.getBoundingClientRect(),card=node.closest('.stage-door-entry').getBoundingClientRect(),
        scale=document.querySelector('.subway-panel').getBoundingClientRect().width/1024;
        return {rightAligned:button.left>card.left+card.width/2,bottomAligned:Math.abs(card.bottom-button.bottom-13*scale)<2*scale}});
    check(geometry.rightAligned&&geometry.bottomAligned,'entry button sits at the bottom-right of its card '+JSON.stringify(geometry));
    await enter.focus();await page.keyboard.press('Enter');
    await page.waitForFunction(()=>SubwaySelectPanel.debugState().phase==='closed');
    check(await page.evaluate(()=>__sent.filter(message=>message.cmd==='enter').length===1),'entry button uses the existing command once without confirmation');
    await page.evaluate(()=>{__frames=[4,3,2,3];__open()});
    await page.waitForFunction(()=>SubwaySelectPanel.debugState().phase==='editing');
    await page.waitForFunction(()=>document.querySelector('.subway-station[data-station="新市场站"] img').complete);
    check(await page.locator('.subway-station[data-station="新市场站"]').getAttribute('data-frame')==='3','snapshot refresh selects the unlocked station frame');
    check((await page.locator('.subway-station[data-station="新市场站"] img').getAttribute('src'))==='assets/subway/station-3.svg','unlocked frame swaps the original SVG');
    const unlockedRoutes=await page.evaluate(()=>Array.from(document.querySelectorAll('.subway-route[data-unlocked="true"]'))
        .map(route=>route.getAttribute('data-route')).sort((a,b)=>Number(a)-Number(b)));
    check(JSON.stringify(unlockedRoutes)===JSON.stringify(['2','4','6','7','8','17']),'all associated routes regain authored colors after required stations unlock');
    await page.screenshot({path:path.join(OUT,'subway-unlocked-'+viewport.width+'x'+viewport.height+'.png')});
    check(errors.length===0,'no browser exceptions: '+errors.join(';'));
    await page.close();
}
async function main(){
    const {chromium}=require('../launcher/perf/node_modules/playwright');
    const server=http.createServer(serve);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const executablePath=[process.env.CF7_BROWSER_EXE,'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe','C:/Program Files/Microsoft/Edge/Application/msedge.exe'].find(candidate=>candidate&&fs.existsSync(candidate));
    const browser=await chromium.launch({executablePath,headless:true});
    try{
        for(const viewport of [{width:1024,height:576},{width:1366,height:768},{width:1024,height:768},{width:2560,height:1080}])await runViewport(browser,'http://127.0.0.1:'+server.address().port,viewport);
        const result={ok:true,passed,viewports:4};fs.writeFileSync(path.join(OUT,'result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
    }finally{await browser.close();await new Promise(resolve=>server.close(resolve))}
}
main().catch(error=>{console.error(error.stack);process.exitCode=1});
