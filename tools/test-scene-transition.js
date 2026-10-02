#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path'),http=require('http'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..'),web=path.join(root,'launcher/web');
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
const edge=[path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),path.join(process.env.ProgramFiles,'Microsoft/Edge/Application/msedge.exe')].find(fs.existsSync);
const artifacts=path.resolve(root,process.env.CF7_U12_OUTPUT_DIRECTORY||'tmp/u12-scene-transition');fs.mkdirSync(artifacts,{recursive:true});
assert.deepEqual(require('./lib/workbench-ui-ratchet.js').scanCss(fs.readFileSync(path.join(web,'css/scene-transition.css'),'utf8'),'launcher/web/css/scene-transition.css').findings,[]);
const server=http.createServer((req,res)=>{
    const p=path.resolve(web,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));
    if(!p.startsWith(web+path.sep)){res.writeHead(403);res.end();return;}
    const mime={'.html':'text/html;charset=utf-8','.js':'application/javascript','.css':'text/css','.png':'image/png','.jpg':'image/jpeg','.woff2':'font/woff2'};
    fs.readFile(p,(e,b)=>{res.writeHead(e?404:200,{'Content-Type':mime[path.extname(p)]||'application/octet-stream'});res.end(e?'missing':b);});
});
const snapshot=(phase='cover',revision=1,extra={})=>({type:'scene_transition',version:1,requestId:'tr:1',revision,phase,
    imageId:'Andy',tip:'原版提示 <原样文本>\n第二行',targetScene:2,actionPending:false,connected:true,generation:0,revealAllowed:false,rewardReady:false,...extra});
(async()=>{
    await new Promise(r=>server.listen(0,'127.0.0.1',r));
    const browser=await chromium.launch({executablePath:edge,headless:true});let checks=0;
    try {
        for(const reduced of [false,true]){
            const page=await browser.newPage({viewport:{width:1024,height:576},reducedMotion:reduced?'reduce':'no-preference'});
            let releaseImage;const imageGate=new Promise(resolve=>{releaseImage=resolve;});
            await page.route('**/assets/bg/remake-andy.png',async route=>{await imageGate;await route.continue();});
            await page.addInitScript(()=>{window.outbox=[];window.hostListeners=[];window.chrome={webview:{
                postMessage:m=>outbox.push(m),addEventListener:(type,cb)=>{if(type==='message')hostListeners.push(cb);}}};
                window.host=p=>hostListeners.forEach(cb=>cb({data:p}));});
            await page.goto('http://127.0.0.1:'+server.address().port+'/scene-transition.html');
            assert.deepEqual(await page.evaluate(()=>outbox.filter(m=>m.type==='scene_transition_ready')),[{type:'scene_transition_ready'}]);checks++;
            const post=p=>page.evaluate(p=>host(p),p);
            await post(snapshot());
            assert.equal(await page.locator('#transition').evaluate(el=>getComputedStyle(el).opacity),'1');checks++;
            await post(snapshot('cover',2));
            const waiting=await page.evaluate(async()=>{
                const opacity=[];for(let i=0;i<3;i++){await new Promise(requestAnimationFrame);opacity.push(getComputedStyle(document.getElementById('transition')).opacity);}
                return {opacity,receipts:outbox.filter(m=>m.kind==='covered').length};
            });
            assert.deepEqual(waiting,{opacity:['1','1','1'],receipts:0});checks++;
            releaseImage();await page.waitForFunction(()=>outbox.some(m=>m.kind==='covered'&&m.revision===2));checks++;
            assert.equal(await page.locator('#transition-tip').textContent(),'原版提示 <原样文本>\n第二行');checks++;
            const style=await page.locator('#transition-image').evaluate(el=>({filter:getComputedStyle(el).filter,opacity:getComputedStyle(el).opacity,width:el.getBoundingClientRect().width}));
            assert.deepEqual(style,{filter:'none',opacity:'1',width:1024});checks++;
            await post(snapshot('loading',3));await page.waitForTimeout(600);
            assert.equal(await page.locator('#transition').isVisible(),true);checks++;
            await post(snapshot('reveal',4));await page.waitForTimeout(300);
            assert.equal(await page.locator('#transition').isVisible(),true);assert.equal(await page.evaluate(()=>outbox.some(m=>m.kind==='revealed')),false);checks++;
            await post(snapshot('reveal',4,{revealAllowed:true}));await page.waitForFunction(()=>outbox.some(m=>m.kind==='revealed'));checks++;
            assert.equal(await page.locator('#transition').isVisible(),false);
            await post(snapshot('reveal',4,{revealAllowed:true}));assert.equal(await page.locator('#transition').isVisible(),false);checks++;
            await post(snapshot('error',1,{requestId:'tr:2'}));await page.locator('#transition-actions').waitFor({state:'visible'});
            await page.waitForTimeout(250);await page.screenshot({path:path.join(artifacts,reduced?'error-reduced.png':'error.png')});
            await page.keyboard.press('Escape');assert.equal(await page.locator('#transition').isVisible(),true);checks++;
            await page.keyboard.press('Tab');assert.equal(await page.evaluate(()=>document.activeElement.dataset.transitionAction),'return');checks++;
            await page.locator('[data-transition-action=retry]').click();
            await page.locator('[data-transition-action=return]').dispatchEvent('click');
            assert.equal(await page.evaluate(()=>outbox.filter(m=>m.type==='scene_transition_action').length),1);checks++;
            await post(snapshot('error',2,{requestId:'tr:2',actionPending:true}));
            assert.equal(await page.locator('[data-transition-action=retry]').isDisabled(),true);checks++;
            // A replacement source cancels an in-flight reveal; the old continuation cannot hide it.
            await post(snapshot('reveal',1,{requestId:'tr:3',revealAllowed:true}));
            await post(snapshot('cover',1,{requestId:'tr:4',imageId:'Blue'}));
            assert.equal(await page.locator('#transition').evaluate(el=>getComputedStyle(el).opacity),'1');checks++;
            await page.waitForTimeout(500);
            assert.equal(await page.locator('#transition').isVisible(),true);
            assert.equal(await page.evaluate(()=>outbox.some(m=>m.requestId==='tr:3'&&m.kind==='revealed')),false);checks++;
            await post(snapshot('cover',2,{requestId:'tr:4',imageId:'Blue',connected:false,generation:1}));
            await page.waitForTimeout(250);assert.match(await page.locator('#transition-status').textContent(),/连接/);checks++;
            await page.setViewportSize({width:1536,height:864});await page.waitForTimeout(100);
            assert.equal(await page.locator('.transition-shell').evaluate(el=>el.getBoundingClientRect().width),1536);checks++;
            await post(snapshot('hide',3,{requestId:'tr:4',imageId:'Blue',generation:1}));assert.equal(await page.locator('#transition').isVisible(),false);checks++;
            await page.close();
        }
        // Decode failure keeps an opaque curtain and readable copy; no indefinite asset gate.
        const page=await browser.newPage();await page.route('**/assets/bg/remake-andy.png',r=>r.abort());
        await page.addInitScript(()=>{window.outbox=[];window.chrome={webview:{postMessage:m=>outbox.push(m),addEventListener:(type,cb)=>(window.hostHandlers||(window.hostHandlers=[])).push(cb)}};window.host=p=>hostHandlers.forEach(cb=>cb({data:p}));});
        await page.goto('http://127.0.0.1:'+server.address().port+'/scene-transition.html');
        await page.evaluate(p=>host(p),snapshot());await page.waitForFunction(()=>outbox.some(m=>m.kind==='covered'));
        assert.equal(await page.locator('#transition').isVisible(),true);checks++;
        await page.close();
        // The report paints before a deliberately blocked loading image. No panel/pause RPC exists here.
        for (const reduced of [false,true]) {
            const p=await browser.newPage({viewport:{width:1024,height:576},reducedMotion:reduced?'reduce':'no-preference'});
            let releaseImage;const gate=new Promise(resolve=>{releaseImage=resolve;});
            await p.route('**/assets/bg/remake-andy.png',async route=>{await gate;await route.continue();});
            await p.addInitScript(()=>{window.outbox=[];window.chrome={webview:{postMessage:m=>outbox.push(m),
                addEventListener:(type,cb)=>(window.hostHandlers||(window.hostHandlers=[])).push(cb)}};window.host=p=>hostHandlers.forEach(cb=>cb({data:p}));});
            await p.goto('http://127.0.0.1:'+server.address().port+'/scene-transition.html');
            const frozen={v:1,runId:'run:1',stageName:'联合大学 · 返回战报',difficulty:'简单',outcome:'victory',activeFrames:900,
                totalKills:24,omittedKillTypes:0,totalItemGains:3,totalItemLosses:0,omittedItemFlowTypes:0,rewardRollOmissions:0,
                rewardStashed:true,kills:Array.from({length:24},(_,i)=>({key:'enemy:'+i,displayName:'敌人 '+i,iconName:'',doll:null,eliteLevel:0,count:1})),
                itemFlows:[{direction:'gain',kind:'item',itemKey:'补给',displayName:'补给',iconName:'',tier:'',source:'stage_settlement',reason:'stage_reward_stashed',count:3}]};
            const report=(phase='cover',revision=1,extra={})=>snapshot(phase,revision,{version:2,report:frozen,reportVisible:true,
                reportHandoff:false,reportReady:false,...extra});
            const post=x=>p.evaluate(x=>host(x),x);
            await post(report());await p.waitForFunction(()=>outbox.some(m=>m.kind==='covered'));
            assert.equal(await p.locator('#transition-report').isVisible(),true);checks++;
            assert.equal(await p.locator('[data-settlement-stage]').textContent(),frozen.stageName);checks++;
            assert.equal(await p.evaluate(()=>LootPanel.reportPresentation().density),'compact');checks++;
            assert.equal(await p.locator('[data-settlement-stashed-rewards] .loot-settlement-flow-card').count(),1);checks++;
            assert.equal(await p.locator('[data-settlement-stashed-rewards] strong').textContent(),'+3');checks++;
            const sectionsDoNotOverlap=()=>{
                const lastKill=document.querySelector('.loot-settlement-kill-card:last-child').getBoundingClientRect();
                const flow=document.querySelector('.loot-settlement-flow-section').getBoundingClientRect();
                return flow.top>=lastKill.bottom;
            };
            assert.equal(await p.evaluate(sectionsDoNotOverlap),true,'compact records must not overlap');checks++;
            await p.screenshot({path:path.join(artifacts,reduced?'report-compact-rewards-reduced.png':'report-compact-rewards.png')});
            assert.equal(await p.locator('[data-settlement-side-tab=rewards]').textContent(),'本轮关卡奖励');checks++;
            assert.equal(await p.locator('.loot-source-view').count(),0);checks++;
            assert.equal(await p.locator('[data-transition-action=manageReport]').count(),0);checks++;
            assert.equal(await p.locator('.loot-close-btn').isEnabled(),true);checks++;
            assert.equal(await p.locator('.loot-stage-settlement .workbench-title').textContent(),'关卡结算');checks++;
            assert.equal(await p.locator('.loot-settlement-side').isVisible(),true);checks++;
            assert.equal(await p.locator('.loot-settlement-report .loot-settlement-metrics em').first().isVisible(),false);checks++;
            assert.equal(await p.locator('.loot-inventory-btn').isDisabled(),true);checks++;
            assert.equal(await p.locator('.loot-commit-bar button').isEnabled(),true);checks++;
            assert.equal(await p.locator('.loot-commit-bar button').textContent(),'完成结算');checks++;
            const rect=await p.locator('#transition-report').boundingBox();assert.ok(rect.x>=0&&rect.y>=0&&rect.x+rect.width<=1024&&rect.y+rect.height<=576);checks++;
            await p.locator('.item-grid-mode-option[data-layout-mode=full]').click();
            assert.equal(await p.evaluate(sectionsDoNotOverlap),true,'full records must not overlap');checks++;
            await p.evaluate(()=>{window.originalReport=document.querySelector('.loot-settlement-report');
                document.querySelector('.loot-settlement-report-scroll').scrollTop=80;});
            await post(report('loading',2));
            assert.equal(await p.evaluate(()=>originalReport===document.querySelector('.loot-settlement-report')),true);checks++;
            assert.equal(await p.locator('.loot-settlement-report-scroll').evaluate(el=>el.scrollTop),80);checks++;
            await p.locator('.item-grid-mode-option[data-layout-mode=full]').click();
            assert.equal(await p.locator('.loot-settlement-metrics em').first().isVisible(),true);checks++;
            await p.locator('[data-settlement-side-tab=materials]').click();
            await p.locator('.loot-settlement-material-toolbar input').fill('金属');
            await p.evaluate(()=>document.querySelector('.loot-settlement-report-scroll').scrollTop=80);
            await p.waitForFunction(()=>outbox.some(m=>m.type==='scene_transition_report_view'
                &&m.viewState.density==='full'&&m.viewState.rightTab==='materials'&&m.viewState.materialSearch==='金属'&&m.viewState.scrollTop===80));checks++;
            await p.screenshot({path:path.join(artifacts,reduced?'report-original-layout-loading-reduced.png':'report-original-layout-loading.png')});
            await p.locator('.loot-commit-bar button').click();
            assert.equal(await p.locator('.loot-commit-bar button').isDisabled(),true);checks++;
            await p.keyboard.press('Escape');await p.keyboard.press('Escape');
            assert.equal(await p.evaluate(()=>outbox.filter(m=>m.verb==='closeReport').length),1);checks++;
            await post(report('loading',3,{reportVisible:false}));
            assert.equal(await p.locator('#transition-report').isVisible(),false);checks++;
            assert.equal(await p.locator('#transition').evaluate(el=>getComputedStyle(el).opacity),'1');checks++;
            releaseImage();await p.waitForFunction(()=>!document.getElementById('transition-image').hidden);
            await post(report('reveal',4,{reportVisible:false,revealAllowed:true,reportReady:true}));
            await p.waitForFunction(()=>outbox.some(m=>m.kind==='revealed'));
            assert.equal(await p.locator('#transition').isVisible(),false);checks++;
            await post(report('reveal',1,{requestId:'tr:2',reportReady:true,rewardReady:true,revealAllowed:true}));
            await p.waitForTimeout(280);
            assert.equal(await p.locator('#transition-report').isVisible(),true);checks++;
            assert.equal(await p.evaluate(()=>outbox.some(m=>m.requestId==='tr:2'&&m.kind==='revealed')),false);checks++;
            assert.equal(await p.locator('[data-transition-action=manageReport]').count(),0);checks++;
            assert.equal(await p.evaluate(()=>outbox.filter(m=>m.requestId==='tr:2'&&m.verb==='manageReport').length),1);checks++;
            await post(report('reveal',1,{requestId:'tr:2',reportReady:true,rewardReady:true,revealAllowed:true}));
            await p.waitForTimeout(120);
            assert.equal(await p.evaluate(()=>outbox.filter(m=>m.requestId==='tr:2'&&m.verb==='manageReport').length),1);checks++;
            await post(report('reveal',2,{requestId:'tr:2',reportReady:true,rewardReady:true,revealAllowed:false,reportHandoff:true,actionPending:true}));
            assert.equal(await p.locator('#transition-report').isVisible(),true);checks++;
            assert.equal(await p.locator('.loot-close-btn').isDisabled(),true);checks++;
            assert.equal(await p.locator('.loot-commit-bar button').isDisabled(),true);checks++;
            await p.keyboard.press('Escape');assert.equal(await p.evaluate(()=>outbox.filter(m=>m.requestId==='tr:2'&&m.type==='scene_transition_action').length),1);checks++;
            await post(report('reveal',3,{requestId:'tr:2',reportReady:true,rewardReady:true,revealAllowed:true}));
            assert.equal(await p.locator('.loot-close-btn').isEnabled(),true);checks++;
            assert.equal(await p.locator('.loot-commit-bar button').isEnabled(),true);checks++;
            await p.waitForTimeout(180);
            assert.equal(await p.evaluate(()=>outbox.filter(m=>m.requestId==='tr:2'&&m.verb==='manageReport').length),1);checks++;
            assert.match(await p.locator('.loot-commit-bar').textContent(),/暂未能打开/);checks++;
            await post(report('reveal',4,{requestId:'tr:2',connected:false,generation:1}));
            assert.equal(await p.locator('.loot-close-btn').isDisabled(),true);checks++;
            assert.equal(await p.locator('.loot-commit-bar button').isDisabled(),true);checks++;
            assert.match(await p.locator('.loot-commit-bar').textContent(),/连接/);checks++;
            assert.deepEqual(await p.evaluate(()=>Array.from(new Set(outbox.map(m=>m.type).filter(t=>t.startsWith('scene_transition')))).sort()),
                ['scene_transition_ready','scene_transition_presented','scene_transition_action','scene_transition_report_view'].sort());checks++;
            await post(report('hide',5,{requestId:'tr:2',reportVisible:false,generation:1}));
            assert.equal(await p.locator('#transition').isVisible(),false);checks++;
            await p.reload();
            await post(report('cover',1,{requestId:'tr:3'}));
            await p.waitForFunction(()=>outbox.some(m=>m.requestId==='tr:3'&&m.kind==='covered'));
            assert.equal(await p.evaluate(()=>LootPanel.reportPresentation().density),'full',
                'an explicit density choice survives loading a fresh document');checks++;
            await p.close();
        }
        // The report mounts inside an already scaled transition canvas. Validate the
        // first painted bounds at non-unit scales, then keep the same report while resizing.
        for(const viewport of [{width:1600,height:900},{width:1024,height:576},{width:1366,height:768},
            {width:1920,height:1080},{width:960,height:540},{width:1280,height:800}]) {
            const p=await browser.newPage({viewport});
            await p.addInitScript(()=>{window.outbox=[];window.chrome={webview:{postMessage:m=>outbox.push(m),
                addEventListener:(type,cb)=>(window.hostHandlers||(window.hostHandlers=[])).push(cb)}};window.host=p=>hostHandlers.forEach(cb=>cb({data:p}));});
            await p.goto('http://127.0.0.1:'+server.address().port+'/scene-transition.html');
            const frozen={v:1,runId:'run:scale',stageName:'DEATH MATCH入门赛',difficulty:'简单',outcome:'victory',
                activeFrames:119,totalKills:1,omittedKillTypes:0,totalItemGains:0,totalItemLosses:0,
                omittedItemFlowTypes:0,rewardRollOmissions:0,rewardStashed:true,
                kills:[{key:'enemy:1',displayName:'测试敌人',iconName:'',doll:null,eliteLevel:0,count:1}],itemFlows:[]};
            const report=snapshot('cover',1,{version:2,report:frozen,reportVisible:true,reportHandoff:false,reportReady:false});
            await p.evaluate(x=>host(x),report);
            async function paintedBounds() {
                return p.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>{
                    const host=document.getElementById('transition-report'),r=host.getBoundingClientRect();
                    const controls=['.loot-close-btn','.loot-settlement-side','.loot-commit-bar button'].map(selector=>{
                        const el=host.querySelector(selector),b=el.getBoundingClientRect();
                        return {selector,x:b.x,y:b.y,right:b.right,bottom:b.bottom,width:b.width,height:b.height};
                    });
                    resolve({x:r.x,y:r.y,width:r.width,height:r.height,controls,
                        containerWidth:innerWidth,containerHeight:innerHeight,
                        stage:host.querySelector('[data-settlement-stage]').textContent});
                })));
            }
            function assertFit(value,size) {
                const s=Math.min(size.width/1024,size.height/576),w=1024*s,h=576*s;
                assert.ok(Math.abs(value.width-w)<1&&Math.abs(value.height-h)<1,
                    'single report scale '+JSON.stringify({viewport:size,expected:{w,h},actual:value}));checks++;
                assert.ok(Math.abs(value.x-(size.width-w)/2)<1&&Math.abs(value.y-(size.height-h)/2)<1);checks++;
                for(const control of value.controls){assert.ok(control.width>0&&control.height>0
                    &&(control.x+control.right)/2>=0&&(control.y+control.bottom)/2>=0
                    &&(control.x+control.right)/2<=size.width&&(control.y+control.bottom)/2<=size.height,
                    'report control outside viewport '+JSON.stringify(control));checks++;}
                assert.equal(value.stage,frozen.stageName);checks++;
            }
            const first=await paintedBounds();
            if(viewport.width===1600) {
                fs.writeFileSync(path.join(artifacts,'report-first-paint-1600.json'),JSON.stringify(first,null,2)+'\n');
                await p.screenshot({path:path.join(artifacts,'report-first-paint-1600.png')});
            }
            assertFit(first,viewport);
            await p.evaluate(()=>{window.scaleReport=document.querySelector('.loot-stage-settlement');});
            for(const size of [{width:1280,height:720},viewport]) {
                await p.setViewportSize(size);await p.waitForTimeout(80);
                assertFit(await paintedBounds(),size);
                assert.equal(await p.evaluate(()=>scaleReport===document.querySelector('.loot-stage-settlement')),true);checks++;
            }
            await p.evaluate(x=>host(x),{...report,phase:'loading',revision:2});
            assertFit(await paintedBounds(),viewport);
            assert.equal(await p.evaluate(()=>outbox.some(m=>m.verb==='manageReport')),false);checks++;
            await p.close();
        }
        // Exercise the production Loot facade and request mux inside the fixed document.
        // Authority responses below are isolated fixtures, never player inventory writes.
        for (const mode of ['hold-open','unknown','close-before-ready']) {
            const p=await browser.newPage({viewport:{width:1600,height:900}});
            const errors=[];p.on('pageerror',e=>errors.push(String(e)));
            await p.addInitScript(()=>{
                window.outbox=[];window.hostHandlers=[];window.fixtureRevision=1;
                window.fixtureLastOperation='';window.fixtureStock=0;window.dropWrite=false;
                window.chrome={webview:{postMessage:m=>{
                    outbox.push(m);
                    if(m.type==='task'&&m.task==='loot_request')setTimeout(()=>{
                        if(m.cmd==='close'&&dropWrite)return;
                        if(m.cmd==='claim'||m.cmd==='claimBatch'){fixtureStock=0;fixtureRevision++;fixtureLastOperation=m.operationId;}
                        if(m.cmd==='close'){fixtureRevision++;fixtureLastOperation=m.operationId;}
                        const empty=i=>({physicalSlot:i,occupied:false,slotLease:'empty.'+i});
                        const slots=(id,count)=>{
                            const rows=Array.from({length:count},(_,i)=>empty(i));
                            if(id===m.lootContainerId&&fixtureStock)rows[0]={physicalSlot:0,occupied:true,slotLease:'stock.1',
                                item:{name:'强化石',displayName:'强化石',icon:'强化石',itemKind:'stack',quantity:1,majorType:'材料',use:'材料'}};
                            return {containerId:id,capacity:count,accessibleCapacity:count,viewCapacity:count,filterKey:'all',
                                pageSizeHint:count,locked:false,snapshotSeq:fixtureRevision,containerEpoch:id===m.lootContainerId?7:1,
                                containerVersion:fixtureRevision,offset:0,limit:count,slots:rows,filterFacets:[],filterItemCount:rows.filter(r=>r.occupied).length,
                                setFacets:[],setFilterItemCount:0};
                        };
                        const closing=m.cmd==='close';
                        const terminal=closing&&!fixtureStock?{kind:'CONSUMED',reason:'user_close',remainingCount:0}:null;
                        host({type:'panel_resp',task:'loot_response',domain:'loot',panel:'loot',cmd:m.cmd,callId:m.callId,
                            panelInstanceId:m.panelInstanceId,chestSessionId:m.chestSessionId,lootContainerId:m.lootContainerId,
                            containerEpoch:m.containerEpoch,success:true,error:'',authorityRevision:fixtureRevision,
                            lastAppliedOperationId:fixtureLastOperation,state:terminal?'CONSUMED':closing?'LOOT_SUSPENDED':'LOOT_ACTIVE',remainingCount:terminal?0:fixtureStock,
                            closeLease:closing?'':'close.'+fixtureRevision,snapshots:closing?[]:[slots(m.lootContainerId,8),slots('背包',50),slots('药剂栏',8)],
                            tooltip:null,materials:m.cmd==='materials'?[]:null,terminal});
                    },0);
                },addEventListener:(type,cb)=>hostHandlers.push(cb)}};
                window.host=x=>hostHandlers.forEach(cb=>cb({data:x}));
            });
            await p.goto('http://127.0.0.1:'+server.address().port+'/scene-transition.html');
            await p.evaluate(()=>window.__LOOT_PANEL_CONFIG__.requestTimeoutMs=80);
            const frozen={v:1,runId:'run.shared',stageName:'共享结算测试',difficulty:'简单',outcome:'victory',activeFrames:300,
                totalKills:0,omittedKillTypes:0,totalItemGains:0,totalItemLosses:0,omittedItemFlowTypes:0,rewardRollOmissions:0,
                rewardStashed:true,kills:[],itemFlows:[]};
            const project=(phase,revision,extra={})=>p.evaluate(x=>host(x),snapshot(phase,revision,
                {version:2,report:frozen,reportVisible:true,reportHandoff:false,...extra}));
            await project('cover',1);
            await p.waitForFunction(()=>outbox.some(m=>m.kind==='covered'));
            assert.equal(await p.evaluate(()=>outbox.filter(m=>m.task==='loot_request').length),0);checks++;
            await p.evaluate(()=>{
                window.originalShell=document.querySelector('.loot-stage-settlement');window.originalReport=document.querySelector('.loot-settlement-report');
                window.originalMode=document.querySelector('.item-grid-mode-option[data-layout-mode=full]');
                window.originalModelGeneration=LootPanel.debugState().generation;
            });
            await p.locator('.item-grid-mode-option[data-layout-mode=full]').click();
            await p.locator('[data-settlement-side-tab=materials]').click();
            await p.locator('.loot-settlement-material-toolbar input').fill('金属');
            await project('loading',2,{rewardReady:true});
            await p.waitForFunction(()=>outbox.some(m=>m.verb==='manageReport'));
            assert.equal(await p.evaluate(()=>outbox.filter(m=>m.verb==='manageReport').length),1);checks++;
            await project('loading',3,{rewardReady:true,reportHandoff:true,actionPending:true});
            await p.evaluate(report=>host({type:'panel_cmd',cmd:'open',panel:'loot',initData:{v:1,panelInstanceId:'loot.shared',
                chestSessionId:'stage.shared',lootContainerId:'settlement.shared',containerEpoch:7,displayName:'关卡结算',capacity:8,columns:4,
                sourceKind:'stage_settlement',report}}),frozen);
            await p.waitForFunction(()=>LootPanel.debugState().phase==='active');
            assert.equal(await p.evaluate(()=>originalShell===document.querySelector('.loot-stage-settlement')
                &&originalReport===document.querySelector('.loot-settlement-report')&&originalMode===document.querySelector('.item-grid-mode-option[data-layout-mode=full]')),true);checks++;
            assert.equal(await p.locator('.loot-settlement-material-toolbar input').inputValue(),'金属');checks++;
            assert.equal(await p.evaluate(()=>LootPanel.reportPresentation().density),'full');checks++;
            assert.equal(await p.evaluate(()=>outbox.filter(m=>m.cmd==='snapshot'&&m.task==='loot_request').length),1);checks++;
            assert.equal(await p.evaluate(()=>outbox.some(m=>m.cmd==='materials')),true);checks++;
            assert.equal(await p.evaluate(()=>window.__LOOT_PANEL_CONFIG__.sceneReady===true),false);checks++;
            if(mode==='hold-open') {
                await project('error',4,{reportHandoff:true,actionPending:false});
                assert.equal(await p.locator('[data-transition-action=retry]').isEnabled(),true);checks++;
                await p.keyboard.press('Tab');
                assert.equal(await p.evaluate(()=>document.activeElement.hasAttribute('data-transition-action')),true);checks++;
                await p.locator('[data-transition-action=retry]').click();
                assert.equal(await p.evaluate(()=>outbox.filter(m=>m.verb==='retry').length),1);checks++;
                await p.evaluate(x=>host(x),snapshot('cover',1,{version:2,requestId:'tr:2',report:frozen,
                    reportVisible:true,reportHandoff:true,rewardReady:true,actionPending:false}));
                assert.equal(await p.evaluate(()=>originalReport===document.querySelector('.loot-settlement-report')&&LootPanel.debugState().phase==='active'),true);checks++;
                assert.equal(await p.evaluate(()=>outbox.filter(m=>m.cmd==='snapshot'&&m.task==='loot_request').length),1);checks++;
            }
            await p.locator('[data-settlement-side-tab=rewards]').click();
            assert.equal(await p.locator('.loot-commit-bar button').textContent(),'完成结算');checks++;
            assert.equal(await p.locator('.loot-commit-bar button').isEnabled(),true);checks++;
            if(mode==='close-before-ready') {
                await p.locator('.loot-commit-bar button').click();
                await p.waitForFunction(()=>outbox.some(m=>m.cmd==='close'&&m.task==='loot_request'));
                await p.waitForFunction(()=>Panels.getActive()===null);
                assert.equal(await p.evaluate(()=>outbox.filter(m=>m.cmd==='close'&&m.task==='loot_request').length),1);checks++;
                await project('loading',4,{reportVisible:false});
                assert.equal(await p.locator('#transition').isVisible(),true);checks++;
                assert.equal(await p.locator('#transition-report').isVisible(),false);checks++;
            } else {
                // Stashed rewards have already committed. A real remaining write here is
                // the exact report-close lease; use its lost ACK to exercise the unknown gate.
                if(mode==='unknown') {
                    await p.evaluate(()=>{dropWrite=true;});
                    await p.locator('.loot-commit-bar button').click();
                    assert.equal(await p.locator('.loot-commit-bar button').isDisabled(),true);checks++;
                    await p.waitForFunction(()=>LootPanel.debugState().phase==='reconcile_required');
                }
                assert.equal(await p.locator('.loot-source-slot.occupied').count(),0);checks++;
                assert.equal(await p.evaluate(()=>outbox.filter(m=>m.task==='loot_request'&&(m.cmd==='claimBatch'||m.cmd==='claim')).length),0);checks++;
                await p.evaluate(()=>window.businessGeneration=LootPanel.debugState().generation);
                await project('reveal',5,{requestId:mode==='hold-open'?'tr:2':'tr:1',rewardReady:true,reportHandoff:true,actionPending:true,reportReady:true,revealAllowed:true,targetScene:3});
                await p.evaluate(()=>host({type:'scene_transition_complete'}));
                assert.equal(await p.evaluate(()=>originalShell===document.querySelector('.loot-stage-settlement')
                    &&originalReport===document.querySelector('.loot-settlement-report')&&businessGeneration===LootPanel.debugState().generation),true);checks++;
                assert.equal(await p.locator('#transition').isVisible(),true);checks++;
                assert.equal(await p.evaluate(()=>outbox.filter(m=>m.cmd==='snapshot'&&m.task==='loot_request').length),1);checks++;
                if(mode==='unknown') {
                    assert.equal(await p.evaluate(()=>LootPanel.debugState().phase),'reconcile_required');checks++;
                    await p.keyboard.press('Escape');await p.locator('.loot-close-btn').click();
                    assert.equal(await p.locator('.loot-commit-bar button').textContent(),'重新核对');checks++;
                    await p.locator('.loot-commit-bar button').click();
                    await p.waitForFunction(()=>outbox.some(m=>m.cmd==='query'&&m.task==='loot_request'));
                    assert.equal(await p.evaluate(()=>outbox.filter(m=>m.cmd==='query'&&m.task==='loot_request').length),1);checks++;
                    assert.equal(await p.evaluate(()=>outbox.filter(m=>m.cmd==='close'&&m.task==='loot_request').length),1);checks++;
                    assert.equal(await p.evaluate(()=>outbox.filter(m=>m.task==='loot_request'&&(m.cmd==='claimBatch'||m.cmd==='claim')).length),0);checks++;
                }
                await p.screenshot({path:path.join(artifacts,'shared-'+mode+'.png')});
                if(mode==='hold-open') {
                    // One warm document serves multiple runs. A previous completion must
                    // not label the next report ready before its own scene has arrived.
                    for(let run=2;run<=3;run++) {
                        const nextReport={...frozen,runId:'run.next.'+run};
                        const nextProjection={version:2,requestId:'tr:'+(run+1),report:nextReport,reportVisible:true};
                        await p.evaluate(()=>Panels.close());
                        await p.evaluate(x=>host(x),snapshot('cover',1,{...nextProjection,reportHandoff:false}));
                        await p.waitForFunction(()=>LootPanel.isPreview());
                        assert.equal(await p.evaluate(()=>window.__LOOT_PANEL_CONFIG__.sceneReady===true),false,
                            'the next settlement must begin with its own loading state');checks++;
                        assert.equal(await p.evaluate(()=>LootPanel.reportPresentation().density),'full',
                            'the next settlement retains the chosen density');checks++;
                        await p.evaluate(x=>host(x),snapshot('loading',2,{...nextProjection,reportHandoff:true,rewardReady:true}));
                        await p.evaluate(report=>host({type:'panel_cmd',cmd:'open',panel:'loot',initData:{v:1,
                            panelInstanceId:'loot.'+report.runId,chestSessionId:'stage.'+report.runId,
                            lootContainerId:'settlement.'+report.runId,containerEpoch:7,displayName:'关卡结算',capacity:8,columns:4,
                            sourceKind:'stage_settlement',report}}),nextReport);
                        await p.waitForFunction(()=>LootPanel.debugState().phase==='active');
                        assert.match(await p.locator('.workbench-status').textContent(),/正在返回基地/);checks++;
                        await p.evaluate(()=>host({type:'scene_transition_complete'}));
                        assert.equal(await p.locator('.workbench-status').textContent(),'结算状态已同步');checks++;
                        assert.equal(await p.evaluate(()=>LootPanel.reportPresentation().density),'full');checks++;
                        assert.equal(await p.evaluate(()=>outbox.filter(m=>m.cmd==='snapshot'&&m.task==='loot_request').length),run);checks++;
                    }
                    assert.equal(await p.locator('.loot-commit-bar button').textContent(),'完成结算');checks++;
                    await p.locator('.loot-commit-bar button').click();
                    await p.waitForFunction(()=>Panels.getActive()===null);
                    assert.equal(await p.evaluate(()=>outbox.filter(m=>m.cmd==='close'&&m.task==='loot_request').length),1);checks++;
                    assert.equal(await p.locator('.loot-stage-settlement').isVisible(),false);checks++;
                    assert.equal(await p.evaluate(()=>outbox.filter(m=>m.task==='loot_request'&&(m.cmd==='claimBatch'||m.cmd==='claim')).length),0);checks++;
                }
            }
            assert.deepEqual(errors,[]);checks++;
            await p.close();
        }
        const report={kind:'browser-fixture',checks,reducedMotion:true,physicalGameAcceptance:false,artifacts};
        fs.writeFileSync(path.join(artifacts,'browser-results.json'),JSON.stringify(report,null,2)+'\n');
        console.log('Scene transition browser checks passed: '+checks+' (DOM/render fixture only)');
    } finally {await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;server.close();});
