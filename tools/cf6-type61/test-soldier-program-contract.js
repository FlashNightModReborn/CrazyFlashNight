'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),path=require('node:path');
const {execFileSync}=require('node:child_process');
const {loadStaticClass}=require('../cf6-soldier-assets/offline/as2-source');
const c=vm.createContext({isFinite,Math,length:value=>typeof value==='string'?value.length:0});
const contract=loadStaticClass(c,path.resolve(__dirname,'../../scripts/类定义/org/flashNight/arki/scene/Cf6SoldierProgramContract.as'),'Cf6SoldierProgramContract');
const raw=execFileSync('python',['-X','utf8','-B','-c',"import sys,json;sys.path.insert(0,'tools/cf6-type61');import fixed_roster;print(json.dumps(fixed_roster.runtime_catalog(),ensure_ascii=False))"],{cwd:path.resolve(__dirname,'../..'),encoding:'utf8'});
const config=()=>vm.runInContext('JSON.parse('+JSON.stringify(raw)+')',c);
test('all158 closed programs and identity mappings are runtime admissible',()=>{
 const d=config();for(const [key,p] of Object.entries(d.profiles))assert.equal(contract.profile(p),true,key+' '+p.program.trigger);
 assert.equal(contract.valid(d),true);assert.equal(Object.keys(d.identities).length,158);
});
const bad={
 'unknown instructor trigger':p=>p.program.trigger='adaptive_guess',
 'separator cannot masquerade as an enum':p=>p.role='line|suppress',
 'unbounded pressure range':p=>p.program.fireDistance=1201,
 'pressure range below tactical window':p=>p.program.fireDistance=p.program.maxDistance-1,
 'unknown executable key':p=>p.program.eval='anything',
 'unknown stage':p=>p.program.stages[0].kind='teleport',
 'unknown mode':p=>p.program.stages[0].mode='both',
 'unbounded stage':p=>p.program.stages[0].frames=NaN,
 'negative warning lock':p=>p.program.stages[0].lock=-1,
 'fractional stage':p=>p.program.stages[0].frames=.5,
 'excess real triggers':p=>p.program.stages[1].events=99,
 'missing recovery':p=>p.program.stages.at(-1).kind='wait',
 'unknown capability':p=>p.program.capabilities.push('free_fire'),
 'duplicate capability':p=>p.program.capabilities.push(p.program.capabilities[0]),
 'fire without a warning':p=>{p.program.stages[0].kind='draw';},
};
for(const [label,mutate] of Object.entries(bad))test(label,()=>{
 const d=config(),p=Object.values(d.profiles).find(p=>p.program.trigger==='judgment_line');mutate(p);assert.equal(contract.valid(d),false);
});
test('identity map cannot omit, add or redirect a fixed person to an unknown profile',()=>{
 for(const edit of [d=>delete d.identities[Object.keys(d.identities)[0]],d=>d.identities.fake=Object.values(d.identities)[0],
   d=>Object.values(d.identities)[0].profileId='unknown',d=>Object.values(d.identities)[0].mapId='A99',
   d=>Object.values(d.identities)[0].roleClass='instructor']){const d=config();edit(d);assert.equal(contract.valid(d),false);}
});

test('sustained windows bind nineteen actual guns and reject drift in frames, identity and recovery',()=>{
 const d=config(),guns=Object.values(d.profiles).filter(p=>p.program.suppression);
 assert.equal(Object.values(d.identities).filter(row=>d.profiles[row.profileId].program.suppression).length,19);
 assert.equal(guns.length,11);
 for(const mutate of [p=>p.program.suppression.fireFrames=61,p=>p.program.suppression.recoveryFrames=29,
   p=>p.program.suppression.weaponType='狙击枪',p=>p.program.suppression.weaponName='',
   p=>p.budget.primaryTriggerLimit=61,p=>p.program.stages.at(-1).frames=29,
   p=>{p.program.stages.find(s=>s.kind==='fire'&&s.mode==='primary').gap=2;},
   p=>delete p.program.suppression]){
  const p=vm.runInContext('JSON.parse('+JSON.stringify(JSON.stringify(guns[0]))+')',c);
  mutate(p);assert.equal(contract.profile(p),false);
 }
});
