import { PrimeMagicOrbitEngine } from "./engine.js";
import { Xoshiro128StarStar } from "./prng.js";
const SEED_DERIVATION_CONSTANT = 0x9e3779b97f4a7c15n;
/**
 * Uniformly selects a seed, then uniformly selects one legal transform in that
 * seed's orbit. When seed orbits are equal-sized and disjoint (as in the
 * packaged eight-center bank), this is uniform over their union.
 */
export class PrimeMagicSeedBankOrbitEngine {
    size;
    magicSum;
    seedCount;
    engines;
    selector;
    cellCount;
    buffer0;
    buffer1;
    currentBufferIndex = 0;
    lastIndex = 0;
    constructor(seeds, randomSeed) {
        if (seeds.length < 1)
            throw new RangeError("seed bank must not be empty");
        const first = seeds[0];
        this.size = first.size;
        this.magicSum = first.magicSum;
        this.cellCount = first.values.length;
        this.seedCount = seeds.length;
        const engines = [];
        for (let index = 0; index < seeds.length; index += 1) {
            const seed = seeds[index];
            if (seed.size !== this.size ||
                seed.magicSum !== this.magicSum ||
                seed.values.length !== this.cellCount) {
                throw new RangeError("all seed-bank entries must share size and magic sum");
            }
            const derivedSeed = randomSeed ^ (SEED_DERIVATION_CONSTANT * BigInt(index + 1));
            engines.push(new PrimeMagicOrbitEngine(seed, derivedSeed));
        }
        this.engines = engines;
        this.selector = new Xoshiro128StarStar(randomSeed ^ 0xd1b54a32d192ed03n);
        this.buffer0 = new Uint32Array(first.values);
        this.buffer1 = new Uint32Array(first.values);
    }
    nextInto(output) {
        if (!(output instanceof Uint32Array) || output.length !== this.cellCount) {
            throw new RangeError(`output must be Uint32Array(${this.cellCount})`);
        }
        this.lastIndex = this.selector.nextBounded(this.seedCount);
        this.engines[this.lastIndex].nextInto(output);
    }
    nextView() {
        this.currentBufferIndex ^= 1;
        const output = this.currentBufferIndex === 0 ? this.buffer0 : this.buffer1;
        this.nextInto(output);
        return output;
    }
    currentView() {
        return this.currentBufferIndex === 0 ? this.buffer0 : this.buffer1;
    }
    lastSeedIndex() {
        return this.lastIndex;
    }
}
//# sourceMappingURL=seed-bank-engine.js.map