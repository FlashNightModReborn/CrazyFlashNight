/** Deterministic 32-bit FNV-1a + Mulberry32 PRNG. */
export function hashString32(input) {
    let hash = 0x811c9dc5;
    for (let i = 0; i < input.length; i += 1) {
        hash ^= input.charCodeAt(i);
        hash = Math.imul(hash, 0x01000193);
    }
    return hash >>> 0;
}
export class DeterministicRng {
    state;
    constructor(seed) {
        this.state = typeof seed === 'number' ? seed >>> 0 : hashString32(seed);
        if (this.state === 0)
            this.state = 0x6d2b79f5;
    }
    nextUint32() {
        this.state = (this.state + 0x6d2b79f5) >>> 0;
        let t = this.state;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return (t ^ (t >>> 14)) >>> 0;
    }
    next() {
        return this.nextUint32() / 0x1_0000_0000;
    }
    range(min, max) {
        return min + (max - min) * this.next();
    }
    getState() {
        return this.state >>> 0;
    }
}
export function deterministicTie(seed, ...parts) {
    return hashString32([seed, ...parts].join('|'));
}
//# sourceMappingURL=rng.js.map