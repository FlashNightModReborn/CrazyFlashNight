'use strict';
// Pure checks. A book-run slot is admitted only by exact observed production identities.
const {canonicalJson,sha256Text}=require('../workbench-live-e2e/kshop/common');
const {resolveRoute}=require('./route-config');
const SLOT=/^bookrun_[a-f0-9]{24}$/;
function artifactSlot(entry) {
    const match=String(entry.locator||'').replace(/\\/g,'/').match(/\/([^/]+)\.(json|sol)$/i);
    return match ? match[1] : null;
}
function admit({before,request,receipt,receiptRequest,originSave,runSave,originSlot,instance,routeId}) {
    const route=resolveRoute(routeId);
    const active=originSave?.ext?.bookshelf?.active;
    const run=runSave?.ext?.bookRun;
    if (!request || request.type!=='panel' || request.panel!=='bookshelf' || request.domain!=='bookshelf'
            || request.cmd!=='commit' || request.panelInstanceId!==instance || !request.callId
            || request.payload?.kind!=='play' || request.payload?.target!==route.playTarget
            || !/^sha256:[a-f0-9]{64}$/.test(request.payload.token||'')) throw Error('missing exact observed production play request');
    if (!receipt || receipt.type!=='panel_resp' || receipt.panel!=='bookshelf' || receipt.domain!=='bookshelf'
            || receipt.panelInstanceId!==instance || receipt.token!==request.payload.token
            || !['commit','query'].includes(receipt.cmd) || receipt.kind!=='play' || receipt.target!==route.playTarget
            || receipt.success!==true || !['switching','applied'].includes(receipt.phase))
        throw Error('missing successful production entry receipt');
    const paired=receipt.cmd==='commit'?request:receiptRequest;
    if(!paired||paired.type!=='panel'||paired.panel!=='bookshelf'||paired.domain!=='bookshelf'
            ||paired.cmd!==receipt.cmd||paired.callId!==receipt.callId||paired.panelInstanceId!==instance
            ||paired.payload?.token!==request.payload.token)throw Error('entry receipt has no exact observed request');
    if (!active || !run || !SLOT.test(active.slot) || active.slot!==run.slot
            || active.bookId!=='cf6-sting' || run.bookId!=='cf6-sting'
            || active.routeId!==route.id || run.routeId!==route.id
            || active.originSlot!==originSlot || run.originSlot!==originSlot
            || active.seed!==run.seed || !Number.isInteger(run.seed) || run.seed<1
            || (receipt.pendingRun!==run.slot && receipt.activeSlot!==run.slot))
        throw Error('production receipt, origin credential and book save do not match');
    if (!before || !Array.isArray(before.artifacts) || before.artifacts.some(entry=>artifactSlot(entry)?.toLowerCase()===run.slot))
        throw Error('affiliated book slot existed before this journey');
    const evidence={schema:'cf7-cf6-e2e.affiliated-slot.v1',slot:run.slot,originSlot,bookId:run.bookId,routeId:run.routeId,
        seed:run.seed,instance,playCallId:request.callId,tokenRef:request.payload.token,
        receiptPhase:receipt.phase,preexisting:false};
    evidence.sha256=sha256Text(canonicalJson(evidence));
    return evidence;
}
function assertCollateral(before,after,admission) {
    const a=before.artifacts,b=after.artifacts;
    if (before.root!==after.root || before.appDataRoot!==after.appDataRoot || before.excludedTargetSlot!==after.excludedTargetSlot)
        throw Error('save universe ownership changed');
    let slot=null;
    if (admission) {
        const payload={...admission};delete payload.sha256;
        if (!SLOT.test(admission.slot) || admission.preexisting!==false || admission.originSlot!==before.excludedTargetSlot
                || admission.sha256!==sha256Text(canonicalJson(payload))
                || a.some(entry=>artifactSlot(entry)?.toLowerCase()===admission.slot)) throw Error('invalid affiliated admission');
        slot=admission.slot;
    }
    const baseline=new Map(a.map(entry=>[entry.locator,entry]));
    for (const entry of b) {
        const original=baseline.get(entry.locator);
        if (original) {
            if (canonicalJson(original)!==canonicalJson(entry)) throw Error('preexisting save artifact changed: '+entry.locator);
            baseline.delete(entry.locator);
        } else if (!slot || artifactSlot(entry)!==slot) throw Error('unregistered save artifact appeared: '+entry.locator);
    }
    if (baseline.size) throw Error('preexisting save artifact disappeared');
    return {protectedArtifacts:a.length,affiliatedSlot:slot,affiliatedArtifacts:b.filter(entry=>artifactSlot(entry)===slot)};
}
function assertReturned(before,after,slot,routeId) {
    const route=resolveRoute(routeId);
    const result=after?.ext?.bookshelf?.routes?.['cf6-sting.'+route.id];
    const record=result?.history?.find(entry=>entry.runId===slot);
    if (after?.ext?.bookRun || after?.ext?.bookshelf?.active || after?.ext?.bookshelf?.lastRun!==slot
            || !record || record.bookId!=='cf6-sting' || record.routeId!==route.id || record.sp!==0
            || !['victory','failure','defeat','retreat','abandoned'].includes(record.outcome))
        throw Error('origin clone has no settled exact CF6 result');
    // Temporary build must never cross back into the origin clone's character assets.
    for (const key of ['0','1','4','5','7','inventory','collection','infrastructure','pets','tasks','shop']) {
        if (canonicalJson(before[key])!==canonicalJson(after[key])) throw Error('origin character field changed: '+key);
    }
    return {runId:slot,outcome:record.outcome,sp:record.sp,originAssetsUnchanged:true,routeId:record.routeId};
}
function assertActor(save,chapter) {
    const route=resolveRoute(chapter.routeId),actor=chapter.actor,core=save['0'],appearance=save['1'];
    if(!core||core[0]!==actor.name||core[1]!==actor.gender||core[3]!==route.level||core[4]!==route.experience
            ||core[5]!==actor.height||core[6]!==chapter.startingSkillPoints||core[2]!==chapter.startingMoney
            ||appearance?.[0]!==actor.face||appearance?.[1]!==actor.hair)
        throw Error('selected-route initial actor or spendable resources differ from chapter');
    const equipment=save.inventory?.装备栏;
    if(!equipment)throw Error('selected-route equipment container absent');
    for(const entry of actor.equipment) {
        if(equipment[entry.slot]?.name!==entry.name||equipment[entry.slot]?.value?.level!==route.enhancement)
            throw Error('selected-route initial equipment or enhancement mismatch: '+entry.slot);
    }
    const learned=(save['5']||[]).filter(row=>Array.isArray(row)&&row[0]);
    if(learned.length!==actor.skills.length||new Set(learned.map(row=>row[0])).size!==learned.length
            ||actor.skills.some(skill=>!learned.some(row=>row[0]===skill.name&&row[1]===skill.level)))
        throw Error('selected-route fixed initial skill list mismatch');
    if(route.id==='type61') {
        const quick=actor.quickSkills||[];
        if(!Array.isArray(save['1'])||save['1'].length<28
                ||Array.from({length:12},(_,i)=>save['1'][16+i]).some((v,i)=>v!==(quick[i]||'')))
            throw Error('Type61 initial quick skills differ from the chapter');
    }
    return {routeId:route.id,name:core[0],level:core[3],experience:core[4],equipmentCount:actor.equipment.length,
        fixedSkillCount:learned.length,allInitialEnhancements:route.enhancement,spendableSp:core[6]};
}
module.exports={admit,assertCollateral,assertReturned,assertActor,artifactSlot,SLOT};
