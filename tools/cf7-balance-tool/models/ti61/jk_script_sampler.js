/* Bounded projection of JK's frame scripts into emission timelines.
 * This executes arithmetic/control-flow in a restricted JS context, not AVM1.
 * Geometry, travel, hit admission, hurt animation and target movement are inputs
 * to the downstream sensitivity model. No Flash assets or game state are written.
 */
'use strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {pathToFileURL} from 'node:url';

function blocks(code) {
  const result = {};
  const re = /onClipEvent\s*\(\s*(load|enterFrame|unload)\s*\)\s*\{/g;
  let m;
  while ((m = re.exec(code))) {
    let depth = 1, i = re.lastIndex;
    for (; i < code.length && depth; i++) {
      if (code[i] === '{') depth++;
      if (code[i] === '}') depth--;
    }
    if (depth) throw new Error('unclosed event');
    result[m[1]] = code.slice(re.lastIndex, i - 1);
    re.lastIndex = i;
  }
  return result;
}

const compiled = new Map();
function execute(code, context, identity) {
  if (!code) return;
  let script = compiled.get(code);
  if (!script) {
    const js = code.replace(/\band\b/g, '&&').replace(/\bor\b/g, '||')
      .replace(/\bvar\s+([\w\u0080-\uFFFF]+)\s*:\s*(Number|Object|String|Boolean|MovieClip)\b/g, 'var $1');
    script = new vm.Script(js, {filename: identity});
    compiled.set(code, script);
  }
  try { script.runInContext(context); }
  catch (error) {
    if (error && error.frameTransition) return;
    throw new Error(identity + ': ' + error.stack);
  }
}

function sample(source, spec) {
  let rng = spec.seed >>> 0 || 1;
  const rand = () => {rng ^= rng << 13; rng ^= rng >>> 17; rng ^= rng << 5; return (rng >>> 0) / 4294967296;};
  const noop = () => {};
  const emissions = [], visits = [];
  let timelineName = 'ground', frame = 1, tick = 0, jump = null, ended = false, stopped = false;
  let sourceRow = null, active = new Map(), jumpedBackward = false;
  const target = {_name: 'player', _x: spec.distance, _y: 0, Z轴坐标: 0,
    hp: 6405 * (spec.playerHpRatio || 1), hp满血值: 6405, 防御力: spec.defence,
    无敌: false, 浮空高度: 0, 状态: '长枪站立', man: {无敌标签: false}, area: {}};
  const transition = () => {throw {frameTransition: true};};
  const unit = {_name: 'jk', _x: 0, _y: 0, Z轴坐标: 0, 等级: 100,
    hp: 3770762.5 * spec.bossHpRatio, hp满血值: 3770762.5, 空手攻击力: 21482.5,
    近战招式: spec.attack, 攻击目标: 'player', 是否为敌人: true, 方向: '右',
    行走X速度: 9.7, y轴攻击范围: 30, 反击动画中: false, area: {_y: 0},
    枪械技能库: ['长枪蹲射', '左轮射击', '单喷', '腰射', '左轮拔枪', '枪斗术'], 枪械技能随机数: 6,
    移动: noop, 方向改变: function(s) {this.方向 = s;},
    动画完毕: () => {ended = true; transition();},
    状态改变: state => {if (state === '空手跳') {jump = {timeline: 'air', frame: 1}; transition();}},
  };
  function emit(p) {
    if (!Number.isFinite(Number(p.子弹威力))) throw new Error('non-finite power at ' + sourceRow.id);
    emissions.push({tick, timeline: timelineName, sourceFrame: frame, sourceLayer: sourceRow.layer,
      bullet: p.子弹种类, power: Number(p.子弹威力), split: Number(p.霰弹值 || 1),
      type: p.伤害类型 || (String(p.子弹种类).includes('真伤') ? '真伤' : '物理'),
      slay: Number(p.斩杀 || 0), rout: Number(p.血量上限击溃 || 0),
      reflectionDisabled: !!unit.不反击});
  }
  const root = {gameworld: {player: target, jk: unit, globalToLocal: noop},
    成功率: p => rand() * 100 < p, 子弹属性初始化: () => ({}),
    子弹区域shoot传递: emit, 播放音效: noop, 发布消息: noop, 发布调试消息: noop,
    子弹区域shoot: (sound, split, diffusion, muzzle, bullet, power) => emit({子弹种类: bullet, 子弹威力: power, 霰弹值: split})};
  const common = {_root: root, random: n => Math.floor(rand() * Math.floor(n)), trace: noop,
    isNaN, Math, Number, String, Boolean, NaN, Infinity, int: x => x < 0 ? Math.ceil(x) : Math.floor(x)};
  let man;
  function makeMan() {
    man = vm.createContext(Object.assign({}, common, {_parent: unit, _x: 0, _y: 0,
      localToGlobal: noop, hitTest: () => true, _currentframe: frame,
      gotoAndPlay: label => {
        const destination = typeof label === 'number' ? label : source.timelines[timelineName].labels[label];
        if (!destination) throw new Error('unknown label: ' + label);
        jump = {timeline: timelineName, frame: destination};
        stopped = false; transition();
      }, stop: () => {stopped = true;}, play: () => {stopped = false;}}));
    unit.man = man;
  }
  makeMan();
  while (!ended && tick < 1200) {
    let jumps = 0;
    do {
      jump = null;
      man._currentframe = frame;
      const table = source.timelines[timelineName];
      for (const row of table.frames) {
        if (row.frame !== frame || row.code.includes('onClipEvent')) continue;
        sourceRow = row;
        execute(row.code, man, timelineName + ':' + row.id);
        if (jump || ended) break;
      }
      if (jump) {
        jumpedBackward = jump.timeline === timelineName && jump.frame < frame;
        if (jump.timeline !== timelineName) {
          timelineName = jump.timeline; frame = jump.frame; active = new Map(); makeMan();
        } else frame = jump.frame;
      }
      if (++jumps > 30) throw new Error('same-tick transition loop');
    } while (jump && !ended);
    if (ended) break;
    visits.push({tick, timeline: timelineName, frame, noCounter: !!unit.不反击});
    const rows = source.timelines[timelineName].frames.filter(row =>
      row.code.includes('onClipEvent') && row.frame <= frame && frame < row.frame + row.duration &&
      (row.code.includes('子弹区域shoot') || row.code.includes('额外攻击')));
    const keys = new Set(rows.map(row => row.id));
    for (const [key, child] of active) {
      if (!keys.has(key) || (spec.resetEmitterOnLoop && jumpedBackward)) {
        sourceRow = child.row;
        execute(child.handlers.unload, child.ctx, timelineName + ':' + key + ':unload'); active.delete(key);
      }
    }
    jumpedBackward = false;
    for (const row of rows) {
      if (!active.has(row.id)) {
        const ctx = vm.createContext(Object.assign({}, common, {_parent: man, _x: 0, _y: 0, area: {},
          localToGlobal: noop, stop: noop, play: noop}));
        const child = {row, ctx, handlers: blocks(row.code)};
        sourceRow = row;
        execute(child.handlers.load, ctx, timelineName + ':' + row.id + ':load'); active.set(row.id, child);
      }
    }
    for (const child of active.values()) {
      sourceRow = child.row;
      execute(child.handlers.enterFrame, child.ctx, timelineName + ':' + child.row.id + ':enterFrame');
    }
    tick++;
    if (!stopped) frame++;
    if (frame > source.timelines[timelineName].duration) ended = true;
  }
  return {spec, durationFrames: tick + 1, completed: ended, emissions, visits};
}

function main() {
  const args = process.argv.slice(2);
  const option = name => args[args.indexOf(name) + 1];
  const source = JSON.parse(fs.readFileSync(option('--source'), 'utf8'));
  const count = Number(option('--samples') || 16);
  const defence = args.includes('--defence') ? Number(option('--defence')) : 8729;
  const attacks = ['长枪蹲射', '腰射', '左轮射击', '左轮拔枪', '枪斗术', '单喷',
    '居合', '五连斩', '完整重斩', '拔刀', '四向拔刀', '次元斩', '空间斩', '斩杀空间斩', '高空下劈', '空中次元斩'];
  const results = [];
  for (const attack of attacks) {
    const distances = ['居合', '五连斩', '完整重斩'].includes(attack) ? [100] : [300];
    for (const distance of distances) for (const bossHpRatio of [1, 0.3]) {
      for (let seed = 1; seed <= count; seed++) results.push(sample(source, {
        attack, distance, bossHpRatio, defence, seed: seed * 2654435761 >>> 0,
        resetEmitterOnLoop: false}));
    }
  }
  for (const attack of ['长枪蹲射', '腰射']) results.push(sample(source, {
    attack, distance: 300, bossHpRatio: 1, defence, seed: 1, resetEmitterOnLoop: true}));
  fs.writeFileSync(option('--out'), JSON.stringify({sourceIdentity: source.identity,
    evidence: 'Source frame-script arithmetic/control projection. Fixed distance; no AVM1/display-list/physics execution.',
    results}, null, 2));
  console.log(JSON.stringify({runs: results.length, emissions: results.reduce((n,r)=>n+r.emissions.length,0),
    truncated: results.filter(r=>!r.completed).length}));
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
export {sample, blocks};
