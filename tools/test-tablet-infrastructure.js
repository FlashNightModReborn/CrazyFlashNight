/** #259: Infra requirements are a lossless projection of the XML source of truth.
 * Run: node tools/test-tablet-infrastructure.js (no FFDec, Flash, or .NET required). */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { parseInfrastructure, splitInfrastructureLevels } = require('./bake-tablet-assets');

const root = path.resolve(__dirname, '..');
const actual = JSON.parse(fs.readFileSync(
  path.join(root, 'launcher/web/assets/tablet/infrastructure.json'), 'utf8'));
const projected = parseInfrastructure();
assert.deepStrictEqual(actual, projected, 'infrastructure.json must match infrastructure.xml');
assert.equal(projected.length, 9, 'check all current projects');

const gates = projected.flatMap(it => it.levels.flatMap((lv, index) =>
  lv.skills.map(s => [it.name, index, s.name, s.level])));
assert.deepStrictEqual(gates, [
  ['摩托车', 0, '驾驶', 1],
  ['越野车', 0, '驾驶', 2],
  ['停机坪梯子', 1, '逆向', 1],
  ['统合标准化学处理器', 0, '逆向', 2],
  ['基地供电与照明', 1, '逆向', 1],
  ['基地供电与照明', 2, '逆向', 2]
]);

const fixture = '<Infrastructure><Name>fixture</Name>'
  + '<Level id="0"><Skill><Name>逆向</Name><Level>2</Level></Skill></Level>'
  + '<Level id="1"><Description>built</Description></Level>'
  + '</Infrastructure>';
assert.equal(parseInfrastructure(fixture)[0].levels[0].skills[0].level, 2);
assert.equal(parseInfrastructure(fixture)[0].maxLevel, 1);
assert.throws(() => splitInfrastructureLevels('<Level id="0"><Level>2</Level>'),
  /unclosed infrastructure Level/);
assert.throws(() => splitInfrastructureLevels('</Level>'),
  /unexpected closing infrastructure Level/);

console.log('[test-tablet-infrastructure] OK: 9 projects, 6 skill requirements, balanced Level parsing');

