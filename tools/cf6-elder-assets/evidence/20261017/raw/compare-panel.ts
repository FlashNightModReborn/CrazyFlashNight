import fs from 'node:fs';
import {computeMonsterRow} from '../../tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';
const inputs=JSON.parse(fs.readFileSync('tools/cf6-elder-assets/balance-inputs.json','utf8'));
const variants=[['current',1,1,4,2,9],['attack-human-def-robot',1,2,4,2,14],['balanced',1,1.5,3,1.8,12],['lower-growth',.7,1.5,3,1.8,12],['r8-initial-draft',1,2,4,2,25],['r8-robot-growth-candidate',.9,2,4,2,28]];
const rows=[];
for(const [name,g,hj,hl,rj,rl] of variants){
 for(const form of ['human','robot']){
  const p=computeMonsterRow({...inputs[form].input,growthFactor:g,highAtkFactor:form==='human'?hj:rj,highDefFactor:form==='human'?hl:rl});
  const val=(a:number,b:number,l:number)=>Math.floor(Math.round(a)+(Math.round(b)-Math.round(a))*l/59);
  rows.push({name,form,levels:[30,60,99].map(level=>({level,hp:val(p.hpMin,p.hpMax,level),atk:val(p.atkMin,p.atkMax,level),def:val(p.defMin,p.defMax,level)}))});
 }
}
console.log(JSON.stringify(rows,null,2));
