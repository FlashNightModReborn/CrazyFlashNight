#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path');
const Preflight=require('./preflight'),Closure=require('./source-closure'),Affiliated=require('./affiliated-slot');
const {openInput}=require('./cdp-input-channel');
const {TranscriptWriter,attachPassiveObserver}=require('./passive-observer');
const {observeVerifiedReturn}=require('./verified-return-observation');
const Clone=require('../workbench-live-e2e/lib/clone-save-guard');
const E=require('../workbench-live-e2e/lib/evidence-artifact');
const Launcher=require('../workbench-live-e2e/lib/launcher-observation');
const Generic=require('../workbench-live-e2e/kshop/generic-opener');
const {atomicWriteJson,canonicalJson,sha256Text,sleep,timestampId}=require('../workbench-live-e2e/kshop/common');
const ROOT=path.resolve(__dirname,'../..'),BASE=path.join('tmp','workbench-live-e2e','cf6');
function parseArgs(argv) {
    if (argv.includes('--help')) return {help:true};
    const args=argv.slice(),options={};
    for (const flag of ['--execute-isolated-candidate','--observe-only','--allow-clone-book-writes']) {
        const count=args.filter(a=>a===flag).length;if(count>1)throw Error('duplicate execution flag');
        options[flag]=count===1;if(count)args.splice(args.indexOf(flag),1);
    }
    const waitIndex=args.indexOf('--await-return-seconds');let wait=1800;
    if(waitIndex>=0){wait=Number(args[waitIndex+1]);args.splice(waitIndex,2);}
    if(!Number.isInteger(wait)||wait<30||wait>14400)throw Error('return wait must be 30..14400 seconds');
    if(!options['--execute-isolated-candidate']||options['--observe-only']===options['--allow-clone-book-writes'])
        throw Error('choose execute-isolated-candidate and exactly observe-only or allow-clone-book-writes');
    const parsed=Preflight.parseArgs(args);
    if(!parsed.expectedBuildIdentity||!parsed.expectedPayloadClosure||!parsed.expectedAsloaderSha256)
        throw Error('pin candidate build, closure and compiled asLoader SHA-256');
    return {...parsed,slot:Preflight.TARGET_SLOT,ownedBaseRelative:BASE,preserveSeedBytes:true,
        readyTimeoutMs:180000,pollMs:200,cloneBaselineTimeoutMs:30000,cloneBaselineStableMs:2000,
        observeOnly:options['--observe-only'],awaitReturnMs:wait*1000};
}
async function until(label,timeout,fn) {
    const end=Date.now()+timeout;
    while(Date.now()<end){const result=await fn();if(result)return result;await sleep(200);}
    throw Error(label+' timed out; no business mutation will be replayed');
}
function message(event){return event&&['bridge_send','webview_message'].includes(event.kind)?event.message:null;}
function readSave(slot) {
    if(!/^(cf7_agent_[A-Za-z0-9_-]+|bookrun_[a-f0-9]{24})$/.test(slot))throw Error('unsafe read slot');
    const file=E.readExactRegularFile(path.join(ROOT,'saves',slot+'.json'),{phase:'cf6_ledger',maximumBytes:128*1024*1024});
    return {data:JSON.parse(file.bytes.toString('utf8')),sha256:file.sha256,bytes:file.bytes};
}
function preserveSaveSnapshot(runDir,label,slot,snapshot) {
    E.assertOwnedRunDirectory(ROOT,runDir,BASE,'cf6_save_snapshot');
    if(!['origin-before-play','origin-entry','book-entry','origin-returned','origin-readback'].includes(label)
            ||!(slot===Preflight.TARGET_SLOT||Affiliated.SLOT.test(slot)))throw Error('unsafe save evidence identity');
    const name=label+'.json',target=path.join(runDir,name);
    fs.writeFileSync(target,snapshot.bytes,{flag:'wx',mode:0o600});
    const saved=E.readExactRegularFile(target,{phase:'cf6_save_snapshot',maximumBytes:128*1024*1024});
    if(saved.sha256!==snapshot.sha256)throw Error('save evidence bytes changed');
    return {file:name,slot,bytes:snapshot.bytes.length,sha256:snapshot.sha256};
}
async function shutdown(runtime) {
    Launcher.assertResponseSucceeded(await runtime.session.agentControl('shutdown'),'cf6_shutdown','supported shutdown');
    await until('exact owned runtime exit',30000,()=>{
        try{return Generic.assertNoLauncherBeforeMutation();}catch(_){return false;}
    });
    return {pid:runtime.identity.pid,normalShutdownRequested:true};
}
function release(runtime,admission) {
    Generic.assertNoLauncherBeforeMutation();
    const after=Generic.captureSaveUniverse(ROOT,runtime.appData,Preflight.TARGET_SLOT);
    const collateral=Affiliated.assertCollateral(runtime.collateralBefore,after,admission);
    const clone=Clone.releaseDedicatedClone({preparation:runtime.preparation,lock:runtime.lock,appData:runtime.appData});
    return {collateral,clone};
}
async function main(argv) {
    const args=parseArgs(argv);
    if(args.help){console.log('See tools/cf6-live-e2e/README.md. Requires pinned candidate, seed and asLoader; observe-only or explicit clone book writes.');return;}
    const preflight=Preflight.inspect(args),sourceClosure=Closure.capture(ROOT);
    const runDir=path.join(ROOT,BASE,timestampId()+'-cf6');fs.mkdirSync(runDir,{recursive:true});
    E.assertOwnedRunDirectory(ROOT,runDir,BASE,'cf6_run');
    const writer=new TranscriptWriter(runDir,'cf6-'+timestampId());
    const report={schema:'cf7-cf6-e2e.candidate-journey.v1',status:'running',preflight,sourceClosure,runDir,
        gameplayDriver:'external production input; this runner does not drive combat or fake termination'};
    let runtime=null,input=null,observer=null,admission=null,entryRequest=null,originBefore=null,completed=false,released=false;
    const persist=()=>atomicWriteJson(path.join(runDir,'report.json'),report);
    persist();
    async function attach(current){
        observer=await attachPassiveObserver({root:ROOT,runDir,writer,cdpBinding:current.cdpBinding,
            runtimeIdentity:current.identity,sourceClosure,timeoutMs:30000,pollMs:200});
        input=await openInput({cdpBinding:current.cdpBinding,runtimeIdentity:current.identity,writer,runDir});
    }
    async function detach(){
        const oldInput=input,oldObserver=observer;input=null;observer=null;
        try { if(oldInput)oldInput.close(); }
        finally { if(oldObserver)await oldObserver.detach(); }
    }
    try {
        runtime=await Generic.openGenericRuntime(ROOT,args,runDir);
        if(runtime.preparation.transformId!=='exact-byte-copy'||runtime.preparation.seedBegin.setSha256!==preflight.seedArtifactSetSha256
                ||runtime.preparation.targetBefore.setSha256!==preflight.targetBeforeArtifactSetSha256
                ||runtime.expectedIdentity.buildIdentity.toUpperCase()!==preflight.candidate.buildIdentity.toUpperCase()
                ||runtime.expectedIdentity.payloadClosure.toUpperCase()!==preflight.candidate.payloadClosure.toUpperCase())
            throw Error('candidate or clone changed after preflight');
        const protectionPath=path.join(runDir,'save-protection-before.json');
        atomicWriteJson(protectionPath,{schema:'cf7-cf6-e2e.save-protection.v1',
            preparation:runtime.preparation,collateralBefore:runtime.collateralBefore,loadedCloneBaseline:runtime.baseline});
        report.saveProtectionBefore={file:path.basename(protectionPath),
            sha256:E.readExactRegularFile(protectionPath,{phase:'cf6_save_protection',maximumBytes:128*1024*1024}).sha256};
        report.candidate={...runtime.identity};persist();await attach(runtime);
        const opener=await runtime.session.agentControl('openBookshelf',{expectedSlot:args.slot,
            expectedAttemptId:runtime.ready.expectedAttemptId});
        Launcher.assertResponseSucceeded(opener,'cf6_open','fixed bookshelf opener');
        if(opener.note!=='bookshelf_panel_open_requested')throw Error('unexpected opener receipt');
        const opened=await until('production bookshelf open',30000,async()=>{
            const status=await runtime.session.agentControl('status');
            const active=status.activePanel;if(active?.name!=='bookshelf'||!active.instanceId)return null;
            const event=writer.events.find(e=>{const m=message(e);return m?.type==='panel_cmd'&&m.cmd==='open'
                &&m.panel==='bookshelf'&&m.panelInstanceId===active.instanceId&&m.initData?.token;});
            const snapshot=writer.events.find(e=>{const m=message(e);return m?.type==='panel_resp'&&m.panel==='bookshelf'
                &&m.panelInstanceId===active.instanceId&&m.cmd==='snapshot'&&m.success===true&&m.activeSlot===args.slot;});
            return event&&snapshot?{instance:active.instanceId,openSequence:event.sequence,snapshotSequence:snapshot.sequence}:null;
        });
        report.open=opened;report.loadedWeb=await observer.assertLoadedCf6Scripts();
        report.openScreenshot=await input.screenshot('bookshelf-open.png');persist();
        originBefore=readSave(args.slot);
        report.saveSnapshots={beforePlay:preserveSaveSnapshot(runDir,'origin-before-play',args.slot,originBefore)};persist();
        if(args.observeOnly){
            await input.click('close');
            await until('bookshelf close',10000,async()=> (await runtime.session.agentControl('status')).activePanel?.name!=='bookshelf');
        } else {
            await input.click('series');await input.click('chapter6');
            report.selectionScreenshot=await input.screenshot('cf6-selected.png');
            const clicked=await input.click('play');
            entryRequest=await until('production CF6 play request',10000,()=>writer.events.map(e=>({e,m:message(e)})).find(({e,m})=>
                e.sequence>clicked.afterSequence&&m?.type==='panel'&&m.panel==='bookshelf'&&m.cmd==='commit'
                &&m.panelInstanceId===opened.instance&&m.payload?.kind==='play'&&m.payload?.target==='cf6-sting')?.m);
            report.entryRequest={callId:entryRequest.callId,instance:entryRequest.panelInstanceId,tokenRef:entryRequest.payload.token};persist();
            admission=await until('durable CF6 entry and exact affiliated slot',120000,()=>{
                const originFile=readSave(args.slot),origin=originFile.data,active=origin.ext?.bookshelf?.active;
                if(!active||!Affiliated.SLOT.test(active.slot))return null;
                const receipt=writer.events.map(message).find(m=>m?.type==='panel_resp'&&m.token===entryRequest.payload.token
                    &&m.panelInstanceId===opened.instance&&m.kind==='play'&&m.target==='cf6-sting'&&m.success===true
                    &&['switching','applied'].includes(m.phase)&&(m.pendingRun===active.slot||m.activeSlot===active.slot));
                if(!receipt||!fs.existsSync(path.join(ROOT,'saves',active.slot+'.json')))return null;
                const runFile=readSave(active.slot),run=runFile.data;
                const receiptRequest=writer.events.map(message).find(m=>m?.type==='panel'&&m.callId===receipt.callId
                    &&m.panelInstanceId===opened.instance&&m.cmd===receipt.cmd);
                const accepted=Affiliated.admit({before:runtime.collateralBefore,request:entryRequest,receipt,receiptRequest,
                    originSave:origin,runSave:run,originSlot:args.slot,instance:opened.instance});
                if(run.ext.bookRun.started!==true)return null;
                report.saveSnapshots.originEntry=preserveSaveSnapshot(runDir,'origin-entry',args.slot,originFile);
                report.saveSnapshots.bookEntry=preserveSaveSnapshot(runDir,'book-entry',active.slot,runFile);persist();
                const chapter=JSON.parse(E.readExactRegularFile(path.join(ROOT,'data/stages/books/cf6-sting.runtime.json'),
                    {phase:'cf6_actor',maximumBytes:32*1024*1024}).bytes.toString('utf8'));
                report.initialActor=Affiliated.assertActor(run,chapter);
                report.initialActor.slot=active.slot;report.initialActor.runStarted=true;
                // Compare return with the real production entry-barrier snapshot, after normal load migration.
                originBefore=originFile;report.originEntrySnapshotSha256=originFile.sha256;
                return accepted;
            });
            report.affiliated=admission;persist();console.log('CF6 entry verified. Awaiting genuine death, retreat or victory; drive combat through normal game input.');
            const terminal=await until('production terminal bookshelf',args.awaitReturnMs,()=>writer.events.map(message).find(m=>
                m?.type==='panel_resp'&&m.panel==='bookshelf'&&m.success===true&&m.inRun===true
                &&m.activeSlot===admission.slot&&m.originSlot===args.slot&&m.bookId==='cf6-sting'
                &&['failure','defeat','retreat','victory','abandoned'].includes(m.runOutcome)));
            // The production panel automatically returns an exitRequired run after its fresh snapshot.
            // Observe that same request; clicking a second return could duplicate an unknown write.
            const returnRequest=await until('production automatic return request',30000,()=>writer.events.map(message).find(m=>
                m?.type==='panel'&&m.panel==='bookshelf'&&m.cmd==='commit'&&m.panelInstanceId===terminal.panelInstanceId
                &&m.payload?.kind==='return'&&m.payload?.target===args.slot&&m.payload?.token===terminal.token));
            const returned=await until('production return applied',120000,()=>writer.events.map(message).find(m=>
                m?.type==='panel_resp'&&m.panel==='bookshelf'&&m.success===true&&m.panelInstanceId===returnRequest.panelInstanceId
                &&m.token===returnRequest.payload.token&&m.kind==='return'&&m.phase==='applied'&&m.activeSlot===args.slot&&m.inRun===false
                &&m.returningResult?.runId===admission.slot&&m.returningResult.bookId==='cf6-sting'&&m.returningResult.sp===0));
            report.returnReceipt={phase:returned.phase,activeSlot:returned.activeSlot,result:returned.returningResult};
            await Clone.captureStableSlotArtifactSet({root:ROOT,appData:runtime.appData,slot:args.slot,requireJson:true,
                timeoutMs:30000,stableMs:2000,pollMs:200});
            const returnedSave=readSave(args.slot);
            report.saveSnapshots.returned=preserveSaveSnapshot(runDir,'origin-returned',args.slot,returnedSave);persist();
            report.result=Affiliated.assertReturned(originBefore.data,returnedSave.data,admission.slot);persist();
            const presentation=await observeVerifiedReturn({before:originBefore.data,after:returnedSave.data,
                slot:admission.slot,originSlot:args.slot,receipt:report.returnReceipt,input,detach});
            report.returnScreenshot=presentation.screenshot;
            report.postReturnObservationWarnings=presentation.warnings;persist();
        }
        await detach();report.shutdown=await shutdown(runtime);
        // A separate process reloads the clone through the same production bootstrap before release.
        if(!args.observeOnly){
            const first=runtime;
            try { runtime=await Generic.restartGenericRuntime(ROOT,args,first.preparation,first.expectedIdentity,first); }
            catch(error) { report.partialRestartShutdown=await Generic.cleanupAuthenticatedPartialStart(ROOT,first.expectedIdentity);throw error; }
            report.restart={pid:runtime.identity.pid,firstPid:first.identity.pid,attempt:runtime.ready.expectedAttemptId};
            const readbackSave=readSave(args.slot);
            report.saveSnapshots.readback=preserveSaveSnapshot(runDir,'origin-readback',args.slot,readbackSave);persist();
            report.readback=Affiliated.assertReturned(originBefore.data,readbackSave.data,admission.slot);
            report.restartShutdown=await shutdown(runtime);runtime=first;
        }
        Closure.assertUnchanged(sourceClosure,Closure.capture(ROOT));
        report.transcript=writer.flush({journeyComplete:true,observeOnly:args.observeOnly});
        report.release=release(runtime,admission);released=true;
        report.status=args.observeOnly?'passed_observe_only':'passed_entry_terminal_return_readback';completed=true;
        report.completedAt=new Date().toISOString();report.sha256=sha256Text(canonicalJson(report));persist();
        console.log(JSON.stringify({status:report.status,runDir,sha256:report.sha256,result:report.result||null},null,2));
    } catch(error) {
        report.status=released?'failed_after_verified_release':'failed_preserved';report.failure={message:String(error.message||error),code:error.code||null};
        try{await detach();}catch(e){report.detachFailure=String(e.message||e);}
        try{if(runtime)report.failureShutdown=await shutdown(runtime);}catch(e){report.shutdownFailure=String(e.message||e);}
        if(runtime&&report.failureShutdown){
            try{
                const after=Generic.captureSaveUniverse(ROOT,runtime.appData,args.slot);
                const target=Clone.captureSlotArtifactSet({root:ROOT,appData:runtime.appData,slot:args.slot,requireJson:false});
                const protectionPath=path.join(runDir,'save-protection-after-failure.json');
                atomicWriteJson(protectionPath,{schema:'cf7-cf6-e2e.save-protection.v1',collateralAfter:after,targetAfter:target});
                report.failureSaveProtection={file:path.basename(protectionPath),
                    sha256:E.readExactRegularFile(protectionPath,{phase:'cf6_save_protection',maximumBytes:128*1024*1024}).sha256};
                report.failureSaveProtection.collateral=Affiliated.assertCollateral(runtime.collateralBefore,after,admission);
            }catch(e){report.failureSaveProtectionError=String(e.message||e);}
        }
        // Do not unlock, restore or delete on failure: a durable or unknown book write may exist.
        report.recovery={required:!released,cloneSlot:args.slot,affiliatedSlot:admission?.slot||null,
            policy:'preserve clone, exact recovery record, all affiliated artifacts and source hashes; no automatic business retry or restore'};
        try{report.transcript=writer.flush({journeyComplete:false});}catch(e){report.transcriptFailure=String(e.message||e);}
        persist();throw error;
    } finally {if(!completed)console.error('CF6 evidence and clone recovery state retained at '+runDir);}
}
module.exports={parseArgs,main,message};
if(require.main===module)main(process.argv.slice(2)).catch(error=>{console.error(error.stack||String(error));process.exitCode=1;});
