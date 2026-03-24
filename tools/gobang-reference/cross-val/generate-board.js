/**
 * Board 交叉验证数据
 * 生成固定 10 步落子后的 isWin 状态
 */
const { createLCG } = require('./lcg');
const fs = require('fs');
const path = require('path');

const SIZE = 15;

// Simple board simulation matching AS2 GobangBoard
function createBoard() {
    const board = [];
    for (let i = 0; i < SIZE; i++) {
        board[i] = [];
        for (let j = 0; j < SIZE; j++) board[i][j] = 0;
    }
    return board;
}

function isWin(board, x, y, role) {
    const dirs = [[1,0],[0,1],[1,1],[1,-1]];
    for (const [dx,dy] of dirs) {
        let count = 1;
        for (let k = 1; k < 5; k++) {
            const nx = x + dx*k, ny = y + dy*k;
            if (nx < 0 || nx >= SIZE || ny < 0 || ny >= SIZE || board[nx][ny] !== role) break;
            count++;
        }
        for (let k = 1; k < 5; k++) {
            const nx = x - dx*k, ny = y - dy*k;
            if (nx < 0 || nx >= SIZE || ny < 0 || ny >= SIZE || board[nx][ny] !== role) break;
            count++;
        }
        if (count >= 5) return true;
    }
    return false;
}

// Test sequence: 10 moves leading to a win for black at move 9
const moves = [
    {i:7, j:7, role:1},   // 1: black center
    {i:6, j:6, role:-1},  // 2: white
    {i:7, j:8, role:1},   // 3: black
    {i:6, j:7, role:-1},  // 4: white
    {i:7, j:9, role:1},   // 5: black
    {i:6, j:8, role:-1},  // 6: white
    {i:7, j:10, role:1},  // 7: black
    {i:6, j:9, role:-1},  // 8: white
    {i:7, j:11, role:1},  // 9: black — five in a row! (7,7)-(7,11)
    {i:6, j:10, role:-1}  // 10: white (after win)
];

const board = createBoard();

// Also compute Zobrist hashes
const rng = createLCG(42);
const zobTable = [];
for (let i = 0; i < SIZE; i++) {
    zobTable[i] = [];
    for (let j = 0; j < SIZE; j++) {
        zobTable[i][j] = [
            { hi: rng.next(), lo: rng.next() },
            { hi: rng.next(), lo: rng.next() }
        ];
    }
}

function roleIndex(role) { return role === 1 ? 0 : 1; }

let hashHi = 0, hashLo = 0;
const results = [];
for (let m = 0; m < moves.length; m++) {
    const mv = moves[m];
    board[mv.i][mv.j] = mv.role;
    const ri = roleIndex(mv.role);
    hashHi = (hashHi ^ zobTable[mv.i][mv.j][ri].hi) | 0;
    hashLo = (hashLo ^ zobTable[mv.i][mv.j][ri].lo) | 0;
    const win = isWin(board, mv.i, mv.j, mv.role);
    results.push({
        step: m,
        i: mv.i, j: mv.j, role: mv.role,
        isWin: win,
        hashHi: hashHi,
        hashLo: hashLo
    });
}

fs.writeFileSync(
    path.join(__dirname, 'fixtures', 'board-10steps.json'),
    JSON.stringify(results, null, 2)
);

console.log('Generated board-10steps.json');
for (const r of results) {
    console.log(`  step ${r.step}: put(${r.i},${r.j},${r.role}) isWin=${r.isWin} hash=${r.hashHi}_${r.hashLo}`);
}
