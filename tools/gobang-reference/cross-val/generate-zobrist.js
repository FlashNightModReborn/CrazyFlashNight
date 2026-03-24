/**
 * 生成 Zobrist 交叉验证数据
 * 使用与 AS2 完全一致的 LCG 参数和种子
 */
const { createLCG } = require('./lcg');
const fs = require('fs');
const path = require('path');

const SIZE = 15;
const SEED = 42;

// 初始化 Zobrist 表（与 AS2 GobangZobrist._initTable 完全一致）
const rng = createLCG(SEED);
const table = [];
for (let i = 0; i < SIZE; i++) {
    table[i] = [];
    for (let j = 0; j < SIZE; j++) {
        table[i][j] = [
            { hi: rng.next(), lo: rng.next() },  // roleIndex 0 = black
            { hi: rng.next(), lo: rng.next() }   // roleIndex 1 = white
        ];
    }
}

function roleIndex(role) {
    return role === 1 ? 0 : 1;
}

// 模拟 XOR hash（有符号 32 位）
function togglePiece(hashHi, hashLo, x, y, role) {
    const ri = roleIndex(role);
    const entry = table[x][y][ri];
    // JS 的 ^ 运算符产生有符号 32 位整数
    return {
        hi: (hashHi ^ entry.hi) | 0,
        lo: (hashLo ^ entry.lo) | 0
    };
}

// 测试序列：5 组固定落子
const testSequences = [
    // 序列 1：中心十字
    [
        {x: 7, y: 7, role: 1},
        {x: 7, y: 8, role: -1},
        {x: 8, y: 7, role: 1},
        {x: 6, y: 7, role: -1},
        {x: 7, y: 6, role: 1}
    ],
    // 序列 2：对角线
    [
        {x: 0, y: 0, role: 1},
        {x: 14, y: 14, role: -1},
        {x: 1, y: 1, role: 1},
        {x: 13, y: 13, role: -1}
    ],
    // 序列 3：边角
    [
        {x: 0, y: 14, role: 1},
        {x: 14, y: 0, role: -1},
        {x: 0, y: 0, role: 1}
    ],
    // 序列 4：put + undo 可逆性测试
    [
        {x: 5, y: 5, role: 1},
        {x: 6, y: 6, role: -1},
        {x: 5, y: 5, role: 1},  // undo 时 togglePiece 同一位置 = XOR 回来
        {x: 6, y: 6, role: -1}  // undo 白方
    ],
    // 序列 5：同一位置反复
    [
        {x: 3, y: 3, role: 1},
        {x: 3, y: 3, role: 1}  // toggle again = back to 0
    ]
];

const results = [];
for (let s = 0; s < testSequences.length; s++) {
    const seq = testSequences[s];
    let hi = 0, lo = 0;
    const steps = [];
    for (let m = 0; m < seq.length; m++) {
        const move = seq[m];
        const hash = togglePiece(hi, lo, move.x, move.y, move.role);
        hi = hash.hi;
        lo = hash.lo;
        steps.push({
            x: move.x, y: move.y, role: move.role,
            hashHi: hi, hashLo: lo,
            key: String(hi) + "_" + String(lo)
        });
    }
    results.push({
        description: 'Sequence ' + (s + 1),
        steps: steps
    });
}

// 写入 fixture
const fixturesDir = path.join(__dirname, 'fixtures');
fs.writeFileSync(
    path.join(fixturesDir, 'zobrist-sequences.json'),
    JSON.stringify(results, null, 2)
);

// 生成 AS2 代码片段
let as2 = '// Auto-generated Zobrist test sequences\n';
as2 += '// Format: [seqIdx][stepIdx] = {x, y, role, hashHi, hashLo}\n';
for (let s = 0; s < results.length; s++) {
    const seq = results[s];
    as2 += '// ' + seq.description + '\n';
    for (let m = 0; m < seq.steps.length; m++) {
        const step = seq.steps[m];
        as2 += `// step ${m}: put(${step.x},${step.y},${step.role}) -> hi=${step.hashHi}, lo=${step.hashLo}\n`;
    }
}

fs.writeFileSync(
    path.join(fixturesDir, 'as2-zobrist-snippet.txt'),
    as2
);

console.log('Generated zobrist-sequences.json');
console.log('\nSummary:');
for (const r of results) {
    const last = r.steps[r.steps.length - 1];
    console.log(`  ${r.description}: final hash = ${last.key}`);
}
