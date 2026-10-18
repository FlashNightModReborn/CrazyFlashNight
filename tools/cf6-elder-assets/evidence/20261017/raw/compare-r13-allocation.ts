import fs from 'node:fs';
import {computeMonsterRow} from '../../tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';
const input=JSON.parse(fs.readFileSync('tools/cf6-elder-assets/balance-inputs.json','utf8')).robot.input;
const at=(a:number,b:number,l:number)=>Math.floor(Math.round(a)+(Math.round(b)-Math.round(a))*l/59);
const rows=[28,30,32,40].map(highDefFactor=>{
  const p=computeMonsterRow({...input,highDefFactor});
  return {highDefFactor,levels:[30,60,99].map(level=>{
    const hp=at(p.hpMin,p.hpMax,level),attack=at(p.atkMin,p.atkMax,level),defense=at(p.defMin,p.defMax,level);
    return {level,hp,attack,defense,physicalEffectiveHp:Math.round(hp*(1+defense/300))};
  })};
});
console.log(JSON.stringify({scope:'Unadopted formula estimates only. Physical effective HP ignores magic, healing, hit geometry and action interruptions; it is not a field result.',rows},null,2));
