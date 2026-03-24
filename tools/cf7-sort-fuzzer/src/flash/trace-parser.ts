/**
 * flashlog.txt 结构化解析器
 *
 * 探针和 benchmark harness 的 trace 输出使用标记行格式：
 *   [PROBE:key] value
 *   [BENCH:dist] native=123 intro=456
 *   [CMP_SEQ:label] 0,1;1,2;0,2;...
 */

export interface ProbeResult {
  key: string;
  value: string;
}

export interface BenchResult {
  dist: string;
  nativeMs: number;
  introMs: number;
  severity: number;
}

export interface CmpSeqResult {
  label: string;
  pairs: Array<[number, number]>;
  count: number;
}

/** 从 trace 中提取 [PROBE:key] value 行 */
export function parseProbes(trace: string): ProbeResult[] {
  const results: ProbeResult[] = [];
  for (const line of trace.split("\n")) {
    const m = line.match(/\[PROBE:([^\]]+)\]\s*(.*)/);
    if (m) {
      results.push({ key: m[1], value: m[2].trim() });
    }
  }
  return results;
}

/** 从 trace 中提取 [BENCH:dist] native=X intro=Y 行 */
export function parseBenchmarks(trace: string): BenchResult[] {
  const results: BenchResult[] = [];
  for (const line of trace.split("\n")) {
    const m = line.match(/\[BENCH:([^\]]+)\]\s*native=(\d+)\s+intro=(\d+)/);
    if (m) {
      const nativeMs = parseInt(m[2], 10);
      const introMs = parseInt(m[3], 10);
      results.push({
        dist: m[1],
        nativeMs,
        introMs,
        severity: introMs > 0 ? nativeMs / introMs : Infinity,
      });
    }
  }
  return results;
}

/** 从 trace 中提取 [CMP_SEQ:label] 比较序列 */
export function parseCmpSequences(trace: string): CmpSeqResult[] {
  const results: CmpSeqResult[] = [];
  for (const line of trace.split("\n")) {
    const m = line.match(/\[CMP_SEQ:([^\]]+)\]\s*(.*)/);
    if (m) {
      const raw = m[2].trim();
      const pairs: Array<[number, number]> = [];
      if (raw.length > 0) {
        for (const p of raw.split(";")) {
          const [a, b] = p.split(",").map(Number);
          if (!isNaN(a) && !isNaN(b)) pairs.push([a, b]);
        }
      }
      results.push({ label: m[1], pairs, count: pairs.length });
    }
  }
  return results;
}
