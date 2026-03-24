/**
 * Fuzzer 语料库管理
 */

export interface CorpusEntry {
  array: number[];
  template: string;
  params: Record<string, number>;
  risk: number;          // predictedRisk from model
  flashSeverity?: number; // Flash wall-clock severity (after labeling)
}

export class Corpus {
  private entries: CorpusEntry[] = [];

  get size(): number { return this.entries.length; }

  get worstRisk(): number {
    return this.entries.reduce((max, e) => Math.max(max, e.risk), 0);
  }

  add(entry: CorpusEntry): void {
    this.entries.push(entry);
  }

  /** 获取 risk 最高的 top-N 个条目 */
  topN(n: number): CorpusEntry[] {
    return [...this.entries]
      .sort((a, b) => b.risk - a.risk)
      .slice(0, n);
  }

  /** 按 risk 降序选择一个种子（轮盘赌选择） */
  selectByFitness(rng: { next(): number }): CorpusEntry | undefined {
    if (this.entries.length === 0) return undefined;
    const totalRisk = this.entries.reduce((s, e) => s + e.risk, 0);
    if (totalRisk <= 0) return this.entries[rng.next() % this.entries.length];
    let target = (rng.next() % 10000) / 10000 * totalRisk;
    for (const entry of this.entries) {
      target -= entry.risk;
      if (target <= 0) return entry;
    }
    return this.entries[this.entries.length - 1];
  }

  /** 获取所有条目 */
  all(): readonly CorpusEntry[] {
    return this.entries;
  }

  /** 去重（基于 template + params） */
  deduplicate(): void {
    const seen = new Set<string>();
    this.entries = this.entries.filter(e => {
      const key = `${e.template}:${JSON.stringify(e.params)}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }
}
