// fffd 串 → 候选还原值匹配器（anchor subsequence）。
// 与 tools/cf7-save-repair/src/matcher.ts 同源。
//
// 关键观察：tester 存档显示 fffd 不是 1:1 替换 —— 多次 saveAll 把 1 个 CJK 字符
// 扩展成多个 fffd（每次 chunk 边界切割让 EF/BF/BD 字节再次变 fffd，下轮 JSON 序列化
// 又写回 3 字节 → 下一轮再切。原 1 字符可能膨胀成 3、9 个 fffd）。
//
// 因此匹配策略：anchor subsequence。
//   1. 把 fffd 去掉，剩下的 ASCII / CJK 字符是「anchor」
//   2. 候选必须按顺序包含全部 anchor（subsequence 匹配，允许任意间隔）
//   3. 长度无硬约束：候选可比 broken 短得多

using System;
using System.Collections.Generic;

namespace CF7Launcher.Save
{
    public enum RepairCandidateSource
    {
        SelfRef,
        Dict,
        DictUnique,
    }

    public class RepairCandidate
    {
        public readonly string Value;
        public double Confidence;
        public RepairCandidateSource Source;

        public RepairCandidate(string value, double confidence, RepairCandidateSource source)
        {
            Value = value;
            Confidence = confidence;
            Source = source;
        }
    }

    public static class RepairMatcher
    {
        private const char FFFD = '�';

        public static List<RepairCandidate> FindCandidates(string broken, string[] dictBucket, string[] selfRefPool)
        {
            // codepoint-aware anchors
            int brokenLen = CountCodepoints(broken);
            int[] anchors = ExtractAnchorCodepoints(broken);
            if (anchors.Length == 0)
                return new List<RepairCandidate>();

            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);

            List<RankedCandidate> fromSelf = new List<RankedCandidate>();
            if (selfRefPool != null)
            {
                for (int i = 0; i < selfRefPool.Length; i++)
                {
                    string v = selfRefPool[i];
                    if (string.IsNullOrEmpty(v) || seen.Contains(v)) continue;
                    if (!IsSubsequenceMatch(v, anchors)) continue;
                    seen.Add(v);
                    fromSelf.Add(new RankedCandidate(v, Math.Abs(CountCodepoints(v) - brokenLen), RepairCandidateSource.SelfRef));
                }
            }

            List<RankedCandidate> fromDict = new List<RankedCandidate>();
            if (dictBucket != null)
            {
                for (int i = 0; i < dictBucket.Length; i++)
                {
                    string v = dictBucket[i];
                    if (string.IsNullOrEmpty(v) || seen.Contains(v)) continue;
                    if (!IsSubsequenceMatch(v, anchors)) continue;
                    seen.Add(v);
                    fromDict.Add(new RankedCandidate(v, Math.Abs(CountCodepoints(v) - brokenLen), RepairCandidateSource.Dict));
                }
            }

            fromSelf.Sort(RankedCandidate.Compare);
            fromDict.Sort(RankedCandidate.Compare);

            List<RepairCandidate> result = new List<RepairCandidate>(fromSelf.Count + fromDict.Count);

            // 同时只能由 dict 提供 → unique 升级
            bool dictUnique = fromSelf.Count == 0 && fromDict.Count == 1;
            int total = fromSelf.Count + fromDict.Count;

            for (int i = 0; i < fromSelf.Count; i++)
                result.Add(new RepairCandidate(fromSelf[i].Value, 1.0, RepairCandidateSource.SelfRef));

            for (int i = 0; i < fromDict.Count; i++)
            {
                if (dictUnique)
                    result.Add(new RepairCandidate(fromDict[i].Value, 1.0, RepairCandidateSource.DictUnique));
                else
                    result.Add(new RepairCandidate(fromDict[i].Value, total > 0 ? 1.0 / total : 0, RepairCandidateSource.Dict));
            }

            return result;
        }

        private static int CountCodepoints(string s)
        {
            if (s == null) return 0;
            int count = 0;
            for (int i = 0; i < s.Length; i++)
            {
                if (char.IsHighSurrogate(s[i]) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1])) i++;
                count++;
            }
            return count;
        }

        private static int[] ExtractAnchorCodepoints(string broken)
        {
            if (string.IsNullOrEmpty(broken)) return new int[0];
            List<int> anchors = new List<int>(broken.Length);
            for (int i = 0; i < broken.Length; i++)
            {
                int cp;
                if (char.IsHighSurrogate(broken[i]) && i + 1 < broken.Length && char.IsLowSurrogate(broken[i + 1]))
                {
                    cp = char.ConvertToUtf32(broken[i], broken[i + 1]);
                    i++;
                }
                else
                {
                    cp = broken[i];
                }
                if (cp != FFFD) anchors.Add(cp);
            }
            return anchors.ToArray();
        }

        private static bool IsSubsequenceMatch(string candidate, int[] anchors)
        {
            int ci = 0;
            int aIdx = 0;
            while (aIdx < anchors.Length && ci < candidate.Length)
            {
                int cp;
                int step;
                if (char.IsHighSurrogate(candidate[ci]) && ci + 1 < candidate.Length && char.IsLowSurrogate(candidate[ci + 1]))
                {
                    cp = char.ConvertToUtf32(candidate[ci], candidate[ci + 1]);
                    step = 2;
                }
                else
                {
                    cp = candidate[ci];
                    step = 1;
                }

                if (cp == anchors[aIdx]) aIdx++;
                ci += step;
            }
            return aIdx == anchors.Length;
        }

        // 内部排序辅助
        private class RankedCandidate
        {
            public readonly string Value;
            public readonly int Diff;
            public readonly RepairCandidateSource Source;

            public RankedCandidate(string value, int diff, RepairCandidateSource source)
            {
                Value = value;
                Diff = diff;
                Source = source;
            }

            public static int Compare(RankedCandidate a, RankedCandidate b)
            {
                int d = a.Diff - b.Diff;
                if (d != 0) return d;
                return string.Compare(a.Value, b.Value, StringComparison.Ordinal);
            }
        }
    }
}
