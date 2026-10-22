'use strict';
const assert=require('assert');
const {observeVerifiedReturn}=require('./verified-return-observation');
const origin='cf7_agent_cf6_sting_20261021',slot='bookrun_'+'a'.repeat(24);
function fixture(){
    const before={'0':['Andy','男',500,60,157526193,175,0],inventory:{bag:{name:'kept'}}};
    const after=JSON.parse(JSON.stringify(before));
    after.ext={bookshelf:{lastRun:slot,routes:{'cf6-sting.historical':{
        history:[{runId:slot,bookId:'cf6-sting',routeId:'historical',sp:0,outcome:'retreat'}]}}}};
    const calls=[];
    return {before,after,slot,originSlot:origin,calls,
        receipt:{phase:'applied',activeSlot:origin,result:{runId:slot,bookId:'cf6-sting',sp:0}},
        input:{screenshot:async()=>{calls.push('screenshot');return {file:'cf6-returned.png'};},
            click:()=>{throw Error('post-return observation must not click any business/UI action');}},
        detach:async()=>{calls.push('detach');}};
}
async function main(){
    let passed=0;
    let f=fixture(),r=await observeVerifiedReturn(f);
    assert.equal(r.result.outcome,'retreat');assert.equal(r.warnings.length,0);
    assert.deepStrictEqual(f.calls,['screenshot','detach']);passed++;
    f=fixture();f.input.screenshot=async()=>{throw Error('CDP WebSocket closed');};
    r=await observeVerifiedReturn(f);
    assert.equal(r.screenshot,null);assert.equal(r.warnings[0].phase,'return_screenshot');
    assert.deepStrictEqual(f.calls,['detach']);assert.equal(r.result.originAssetsUnchanged,true);passed++;
    f=fixture();f.detach=async()=>{throw Error('CDP WebSocket closed');};
    r=await observeVerifiedReturn(f);assert.equal(r.warnings[0].phase,'observer_detach');passed++;
    for(const mutate of [f=>f.receipt.phase='save_pending',f=>f.receipt.result.runId='foreign',
        f=>f.receipt.activeSlot='foreign',f=>f.receipt.result.sp=1,f=>f.receipt.result.bookId='other',
        f=>f.after['0'][2]++,f=>f.after.ext.bookshelf.routes['cf6-sting.historical'].history[0].outcome='active']){
        f=fixture();mutate(f);await assert.rejects(()=>observeVerifiedReturn(f));
        assert.deepStrictEqual(f.calls,[]);passed++;
    }
    console.log('Verified return observation: '+passed+'/'+passed+' passed; no process/save mutation in fixtures');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
