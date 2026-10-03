#!/usr/bin/env node
'use strict';
// Production panel and mux, simulated Host/AS2 receipts; never reads or writes saves.
const fs = require('fs'), path = require('path'), http = require('http'), assert = require('assert');
const ROOT = path.resolve(__dirname, '..');
const {chromium} = require(path.join(ROOT, 'launcher/perf/node_modules/playwright'));
const out = path.resolve((process.argv.find(a => a.startsWith('--shot-dir=')) || '--shot-dir=tmp/bookshelf-flow-ui').slice(11));
fs.mkdirSync(out, {recursive:true});
function fixture() {
    const handlers = {}, scenario = new URLSearchParams(location.search).get('scenario');
    const qa = window.__bookQa = {sent:[],pending:scenario !== 'return',reads:0,writes:0,queries:0};
    window.Toast = {add:function(){}};
    window.Bridge = {on:(t,f)=>(handlers[t]||(handlers[t]=[])).push(f),
        off:(t,f)=>{handlers[t]=(handlers[t]||[]).filter(x=>x!==f);}, send:m=>{
            qa.sent.push(m); if(m.cmd==='close')return true;
            const base={type:'panel_resp',panel:'bookshelf',domain:'bookshelf',cmd:m.cmd,callId:m.callId,
                panelInstanceId:m.panelInstanceId,v:1,token:m.payload.token,phase:'editing',success:true,
                activeSlot:scenario==='return'?'bookrun_fixture':'fixture_a',role:scenario==='return'?'Andy Law':'测试角色',
                inRun:scenario==='return',originSlot:'fixture_a',exitRequired:scenario==='return',
                canSwitch:true,unlocked:true,pendingRun:qa.pending?'bookrun_fixture':'',lastReward:qa.pending?0:75,
                slots:[{slot:'fixture_a',name:'测试角色'}]};
            if(m.cmd==='snapshot') {
                qa.reads++;
                if(scenario==='readfail' && qa.reads===2) Object.assign(base,{success:false,error:'disconnected',phase:undefined});
            } else if(m.cmd==='commit') {
                qa.writes++;
                if(m.payload.kind==='play') Object.assign(base,{phase:'switching'});
                else if(scenario==='return') {
                    if(qa.writes===1) Object.assign(base,{phase:undefined,success:false,error:'save_unavailable'});
                    else Object.assign(base,{phase:'switching'});
                } else Object.assign(base,{phase:'save_pending',success:false,requiresReconcile:true,recoveryToken:m.payload.token});
            } else if(m.cmd==='query') {
                qa.queries++;
                if(scenario==='unknown' && qa.queries===1) Object.assign(base,{phase:'save_pending',success:false,requiresReconcile:true});
                else {qa.pending=false;Object.assign(base,{phase:'applied',pendingRun:'',nextToken:'bookshelf.fixture.next',lastReward:75});}
            } else throw new Error('unexpected '+m.cmd);
            setTimeout(()=>(handlers.panel_resp||[]).forEach(f=>f(base)),8);
            return true;
        }};
}
const server = http.createServer((req,res)=>{
    const url=new URL(req.url,'http://localhost');
    const file=path.resolve(ROOT,'.'+decodeURIComponent(url.pathname));
    if(path.relative(ROOT,file).startsWith('..')){res.writeHead(403);res.end();return;}
    fs.readFile(file,(err,data)=>{
        if(err){res.writeHead(404);res.end();return;}
        if(url.pathname.endsWith('/bookshelf/dev/harness.html')) data=Buffer.from(data.toString('utf8').replace(/<script>[\s\S]*?<\/script>/,'<script>('+fixture.toString()+')();</script>'));
        const type={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml'}[path.extname(file)];
        res.setHeader('Content-Type',(type||'application/octet-stream')+'; charset=utf-8');res.end(data);
    });
});
async function main(){
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const edge=[process.env['ProgramFiles(x86)'],process.env.ProgramFiles].filter(Boolean)
        .map(p=>path.join(p,'Microsoft/Edge/Application/msedge.exe')).find(fs.existsSync);
    const browser=await chromium.launch({headless:true,executablePath:edge}),report=[];
    try {
        for(const [width,height] of [[1024,576],[1366,768],[1920,1080]]) for(const scenario of ['settle','unknown','readfail','return']) {
            const page=await browser.newPage({viewport:{width,height},reducedMotion:'reduce'}),errors=[];
            page.on('pageerror',e=>errors.push(e.message));
            await page.goto('http://127.0.0.1:'+server.address().port+'/launcher/web/modules/bookshelf/dev/harness.html?scenario='+scenario);
            const primary=page.locator('.bookshelf-primary'), recover=page.locator('#bookshelf-recover');
            if(scenario==='return') {
                await page.waitForFunction(()=>__bookQa.writes===1 && !document.querySelector('.bookshelf-primary').disabled);
                assert.strictEqual(await primary.textContent(),'结束旅程，返回原角色');
                assert(await page.locator('#bookshelf-close').isDisabled());
                await page.locator('#bookshelf-close').evaluate(b=>b.click()); await page.keyboard.press('Escape');
                assert.strictEqual(await page.evaluate(()=>__bookQa.sent.filter(m=>m.cmd==='close').length),0);
                assert(await primary.isVisible());
                await primary.click();
                await page.waitForFunction(()=>__bookQa.sent.some(m=>m.cmd==='close'));
                assert.strictEqual(await page.evaluate(()=>__bookQa.writes),2);
                assert.deepStrictEqual(await page.evaluate(()=>__bookQa.sent.filter(m=>m.cmd==='commit').map(m=>m.payload.kind)),['return','return']);
            } else {
                await primary.waitFor(); assert.strictEqual(await primary.textContent(),'核对上次旅程');
                await primary.click(); await recover.waitFor(); await recover.click();
                if(scenario==='unknown') {
                    await page.waitForFunction(()=>__bookQa.queries===1 && !document.querySelector('#bookshelf-recover').disabled);
                    assert(await primary.isDisabled()); assert.strictEqual(await page.evaluate(()=>__bookQa.writes),1);
                    await recover.click();
                }
                if(scenario==='readfail') {
                    await page.waitForFunction(()=>document.querySelector('#bookshelf-status').textContent.includes('连接'));
                    assert(await primary.isDisabled()); assert.strictEqual(await recover.textContent(),'重新读取');
                    await recover.click();
                }
                await page.waitForFunction(()=>document.querySelector('.bookshelf-primary').textContent==='进入书中'&&!document.querySelector('.bookshelf-primary').disabled);
                const messages=await page.evaluate(()=>__bookQa.sent);
                assert.strictEqual(messages.filter(m=>m.cmd==='close').length,0);
                assert(messages.filter(m=>m.cmd==='query').every(m=>m.payload.token==='bookshelf.preview.1'));
                assert(messages.some(m=>m.cmd==='snapshot'&&m.payload.token==='bookshelf.fixture.next'));
                const geometry=await page.evaluate(()=>{const n=document.querySelector('.bookshelf-panel'),b=n.getBoundingClientRect();
                    return b.left>=-1&&b.top>=-1&&b.right<=innerWidth+1&&b.bottom<=innerHeight+1&&n.scrollWidth<=n.clientWidth+1;});
                assert(geometry);
                if(scenario==='settle')await page.screenshot({path:path.join(out,width+'x'+height+'.png')});
                await primary.click();
                await page.waitForFunction(()=>__bookQa.sent.some(m=>m.cmd==='close'));
                assert.deepStrictEqual(await page.evaluate(()=>__bookQa.sent.filter(m=>m.cmd==='commit').map(m=>[m.payload.kind,m.payload.token])),
                    [['settle','bookshelf.preview.1'],['play','bookshelf.fixture.next']]);
            }
            assert.deepStrictEqual(errors,[]);report.push({width,height,scenario,passed:true});await page.close();
        }
        fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n');
        console.log('Bookshelf flow browser harness: 12 scenarios passed at 3 viewports.');
    } finally {await browser.close();}
}
main().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>server.close());
