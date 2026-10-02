#!/usr/bin/env node
'use strict';
const assert=require('assert/strict'),fs=require('fs'),path=require('path'),http=require('http');
const root=path.resolve(__dirname,'..'),web=path.join(root,'launcher/web');
const registry={};require('vm').runInNewContext(fs.readFileSync(path.join(web,'modules/panels-lazy-registry.js'),'utf8'),{
    Panels:{registerLazy:(id,deps)=>registry[id]=deps},LazyLoader:{},console:console});
const authoredJourneys=require(path.join(web,'generated/tutorial-journeys.js'));
assert.deepEqual(require('./lib/workbench-ui-ratchet.js').scanCss(fs.readFileSync(path.join(web,'css/guidance.css'),'utf8'),'launcher/web/css/guidance.css').findings,[]);
function fixtureSnapshot(request){
    const capacity=request.containerId==='背包'?50:240,offset=request.offset,limit=Math.min(request.limit,capacity-offset);
    return {containerId:request.containerId,capacity:capacity,accessibleCapacity:capacity,viewCapacity:capacity,
        filterKey:request.filterKey||'all',pageSizeHint:50,locked:false,snapshotSeq:1,containerEpoch:1,containerVersion:1,
        offset:offset,limit:limit,slots:Array.from({length:limit},(_,i)=>({physicalSlot:offset+i,occupied:false,slotLease:'lease.1.'+i})),
        filterFacets:[],filterItemCount:0,setFacets:[],setFilterItemCount:0};
}
const workbenchHtml='<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="/css/panels.css"><link rel="stylesheet" href="/css/guidance.css"><style>body{background:var(--launcher-bg-1)}#workbench-host{position:relative;width:1024px;height:576px}</style><div id="workbench-host"></div>'
    +'<script>window.fixtureSnapshot='+fixtureSnapshot.toString()+';window.outbox=[];window.Bridge={send:function(m){outbox.push(m);setTimeout(function(){var requests=m.payload&&m.payload.requests;PanelRuntime.sharedResponseRouter.handleResponse({type:"panel_resp",domain:"inventory",panel:m.panel,panelInstanceId:m.panelInstanceId,callId:m.callId,cmd:m.cmd,success:!!requests,snapshots:requests?requests.map(fixtureSnapshot):[],error:requests?null:"disconnected"});},0);return true;}};window.Panels={register:function(id,handler){if(id==="workbench")window.workbenchHandler=handler;},getActive:function(){return "workbench";},isOpen:function(){return true;},requestClose:function(){}};</script>'
    +registry.workbench.map(n=>'<script src="/'+n+'"></script>').join('')
    +'<script>window.workbenchEl=workbenchHandler.create();document.querySelector("#workbench-host").appendChild(workbenchEl);window.accepted=workbenchHandler.onOpen(workbenchEl,{profile:"battlebox",view:"storage",panelInstanceId:"fixture-guidance"});</script>';
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
const html='<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="/css/panels.css"><link rel="stylesheet" href="/css/guidance.css"><style>body{background:#101b27}#host{width:950px;margin:20px;color:white}</style><button id="outside" data-tutorial-target="foreign">Outside</button><div id="host"></div>'
    +registry.help.filter(n=>n!=='modules/help-panel.js').map(n=>'<script src="/'+n+'"></script>').join('')
    +'<script>window.outbox=[];window.Bridge={send:m=>outbox.push(m),task:m=>outbox.push(m)};window.view=GuidanceTutorials.mount(document.querySelector("#host"),{domain:"workbench",stepMs:0});</script>';
const edge=[path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),path.join(process.env.ProgramFiles,'Microsoft/Edge/Application/msedge.exe')].find(fs.existsSync);
const server=http.createServer((req,res)=>{if(req.url==='/fixture'||req.url==='/workbench-fixture'){res.setHeader('Content-Type','text/html;charset=utf-8');res.end(req.url==='/fixture'?html:workbenchHtml);return;}const p=path.resolve(web,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!p.startsWith(web+path.sep)){res.writeHead(403);res.end();return;}fs.readFile(p,(e,b)=>{res.writeHead(e?404:200,{'Content-Type':p.endsWith('.js')?'application/javascript':p.endsWith('.css')?'text/css':'text/plain'});res.end(e?'missing':b);});});
(async()=>{
    await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({executablePath:edge,headless:true});let checks=0;
    try {
        for(const [width,height] of [[1024,576],[1600,900],[2560,1440]]){
            const page=await browser.newPage({viewport:{width,height}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
            await page.goto('http://127.0.0.1:'+server.address().port+'/fixture');await page.waitForSelector('.guidance-demo-grid');
            for(const journey of authoredJourneys.journeys){
                await page.evaluate(domain=>{view.destroy();window.view=GuidanceTutorials.mount(document.querySelector('#host'),{domain:domain,stepMs:0});},journey.domain);
                await page.getByRole('button',{name:journey.title,exact:true}).click();
                const result=await page.evaluate(async id=>{const j=TutorialJourneys.journeys.find(j=>j.id===id);return {ok:await view.play(j),actual:view.snapshot(),expected:j.steps[j.steps.length-1].expected};},journey.id);
                assert.equal(result.ok,true);assert.deepEqual(result.actual,result.expected);checks++;
            }
            await page.evaluate(()=>{view.destroy();window.view=GuidanceTutorials.mount(document.querySelector('#host'),{domain:'workbench',stepMs:0});});
            await page.getByRole('button',{name:'选择多件再一起存入',exact:true}).click();
            await page.evaluate(()=>view.record());
            await page.locator('[data-tutorial-target="deposit"]').click();await page.locator('[data-tutorial-target="backpack-0"]').click();
            await page.locator('[data-tutorial-target="backpack-1"]').click();await page.locator('[data-tutorial-target="commit"]').click();
            const replay=await page.evaluate(async()=>{const record=view.finishRecording();return {n:record.steps.length,ok:await view.play(record),actual:view.snapshot(),expected:record.steps[record.steps.length-1].expected};});
            assert.equal(replay.n,4);assert.equal(replay.ok,true);assert.deepEqual(replay.actual,replay.expected);checks++;
            assert.equal(await page.evaluate(async()=>{const j=JSON.parse(JSON.stringify(TutorialJourneys.journeys[0]));j.steps[0].target='foreign';return view.play(j);}),false);checks++;
            assert.equal(await page.evaluate(async()=>{const j=JSON.parse(JSON.stringify(TutorialJourneys.journeys[0]));j.steps[0].expected.backpack=[999];return view.play(j);}),false);checks++;
            const canceled=await page.evaluate(async()=>{const run=view.play(TutorialJourneys.journeys[1]);view.destroy();await run;return !document.querySelector('.guidance-tutorials');});assert.equal(canceled,true);checks++;
            await page.evaluate(()=>{window.view=GuidanceTutorials.mount(document.querySelector('#host'),{domain:'workbench'});});
            const generic=await page.evaluate(async()=>{
                view.destroy();GuidanceTutorials.registerDomain('fixture-domain',host=>GuidanceInventoryDemo.create(host));
                var journey=JSON.parse(JSON.stringify(TutorialJourneys.journeys[0]));journey.domain='fixture-domain';
                window.view=GuidanceTutorials.mount(document.querySelector('#host'),{domain:'fixture-domain',journeys:{journeys:[journey]},stepMs:0});
                view.record();document.querySelector('[data-tutorial-target="backpack-0"]').dispatchEvent(new MouseEvent('click',{ctrlKey:true,bubbles:true}));
                var recorded=view.finishRecording();return {domain:recorded.domain,ok:await view.play(recorded)};
            });assert.deepEqual(generic,{domain:'fixture-domain',ok:true});checks++;
            await page.evaluate(()=>view.reset());
            await page.locator('[data-tutorial-target="deposit"]').focus();await page.keyboard.press('Enter');
            await page.locator('[data-tutorial-target="backpack-0"]').focus();await page.keyboard.press('Enter');
            assert.equal(await page.evaluate(()=>view.snapshot().pending),1);
            assert.equal(await page.evaluate(()=>document.activeElement.dataset.tutorialTarget),'backpack-0');checks++;
            await page.evaluate(()=>{view.destroy();document.querySelector('#outside').focus();window.secondary=GuidanceTutorials.openSecondary(document.querySelector('#host'),null,{domain:'workbench',title:'物品帮助'});});
            assert.equal(await page.evaluate(()=>secondary.root.contains(document.activeElement)),true);checks++;
            await page.keyboard.press('Tab');assert.equal(await page.evaluate(()=>secondary.root.contains(document.activeElement)),true);
            await page.keyboard.press('Escape');assert.equal(await page.evaluate(()=>secondary.isActive()),false);
            await page.locator('.guidance-secondary').waitFor({state:'hidden'});
            assert.equal(await page.locator('.guidance-secondary').isVisible(),false);
            assert.equal(await page.evaluate(()=>document.activeElement.id),'outside');checks++;
            await page.evaluate(()=>{window.secondary=GuidanceTutorials.openSecondary(document.querySelector('#host'),secondary,{domain:'workbench'});});
            assert.equal(await page.locator('.guidance-secondary .guidance-tutorials').count(),1);
            const consumed=await page.evaluate(()=>{var result=[];var ok=GuidanceTutorials.consumeEscape(secondary,'escape',function(){result=Array.from(arguments);});return {ok:ok,result:result};});
            assert.deepEqual(consumed,{ok:true,result:[false,'consumed']});checks++;
            await page.evaluate(()=>{secondary=GuidanceTutorials.disposeSecondary(secondary);});
            assert.equal(await page.locator('.guidance-secondary').count(),0);checks++;
            await page.evaluate(()=>{window.view=GuidanceTutorials.mount(document.querySelector('#host'),{domain:'workbench'});});
            assert.deepEqual(await page.evaluate(()=>outbox),[]);assert.deepEqual(errors,[]);checks++;
            if(width===1024){await page.screenshot({path:path.join(root,'tmp/u8-guidance/inventory-tutorial.png')});}
            await page.close();
        }
        const panel=await browser.newPage({viewport:{width:1024,height:576}}),panelErrors=[];panel.on('pageerror',e=>panelErrors.push(e.message));
        await panel.goto('http://127.0.0.1:'+server.address().port+'/workbench-fixture');
        assert.deepEqual(panelErrors,[]);assert.equal(await panel.evaluate(()=>accepted),true);
        await panel.waitForFunction(()=>InventoryStorageWorkbench.debugState().coordinator.ready);checks++;
        const before=await panel.evaluate(()=>outbox.length);
        await panel.locator('[data-workbench-help]').click();await panel.waitForSelector('.guidance-secondary .guidance-tutorials');checks++;
        await panel.getByRole('button',{name:'播放演示',exact:true}).click();await panel.getByText('演示完成，可以重播或亲自练习。',{exact:true}).waitFor();checks++;
        await panel.keyboard.press('PageDown');await panel.keyboard.press('Control+End');
        assert.equal(await panel.evaluate(()=>outbox.length),before);checks++;
        await panel.keyboard.press('Escape');await panel.locator('.guidance-secondary').waitFor({state:'hidden'});assert.equal(await panel.locator('.guidance-secondary').isVisible(),false);
        assert.equal(await panel.evaluate(()=>document.activeElement.hasAttribute('data-workbench-help')),true);checks++;
        await panel.locator('[data-workbench-help]').click();
        assert.equal(await panel.evaluate(()=>InventoryStorageWorkbench.consumeEscape()),true);
        await panel.locator('.guidance-secondary').waitFor({state:'hidden'});
        assert.equal(await panel.locator('.guidance-secondary').isVisible(),false);checks++;
        await panel.locator('[data-workbench-help]').click();
        await panel.screenshot({path:path.join(root,'tmp/u8-guidance/workbench-help.png'),animations:'disabled'});
        await panel.evaluate(()=>workbenchHandler.onClose());assert.equal(await panel.locator('.guidance-secondary').count(),0);checks++;
        assert.equal(await panel.evaluate(()=>outbox.length),before);assert.deepEqual(panelErrors,[]);checks++;
        await panel.close();
        console.log('Guidance tutorial browser gate: '+checks+' checks passed; production workbench/help, fixture transport, no game E2E');
    } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>server.close());
