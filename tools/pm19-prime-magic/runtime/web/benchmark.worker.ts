import { PrimeMagicOrbitEngine } from "../src/engine.js";
import type { PrimeMagicSeed } from "../src/types.js";

interface RunMessage {
  readonly kind: "run";
  readonly seed: PrimeMagicSeed;
  readonly randomSeed: string;
  readonly iterations: number;
  readonly warmup: number;
}

function summarize(samples: Float64Array, elapsedMilliseconds: number): object {
  samples.sort();
  const at = (probability: number): number => {
    const index = Math.min(samples.length - 1, Math.floor(samples.length * probability));
    return samples[index]! * 1_000;
  };
  return {
    samples: samples.length,
    medianMicroseconds: at(0.5),
    p95Microseconds: at(0.95),
    p99Microseconds: at(0.99),
    maxMicroseconds: samples[samples.length - 1]! * 1_000,
    operationsPerSecond: (samples.length * 1_000) / elapsedMilliseconds,
  };
}

globalThis.onmessage = (event: MessageEvent<RunMessage>): void => {
  try {
    const message = event.data;
    const engine = new PrimeMagicOrbitEngine(message.seed, BigInt(message.randomSeed));
    const output = new Uint32Array(message.seed.values.length);
    for (let iteration = 0; iteration < message.warmup; iteration += 1) engine.nextInto(output);
    const samples = new Float64Array(message.iterations);
    const overallStart = performance.now();
    for (let iteration = 0; iteration < message.iterations; iteration += 1) {
      const start = performance.now();
      engine.nextInto(output);
      samples[iteration] = performance.now() - start;
    }
    globalThis.postMessage({ summary: summarize(samples, performance.now() - overallStart) });
  } catch (error) {
    globalThis.postMessage({ error: String(error) });
  }
};
