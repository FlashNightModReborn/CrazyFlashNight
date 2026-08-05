import { loadPrimeMagicSeed, loadPrimeMagicSeedBank } from "../src/binary-seed.js";
import { PrimeMagicOrbitEngine } from "../src/engine.js";
import type { PrimeMagicSeed } from "../src/types.js";
import { PrimeMagicGridRenderer } from "./renderer.js";

interface LatencySummary {
  readonly samples: number;
  readonly medianMicroseconds: number;
  readonly p95Microseconds: number;
  readonly p99Microseconds: number;
  readonly maxMicroseconds: number;
  readonly operationsPerSecond: number;
}

interface WorkerBenchmarkResult {
  readonly summary: LatencySummary;
  readonly batchWallMilliseconds: number;
}

interface ChromeMemoryInfo {
  readonly jsHeapSizeLimit: number;
  readonly totalJSHeapSize: number;
  readonly usedJSHeapSize: number;
}

interface DetailedMemoryResult {
  readonly bytes: number;
}

interface PerformanceWithMemory extends Performance {
  readonly memory?: ChromeMemoryInfo;
  measureUserAgentSpecificMemory?: () => Promise<DetailedMemoryResult>;
}

function summarize(samples: Float64Array, elapsedMilliseconds: number): LatencySummary {
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

function measure(iterations: number, warmup: number, operation: (iteration: number) => void): LatencySummary {
  for (let iteration = 0; iteration < warmup; iteration += 1) operation(iteration);
  const samples = new Float64Array(iterations);
  const overallStart = performance.now();
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const start = performance.now();
    operation(iteration);
    samples[iteration] = performance.now() - start;
  }
  return summarize(samples, performance.now() - overallStart);
}

function makeFixedPermutation(): Uint8Array {
  const permutation = new Uint8Array(19);
  for (let targetPair = 0; targetPair < 9; targetPair += 1) {
    const sourcePair = 8 - targetPair;
    const source = (targetPair & 1) === 0 ? sourcePair : 18 - sourcePair;
    permutation[targetPair] = source;
    permutation[18 - targetPair] = 18 - source;
  }
  permutation[9] = 9;
  return permutation;
}

function benchmarkFixedCopies(seed: PrimeMagicSeed): {
  readonly typedArray: LatencySummary;
  readonly ordinaryArray: LatencySummary;
  readonly sink: number;
} {
  const permutation = makeFixedPermutation();
  const typedOutput = new Uint32Array(seed.values.length);
  const ordinaryInput = Array.from(seed.values);
  const ordinaryOutput = new Array<number>(seed.values.length).fill(0);
  let sink = 0;

  const typedArray = measure(100_000, 10_000, () => {
    let destination = 0;
    for (let row = 0; row < 19; row += 1) {
      const rowOffset = permutation[row]! * 19;
      for (let column = 0; column < 19; column += 1) {
        typedOutput[destination] = seed.values[rowOffset + permutation[column]!]!;
        destination += 1;
      }
    }
    sink ^= typedOutput[17]!;
  });

  const ordinaryArray = measure(100_000, 10_000, () => {
    let destination = 0;
    for (let row = 0; row < 19; row += 1) {
      const rowOffset = permutation[row]! * 19;
      for (let column = 0; column < 19; column += 1) {
        ordinaryOutput[destination] = ordinaryInput[rowOffset + permutation[column]!]!;
        destination += 1;
      }
    }
    sink ^= ordinaryOutput[17]!;
  });
  return { typedArray, ordinaryArray, sink };
}

class CanvasGlyphBenchmark {
  private readonly context: CanvasRenderingContext2D;
  private readonly atlas: HTMLCanvasElement;
  private readonly divisors = new Uint32Array([
    10_000_000, 1_000_000, 100_000, 10_000, 1_000, 100, 10, 1,
  ]);

  public constructor(canvas: HTMLCanvasElement) {
    canvas.width = 760;
    canvas.height = 760;
    const context = canvas.getContext("2d", { alpha: false });
    if (context === null) throw new Error("Canvas2D unavailable");
    this.context = context;
    this.atlas = document.createElement("canvas");
    this.atlas.width = 200;
    this.atlas.height = 32;
    const atlasContext = this.atlas.getContext("2d");
    if (atlasContext === null) throw new Error("Canvas2D atlas unavailable");
    atlasContext.fillStyle = "#9ffff0";
    atlasContext.font = "26px monospace";
    atlasContext.textAlign = "center";
    atlasContext.textBaseline = "middle";
    for (let digit = 0; digit < 10; digit += 1) {
      atlasContext.fillText(String(digit), digit * 20 + 10, 16);
    }
  }

  public render(values: Uint32Array): void {
    const context = this.context;
    context.fillStyle = "#02080b";
    context.fillRect(0, 0, 760, 760);
    const cell = 40;
    for (let index = 0; index < values.length; index += 1) {
      const row = Math.floor(index / 19);
      const column = index - row * 19;
      const value = values[index]!;
      for (let slot = 0; slot < 8; slot += 1) {
        const divisor = this.divisors[slot]!;
        if (slot !== 7 && value < divisor) continue;
        const digit = Math.floor(value / divisor) % 10;
        context.drawImage(
          this.atlas,
          digit * 20,
          0,
          20,
          32,
          column * cell + slot * 5,
          row * cell + 4,
          5,
          32,
        );
      }
    }
  }
}

function createDomBenchmarkHost(): { readonly host: HTMLElement; readonly cells: readonly HTMLElement[] } {
  const host = document.createElement("div");
  host.className = "dom-benchmark-grid";
  const cells: HTMLElement[] = [];
  for (let index = 0; index < 361; index += 1) {
    const cell = document.createElement("span");
    host.append(cell);
    cells.push(cell);
  }
  document.body.append(host);
  return { host, cells };
}

async function benchmarkWorker(seed: PrimeMagicSeed): Promise<WorkerBenchmarkResult> {
  const worker = new Worker("/dist/web/benchmark.worker.js", { type: "module" });
  const batchStart = performance.now();
  try {
    const summary = await new Promise<LatencySummary>((resolve, reject) => {
      worker.onmessage = (event: MessageEvent<{ readonly summary?: LatencySummary; readonly error?: string }>) => {
        if (event.data.error !== undefined) reject(new Error(event.data.error));
        else if (event.data.summary !== undefined) resolve(event.data.summary);
      };
      worker.onerror = (event) => reject(new Error(event.message));
      worker.postMessage({ kind: "run", seed, randomSeed: "2026", iterations: 100_000, warmup: 10_000 });
    });
    return { summary, batchWallMilliseconds: performance.now() - batchStart };
  } finally {
    worker.terminate();
  }
}

async function detailedMemory(performanceApi: PerformanceWithMemory): Promise<number | null> {
  if (performanceApi.measureUserAgentSpecificMemory === undefined || !window.crossOriginIsolated) {
    return null;
  }
  try {
    return (await performanceApi.measureUserAgentSpecificMemory()).bytes;
  } catch {
    return null;
  }
}

const canvas = document.querySelector<HTMLCanvasElement>("#benchmark-canvas");
const canvas2d = document.querySelector<HTMLCanvasElement>("#canvas2d-benchmark");
const button = document.querySelector<HTMLButtonElement>("#run-benchmark");
const output = document.querySelector<HTMLElement>("#benchmark-output");
if (canvas === null || canvas2d === null || button === null || output === null) {
  throw new Error("benchmark DOM is incomplete");
}
const runButton = button;
const reportOutput = output;
const bank = await loadPrimeMagicSeedBank("/web/assets/seed-bank.json");
const seed = await loadPrimeMagicSeed(bank.seeds[0]!);
const engine = new PrimeMagicOrbitEngine(seed, 2026n);
const board = new Uint32Array(seed.values.length);
const renderer = new PrimeMagicGridRenderer(canvas, seed.size, 8);
const canvasRenderer = new CanvasGlyphBenchmark(canvas2d);
renderer.updateValues(seed.values);
renderer.render(0);
canvasRenderer.render(seed.values);
reportOutput.textContent = `ready · ${seed.checksum}`;

runButton.addEventListener("click", async () => {
  runButton.disabled = true;
  reportOutput.textContent = "running…";
  await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
  const performanceApi = performance as PerformanceWithMemory;
  const memoryBefore = performanceApi.memory?.usedJSHeapSize ?? null;
  const detailedMemoryBefore = await detailedMemory(performanceApi);
  const gcEntrySupported = PerformanceObserver.supportedEntryTypes.includes("gc");
  let gcEntryCount = 0;
  let gcDurationMilliseconds = 0;
  const gcObserver = gcEntrySupported
    ? new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          gcEntryCount += 1;
          gcDurationMilliseconds += entry.duration;
        }
      })
    : null;
  gcObserver?.observe({ entryTypes: ["gc"] });

  try {
    const engineLatency = measure(100_000, 10_000, () => engine.nextInto(board));
    const fixedCopies = benchmarkFixedCopies(seed);
    const workerLatency = await benchmarkWorker(seed);

    const dom = createDomBenchmarkHost();
    const domLatency = measure(200, 20, () => {
      engine.nextInto(board);
      for (let index = 0; index < 361; index += 1) {
        dom.cells[index]!.textContent = String(board[index]!);
      }
      void dom.host.offsetWidth;
    });
    dom.host.remove();

    const canvas2dLatency = measure(500, 50, () => {
      engine.nextInto(board);
      canvasRenderer.render(board);
    });

    renderer.setVisualEffects(false);
    const webglEffectsOff = measure(1_000, 100, (iteration) => {
      engine.nextInto(board);
      renderer.updateValues(board);
      renderer.render(iteration / 144);
      renderer.finishForBenchmark();
    });
    renderer.setVisualEffects(true);
    const webglEffectsOn = measure(1_000, 100, (iteration) => {
      engine.nextInto(board);
      renderer.updateValues(board);
      renderer.render(iteration / 144);
      renderer.finishForBenchmark();
    });

    gcObserver?.disconnect();
    const detailedMemoryAfter = await detailedMemory(performanceApi);
    const memoryAfter = performanceApi.memory?.usedJSHeapSize ?? null;
    const report = {
      timestampUtc: new Date().toISOString(),
      browser: navigator.userAgent,
      hardwareConcurrency: navigator.hardwareConcurrency,
      devicePixelRatio: window.devicePixelRatio,
      crossOriginIsolated: window.crossOriginIsolated,
      seed: { checksum: seed.checksum, size: seed.size, magicSum: seed.magicSum },
      mainVsWorker: { main: engineLatency, worker: workerLatency },
      typedVsOrdinary: fixedCopies,
      renderers: {
        dom361TextNodesForcedLayout: domLatency,
        canvas2dGlyphAtlas: canvas2dLatency,
        webgl2EffectsOffSynchronous: webglEffectsOff,
        webgl2EffectsOnSynchronous: webglEffectsOn,
      },
      memoryAndGc: {
        performanceMemorySupported: performanceApi.memory !== undefined,
        usedJsHeapBefore: memoryBefore,
        usedJsHeapAfter: memoryAfter,
        usedJsHeapDelta: memoryBefore === null || memoryAfter === null ? null : memoryAfter - memoryBefore,
        detailedMemorySupported:
          performanceApi.measureUserAgentSpecificMemory !== undefined && window.crossOriginIsolated,
        detailedMemoryBefore,
        detailedMemoryAfter,
        gcPerformanceEntriesSupported: gcEntrySupported,
        gcEntryCount: gcEntrySupported ? gcEntryCount : null,
        gcDurationMilliseconds: gcEntrySupported ? gcDurationMilliseconds : null,
      },
      notes: [
        "WebGL metrics include nextInto, 1444-byte bufferSubData, draw, and gl.finish.",
        "gl.finish is intentionally pessimistic and must not be used in gameplay.",
        "DOM benchmark deliberately includes 361 String conversions and forced layout.",
        "Canvas2D benchmark uses a ten-glyph atlas and integer digit extraction, not fillText per cell.",
        "If GC entries are unavailable, capture Chrome Performance/Memory trace manually.",
        "WebGPU is analysis-only because one 19x19 board does not justify a second graphics stack.",
      ],
    };
    reportOutput.textContent = JSON.stringify(report, null, 2);
  } catch (error) {
    gcObserver?.disconnect();
    reportOutput.textContent = `benchmark fault\n${String(error)}`;
  } finally {
    runButton.disabled = false;
  }
});
