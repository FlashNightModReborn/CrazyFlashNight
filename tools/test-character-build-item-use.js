'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const PanelRuntime = require(
    '../launcher/web/modules/panel-runtime.js');
const ItemUse = require(
    '../launcher/web/modules/character-build/character-build-item-use.js');
const ItemUseChannel = require(
    '../launcher/web/modules/character-build/character-build-item-use-channel.js');
const CandidateChannel = require(
    '../launcher/web/modules/character-build/character-build-candidate-channel.js');
const CharacterBuildView = require(
    '../launcher/web/modules/character-build-view.js').CharacterBuildView;

let passed = 0;
function check(name, callback) {
    callback();
    passed++;
    process.stdout.write('PASS ' + name + '\n');
}

function candidate(command) {
    return {
        name:command === 'open' ? '福袋' : '加强抗生素药剂',
        useAction:{command:command,label:command === 'open' ? '打开' : '服用'},
        raw:{
            physicalSlot:4,
            item:{name:command === 'open' ? '福袋' : '加强抗生素药剂'},
            // Existing loadout source remains untouched and must not authorize use.
            source:{containerId:'背包',slot:4,expectedLease:'equip.lease'},
            useAction:{
                command:command,
                label:command === 'open' ? '打开' : '服用',
                source:{
                    physicalSlot:4,
                    slotLease:'use.lease.4',
                    itemName:command === 'open' ? '福袋' : '加强抗生素药剂',
                    backpackVersion:9
                }
            }
        }
    };
}

function harness() {
    const sent = [];
    const router = new PanelRuntime.PanelResponseRouter();
    const settled = [];
    const inbox = [];
    const cooldowns = [];
    const controller = new ItemUse.Controller({
        send:message => { sent.push(message); return true; },
        router:router,
        operationNonce:'test',
        setTimer:() => ({timer:true}),
        clearTimer:() => {},
        onSettled:(response, committed, pending) => settled.push({response,committed,pending}),
        onInbox:value => inbox.push(value),
        onCooldown:value => cooldowns.push(value)
    });
    assert.strictEqual(controller.bind('panel.workbench.1', 7), true);
    return {controller,router,sent,settled,inbox,cooldowns};
}

function cooldownLanes(activeLane) {
    return [0,1,2,3].map(lane => {
        const ready = lane !== activeLane;
        return {
            lane:lane,ready:ready,totalSteps:ready?0:90,
            currentStep:ready?0:30,progressPercent:ready?0:33,
            animationFrame:ready?1:34,remainingMs:ready?0:2000
        };
    });
}

function allCoolingLanes(readyLane) {
    return [0,1,2,3].map(lane => {
        const ready = lane === readyLane;
        return {
            lane:lane,ready:ready,totalSteps:ready?0:90,
            currentStep:ready?0:30,progressPercent:ready?0:33,
            animationFrame:ready?1:34,remainingMs:ready?0:2000
        };
    });
}

function respond(run, request, fields) {
    const response = Object.assign({
        type:'panel_resp', panel:'workbench', domain:'item_use',
        cmd:request.cmd, callId:request.callId,
        panelInstanceId:'panel.workbench.1'
    }, fields);
    assert.strictEqual(run.router.handleResponse(response), true);
}

function button() {
    return {
        hidden:false,
        disabled:false,
        textContent:'',
        attributes:{},
        setAttribute:function(name, value) { this.attributes[name] = String(value); },
        removeAttribute:function(name) { delete this.attributes[name]; }
    };
}

check('exact source comes only from the dedicated item-use capability', function() {
    assert.deepStrictEqual(ItemUse.exactSource(candidate('open')), {
        physicalSlot:4,
        slotLease:'use.lease.4',
        itemName:'福袋',
        backpackVersion:9
    });
    const invalid = candidate('open');
    delete invalid.raw.useAction.source;
    assert.strictEqual(ItemUse.exactSource(invalid), null);
});

check('open sends the exact workbench item_use envelope and settles once', function() {
    const run = harness();
    assert(run.controller.invoke(candidate('open')));
    assert.strictEqual(run.sent.length, 1);
    const request = run.sent[0];
    assert.deepStrictEqual({
        type:request.type,panel:request.panel,domain:request.domain,cmd:request.cmd,
        panelInstanceId:request.panelInstanceId
    }, {
        type:'panel',panel:'workbench',domain:'item_use',cmd:'open',
        panelInstanceId:'panel.workbench.1'
    });
    assert.deepStrictEqual(request.payload.source, {
        physicalSlot:4,slotLease:'use.lease.4',itemName:'福袋',backpackVersion:9
    });
    assert.strictEqual(request.payload.sessionGeneration, 7);
    respond(run, request, {
        success:true, command:'open', operationId:request.payload.operationId,
        rewardReady:true, consumed:1, remaining:0,
        inboxSummary:{v:1,batchCount:1,remainingCount:2,capacity:64,authorityRevision:1},
        rewardAuthority:{sourceKind:'reward_inbox',openAttemptSeq:1}
    });
    assert.strictEqual(run.settled.length, 1);
    assert.strictEqual(run.settled[0].committed, true);
    assert.strictEqual(run.controller.debugState().state, 'idle');
});

check('unknown write issues only a same-operation query and never replays consume', function() {
    const run = harness();
    run.controller.invoke(candidate('consume'));
    const write = run.sent[0];
    respond(run, write, {
        success:false,error:'reconcile_required',requiresReconcile:true,
        command:'consume',operationId:write.payload.operationId
    });
    assert.strictEqual(run.sent.length, 2);
    const query = run.sent[1];
    assert.strictEqual(query.cmd, 'query');
    assert.strictEqual(query.payload.operationId, write.payload.operationId);
    assert.strictEqual(run.sent.filter(message => message.cmd === 'consume').length, 1);
    respond(run, query, {
        success:true,found:true,command:'query',operationId:write.payload.operationId,
        receipt:{kind:'consume',status:'committed',consumed:1,remaining:2,selectedLane:3},
        inboxSummary:{v:1,batchCount:0,remainingCount:0,capacity:64,authorityRevision:0}
    });
    assert.strictEqual(run.settled.length, 1);
    assert.strictEqual(run.settled[0].committed, true);
    assert.strictEqual(run.settled[0].pending.command, 'consume');
});

check('definitive query not-found returns idle without replay', function() {
    const run = harness();
    run.controller.invoke(candidate('open'));
    const write = run.sent[0];
    respond(run, write, {
        success:false,error:'client_timeout',requiresReconcile:true,
        command:'open',operationId:write.payload.operationId
    });
    const query = run.sent[1];
    respond(run, query, {
        success:true,found:false,command:'query',operationId:write.payload.operationId,
        inboxSummary:{v:1,batchCount:0,remainingCount:0,capacity:64,authorityRevision:0}
    });
    assert.strictEqual(run.settled[0].committed, false);
    assert.strictEqual(run.settled[0].response.error, 'not_committed');
    assert.strictEqual(run.sent.filter(message => message.cmd === 'open').length, 1);
    assert.strictEqual(run.controller.debugState().state, 'idle');
});

check('inboxSnapshot caches a complete summary and available reward authority', function() {
    const run = harness();
    run.controller.refreshInbox();
    const request = run.sent[0];
    assert.strictEqual(request.cmd, 'inboxSnapshot');
    respond(run, request, {
        success:true,command:'inboxSnapshot',
        rewardReady:true,
        inboxSummary:{v:1,batchCount:2,remainingCount:5,capacity:64,authorityRevision:4},
        rewardAuthority:{sourceKind:'reward_inbox',openAttemptSeq:2}
    });
    assert.strictEqual(run.inbox.length, 1);
    assert.strictEqual(run.controller.debugState().inboxRemaining, 5);
});

check('empty or temporarily unavailable inbox keeps its summary without authority', function() {
    const run = harness();
    run.controller.refreshInbox();
    let request = run.sent[0];
    respond(run, request, {
        success:true,command:'inboxSnapshot',rewardReady:false,
        inboxSummary:{v:1,batchCount:0,remainingCount:0,capacity:64,authorityRevision:0},
        rewardAuthority:null
    });
    assert.strictEqual(run.inbox.length, 1);
    assert.strictEqual(run.inbox[0].authority, null);
    assert.strictEqual(run.controller.debugState().inboxRemaining, 0);

    run.controller.refreshInbox();
    request = run.sent[1];
    respond(run, request, {
        success:true,command:'inboxSnapshot',rewardReady:true,
        inboxSummary:{v:1,batchCount:1,remainingCount:3,capacity:64,authorityRevision:2},
        rewardAuthority:null
    });
    assert.strictEqual(run.inbox.length, 2);
    assert.strictEqual(run.inbox[1].authority, null);
    assert.strictEqual(run.controller.debugState().inboxRemaining, 3);
});

check('cooldownSnapshot accepts exactly four ordered read-only lanes', function() {
    const run = harness();
    run.controller.refreshCooldowns();
    const request = run.sent[0];
    assert.strictEqual(request.cmd, 'cooldownSnapshot');
    respond(run, request, {
        success:true,command:'cooldownSnapshot',cooldownLanes:cooldownLanes(2)
    });
    assert.strictEqual(run.cooldowns.length, 1);
    assert.strictEqual(run.cooldowns[0][2].remainingMs, 2000);
    assert.strictEqual(run.controller.debugState().cooldownActive, true);

    const malformed = cooldownLanes(1);
    malformed[3].lane = 2;
    assert.strictEqual(ItemUse.normalizeCooldownLanes(malformed), null);
    malformed[3].lane = 3;
    malformed[1].animationFrame = 99;
    assert.strictEqual(ItemUse.normalizeCooldownLanes(malformed), null);
});

check('cooldown shade overlays both physical slots of the selected shared lane', function() {
    function slotNode(lane) {
        return {
            attributes:{
                'data-drug-lane':String(lane),
                'aria-label':'药剂槽，冷却就绪'
            },
            style:{values:{},setProperty:function(key,value) {
                this.values[key]=String(value);
            }},
            setAttribute:function(key,value){this.attributes[key]=String(value);},
            getAttribute:function(key){return this.attributes[key] || null;}
        };
    }
    const nodes=[0,1,2,3,0,1,2,3].map(slotNode);
    function Controller() {}
    ItemUseChannel.install(Controller.prototype);
    const controller=new Controller();
    controller._view={root:{querySelectorAll:function(){return nodes;}}};
    const rows=cooldownLanes(2);
    rows.forEach(row=>{row.keyLabel=String(7+row.lane);});
    controller._itemUseCooldownChanged(rows);
    assert.strictEqual(controller._noteItemUseCooldownLane(2),true);
    controller._itemUseCooldownChanged(rows);
    assert.strictEqual(nodes[2].attributes['data-drug-state'],'cooling');
    assert.strictEqual(nodes[6].attributes['data-drug-state'],'cooling');
    assert.strictEqual(nodes[2].attributes['data-recent'],'true');
    assert.strictEqual(nodes[6].attributes['data-recent'],'true');
    assert.strictEqual(nodes[2].style.values['--drug-cooldown-progress'],'33%');
    assert.strictEqual(nodes[6].style.values['--drug-cooldown-progress'],'33%');
    assert.match(nodes[2].attributes['aria-label'],/冷却中，已完成 33%$/);
    assert.strictEqual(nodes[0].attributes['data-drug-ready'],'true');
});

check('cooldown feedback stays inside drug tiles without adding a layout row', function() {
    const root = path.resolve(__dirname, '..');
    const template = fs.readFileSync(path.join(root,
        'launcher/web/modules/character-build/character-build-template.js'), 'utf8');
    const css = fs.readFileSync(path.join(root,
        'launcher/web/css/workbench/loadout-picker.css'), 'utf8');
    assert.doesNotMatch(template, /character-build-cooldown-strip/);
    assert.doesNotMatch(css, /character-build-cooldown-strip/);
});

check('first ready lane refreshes a cooldown-blocked overview exactly once', function() {
    function Controller() {}
    ItemUseChannel.install(Controller.prototype);
    const controller = new Controller();
    const blocked = candidate('consume');
    blocked.raw.useBlockedReason = 'no_available_lane';
    blocked.useBlockedReason = '四条药剂通道当前都不能承接。';
    let refreshes = 0;
    controller._session = {getState:function() { return 'idle'; }};
    controller._itemUse = {debugState:function() { return {state:'idle'}; }};
    controller._selectedCandidate = blocked;
    controller._candidateCache = {stale:true};
    controller._view = {
        root:{querySelectorAll:function() { return []; }},
        debugState:function() {
            return {candidateScope:'backpack',selectedSlotKey:''};
        },
        getCandidates:function() { return [blocked]; },
        captureItemUseFocus:function() { return 'action'; },
        showBackpackOverview:function() { refreshes++; return true; }
    };
    assert.strictEqual(controller._itemUseCooldownChanged(
        allCoolingLanes(-1)), true);
    assert.strictEqual(refreshes, 0);
    assert.strictEqual(controller._itemUseCooldownChanged(
        allCoolingLanes(1)), true);
    assert.strictEqual(refreshes, 1);
    assert.strictEqual(controller._candidateCache, null);
    assert.strictEqual(controller._itemUseResumeSelection.physicalSlot, 4);
    assert.strictEqual(controller._itemUseResumeSelection.itemName,
        '加强抗生素药剂');
    assert.strictEqual(controller._itemUseResumeSelection.focusMode, 'action');
    controller._itemUseCooldownChanged(allCoolingLanes(2));
    assert.strictEqual(refreshes, 1);
});

check('busy user slot clicks are ignored without wrapping programmatic slot selection', function() {
    const selections = [];
    const view = {
        _interactionState:'write_pending',
        _selectSlot:function(key, reason) {
            selections.push({key:key,reason:reason});
            return true;
        }
    };
    assert.strictEqual(
        CharacterBuildView.prototype._selectUserSlot.call(view, 'drug:drug1', 'click'),
        false);
    assert.deepStrictEqual(selections, []);
    // Session restore and other programmatic callers continue to use _selectSlot directly.
    assert.strictEqual(view._selectSlot('drug:drug1', 'restore'), true);
    assert.strictEqual(selections.length, 1);
    view._interactionState = 'idle';
    assert.strictEqual(
        CharacterBuildView.prototype._selectUserSlot.call(view, 'drug:drug2', 'click'),
        true);
    assert.deepStrictEqual(selections[1], {key:'drug:drug2',reason:'click'});
});

check('item-use button names write and query progress for the selected action', function() {
    const use = button();
    const inbox = button();
    const view = {
        _useButton:use,
        _inboxButton:inbox,
        _selectedUseCandidate:{
            name:'加强抗生素药剂',
            useAction:{command:'consume',label:'服用'}
        },
        _itemUseState:'write_pending',
        _interactionState:'write_pending',
        _inboxSummary:null,
        root:{querySelector:function() { return null; }}
    };
    CharacterBuildView.prototype._syncItemUseActions.call(view);
    assert.strictEqual(use.textContent, '正在服用…');
    assert.strictEqual(use.disabled, true);
    assert.match(use.attributes['aria-label'], /^正在服用/);
    view._itemUseState = 'query_pending';
    CharacterBuildView.prototype._syncItemUseActions.call(view);
    assert.strictEqual(use.textContent, '正在确认服用…');
    view._selectedUseCandidate = {
        name:'福袋',
        useAction:{command:'open',label:'打开'}
    };
    view._itemUseState = 'write_pending';
    CharacterBuildView.prototype._syncItemUseActions.call(view);
    assert.strictEqual(use.textContent, '正在打开…');
});

check('inline success survives the automatic candidate refresh until the next user slot action', function() {
    const notice = {
        textContent:'',
        attributes:{},
        setAttribute:function(name, value) { this.attributes[name] = String(value); }
    };
    const selections = [];
    const view = {
        _destroyed:false,
        _notice:notice,
        _itemUseResultNotice:'',
        _interactionState:'idle',
        _showStatusNotice:CharacterBuildView.prototype._showStatusNotice,
        _selectSlot:function(key) { selections.push(key); return true; }
    };
    assert.strictEqual(CharacterBuildView.prototype.showItemUseResult.call(
        view, '已服用「加强抗生素药剂」。'), true);
    CharacterBuildView.prototype._showBrowsingNotice.call(view, '候选与数量已同步。');
    assert.strictEqual(notice.textContent, '已服用「加强抗生素药剂」。');
    assert.strictEqual(notice.attributes['data-notice-kind'], 'success');
    assert.strictEqual(CharacterBuildView.prototype._selectUserSlot.call(
        view, 'drug:drug1', 'click'), true);
    CharacterBuildView.prototype._showBrowsingNotice.call(view, '正在读取槽位。');
    assert.strictEqual(notice.textContent, '正在读取槽位。');
    assert.strictEqual(notice.attributes['data-notice-kind'], 'browsing');
    assert.deepStrictEqual(selections, ['drug:drug1']);
});

check('committed consume publishes an inline result after refreshed snapshot', function() {
    const order = [];
    const toasts = [];
    const controller = {
        _ports:{toast:function(message) { toasts.push(message); }},
        _session:{refreshSnapshot:function(callback) {
            order.push('refresh');
            callback({payload:{version:10}}, true);
            return 'snapshot.1';
        }},
        _view:{
            setInboxSummary:function() { return true; },
            showItemUseResult:function(message) {
                order.push('notice:' + message);
                return true;
            }
        },
        _applySnapshot:function() { order.push('snapshot'); },
        _candidateCache:{old:true},
        _rewardAuthority:null,
        _itemUseInboxChanged:function() {}
    };
    ItemUseChannel.install(controller);
    controller._itemUseSettled({
        success:true,selectedLane:2,remaining:4
    }, true, {
        command:'consume',candidate:{name:'加强抗生素药剂'}
    });
    assert.deepStrictEqual(order, [
        'refresh',
        'snapshot',
        'notice:已服用「加强抗生素药剂」；通道 3 进入冷却（背包剩余 4）。'
    ]);
    assert.deepStrictEqual(toasts, [
        '已服用「加强抗生素药剂」；通道 3 进入冷却（背包剩余 4）。'
    ]);
    assert.strictEqual(controller._candidateCache, null);
});

check('committed open reports the reward transfer before inbox navigation', function() {
    const order = [];
    const controller = {
        _ports:{},
        _session:{refreshSnapshot:function(callback) {
            callback({payload:{}}, true);
            return 'snapshot.2';
        }},
        _view:{
            setInboxSummary:function() { return true; },
            showItemUseResult:function(message) {
                order.push('notice:' + message);
                return true;
            }
        },
        _applySnapshot:function() { order.push('snapshot'); },
        _candidateCache:null,
        _rewardAuthority:null,
        _itemUseInboxChanged:function() {}
    };
    ItemUseChannel.install(controller);
    controller._openRewardInbox = function() { order.push('inbox'); return true; };
    controller._itemUseSettled({
        success:true,rewardReady:true,
        inboxSummary:{remainingCount:3}
    }, true, {
        command:'open',candidate:{name:'福袋'}
    });
    assert.deepStrictEqual(order, [
        'snapshot',
        'notice:已打开「福袋」；奖励已转入待领取（当前 3 件）。',
        'inbox'
    ]);
});

check('post-consume reselection adopts only the fresh same-slot lease', function() {
    function Controller() {}
    CandidateChannel.install(Controller.prototype);
    const controller = new Controller();
    const restored = [];
    controller._itemUseResumeSelection = {
        physicalSlot:4,
        itemName:'加强抗生素药剂',
        focusMode:'action',
        requestKey:'overview.2'
    };
    controller._view = {
        restoreItemUseCandidate:function(value, focusMode) {
            restored.push({value:value,focusMode:focusMode});
            return true;
        }
    };
    const fresh = candidate('consume');
    fresh.key = 'backpack:4:fresh.lease.4';
    fresh.physicalSlot = 4;
    fresh.raw.source.expectedLease = 'fresh.lease.4';
    fresh.raw.useAction.source.slotLease = 'fresh.use.lease.4';
    assert.strictEqual(controller._restoreItemUseCandidate(
        [fresh], 'overview.2'), true);
    assert.strictEqual(restored.length, 1);
    assert.strictEqual(restored[0].value.raw.useAction.source.slotLease,
        'fresh.use.lease.4');
    assert.strictEqual(restored[0].focusMode, 'action');
    assert.strictEqual(controller._itemUseResumeSelection, null);

    controller._itemUseResumeSelection = {
        physicalSlot:4,itemName:'加强抗生素药剂',
        focusMode:'candidate',requestKey:'overview.3'
    };
    const replaced = candidate('consume');
    replaced.raw.item.name = '另一种药剂';
    assert.strictEqual(controller._restoreItemUseCandidate(
        [replaced], 'overview.3'), false);
    assert.strictEqual(restored.length, 1);
    assert.strictEqual(controller._itemUseResumeSelection, null);
});

process.stdout.write(
    'Character Build item use: ' + passed + '/' + passed + ' passed\n');
