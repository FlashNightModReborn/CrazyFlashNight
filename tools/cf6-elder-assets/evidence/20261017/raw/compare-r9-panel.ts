import fs from 'node:fs';
import {computeMonsterRow} from '../../tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';
const input=JSON.parse(fs.readFileSync('tools/cf6-elder-assets/balance-inputs.json','utf8')).robot.input;
const val=(a:number,b:number,l:number)=>Math.floor(Math.round(a)+(Math.round(b)-Math.round(a))*l/59);
const rows=[28,36,40,44].map(defenseBias=>{
  const p=computeMonsterRow({...input,highDefFactor:defenseBias});
  return {defenseBias,levels:[30,60,99].map(level=>{
    const hp=val(p.hpMin,p.hpMax,level),def=val(p.defMin,p.defMax,level);
    return {level,hp,atk:val(p.atkMin,p.atkMax,level),def,physicalEhp:Math.round(hp*(def+300)/300)};
  })};
});
console.log(JSON.stringify({scope:'Formula estimates only, unchanged AI and growth 0.9; no real-combat outcome asserted',rows},null,2));
