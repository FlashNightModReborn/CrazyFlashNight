'use strict';

const assert = require('assert');
const PanelRuntime = require('../launcher/web/modules/panel-runtime.js');
const Transport = require('../launcher/web/modules/character-build/character-build-transport.js');
const SessionModule = require('../launcher/web/modules/character-build-session.js');
const LoadoutTuning = require('../launcher/web/modules/inventory-workbench-loadout-tuning.js');

let passed = 0;
function check(name, fn) {
    fn();
    passed++;
    process.stdout.write('PASS ' + name + '\n');
}

function makeFakeElement(tag) {
    const el = {
        tagName: String(tag || 'div').toUpperCase(),
        className: '',
        textContent: '',
        innerHTML: '',
        hidden: false,
        disabled: false,
        attrs: {},
        children: [],
        parentNode: null,
        listeners: {},
        classList: {
            _set: new Set(),
            add(c) { this._set.add(c); syncClass(); },
            remove(c) { this._set.delete(c); syncClass(); },
            toggle(c, force) {
                if (force === undefined) {
                    if (this._set.has(c)) this._set.delete(c); else this._set.add(c);
                } else if (force) this._set.add(c);
                else this._set.delete(c);
                syncClass();
            },
            contains(c) { return this._set.has(c); }
        },
        setAttribute(k, v) { this.attrs[k] = String(v); },
        getAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k) ? this.attrs[k] : null; },
        hasAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k); },
        removeAttribute(k) { delete this.attrs[k]; },
        appendChild(child) {
            if (child.parentNode) child.parentNode.removeChild(child);
            child.parentNode = this;
            this.children.push(child);
            return child;
        },
        removeChild(child) {
            const idx = this.children.indexOf(child);
            if (idx >= 0) { this.children.splice(idx, 1); child.parentNode = null; }
            return child;
        },
        get firstChild() { return this.children[0] || null; },
        get childNodes() { return this.children; },
        addEventListener(evt, fn) { (this.listeners[evt] = this.listeners[evt] || []).push(fn); },
        click() { (this.listeners.click || []).forEach(fn => fn({type:'click'})); },
        querySelectorAll(sel) {
            const out = [];
            function walk(node) {
                for (const child of node.children) {
                    if (matches(child, sel)) out.push(child);
                    walk(child);
                }
            }
            walk(this);
            return out;
        },
        querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
    };
    function syncClass() {
        const base = el.className.split(/\s+/).filter(Boolean);
        for (const c of el.classList._set) if (!base.includes(c)) base.push(c);
        el.className = base.join(' ');
    }
    const origClassDesc = Object.getOwnPropertyDescriptor(el, 'className');
    let _cls = '';
    Object.defineProperty(el, 'className', {
        get() { return _cls; },
        set(v) {
            _cls = String(v || '');
            el.classList._set = new Set(_cls.split(/\s+/).filter(Boolean));
        }
    });
    function matches(node, sel) {
        if (sel.startsWith('.')) return node.classList.contains(sel.slice(1));
        if (sel.startsWith('[')) {
            const m = sel.match(/^\[([^=\]]+)(?:="([^"]*)")?\]$/);
            if (!m) return false;
            const val = node.getAttribute(m[1]);
            return m[2] === undefined ? val !== null : val === m[2];
        }
        return node.tagName.toLowerCase() === sel.toLowerCase();
    }
    return el;
}

function makeFakeDoc() {
    return { createElement: tag => makeFakeElement(tag) };
}

function fullBackpack(seq) {
    return {
        containerId:'背包', capacity:50, accessibleCapacity:50, viewCapacity:50,
        filterKey:'all', pageSizeHint:50, locked:false,
        snapshotSeq:seq || 2, containerEpoch:1, containerVersion:2, offset:0, limit:50,
        slots:Array.from({length:50}, (_, physicalSlot) => ({
            physicalSlot, slotLease:'lease.' + physicalSlot + '.' + (seq || 2),
            occupied:false, item:null
        }))
    };
}

function snapshotPayload(extra) {
    const cooldown = {ready:true, totalSteps:0, currentStep:0, progressPercent:100, animationFrame:1, remainingMs:0};
    const layout = {v:2, bankCount:2, laneCount:4, physicalSlotCount:8, activeBank:0, switchKeyLabel:'6', switchCooldown:Object.assign({}, cooldown)};
    const drugs = [];
    for (let slot = 0; slot < 8; slot++) {
        const row = Object.assign({
            slot, bank:Math.floor(slot / 4), lane:slot % 4, active:slot < 4, keyLabel:['7','8','9','0'][slot % 4],
            occupied:slot === 0, quantity:slot === 0 ? 5 : 0
        }, cooldown);
        if (slot === 0) {
            row.item = {name:'大HP药剂', displayName:'大HP药剂', icon:'hp', itemKind:'stack', majorType:'消耗品', use:'药剂', quantity:5};
        }
        drugs.push(row);
    }
    const disabled = {v:1, enabled:false, physicalSlot:-1, itemKey:'', status:'disabled'};
    const emer = (extra && extra.emergencyInjection) || disabled;
    const equipment = [
        {slotKey:'头部装备', occupied:false, item:null},
        {slotKey:'上装装备', occupied:true, item:{
            name:'统合61式胸甲', displayName:'统合61式胸甲', itemKind:'equipment',
            majorType:'防具', use:'上装装备', enhancementLevel:7, modSlotCapacity:2, modSlotUsed:1,
            icon:'chest61', emergencyInjection:emer
        }},
        {slotKey:'下装装备', occupied:false, item:null},
        {slotKey:'手部装备', occupied:false, item:null},
        {slotKey:'脚部装备', occupied:false, item:null},
        {slotKey:'颈部装备', occupied:false, item:null},
        {slotKey:'长枪', occupied:true, item:{
            name:'AK47', displayName:'AK47突击步枪', itemKind:'equipment',
            majorType:'武器', use:'长枪', enhancementLevel:10, modSlotCapacity:3, modSlotUsed:2, icon:'ak47'
        }},
        {slotKey:'手枪', occupied:false, item:null},
        {slotKey:'手枪2', occupied:false, item:null},
        {slotKey:'刀', occupied:false, item:null},
        {slotKey:'手雷', occupied:false, item:null}
    ];
    return Object.assign({
        equipment, drugs, drugLayout:layout,
        emergencyInjection:emer,
        portrait:{gender:'男', equipment:{}, appearance:{}},
        stateHealth:'ok', diagnostics:[]
    }, extra || {});
}

function createSessionFixture() {
    const sent = [];
    const router = new PanelRuntime.PanelResponseRouter();
    const mux = Transport.createRequestMux({
        send:msg => { sent.push(msg); return true; },
        router, timeoutMs:60000, sessionNonce:'standalone-test',
        setTimer:() => ({id:1}), clearTimer:() => {}
    });
    const session = new SessionModule.CharacterBuildSession({ mux });
    function respond(req, extra) {
        router.handleResponse(Object.assign({
            type:'panel_resp', panel:'workbench', domain:'loadout',
            cmd:req.cmd, callId:req.callId, panelInstanceId:'panel.workbench.9',
            v:1, success:true, writeEpoch:0, sessionGeneration:12,
            loadoutRevision:4, liveRevision:4, drugRevision:2,
            liveRefreshDirty:false, active:true
        }, extra || {}));
    }
    return {sent, router, session, respond};
}

check('CharacterBuildSession.subscribe delivers opened/snapshot/mutation events and unsubscribes cleanly', function() {
    const f = createSessionFixture();
    const seen = [];
    const offOpen = f.session.subscribe('opened', () => seen.push('opened'));
    const offSnap = f.session.subscribe('snapshot', () => seen.push('snapshot'));
    const offMut = f.session.subscribe('mutation_success', () => seen.push('mutation_success'));
    f.session.open('panel.workbench.9');
    f.respond(f.sent[0], {payload:snapshotPayload()});
    assert.deepStrictEqual(seen, ['opened']);
    f.session.refreshSnapshot();
    f.respond(f.sent[1], {payload:snapshotPayload()});
    assert.deepStrictEqual(seen, ['opened', 'snapshot']);
    offSnap();
    f.session.refreshSnapshot();
    f.respond(f.sent[2], {payload:snapshotPayload()});
    assert.deepStrictEqual(seen, ['opened', 'snapshot'], 'unsubscribed snapshot callback must not fire');
    f.session.configureEmergencyInjection({kind:'loadout', slotKey:'上装装备', expectedLoadoutRevision:4}, true, 0, '大HP药剂');
    const auth = {v:1, enabled:true, physicalSlot:0, itemKey:'大HP药剂', status:'authorized'};
    f.respond(f.sent[3], {
        writeEpoch:1, drugRevision:3, changed:true, operation:'configureEmergencyInjection',
        affectedBackpackSlot:-1, inventorySnapshots:[fullBackpack(2)],
        payload:snapshotPayload({emergencyInjection:auth, targetEmergencyInjection:auth})
    });
    assert.deepStrictEqual(seen, ['opened', 'snapshot', 'mutation_success']);
    offOpen();
    offMut();
    f.session.destroy();
});

check('standalone loadout tuning switches 背包/已穿戴, selects worn gear, decorates completeWrite/tooltip, and unlocks 61 customization', function() {
    const doc = makeFakeDoc();
    const f = createSessionFixture();
    const titleRow = makeFakeElement('div');
    const toolbar = makeFakeElement('div');
    const gridRoot = makeFakeElement('div');
    const paneBody = makeFakeElement('div');
    paneBody.appendChild(gridRoot);
    const backpackRoot = makeFakeElement('section');
    backpackRoot.appendChild(titleRow);
    backpackRoot.appendChild(toolbar);
    backpackRoot.appendChild(paneBody);
    const backpackView = {root:backpackRoot, chrome:{titleRow, toolbar}, renderer:{root:gridRoot}};

    let acquireCalls = 0;
    let pendingAcquireCb = null;
    const tooltipBindings = [];
    const fakeTooltip = {
        createScope() {
            return {
                bindAsync(node, opts) { tooltipBindings.push({node, opts}); return {release() {}}; },
                releaseTree() {},
                dispose() {}
            };
        }
    };
    const writeCalls = [];
    const controller = LoadoutTuning.create({
        document:doc,
        acquireLoadoutSession:cb => { acquireCalls++; pendingAcquireCb = cb; return true; },
        beginWrite:owner => ({owner}),
        completeWrite:(op, snapshots, cb, needsRefresh) => { writeCalls.push({op, snapshots, needsRefresh}); if (cb) cb({success:true}); return true; },
        iconHtml:(name) => '<i>' + name + '</i>',
        toast:() => {},
        tooltip:() => fakeTooltip
    });

    const baseCompleteCalls = [];
    const baseTooltipCalls = [];
    const opts = controller.decorateOptions({
        completeWrite:(op, needsRefresh, cb, snapshots) => { baseCompleteCalls.push({op, needsRefresh, snapshots}); if (cb) cb({success:true}); return true; },
        bindSourceTooltip:(node, item, source) => { baseTooltipCalls.push({node, item, source}); return 'bag-tt'; }
    });

    const selectedLoadout = [];
    let clearedCount = 0;
    let currentDebug = {source:null};
    const tuningView = {
        canClose:() => true,
        debugState:() => currentDebug,
        clearSelection:() => { clearedCount++; currentDebug = {source:null}; return true; },
        handleLoadoutSelection:(source, item) => {
            selectedLoadout.push({source, item});
            currentDebug = {source};
            return true;
        },
        refreshCustomizationSnapshot:() => {}
    };

    // Attach in storage mode: switch hidden, no eager session open
    assert.strictEqual(controller.attach({backpackView, tuningView, viewMode:'storage'}), true);
    assert.strictEqual(acquireCalls, 0);
    assert.strictEqual(titleRow.querySelector('.inventory-tuning-source-switch').hidden, true);

    // Enter tuning mode: switcher visible, session acquired once
    controller.onViewMode('tuning');
    assert.strictEqual(acquireCalls, 1);
    assert.strictEqual(titleRow.querySelector('.inventory-tuning-source-switch').hidden, false);

    // Open headless session & resolve
    f.session.open('panel.workbench.9');
    f.respond(f.sent[0], {payload:snapshotPayload()});
    pendingAcquireCb({session:f.session, generation:12, panelInstanceId:'panel.workbench.9', headless:true});

    // Switch left source to 已穿戴
    assert.strictEqual(controller.switchLeftSource('equipped'), true);
    assert.strictEqual(gridRoot.hidden, true);
    assert.strictEqual(toolbar.hidden, true);
    const loadoutPane = paneBody.querySelector('.inventory-tuning-loadout-pane');
    assert.strictEqual(loadoutPane.hidden, false);
    const cards = loadoutPane.querySelectorAll('.inventory-tuning-loadout-card');
    assert.strictEqual(cards.length, 11, 'must render all 11 armor + weapon slots');
    const longGunCard = cards.find(c => c.getAttribute('data-slot-protocol-key') === '长枪');
    const headCard = cards.find(c => c.getAttribute('data-slot-protocol-key') === '头部装备');
    assert.strictEqual(longGunCard.disabled, false);
    assert.strictEqual(headCard.disabled, true);

    // Click worn AK47 card -> routes to tuningView.handleLoadoutSelection
    longGunCard.click();
    assert.strictEqual(selectedLoadout.length, 1);
    assert.strictEqual(selectedLoadout[0].source.sourceKind, 'loadout');
    assert.strictEqual(selectedLoadout[0].source.slotKey, '长枪');
    assert.strictEqual(selectedLoadout[0].source.sessionGeneration, 12);
    assert.strictEqual(selectedLoadout[0].source.expectedLoadoutRevision, 4);
    assert(longGunCard.classList.contains('equipment-tuning-authority-source'));

    // Decorated completeWrite forwards snapshots receipt directly
    opts.completeWrite({id:1}, false, null, [{containerId:'背包', slots:[]}]);
    assert.strictEqual(Array.isArray(baseCompleteCalls[0].snapshots), true);
    opts.completeWrite({id:2}, false, null, null);
    assert.strictEqual(baseCompleteCalls[1].snapshots, null);

    // Decorated bindSourceTooltip separates loadout vs inventory & exposes renderFailure
    const bagNode = makeFakeElement('div');
    assert.strictEqual(opts.bindSourceTooltip(bagNode, {name:'x'}, {sourceKind:'inventory', containerId:'背包', slot:0}), 'bag-tt');
    assert.strictEqual(baseTooltipCalls.length, 1);
    const ttBefore = tooltipBindings.length;
    opts.bindSourceTooltip(makeFakeElement('div'), {name:'AK47', displayName:'AK47突击步枪'}, selectedLoadout[0].source);
    assert.strictEqual(tooltipBindings.length, ttBefore + 1);
    assert.strictEqual(typeof tooltipBindings[tooltipBindings.length - 1].opts.renderFailure, 'function');
    assert.strictEqual(baseTooltipCalls.length, 1, 'loadout tooltip must not call backpack tooltip');

    // Switching back to 背包 clears hidden worn source so hidden item cannot stay armed
    assert.strictEqual(controller.switchLeftSource('backpack'), true);
    assert.strictEqual(clearedCount, 1);
    assert.strictEqual(controller.switchLeftSource('equipped'), true);

    // Type-61 customization available for both worn and backpack chestplates
    const chestWorn = {name:'统合61式胸甲', displayName:'统合61式胸甲', use:'上装装备'};
    const chestBag = {name:'钛合金61式胸甲', displayName:'钛合金61式胸甲', use:'上装装备'};
    assert.strictEqual(opts.customization.isAvailable({sourceKind:'loadout', slotKey:'上装装备'}, chestWorn), true);
    assert.strictEqual(opts.customization.isAvailable({sourceKind:'inventory', containerId:'背包', slot:3, expectedLease:'L3'}, chestBag), true);
    assert.strictEqual(opts.customization.isAvailable({sourceKind:'loadout', slotKey:'长枪'}, {name:'AK47', use:'长枪'}), false);

    // Render customization & toggle drug slot 0 on worn 61 chestplate
    const rendered = opts.customization.render({
        document:doc,
        source:{sourceKind:'loadout', slotKey:'上装装备', sessionGeneration:12, expectedLoadoutRevision:4},
        item:chestWorn
    });
    assert.strictEqual(rendered.body.querySelectorAll('.cb-mech-tile').length, 8);
    assert.strictEqual(opts.customization.toggleSlot(0), true);
    assert.strictEqual(controller.canClose(), false, 'pending 61 customization mutation must block close');
    const cfgReq = f.sent.find(m => m.cmd === 'configureEmergencyInjection');
    assert(cfgReq, 'toggleSlot must send configureEmergencyInjection');
    assert.strictEqual(cfgReq.payload.enabled, true);
    assert.strictEqual(cfgReq.payload.drugSlot, 0);
    const auth = {v:1, enabled:true, physicalSlot:0, itemKey:'大HP药剂', status:'authorized'};
    f.respond(cfgReq, {
        writeEpoch:1, drugRevision:3, changed:true, operation:'configureEmergencyInjection',
        affectedBackpackSlot:-1, inventorySnapshots:[fullBackpack(2)],
        payload:snapshotPayload({emergencyInjection:auth, targetEmergencyInjection:auth})
    });
    assert.strictEqual(controller.canClose(), true, 'settled mutation unlocks close');
    assert.strictEqual(writeCalls.length, 1);

    // Return to storage resets leftSource back to backpack
    controller.onViewMode('storage');
    assert.strictEqual(gridRoot.hidden, false);
    assert.strictEqual(loadoutPane.hidden, true);
    assert.strictEqual(controller.debugState().leftSource, 'backpack');
    controller.destroy();
    f.session.destroy();
});

check('graceful degradation when loadout session fails keeps backpack tuning usable', function() {
    const doc = makeFakeDoc();
    const titleRow = makeFakeElement('div');
    const toolbar = makeFakeElement('div');
    const gridRoot = makeFakeElement('div');
    const paneBody = makeFakeElement('div');
    paneBody.appendChild(gridRoot);
    const root = makeFakeElement('section');
    root.appendChild(titleRow); root.appendChild(toolbar); root.appendChild(paneBody);

    const controller = LoadoutTuning.create({
        document:doc,
        acquireLoadoutSession:cb => { cb(null); return true; }
    });
    const opts = controller.decorateOptions({});
    controller.attach({
        backpackView:{root, chrome:{titleRow, toolbar}, renderer:{root:gridRoot}},
        tuningView:{canClose:() => true, debugState:() => ({source:null})},
        viewMode:'tuning'
    });
    assert.strictEqual(controller.debugState().sessionState, 'unavailable');
    assert.strictEqual(opts.customization.isAvailable({sourceKind:'inventory', slot:0}, {name:'统合61式胸甲'}), false);
    controller.switchLeftSource('equipped');
    const emptyMsg = paneBody.querySelector('.inventory-tuning-loadout-empty');
    assert(emptyMsg, 'unavailable loadout session must render retry fallback');
    controller.switchLeftSource('backpack');
    assert.strictEqual(gridRoot.hidden, false);
    controller.destroy();
});

process.stdout.write('Standalone loadout tuning: ' + passed + ' checks passed\n');
