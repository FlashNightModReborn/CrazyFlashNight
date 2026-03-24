/**
 * PRNG 对拍验证脚本
 * 生成前 1000 个 LCG 输出 + 前 100 个 Zobrist 槽位
 * 输出到 fixtures/ 供 AS2 侧比对
 */
const { createLCG } = require('./lcg');
const fs = require('fs');
const path = require('path');

const SEED = 42;
const LCG_COUNT = 1000;
const ZOBRIST_SLOTS = 100; // 前 100 个槽位 (15*15*2 = 450 total, 取前 100)

// === 生成 LCG 序列 ===
const lcg = createLCG(SEED);
const lcgOutputs = [];
for (let i = 0; i < LCG_COUNT; i++) {
    lcgOutputs.push(lcg.next());
}

// === 生成 Zobrist 槽位 ===
// 重新初始化 LCG，用同一种子
const lcg2 = createLCG(SEED);
const zobristSlots = [];
for (let i = 0; i < ZOBRIST_SLOTS; i++) {
    const hi = lcg2.next();
    const lo = lcg2.next();
    zobristSlots.push({ hi, lo });
}

// === 写入 fixtures ===
const fixturesDir = path.join(__dirname, 'fixtures');
fs.mkdirSync(fixturesDir, { recursive: true });

fs.writeFileSync(
    path.join(fixturesDir, 'lcg-1000.json'),
    JSON.stringify(lcgOutputs, null, 2)
);

fs.writeFileSync(
    path.join(fixturesDir, 'zobrist-100.json'),
    JSON.stringify(zobristSlots, null, 2)
);

// === 同时生成 AS2 常量代码片段 ===
// 只取前 20 个 LCG 值用于 quick test
let as2Snippet = '// Auto-generated from verify-lcg.js — seed=42\n';
as2Snippet += '// 前 20 个 LCG 输出（quick test 用）\n';
as2Snippet += 'private static var LCG_EXPECTED:Array = [\n';
for (let i = 0; i < 20; i++) {
    as2Snippet += '    ' + lcgOutputs[i] + (i < 19 ? ',' : '') + '\n';
}
as2Snippet += '];\n\n';

as2Snippet += '// 前 10 个 Zobrist 槽位\n';
as2Snippet += 'private static var ZOBRIST_EXPECTED_HI:Array = [\n';
for (let i = 0; i < 10; i++) {
    as2Snippet += '    ' + zobristSlots[i].hi + (i < 9 ? ',' : '') + '\n';
}
as2Snippet += '];\n';
as2Snippet += 'private static var ZOBRIST_EXPECTED_LO:Array = [\n';
for (let i = 0; i < 10; i++) {
    as2Snippet += '    ' + zobristSlots[i].lo + (i < 9 ? ',' : '') + '\n';
}
as2Snippet += '];\n';

fs.writeFileSync(
    path.join(fixturesDir, 'as2-lcg-snippet.txt'),
    as2Snippet
);

console.log('Generated:');
console.log('  fixtures/lcg-1000.json (' + lcgOutputs.length + ' values)');
console.log('  fixtures/zobrist-100.json (' + zobristSlots.length + ' slots)');
console.log('  fixtures/as2-lcg-snippet.txt');
console.log('\nFirst 5 LCG values:', lcgOutputs.slice(0, 5));
console.log('First 3 Zobrist slots:', zobristSlots.slice(0, 3));
