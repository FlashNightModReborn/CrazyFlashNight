/**
 * Eval 交叉验证
 * 构造棋面 → 调用 evaluate → 输出分数
 * 使用内联的上游逻辑（避免 ES module 问题）
 */
const fs = require('fs');
const path = require('path');

const SIZE = 15;

// ===== 内联 shapes + scores =====
const shapes = {
    FIVE: 5, BLOCK_FIVE: 50, FOUR: 4, FOUR_FOUR: 44, FOUR_THREE: 43,
    THREE_THREE: 33, BLOCK_FOUR: 40, THREE: 3, BLOCK_THREE: 30,
    TWO_TWO: 22, TWO: 2, NONE: 0
};
const FIVE = 10000000, BLOCK_FIVE_S = FIVE, FOUR_S = 100000, FOUR_FOUR_S = FOUR_S;
const FOUR_THREE_S = FOUR_S, THREE_THREE_S = FOUR_S / 2;
const BLOCK_FOUR_S = 1500, THREE_S = 1000, BLOCK_THREE_S = 150;
const TWO_TWO_S = 200, TWO_S = 100, BLOCK_TWO_S = 15, ONE_S = 10, BLOCK_ONE_S = 1;

function getRealShapeScore(shape) {
    if (shape === shapes.FIVE) return FOUR_S;
    if (shape === shapes.BLOCK_FIVE) return BLOCK_FOUR_S;
    if (shape === shapes.FOUR) return THREE_S;
    if (shape === shapes.FOUR_FOUR) return THREE_S;
    if (shape === shapes.FOUR_THREE) return THREE_S;
    if (shape === shapes.BLOCK_FOUR) return BLOCK_THREE_S;
    if (shape === shapes.THREE) return TWO_S;
    if (shape === shapes.THREE_THREE) return THREE_THREE_S / 10;
    if (shape === shapes.BLOCK_THREE) return BLOCK_TWO_S;
    if (shape === shapes.TWO) return ONE_S;
    if (shape === shapes.TWO_TWO) return TWO_TWO_S / 10;
    return 0;
}

function direction2index(ox, oy) {
    if (ox === 0) return 0;
    if (oy === 0) return 1;
    if (ox === oy) return 2;
    return 3;
}

const allDirs = [[0,1],[1,0],[1,1],[1,-1]];

// ===== 内联 countShape + getShapeFast =====
const countShape = (board, x, y, offsetX, offsetY, role) => {
    const opponent = -role;
    let innerEmptyCount = 0, tempEmptyCount = 0, selfCount = 0;
    let totalLength = 0, sideEmptyCount = 0;
    let noEmptySelfCount = 0, OneEmptySelfCount = 0;
    for (let i = 1; i <= 5; i++) {
        const nx = x + i * offsetX + 1, ny = y + i * offsetY + 1;
        const cur = board[nx][ny];
        if (cur === 2 || cur === opponent) break;
        if (cur === role) {
            selfCount++; sideEmptyCount = 0;
            if (tempEmptyCount) { innerEmptyCount += tempEmptyCount; tempEmptyCount = 0; }
            if (innerEmptyCount === 0) { noEmptySelfCount++; OneEmptySelfCount++; }
            else if (innerEmptyCount === 1) OneEmptySelfCount++;
        }
        totalLength++;
        if (cur === 0) { tempEmptyCount++; sideEmptyCount++; }
        if (sideEmptyCount >= 2) break;
    }
    if (!innerEmptyCount) OneEmptySelfCount = 0;
    return { selfCount, totalLength, noEmptySelfCount, OneEmptySelfCount, innerEmptyCount, sideEmptyCount };
};

const getShapeFast = (board, x, y, offsetX, offsetY, role) => {
    if (board[x+offsetX+1][y+offsetY+1] === 0 && board[x-offsetX+1][y-offsetY+1] === 0
        && board[x+2*offsetX+1][y+2*offsetY+1] === 0 && board[x-2*offsetX+1][y-2*offsetY+1] === 0)
        return [shapes.NONE, 1];
    let selfCount=1, totalLength=1, shape=shapes.NONE;
    let leftEmpty=0, rightEmpty=0, noEmptySelfCount=1, OneEmptySelfCount=1;
    const left = countShape(board,x,y,-offsetX,-offsetY,role);
    const right = countShape(board,x,y,offsetX,offsetY,role);
    selfCount = left.selfCount + right.selfCount + 1;
    totalLength = left.totalLength + right.totalLength + 1;
    noEmptySelfCount = left.noEmptySelfCount + right.noEmptySelfCount + 1;
    OneEmptySelfCount = Math.max(left.OneEmptySelfCount+right.noEmptySelfCount, left.noEmptySelfCount+right.OneEmptySelfCount) + 1;
    rightEmpty = right.sideEmptyCount; leftEmpty = left.sideEmptyCount;
    if (totalLength < 5) return [shape, selfCount];
    if (noEmptySelfCount >= 5) return (rightEmpty>0 && leftEmpty>0) ? [shapes.FIVE,selfCount] : [shapes.BLOCK_FIVE,selfCount];
    if (noEmptySelfCount === 4) {
        if ((rightEmpty>=1||right.OneEmptySelfCount>right.noEmptySelfCount) && (leftEmpty>=1||left.OneEmptySelfCount>left.noEmptySelfCount)) return [shapes.FOUR,selfCount];
        if (!(rightEmpty===0 && leftEmpty===0)) return [shapes.BLOCK_FOUR,selfCount];
    }
    if (OneEmptySelfCount === 4) return [shapes.BLOCK_FOUR,selfCount];
    if (noEmptySelfCount === 3) return ((rightEmpty>=2&&leftEmpty>=1)||(rightEmpty>=1&&leftEmpty>=2)) ? [shapes.THREE,selfCount] : [shapes.BLOCK_THREE,selfCount];
    if (OneEmptySelfCount === 3) return (rightEmpty>=1&&leftEmpty>=1) ? [shapes.THREE,selfCount] : [shapes.BLOCK_THREE,selfCount];
    if ((noEmptySelfCount===2||OneEmptySelfCount===2) && totalLength>5) shape = shapes.TWO;
    return [shape, selfCount];
};

// ===== 简化版 Evaluate 类 =====
class Evaluate {
    constructor(size = 15) {
        this.size = size;
        this.board = Array.from({length:size+2}).map((_,i) => Array.from({length:size+2}).map((_,j) =>
            (i===0||j===0||i===size+1||j===size+1) ? 2 : 0));
        this.blackScores = Array.from({length:size}).map(() => Array(size).fill(0));
        this.whiteScores = Array.from({length:size}).map(() => Array(size).fill(0));
        this.shapeCache = {};
        for (const role of [1,-1]) {
            this.shapeCache[role] = {};
            for (const d of [0,1,2,3]) {
                this.shapeCache[role][d] = Array.from({length:size}).map(() => Array(size).fill(shapes.NONE));
            }
        }
        this.history = [];
    }
    move(x,y,role) {
        for (const d of [0,1,2,3]) { this.shapeCache[role][d][x][y]=0; this.shapeCache[-role][d][x][y]=0; }
        this.blackScores[x][y]=0; this.whiteScores[x][y]=0;
        this.board[x+1][y+1] = role;
        this.updatePoint(x,y);
        this.history.push([x*this.size+y, role]);
    }
    undo(x,y) {
        this.board[x+1][y+1] = 0;
        this.updatePoint(x,y);
        this.history.pop();
    }
    updatePoint(x,y) {
        this.updateSinglePoint(x,y,1);
        this.updateSinglePoint(x,y,-1);
        for (const [ox,oy] of allDirs) {
            for (const sign of [1,-1]) {
                let reachEdge = false;
                for (let step=1; step<=5; step++) {
                    for (const role of [1,-1]) {
                        const nx = x+sign*step*ox+1, ny = y+sign*step*oy+1;
                        if (this.board[nx][ny] === 2) { reachEdge=true; break; }
                        if (this.board[nx][ny] === -role) continue;
                        if (this.board[nx][ny] === 0) {
                            this.updateSinglePoint(nx-1, ny-1, role, [sign*ox, sign*oy]);
                        }
                    }
                    if (reachEdge) break;
                }
            }
        }
    }
    updateSinglePoint(x,y,role,direction=undefined) {
        if (this.board[x+1][y+1] !== 0) return;
        this.board[x+1][y+1] = role;
        const sc = this.shapeCache[role];
        const directions = direction ? [direction] : allDirs;
        for (const [ox,oy] of directions) { sc[direction2index(ox,oy)][x][y] = shapes.NONE; }
        let score=0, blockfourCount=0, threeCount=0, twoCount=0;
        for (let d=0; d<4; d++) {
            const s = sc[d][x][y];
            if (s > shapes.NONE) {
                score += getRealShapeScore(s);
                if (s===shapes.BLOCK_FOUR) blockfourCount++;
                if (s===shapes.THREE) threeCount++;
                if (s===shapes.TWO) twoCount++;
            }
        }
        for (const [ox,oy] of directions) {
            const intDir = direction2index(ox,oy);
            let [shape] = getShapeFast(this.board,x,y,ox,oy,role);
            if (!shape) continue;
            sc[intDir][x][y] = shape;
            if (shape===shapes.BLOCK_FOUR) blockfourCount++;
            if (shape===shapes.THREE) threeCount++;
            if (shape===shapes.TWO) twoCount++;
            if (blockfourCount>=2) shape=shapes.FOUR_FOUR;
            else if (blockfourCount&&threeCount) shape=shapes.FOUR_THREE;
            else if (threeCount>=2) shape=shapes.THREE_THREE;
            else if (twoCount>=2) shape=shapes.TWO_TWO;
            score += getRealShapeScore(shape);
        }
        this.board[x+1][y+1] = 0;
        if (role===1) this.blackScores[x][y]=score; else this.whiteScores[x][y]=score;
    }
    evaluate(role) {
        let b=0, w=0;
        for (let i=0;i<this.size;i++) for (let j=0;j<this.size;j++) { b+=this.blackScores[i][j]; w+=this.whiteScores[i][j]; }
        return role===1 ? b-w : w-b;
    }
}

// ===== 测试棋面 =====
const tests = [];

// Test 1: 单步 — 黑棋中心
{
    const e = new Evaluate(15);
    e.move(7, 7, 1);
    tests.push({ name: 'single_black_center', score: e.evaluate(1) });
}

// Test 2: 两步 — 黑白各一
{
    const e = new Evaluate(15);
    e.move(7, 7, 1);
    e.move(7, 8, -1);
    tests.push({ name: 'black_white_adjacent', scoreBlack: e.evaluate(1), scoreWhite: e.evaluate(-1) });
}

// Test 3: 黑棋活三
{
    const e = new Evaluate(15);
    e.move(7, 6, 1);
    e.move(0, 0, -1);
    e.move(7, 7, 1);
    e.move(0, 1, -1);
    e.move(7, 8, 1);
    tests.push({ name: 'black_three', score: e.evaluate(1) });
}

// Test 4: undo 可逆性
{
    const e = new Evaluate(15);
    e.move(7, 7, 1);
    const s1 = e.evaluate(1);
    e.move(6, 6, -1);
    e.undo(6, 6);
    const s2 = e.evaluate(1);
    tests.push({ name: 'undo_reversible', score1: s1, score2: s2, match: s1 === s2 });
}

// Test 5: 空棋盘 evaluate = 0
{
    const e = new Evaluate(15);
    tests.push({ name: 'empty_board', score: e.evaluate(1) });
}

fs.writeFileSync(path.join(__dirname, 'fixtures', 'eval-tests.json'), JSON.stringify(tests, null, 2));
console.log('Eval fixtures:');
for (const t of tests) console.log(' ', JSON.stringify(t));
