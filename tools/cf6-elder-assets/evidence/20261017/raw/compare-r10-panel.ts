import fs from 'node:fs';
import {computeMonsterRow} from '../../tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';
const inputs=JSON.parse(fs.readFileSync('tools/cf6-elder-assets/balance-inputs.json','utf8'));
const val=(a:number,b:number,l:number)=>Math.floor(Math.round(a)+(Math.round(b)-Math.round(a))*l/59);
const rows=[];
for(const [name,attackBias,robotDefenseBias] of [['r9-current',2,40],['j2.5-l50',2.5,50],['j3-l60',3,60]] as const){
  for(const form of ['human','robot']){
    const p=computeMonsterRow({...inputs[form].input,highAtkFactor:attackBias,highDefFactor:form==='robot'?robotDefenseBias:4});
    rows.push({name,form,levels:[30,60,99].map(level=>({level,hp:val(p.hpMin,p.hpMax,level),atk:val(p.atkMin,p.atkMax,level),def:val(p.defMin,p.defMax,level)}))});
  }
}
console.log(JSON.stringify({scope:'Formula estimates only. Fixed stage/tier and observed action factors; no predicted combat qualification.',rows},null,2));
