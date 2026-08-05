const MASK_64 = (1n << 64n) - 1n;
const SPLITMIX_INCREMENT = 0x9e3779b97f4a7c15n;
const SPLITMIX_MUL_1 = 0xbf58476d1ce4e5b9n;
const SPLITMIX_MUL_2 = 0x94d049bb133111ebn;
function rotateLeft32(value, bits) {
    return ((value << bits) | (value >>> (32 - bits))) >>> 0;
}
function splitMix64Next(state) {
    const nextState = (state + SPLITMIX_INCREMENT) & MASK_64;
    let value = nextState;
    value = ((value ^ (value >> 30n)) * SPLITMIX_MUL_1) & MASK_64;
    value = ((value ^ (value >> 27n)) * SPLITMIX_MUL_2) & MASK_64;
    value ^= value >> 31n;
    return [nextState, value & MASK_64];
}
/**
 * xoshiro128**. BigInt is used only while expanding the constructor seed;
 * nextUint32()/nextBounded() stay entirely in 32-bit number arithmetic.
 */
export class Xoshiro128StarStar {
    state0;
    state1;
    state2;
    state3;
    constructor(seed) {
        let splitState = seed & MASK_64;
        let sample;
        [splitState, sample] = splitMix64Next(splitState);
        this.state0 = Number(sample & 0xffffffffn) >>> 0;
        [splitState, sample] = splitMix64Next(splitState);
        this.state1 = Number(sample & 0xffffffffn) >>> 0;
        [splitState, sample] = splitMix64Next(splitState);
        this.state2 = Number(sample & 0xffffffffn) >>> 0;
        [, sample] = splitMix64Next(splitState);
        this.state3 = Number(sample & 0xffffffffn) >>> 0;
        if ((this.state0 | this.state1 | this.state2 | this.state3) === 0) {
            this.state0 = 1;
        }
    }
    nextUint32() {
        const result = Math.imul(rotateLeft32(Math.imul(this.state1, 5), 7), 9) >>> 0;
        const temporary = (this.state1 << 9) >>> 0;
        this.state2 = (this.state2 ^ this.state0) >>> 0;
        this.state3 = (this.state3 ^ this.state1) >>> 0;
        this.state1 = (this.state1 ^ this.state2) >>> 0;
        this.state0 = (this.state0 ^ this.state3) >>> 0;
        this.state2 = (this.state2 ^ temporary) >>> 0;
        this.state3 = rotateLeft32(this.state3, 11);
        return result;
    }
    /** Uniform on [0, bound), using rejection rather than biased x % bound. */
    nextBounded(bound) {
        if (!Number.isInteger(bound) || bound < 1 || bound > 0x1_0000_0000) {
            throw new RangeError("bound must be an integer in [1, 2^32]");
        }
        if (bound === 0x1_0000_0000) {
            return this.nextUint32();
        }
        const rejectionThreshold = (0x1_0000_0000 - bound) % bound;
        let sample;
        do {
            sample = this.nextUint32();
        } while (sample < rejectionThreshold);
        return sample % bound;
    }
    nextBoolean() {
        return (this.nextUint32() & 1) !== 0;
    }
    saveStateInto(output) {
        if (output.length < 4) {
            throw new RangeError("PRNG state output needs at least four words");
        }
        output[0] = this.state0;
        output[1] = this.state1;
        output[2] = this.state2;
        output[3] = this.state3;
    }
    restoreState(input) {
        if (input.length < 4) {
            throw new RangeError("PRNG state input needs at least four words");
        }
        const state0 = input[0];
        const state1 = input[1];
        const state2 = input[2];
        const state3 = input[3];
        if ((state0 | state1 | state2 | state3) === 0) {
            throw new RangeError("xoshiro128** forbids the all-zero state");
        }
        this.state0 = state0;
        this.state1 = state1;
        this.state2 = state2;
        this.state3 = state3;
    }
}
//# sourceMappingURL=prng.js.map