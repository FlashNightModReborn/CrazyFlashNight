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
    const qa = window.__bookQa = {
        sent:[], pending:['settle','unknown','readfail'].includes(scenario), reads:0, writes:0, queries:0,
        done:false, allowReturn:false, transitionAcks:[], frames:0
    };
    function frame() { qa.frames++; requestAnimationFrame(frame); }
    requestAnimationFrame(frame);
    qa.emit = (type, data) => (handlers[type] || []).forEach(handler => handler(data));
    qa.transition = data => { qa.transitionFrame=qa.frames; qa.emit('bookshelf_transition', Object.assign({
        panelInstanceId:'bookshelf.preview.1', requestId:'tr:1', revision:1,
        generation:4, phase:'cover', connected:true, revealAllowed:false
    }, data)); };
    qa.records = {bestMs:87250, clears:8, history:Array.from({length:20}, (_, index) => ({
        runId:'saved.' + index, bookId:'repair-campus', outcome:index===0 ? 'failure' : index%3 ? 'victory' : 'retreat',
        elapsedMs:87250 + index * 4000, completedAt:1791172800000 - index * 3600000,
        sp:index===0 ? 0 : index===1 ? 45 : index%3 ? 5 : 0,
        reason:index===0 ? 'incomplete' : index===1 ? 'first_clear' : index%3 ? 'clear' : 'incomplete', debug:index===19
    }))};
    if (scenario==='empty') qa.records={bestMs:87250,clears:8,history:[]};
    qa.returningResult = scenario==='return' ? {
        runId:'pending.victory', bookId:'repair-campus', outcome:'victory', elapsedMs:123450,
        completedAt:0, sp:0, reason:'pending', debug:false
    } : null;
    window.Toast = {add:function(){}};
    window.Bridge = {
        on:(type, handler)=>(handlers[type]||(handlers[type]=[])).push(handler),
        off:(type, handler)=>{handlers[type]=(handlers[type]||[]).filter(x=>x!==handler);},
        send:message=>{
            qa.sent.push(message);
            if(message.cmd==='close') return true;
            if(message.cmd==='transitionPresented') {
                qa.transitionAcks.push({payload:message.payload, frame:qa.frames,
                    visible:!!document.querySelector('.bookshelf-panel') &&
                        document.querySelector('.bookshelf-panel').getBoundingClientRect().height>0});
                return true;
            }
            if(message.domain==='bookshelf-original') {
                const response={type:'panel_resp',panel:'bookshelf',domain:'bookshelf-original',cmd:message.cmd,
                    callId:message.callId,panelInstanceId:message.panelInstanceId,success:message.cmd==='release',
                    error:message.cmd==='prepare'?'not_owned':undefined};
                setTimeout(()=>qa.emit('panel_resp',response),8); return true;
            }
            const inRun=scenario==='return' && !qa.done;
            const base={type:'panel_resp',panel:'bookshelf',domain:'bookshelf',cmd:message.cmd,
                callId:message.callId,panelInstanceId:message.panelInstanceId,v:1,token:message.payload.token,
                phase:'editing',success:true,kind:message.payload.kind || (scenario==='return'?'return':'settle'),
                activeSlot:inRun?'bookrun_fixture':'fixture_a',role:inRun?'Andy Law':'测试角色',inRun,
                originSlot:'fixture_a',exitRequired:inRun,canSwitch:true,unlocked:true,
                pendingRun:qa.pending?'bookrun_fixture':'',lastReward:0,records:qa.records,
                returningResult:qa.returningResult,slots:[{slot:'fixture_a',name:'测试角色'}]};
            if(message.cmd==='snapshot') {
                qa.reads++;
                if(scenario==='readfail' && qa.reads===2) Object.assign(base,{success:false,error:'disconnected',phase:undefined});
            } else if(message.cmd==='commit') {
                qa.writes++;
                if(message.payload.kind==='play') Object.assign(base,{phase:'switching'});
                else if(scenario==='return') {
                    if(qa.writes===1) Object.assign(base,{phase:undefined,success:false,error:'save_unavailable'});
                    else { Object.assign(base,{phase:'switching'}); setTimeout(()=>qa.transition(),20); }
                } else Object.assign(base,{phase:'save_pending',success:false,requiresReconcile:true,recoveryToken:message.payload.token});
            } else if(message.cmd==='query') {
                qa.queries++;
                if(scenario==='return' && !qa.allowReturn) {
                    Object.assign(base,qa.queries===1 ? {phase:undefined,success:false,error:'disconnected'} : {phase:'switching',kind:'return'});
                } else if(scenario==='unknown' && qa.queries===1) {
                    Object.assign(base,{phase:'save_pending',success:false,requiresReconcile:true});
                } else {
                    if(scenario==='return') {
                        qa.records.history.unshift({runId:'saved.return',bookId:'repair-campus',outcome:'victory',
                            elapsedMs:86250,completedAt:1791176400000,sp:45,reason:'first_clear',debug:false});
                        qa.records.history=qa.records.history.slice(0,20);
                        qa.records.bestMs=86250; qa.records.clears=9;
                    }
                    qa.pending=false; qa.done=true; qa.returningResult=null;
                    Object.assign(base,{phase:'applied',pendingRun:'',nextToken:'bookshelf.fixture.next'});
                }
            } else throw new Error('unexpected '+message.cmd);
            setTimeout(()=>qa.emit('panel_resp',base),8);
            return true;
        }
    };
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
async function assertEntryFirst(page) {
    const metrics=await page.evaluate(()=>{
        const detail=document.querySelector('#bookshelf-detail');
        detail.scrollTop=0;
        const editions=detail.querySelector('.bookshelf-editions');
        const records=detail.querySelector('.bookshelf-run-records');
        const viewport=detail.getBoundingClientRect();
        const latest=records.querySelector('.bookshelf-last-run strong');
        return {
            detailHeight:viewport.height,entriesHeight:editions.getBoundingClientRect().height,recordsTop:records.getBoundingClientRect().top-viewport.top,latestBottom:latest&&latest.getBoundingClientRect().bottom-viewport.top,
            entriesFirst:!!(editions.compareDocumentPosition(records)&Node.DOCUMENT_POSITION_FOLLOWING),
            entryButtonsVisible:Array.from(editions.querySelectorAll('button')).every(button=>{
                const box=button.getBoundingClientRect();
                return box.top>=viewport.top && box.bottom<=viewport.bottom;
            }),
            latestSummaryVisible:!latest || latest.getBoundingClientRect().bottom<=viewport.bottom,
            latestRewardVisible:!latest || records.querySelector('.bookshelf-record-reward').getBoundingClientRect().bottom<=viewport.bottom,
            bestVisible:records.querySelector('.bookshelf-record-summary').getBoundingClientRect().bottom<=viewport.bottom
        };
    });
    assert(metrics.entriesFirst && metrics.entryButtonsVisible && metrics.latestSummaryVisible && metrics.latestRewardVisible && metrics.bestVisible,
        'entry-first first-screen geometry: '+JSON.stringify(metrics));
}
async function assertPrimaryReadability(page, enabled) {
    const primary=page.locator('.bookshelf-primary');
    function luminance(color) {
        const rgb=color.match(/[\d.]+/g).slice(0,3).map(Number).map(value=>{
            const component=value/255;
            return component<=.04045 ? component/12.92 : Math.pow((component+.055)/1.055,2.4);
        });
        return .2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2];
    }
    async function check() {
        const style=await primary.evaluate(node=>{
            const css=getComputedStyle(node);
            return {text:css.color,fill:css.backgroundColor,opacity:Number(css.opacity),disabled:node.disabled};
        });
        const a=luminance(style.text),b=luminance(style.fill);
        assert((Math.max(a,b)+.05)/(Math.min(a,b)+.05)>=4.5,'primary theme text contrast meets 4.5:1');
        assert.strictEqual(style.disabled,!enabled);
        assert(enabled ? style.opacity===1 : style.opacity<1,'disabled visual remains distinct');
        return style;
    }
    await page.mouse.move(0,0);
    const normal=await check();
    await primary.hover();
    const hovered=await check();
    assert.strictEqual(hovered.fill,normal.fill,'hover preserves the primary light fill');
    assert.strictEqual(hovered.text,normal.text,'hover preserves readable primary text');
}
async function main(){
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const edge=[process.env['ProgramFiles(x86)'],process.env.ProgramFiles].filter(Boolean)
        .map(p=>path.join(p,'Microsoft/Edge/Application/msedge.exe')).find(fs.existsSync);
    const browser=await chromium.launch({headless:true,executablePath:edge,ignoreDefaultArgs:['--hide-scrollbars']}),report=[];
    try {
        for(const [width,height] of [[640,360],[1024,576],[1600,900]]) for(const scenario of ['settle','unknown','readfail','return','series','records','empty']) {
            const page=await browser.newPage({viewport:{width,height},reducedMotion:'reduce'}),errors=[];
            page.on('pageerror',e=>errors.push(e.message));
            await page.goto('http://127.0.0.1:'+server.address().port+'/launcher/web/modules/bookshelf/dev/harness.html?scenario='+scenario);
            const primary=page.locator('.bookshelf-primary'), recover=page.locator('#bookshelf-recover');
            if(scenario==='series') {
                await page.locator('#bookshelf-reader-tools [data-reader="library"]').click();
                await page.locator('[data-book="crazy-flasher"]').click();
                await primary.waitFor();
                assert.strictEqual(await page.locator('[data-book="crazy-flasher"]').count(),1);
                assert.strictEqual(await page.locator('[data-chapter]').count(),6);
                const note=await page.locator('[data-edition="remake-note"]').textContent();
                assert(note.includes('45 SP')&&note.includes('5 SP')&&note.includes('暂停'));
                await page.screenshot({path:path.join(out,'series-'+width+'x'+height+'.png')});
                for(let chapter=2;chapter<=6;chapter++) {
                    await page.locator('[data-chapter="'+chapter+'"]').click();
                    assert(await primary.isDisabled());assert.strictEqual(await primary.textContent(),'尚未制作');
                    await assertPrimaryReadability(page,false);
                    const language=page.locator('[data-action="language"]');await language.selectOption('en');
                    await page.locator('[data-action="original"]').click();
                    await page.waitForFunction(()=>document.querySelector('.bookshelf-original-status').textContent.includes('未拥有'));
                    assert.strictEqual(await page.locator('#bookshelf-original iframe').count(),0);
                    await page.locator('[data-original="back"]').click();
                    assert.strictEqual(await language.inputValue(),'en');
                    assert.strictEqual(await page.locator('[data-chapter="'+chapter+'"]').getAttribute('aria-pressed'),'true');
                }
                const requests=await page.evaluate(()=>__bookQa.sent);
                assert.strictEqual(requests.filter(m=>m.cmd==='commit').length,0);
                assert.deepStrictEqual(requests.filter(m=>m.domain==='bookshelf-original'&&m.cmd==='prepare').map(m=>[m.payload.chapter,m.payload.language]),
                    [[2,'en'],[3,'en'],[4,'en'],[5,'en'],[6,'en']]);
                const geometry=await page.evaluate(()=>{const n=document.querySelector('.bookshelf-panel'),a=document.querySelector('[data-action="original"]'),b=a.getBoundingClientRect();
                    return n.scrollWidth<=n.clientWidth+1 && b.bottom<=innerHeight && b.width>40 && b.height>24;});
                assert(geometry);
            } else if(scenario==='return') {
                await page.waitForFunction(()=>__bookQa.writes===1 && !document.querySelector('.bookshelf-primary').disabled);
                assert.strictEqual(await primary.textContent(),'结束旅程，返回原角色');
                assert(await page.locator('#bookshelf-close').isDisabled());
                await page.locator('#bookshelf-close').evaluate(b=>b.click()); await page.keyboard.press('Escape');
                assert.strictEqual(await page.evaluate(()=>__bookQa.sent.filter(m=>m.cmd==='close').length),0);
                assert(await primary.isVisible());
                await primary.click();
                await page.waitForFunction(()=>__bookQa.transitionAcks.some(a=>a.payload.kind==='covered'));
                assert(await page.evaluate(()=>__bookQa.transitionAcks[0].frame>=__bookQa.transitionFrame+2),'cover waits for two painted frames');
                // Model the first receipt being rejected by Host after losing foreground.
                // The retained document must confirm the same stamp after a foreground retry.
                await page.evaluate(()=>{
                    Object.defineProperty(document,'hidden',{configurable:true,value:true});
                    __bookQa.transition();
                });
                await page.waitForTimeout(80);
                assert.strictEqual(await page.evaluate(()=>__bookQa.transitionAcks.length),1,'hidden document cannot acknowledge a retry');
                await page.evaluate(()=>{
                    delete document.hidden;
                    __bookQa.transition();
                });
                await page.waitForFunction(()=>__bookQa.transitionAcks.length===2);
                assert(await page.evaluate(()=>{
                    const qa=__bookQa, first=qa.transitionAcks[0], retry=qa.transitionAcks[1];
                    return JSON.stringify(first.payload)===JSON.stringify(retry.payload)
                        && retry.visible && retry.frame>=qa.transitionFrame+2;
                }),'same stamp rejected by Host can be confirmed again after two foreground frames');
                assert((await page.locator('.bookshelf-record-reward').textContent()).includes('确认中'));
                assert(!(await page.locator('.bookshelf-last-run').textContent()).includes('+45'));
                const frameBefore=await page.evaluate(()=>{
                    const qa=__bookQa; qa.transitionAcks=[];
                    qa.transition({revision:2,phase:'error'});
                    return qa.frames;
                });
                await page.locator('#bookshelf-transition-retry').waitFor({state:'visible'});
                await page.evaluate(()=>{
                    __bookQa.emit('bookshelf_transition_complete',{panelInstanceId:'bookshelf.preview.1',requestId:'expired.request',revision:1,generation:3});
                });
                await page.waitForTimeout(80);
                assert(await page.locator('#bookshelf-transition-retry').isVisible(),'expired complete must not retire current transition');
                await page.evaluate(()=>{
                    __bookQa.transition({panelInstanceId:'expired.instance',revision:999,phase:'reveal',revealAllowed:true});
                    __bookQa.transition({generation:3,revision:999,phase:'reveal',revealAllowed:true});
                    __bookQa.transition({revision:1,phase:'reveal',revealAllowed:true});
                });
                await page.waitForTimeout(80);
                assert.strictEqual(await page.evaluate(()=>__bookQa.transitionAcks.length),0,'expired identities cannot acknowledge');
                await page.evaluate(()=>__bookQa.transition({revision:3,phase:'reveal',revealAllowed:false}));
                await page.waitForTimeout(80);
                assert.strictEqual(await page.evaluate(()=>__bookQa.transitionAcks.length),0,'reveal admission required');
                await page.evaluate(()=>__bookQa.transition({revision:4,phase:'reveal',revealAllowed:true}));
                await page.waitForFunction(()=>__bookQa.transitionAcks.some(a=>a.payload.kind==='revealed'));
                const ack=await page.evaluate(()=>__bookQa.transitionAcks[0]);
                assert(ack.visible && ack.frame>=frameBefore+2);
                assert.deepStrictEqual(ack.payload,{type:'scene_transition_presented',requestId:'tr:1',revision:4,generation:4,kind:'revealed'});
                await page.waitForFunction(()=>__bookQa.queries>=2);
                assert(await primary.isDisabled());
                assert.strictEqual(await page.evaluate(()=>__bookQa.sent.filter(m=>m.cmd==='close').length),0);
                await page.evaluate(()=>{
                    __bookQa.allowReturn=true;
                    __bookQa.emit('bookshelf_transition_complete',{panelInstanceId:'bookshelf.preview.1',requestId:'tr:1',revision:4,generation:4});
                });
                await page.waitForFunction(()=>__bookQa.sent.some(m=>m.cmd==='snapshot'&&m.payload.token==='bookshelf.fixture.next'));
                await page.evaluate(()=>__bookQa.transition({revision:4,phase:'reveal',revealAllowed:true}));
                await page.waitForTimeout(80);
                assert.strictEqual(await page.evaluate(()=>__bookQa.transitionAcks.length),1,'completed request tombstone rejects late revival');
                await page.waitForFunction(()=>document.querySelector('.bookshelf-record-reward').textContent.includes('+45 SP · 已入账'));
                assert(await primary.isEnabled());
                await assertPrimaryReadability(page,true);
                await assertEntryFirst(page);
                await page.screenshot({path:path.join(out,'return-reward-'+width+'x'+height+'.png')});
                assert.strictEqual(await page.evaluate(()=>__bookQa.writes),2);
                assert.deepStrictEqual(await page.evaluate(()=>__bookQa.sent.filter(m=>m.cmd==='commit').map(m=>m.payload.kind)),['return','return']);
                assert(await page.evaluate(()=>__bookQa.sent.filter(m=>m.cmd==='query').every(m=>m.payload.token==='bookshelf.preview.1')));
                assert.strictEqual(await page.evaluate(()=>__bookQa.sent.filter(m=>m.cmd==='close').length),0);
            } else if(scenario==='records' || scenario==='empty') {
                await page.locator('#bookshelf-reader-tools [data-reader="library"]').click();
                await page.locator('[data-book="crazy-flasher"]').click();
                await page.locator('.bookshelf-run-records').waitFor();
                await assertEntryFirst(page);
                assert((await page.locator('.bookshelf-record-summary').textContent()).includes('1:27.25'));
                if(scenario==='records') {
                    assert((await page.locator('.bookshelf-last-run').textContent()).includes('挑战失败'));
                    assert(!(await page.locator('.bookshelf-last-run').textContent()).includes('+45'));
                    assert((await page.locator('.bookshelf-record-reward').textContent()).includes('无 SP'));
                    await page.locator('.bookshelf-history summary').click();
                    assert.strictEqual(await page.locator('.bookshelf-history tbody tr').count(),20);
                    await page.evaluate(()=>window.__recordNode=document.querySelector('.bookshelf-run-records'));
                    await page.locator('[data-chapter="1"]').evaluate(button=>button.click());
                    assert(await page.evaluate(()=>document.querySelector('.bookshelf-run-records')===__recordNode
                        && __recordNode.querySelector('details').open),'record DOM and expanded history remain stable');
                    const area=page.locator('#bookshelf-detail');
                    assert(await area.evaluate(n=>n.scrollHeight>n.clientHeight),'history scrolls');
                    for(const selector of ['.bookshelf-body nav','#bookshelf-detail']) {
                        const style=await page.locator(selector).evaluate(n=>{
                            const probe=document.createElement('span');
                            probe.style.backgroundColor='var(--wb-scrollbar-thumb)'; n.appendChild(probe);
                            const expectedThumb=getComputedStyle(probe).backgroundColor;
                            probe.style.backgroundColor='var(--wb-scrollbar-thumb-hover)';
                            const expectedHover=getComputedStyle(probe).backgroundColor;
                            probe.style.backgroundColor='var(--wb-scrollbar-track)';
                            const expectedTrack=getComputedStyle(probe).backgroundColor; probe.remove();
                            return {color:getComputedStyle(n).scrollbarColor,width:getComputedStyle(n).scrollbarWidth,
                                thumb:getComputedStyle(n,'::-webkit-scrollbar-thumb').backgroundColor,
                                track:getComputedStyle(n,'::-webkit-scrollbar-track').backgroundColor,
                                arrows:getComputedStyle(n,'::-webkit-scrollbar-button').display,
                                expectedThumb,expectedHover,expectedTrack};
                        });
                        assert.strictEqual(style.color,'auto','Chromium uses themed pseudo-elements');
                        assert.strictEqual(style.width,'auto');
                        assert([style.expectedThumb,style.expectedHover].includes(style.thumb),'shared normal or hovered thumb color');
                        assert.strictEqual(style.track,style.expectedTrack);
                        assert.strictEqual(style.arrows,'none','system arrows hidden');
                    }
                    await area.hover(); await page.mouse.wheel(0,400);
                    await page.waitForFunction(()=>document.querySelector('#bookshelf-detail').scrollTop>0);
                    await area.evaluate(n=>n.scrollTop=0);
                    await assertPrimaryReadability(page,true);
                await assertEntryFirst(page);
                    await area.evaluate(n=>n.scrollTop=0);
                    await page.screenshot({path:path.join(out,'records-'+width+'x'+height+'.png')});
                } else {
                    assert.strictEqual(await page.locator('.bookshelf-history').count(),0);
                    assert.strictEqual(await page.locator('.bookshelf-last-run').count(),0);
                    assert((await page.locator('.bookshelf-run-records').textContent()).includes('尚无详细战绩'));
                    await page.locator('#bookshelf-close').click();
                    await page.evaluate(()=>Panels.open('bookshelf',{panelInstanceId:'bookshelf.reopen.1',token:'bookshelf.reopen.1'}));
                    await page.locator('[data-book="crazy-flasher"]').click();
                    assert.strictEqual(await page.locator('.bookshelf-last-run').count(),0);
                }
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
                await page.waitForFunction(()=>document.querySelector('.bookshelf-primary').textContent==='进入重制版'&&!document.querySelector('.bookshelf-primary').disabled);
                const messages=await page.evaluate(()=>__bookQa.sent);
                assert.strictEqual(messages.filter(m=>m.cmd==='close').length,0);
                assert(messages.filter(m=>m.cmd==='query').every(m=>m.payload.token==='bookshelf.preview.1'));
                assert(messages.some(m=>m.cmd==='snapshot'&&m.payload.token==='bookshelf.fixture.next'));
                const geometry=await page.evaluate(()=>{const n=document.querySelector('.bookshelf-panel'),b=n.getBoundingClientRect();
                    return Math.abs(b.left)<=1&&Math.abs(b.top)<=1&&Math.abs(b.width-innerWidth)<=1
                        &&Math.abs(b.height-innerHeight)<=1&&n.scrollWidth<=n.clientWidth+1;});
                assert(geometry);
                if(scenario==='settle')await page.screenshot({path:path.join(out,width+'x'+height+'.png')});
                await primary.click();
                await page.waitForFunction(()=>__bookQa.sent.some(m=>m.cmd==='close'));
                assert.deepStrictEqual(await page.evaluate(()=>__bookQa.sent.filter(m=>m.cmd==='commit').map(m=>[m.payload.kind,m.payload.token])),
                    [['settle','bookshelf.preview.1'],['play','bookshelf.fixture.next']]);
            }
            assert(await page.evaluate(()=>{
                const panel=document.querySelector('.bookshelf-panel');
                if(!panel) return __bookQa.sent.some(m=>m.cmd==='commit'&&m.payload.kind==='play');
                const box=panel.getBoundingClientRect();
                return panel.scrollWidth<=panel.clientWidth+1 && Math.abs(box.width/box.height-1024/576)<.01
                    && box.left>=-1 && box.top>=-1 && box.right<=innerWidth+1 && box.bottom<=innerHeight+1;
            }),'fixed-ratio panel stays within viewport with no horizontal spill');
            assert.deepStrictEqual(errors,[]);report.push({width,height,scenario,passed:true});await page.close();
        }
        fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n');
        console.log('Bookshelf flow browser harness: 21 scenarios passed at 3 viewports.');
    } finally {await browser.close();}
}
main().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>server.close());
