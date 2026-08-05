import type { PrimeMagicSeed } from "../src/types.js";

/**
 * Odd-order Siamese construction used only to test the orbit mechanics.
 * It is a complete normal integer magic square, NOT a prime-magic seed.
 */
export function createNormalMagicFixture(size = 5): PrimeMagicSeed {
  if (!Number.isInteger(size) || size < 1 || (size & 1) === 0) {
    throw new RangeError("Siamese fixture size must be a positive odd integer");
  }
  const values = new Uint32Array(size * size);
  let row = 0;
  let column = Math.floor(size / 2);
  for (let value = 1; value <= size * size; value += 1) {
    values[row * size + column] = value;
    const candidateRow = (row + size - 1) % size;
    const candidateColumn = (column + 1) % size;
    if (values[candidateRow * size + candidateColumn] !== 0) {
      row = (row + 1) % size;
    } else {
      row = candidateRow;
      column = candidateColumn;
    }
  }
  return {
    size,
    magicSum: (size * (size * size + 1)) / 2,
    values,
    checksum: `fixture:normal-magic-${size}:not-prime`,
  };
}
