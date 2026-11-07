'use strict';
// Starts the production bookshelf on a dedicated clone. Book selection and story
// input use the normal UI; this helper has no business-write or console channel.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),readline=require('readline');
const Generic=require('../workbench-live-e2e/kshop/generic-opener');
const Clone=require('../workbench-live-e2e/lib/clone-save-guard');
const Launcher=require('../workbench-live-e2e/lib/launcher-observation');
const {atomicWriteJson,sleep,canonicalJson,sha256Text}=require('../workbench-live-e2e/kshop/common');
const {writeReport}=require('./report-io');
const {observeOwnedEntry}=require('./observe-entry');
const ROOT=path.resolve(__dirname,'../..');
const BASE=path.join('tmp','workbench-live-e2e','stage-intro');
const TARGETS={
    'repair-campus':{bookId:'repair-campus',routeId:null,slot:'cf7_agent_intro_all_campus_1107'},
    'cf6-sting':{bookId:'cf6-sting',routeId:'historical',slot:'cf7_agent_intro_all_cf6_1107'},
    'cf6-sting.type61':{bookId:'cf6-sting',routeId:'type61',slot:'cf7_agent_intro_all_type61_1107'},
};
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function verifyRuntimeSlot(status,originSlot,affiliatedSlot) {
    const slot=status?.saveRuntime?.savePath, slots=Array.isArray(affiliatedSlot)?affiliatedSlot:[affiliatedSlot];
    if(status?.saveRuntime?.loaded!==true || slot!==originSlot && !slots.includes(slot))
        throw Error('Runtime moved outside the owned origin/affiliated test slots');
    return slot;
}
function verifyPilotSaveUniverse(begin,end,affiliatedSlot) {
    Generic.verifySaveUniverse(begin); Generic.verifySaveUniverse(end);
    const slots=Array.isArray(affiliatedSlot)?affiliatedSlot:affiliatedSlot?[affiliatedSlot]:[];
    if(slots.length===0)return Generic.assertSaveUniverseInvariant(begin,end);
    if(slots.length>8 || new Set(slots).size!==slots.length || slots.some(slot=>!/^bookrun_[a-f0-9]{24}$/.test(slot)))throw Error('Malformed affiliated slot');
    const allowed=entry=>slots.some(slot=>['json','sol'].some(extension=>entry.locator.toLowerCase().endsWith('/'+slot+'.'+extension)));
    if(begin.artifacts.some(allowed))throw Error('An affiliated slot that existed before this journey cannot be excepted');
    const artifacts=end.artifacts.filter(entry=>!allowed(entry));
    const payload={schema:end.schema,root:path.resolve(end.root),appDataRoot:path.resolve(end.appDataRoot),excludedTargetSlot:end.excludedTargetSlot,artifacts};
    const filtered={...end,artifacts,setSha256:sha256Text(canonicalJson(payload))};
    return {...Generic.assertSaveUniverseInvariant(begin,filtered),affiliatedNewArtifacts:end.artifacts.filter(allowed)};
}
function parse(argv) {
    if(argv.includes('--help'))return null;
    if(!argv.includes('--execute-isolated-candidate')||!argv.includes('--allow-clone-book-writes'))
        throw Error('Explicit isolated-candidate and clone-book-write execution flags required.');
    const args=argv.filter(x=>!['--execute-isolated-candidate','--allow-clone-book-writes'].includes(x));
    const options={};
    while(args.length){const key=args.shift(),value=args.shift();if(!['--candidate-root','--expected-asloader-sha256','--seed-slot','--book-target'].includes(key)||!value||options[key])throw Error('Unknown, duplicate or incomplete argument');options[key]=value;}
    if(!options['--candidate-root']||!path.isAbsolute(options['--candidate-root'])||!/^[a-f0-9]{64}$/i.test(options['--expected-asloader-sha256']||''))throw Error('Pin exact candidate and fresh compiled asLoader SHA256');
    if(!/^cf7_agent_[A-Za-z0-9_-]+$/.test(options['--seed-slot']||''))throw Error('Only an existing dedicated seed slot is allowed');
    if(hash(path.join(ROOT,'scripts/asLoader.swf'))!==options['--expected-asloader-sha256'].toLowerCase())throw Error('Compiled loader differs from execution pin');
    const bookTarget=options['--book-target']||'repair-campus',target=TARGETS[bookTarget];
    if(!Object.prototype.hasOwnProperty.call(TARGETS,bookTarget))throw Error('Only the reviewed campus/historical/Type61 book targets are allowed');
    return {candidateRoot:options['--candidate-root'],seedSlot:options['--seed-slot'],bookTarget,...target,
        preserveSeedBytes:true,ownedBaseRelative:BASE,readyTimeoutMs:180000,pollMs:200,
        cloneBaselineTimeoutMs:30000,cloneBaselineStableMs:2000};
}
async function main(argv) {
    const args=parse(argv);
    if(!args){console.log('Requires --execute-isolated-candidate --allow-clone-book-writes --candidate-root ABSOLUTE --expected-asloader-sha256 SHA256 --seed-slot cf7_agent_EXISTING [--book-target repair-campus|cf6-sting|cf6-sting.type61]. After ready, stdin accepts observe or shutdown only.');return;}
    if(!process.stdin.isTTY)throw Error('An interactive console is required before clone preparation. Automation must allocate a PTY.');
    const runDir=path.join(ROOT,BASE,new Date().toISOString().replace(/[:.]/g,'-'));
    fs.mkdirSync(runDir,{recursive:true});
    const sourceFiles=['data/books/chapter-intros.json',
        'tools/stage-intro-live-e2e/run-candidate.js','tools/stage-intro-live-e2e/report-io.js','tools/stage-intro-live-e2e/observe-entry.js',
        'scripts/类定义/org/flashNight/arki/scene/BookComicSequence.as',
        'scripts/类定义/org/flashNight/arki/scene/BookRunRules.as',
        'scripts/类定义/org/flashNight/arki/scene/BookRunService.as',
        'scripts/类定义/org/flashNight/arki/scene/BookDefinition.as','scripts/asLoader.swf','CRAZYFLASHER7MercenaryEmpire.swf',
        'scripts/类定义/org/flashNight/arki/scene/StageIntroService.as',
        'scripts/类定义/org/flashNight/arki/scene/StageManager.as',
        'scripts/类定义/org/flashNight/arki/ui/SceneTransitionService.as',
        'launcher/web/modules/book-comic-panel.js','launcher/web/modules/scene-transition.js',
        'data/stages/books/repair-campus.runtime.json','flashswf/backgrounds/gk12_1_BG.swf'];
    if(args.bookId==='cf6-sting') {
        const closure=require('../cf6-live-e2e/source-closure').capture(ROOT,args.routeId);
        atomicWriteJson(path.join(runDir,'cf6-source-closure.json'),closure);
        for(const row of closure.files) {
            if(hash(path.join(ROOT,row.relativePath))!==row.sha256)throw Error('CF6 input changed during capture');
            sourceFiles.push(row.relativePath);
        }
    } else {
        const campus=JSON.parse(fs.readFileSync(path.join(ROOT,'data/stages/books/repair-campus.runtime.json'),'utf8'));
        for(const map of campus.maps)sourceFiles.push('flashswf/backgrounds/'+map.background);
    }
    const report={schema:'cf7-stage-intro.candidate-journey.v2',status:'preparing',slot:args.slot,bookTarget:args.bookTarget,runDir,
        source:[...new Set(sourceFiles)].sort().map(file=>({path:file,sha256:hash(path.join(ROOT,file))})),observations:[],affiliatedSlot:null,affiliatedSlots:[]};
    const persist=()=>writeReport(path.join(runDir,'report.json'),report);
    persist();let runtime,input;
    try {
        runtime=await Generic.openGenericRuntime(ROOT,args,runDir);
        report.candidate={pid:runtime.identity.pid,identity:runtime.identity,cdpBinding:runtime.cdpBinding};
        atomicWriteJson(path.join(runDir,'save-protection.json'),{
            preparation:runtime.preparation,collateralBefore:runtime.collateralBefore,baseline:runtime.baseline});
        const opened=await runtime.session.agentControl('openBookshelf',{
            expectedSlot:args.slot,expectedAttemptId:runtime.ready.expectedAttemptId});
        Launcher.assertResponseSucceeded(opened,'stage_intro','production bookshelf opener');
        report.status='bookshelf_requested';persist();
        console.log(JSON.stringify({status:report.status,runDir,pid:runtime.identity.pid,slot:args.slot}));
        async function observe() {
            for(const entry of report.source)
                if(hash(path.join(ROOT,entry.path))!==entry.sha256)throw Error('Runtime input drifted: '+entry.path);
            const entry=await observeOwnedEntry({originSlot:args.slot,bookId:args.bookId,routeId:args.routeId,affiliatedSlots:report.affiliatedSlots,
                readStatus:()=>runtime.session.agentControl('status'),
                readOrigin:()=>JSON.parse(fs.readFileSync(path.join(ROOT,'saves',args.slot+'.json'),'utf8')),
                readBook:slot=>JSON.parse(fs.readFileSync(path.join(ROOT,'saves',slot+'.json'),'utf8'))});
            const {status,active,book}=entry;
            const snapshot=await runtime.session.readTerminalLogSnapshot(1600);
            if(active?.slot){
                if(active.bookId!==args.bookId||active.originSlot!==args.slot||!/^bookrun_[a-f0-9]{24}$/.test(active.slot))throw Error('Unexpected affiliated book identity; stopping observation');
                if(book.ext?.bookRun?.bookId!==args.bookId||book.ext.bookRun.originSlot!==args.slot||book.ext.bookRun.slot!==active.slot)throw Error('Affiliated run does not match the production origin');
                if(args.routeId && book.ext.bookRun.routeId!==args.routeId)throw Error('Affiliated run has a foreign route');
                if(!report.affiliatedSlots.includes(active.slot)) {
                    if(report.affiliatedSlots.length>=8)throw Error('Journey exceeded its bounded affiliated slot inventory');
                    if(runtime.collateralBefore.artifacts.some(entry=>['json','sol'].some(ext=>entry.locator.toLowerCase().endsWith('/'+active.slot+'.'+ext))))throw Error('Affiliated slot existed before this journey');
                    report.affiliatedSlots.push(active.slot);
                }
                report.affiliatedSlot=active.slot;
            }
            verifyRuntimeSlot(status,args.slot,report.affiliatedSlots);
            const item={at:new Date().toISOString(),status,terminal:snapshot};
            report.observations.push(item);report.status='observing';persist();
            console.log(JSON.stringify({status:'observed',runDir,activePanel:status.activePanel,affiliatedSlot:report.affiliatedSlot}));
        }
        await observe();
        input=readline.createInterface({input:process.stdin,crlfDelay:Infinity});
        for await(const line of input) {
            const command=line.trim();
            if(command==='observe'){await observe();continue;}
            if(command!=='shutdown'){console.log('Only observe or shutdown are supported.');continue;}
            await observe();
            Launcher.assertResponseSucceeded(await runtime.session.agentControl('shutdown'),'stage_intro','normal owned runtime shutdown');
            const until=Date.now()+30000;
            while(true){try{Generic.assertNoLauncherBeforeMutation();break;}catch(error){if(Date.now()>until)throw error;await sleep(200);}}
            const after=Generic.captureSaveUniverse(ROOT,runtime.appData,args.slot);
            // Verify every original JSON/SOL; only the exact production-created affiliated slot is excepted.
            const invariant=verifyPilotSaveUniverse(runtime.collateralBefore,after,report.affiliatedSlots);
            const released=Clone.releaseDedicatedClone({preparation:runtime.preparation,lock:runtime.lock,appData:runtime.appData});
            report.cleanup={invariant,released,affiliatedTestSlotRetained:report.affiliatedSlot,affiliatedTestSlotsRetained:report.affiliatedSlots};
            report.status='closed';persist();console.log(JSON.stringify({status:'closed',runDir,affiliatedTestSlotRetained:report.affiliatedSlot}));break;
        }
        input.close(); process.stdin.pause();
        if(report.status!=='closed')throw Error('Interactive input ended before normal shutdown; preserve the recovery record.');
    } catch(error) {
        report.status='failed';report.error=String(error.message||error);
        try{persist();}catch(recordError){console.error('Failure record could not be replaced: '+String(recordError.message||recordError));}
        try{if(runtime)await Generic.cleanupAuthenticatedPartialStart(ROOT,runtime.expectedIdentity);}
        finally{if(input)input.close();process.stdin.pause();}
        throw error;
    }
}
if(require.main===module)main(process.argv.slice(2)).catch(error=>{console.error(error.stack||error);process.exitCode=1;});
module.exports={parse,verifyPilotSaveUniverse,verifyRuntimeSlot};
