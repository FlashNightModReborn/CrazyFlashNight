/**
 * Fuzzer 主循环
 *
 * 在 TS native-sort 模型上快速评估候选输入的退化风险，
 * 将高 risk 候选收入语料库等待 Flash 标注。
 */

import { LCG } from "../shared/lcg.js";
import { DISCARD_THRESHOLD, LABEL_THRESHOLD, DEFAULT_N } from "../shared/constants.js";
import { nativeSortModel, predictedRisk } from "../model/native-sort.js";
import { Corpus, CorpusEntry } from "./corpus.js";
import {
  genNearSorted, genPlateau, genMountain,
  genComposite, genPeriodic, genAdversarial,
  genAdversarialReverse, GeneratedInput,
} from "./grammar.js";
import { mutateSwap, mutateSegment, mutateReverse } from "./mutator.js";

export interface FuzzConfig {
  n: number;
  grammarRounds: number;   // 语法生成轮数
  mutationRounds: number;  // 突变轮数
  mutationsPerSeed: number; // 每个种子的突变数
  seed: number;
}

const DEFAULT_CONFIG: FuzzConfig = {
  n: DEFAULT_N,
  grammarRounds: 500,
  mutationRounds: 2000,
  mutationsPerSeed: 5,
  seed: 42,
};

export function runFuzzer(config: Partial<FuzzConfig> = {}): Corpus {
  const cfg = { ...DEFAULT_CONFIG, ...config };
  const rng = new LCG(cfg.seed);
  const corpus = new Corpus();
  const n = cfg.n;

  console.log(`Fuzzer: n=${n}, grammar=${cfg.grammarRounds}, mutation=${cfg.mutationRounds}`);

  // Phase 1: 语法生成 — 系统扫描参数空间
  console.log("Phase 1: Grammar generation...");

  // nearSorted: perturbRate 从 0.001 到 0.20
  for (let i = 0; i < 100; i++) {
    const rate = 0.001 + (i / 99) * 0.199;
    evaluate(genNearSorted(n, "asc", rate, new LCG(rng.next())), n, corpus);
    evaluate(genNearSorted(n, "desc", rate, new LCG(rng.next())), n, corpus);
  }

  // plateau: k 从 2 到 50
  for (let k = 2; k <= 50; k++) {
    for (const order of ["asc", "desc", "random"] as const) {
      evaluate(genPlateau(n, k, order, new LCG(rng.next())), n, corpus);
    }
  }

  // mountain: peakPos 从 0.1 到 0.9, allUnique true/false
  for (let i = 0; i < 50; i++) {
    const pos = 0.1 + (i / 49) * 0.8;
    evaluate(genMountain(n, pos, true), n, corpus);
    evaluate(genMountain(n, pos, false), n, corpus);
  }

  // composite: sortedFrac 从 0.1 到 0.95
  for (let i = 0; i < 50; i++) {
    const frac = 0.1 + (i / 49) * 0.85;
    evaluate(genComposite(n, frac, new LCG(rng.next())), n, corpus);
  }

  // periodic: period 从 2 到 500
  for (const p of [2, 3, 5, 10, 20, 50, 100, 200, 500]) {
    evaluate(genPeriodic(n, p), n, corpus);
  }

  // adversarial
  evaluate(genAdversarial(n), n, corpus);
  evaluate(genAdversarialReverse(n), n, corpus);

  console.log(`  Grammar phase: corpus=${corpus.size}, worst risk=${corpus.worstRisk.toFixed(1)}`);

  // Phase 2: 突变 — 从高 risk 种子出发做局部变异
  console.log("Phase 2: Mutation...");

  for (let round = 0; round < cfg.mutationRounds; round++) {
    const seed = corpus.selectByFitness(rng);
    if (!seed) continue;

    for (let m = 0; m < cfg.mutationsPerSeed; m++) {
      const mutRng = new LCG(rng.next());
      const strategy = rng.next() % 3;
      let mutated: number[];

      if (strategy === 0) {
        // 随机交换 1-5% 元素
        const k = 1 + mutRng.next() % Math.max(1, Math.floor(n * 0.05));
        mutated = mutateSwap(seed.array, k, mutRng);
      } else if (strategy === 1) {
        // 段替换 1-10% 长度
        const len = 1 + mutRng.next() % Math.max(1, Math.floor(n * 0.10));
        const start = mutRng.next() % n;
        mutated = mutateSegment(seed.array, start, len, mutRng);
      } else {
        // 局部反转
        const start = mutRng.next() % n;
        const len = 1 + mutRng.next() % Math.max(1, Math.floor(n * 0.20));
        mutated = mutateReverse(seed.array, start, start + len);
      }

      const input: GeneratedInput = {
        array: mutated,
        template: `mutant_${seed.template}`,
        params: { ...seed.params, mutation: strategy, round },
      };
      evaluate(input, n, corpus);
    }
  }

  corpus.deduplicate();
  console.log(`  Mutation phase: corpus=${corpus.size}, worst risk=${corpus.worstRisk.toFixed(1)}`);

  return corpus;
}

function evaluate(input: GeneratedInput, n: number, corpus: Corpus): void {
  const { stats } = nativeSortModel(input.array);
  const risk = predictedRisk(stats.comparisons, n);

  if (risk >= DISCARD_THRESHOLD) {
    const entry: CorpusEntry = {
      array: input.array,
      template: input.template,
      params: input.params,
      risk,
    };
    corpus.add(entry);
  }
}
