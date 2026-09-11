'use strict';
const assert = require('assert');
const path = require('path');
const fs = require('fs');
const { chromium } = require('../launcher/perf/node_modules/playwright');
const root = path.resolve(__dirname, '..');
(async () => {
    const executablePath = ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
        'C:/Program Files/Microsoft/Edge/Application/msedge.exe'].find(value=>fs.existsSync(value));
    if (!executablePath) throw new Error('Microsoft Edge not found');
    const browser = await chromium.launch({executablePath,headless:true});
    try {
        const page = await browser.newPage({viewport:{width:1024,height:576}});
        await page.setContent('<html lang="zh-CN"><body style="margin:0"><main style="position:relative;width:1024px;height:576px"><div data-build-underlay><button id="origin">物品页</button></div></main></body></html>');
        function styles(file) {
            return fs.readFileSync(file, 'utf8').replace(/@import url\("([^"]+)"\);/g,
                (_, source) => styles(path.resolve(path.dirname(file), source)));
        }
        await page.addStyleTag({content:styles(path.join(root,'launcher/web/css/panels.css'))});
        for (const module of ['workbench-lifecycle','workbench-focus','workbench-primitives','workbench-profile','workbench','inventory-ui'])
            await page.addScriptTag({path:path.join(root,'launcher/web/modules/'+module+'.js')});
        await page.addScriptTag({path:path.join(root,'launcher/web/modules/character-build/character-build-stash-view.js')});
        await page.evaluate(() => {
            window.fixture = {items:[],requests:[],queries:[],state:'idle',changes:0,slow:false};
            fixture.reset = count => {
                fixture.items = Array.from({length:count}, (_, i) => ({entryId:'store.e'+i,revision:1,quantity:i%2 ? 1 : 8,
                    item:{name:'物资'+i,displayName:i%2 ? '备用步枪 '+i : '维修材料 '+i,itemKind:i%2 ? 'equipment':'stack',
                        enhancementLevel:5,quantity:i%2?1:8,icon:'',modSlots:[]}}));
                fixture.requests=[];fixture.queries=[];fixture.revision=1;
            };
            fixture.view={root:document.querySelector('main'),_iconHtml:()=>'<span aria-hidden="true">◆</span>'};
            fixture.controller={
                debugState:()=>({state:fixture.state}),
                requestStashPage:(offset, callback) => {
                    fixture.queries.push(offset);
                    setTimeout(()=>callback({success:true,storeId:'store',revision:fixture.revision,offset,total:fixture.items.length,
                        entries:fixture.items.slice(offset,offset+32),migrationRequired:false,pendingOperationId:''}),0);
                    return 'query';
                },
                invokeStash:(command, data, callback) => {
                    if(fixture.state!=='idle')return null;
                    fixture.requests.push({command,entries:data.entries.slice()});fixture.state='write_pending';
                    setTimeout(()=>{
                        const accepted=[],blocked=[];
                        data.entries.forEach(ref=>{
                            const index=fixture.items.findIndex(item=>item.entryId===ref.entryId);
                            const item=fixture.items[index];
                            if(item.item.itemKind==='equipment') {blocked.push({entryId:ref.entryId,reason:'inventory_full'});return;}
                            accepted.push({entryId:ref.entryId,quantity:ref.quantity});
                            if(ref.quantity===item.quantity)fixture.items.splice(index,1);
                            else {item.quantity-=ref.quantity;item.revision++;}
                        });
                        fixture.revision++;fixture.state='idle';callback({success:true,accepted,blocked},true);
                    }, fixture.slow?120:0);
                    return 'write';
                },reconcile:()=>{}
            };
            fixture.open=()=>CharacterBuildStashView.open(fixture.view,fixture.controller,{changed:()=>fixture.changes++});
            fixture.reset(85);document.querySelector('#origin').focus();fixture.open();
        });
        await page.waitForFunction(()=>document.querySelectorAll('[data-stash-entry]').length===32);
        assert.strictEqual(await page.locator('[data-build-underlay]').evaluate(el=>el.inert),true);
        assert.strictEqual(await page.locator('[data-stash-entry]').count(),32);
        await page.locator('[data-stash-entry]').first().click();
        await page.locator('.stash-quantity').fill('3');
        await page.locator('[data-stash-take]').click();
        await page.waitForFunction(()=>fixture.items[0].quantity===5&&document.querySelector('.stash-quantity').value==='5');
        await page.locator('[data-stash-all]').click();
        await page.waitForFunction(()=>document.querySelector('[data-stash-status]').textContent.includes('其余继续保管'),null,{timeout:10000});
        const state=await page.evaluate(()=>({remaining:fixture.items.length,requests:fixture.requests,queries:fixture.queries}));
        assert.strictEqual(state.remaining,42);
        assert(state.requests.length<20,'all-take must converge without looping over blocked rows');
        assert(state.requests.every(request=>request.command==='stashTake'&&request.entries.length<=32));
        assert(state.queries.some(offset=>offset>0),'all-take reaches later pages');
        await page.keyboard.press('Escape');
        assert.strictEqual(await page.locator('.character-build-stash').count(),0);
        assert.strictEqual(await page.locator('[data-build-underlay]').evaluate(el=>el.inert),false);
        assert.strictEqual(await page.evaluate(()=>document.activeElement.id),'origin');
        await page.evaluate(()=>{fixture.reset(4096);fixture.open();});
        await page.waitForFunction(()=>document.querySelectorAll('[data-stash-entry]').length===32);
        await page.locator('[data-stash-next]').click();
        await page.waitForFunction(()=>fixture.queries[fixture.queries.length-1]===32 && document.querySelectorAll('[data-stash-entry]')[0].getAttribute('data-stash-entry')==='store.e32');
        assert.strictEqual(await page.locator('[data-stash-entry]').count(),32);
        assert((await page.locator('.inventory-page-option').count())<=15,'page menu must also remain bounded');
        await page.locator('.inventory-page-jump').click();
        await page.keyboard.press('Escape');
        assert.strictEqual(await page.locator('.character-build-stash').count(),1,'first Escape closes page menu');
        await page.locator('.item-grid-mode-option[data-layout-mode=full]').click();
        assert.strictEqual(await page.locator('.stash-owned-grid.item-grid-compact').count(),0);
        await page.locator('.item-grid-mode-option[data-layout-mode=compact]').click();
        const geometry=await page.locator('.character-build-stash').evaluate(el=>({width:el.getBoundingClientRect().width,height:el.getBoundingClientRect().height,scroll:document.documentElement.scrollWidth}));
        assert(geometry.width<=1024&&geometry.height<=576&&geometry.scroll<=1024,JSON.stringify(geometry));
        fs.mkdirSync(path.join(root,'tmp/reward-stash'),{recursive:true});
        await page.screenshot({path:path.join(root,'tmp/reward-stash/stash-view.png')});
        await page.evaluate(()=>{fixture.view._stashClose();fixture.reset(64);fixture.slow=true;fixture.open();});
        await page.waitForFunction(()=>document.querySelectorAll('[data-stash-entry]').length===32);
        await page.locator('[data-stash-all]').click();
        await page.waitForFunction(()=>fixture.state==='write_pending');
        await page.locator('[data-stash-back]').click();
        await page.waitForTimeout(200);
        assert.strictEqual(await page.evaluate(()=>fixture.requests.length),1,'closing stops future batches while current result completes');
        console.log('Reward stash battlebox components: shared grid, density, bounded page menu, partial amount, bounded pages, blocked rows, all-take, Esc, focus restore, 4096-row window and close-during-write passed.');
    } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
