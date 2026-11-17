#!/usr/bin/env node
'use strict';
const fs = require('fs'), http = require('http'), path = require('path');
const ROOT = path.resolve(__dirname, '..'), WEB = path.join(ROOT, 'launcher/web');
const {chromium} = require(path.join(ROOT, 'launcher/perf/node_modules/playwright'));
const shot = process.argv.find(a => a.startsWith('--shot-dir='));
const results = [];
function check(ok, name) { if (!ok) throw new Error(name); results.push(name); }
function fixture() {
    var listeners = {};
    function emit(evt) {
        (listeners[evt] || []).slice().forEach(function(fn) { fn(); });
    }
    var disabledCfg = {v:1, enabled:false, physicalSlot:-1, itemKey:'', status:'disabled'};
    var authority = window.__customAuthority = {
        state:'idle', mode:'success', calls:[], queries:0, navigatedToDrugs:0,
        loadoutRevision:1, drugRevision:1,
        bagCfg:JSON.parse(JSON.stringify(disabledCfg)),
        payload:{
            emergencyInjection:JSON.parse(JSON.stringify(disabledCfg)),
            targetEmergencyInjection:null,
            drugLayout:{v:2,bankCount:2,laneCount:4,physicalSlotCount:8,activeBank:0,switchKeyLabel:'6',
                switchCooldown:{ready:true,totalSteps:0,currentStep:0,progressPercent:0,animationFrame:1,remainingMs:0}},
            drugs:[]
        }
    };
    for (var i = 0; i < 8; i++) {
        authority.payload.drugs.push({
            slot:i, bank:Math.floor(i / 4), lane:i % 4, active:i < 4,
            keyLabel:['7', '8', '9', '0'][i % 4],
            occupied:i === 0 || i === 1 || i === 4,
            quantity:i === 0 || i === 1 || i === 4 ? 99 - i : 0,
            item:i === 0 || i === 1 || i === 4
                ? {name:i === 1 ? '大MP药剂' : '大HP药剂', displayName:i === 1 ? '大MP药剂' : '大HP药剂', icon:i === 1 ? '大MP药剂' : '大HP药剂', quantity:99 - i}
                : null
        });
    }
    function settle(success) {
        if (success && authority.intent) {
            var nextCfg = {
                v:1,
                enabled:authority.intent.enabled,
                physicalSlot:authority.intent.enabled ? authority.intent.drugSlot : -1,
                itemKey:authority.intent.enabled ? authority.intent.expectedItemName : '',
                status:authority.intent.enabled ? 'authorized' : 'disabled'
            };
            authority.drugRevision++;
            authority.payload.targetEmergencyInjection = nextCfg;
            if (authority.intent.chestTarget.kind === 'backpack') {
                authority.bagCfg = nextCfg;
                if (window.__customView && window.__customView._source && window.__customView._source.sourceKind === 'inventory') {
                    window.__customView._snapshot.equipment.emergencyInjection = nextCfg;
                }
            } else {
                authority.payload.emergencyInjection = nextCfg;
                if (window.__customView && window.__customView._source && window.__customView._source.sourceKind === 'loadout') {
                    window.__customView._snapshot.equipment.emergencyInjection = nextCfg;
                }
            }
        }
        authority.state = 'idle';
        emit(success ? 'mutation_success' : 'mutation_failed');
    }
    var session = {
        getSnapshot:function() { return authority.payload; },
        getState:function() { return authority.state; },
        getLoadoutRevision:function() { return authority.loadoutRevision; },
        debugState:function() { return {state:authority.state, loadoutRevision:authority.loadoutRevision, drugRevision:authority.drugRevision}; },
        subscribe:function(evt, fn) {
            (listeners[evt] = listeners[evt] || []).push(fn);
            return function() {
                listeners[evt] = (listeners[evt] || []).filter(function(cb) { return cb !== fn; });
            };
        },
        configureEmergencyInjection:function(chestTarget, enabled, drugSlot, expectedItemName) {
            authority.intent = {chestTarget:chestTarget, enabled:enabled, drugSlot:drugSlot, expectedItemName:expectedItemName};
            authority.calls.push(authority.intent);
            authority.state = 'write_pending';
            emit('mutation_start');
            setTimeout(function() {
                if (authority.mode === 'unknown') {
                    authority.state = 'needs_reconcile';
                    emit('mutation_unknown');
                } else {
                    settle(authority.mode !== 'failure');
                }
            }, 15);
            return 'call.' + authority.calls.length;
        },
        reconcileMutation:function() {
            authority.queries++;
            settle(true);
            return 'reconcile.' + authority.queries;
        }
    };
    var custom = CharacterBuildCustomization.createForSession(session);
    var view = window.__customView = EquipmentTuningView.create({
        customization:custom,
        onNavigateToDrugSlots:function() { authority.navigatedToDrugs++; },
        send:function() { return false; }
    });
    window.__setChest = function(kind, name, bagSlot) {
        if (kind === 'non61') {
            view._source = {sourceKind:'loadout', sessionGeneration:1, slotKey:'上装装备', expectedLoadoutRevision:authority.loadoutRevision};
            view._sourceItem = {name:'普通防弹衣', displayName:'普通防弹衣', icon:'普通防弹衣', itemKind:'equipment', majorType:'防具', use:'上装装备', enhancementLevel:1};
            view._snapshot = {equipment:{name:'普通防弹衣', type:'防具', use:'上装装备', level:1, mods:[], modSlots:[], modSlotCapacity:0}};
            view._customizationActive = false;
        } else if (kind === 'backpack') {
            view._source = {sourceKind:'inventory', containerId:'背包', slot:bagSlot, expectedLease:'lease.bag.' + bagSlot};
            view._sourceItem = {name:name, displayName:name, icon:name, itemKind:'equipment', majorType:'防具', use:'上装装备', enhancementLevel:5};
            view._snapshot = {equipment:{name:name, type:'防具', use:'上装装备', level:5, mods:[], modSlots:[], modSlotCapacity:0, emergencyInjection:authority.bagCfg}};
        } else {
            view._source = {sourceKind:'loadout', sessionGeneration:1, slotKey:'上装装备', expectedLoadoutRevision:authority.loadoutRevision};
            view._sourceItem = {name:name, displayName:name, icon:name, itemKind:'equipment', majorType:'防具', use:'上装装备', enhancementLevel:13};
            view._snapshot = {equipment:{name:name, type:'防具', use:'上装装备', level:13, mods:[], modSlots:[], modSlotCapacity:0, emergencyInjection:authority.payload.emergencyInjection}};
        }
        view._status = '装备状态已同步';
        view.render({preserveScroll:false});
    };
    window.__setChest('loadout', '统合61式胸甲');
    document.getElementById('qa-output').hidden = true;
    view.mount(document.getElementById('host'));
    window.__customReady = true;
}
let html = fs.readFileSync(path.join(WEB, 'modules/equipment-tuning/dev/harness.html'), 'utf8');
const start = html.indexOf('<script>', html.indexOf('equipment-tuning-view.js'));
if (start < 0) throw new Error('Cannot locate the existing tuning browser fixture');
html = html.slice(0, start)
    + '<script src="../../character-build/character-build-drug-controls.js"></script>'
    + '<script src="../../character-build/character-build-customization.js"></script>'
    + '<script>(' + fixture.toString() + ')();</script></body></html>';
async function main() {
    const server = http.createServer((req, res) => {
        const url = new URL(req.url, 'http://127.0.0.1');
        if (url.pathname === '/modules/equipment-tuning/dev/customization-test.html') {
            res.setHeader('Content-Type', 'text/html; charset=utf-8');
            res.end(html);
            return;
        }
        const file = path.resolve(WEB, '.' + decodeURIComponent(url.pathname));
        if (!file.startsWith(WEB + path.sep)) { res.writeHead(403); res.end(); return; }
        fs.readFile(file, (error, bytes) => {
            if (error) { res.writeHead(404); res.end(); return; }
            res.setHeader('Content-Type', file.endsWith('.js') ? 'application/javascript' : file.endsWith('.css') ? 'text/css' : 'text/html');
            res.end(bytes);
        });
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const executablePath = [process.env['ProgramFiles(x86)'], process.env.ProgramFiles]
        .filter(Boolean).map(p => path.join(p, 'Microsoft/Edge/Application/msedge.exe')).find(p => fs.existsSync(p));
    const browser = await chromium.launch({executablePath, headless:true});
    try {
        for (const [width, height] of [[1024, 576], [1156, 662], [1600, 960]]) {
            const page = await browser.newPage({viewport:{width, height}});
            const errors = []; page.on('pageerror', error => errors.push(error.message));
            await page.goto('http://127.0.0.1:' + server.address().port + '/modules/equipment-tuning/dev/customization-test.html');
            await page.waitForFunction(() => window.__customReady);

            check(await page.locator('.equipment-tuning-tab').count() === 5, '61 chest exposes five tabs with 机制');
            check((await page.locator('[data-customization-open]').innerText()).trim() === '机制', '5th tab is labeled 机制');
            check(await page.locator('[data-tuning-focus-key="summary-mechanism"]').count() === 1, 'summary header pill renders for 61 chest');
            check(await page.locator('.equipment-tuning-tabs').evaluate(root => {
                const boxes = Array.from(root.children).map(n => n.getBoundingClientRect());
                return boxes.every(box => Math.abs(box.top - boxes[0].top) < 1) && root.scrollWidth <= root.clientWidth + 1;
            }), 'all five tabs fit on one row');

            await page.evaluate(() => window.__setChest('non61'));
            check(await page.locator('.equipment-tuning-tab').count() === 4, 'non-61 equipment remains 4 tabs');
            check(await page.locator('[data-tuning-focus-key="summary-mechanism"]').count() === 0, 'non-61 equipment hides mechanism summary pill');

            await page.evaluate(() => window.__setChest('loadout', '统合61式胸甲'));
            await page.locator('[data-tuning-focus-key="summary-mechanism"]').click();
            check(await page.locator('.equipment-tuning-confirmation').count() === 0, 'mechanism tab hides quick-submit controls');
            check(await page.locator('[data-customization-enabled]').count() === 0
                && await page.locator('.equipment-tuning-commit-bar').count() === 0, 'single-step click removes checkbox and commit bar');

            await page.locator('[data-drug-slot="4"]').click();
            await page.waitForFunction(() => document.querySelector('[data-drug-slot="4"]')?.getAttribute('data-bound') === 'true');
            check(await page.evaluate(() => __customAuthority.calls.length === 1
                && __customAuthority.calls[0].chestTarget.kind === 'loadout'
                && __customAuthority.payload.emergencyInjection.physicalSlot === 4), 'single click binds inactive bank slot directly to worn chest');
            check((await page.locator('[data-tuning-focus-key="summary-mechanism"]').innerText()).includes('II-[7]'), 'summary pill shows II-[7] after bind');

            await page.evaluate(() => { __customAuthority.mode = 'unknown'; });
            await page.locator('[data-customization-disable]').click();
            await page.waitForFunction(() => document.querySelectorAll('[data-customization-reconcile]').length === 1);
            check(await page.evaluate(() => !__customView.canClose()), 'unknown mutation keeps tuning close fence');
            check(await page.locator('[data-drug-slot="0"]').isDisabled(), 'unknown mutation freezes drug tiles');
            await page.locator('[data-customization-reconcile]').click();
            await page.waitForFunction(() => document.querySelector('[data-drug-slot="4"]')?.getAttribute('data-bound') === 'false');
            check(await page.evaluate(() => __customAuthority.calls.length === 2 && __customAuthority.queries === 1
                && !__customAuthority.payload.emergencyInjection.enabled), 'reconcile queries outcome without replaying write');

            await page.evaluate(() => { __customAuthority.mode = 'failure'; });
            await page.locator('[data-drug-slot="0"]').click();
            await page.waitForTimeout(40);
            check(await page.evaluate(() => !__customAuthority.payload.emergencyInjection.enabled), 'rejected click never writes false UI state');

            await page.evaluate(() => { __customAuthority.mode = 'success'; });
            await page.locator('[data-drug-slot="4"]').click();
            await page.waitForFunction(() => document.querySelector('[data-drug-slot="4"]')?.getAttribute('data-bound') === 'true');
            await page.locator('[data-drug-slot="4"]').click();
            await page.waitForFunction(() => document.querySelector('[data-drug-slot="4"]')?.getAttribute('data-bound') === 'false');

            await page.evaluate(() => window.__setChest('backpack', '钛合金61式胸甲', 2));
            await page.locator('[data-drug-slot="0"]').click();
            await page.waitForFunction(() => document.querySelector('[data-drug-slot="0"]')?.getAttribute('data-bound') === 'true');
            check(await page.evaluate(() => {
                const last = __customAuthority.calls[__customAuthority.calls.length - 1];
                return last.chestTarget.kind === 'backpack' && last.chestTarget.slot === 2
                    && __customAuthority.bagCfg.physicalSlot === 0
                    && !__customAuthority.payload.emergencyInjection.enabled;
            }), 'backpack 61 chest configures independent slot without altering worn chest');

            const layout = await page.evaluate(() => {
                const view = document.querySelector('.equipment-tuning-view');
                const footer = document.querySelector('.cb-mech-footer')?.getBoundingClientRect();
                return {overflowX:view.scrollWidth > view.clientWidth + 1,
                    footerTop:footer ? footer.top : -1, footerBottom:footer ? footer.bottom : -1};
            });
            check(!layout.overflowX && layout.footerTop >= 0 && layout.footerBottom <= height, 'no horizontal overflow and rules footer fits viewport');

            if (shot) {
                const dir = path.resolve(shot.slice('--shot-dir='.length));
                fs.mkdirSync(dir, {recursive:true});
                await page.screenshot({path:path.join(dir, 'customization-' + width + 'x' + height + '.png')});
            }
            check(errors.length === 0, 'browser has no page errors: ' + errors.join('; '));
            await page.close();
        }
        console.log('Character build customization: ' + results.length + '/' + results.length + ' passed across 3 viewports (mock authority)');
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
}
main().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
