#!/usr/bin/env node
'use strict';
// Browser fixture: production view/channel/transport, an explicit fake authority, no player save.
const fs = require('fs'), path = require('path'), http = require('http'), assert = require('assert');
const ROOT = path.resolve(__dirname, '..'), WEB = path.join(ROOT, 'launcher/web');
const {chromium} = require(path.join(ROOT, 'launcher/perf/node_modules/playwright'));
const catalog = JSON.parse(fs.readFileSync(path.join(ROOT, 'data/rewards/choice-rewards.json'), 'utf8'));
const optionFixture = [catalog.bundles[3],catalog.bundles[0],catalog.bundles.find(b => b.id === 'campus.advanced.revive'),catalog.bundles[2]]
    .map(b => ({optionId:b.id, title:b.title, description:b.description,
    items:b.items ? b.items.map(i => ({displayName:i.itemName,itemName:i.itemName,quantity:i.quantity,level:0}))
        : Array.from({length:b.weaponCount || 1},()=>({displayName:b.weapon,itemName:b.weapon,quantity:1,level:0}))
        .concat(b.mods.map(n => ({displayName:n,itemName:n,quantity:b.weaponCount || 1,level:0})))
        .concat(b.consumables.map(e => ({displayName:e.name,itemName:e.name,quantity:e.count,level:0})))}));
const out = path.resolve((process.argv.find(a => a.startsWith('--shot-dir=')) || '--shot-dir=tmp/choice-rewards-ui').split('=').slice(1).join('='));
fs.mkdirSync(out, {recursive:true});
const server = http.createServer((req, res) => {
    const file = path.resolve(WEB, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
    if (path.relative(WEB,file).startsWith('..')) { res.writeHead(403); res.end(); return; }
    fs.readFile(file, (err, bytes) => {
        if (err) { res.writeHead(404); res.end(); return; }
        const ext = path.extname(file);
        res.setHeader('Content-Type', ext === '.html' ? 'text/html; charset=utf-8' : ext === '.js' ? 'text/javascript; charset=utf-8' : ext === '.css' ? 'text/css; charset=utf-8' : 'application/octet-stream');
        res.end(bytes);
    });
});
async function assertCardBoundaries(page) {
    const metrics = await page.evaluate(() => {
        const root = __choiceQa.control._choiceRewards.page.root;
        const cards = root.querySelector('.character-build-choice-cards');
        const footer = root.querySelector('.character-build-choice-footer');
        const colorProbe=document.createElement('span');
        colorProbe.style.backgroundColor='var(--wb-scrollbar-track)';
        root.appendChild(colorProbe);
        const expectedTrack=getComputedStyle(colorProbe).backgroundColor;
        colorProbe.remove();
        return {
            children: root.children.length,
            noPageOverflow: root.scrollHeight <= root.clientHeight + 1 && root.scrollWidth <= root.clientWidth + 1,
            separated: cards.getBoundingClientRect().bottom <= footer.getBoundingClientRect().top,
            themedTrack: getComputedStyle(cards, '::-webkit-scrollbar-track').backgroundColor,
            expectedTrack,
            arrowsHidden: getComputedStyle(cards, '::-webkit-scrollbar-button').display === 'none',
            cardContentBounded: Array.from(cards.querySelectorAll('[data-choice-option]')).every(card => {
                const bounds = card.getBoundingClientRect();
                return card.scrollWidth <= card.clientWidth + 1 && card.scrollHeight <= card.clientHeight + 1
                    && Array.from(card.querySelectorAll('*')).every(child => {
                        const rect = child.getBoundingClientRect();
                        return rect.left >= bounds.left - 1 && rect.right <= bounds.right + 1
                            && rect.top >= bounds.top - 1 && rect.bottom <= bounds.bottom + 1;
                    });
            })
        };
    });
    assert.strictEqual(metrics.children, 4, 'header/context/cards/footer');
    assert(metrics.noPageOverflow && metrics.separated && metrics.cardContentBounded, JSON.stringify(metrics));
    assert.strictEqual(metrics.themedTrack, metrics.expectedTrack);
    assert(metrics.arrowsHidden, 'no native scrollbar arrow buttons');
    return metrics;
}
async function main() {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const base = 'http://127.0.0.1:' + server.address().port;
    const edge = [process.env['ProgramFiles(x86)'],process.env.ProgramFiles].filter(Boolean)
        .map(p => path.join(p,'Microsoft/Edge/Application/msedge.exe')).find(fs.existsSync);
    const browser = await chromium.launch({headless:true, executablePath:edge, ignoreDefaultArgs:['--hide-scrollbars']});
    const report = [];
    try {
        for (const [width,height] of [[1024,576],[1366,768],[1920,1080]]) {
            const page = await browser.newPage({viewport:{width,height}, reducedMotion:'reduce'});
            const errors = []; page.on('pageerror', e => {errors.push(e.message);console.error(e.message);});
            await page.goto(base + '/modules/character-build/dev/harness.html');
            await page.waitForFunction(() => window.__qaReady === true);
            for (const rel of ['panel-scale.js','panel-runtime.js','character-build/character-build-cooldown-channel.js',
                'character-build/character-build-stash-transport.js','character-build/character-build-item-use.js',
                'character-build/character-build-choice-rewards.js','character-build/character-build-item-use-channel.js',
                'equipment-tuning-model.js','character-build/character-build-drug-layout.js','character-build/character-build-tuning-adapter.js',
                'character-build/character-build-candidate-eligibility.js','character-build/character-build-projection.js']) {
                await page.addScriptTag({url:base+'/modules/'+rel});
            }
            await page.evaluate(options => {
                const view = CharacterBuildHarness.view;
                const stage = document.getElementById('character-build-stage');
                stage.classList.add('panel-scale-shell'); PanelScale.attach(stage,1024,576);
                const qa = window.__choiceQa = {sent:[],offers:[],revision:0,mode:'commit',storage:0};
                qa.addOffer = function(count) {
                    qa.revision++;
                    qa.offers.push({offerId:'fixture.choice.'+qa.revision,title:'初阶配给',options:JSON.parse(JSON.stringify(options.slice(0,count || 3)))});
                    return qa.offers[qa.offers.length-1].offerId;
                };
                const router = new PanelRuntime.PanelResponseRouter();
                const control = qa.control = {_view:view,_panelInstanceId:'choice.ui',_session:{
                    getState:()=>'idle',getSessionGeneration:()=>1,debugState:()=>({}),refreshSnapshot:()=>null},
                    _ports:{toast:()=>{},openStorageSource:()=>{qa.storage++;return true;}},
                    _stateChanged:()=>view.setItemUseState(control._itemUse.debugState().state)};
                CharacterBuildItemUseChannel.install(control);
                control._startItemUseCooldownPolling = function() {};
                function send(message) {
                    qa.sent.push(message);
                    setTimeout(() => {
                        const response = {type:'panel_resp',panel:'workbench',domain:'item_use',cmd:message.cmd,
                            callId:message.callId,panelInstanceId:'choice.ui',success:true,operationId:message.payload.operationId};
                        if (message.cmd === 'inboxSnapshot') Object.assign(response, {rewardReady:false,rewardAuthority:null,
                            inboxSummary:{v:2,storeId:'fixture',authorityRevision:qa.revision,remainingCount:qa.stock ? 3 : 0}});
                        else if (message.cmd === 'stashChoices') {
                            if (qa.failRead) Object.assign(response, {success:false,error:'disconnected'});
                            else response.data={storeId:'fixture',revision:qa.revision,kpoints:qa.kpoints || 0,offers:JSON.parse(JSON.stringify(qa.offers)),pendingOperationId:''};
                        } else if (message.cmd === 'stashOpen') response.data={success:true,kind:'choiceOpen',offerId:qa.addOffer(),consumed:1,remaining:1};
                        else if (message.cmd === 'stashChoose') {
                            qa.receipt={success:true,kind:'choiceSelect',offerId:message.payload.offerId,optionId:message.payload.optionId,rewardReady:true};
                            if (qa.mode === 'unknown') Object.assign(response,{success:false,error:'reconcile_required',requiresReconcile:true});
                            else { qa.offers=qa.offers.filter(o=>o.offerId!==message.payload.offerId);qa.stock=!qa.noOverflow;qa.revision++;response.data=qa.receipt; }
                        } else if (message.cmd === 'stashQuery') {
                            if (qa.mode === 'unknown') Object.assign(response,{success:false,error:'client_timeout',requiresReconcile:true});
                            else { qa.offers=qa.offers.filter(o=>o.offerId!==qa.receipt.offerId);qa.stock=!qa.noOverflow;qa.revision++;response.data={state:'committed',result:qa.receipt}; }
                        } else throw new Error('unexpected fixture command '+message.cmd);
                        router.handleResponse(response);
                    }, 0);
                    return true;
                }
                control._itemUse=new CharacterBuildItemUse.Controller({send:send,router:router,operationNonce:'choice.ui',
                    onState:(s,r)=>control._itemUseStateChanged(s,r),
                    onInbox:i=>control._itemUseInboxChanged(i),onSettled:(r,c,p)=>control._itemUseSettled(r,c,p)});
                control._bindItemUse();
                const row={physicalSlot:4,quantity:2,item:{name:'书中初阶自选配给包',displayName:'书中初阶自选配给包',use:'礼包',itemKind:'stack'},
                    source:{containerId:'背包',slot:4,expectedLease:'lease.4'},
                    useAction:{command:'openChoice',label:'自选配给',source:{physicalSlot:4,slotLease:'lease.4',backpackVersion:1,itemName:'书中初阶自选配给包'}}};
                const candidates=CharacterBuildProjection.viewCandidates({target:{kind:'backpack'},candidates:[row]});
                view._onSlotSelect=()=>candidates;view._onCandidateScopeChange=()=>candidates;
                view._onCandidateSelect=c=>view.setItemUseCandidate(c);view._onUseCandidate=c=>control._useCandidate(c);
                view.showBackpackOverview();
            }, optionFixture);
            await page.locator('[data-candidate-key]').first().click();
            await page.locator('[data-build-action="use"]').click();
            const dialog = page.getByRole('dialog',{name:'自选礼包',exact:true});
            await dialog.waitFor({state:'visible'});
            await page.waitForFunction(() => document.querySelectorAll('[data-choice-option]').length === 3);
            assert((await page.locator('[data-choice-option]').nth(2).textContent()).includes('复活币'));
            assert.strictEqual(await page.locator('[data-choice-option]').nth(1).getByText('UZI',{exact:true}).count(),2);
            assert(await page.locator('[data-choice-confirm]').isDisabled());
            await page.locator('[data-choice-option]').nth(1).click();
            const saved = await page.evaluate(() => ({offer:__choiceQa.control._choiceRewards.offerId,
                selected:__choiceQa.control._choiceRewards.selected,options:JSON.stringify(__choiceQa.offers)}));
            await page.getByRole('button',{name:'返回构筑',exact:true}).click();
            const entryGeometry = await page.evaluate(() => {
                CharacterBuildHarness.view.clearCandidateSelection();
                const entry=document.querySelector('[data-choice-rewards-open]'),heading=entry.closest('header'),box=heading.getBoundingClientRect();
                const actions=Array.from(document.querySelectorAll('.character-build-candidate-actions button')).filter(n=>!n.hidden);
                return {bounded:entry.getBoundingClientRect().left>=box.left&&heading.scrollWidth<=heading.clientWidth+1,
                    maxThreeActions:actions.length<=3};
            });
            assert(Object.values(entryGeometry).every(Boolean),JSON.stringify(entryGeometry));
            if(width===1024) await page.screenshot({path:path.join(out,'pending-entry-1024x576.png')});
            await page.locator('[data-choice-rewards-open]').click();
            await page.waitForFunction(() => __choiceQa.control._choiceRewards.snapshot.offers.length === 1);
            assert.deepStrictEqual(await page.evaluate(() => ({offer:__choiceQa.control._choiceRewards.offerId,
                selected:__choiceQa.control._choiceRewards.selected,options:JSON.stringify(__choiceQa.offers)})), saved);
            // Keyboard scope and pointer occlusion must agree.
            for (let tab=0;tab<10;tab++) {
                await page.keyboard.press('Tab');
                assert(await page.evaluate(() => !!document.activeElement.closest('.character-build-choice-page')));
                assert(await page.evaluate(() => {
                    const css=getComputedStyle(document.activeElement);
                    return css.outlineStyle==='solid'&&css.outlineWidth==='2px'&&css.outlineOffset==='2px';
                }));
            }
            const geometry = await page.evaluate(() => {
                const root=__choiceQa.control._choiceRewards.page.root, box=root.getBoundingClientRect();
                return {within:box.left>=-1&&box.top>=-1&&box.right<=innerWidth+1&&box.bottom<=innerHeight+1,
                    noOverflow:root.scrollWidth<=root.clientWidth+1,
                    cards:Array.from(root.querySelectorAll('[data-choice-option]')).every(n=>n.getBoundingClientRect().height>180),
                    blocked:CharacterBuildHarness.view._underlay.hasAttribute('inert')};
            });
            assert(Object.values(geometry).every(Boolean),JSON.stringify(geometry));
            await assertCardBoundaries(page);
            await page.screenshot({path:path.join(out,width+'x'+height+'.png')});
            // Failed refresh cannot authorize a choice against old authority.
            await page.evaluate(() => {__choiceQa.failRead=true;__choiceQa.control._refreshChoiceRewards();});
            await page.waitForFunction(() => __choiceQa.control._choiceRewards.loadFailed === true);
            assert(await page.locator('[data-choice-confirm]').isDisabled());
            await page.evaluate(() => {__choiceQa.failRead=false;__choiceQa.mode='unknown';__choiceQa.control._refreshChoiceRewards();});
            await page.locator('[data-choice-confirm]').click();
            await page.waitForFunction(() => __choiceQa.control._itemUse.debugState().state === 'needs_reconcile');
            await page.getByRole('button',{name:'刷新',exact:true}).click();
            assert(await page.locator('[data-choice-confirm]').isDisabled());
            await page.evaluate(() => {__choiceQa.mode='commit';});
            await page.getByRole('button',{name:'核对领取结果',exact:true}).click();
            await page.waitForFunction(() => __choiceQa.control._choiceRewards.snapshot.offers.length === 0);
            assert(await page.getByRole('button',{name:'返回构筑',exact:true}).isEnabled());
            assert((await dialog.textContent()).includes('物品优先进入背包，装不下的进入暂存'));
            const writes = await page.evaluate(() => __choiceQa.sent.filter(r=>r.cmd==='stashChoose'||r.cmd==='stashQuery'));
            assert.strictEqual(writes.filter(r=>r.cmd==='stashChoose').length,1);
            assert(writes.every(r=>r.payload.operationId===writes[0].payload.operationId));
            assert.deepStrictEqual(Object.keys(writes[0].payload).sort(),['v','panelInstanceId','sessionGeneration','storeId','expectedRevision','offerId','optionId','operationId'].sort());
            await page.getByRole('button',{name:'前往暂存物资',exact:true}).click();
            assert.strictEqual(await page.evaluate(() => __choiceQa.storage),1);
            // Multiple pending packs and a larger four-card pool stay within the same surface.
            await page.evaluate(() => {__choiceQa.addOffer(4);__choiceQa.addOffer(2);__choiceQa.control._refreshChoiceRewards(__choiceQa.offers[0].offerId);});
            await page.waitForFunction(() => document.querySelectorAll('[data-choice-option]').length===4);
            assert.strictEqual(await dialog.locator('select').count(),0);
            assert.strictEqual(await page.locator('[data-choice-offer]').count(),2);
            await assertCardBoundaries(page);
            await page.screenshot({path:path.join(out,'multiple-offers-'+width+'x'+height+'.png')});
            await page.evaluate(() => {
                const qa=__choiceQa;qa.kpoints=200;
                const paid=qa.offers[0].options[0];paid.title='闪现特训';paid.description='直接获得闪现2级，主动技能需在技能页装备，不消耗SP。';paid.items=[];paid.kCost=300;paid.available=true;
                paid.skills=[{skillKey:'闪现',level:2,currentLevel:0,description:'回避技能，获得后在技能页装备。'}];
                qa.control._refreshChoiceRewards();
            });
            await page.waitForFunction(() => document.querySelector('[data-choice-option]').textContent.includes('300 K点'));
            await page.locator('[data-choice-option]').first().click();
            assert(await page.locator('[data-choice-confirm]').isDisabled());
            assert((await dialog.textContent()).includes('K点不足'));
            await page.locator('[data-choice-option]').nth(1).click();
            assert(await page.locator('[data-choice-confirm]').isEnabled());
            await page.evaluate(() => {__choiceQa.kpoints=400;__choiceQa.control._refreshChoiceRewards();});
            await page.waitForFunction(() => __choiceQa.control._choiceRewards.snapshot.kpoints===400);
            await page.locator('[data-choice-option]').first().click();
            assert(await page.locator('[data-choice-confirm]').isEnabled());
            assert((await page.locator('[data-choice-confirm]').textContent()).includes('支付 300 K点'));
            await page.screenshot({path:path.join(out,'paid-skill-'+width+'x'+height+'.png')});
            await page.evaluate(() => {__choiceQa.offers[0].options[0].available=false;__choiceQa.control._refreshChoiceRewards();});
            await page.waitForFunction(() => __choiceQa.control._choiceRewards.snapshot.offers[0].options[0].available===false);
            assert(await page.locator('[data-choice-confirm]').isDisabled());
            await page.evaluate(() => {
                const qa=__choiceQa;
                qa.offers[0].options[0].skills=[];
                qa.offers[0].options.forEach(o=>{
                    o.title='长中文候选配给标题用于验证换行后仍完整位于卡片内部';
                    o.description='长中文说明验证候选内容不会遮挡确认与返回按钮。'.repeat(8);
                    o.items=Array.from({length:16},(_,i)=>({itemName:'fixture.'+i,displayName:'较长的测试物品名称用于检查换行与可滚动候选',quantity:9999,level:15}));
                });
                qa.control._refreshChoiceRewards();
            });
            await page.waitForFunction(() => document.querySelector('.character-build-choice-items').children.length===16);
            assert(await page.evaluate(() => {
                const c=__choiceQa.control._choiceRewards;
                return c.cards.scrollHeight>c.cards.clientHeight&&c.cards.scrollWidth<=c.cards.clientWidth+1
                    && c.confirm.getBoundingClientRect().bottom<=innerHeight+1;
            }));
            await assertCardBoundaries(page);
            await page.locator('[data-choice-option]').first().focus();
            const scrollState = await page.evaluate(() => {
                const view=__choiceQa.control._choiceRewards;
                view.cards.scrollTop=120;
                return {top:view.cards.scrollTop, focused:document.activeElement.getAttribute('data-choice-option')};
            });
            await page.evaluate(() => {
                __choiceQa.kpoints=999999;
                __choiceQa.control._refreshChoiceRewards();
            });
            await page.waitForFunction(() => __choiceQa.control._choiceRewards.snapshot.kpoints===999999);
            assert.deepStrictEqual(await page.evaluate(() => ({top:__choiceQa.control._choiceRewards.cards.scrollTop,
                focused:document.activeElement.getAttribute('data-choice-option')})),scrollState);
            await page.evaluate(() => {
                const cards=__choiceQa.control._choiceRewards.cards;
                cards.scrollTop=cards.scrollHeight;
            });
            await page.screenshot({path:path.join(out,'long-content-bottom-'+width+'x'+height+'.png')});
            await page.locator('[data-choice-offer]').nth(1).click();
            assert.strictEqual(await page.locator('[data-choice-option]').count(),2);
            await page.keyboard.press('Escape');
            await dialog.waitFor({state:'hidden'});
            assert(await page.evaluate(() => !CharacterBuildHarness.view._underlay.hasAttribute('inert')));
            // A committed last choice returns directly to build only after both
            // the choice list and overflow inbox have authoritative empty reads.
            await page.evaluate(() => {
                const qa=__choiceQa;qa.offers=[];qa.stock=false;qa.noOverflow=true;
                qa.addOffer(2);qa.addOffer(2);qa.control._refreshChoiceRewards(qa.offers[0].offerId);
            });
            await dialog.waitFor({state:'visible'});
            await page.locator('[data-choice-option]').first().click();
            await page.locator('[data-choice-confirm]').click();
            await page.waitForFunction(() => __choiceQa.control._choiceRewards.snapshot.offers.length===1);
            assert(await dialog.isVisible(), 'another choice must remain available');
            await page.evaluate(() => {
                const qa=__choiceQa;qa.offers[0].options.forEach(o=>{o.items=[];o.skills=[{skillKey:'闪现',level:2,currentLevel:0}];});
                qa.control._refreshChoiceRewards();
            });
            await page.waitForFunction(() => __choiceQa.control._choiceRewards.snapshot.offers[0].options[0].items.length===0);
            await page.locator('[data-choice-option]').first().click();
            await page.locator('[data-choice-confirm]').click();
            await dialog.waitFor({state:'hidden'});
            assert(await page.evaluate(() => !CharacterBuildHarness.view._underlay.hasAttribute('inert')));
            // Merely reading an empty list does not force-close a manually opened page.
            await page.evaluate(() => {__choiceQa.control._choiceRewards.open();__choiceQa.control._refreshChoiceRewards();});
            await page.waitForFunction(() => __choiceQa.control._choiceRewards.snapshot.offers.length===0);
            assert(await dialog.isVisible());
            assert.deepStrictEqual(errors,[]);
            report.push({width,height,geometry,entryGeometry,checks:['backpack open','frozen reopen','keyboard focus','read failure','unknown write','exact query','stash navigation','multiple offers','2-4 cards','long content scroll']});
            await page.close();
        }
        fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n');
        console.log('Choice reward browser harness passed at all 3 viewports.');
    } finally {await browser.close();}
}
main().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>server.close());
