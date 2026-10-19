"use strict";
// Preserve a canonical repeat=3 plan, then interleave one blue/red pair per independent shard.
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert/strict');
const {normalizeManifest}=require('../../tools/arena-calibration/lib/arena-calibration-core');
const load=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const put=(p,value)=>fs.writeFileSync(p,JSON.stringify(value,null,2)+'\n',{flag:'wx'});
assert.equal(process.argv.length,4);
const sourceRoot=path.resolve(process.argv[2]),outputRoot=path.resolve(process.argv[3]);
assert(outputRoot.startsWith(path.join(process.cwd(),'tmp')+path.sep));assert(!fs.existsSync(outputRoot));
const originalPlan=load(path.join(sourceRoot,'experiment-plan.json'));
const identity=load(path.join(sourceRoot,'input-identity.json'));
assert.equal(originalPlan.workers.length,1);assert.equal(originalPlan.groups.length,6);
assert.equal(identity.repeat,3);assert.equal(identity.expectedRows,36);assert.deepEqual(identity.levels,[60,80,100]);
const prepared=originalPlan.groups.map(group=>{
    assert.equal(group.mode,'serial');assert([1,2].includes(group.jobs.length));
    const originals=group.jobs.map(job=>{
        assert.equal(job.batchTimeoutMs,900000);assert.equal(job.workerId,originalPlan.workers[0].workerId);
        return {job,manifest:load(job.manifestPath)};
    });
    const cases=originals.flatMap(item=>item.manifest.cases);
    assert.equal(cases.length,2);
    assert.deepEqual(new Set(cases.map(c=>c.authorityContext.candidateSide)),new Set(['blue','red']));
    assert(cases.every(c=>c.repeat===3 && c.timeoutFrames===5400 && c.authorityContext.candidateUnitId===473 && c.authorityContext.successorUnitId===474));
    const template=originals[0].manifest;
    for(const item of originals){assert.equal(item.manifest.buildCommit,template.buildCommit);assert.deepEqual(item.manifest.planner,template.planner);}
    return {group,originals,cases,template};
});
const shards=[],mapping=[];
for(const item of prepared){
    for(let repetition=1;repetition<=3;repetition++){
        const suffix='-s'+repetition;
        const cases=item.cases.map(c=>({...c,caseId:c.caseId+suffix,repeat:1}));
        const manifest=normalizeManifest({...item.template,batchId:originalPlan.experimentId+'-'+item.group.groupId+suffix,repeat:1,cases});
        for(let i=0;i<cases.length;i++){
            const before=JSON.parse(JSON.stringify(item.cases[i])),after=JSON.parse(JSON.stringify(manifest.cases[i]));
            for(const c of [before,after]){delete c.caseId;delete c.caseHash;delete c.repeat;}
            assert.deepEqual(after,before);
        }
        shards.push({item,repetition,suffix,manifest});
    }
}
assert.equal(shards.length,18);
fs.mkdirSync(outputRoot);
const groups=[];
for(const {item,repetition,suffix,manifest} of shards){
    const file=path.join(outputRoot,item.group.groupId+suffix+'-manifest.json');put(file,manifest);
    groups.push({...item.group,groupId:item.group.groupId+suffix,jobs:[{...item.originals[0].job,jobId:item.group.groupId+'-w1'+suffix,manifestPath:file}]});
    mapping.push({originalGroup:item.group.groupId,repetition,
        originalManifests:item.originals.map(({job})=>({path:job.manifestPath,sha256:sha(job.manifestPath)})),
        shardManifest:file,shardSha256:sha(file),caseIds:manifest.cases.map(c=>c.caseId),unchangedCombatConditions:true});
}
put(path.join(outputRoot,'experiment-plan.json'),{...originalPlan,groups});
put(path.join(outputRoot,'input-identity.json'),identity);
put(path.join(outputRoot,'sharding-proof.json'),{originalPlanSha256:sha(path.join(sourceRoot,'experiment-plan.json')),
    finalPlanSha256:sha(path.join(outputRoot,'experiment-plan.json')),expectedRows:36,levels:identity.levels,
    groups:18,rowsPerGroup:2,perFightTimeoutFrames:5400,perShardWallLimitMs:900000,conditionsUnchanged:true,
    schedule:'Interleave one blue/red pair per fresh shard. Canonical generator may contain one joint job or two jobs split by side; original plans are retained.',mapping});
console.log(JSON.stringify({groups:18,rows:36,levels:identity.levels,sourcePlanPreserved:true,conditionsUnchanged:true}));
