import os from "node:os";
import { writeFileSync } from "node:fs";
import { performance } from "node:perf_hooks";
import {
  loadLocalPrimeMagicSeed,
  loadLocalSeedBankManifest,
} from "../examples/load-node-seeds.js";
import { PrimeMagicOrbitEngine } from "../src/engine.js";
import { PrimeMagicSeedBankOrbitEngine } from "../src/seed-bank-engine.js";

interface Summary {
  readonly samples: number;
  readonly medianMicroseconds: number;
  readonly p95Microseconds: number;
  readonly p99Microseconds: number;
  readonly maxMicroseconds: number;
  readonly boardsPerSecond: number;
  readonly heapDeltaBytes: number | null;
}

const iterations = Number.parseInt(process.env.BENCH_ITERATIONS ?? "250000", 10);
const warmupIterations = Number.parseInt(process.env.BENCH_WARMUP ?? "25000", 10);
if (!Number.isInteger(iterations) || iterations < 1 || !Number.isInteger(warmupIterations) || warmupIterations < 0) {
  throw new Error("BENCH_ITERATIONS must be positive and BENCH_WARMUP non-negative");
}

const seed = loadLocalPrimeMagicSeed(0);
const permutation = new Uint8Array(seed.size);
for (let targetPair = 0; targetPair < 9; targetPair += 1) {
  const sourcePair = 8 - targetPair;
  const source = (targetPair & 1) === 0 ? sourcePair : 18 - sourcePair;
  permutation[targetPair] = source;
  permutation[18 - targetPair] = 18 - source;
}
permutation[9] = 9;

function percentile(sorted: Float64Array, probability: number): number {
  const index = Math.min(sorted.length - 1, Math.floor(probability * sorted.length));
  return sorted[index]! * 1_000;
}

function runBenchmark(operation: () => void): Summary {
  for (let index = 0; index < warmupIterations; index += 1) {
    operation();
  }

  if (typeof global.gc === "function") global.gc();
  const heapBefore = typeof global.gc === "function" ? process.memoryUsage().heapUsed : null;
  const samples = new Float64Array(iterations);
  const overallStart = performance.now();
  for (let index = 0; index < iterations; index += 1) {
    const start = performance.now();
    operation();
    samples[index] = performance.now() - start;
  }
  const overallElapsed = performance.now() - overallStart;
  if (typeof global.gc === "function") global.gc();
  const heapAfter = heapBefore === null ? null : process.memoryUsage().heapUsed;
  samples.sort();

  return {
    samples: iterations,
    medianMicroseconds: percentile(samples, 0.5),
    p95Microseconds: percentile(samples, 0.95),
    p99Microseconds: percentile(samples, 0.99),
    maxMicroseconds: samples[samples.length - 1]! * 1_000,
    boardsPerSecond: (iterations * 1_000) / overallElapsed,
    heapDeltaBytes: heapBefore === null || heapAfter === null ? null : heapAfter - heapBefore,
  };
}

const engine = new PrimeMagicOrbitEngine(seed, 0xdecaf_bad5eedn);
const typedOutput = new Uint32Array(seed.values.length);
let typedSink = 0;
const randomOrbit = runBenchmark(() => {
  engine.nextInto(typedOutput);
  typedSink ^= typedOutput[17]!;
});

const bankManifest = loadLocalSeedBankManifest();
const bankSeeds = bankManifest.seeds.map((entry) => loadLocalPrimeMagicSeed(entry.index));
const bankEngine = new PrimeMagicSeedBankOrbitEngine(bankSeeds, 0xdecaf_bad5eedn);
const bankOutput = new Uint32Array(seed.values.length);
const randomBankOrbit = runBenchmark(() => {
  bankEngine.nextInto(bankOutput);
  typedSink ^= bankOutput[17]!;
});

function fixedTypedCopy(): void {
  let destination = 0;
  for (let row = 0; row < seed.size; row += 1) {
    const rowOffset = permutation[row]! * seed.size;
    for (let column = 0; column < seed.size; column += 1) {
      typedOutput[destination] = seed.values[rowOffset + permutation[column]!]!;
      destination += 1;
    }
  }
  typedSink ^= typedOutput[31]!;
}
const fixedTyped = runBenchmark(fixedTypedCopy);

const ordinaryInput = Array.from(seed.values);
const ordinaryOutput = new Array<number>(seed.values.length).fill(0);
let ordinarySink = 0;
function fixedOrdinaryCopy(): void {
  let destination = 0;
  for (let row = 0; row < seed.size; row += 1) {
    const rowOffset = permutation[row]! * seed.size;
    for (let column = 0; column < seed.size; column += 1) {
      ordinaryOutput[destination] = ordinaryInput[rowOffset + permutation[column]!]!;
      destination += 1;
    }
  }
  ordinarySink ^= ordinaryOutput[31]!;
}
const fixedOrdinary = runBenchmark(fixedOrdinaryCopy);

const report = {
  timestampUtc: new Date().toISOString(),
  runtime: {
    node: process.version,
    v8: process.versions.v8,
    platform: `${process.platform}/${process.arch}`,
    cpu: os.cpus()[0]?.model ?? "unknown",
    logicalCpus: os.cpus().length,
    totalMemoryBytes: os.totalmem(),
  },
  seed: {
    size: seed.size,
    cells: seed.values.length,
    checksum: seed.checksum,
    source: "verified PM19 seed 00",
  },
  warmupIterations,
  measurements: {
    randomOrbitTypedArray: randomOrbit,
    randomEightSeedBankTypedArray: randomBankOrbit,
    fixedPermutationTypedArray: fixedTyped,
    fixedPermutationOrdinaryArray: fixedOrdinary,
  },
  sink: typedSink ^ ordinarySink,
  caveats: [
    "Per-call performance.now() overhead is included in latency percentiles.",
    "heapDeltaBytes is post-GC retained heap, not total allocation traffic.",
    "Browser, Worker, renderer, and GPU metrics must be measured in target Chromium.",
  ],
};

const rendered = `${JSON.stringify(report, null, 2)}\n`;
const reportPath = process.env.BENCH_REPORT;
if (reportPath !== undefined && reportPath.length > 0) {
  writeFileSync(reportPath, rendered, { encoding: "utf8" });
}
process.stdout.write(rendered);
