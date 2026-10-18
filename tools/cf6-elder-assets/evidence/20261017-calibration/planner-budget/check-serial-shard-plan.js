"use strict";
const fs=require('fs'),path=require('path'),assert=require('assert');
const {createPlan}=require('../../tools/cf6-elder-assets/arena-plan');
const R=process.cwd(),O=path.join(R,'tmp/cf6-combat-calibration-20261017');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const config=read(path.join(O,'arena-r13-full-config.json'));
config.experimentId='cf6-serial-shard-check-20261018';config.outputDirectory=path.join(O,'serial-shard-check');
const before=read(path.join(O,'arena-r13-full/experiment-plan.json'));
const result=createPlan(config),plan=read(result.planPath);let rows=0;
assert.equal(plan.groups.length,6);assert.equal(plan.workers.length,1);
for(let i=0;i<plan.groups.length;i++){
 const g=plan.groups[i];assert.equal(g.mode,'serial');assert.equal(g.jobs.length,2);
 assert(g.jobs.every(j=>j.workerId===plan.workers[0].workerId && j.batchTimeoutMs===900000));
 const old=read(before.groups[i].jobs[0].manifestPath);
 const combined=g.jobs.flatMap(j=>{const m=read(j.manifestPath);assert.equal(m.timeoutFrames,5400);
   assert.equal(m.cases.reduce((n,c)=>n+c.repeat,0),3);return m.cases;});
 assert.equal(combined.length,old.cases.length);
 for(let k=0;k<combined.length;k++){
  assert.deepStrictEqual(combined[k],old.cases[k]);rows+=combined[k].repeat;
 }
}
assert.equal(rows,36);
const proof={ok:true,rows,groups:plan.groups.length,jobs:12,maximumConcurrentGames:1,caseContentsByteEquivalentAsObjects:true,coordinatorTimeoutMs:900000,perFightTimeoutFrames:5400,executed:false};
fs.writeFileSync(path.join(O,'serial-shard-plan-check.json'),JSON.stringify(proof,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(proof));
