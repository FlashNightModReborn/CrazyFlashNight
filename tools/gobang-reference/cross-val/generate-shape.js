/**
 * Shape 交叉验证数据
 * 在 padded board 上构造典型棋型，调用 getShapeFast 验证
 */
const fs = require('fs');
const path = require('path');

// Inline shape constants (from upstream shape.js)
const shapes = {
    FIVE: 5, BLOCK_FIVE: 50, FOUR: 4, FOUR_FOUR: 44, FOUR_THREE: 43,
    THREE_THREE: 33, BLOCK_FOUR: 40, THREE: 3, BLOCK_THREE: 30,
    TWO_TWO: 22, TWO: 2, NONE: 0
};

// Inline countShape and getShapeFast from upstream
const countShape = (board, x, y, offsetX, offsetY, role) => {
    const opponent = -role;
    let innerEmptyCount = 0, tempEmptyCount = 0, selfCount = 0;
    let totalLength = 0, sideEmptyCount = 0;
    let noEmptySelfCount = 0, OneEmptySelfCount = 0;
    for (let i = 1; i <= 5; i++) {
        const [nx, ny] = [x + i * offsetX + 1, y + i * offsetY + 1];
        const cur = board[nx][ny];
        if (cur === 2 || cur === opponent) break;
        if (cur === role) {
            selfCount++; sideEmptyCount = 0;
            if (tempEmptyCount) { innerEmptyCount += tempEmptyCount; tempEmptyCount = 0; }
            if (innerEmptyCount === 0) { noEmptySelfCount++; OneEmptySelfCount++; }
            else if (innerEmptyCount === 1) { OneEmptySelfCount++; }
        }
        totalLength++;
        if (cur === 0) { tempEmptyCount++; sideEmptyCount++; }
        if (sideEmptyCount >= 2) break;
    }
    if (!innerEmptyCount) OneEmptySelfCount = 0;
    return { selfCount, totalLength, noEmptySelfCount, OneEmptySelfCount, innerEmptyCount, sideEmptyCount };
};

const getShapeFast = (board, x, y, offsetX, offsetY, role) => {
    if (board[x + offsetX + 1][y + offsetY + 1] === 0
        && board[x - offsetX + 1][y - offsetY + 1] === 0
        && board[x + 2 * offsetX + 1][y + 2 * offsetY + 1] === 0
        && board[x - 2 * offsetX + 1][y - 2 * offsetY + 1] === 0) {
        return [shapes.NONE, 1];
    }
    let selfCount = 1, totalLength = 1, shape = shapes.NONE;
    let leftEmpty = 0, rightEmpty = 0;
    let noEmptySelfCount = 1, OneEmptySelfCount = 1;
    const left = countShape(board, x, y, -offsetX, -offsetY, role);
    const right = countShape(board, x, y, offsetX, offsetY, role);
    selfCount = left.selfCount + right.selfCount + 1;
    totalLength = left.totalLength + right.totalLength + 1;
    noEmptySelfCount = left.noEmptySelfCount + right.noEmptySelfCount + 1;
    OneEmptySelfCount = Math.max(left.OneEmptySelfCount + right.noEmptySelfCount, left.noEmptySelfCount + right.OneEmptySelfCount) + 1;
    rightEmpty = right.sideEmptyCount;
    leftEmpty = left.sideEmptyCount;
    if (totalLength < 5) return [shape, selfCount];
    if (noEmptySelfCount >= 5) {
        return (rightEmpty > 0 && leftEmpty > 0) ? [shapes.FIVE, selfCount] : [shapes.BLOCK_FIVE, selfCount];
    }
    if (noEmptySelfCount === 4) {
        if ((rightEmpty >= 1 || right.OneEmptySelfCount > right.noEmptySelfCount)
            && (leftEmpty >= 1 || left.OneEmptySelfCount > left.noEmptySelfCount)) {
            return [shapes.FOUR, selfCount];
        } else if (!(rightEmpty === 0 && leftEmpty === 0)) {
            return [shapes.BLOCK_FOUR, selfCount];
        }
    }
    if (OneEmptySelfCount === 4) return [shapes.BLOCK_FOUR, selfCount];
    if (noEmptySelfCount === 3) {
        return ((rightEmpty >= 2 && leftEmpty >= 1) || (rightEmpty >= 1 && leftEmpty >= 2))
            ? [shapes.THREE, selfCount] : [shapes.BLOCK_THREE, selfCount];
    }
    if (OneEmptySelfCount === 3) {
        return (rightEmpty >= 1 && leftEmpty >= 1)
            ? [shapes.THREE, selfCount] : [shapes.BLOCK_THREE, selfCount];
    }
    if ((noEmptySelfCount === 2 || OneEmptySelfCount === 2) && totalLength > 5) shape = shapes.TWO;
    return [shape, selfCount];
};

const SIZE = 15;

// Create padded board (SIZE+2 x SIZE+2), border = 2
function createPaddedBoard() {
    const board = [];
    for (let i = 0; i < SIZE + 2; i++) {
        board[i] = [];
        for (let j = 0; j < SIZE + 2; j++) {
            board[i][j] = (i === 0 || j === 0 || i === SIZE + 1 || j === SIZE + 1) ? 2 : 0;
        }
    }
    return board;
}

// Helper: place pieces on padded board (coords are non-padded)
function place(board, pieces) {
    for (const [x, y, role] of pieces) {
        board[x + 1][y + 1] = role;
    }
}

const tests = [];

// Test 1: FIVE — five black in a row horizontally
{
    const board = createPaddedBoard();
    place(board, [[7,5,1],[7,6,1],[7,7,1],[7,8,1],[7,9,1]]);
    const [shape] = getShapeFast(board, 7, 7, 0, 1, 1); // horizontal
    tests.push({ name: 'FIVE horizontal', x: 7, y: 7, ox: 0, oy: 1, role: 1, shape, expected: shapes.FIVE });
}

// Test 2: BLOCK_FIVE — five at edge
{
    const board = createPaddedBoard();
    place(board, [[0,0,1],[0,1,1],[0,2,1],[0,3,1],[0,4,1]]);
    const [shape] = getShapeFast(board, 0, 2, 0, 1, 1);
    tests.push({ name: 'BLOCK_FIVE at edge', x: 0, y: 2, ox: 0, oy: 1, role: 1, shape, expected: shapes.BLOCK_FIVE });
}

// Test 3: FOUR — open four (both ends empty)
{
    const board = createPaddedBoard();
    // _XXXX_ at row 7, cols 5-8, col 4 and 9 are empty
    place(board, [[7,5,1],[7,6,1],[7,7,1],[7,8,1]]);
    const [shape] = getShapeFast(board, 7, 7, 0, 1, 1);
    tests.push({ name: 'FOUR open', x: 7, y: 7, ox: 0, oy: 1, role: 1, shape, expected: shapes.FOUR });
}

// Test 4: BLOCK_FOUR — four blocked on one side
{
    const board = createPaddedBoard();
    // WXXXX_ at row 7
    place(board, [[7,4,-1],[7,5,1],[7,6,1],[7,7,1],[7,8,1]]);
    const [shape] = getShapeFast(board, 7, 7, 0, 1, 1);
    tests.push({ name: 'BLOCK_FOUR one side blocked', x: 7, y: 7, ox: 0, oy: 1, role: 1, shape, expected: shapes.BLOCK_FOUR });
}

// Test 5: THREE — open three
{
    const board = createPaddedBoard();
    // __XXX__ at row 7
    place(board, [[7,6,1],[7,7,1],[7,8,1]]);
    const [shape] = getShapeFast(board, 7, 7, 0, 1, 1);
    tests.push({ name: 'THREE open', x: 7, y: 7, ox: 0, oy: 1, role: 1, shape, expected: shapes.THREE });
}

// Test 6: BLOCK_THREE — three blocked
{
    const board = createPaddedBoard();
    // WXXX_ at row 7
    place(board, [[7,4,-1],[7,5,1],[7,6,1],[7,7,1]]);
    const [shape] = getShapeFast(board, 7, 6, 0, 1, 1);
    tests.push({ name: 'BLOCK_THREE', x: 7, y: 6, ox: 0, oy: 1, role: 1, shape, expected: shapes.BLOCK_THREE });
}

// Test 7: TWO — open two
{
    const board = createPaddedBoard();
    // ___XX___ at row 7
    place(board, [[7,7,1],[7,8,1]]);
    const [shape] = getShapeFast(board, 7, 7, 0, 1, 1);
    tests.push({ name: 'TWO open', x: 7, y: 7, ox: 0, oy: 1, role: 1, shape, expected: shapes.TWO });
}

// Test 8: NONE — isolated piece
{
    const board = createPaddedBoard();
    place(board, [[7,7,1]]);
    const [shape] = getShapeFast(board, 7, 7, 0, 1, 1);
    tests.push({ name: 'NONE isolated', x: 7, y: 7, ox: 0, oy: 1, role: 1, shape, expected: shapes.NONE });
}

// Test 9: Vertical THREE
{
    const board = createPaddedBoard();
    place(board, [[5,7,1],[6,7,1],[7,7,1]]);
    const [shape] = getShapeFast(board, 6, 7, 1, 0, 1);
    tests.push({ name: 'THREE vertical', x: 6, y: 7, ox: 1, oy: 0, role: 1, shape, expected: shapes.THREE });
}

// Test 10: Diagonal FOUR
{
    const board = createPaddedBoard();
    place(board, [[4,4,1],[5,5,1],[6,6,1],[7,7,1]]);
    const [shape] = getShapeFast(board, 5, 5, 1, 1, 1);
    tests.push({ name: 'FOUR diagonal', x: 5, y: 5, ox: 1, oy: 1, role: 1, shape, expected: shapes.FOUR });
}

// Test 11: White pieces — BLOCK_FOUR
{
    const board = createPaddedBoard();
    place(board, [[7,5,-1],[7,6,-1],[7,7,-1],[7,8,-1],[7,4,1]]);
    const [shape] = getShapeFast(board, 7, 7, 0, 1, -1);
    tests.push({ name: 'BLOCK_FOUR white', x: 7, y: 7, ox: 0, oy: 1, role: -1, shape, expected: shapes.BLOCK_FOUR });
}

// Test 12: Anti-diagonal THREE
{
    const board = createPaddedBoard();
    place(board, [[5,9,1],[6,8,1],[7,7,1]]);
    const [shape] = getShapeFast(board, 6, 8, 1, -1, 1);
    tests.push({ name: 'THREE anti-diagonal', x: 6, y: 8, ox: 1, oy: -1, role: 1, shape, expected: shapes.THREE });
}

// Write results
const results = tests.map(t => ({
    name: t.name,
    x: t.x, y: t.y, ox: t.ox, oy: t.oy, role: t.role,
    shape: t.shape,
    expected: t.expected,
    pass: t.shape === t.expected
}));

fs.writeFileSync(
    path.join(__dirname, 'fixtures', 'shape-tests.json'),
    JSON.stringify(results, null, 2)
);

console.log('Shape test results:');
let pass = 0, fail = 0;
for (const r of results) {
    const status = r.pass ? 'PASS' : 'FAIL';
    console.log(`  [${status}] ${r.name}: shape=${r.shape}, expected=${r.expected}`);
    if (r.pass) pass++; else fail++;
}
console.log(`\n${pass} passed, ${fail} failed`);
