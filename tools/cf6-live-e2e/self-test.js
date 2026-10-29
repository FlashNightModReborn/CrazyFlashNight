#!/usr/bin/env node
'use strict';
const assert=require('assert'),fs=require('fs'),os=require('os'),path=require('path');
const A=require('./affiliated-slot'),P=require('./preflight'),Runner=require('./run-candidate');
const Observer=require('./passive-observer');
const Launcher=require('../workbench-live-e2e/lib/launcher-observation');
const clone=v=>JSON.parse(JSON.stringify(v));let passed=0;
function test(name,fn){fn();passed++;console.log('PASS '+name);}
const origin=P.TARGET_SLOT,book='bookrun_'+'a'.repeat(24),instance='bookshelf.fixture.one',token='sha256:'+'f'.repeat(64);
const artifact=(slot,hash='b'.repeat(64),kind='json')=>({kind,locator:kind==='json'?'root:saves/'+slot+'.json':'appdata:Macromedia/fixture/'+slot+'.sol',
    sha256:hash,bytes:100,regularFile:true,exactRealPath:true});
function fixture(){
    const credential={slot:book,originSlot:origin,bookId:'cf6-sting',routeId:'historical',seed:17,outcome:'active'};
    const request={type:'panel',panel:'bookshelf',domain:'bookshelf',cmd:'commit',panelInstanceId:instance,callId:'call.1',
        payload:{v:1,token,kind:'play',target:'cf6-sting'}};
    return {before:{root:'fixture-root',appDataRoot:'fixture-appdata',excludedTargetSlot:origin,
        artifacts:[artifact('cf7_agent_seed'),artifact('preexisting-book'),artifact('preexisting-book','b'.repeat(64),'sol')]},
        request,receipt:{type:'panel_resp',panel:'bookshelf',domain:'bookshelf',panelInstanceId:instance,token,
            callId:'call.1',cmd:'commit',kind:'play',target:'cf6-sting',success:true,phase:'switching',activeSlot:origin,pendingRun:book},
        originSave:{ext:{bookshelf:{active:credential}}},runSave:{ext:{bookRun:clone(credential)}},originSlot:origin,instance};
}
test('exact production entry admits one new subsidiary slot',()=>{
    const f=fixture(),a=A.admit(f);assert.equal(a.slot,book);assert.equal(a.preexisting,false);
    const after=clone(f.before);after.artifacts.push(artifact(book),artifact(book,'c'.repeat(64),'sol'));
    assert.equal(A.assertCollateral(f.before,after,a).affiliatedArtifacts.length,2);
});
for(const [name,mutate] of [
    ['foreign panel',f=>f.receipt.panelInstanceId='foreign'],
    ['foreign token',f=>f.receipt.token='sha256:'+'e'.repeat(64)],
    ['foreign call',f=>f.receipt.callId='call.other'],
    ['save pending is not acceptance',f=>{f.receipt.phase='save_pending';f.receipt.success=false;}],
    ['foreign origin',f=>f.runSave.ext.bookRun.originSlot='cf7_agent_other'],
    ['foreign route',f=>f.runSave.ext.bookRun.routeId='plan61'],
    ['foreign seed',f=>f.runSave.ext.bookRun.seed=18],
    ['preexisting JSON slot',f=>f.before.artifacts.push(artifact(book))],
    ['preexisting SOL slot',f=>f.before.artifacts.push(artifact(book,'b'.repeat(64),'sol'))],
    ['receipt lacks slot identity',f=>{f.receipt.activeSlot='other';f.receipt.pendingRun='';}],
    ['raw token is not written to evidence',f=>{f.request.payload.token='secret';f.receipt.token='secret';}]
])test(name,()=>{const f=fixture();mutate(f);assert.throws(()=>A.admit(f));});
test('query receipt must pair exact observed query request',()=>{
    const f=fixture();f.receipt.cmd='query';f.receipt.callId='call.query';
    assert.throws(()=>A.admit(f));
    f.receiptRequest={...f.request,cmd:'query',callId:'call.query',payload:{v:1,token}};
    assert.equal(A.admit(f).slot,book);
});
for(const [name,mutate] of [
    ['old save changed',after=>after.artifacts[0].sha256='0'.repeat(64)],
    ['old save deleted',after=>after.artifacts.shift()],
    ['unregistered book slot created',after=>after.artifacts.push(artifact('bookrun_'+'c'.repeat(24)))],
    ['unregistered permanent slot created',after=>after.artifacts.push(artifact('cf7_agent_foreign'))]
])test(name,()=>{const f=fixture(),a=A.admit(f),after=clone(f.before);mutate(after);assert.throws(()=>A.assertCollateral(f.before,after,a));});
test('new slot cannot bypass protection without an admission',()=>{
    const f=fixture(),after=clone(f.before);after.artifacts.push(artifact(book));assert.throws(()=>A.assertCollateral(f.before,after,null));
});
test('production may clean up only its exact newly admitted book slot',()=>{
    const f=fixture();assert.equal(A.assertCollateral(f.before,clone(f.before),A.admit(f)).affiliatedArtifacts.length,0);
});
test('tampered affiliated admission does not authorize exclusions',()=>{
    const f=fixture(),a=A.admit(f);a.slot='bookrun_'+'d'.repeat(24);assert.throws(()=>A.assertCollateral(f.before,clone(f.before),a));
});
function actorFixture(){
    const chapter={startingMoney:500,startingSkillPoints:0,actor:{name:'Andy',gender:'男',height:175,face:'face',hair:'hair',
        equipment:[{slot:'刀',name:'镜之虎彻',enhancement:11}],skills:[{name:'小跳',level:10}]}};
    const save={'0':['Andy','男',500,60,157526193,175,0],'1':['face','hair'],'5':[['小跳',10,false,'主动',false]],
        inventory:{装备栏:{刀:{name:'镜之虎彻',value:{level:11}}}}};return {chapter,save};
}
test('historical actor validates fixed skills and initial enhancement',()=>{const f=actorFixture();assert.equal(A.assertActor(f.save,f.chapter).allInitialEnhancements,11);});
test('actor mismatches fail before initial-state proof',()=>{
    for(const mutate of [f=>f.save['0'][4]=0,f=>f.save.inventory.装备栏.刀.value.level=1,f=>f.save['5'].push(clone(f.save['5'][0]))]){
        const f=actorFixture();mutate(f);assert.throws(()=>A.assertActor(f.save,f.chapter));
    }
});
test('returned origin must retain assets and exact zero-SP route record',()=>{
    const before=actorFixture().save,after=clone(before);after.ext={bookshelf:{lastRun:book,routes:{'cf6-sting.historical':{
        history:[{runId:book,bookId:'cf6-sting',routeId:'historical',sp:0,outcome:'retreat'}]}}}};
    assert.equal(A.assertReturned(before,after,book).outcome,'retreat');
    after['0'][2]++;assert.throws(()=>A.assertReturned(before,after,book));
});
const pinned=['--candidate-root',path.resolve(os.tmpdir(),'candidate-fixture'),'--seed-slot','cf7_agent_scene_ready_1014',
    '--expected-build-identity','a'.repeat(64),'--expected-payload-closure','b'.repeat(64),'--expected-asloader-sha256','c'.repeat(64)];
test('runner requires explicit isolated scope and pinned compilation',()=>{
    assert.throws(()=>Runner.parseArgs(pinned));
    assert.throws(()=>Runner.parseArgs(pinned.slice(0,-2).concat('--execute-isolated-candidate','--observe-only')));
    assert.equal(Runner.parseArgs(pinned.concat('--execute-isolated-candidate','--observe-only')).slot,origin);
    assert.throws(()=>Runner.parseArgs(pinned.concat('--execute-isolated-candidate','--observe-only','--allow-clone-book-writes')));
});
test('preflight rejects live seed and arbitrary target/fresh overrides',()=>{
    const live=pinned.slice();live[live.indexOf('--seed-slot')+1]='crazyflasher7_saves';assert.throws(()=>P.parseArgs(live));
    assert.throws(()=>P.parseArgs(pinned.concat('--slot','other')));assert.throws(()=>P.parseArgs(pinned.concat('--fresh')));
});
test('passive observer redacts and preserves identity equality',()=>{
    const redacted=Observer.redactCf6Tokens({token:'secret',nextToken:'secret',payload:{token:'secret'}},null);
    assert.equal(redacted.token,redacted.payload.token);assert.equal(redacted.token,redacted.nextToken);assert(!JSON.stringify(redacted).includes('secret'));
});
test('active runner and input contain no direct app business calls',()=>{
    for(const file of ['run-candidate.js','cdp-input-channel.js']){
        const s=fs.readFileSync(path.join(__dirname,file),'utf8');
        for(const pattern of [/\bBridge\s*\.\s*send\s*\(/,/\bPanels\s*\.\s*open\s*\(/,/\b(?:button|element)\s*\.\s*click\s*\(/,/requestFixedAgentEnter\s*\(/])assert(!pattern.test(s),file);
    }
});
test('Type61 selects a separate fixed clone and virtual play target',()=>{
    const args=Runner.parseArgs(pinned.concat('--route','type61','--execute-isolated-candidate','--allow-clone-book-writes'));
    assert.equal(args.routeId,'type61');assert.equal(args.slot,'cf7_agent_cf6_type61_20261026');
    assert.throws(()=>P.parseArgs(pinned.concat('--route','plan61')));
});
test('Type61 admission binds both request target and both route credentials',()=>{
    const f=fixture();f.routeId='type61';f.originSlot='cf7_agent_cf6_type61_20261026';f.before.excludedTargetSlot=f.originSlot;
    f.request.payload.target=f.receipt.target='cf6-sting.type61';
    for(const c of [f.originSave.ext.bookshelf.active,f.runSave.ext.bookRun]){c.routeId='type61';c.originSlot=f.originSlot;}
    assert.equal(A.admit(f).routeId,'type61');
    for(const mutate of [g=>g.request.payload.target='cf6-sting',g=>g.receipt.target='cf6-sting',
        g=>g.runSave.ext.bookRun.routeId='historical',g=>g.originSave.ext.bookshelf.active.routeId='historical']){
        const g=clone(f);mutate(g);assert.throws(()=>A.admit(g));
    }
});
test('Type61 actor proof checks 35, +1 and all twelve quick slots',()=>{
    const f=actorFixture();f.chapter.routeId='type61';f.chapter.startingMoney=30000;f.chapter.startingSkillPoints=1050;
    f.chapter.actor.quickSkills=['小跳'];f.chapter.actor.equipment[0].enhancement=1;
    Object.assign(f.save['0'],{2:30000,3:35,4:17372868,6:1050});f.save.inventory.装备栏.刀.value.level=1;
    f.save['1'].length=28;for(let i=0;i<12;i++)f.save['1'][16+i]=i===0?'小跳':'';
    assert.equal(A.assertActor(f.save,f.chapter).allInitialEnhancements,1);
    for(const mutate of [g=>g.save['0'][3]=60,g=>g.save['0'][6]=2560,
        g=>g.save.inventory.装备栏.刀.value.level=11,g=>g.save['1'][16]='口才']){
        const g=clone(f);mutate(g);assert.throws(()=>A.assertActor(g.save,g.chapter));
    }
});
test('Type61 return proof refuses a historical record for the same run',()=>{
    const before=actorFixture().save,after=clone(before);
    after.ext={bookshelf:{lastRun:book,routes:{'cf6-sting.type61':{history:[{runId:book,bookId:'cf6-sting',routeId:'type61',sp:0,outcome:'retreat'}]}}}};
    assert.equal(A.assertReturned(before,after,book,'type61').routeId,'type61');
    assert.throws(()=>A.assertReturned(before,after,book,'historical'));
    after.ext.bookshelf.routes['cf6-sting.type61'].history[0].routeId='historical';
    assert.throws(()=>A.assertReturned(before,after,book,'type61'));
});
async function clientFixture(){
    const parent=fs.realpathSync.native(os.tmpdir()),tmp=fs.mkdtempSync(path.join(parent,'cf7-cf6-e2e-fixture-'));
    try{
        fs.writeFileSync(path.join(tmp,'launcher_ports.json'),JSON.stringify({pid:7001,httpPort:18080,socketPort:18081}));
        fs.writeFileSync(path.join(tmp,'legacy-http-credential.json'),JSON.stringify({token:'fixture'}));
        const calls=[];const context={projectRoot:tmp,portsFile:path.join(tmp,'launcher_ports.json'),pid:7001,httpPort:18080,socketPort:18081,
            authorizationHeaders:{'X-CF7-Automation-Token':'fixture'},credential:{path:path.join(tmp,'legacy-http-credential.json'),header:'X-CF7-Automation-Token',
                token:'fixture-secret',pid:7001,processStartUtcTicks:'638900000000000001',lifecycleId:'fixture-life',
                capabilities:['legacy.console','legacy.status','legacy.task','legacy.logs']}};
        const session=Launcher.openAuthenticatedLegacyHttpSession({root:tmp,contextReader:()=>context,
            requestImpl:async(_c,method,pathname,body)=>{calls.push({method,pathname,body});return{statusCode:200,text:'{"success":true}'};}});
        await session.agentControl('openBookshelf',{expectedSlot:origin,expectedAttemptId:'attempt-fixture'});
        assert.deepStrictEqual(calls[0].body,{task:'agent_control',action:'openBookshelf',expectedSlot:origin,expectedAttemptId:'attempt-fixture'});
        for(const extra of ['bookId','token','cmd','snapshot','panel'])await assert.rejects(()=>session.agentControl('openBookshelf',{
            expectedSlot:origin,expectedAttemptId:'attempt-fixture',[extra]:'forbidden'}));
        await assert.rejects(()=>session.agentControl('openBookshelf',{expectedSlot:'crazyflasher7_saves',expectedAttemptId:'attempt-fixture'}));
        assert.equal(calls.length,1);passed++;console.log('PASS fixed opener client rejects business payloads');
    }finally{
        const resolved=path.resolve(tmp);assert.equal(path.dirname(resolved),parent);assert(path.basename(resolved).startsWith('cf7-cf6-e2e-fixture-'));
        fs.rmSync(resolved,{recursive:true,force:true});
    }
}
clientFixture().then(()=>console.log('CF6 E2E offline safety cases: '+passed+'/'+passed)).catch(error=>{console.error(error.stack||error);process.exitCode=1;});
