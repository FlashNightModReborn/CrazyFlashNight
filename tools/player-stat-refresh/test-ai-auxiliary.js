'use strict';
// Executes production functions; native AVM1 and in-game journeys remain separate.
const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
const {createSource}=require('./source');
const source=createSource(process.argv.find(x=>x.startsWith('--source='))?.slice(9)||path.resolve(__dirname,'../..'));
const {fixture:baseFixture}=require('./persistent-source-probe');
function fixture(source){const f=baseFixture(source);f.target.被动技能={独行者:{等级:0,启用:false}};return f;}
const results=[];
function check(name,fn){try{fn();results.push({name,passed:true});}catch(e){results.push({name,passed:false,error:e.message});}}
const policySource=createSource(path.resolve(__dirname,'../..'));
const limit=policySource.fn('scripts/类定义/org/flashNight/arki/unit/UnitAI/behavior/LegacyUnarmedSkillChance.as','function limit(');
for(const [label,value] of [['nan',NaN],['missing',undefined],['infinite',Infinity],['negative',-1]])check('auxiliary_'+label+'_does_not_reject_player',()=>{
 const f=fixture(source),t=f.target,record=f.api.buildPersistentSnapshot(t);
 record.unbuffed.佣兵技能概率抑制基数=value;
 f.api.applyPersistentSnapshot(t,record);
 assert.deepEqual([t.hp,t.mp,t.空手攻击力],[600,200,100]);
 assert.equal(limit(100,t.佣兵技能概率抑制基数),0);
});
check('valid_refresh_retains_ai_value_updates',()=>{
 const f=fixture(source),t=f.target;
 t.__persistentEquipmentInputV1.slots.手部装备.data.punch=16;
 f.api.applyPersistentSnapshot(t,f.api.buildPersistentSnapshot(t));
 assert.equal(t.佣兵技能概率抑制基数,4);assert.equal(limit(100,t.佣兵技能概率抑制基数),86);
 t.__persistentEquipmentInputV1.slots.手部装备.data.punch=-5;
 f.api.applyPersistentSnapshot(t,f.api.buildPersistentSnapshot(t));
 assert.equal(t.佣兵技能概率抑制基数,0);assert.equal(t.空手攻击力,95);
});
check('valid_probabilities_keep_original_formula',()=>{
 for(const chance of [0,20,50,100,200])for(const weight of [0,4,81,2500])
  assert.equal(limit(chance,weight),Math.min(chance,100-(Math.sqrt(weight)+5)*2));
});
check('malformed_ai_value_declines_optional_skill',()=>{
 for(const v of [null,undefined,'4',{},NaN,Infinity,-Infinity,-1])assert.equal(limit(100,v),0);
});
check('required_bad_hp_still_fails_before_commit',()=>{
 const f=fixture(source),t=f.target,record=f.api.buildPersistentSnapshot(t);
 record.unbuffed.hp满血值=NaN;
 assert.throws(()=>f.api.applyPersistentSnapshot(t,record),/stat_output_invalid/);
 assert.equal(t.hp,600);
});
const report={evidenceTier:'node-source-extraction',passed:results.filter(x=>x.passed).length,failed:results.filter(x=>!x.passed).length,results,sourceEvidence:[...source.evidence,...policySource.evidence]};
const dest=process.argv.find(x=>x.startsWith('--output='))?.slice(9);if(dest)fs.writeFileSync(dest,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({passed:report.passed,failed:report.failed}));
for(const r of results)if(!r.passed)console.error(r.name,r.error);
if(report.failed)process.exitCode=1;
