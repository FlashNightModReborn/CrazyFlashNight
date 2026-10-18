import fs from 'node:fs';
import {computeMonsterRow} from '../../tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';

const source = 'tools/cf6-elder-assets/balance-inputs.json';
const input = JSON.parse(fs.readFileSync(source, 'utf8')).robot.input;
if (input.growthFactor !== 1 || input.highDefFactor !== 34) throw new Error('Expected unchanged R15 inputs');
const value = (a: number, b: number, level: number) => Math.floor(Math.round(a) + (Math.round(b) - Math.round(a)) * level / 59);
const rows = [1, .95, .9, .85].map(growthFactor => {
  const panel = computeMonsterRow({...input, growthFactor});
  return {growthFactor, levels: [30, 60, 99].map(level => ({
    level,
    hp: value(panel.hpMin, panel.hpMax, level),
    atk: value(panel.atkMin, panel.atkMax, level),
    def: value(panel.defMin, panel.defMax, level),
  }))};
});
console.log(JSON.stringify({scope: 'Read-only formula estimates. R15 remains running and unchanged; only robot growth varies in this calculation. Not combat evidence.', source, rows}, null, 2));
