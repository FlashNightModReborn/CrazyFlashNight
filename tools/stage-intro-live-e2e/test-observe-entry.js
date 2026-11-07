'use strict';
const assert=require('assert');
const {observeOwnedEntry}=require('./observe-entry');
const originSlot='cf7_agent_fixture',slot='bookrun_0123456789abcdef01234567',bookId='cf6-sting',routeId='type61';
const active={slot,bookId,originSlot},book={ext:{bookRun:{slot,bookId,originSlot,routeId}}};
const missing=()=>Object.assign(Error('not created yet'),{code:'ENOENT'});
function fixture(extra={}){let clock=0;return {originSlot,bookId,routeId,readStatus:async()=>({saveRuntime:{loaded:true,savePath:originSlot}}),readOrigin:()=>({ext:{bookshelf:{active}}}),readBook:()=>book,now:()=>clock,wait:async ms=>{clock+=ms;},...extra};}
async function main(){
    let count=0;const result=await observeOwnedEntry(fixture({readBook:()=>{if(++count<3)throw missing();return book;}}));
    assert.equal(count,3);assert.equal(result.active.slot,slot);
    count=0;const switched=await observeOwnedEntry(fixture({readStatus:async()=>({saveRuntime:{loaded:++count>1,savePath:originSlot}})}));
    assert.equal(count,2);assert.equal(switched.status.saveRuntime.loaded,true);
    count=0;const returned=await observeOwnedEntry(fixture({readOrigin:()=>++count===1?{ext:{bookshelf:{active}}}:{ext:{bookshelf:{}}},readBook:()=>{throw missing();}}));
    assert.equal(returned.active,undefined);
    await assert.rejects(observeOwnedEntry(fixture({readStatus:async()=>({saveRuntime:{loaded:true,savePath:'original_player'}}),readBook:()=>{throw missing();}})),/foreign/);
    await assert.rejects(observeOwnedEntry(fixture({readOrigin:()=>({ext:{bookshelf:{active:{...active,originSlot:'foreign'}}}})})),/Unexpected affiliated/);
    await assert.rejects(observeOwnedEntry(fixture({readBook:()=>({ext:{bookRun:{...book.ext.bookRun,routeId:'historical'}}})})),/origin\/route/);
    await assert.rejects(observeOwnedEntry(fixture({readBook:()=>{throw Object.assign(Error('denied'),{code:'EACCES'});}})),/denied/);
    await assert.rejects(observeOwnedEntry(fixture({readBook:()=>{throw missing();}})),/within 45 seconds/);
    console.log('PASS owned entry waits for first save, observes cancelled entry, rejects foreign origin/runtime/route, preserves non-transient failures and bounds missing-save wait. No saves touched.');
}
main().catch(error=>{console.error(error);process.exitCode=1});
