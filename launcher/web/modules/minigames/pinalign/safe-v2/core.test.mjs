import test from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG, STRUCTURES, TOOLS, PUZZLE_TYPES, POLARITIES, resolveStructureSpec } from './config.mjs';
import { createPuzzle, enumerateParams, generatePuzzle, isLegalParams, createRng, deriveSafeSeed, DIRS, ODD_LABELS, GRILLE_MASKS } from './puzzles.mjs';
import { SafeSession } from './state.mjs';
import { createSafeModel } from './model.mjs';
import { captureGesture, projectGesture } from './gestures.mjs';

const TYPES = ['matrix', 'odd', 'grille'];
const EXPECTED_COUNTS = { matrix: 5400, odd: 5400, grille: 3600 };
const scenario700 = { puzzleType: 'matrix', puzzleParams: { aDir: 0, delta: 1, code: 700 }, a: 0, b: 0 };

function fixture(overrides = {}) {
  let now = 0;
  return {
    session: new SafeSession({ seed: 'test-700', overrides: { ...scenario700, ...overrides }, clock: () => now }),
    advance: ms => { now += ms; },
  };
}

function direction(session, stage) {
  return session.stageDirection(stage);
}

function completeStage(session, stage) {
  session.selectTool(stage === 'a' ? 'wedge' : 'hook');
  return session.operate(stage, { direction: direction(session, stage), progress: 1, commit: true });
}

/** Independent domain construction without generator constants or isLegalParams. */
function independentDomain(type) {
  const result = [];
  if (type === 'matrix') {
    for (let aDir = 0; aDir < 3; aDir++) {
      for (const delta of [1, 2]) {
        for (let code = 100; code < 1000; code++) {
          result.push({ aDir, delta, code });
        }
      }
    }
  } else if (type === 'odd') {
    for (let oddIndex = 0; oddIndex < 6; oddIndex++) {
      for (let code = 100; code < 1000; code++) {
        result.push({ oddIndex, code });
      }
    }
  } else if (type === 'grille') {
    for (let maskId = 0; maskId < 4; maskId++) {
      for (let code = 100; code < 1000; code++) {
        result.push({ maskId, code });
      }
    }
  }
  return result;
}

/**
 * Decode the rendered Chinese memo and check candidate answers in reverse.
 * Does not call solvePuzzle or read puzzle.params.code directly.
 */
function independentSolutions(puzzle) {
  let predicate;
  if (puzzle.type === 'matrix') {
    const rowMatch = /^图推矩阵：第一行 ○([▲►▼◄]) → ○([▲►▼◄])；第二行 □([▲►▼◄]) → ？。/m.exec(puzzle.memo);
    const legendMatch = /^印章对照：□▲＝(\d{3})，□►＝(\d{3})，□▼＝(\d{3})，□◄＝(\d{3})。/m.exec(puzzle.memo);
    assert.ok(rowMatch && legendMatch, 'Matrix memo must expose both rows and all 4 candidate stamp codes.');
    const aIdx = DIRS.indexOf(rowMatch[1]);
    const bIdx = DIRS.indexOf(rowMatch[2]);
    const cIdx = DIRS.indexOf(rowMatch[3]);
    const delta = (bIdx - aIdx + 4) % 4;
    const targetDir = (cIdx + delta) % 4;
    const targetCode = legendMatch[targetDir + 1];
    predicate = candidate => String(candidate) === targetCode;
  } else if (puzzle.type === 'odd') {
    const lineMatch = /^质检排异：(.+)。$/m.exec(puzzle.memo);
    assert.ok(lineMatch, 'Odd-one-out memo must list all six stamped items.');
    const entries = lineMatch[1].split('，').map(item => {
      const m = /^[①②③④⑤⑥]\[([^\]]+)\]＝(\d{3})$/.exec(item);
      assert.ok(m, `Malformed odd entry: ${item}`);
      return { tag: m[1], code: m[2] };
    });
    assert.equal(entries.length, 6);
    const tagCounts = new Map();
    for (const e of entries) tagCounts.set(e.tag, (tagCounts.get(e.tag) || 0) + 1);
    const uniqueEntry = entries.find(e => tagCounts.get(e.tag) === 1);
    assert.ok(uniqueEntry, 'Exactly one stamp must have the anomalous feature tag.');
    predicate = candidate => String(candidate) === uniqueEntry.code;
  } else {
    const gridMatch = /^转格底盘（▲在顶边）：\[([0-9 /]+)\]。/m.exec(puzzle.memo);
    const maskMatch = /^掩模缺口：(▲上缺口|▼下缺口)[^；]*；盘面孔位：①＝格(\d)，②＝格(\d)，③＝格(\d)。/m.exec(puzzle.memo);
    assert.ok(gridMatch && maskMatch, 'Grille memo must expose the 3x3 digit grid, notch orientation, and 3 hole positions.');
    const cells = gridMatch[1].replace(/\//g, ' ').trim().split(/\s+/).map(Number);
    assert.equal(cells.length, 9);
    const inverted = maskMatch[1].startsWith('▼');
    const holes = [Number(maskMatch[2]) - 1, Number(maskMatch[3]) - 1, Number(maskMatch[4]) - 1].map(idx => inverted ? 8 - idx : idx);
    const expected = holes.map(h => String(cells[h])).join('');
    predicate = candidate => String(candidate) === expected;
  }
  const answers = [];
  for (let candidate = 100; candidate <= 999; candidate++) {
    if (predicate(candidate)) answers.push(String(candidate));
  }
  return answers;
}

for (const type of TYPES) {
  test(`exhaustive ${type}: exact domain, rendered memo & SVG, independent uniqueness`, t => {
    const actual = [...enumerateParams(type)];
    const expected = independentDomain(type);
    const key = p => JSON.stringify(p);
    const actualKeys = actual.map(key).sort();
    assert.equal(new Set(actualKeys).size, actual.length, 'No duplicate parameter templates.');
    assert.equal(actual.length, EXPECTED_COUNTS[type]);
    assert.deepEqual(actualKeys, expected.map(key).sort(), 'No silently omitted or extra legal template.');
    const answers = new Set();
    let min = Infinity, max = -Infinity;
    for (const params of actual) {
      assert.equal(isLegalParams(type, params), true);
      const puzzle = createPuzzle(type, params);
      assert.match(puzzle.answer, /^[1-9][0-9]{2}$/);
      assert.ok(puzzle.svg.startsWith('<svg') && puzzle.svg.endsWith('</svg>'));
      assert.ok(puzzle.solvedSvg.startsWith('<svg') && puzzle.solvedSvg.endsWith('</svg>'));
      assert.notEqual(puzzle.svg, puzzle.solvedSvg);
      const independent = independentSolutions(puzzle);
      assert.equal(independent.length, 1, `${type} ${key(params)} must have exactly one formal answer`);
      assert.equal(independent[0], puzzle.answer, `${type} solver must match memo-derived constraints`);
      answers.add(puzzle.answer);
      min = Math.min(min, Number(puzzle.answer));
      max = Math.max(max, Number(puzzle.answer));
    }
    assert.equal(answers.size, 900, `${type} covers all 900 3-digit codes 100..999`);
    t.diagnostic(JSON.stringify({ type, templates: actual.length, candidateAnswersChecked: actual.length * 900, distinctAnswers: answers.size, min, max }));
  });
}

test('three visual reasoning rules; all six structures, both polarities, and every manual page are covered', () => {
  assert.deepEqual(PUZZLE_TYPES.map(p => p.id), TYPES);
  assert.equal(STRUCTURES.a.length, 3);
  assert.equal(STRUCTURES.b.length, 3);
  assert.deepEqual(POLARITIES, [1, -1]);
  assert.deepEqual(TOOLS.map(t => t.id).sort(), ['hook', 'wedge']);
  const pages = [...STRUCTURES.a, ...STRUCTURES.b, ...PUZZLE_TYPES].map(p => p.manualPage);
  assert.deepEqual(pages.sort((a, b) => a - b), [0, 1, 2, 3, 4, 5, 6, 7, 8]);
  for (const spec of [...STRUCTURES.a, ...STRUCTURES.b]) {
    for (const field of ['feature', 'point', 'action', 'result', 'error', 'recovery', 'next']) assert.ok(spec[field].length > 4);
  }
  for (const stage of ['a', 'b']) {
    for (let idx = 0; idx < 3; idx++) {
      const pos = resolveStructureSpec(stage, idx, 1);
      const neg = resolveStructureSpec(stage, idx, -1);
      assert.notEqual(pos.direction, neg.direction);
    }
  }
});

test('generation and variants reproduce for seeds, including Unicode; supplied params remain unmodified', () => {
  for (const seed of ['CF7-20261018', '复现-700', '', '0', '4294967295']) {
    for (const type of TYPES) assert.deepEqual(generatePuzzle(seed, { type }), generatePuzzle(seed, { type }));
    const left = new SafeSession({ seed, clock: () => 0 });
    const right = new SafeSession({ seed, clock: () => 0 });
    assert.deepEqual(left.snapshot(), right.snapshot());
    left.reset();
    assert.deepEqual(left.state.puzzle, right.state.puzzle);
    assert.deepEqual(left.state.variants, right.state.variants);
  }
  const params = { aDir: 1, delta: 2, code: 702 };
  const puzzle = createPuzzle('matrix', params);
  params.code = 800;
  assert.equal(puzzle.params.code, 702);
  const rng = createRng('range');
  for (let i = 0; i < 10000; i++) { const n = rng(); assert.ok(n >= 0 && n < 1); }
});

test('out-of-domain parameters and structural debug overrides fail before changing a live run', () => {
  const invalid = [
    ['matrix', { aDir: -1, delta: 1, code: 700 }],
    ['matrix', { aDir: 3, delta: 1, code: 700 }],
    ['matrix', { aDir: 0, delta: 0, code: 700 }],
    ['matrix', { aDir: 0, delta: 1, code: 99 }],
    ['matrix', { aDir: 0, delta: 1, code: 1000 }],
    ['odd', { oddIndex: -1, code: 700 }],
    ['odd', { oddIndex: 6, code: 700 }],
    ['odd', { oddIndex: 2, code: 99 }],
    ['grille', { maskId: -1, code: 700 }],
    ['grille', { maskId: 4, code: 700 }],
    ['grille', { maskId: 1, code: 1000 }],
    ['unknown', {}],
  ];
  for (const [type, params] of invalid) {
    assert.equal(isLegalParams(type, params), false);
    assert.throws(() => createPuzzle(type, params), RangeError);
  }
  const { session } = fixture();
  session.setNote('70');
  const before = session.snapshot();
  assert.throws(() => session.reset('bad', { ...scenario700, a: NaN }), RangeError);
  assert.deepEqual(session.snapshot(), before);
  assert.throws(() => session.reset('bad', { ...scenario700, aDir: 0 }), RangeError);
  assert.deepEqual(session.snapshot(), before);
  assert.throws(() => session.reset('bad', { ...scenario700, puzzleParams: { aDir: 9 } }), RangeError);
  assert.deepEqual(session.snapshot(), before);
});

test('raw input is checked only on explicit submit; 7, 70, 700 typing never unlocks', () => {
  const { session } = fixture();
  for (const input of ['7', '70', '700']) {
    session.setNote(input);
    assert.equal(session.state.door, 'locked');
    assert.equal(session.state.note, input);
    assert.equal(session.log.filter(e => e.type === 'password_submit').length, 0);
  }
  assert.equal(session.requestUnlock('password').code, 'not_authorized');
  const result = session.submitPassword();
  assert.equal(result.ok, true);
  assert.equal(session.state.door, 'opening');
  assert.equal(session.state.unlock.token, result.token);
  assert.equal(session.state.mechanics.releaseAuthorized, true);
  assert.equal(session.state.mechanics.smallBoltRetracted, false);
  assert.equal(session.state.mechanics.fenceDropped, false);
  session.finishUnlock(result.token);
  assert.equal(session.state.mechanics.smallBoltRetracted, true);
  assert.equal(session.state.mechanics.fenceDropped, true);
});

test('format errors preserve exact text: zero, whitespace, newline, decimals, exponent and Unicode', () => {
  const { session } = fixture();
  const inputs = ['', '7', '70', '007', '070', '000', '099', '1000', '700 ', ' 700', '700\n', '700\r\n', '+700', '-700', '7e2', '７００', '700.0', '7\u000000'];
  for (const input of inputs) {
    session.setNote(input);
    const result = session.submitPassword();
    assert.equal(result.code, 'format', JSON.stringify(input));
    assert.equal(session.state.note, input);
    assert.equal(session.state.validation.kind, 'format');
    assert.equal(session.state.door, 'locked');
  }
  session.setNote('701');
  assert.equal(session.submitPassword().code, 'password');
  assert.equal(session.state.validation.kind, 'password');
  assert.equal(session.state.note, '701');
});

test('all 899 other legal inputs fail as whole answers without digit-match feedback', () => {
  const { session } = fixture();
  for (let candidate = 100; candidate <= 999; candidate++) {
    if (candidate === 700) continue;
    session.setNote(String(candidate));
    const result = session.submitPassword();
    assert.deepEqual(Object.keys(result).sort(), ['code', 'message', 'ok']);
    assert.equal(result.code, 'password');
    assert.equal(session.state.door, 'locked');
  }
  assert.equal(session.log.some(e => e.type === 'unlock_request'), false);
});

test('skill recognition fills the same input immediately, then requires the same explicit submit', () => {
  const { session } = fixture();
  assert.equal(session.identifyPassword().code, 'skill');
  session.setSkill(true);
  assert.equal(session.identifyPassword().ok, true);
  assert.equal(session.state.note, '700');
  assert.equal(session.state.door, 'locked');
  assert.equal(session.log.some(e => e.type === 'note_first_input'), false);
  assert.equal(session.submitPassword().ok, true);
  assert.equal(session.log.filter(e => e.type === 'unlock_request').length, 1);
});

for (let a = 0; a < 3; a++) for (let b = 0; b < 3; b++) for (const aDir of [1, -1]) for (const bDir of [1, -1]) {
  test(`36-polarity combination A${a}(${aDir > 0 ? '+' : '-'}) + B${b}(${bDir > 0 ? '+' : '-'}): wrong input recovery, partial release, shared final bolt`, () => {
    const { session } = fixture({ a, b, aDir, bDir });
    session.selectTool('hook');
    assert.equal(session.operate('b', { direction: direction(session, 'b') }).code, 'prerequisite');
    assert.equal(session.operate('a', { direction: direction(session, 'a') }).code, 'tool');
    session.selectTool('wedge');
    const oppositeA = resolveStructureSpec('a', a, -aDir).direction;
    assert.equal(session.operate('a', { direction: oppositeA }).code, 'direction');
    assert.equal(session.operate('a', { direction: direction(session, 'a'), progress: NaN }).code, 'progress');
    assert.equal(session.state.mechanics.a.progress, 0);
    session.operate('a', { direction: direction(session, 'a'), progress: 0.65, commit: false });
    assert.equal(session.state.mechanics.a.progress, 0.65);
    session.setHelp(true, a);
    assert.equal(session.state.mechanics.a.progress, 0.65);
    assert.equal(session.operate('a', { direction: direction(session, 'a'), progress: 0.65 }).code, 'incomplete');
    assert.equal(session.state.mechanics.a.progress, 0);
    assert.equal(completeStage(session, 'a').ok, true);
    session.setRoute('password');
    session.setNote('70');
    session.setHelp(true, 8);
    session.setRoute('tools');
    assert.equal(session.state.note, '70');
    assert.equal(session.state.mechanics.a.complete, true);
    session.selectTool('hook');
    const oppositeB = resolveStructureSpec('b', b, -bDir).direction;
    assert.equal(session.operate('b', { direction: oppositeB }).code, 'direction');
    session.operate('b', { direction: direction(session, 'b'), progress: 0.8, commit: false });
    session.close();
    assert.equal(session.state.mechanics.a.progress, 1);
    assert.equal(session.state.mechanics.b.progress, 0);
    session.reopen();
    assert.equal(session.state.help.page, 8);
    assert.equal(session.state.selectedTool, 'hook');
    const opening = completeStage(session, 'b');
    assert.equal(opening.code, 'opening');
    assert.deepEqual(session.state.mechanics, {
      a: { progress: 1, complete: true }, b: { progress: 1, complete: true },
      smallBoltRetracted: false, fenceDropped: false, releaseMode: 'tools', releaseAuthorized: true,
    });
    assert.equal(session.requestUnlock('tools').ok, false);
    assert.equal(session.finishUnlock('stale').code, 'stale_token');
    assert.equal(session.finishUnlock(opening.token).ok, true);
    assert.equal(session.state.door, 'open');
    assert.equal(session.state.mechanics.smallBoltRetracted, true);
    assert.equal(session.finishUnlock(opening.token).ok, false);
    assert.equal(session.log.filter(e => e.type === 'unlock_request').length, 1);
    assert.equal(session.log.filter(e => e.type === 'unlock_complete').length, 1);
  });
}

test('threshold is displacement-based; holding a preview forever cannot unlock', () => {
  const { session, advance } = fixture();
  session.selectTool('wedge');
  session.operate('a', { direction: 'right', progress: 1, commit: false });
  advance(600000);
  assert.equal(session.state.mechanics.a.complete, false);
  assert.equal(session.state.door, 'locked');
  session.cancelAction();
  assert.equal(session.state.mechanics.a.progress, 0);
  assert.equal(session.operate('a', { direction: 'right', progress: 0.939 }).code, 'incomplete');
  assert.equal(session.operate('a', { direction: 'right', progress: CONFIG.interaction.completionThreshold }).code, 'complete');
  assert.equal(session.state.mechanics.a.progress, 1);
});

test('V2 ordinary generation covers all three visual puzzle types, nine base combinations, and 36 directional polarities', t => {
  const types = new Set(), combinations = new Set(), polarities = new Set(), joint = new Map();
  const session = new SafeSession({ seed: 'V2-normal-entry-coverage', clock: () => 0 });
  for (let index = 0; index < 512; index++) {
    const { puzzle, variants: { a, b, aDir, bDir } } = session.state;
    assert.ok(TYPES.includes(puzzle.type));
    assert.equal(isLegalParams(puzzle.type, puzzle.params), true);
    assert.equal(independentSolutions(puzzle)[0], puzzle.answer);
    assert.ok(Number.isInteger(a) && a >= 0 && a < 3);
    assert.ok(Number.isInteger(b) && b >= 0 && b < 3);
    assert.ok(aDir === 1 || aDir === -1);
    assert.ok(bDir === 1 || bDir === -1);
    types.add(puzzle.type);
    combinations.add(`${a}:${b}`);
    polarities.add(`${a}(${aDir}):${b}(${bDir})`);
    const key = `${puzzle.type}/${a}:${b}`;
    joint.set(key, (joint.get(key) ?? 0) + 1);
    session.nextSafe();
  }
  assert.equal(types.size, 3);
  assert.equal(combinations.size, 9);
  assert.equal(polarities.size, 36);
  assert.equal(joint.size, 27);
  t.diagnostic(JSON.stringify({ seriesBoxes: 512, puzzleTypes: types.size, combinations: combinations.size, polarities36: polarities.size, jointPairs: joint.size }));
});

test('V2 public snapshots and ordinary logs redact prepared answers and solvedSvg without losing user input', () => {
  const { session } = fixture();
  let ordinary = session.exportLog();
  assert.equal(ordinary.answersIncluded, false);
  assert.equal(Object.hasOwn(ordinary.state.puzzle, 'answer'), false);
  assert.equal(Object.hasOwn(ordinary.state.puzzle, 'solvedSvg'), false);
  assert.ok(ordinary.state.puzzle.svg.startsWith('<svg'));
  assert.equal(ordinary.state.note, '');
  assert.ok(ordinary.events.every(e => !Object.hasOwn(e, 'answer')));
  assert.equal(session.snapshot().puzzle.answer, '700');
  session.setSkill(true);
  session.identifyPassword();
  session.submitPassword();
  ordinary = session.exportLog();
  assert.equal(Object.hasOwn(ordinary.state, 'note'), false);
  assert.equal(ordinary.state.noteRedacted, true);
  const development = session.exportLog({ includeAnswers: true });
  assert.equal(development.answersIncluded, true);
  assert.equal(development.state.note, '700');
  assert.equal(development.state.puzzle.answer, '700');
});

test('3D procedural safe model audits cleanly across all 36 polarities, jammed B micro-travel, and full unlock', () => {
  const model = createSafeModel();
  try {
    for (let a = 0; a < 3; a++) for (let b = 0; b < 3; b++) for (const aDir of [1, -1]) for (const bDir of [1, -1]) {
      model.setVariants(a, b, aDir, bDir);
      const restPose = { a: 0, b: 0, latch: 0, bolts: 0, handle: 0, door: 0, jamA: 0, jamB: 0, jamShudder: 0, bTwitch: 0, toolInserted: 0, activeStage: null };
      model.apply(restPose);
      const restAudit = model.getAuditState();
      assert.equal(restAudit.ok, true, `rest audit failed for A${a}(${aDir})+B${b}(${bDir}): ${JSON.stringify(restAudit)}`);
      const restShoulderX = model.parts['B横向输出滑架'].position.x;

      // T1 jammed micro-travel on B before A is released: B moves ~12% toward A's interlock tongue while authoritative b stays 0
      model.apply({ ...restPose, jamB: 0.12, jamShudder: 0.004, activeStage: 'b', toolInserted: 1 });
      const jamBAudit = model.getAuditState();
      assert.equal(jamBAudit.ok, true, `jamB audit failed for A${a}(${aDir})+B${b}(${bDir}): ${JSON.stringify(jamBAudit)}`);
      assert.ok(model.parts['B横向输出滑架'].position.x < restShoulderX - 0.015, 'B output carriage should move across the backlash gap toward A interlock tongue during jamB');

      // Wrong-direction stopper collision on A
      model.apply({ ...restPose, jamA: -0.045, jamShudder: -0.004, activeStage: 'a', toolInserted: 1 });
      assert.equal(model.getAuditState().ok, true);

      // A released + B twitch cue
      model.apply({ ...restPose, a: 1, bTwitch: 0.015 });
      assert.equal(model.getAuditState().ok, true);

      // Service gesture direction matches polarity
      const gA = model.getServiceGesture('a');
      const gB = model.getServiceGesture('b');
      assert.equal(gA.direction, resolveStructureSpec('a', a, aDir).direction);
      assert.equal(gB.direction, resolveStructureSpec('b', b, bDir).direction);

      // Full mechanical unlock pose
      model.apply({ ...restPose, a: 1, b: 1, latch: 1, bolts: 1, handle: 1, door: 0.72 });
      const openAudit = model.getAuditState();
      assert.equal(openAudit.ok, true, `open audit failed for A${a}(${aDir})+B${b}(${bDir}): ${JSON.stringify(openAudit)}`);
    }
  } finally {
    model.dispose();
  }
});

test('arc gesture projection tolerates human mouse sweep on B2 rotary wheel and over-pull past the stop without false direction error', () => {
  // Simulate a 48px screen-space counterclockwise arc for B2
  const r = 45;
  const cx = 300, cy = 300;
  const path = Array.from({ length: 17 }, (_, i) => {
    const p = i / 16;
    const angle = -Math.PI / 2 - p * 1.08;
    return { p, x: cx + r * Math.cos(angle), y: cy + r * Math.sin(angle) };
  });
  const gesture = captureGesture({ kind: 'arc', direction: 'counterclockwise', path, x: path[0].x, y: path[0].y, tolerance: 28 });
  assert.ok(gesture.tolerance >= 28, 'arc tolerance should not shrink below 28px on a 48px rotary wheel');

  // Dragging to the end of the arc with 20px human lateral offset stays valid
  const endPt = path.at(-1);
  const nearEnd = projectGesture(gesture, endPt.x - 18, endPt.y + 8);
  assert.equal(nearEnd.valid, true);
  assert.ok(nearEnd.progress >= 0.94);

  // Over-pulling 45px past the end of the arc in the pull direction stays valid at progress 1.0
  const overPull = projectGesture(gesture, endPt.x - 35, endPt.y + 30);
  assert.equal(overPull.valid, true);
  assert.equal(overPull.progress, 1);

  // Dragging backwards against the stopper pin returns reason === 'direction'
  const backward = projectGesture(gesture, path[0].x + 28, path[0].y);
  assert.equal(backward.valid, false);
  assert.equal(backward.reason, 'direction');
});
