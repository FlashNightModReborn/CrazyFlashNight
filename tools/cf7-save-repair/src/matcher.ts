// fffd 串 → 候选还原值匹配器
//
// 关键观察：tester 存档显示 fffd 不是 1:1 替换 —— 多次 saveAll 把 1 个 CJK 字符
// 扩展成多个 fffd（每次 chunk 边界切割让 EF/BF/BD 字节再次变 fffd，下轮 JSON 序列化
// 又写回 3 字节 → 下一轮再切。原 1 字符可能膨胀成 3、9 个 fffd）。
//
// 因此匹配策略：anchor subsequence。
//   1. 把 fffd 去掉，剩下的 ASCII / CJK 字符是「anchor」
//   2. 候选必须按顺序包含全部 anchor（subsequence 匹配，允许任意间隔）
//   3. 长度无硬约束：候选可比 broken 短得多
// 排序：先优先同长度（1:1 case），再按长度差升序，最后字典序。

export interface MatchCandidate {
  value: string;
  confidence: number;  // 0..1，越高越确定
  source: 'self_ref' | 'dict' | 'dict_unique';
}

const FFFD = '�';

export function findCandidates(
  broken: string,
  dictBucket: string[],
  selfRefPool: string[] = [],
): MatchCandidate[] {
  const brokenChars = [...broken];
  const anchors = brokenChars.filter((c) => c !== FFFD);

  // 没 anchor 完全无法定位（broken 全是 fffd），跳过
  if (anchors.length === 0) return [];

  const matchAndRank = (candidate: string) => {
    if (!isSubsequenceMatch(candidate, anchors)) return null;
    return Math.abs([...candidate].length - brokenChars.length); // 长度差
  };

  const seen = new Set<string>();
  const fromSelf: Array<MatchCandidate & { _diff: number }> = [];
  for (const v of selfRefPool) {
    if (!v || seen.has(v)) continue;
    const diff = matchAndRank(v);
    if (diff === null) continue;
    seen.add(v);
    fromSelf.push({ value: v, confidence: 1.0, source: 'self_ref', _diff: diff });
  }

  const fromDict: Array<MatchCandidate & { _diff: number }> = [];
  for (const v of dictBucket) {
    if (!v || seen.has(v)) continue;
    const diff = matchAndRank(v);
    if (diff === null) continue;
    seen.add(v);
    fromDict.push({ value: v, confidence: 0, source: 'dict', _diff: diff });
  }

  // 排序：长度差升序 → 字典序
  const sortByDiff = (
    a: MatchCandidate & { _diff: number },
    b: MatchCandidate & { _diff: number },
  ) => a._diff - b._diff || a.value.localeCompare(b.value);
  fromSelf.sort(sortByDiff);
  fromDict.sort(sortByDiff);

  // unique 标记：dict 仅 1 个 + 无 self_ref → dict_unique 提升置信度
  if (fromSelf.length === 0 && fromDict.length === 1) {
    fromDict[0]!.source = 'dict_unique';
    fromDict[0]!.confidence = 1.0;
  } else {
    const total = fromSelf.length + fromDict.length;
    for (const c of fromDict) c.confidence = total > 0 ? 1 / total : 0;
  }

  return [...fromSelf, ...fromDict].map((c) => ({
    value: c.value,
    confidence: c.confidence,
    source: c.source,
  }));
}

function isSubsequenceMatch(candidate: string, anchors: string[]): boolean {
  const cChars = [...candidate];
  let ci = 0;
  for (const a of anchors) {
    let found = false;
    while (ci < cChars.length) {
      if (cChars[ci] === a) {
        found = true;
        ci++;
        break;
      }
      ci++;
    }
    if (!found) return false;
  }
  return true;
}
