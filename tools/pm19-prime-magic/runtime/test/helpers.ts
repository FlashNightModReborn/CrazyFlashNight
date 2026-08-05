import assert from "node:assert/strict";
import type { PrimeMagicSeed } from "../src/types.js";

export function assertCompleteMagic(values: Uint32Array, seed: PrimeMagicSeed): void {
  const size = seed.size;
  assert.equal(values.length, size * size);
  let mainDiagonal = 0;
  let secondaryDiagonal = 0;
  const seen = new Set<number>();

  for (let row = 0; row < size; row += 1) {
    let rowSum = 0;
    let columnSum = 0;
    for (let column = 0; column < size; column += 1) {
      const rowValue = values[row * size + column]!;
      const columnValue = values[column * size + row]!;
      rowSum += rowValue;
      columnSum += columnValue;
      seen.add(rowValue);
    }
    assert.equal(rowSum, seed.magicSum, `row ${row}`);
    assert.equal(columnSum, seed.magicSum, `column ${row}`);
    mainDiagonal += values[row * size + row]!;
    secondaryDiagonal += values[row * size + size - 1 - row]!;
  }

  assert.equal(mainDiagonal, seed.magicSum, "main diagonal");
  assert.equal(secondaryDiagonal, seed.magicSum, "secondary diagonal");
  assert.equal(seen.size, size * size, "global uniqueness");
}

export function makeTransform(size: number): {
  rowPermutation: Uint8Array | Uint16Array;
  columnPermutation: Uint8Array | Uint16Array;
  transpose: boolean;
} {
  const ArrayType = size <= 256 ? Uint8Array : Uint16Array;
  return {
    rowPermutation: new ArrayType(size),
    columnPermutation: new ArrayType(size),
    transpose: false,
  };
}
