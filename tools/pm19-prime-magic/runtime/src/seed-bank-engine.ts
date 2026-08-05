import { PrimeMagicOrbitEngine } from "./engine.js";
import { Xoshiro128StarStar } from "./prng.js";
import type { PrimeMagicSeed } from "./types.js";

const SEED_DERIVATION_CONSTANT = 0x9e37_79b9_7f4a_7c15n;

/**
 * Uniformly selects a seed, then uniformly selects one legal transform in that
 * seed's orbit. When seed orbits are equal-sized and disjoint (as in the
 * packaged eight-center bank), this is uniform over their union.
 */
export class PrimeMagicSeedBankOrbitEngine {
  public readonly size: number;
  public readonly magicSum: number;
  public readonly seedCount: number;

  private readonly engines: readonly PrimeMagicOrbitEngine[];
  private readonly selector: Xoshiro128StarStar;
  private readonly cellCount: number;
  private readonly buffer0: Uint32Array;
  private readonly buffer1: Uint32Array;
  private currentBufferIndex = 0;
  private lastIndex = 0;

  public constructor(seeds: readonly PrimeMagicSeed[], randomSeed: bigint) {
    if (seeds.length < 1) throw new RangeError("seed bank must not be empty");
    const first = seeds[0]!;
    this.size = first.size;
    this.magicSum = first.magicSum;
    this.cellCount = first.values.length;
    this.seedCount = seeds.length;
    const engines: PrimeMagicOrbitEngine[] = [];
    for (let index = 0; index < seeds.length; index += 1) {
      const seed = seeds[index]!;
      if (
        seed.size !== this.size ||
        seed.magicSum !== this.magicSum ||
        seed.values.length !== this.cellCount
      ) {
        throw new RangeError("all seed-bank entries must share size and magic sum");
      }
      const derivedSeed = randomSeed ^ (SEED_DERIVATION_CONSTANT * BigInt(index + 1));
      engines.push(new PrimeMagicOrbitEngine(seed, derivedSeed));
    }
    this.engines = engines;
    this.selector = new Xoshiro128StarStar(randomSeed ^ 0xd1b5_4a32_d192_ed03n);
    this.buffer0 = new Uint32Array(first.values);
    this.buffer1 = new Uint32Array(first.values);
  }

  public nextInto(output: Uint32Array): void {
    if (!(output instanceof Uint32Array) || output.length !== this.cellCount) {
      throw new RangeError(`output must be Uint32Array(${this.cellCount})`);
    }
    this.lastIndex = this.selector.nextBounded(this.seedCount);
    this.engines[this.lastIndex]!.nextInto(output);
  }

  public nextView(): Uint32Array {
    this.currentBufferIndex ^= 1;
    const output = this.currentBufferIndex === 0 ? this.buffer0 : this.buffer1;
    this.nextInto(output);
    return output;
  }

  public currentView(): Uint32Array {
    return this.currentBufferIndex === 0 ? this.buffer0 : this.buffer1;
  }

  public lastSeedIndex(): number {
    return this.lastIndex;
  }
}
