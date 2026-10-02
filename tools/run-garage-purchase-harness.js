#!/usr/bin/env node
'use strict';
const fs = require('fs'), path = require('path'), http = require('http'), assert = require('assert');
const ROOT = path.resolve(__dirname, '..'), OUT = path.join(ROOT, 'tmp/u13/web');
const Runtime = require('../launcher/web/modules/garage-purchase-runtime.js');
fs.mkdirSync(OUT, {recursive:true});
let passed = 0;
function check(value, message) { assert(value, message); passed++; }
function staticChecks() {
    const xml = fs.readFileSync(path.join(ROOT,'data/infrastructure/infrastructure.xml'),'utf8');
    for (const [name, price] of [['自行车',8000],['摩托车',35000],['越野车',500000]]) {
        const block = xml.match(new RegExp('<Infrastructure>\\s*<Name>'+name+'</Name>[\\s\\S]*?</Infrastructure>'));
        check(block && Number(block[0].match(/<Price>(\d+)<\/Price>/)[1]) === price, 'fixture price agrees with real XML: '+name);
    }
    const garage = fs.readFileSync(path.join(ROOT,'flashswf/levels/基地场景合集/LIBRARY/地图/车库.xml'),'utf8');
    check(!garage.includes('确认通用面板') && !garage.includes('_root.金钱 -='), 'garage delegates all purchase writes');
    for (const id of ['bicycle','motorcycle','offroad']) check(garage.includes('打开车库购车("'+id+'")'), 'real scene entry: '+id);
    const main = fs.readFileSync(path.join(ROOT,'CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml'),'utf8');
    check(!/<DOMSymbolInstance[^>]*name="确认通用面板"/.test(main), 'retired confirmation has no main placement');
    const value = {v:1,token:'garage.test',phase:'editing',vehicleId:'bicycle',draft:{vehicleId:'bicycle'},name:'自行车',description:'说明\n权益',
        cost:8000,balance:10000,requiredDrivingLevel:0,drivingLevel:0,owned:false,canPurchase:true,success:true,changed:false,saved:false};
    check(Runtime.normalizeState(value), 'valid read state');
    for (const patch of [{cost:0},{balance:-1},{vehicleId:'tank'},{canPurchase:false},{phase:'applied',owned:true,changed:true,saved:false}])
        check(!Runtime.normalizeState(Object.assign({},value,patch)), 'invalid state refused');
}
function serve(req,res) {
    const file = path.resolve(ROOT,'.'+decodeURIComponent((req.url || '/').split('?')[0]));
    if (!file.startsWith(ROOT+path.sep)) { res.writeHead(403); res.end(); return; }
    fs.readFile(file,(error,bytes)=> {
        if(error){res.writeHead(404);res.end();return;}
        const type={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp','.woff2':'font/woff2'}[path.extname(file)]||'application/octet-stream';
        res.setHeader('Content-Type',type+'; charset=utf-8');res.end(bytes);
    });
}
async function runViewport(browser,address,viewport) {
    const page=await browser.newPage({viewport});const errors=[];
    page.on('pageerror',error=>errors.push(String(error)));
    await page.goto(address+'/launcher/web/modules/garage-purchase/dev/harness.html');
    const phase=()=>page.evaluate(()=>GaragePurchasePanel.debugState().phase);
    const wait=value=>page.waitForFunction(v=>GaragePurchasePanel.debugState().phase===v,value,{timeout:10000});
    await wait('editing');
    await page.waitForFunction(()=>{const image=document.getElementById('garage-image');return image.complete&&image.naturalWidth>0&&!image.hidden});
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    const fit=await page.evaluate(()=> {
        const panel=document.querySelector('.garage-panel').getBoundingClientRect(),button=document.getElementById('garage-confirm').getBoundingClientRect();
        const width=Math.min(innerWidth,innerHeight*16/9),height=Math.min(innerHeight,innerWidth*9/16);
        return Math.abs(panel.width-width)<=1&&Math.abs(panel.height-height)<=1
            &&Math.abs(panel.left-(innerWidth-width)/2)<=1&&Math.abs(panel.top-(innerHeight-height)/2)<=1
            &&document.elementFromPoint(button.x+button.width/2,button.y+button.height/2)===document.getElementById('garage-confirm')
            &&document.documentElement.scrollWidth<=innerWidth
            &&getComputedStyle(document.getElementById('panel-backdrop')).backgroundColor!=='rgba(0, 0, 0, 0)';
    });
    const layout=await page.evaluate(()=>{const panel=document.querySelector('.garage-panel').getBoundingClientRect(),button=document.getElementById('garage-confirm').getBoundingClientRect();return {panel:panel.toJSON(),viewport:[innerWidth,innerHeight],scrollWidth:document.documentElement.scrollWidth,hit:document.elementFromPoint(button.x+button.width/2,button.y+button.height/2)?.id}});
    check(fit,'real DOM fits and CTA is hittable '+viewport.width+' '+JSON.stringify(layout));
    check(await page.evaluate(()=>__charges===0),'opening is free');
    await page.screenshot({path:path.join(OUT,'garage-'+viewport.width+'x'+viewport.height+'.png')});
    await page.locator('#garage-cancel').click();
    check(await phase()==='closed'&&await page.evaluate(()=>__charges===0),'cancel is free');
    for(const id of ['bicycle','motorcycle','offroad']) {
        await page.evaluate(id=>{__reset();__open(id)},id);await wait('editing');
        await page.waitForFunction(id=>{const image=document.getElementById('garage-image');return image.complete&&image.naturalWidth>0&&!image.hidden&&image.src.endsWith(id+'.webp')},id);
        const presentation=await page.evaluate(id=> {
            const card=document.querySelector('.garage-card'),description=document.getElementById('garage-description');
            const expected=__catalog[id].description.split(/\r?\n/).filter(Boolean).map(line=>line.replace('：',''));
            const actual=Array.from(description.children).map(row=>row.textContent);
            return JSON.stringify(expected)===JSON.stringify(actual)&&card.scrollHeight<=card.clientHeight+1
                &&document.getElementById('garage-image').alt===__catalog[id].name+'外观';
        },id);
        check(presentation,'real XML benefits and vehicle image fit without scrolling '+id+' '+viewport.width);
        await page.screenshot({path:path.join(OUT,'garage-'+id+'-'+viewport.width+'x'+viewport.height+'.png')});
        await page.locator('#garage-confirm').click();await wait('applied');
        check(await page.evaluate(()=>__charges===1&&__saves===1),'single purchase '+id);
        const commits=await page.evaluate(()=>__sent.filter(m=>m.domain==='garage'&&m.cmd==='commit').length);
        await page.locator('#garage-confirm').click();
        check(await phase()==='closed'&&await page.evaluate(()=>__sent.filter(m=>m.domain==='garage'&&m.cmd==='commit').length)===commits,'saved close does not buy again '+id);
    }
    await page.evaluate(()=>{__reset();__balance=7999;__open('bicycle')});await wait('editing');
    check(await page.locator('#garage-confirm').isDisabled(),'insufficient gold disables purchase');
    await page.locator('#garage-cancel').click();
    await page.evaluate(()=>{__reset();__driving=1;__open('offroad')});await wait('editing');
    check(await page.locator('#garage-confirm').isDisabled(),'insufficient driving disables purchase');
    await page.locator('#garage-cancel').click();
    await page.evaluate(()=>{__reset();__open('offroad');__fault='save_failure'});await wait('editing');
    // snapshot consumes the next transport fault, so arm the save fault after reading.
    await page.evaluate(()=>{__fault='save_failure'});await page.locator('#garage-confirm').click();await wait('save_pending');
    check(await page.locator('#garage-confirm').textContent()==='重试保存','pending persistence offers save retry');
    await page.locator('#garage-confirm').click();await wait('applied');
    check(await page.evaluate(()=>__charges===1&&__saves===2&&__balance===100000),'save retry preserves one charge');
    await page.locator('#garage-confirm').click();
    await page.evaluate(()=>{__reset();__open()});await wait('editing');
    await page.evaluate(()=>{__fault='unknown_applied'});await page.locator('#garage-confirm').click();await wait('unknown');
    await page.locator('#garage-confirm').click();await wait('applied');
    check(await page.evaluate(()=>__charges===1&&__queries===1),'uncertain result only queries existing purchase');
    await page.locator('#garage-confirm').click();
    await page.evaluate(()=>{__reset();__open()});await wait('editing');
    await page.evaluate(()=>{__closeFails=true});await page.locator('#garage-close').click();
    check(await phase()==='editing','failed close preserves panel');
    await page.evaluate(()=>{__closeFails=false});await page.locator('#garage-close').click();
    check(await page.evaluate(()=>PanelRuntime.sharedResponseRouter.debugState().handlerCount===0),'close releases shared response subscription');
    await page.route('**/assets/garage-vehicles/motorcycle.webp',route=>route.abort());
    await page.evaluate(()=>{__reset();__open('motorcycle')});await wait('editing');
    await page.waitForFunction(()=>document.getElementById('garage-image-placeholder').textContent==='车辆预览暂时不可用');
    check(await page.locator('#garage-image').isHidden()&&await page.locator('#garage-confirm').isEnabled(),'missing image leaves purchase usable');
    await page.locator('#garage-cancel').click();
    await page.evaluate(()=>{__reset();__catalog.bicycle.description=('地图出行：'+('较长的中文权益说明与剧情条件。'.repeat(35))+'\n').repeat(4);__open('bicycle')});await wait('editing');
    check(await page.evaluate(()=>{const card=document.querySelector('.garage-card');card.scrollTop=card.scrollHeight;const button=document.getElementById('garage-confirm').getBoundingClientRect();return card.scrollHeight>card.clientHeight&&document.elementFromPoint(button.x+button.width/2,button.y+button.height/2)===document.getElementById('garage-confirm')}),'long Chinese copy scrolls locally and keeps purchase hittable');
    await page.locator('#garage-cancel').click();
    check(errors.length===0,'no browser exceptions: '+errors.join(';'));
    await page.close();
}
async function main() {
    staticChecks();
    if(process.argv.includes('--static-only')){console.log(JSON.stringify({ok:true,passed,browser:false}));return;}
    const {chromium}=require('../launcher/perf/node_modules/playwright');
    const server=http.createServer(serve);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const executablePath=[process.env.CF7_BROWSER_EXE,'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe','C:/Program Files/Microsoft/Edge/Application/msedge.exe'].find(p=>p&&fs.existsSync(p));
    const browser=await chromium.launch({executablePath,headless:true});
    try {
        for(const viewport of [{width:1024,height:576},{width:1366,height:768},{width:1920,height:1080},{width:1024,height:768},{width:2560,height:1080}]) await runViewport(browser,'http://127.0.0.1:'+server.address().port,viewport);
        const result={ok:true,passed,viewports:5};fs.writeFileSync(path.join(OUT,'result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
    } finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
}
main().catch(error=>{console.error(error.stack);process.exitCode=1});
