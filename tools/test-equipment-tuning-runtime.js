#!/usr/bin/env node
'use strict';

const assert = require('assert');
const {RequestMux, isAmbiguous, safeToken} = require('../launcher/web/modules/equipment-tuning-runtime.js');

const sent = [];
const timers = [];
const mux = new RequestMux({
  sessionNonce:'runtime-test', timeoutMs:100,
  send(message){ sent.push(message); return true; },
  setTimer(callback){ const timer={callback,cleared:false}; timers.push(timer); return timer; },
  clearTimer(timer){ timer.cleared=true; }
});

assert.strictEqual(mux.openSession('panel.1','view.1'),true);
let response = null;
const callId = mux.request('snapshot',{source:{containerId:'背包',slot:1,expectedLease:'lease.1'}},value=>{ response=value; });
assert.ok(/^tune\.runtime-test\.1\.1$/.test(callId));
assert.deepStrictEqual(Object.keys(sent[0]).sort(),['callId','cmd','domain','panel','panelInstanceId','payload','type'].sort());
assert.strictEqual(sent[0].payload.viewSessionId,'view.1');
assert.strictEqual(sent[0].payload.v,1);
assert.strictEqual(mux.handleResponse({type:'panel_resp',domain:'equipment_tuning',cmd:'snapshot',callId,
  panelInstanceId:'panel.old',viewSessionId:'view.1',success:true}),false);
assert.strictEqual(response,null);
assert.strictEqual(mux.handleResponse({type:'panel_resp',domain:'equipment_tuning',cmd:'snapshot',callId,
  panelInstanceId:'panel.1',viewSessionId:'view.1',success:true,snapshot:{}}),true);
assert.strictEqual(response.success,true);

let late = false;
const oldCall = mux.request('preview',{operation:'enhance'},()=>{ late=true; });
assert.strictEqual(mux.openSession('panel.2','view.2'),true);
assert.strictEqual(mux.handleResponse({type:'panel_resp',domain:'equipment_tuning',cmd:'preview',callId:oldCall,
  panelInstanceId:'panel.1',viewSessionId:'view.1',success:true}),false);
assert.strictEqual(late,false);

let timeout = null;
const commit = mux.request('commit',{expectedTuningToken:'token.1'},value=>{ timeout=value; });
const timer = timers[timers.length-1];
timer.callback();
assert.strictEqual(timeout.callId,commit);
assert.strictEqual(timeout.requiresReconcile,true);
assert.strictEqual(isAmbiguous(timeout),true);
assert.strictEqual(isAmbiguous({success:false,error:'material_missing'}),false);
assert.strictEqual(isAmbiguous({success:false,error:'disconnected',requiresReconcile:false}),false);
assert.strictEqual(isAmbiguous({success:false,error:'disconnected',requiresReconcile:true}),true);
const reconcileRequired = {success:false,error:'reconcile_required',requiresReconcile:true,
  reconcileAfterCallId:'tune.host.previous.unknown.1'};
assert.strictEqual(isAmbiguous(reconcileRequired),true);
assert.strictEqual(safeToken(reconcileRequired.reconcileAfterCallId),'tune.host.previous.unknown.1');

let notSent = null;
const disconnectedMux = new RequestMux({sessionNonce:'not-sent',send(){ return false; }});
assert.strictEqual(disconnectedMux.openSession('panel.3','view.3'),true);
assert.ok(disconnectedMux.request('commit',{expectedTuningToken:'token.2'},value=>{ notSent=value; }));
assert.strictEqual(notSent.error,'not_sent');
assert.strictEqual(isAmbiguous(notSent),false);

let detached = null;
const detachCall = disconnectedMux.request('detach',{},value=>{ detached=value; });
assert.ok(detachCall);
assert.strictEqual(detached.cmd,'detach');
assert.strictEqual(detached.requiresReconcile,false);

assert.strictEqual(mux.request('unknown',{},()=>{}),null);
mux.closeSession();
assert.strictEqual(mux.debugState().pendingCount,0);
console.log('Equipment tuning runtime 25/25 passed');
