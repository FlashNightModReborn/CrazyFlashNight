import { Xoshiro128StarStar } from "./prng.js";
import { allocateIndexArray } from "./transform.js";
import type { IndexArray, OrbitTransform, PrimeMagicSeed } from "./types.js";

function validateSeedShape(seed: PrimeMagicSeed): void {
  if (!Number.isInteger(seed.size) || seed.size < 1 || seed.size > 65_536) {
    throw new RangeError("seed.size must be an integer in [1, 65536]");
  }
  const cellCount = seed.size * seed.size;
  if (!Number.isSafeInteger(cellCount) || seed.values.length !== cellCount) {
    throw new RangeError("seed.values length does not equal size squared");
  }
  if (!(seed.values instanceof Uint32Array)) {
    throw new TypeError("seed.values must be a Uint32Array");
  }
  if (!Number.isSafeInteger(seed.magicSum) || seed.magicSum < 0) {
    throw new RangeError("seed.magicSum must be a non-negative safe integer");
  }
  if (typeof seed.checksum !== "string" || seed.checksum.length === 0) {
    throw new TypeError("seed.checksum must be a non-empty string");
  }
}

/**
 * Uniformly samples the reversal centralizer, one independent-axis reversal,
 * and optional transpose, then copies exactly n^2 uint32 values into
 * caller-owned storage. This includes all eight square dihedral symmetries.
 *
 * The constructor allocates and copies. nextInto(), nextView(),
 * sampleTransformInto(), and applyTransformInto() allocate no JS objects or
 * backing stores on their successful hot paths.
 */
export class PrimeMagicOrbitEngine {
  public readonly size: number;
  public readonly magicSum: number;
  public readonly checksum: string;

  private readonly cellCount: number;
  private readonly seedValues: Uint32Array;
  private readonly random: Xoshiro128StarStar;
  private readonly pairCount: number;
  private readonly pairOrder: IndexArray;
  private readonly lastRowPermutation: IndexArray;
  private readonly lastColumnPermutation: IndexArray;
  private lastTranspose = false;

  private readonly validationMarks: Uint32Array;
  private validationEpoch = 0;

  private readonly buffer0: Uint32Array;
  private readonly buffer1: Uint32Array;
  private currentBufferIndex = 0;

  public constructor(seed: PrimeMagicSeed, randomSeed: bigint) {
    validateSeedShape(seed);
    this.size = seed.size;
    this.magicSum = seed.magicSum;
    this.checksum = seed.checksum;
    this.cellCount = seed.values.length;
    this.seedValues = new Uint32Array(seed.values);
    this.random = new Xoshiro128StarStar(randomSeed);
    this.pairCount = Math.floor(this.size / 2);
    this.pairOrder = allocateIndexArray(Math.max(1, this.pairCount));
    this.lastRowPermutation = allocateIndexArray(this.size);
    this.lastColumnPermutation = allocateIndexArray(this.size);
    this.validationMarks = new Uint32Array(this.size);
    this.buffer0 = new Uint32Array(this.cellCount);
    this.buffer1 = new Uint32Array(this.cellCount);
    this.buffer0.set(this.seedValues);
    this.buffer1.set(this.seedValues);

    for (let index = 0; index < this.size; index += 1) {
      this.lastRowPermutation[index] = index;
      this.lastColumnPermutation[index] = index;
    }
  }

  /** Generate the next independent, uniformly sampled legal group element. */
  public nextInto(output: Uint32Array): void {
    this.assertOutput(output);
    this.sampleAxisPermutationsInto(this.lastRowPermutation, this.lastColumnPermutation);
    this.lastTranspose = this.random.nextBoolean();
    this.applyUncheckedInto(
      this.lastRowPermutation,
      this.lastColumnPermutation,
      this.lastTranspose,
      output,
    );
  }

  /**
   * Alternate between two constructor-owned buffers. The returned reference is
   * stable but will be overwritten every other call.
   */
  public nextView(): Uint32Array {
    this.currentBufferIndex ^= 1;
    const output = this.currentBufferIndex === 0 ? this.buffer0 : this.buffer1;
    this.nextInto(output);
    return output;
  }

  /** Initial value is the seed; later it is the most recent nextView() result. */
  public currentView(): Uint32Array {
    return this.currentBufferIndex === 0 ? this.buffer0 : this.buffer1;
  }

  /**
   * Fill caller-owned arrays with a fresh legal transform. Return value is the
   * transpose bit. Arrays must be distinct so the full axis-reversal bit can
   * be represented and sampled uniformly.
   */
  public sampleTransformInto(rowPermutation: IndexArray, columnPermutation: IndexArray): boolean {
    this.assertPermutationOutput(rowPermutation);
    this.assertPermutationOutput(columnPermutation);
    if (columnPermutation === rowPermutation) {
      throw new RangeError("row and column permutation outputs must be distinct");
    }
    this.sampleAxisPermutationsInto(rowPermutation, columnPermutation);
    return this.random.nextBoolean();
  }

  /** Copy the transform most recently used by nextInto()/nextView(). */
  public copyLastTransformInto(rowPermutation: IndexArray, columnPermutation: IndexArray): boolean {
    this.assertPermutationOutput(rowPermutation);
    this.assertPermutationOutput(columnPermutation);
    if (columnPermutation === rowPermutation) {
      throw new RangeError("row and column permutation outputs must be distinct");
    }
    rowPermutation.set(this.lastRowPermutation);
    columnPermutation.set(this.lastColumnPermutation);
    return this.lastTranspose;
  }

  public applyTransformInto(transform: OrbitTransform, output: Uint32Array): void {
    this.assertOutput(output);
    if (!this.validateTransform(transform)) {
      throw new RangeError("transform is not in the legal reversal-centralizing coordinate group");
    }
    this.applyUncheckedInto(
      transform.rowPermutation,
      transform.columnPermutation,
      transform.transpose,
      output,
    );
  }

  /** O(n), allocation-free validation using an epoch-marked scratch array. */
  public validateTransform(transform: OrbitTransform): boolean {
    const row = transform.rowPermutation;
    const column = transform.columnPermutation;
    if (
      typeof transform.transpose !== "boolean" ||
      (!(row instanceof Uint8Array) && !(row instanceof Uint16Array)) ||
      (!(column instanceof Uint8Array) && !(column instanceof Uint16Array)) ||
      row.length !== this.size ||
      column.length !== this.size
    ) {
      return false;
    }

    let epoch = (this.validationEpoch + 1) >>> 0;
    if (epoch === 0) {
      this.validationMarks.fill(0);
      epoch = 1;
    }
    this.validationEpoch = epoch;

    const lastIndex = this.size - 1;
    const reversedAxes = this.size > 1 && row[0] === lastIndex - column[0]!;
    for (let index = 0; index < this.size; index += 1) {
      const value = row[index]!;
      const columnValue = column[index]!;
      if (
        value >= this.size ||
        columnValue >= this.size ||
        value !== (reversedAxes ? lastIndex - columnValue : columnValue) ||
        this.validationMarks[value] === epoch ||
        row[lastIndex - index] !== lastIndex - value ||
        column[lastIndex - index] !== lastIndex - columnValue
      ) {
        return false;
      }
      this.validationMarks[value] = epoch;
    }
    return true;
  }

  public saveRandomStateInto(output: Uint32Array): void {
    this.random.saveStateInto(output);
  }

  public restoreRandomState(input: Uint32Array): void {
    this.random.restoreState(input);
  }

  private assertOutput(output: Uint32Array): void {
    if (!(output instanceof Uint32Array) || output.length !== this.cellCount) {
      throw new RangeError(`output must be Uint32Array(${this.cellCount})`);
    }
  }

  private assertPermutationOutput(output: IndexArray): void {
    if (
      output.length !== this.size ||
      (this.size <= 256 && !(output instanceof Uint8Array) && !(output instanceof Uint16Array)) ||
      (this.size > 256 && !(output instanceof Uint16Array))
    ) {
      throw new RangeError("permutation output has the wrong type or length");
    }
  }

  private samplePermutationInto(output: IndexArray): void {
    for (let pair = 0; pair < this.pairCount; pair += 1) {
      this.pairOrder[pair] = pair;
    }

    for (let index = this.pairCount - 1; index > 0; index -= 1) {
      const other = this.random.nextBounded(index + 1);
      const temporary = this.pairOrder[index]!;
      this.pairOrder[index] = this.pairOrder[other]!;
      this.pairOrder[other] = temporary;
    }

    const lastIndex = this.size - 1;
    for (let pair = 0; pair < this.pairCount; pair += 1) {
      const sourcePair = this.pairOrder[pair]!;
      const source = this.random.nextBoolean() ? lastIndex - sourcePair : sourcePair;
      output[pair] = source;
      output[lastIndex - pair] = lastIndex - source;
    }
    if ((this.size & 1) !== 0) {
      output[this.pairCount] = this.pairCount;
    }
  }

  private sampleAxisPermutationsInto(row: IndexArray, column: IndexArray): void {
    this.samplePermutationInto(column);
    if (this.random.nextBoolean()) {
      const lastIndex = this.size - 1;
      for (let index = 0; index < this.size; index += 1) {
        row[index] = lastIndex - column[index]!;
      }
    } else {
      row.set(column);
    }
  }

  private applyUncheckedInto(
    rowPermutation: IndexArray,
    columnPermutation: IndexArray,
    transpose: boolean,
    output: Uint32Array,
  ): void {
    const size = this.size;
    const seed = this.seedValues;
    let destination = 0;

    if (!transpose) {
      for (let row = 0; row < size; row += 1) {
        const sourceRowOffset = rowPermutation[row]! * size;
        for (let column = 0; column < size; column += 1) {
          output[destination] = seed[sourceRowOffset + columnPermutation[column]!]!;
          destination += 1;
        }
      }
      return;
    }

    for (let row = 0; row < size; row += 1) {
      const sourceColumn = columnPermutation[row]!;
      for (let column = 0; column < size; column += 1) {
        output[destination] = seed[rowPermutation[column]! * size + sourceColumn]!;
        destination += 1;
      }
    }
  }
}
