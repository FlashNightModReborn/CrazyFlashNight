import fs from 'node:fs';
import {computeMonsterRow} from '../../tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';
const input=JSON.parse(fs.readFileSync('tools/cf6-elder-assets/balance-inputs.json','utf8')).robot.input;
const val=(a:number,b:number,l:number)=>Math.floor(Math.round(a)+(Math.round(b)-Math.round(a))*l/59);
const rows=[.9,1,1.1,1.2].map(growthFactor=>{
  const p=computeMonsterRow({...input,growthFactor});
  return {growthFactor,levels:[30,60,99].map(level=>({level,hp:val(p.hpMin,p.hpMax,level),atk:val(p.atkMin,p.atkMax,level),def:val(p.defMin,p.defMax,level)}))};
});
console.log(JSON.stringify({scope:'Alternative formula estimates only; all flags except robot growth fixed to R9',rows},null,2));
