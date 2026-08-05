export type IndexArray = Uint8Array | Uint16Array;

/**
 * Runtime form of a seed that has already passed the independent offline
 * verifier.  This package intentionally does not perform primality testing.
 */
export interface PrimeMagicSeed {
  readonly size: number;
  readonly magicSum: number;
  readonly values: Uint32Array;
  readonly checksum: string;
}

/**
 * Source-index convention:
 * Without transpose, output[i,j] = seed[rowPermutation[i], columnPermutation[j]].
 * With transpose, output[i,j] = seed[rowPermutation[j], columnPermutation[i]].
 * Legal runtime transforms use reversal-commuting permutations whose row and
 * column maps are either equal or differ by one reversal.
 */
export interface OrbitTransform {
  readonly rowPermutation: IndexArray;
  readonly columnPermutation: IndexArray;
  readonly transpose: boolean;
}

export interface MutableOrbitTransform {
  readonly rowPermutation: IndexArray;
  readonly columnPermutation: IndexArray;
  transpose: boolean;
}

export interface SharedOrbitViews {
  readonly storage: SharedArrayBuffer;
  /** [frontBufferIndex, monotonically increasing version, readerIndexPlusOne] */
  readonly control: Int32Array;
  readonly boards: readonly [Uint32Array, Uint32Array];
}
