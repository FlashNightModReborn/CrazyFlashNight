import test from "node:test";
import { loadLocalPrimeMagicSeed } from "../examples/load-node-seeds.js";
import { PrimeMagicOrbitEngine } from "../src/engine.js";
import { assertCompleteMagic, makeTransform } from "./helpers.js";

const requestedIterations = Number.parseInt(process.env.MILLION_TRANSFORMS ?? "1000000", 10);
if (!Number.isInteger(requestedIterations) || requestedIterations < 1) {
  throw new Error("MILLION_TRANSFORMS must be a positive integer");
}

test(`stress: ${requestedIterations.toLocaleString()} independently sampled legal transforms`, {
  timeout: 180_000,
}, () => {
  const seed = loadLocalPrimeMagicSeed(0);
  const engine = new PrimeMagicOrbitEngine(seed, 0x0123_4567_89ab_cdefn);
  const transform = makeTransform(seed.size);
  const size = seed.size;
  const target = seed.magicSum;

  for (let iteration = 0; iteration < requestedIterations; iteration += 1) {
    const board = engine.nextView();
    transform.transpose = engine.copyLastTransformInto(
      transform.rowPermutation,
      transform.columnPermutation,
    );
    if (!engine.validateTransform(transform)) {
      throw new Error(`illegal sampled transform at iteration ${iteration}`);
    }

    // Every board checks both diagonals and one rotating row/column. Together
    // all lines are sampled uniformly; a full invariant check follows every
    // 4096 boards.
    const sampledRow = iteration % size;
    const sampledColumn = (iteration * 7) % size;
    let rowSum = 0;
    let columnSum = 0;
    let mainDiagonal = 0;
    let secondaryDiagonal = 0;
    for (let index = 0; index < size; index += 1) {
      rowSum += board[sampledRow * size + index]!;
      columnSum += board[index * size + sampledColumn]!;
      mainDiagonal += board[index * size + index]!;
      secondaryDiagonal += board[index * size + size - 1 - index]!;
    }
    if (
      rowSum !== target ||
      columnSum !== target ||
      mainDiagonal !== target ||
      secondaryDiagonal !== target
    ) {
      throw new Error(`magic invariant failed at iteration ${iteration}`);
    }
    if ((iteration & 4095) === 0) {
      assertCompleteMagic(board, seed);
    }
  }
});
