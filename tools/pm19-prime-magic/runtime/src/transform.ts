import type { IndexArray, MutableOrbitTransform, OrbitTransform } from "./types.js";

export function allocateIndexArray(size: number): IndexArray {
  if (!Number.isInteger(size) || size < 1 || size > 65_536) {
    throw new RangeError("size must be an integer in [1, 65536]");
  }
  return size <= 256 ? new Uint8Array(size) : new Uint16Array(size);
}

export function reversal(index: number, size: number): number {
  return size - 1 - index;
}

export function isPermutation(permutation: IndexArray, size = permutation.length): boolean {
  if (permutation.length !== size) {
    return false;
  }
  for (let index = 0; index < size; index += 1) {
    const value = permutation[index]!;
    if (value >= size) {
      return false;
    }
    for (let previous = 0; previous < index; previous += 1) {
      if (permutation[previous] === value) {
        return false;
      }
    }
  }
  return true;
}

export function commutesWithReversal(permutation: IndexArray, size = permutation.length): boolean {
  if (permutation.length !== size) {
    return false;
  }
  for (let index = 0; index < size; index += 1) {
    const reversedIndex = size - 1 - index;
    if (permutation[reversedIndex] !== size - 1 - permutation[index]!) {
      return false;
    }
  }
  return true;
}

export function isLegalOrbitTransform(transform: OrbitTransform, size: number): boolean {
  const row = transform.rowPermutation;
  const column = transform.columnPermutation;
  if (
    typeof transform.transpose !== "boolean" ||
    (!(row instanceof Uint8Array) && !(row instanceof Uint16Array)) ||
    (!(column instanceof Uint8Array) && !(column instanceof Uint16Array)) ||
    row.length !== size ||
    column.length !== size
  ) {
    return false;
  }
  const reversedAxes = size > 1 && row[0] === size - 1 - column[0]!;
  for (let index = 0; index < size; index += 1) {
    const expectedRow = reversedAxes ? size - 1 - column[index]! : column[index]!;
    if (row[index] !== expectedRow) {
      return false;
    }
  }
  return (
    isPermutation(row, size) &&
    isPermutation(column, size) &&
    commutesWithReversal(row, size) &&
    commutesWithReversal(column, size)
  );
}

/** |C_Sym(R)| = floor(n/2)! * 2^floor(n/2), for reversal R(i)=n-1-i. */
export function reversalCentralizerSize(size: number): bigint {
  if (!Number.isInteger(size) || size < 1) {
    throw new RangeError("size must be a positive integer");
  }
  const pairCount = Math.floor(size / 2);
  let result = 1n << BigInt(pairCount);
  for (let factor = 2; factor <= pairCount; factor += 1) {
    result *= BigInt(factor);
  }
  return result;
}

export function identityTransformInto(output: MutableOrbitTransform): void {
  const row = output.rowPermutation;
  const column = output.columnPermutation;
  if (row.length !== column.length) {
    throw new RangeError("row and column permutation lengths differ");
  }
  for (let index = 0; index < row.length; index += 1) {
    row[index] = index;
    column[index] = index;
  }
  output.transpose = false;
}

/**
 * Compose source-index transforms in execution order: apply first, then second.
 * Transpose swaps which second-axis map is fed into the first transform.
 * Transpose bits XOR.
 * Output arrays must not alias either input array.
 */
export function composeTransformsInto(
  first: OrbitTransform,
  second: OrbitTransform,
  output: MutableOrbitTransform,
): void {
  const size = first.rowPermutation.length;
  if (
    first.columnPermutation.length !== size ||
    second.rowPermutation.length !== size ||
    second.columnPermutation.length !== size ||
    output.rowPermutation.length !== size ||
    output.columnPermutation.length !== size
  ) {
    throw new RangeError("all transform arrays must have equal lengths");
  }
  if (
    output.rowPermutation === first.rowPermutation ||
    output.rowPermutation === first.columnPermutation ||
    output.rowPermutation === second.rowPermutation ||
    output.rowPermutation === second.columnPermutation ||
    output.columnPermutation === first.rowPermutation ||
    output.columnPermutation === first.columnPermutation ||
    output.columnPermutation === second.rowPermutation ||
    output.columnPermutation === second.columnPermutation
  ) {
    throw new Error("composition output must not alias an input array");
  }

  for (let index = 0; index < size; index += 1) {
    if (!first.transpose) {
      output.rowPermutation[index] = first.rowPermutation[second.rowPermutation[index]!]!;
      output.columnPermutation[index] = first.columnPermutation[second.columnPermutation[index]!]!;
    } else {
      output.rowPermutation[index] = first.rowPermutation[second.columnPermutation[index]!]!;
      output.columnPermutation[index] = first.columnPermutation[second.rowPermutation[index]!]!;
    }
  }
  output.transpose = first.transpose !== second.transpose;
}

export function invertTransformInto(input: OrbitTransform, output: MutableOrbitTransform): void {
  const size = input.rowPermutation.length;
  if (
    input.columnPermutation.length !== size ||
    output.rowPermutation.length !== size ||
    output.columnPermutation.length !== size
  ) {
    throw new RangeError("all transform arrays must have equal lengths");
  }
  if (
    output.rowPermutation === input.rowPermutation ||
    output.rowPermutation === input.columnPermutation ||
    output.columnPermutation === input.rowPermutation ||
    output.columnPermutation === input.columnPermutation
  ) {
    throw new Error("inverse output must not alias an input array");
  }
  for (let index = 0; index < size; index += 1) {
    if (!input.transpose) {
      output.rowPermutation[input.rowPermutation[index]!] = index;
      output.columnPermutation[input.columnPermutation[index]!] = index;
    } else {
      output.columnPermutation[input.rowPermutation[index]!] = index;
      output.rowPermutation[input.columnPermutation[index]!] = index;
    }
  }
  output.transpose = input.transpose;
}
