#!/usr/bin/env node
'use strict';
const assert=require('assert'),M=require('./manual-observation'),P=require('./preflight');
function fixture(){
    const calls=[],identity={runtimeMode:'candidate',pid:7001,httpPort:18080};
    const status={success:true,save:{slot:P.TARGET_SLOT,attemptId:'attempt'},
        saveRuntime:{savePath:P.TARGET_SLOT,attemptId:'attempt'},gameEnteredAttemptId:'attempt',
        readyForRuntimeAutomation:true,activePanel:{name:'bookshelf',token:'must-not-leak'}};
    return {calls,status,runtime:{identity,expectedIdentity:{fixture:true},ready:{expectedAttemptId:'attempt'},
        session:{verifyRuntimeIdentity(){calls.push('identity');return {...identity};},
            async agentControl(action){calls.push(action);return status;}}}};
}
(async()=>{
    let passed=0;
    async function test(name,fn){await fn();passed++;console.log('PASS '+name);}
    await test('only reads status between exact identity checks',async()=>{
        const f=fixture(),s=await M.snapshot(f);assert.deepStrictEqual(f.calls,['identity','status','identity']);
        assert.equal(s.inputSent,false);assert.equal(s.physicalInputAttestation,false);
        assert(Object.values(s.gameplay).every(v=>v==='unknown'));assert(!JSON.stringify(s).includes('must-not-leak'));
    });
    for(const [name,mutate] of [
        ['foreign launch slot',f=>f.status.save.slot='crazyflasher7_saves'],
        ['foreign launch attempt',f=>f.status.save.attemptId='foreign'],
        ['foreign loaded attempt',f=>f.status.saveRuntime.attemptId='foreign'],
        ['unadmitted subsidiary slot',f=>f.status.saveRuntime.savePath='bookrun_'+'a'.repeat(24)],
        ['unsuccessful status',f=>f.status.success=false],
        ['changed process identity',f=>f.runtime.session.verifyRuntimeIdentity=()=>({runtimeMode:'candidate',pid:7002,httpPort:18080})]
    ])await test(name+' rejected',async()=>{const f=fixture();mutate(f);await assert.rejects(()=>M.snapshot(f));});
    await test('PID change during status is rejected',async()=>{const f=fixture();let n=0;
        f.runtime.session.verifyRuntimeIdentity=()=>({...f.runtime.identity,pid:++n===1?7001:7002});await assert.rejects(()=>M.snapshot(f));});
    console.log('CF6 manual observation offline cases: '+passed+'/'+passed);
})().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
