"use strict";
// Split a frozen canonical repeat=3 plan into repeat=1 shards without changing combat conditions.
const fs=require('fs'), path=require('path'), crypto=require('crypto');
const {normalizeManifest}=require('../../tools/arena-calibration/lib/arena-calibration-core');
const assert=require('assert/strict');
const load=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const put=(p,value)=>fs.writeFileSync(p,JSON.stringify(value,null,2)+'\n',{flag:'wx'});
assert.equal(process.argv.length,4);
const sourceRoot=path.resolve(process.argv[2]), outputRoot=path.resolve(process.argv[3]);
assert(outputRoot.startsWith(path.join(process.cwd(),'tmp')+path.sep));
assert(!fs.existsSync(outputRoot));
const sourcePlan=load(path.join(sourceRoot,'experiment-plan.json'));
const identity=load(path.join(sourceRoot,'input-identity.json'));
assert.equal(sourcePlan.workers.length,1);
assert.equal(sourcePlan.groups.length,6);
assert.equal(identity.repeat,3);
assert.equal(identity.expectedRows,36);
const manifestSources=sourcePlan.groups.map(group=>{
 assert.equal(group.mode,'serial');assert.equal(group.jobs.length,1);
 assert.equal(group.jobs[0].batchTimeoutMs,900000);
 const manifest=load(group.jobs[0].manifestPath);
 assert.equal(manifest.cases.length,2);
 assert(manifest.cases.every(c=>c.repeat===3 && c.timeoutFrames===5400));
 assert.deepEqual(new Set(manifest.cases.map(c=>c.authorityContext.candidateSide)),new Set(['blue','red']));
 assert(manifest.cases.every(c=>c.authorityContext.candidateUnitId===473 && c.authorityContext.successorUnitId===474));
 return {group,manifest};
});
fs.mkdirSync(outputRoot);
const groups=[],mapping=[];
for(const {group,manifest} of manifestSources){
 for(let repetition=1;repetition<=3;repetition++){
  const suffix='-s'+repetition;
  const cases=manifest.cases.map(original=>({...original,caseId:original.caseId+suffix,repeat:1}));
  const shard=normalizeManifest({...manifest,batchId:manifest.batchId+suffix,repeat:1,cases});
  const file=path.join(outputRoot,group.groupId+suffix+'-manifest.json');
  for(let i=0;i<cases.length;i++){
   const before=JSON.parse(JSON.stringify(manifest.cases[i]));
   const after=JSON.parse(JSON.stringify(shard.cases[i]));
   for(const c of [before,after]){delete c.caseId;delete c.caseHash;delete c.repeat;}
   assert.deepEqual(after,before);
  }
  put(file,shard);
  groups.push({...group,groupId:group.groupId+suffix,jobs:[{...group.jobs[0],jobId:group.jobs[0].jobId+suffix,manifestPath:file}]});
  mapping.push({originalGroup:group.groupId,originalManifest:group.jobs[0].manifestPath,
    originalSha256:sha(group.jobs[0].manifestPath),repetition,shardManifest:file,shardSha256:sha(file),
    caseIds:shard.cases.map(c=>c.caseId),unchangedCombatConditions:true});
 }
}
assert.equal(groups.length,18);
put(path.join(outputRoot,'experiment-plan.json'),{...sourcePlan,groups});
put(path.join(outputRoot,'input-identity.json'),identity);
put(path.join(outputRoot,'sharding-proof.json'),{originalPlanSha256:sha(path.join(sourceRoot,'experiment-plan.json')),
 finalPlanSha256:sha(path.join(outputRoot,'experiment-plan.json')),expectedRows:36,groups:18,rowsPerGroup:2,
 perFightTimeoutFrames:5400,perShardWallLimitMs:900000,conditionsUnchanged:true,mapping});
console.log(JSON.stringify({groups:18,rows:36,sourcePlanPreserved:true,conditionsUnchanged:true}));
