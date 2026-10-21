import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../..');
const {computeMonsterRow}=await import(pathToFileURL(path.join(root,'tools/cf7-balance-tool/packages/core/dist/formulas/monsters.js')).href);
const file=path.join(here,'balance-inputs.json');
const record=JSON.parse(fs.readFileSync(file,'utf8'));
const actual=Object.fromEntries(Object.entries(computeMonsterRow(record.input)).map(([key,value])=>[key,typeof value==='number'?Math.floor(value):value]));
actual.speedMin=50;actual.speedMax=70;
if(process.argv.includes('--check')){
  if(JSON.stringify(actual)!==JSON.stringify(record.stats))throw Error('Monster formula projection is stale');
}else{
  record.stats=actual;
  fs.writeFileSync(file,JSON.stringify(record,null,2)+'\n');
}
console.log(JSON.stringify({check:process.argv.includes('--check'),stage:record.input.stage,tier:record.input.tierFactor,stats:actual}));
