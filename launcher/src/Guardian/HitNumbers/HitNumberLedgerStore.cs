using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.HitNumbers
{
    /// <summary>
    /// 场景级精确伤害对账环。世界飘字寿命与本日志完全解耦；日志只在玩家打开
    /// Web 设置中的对账窗口时物化分组和 JSON，因此高频战斗热路径只有 O(1) 引用写入。
    /// 固定容量避免重新引入“累计游玩越久越慢”，溢出量会在 UI 中明确披露。
    /// </summary>
    internal sealed class HitNumberLedgerStore
    {
        internal const int Capacity = 32768;

        private readonly HitNumberSegment[] _segments = new HitNumberSegment[Capacity];
        private int _start;
        private int _count;
        private long _droppedSegmentCount;
        private int _generation;

        internal int CountForTests => _count;
        internal long DroppedSegmentCountForTests => _droppedSegmentCount;

        internal void AddRange(
            IReadOnlyList<HitNumberSegment> source,
            int startIndex,
            int count)
        {
            if (source == null) throw new ArgumentNullException(nameof(source));
            if (startIndex < 0 || count < 0 || startIndex + count > source.Count)
                throw new ArgumentOutOfRangeException(nameof(startIndex));

            for (int i = 0; i < count; i++) Add(source[startIndex + i]);
        }

        internal void Reset()
        {
            if (_count > 0)
                Array.Clear(_segments, 0, _segments.Length);
            _start = 0;
            _count = 0;
            _droppedSegmentCount = 0;
            _generation++;
        }

        internal JObject BuildPage(double nowSeconds, int offset, int limit)
        {
            if (offset < 0) throw new ArgumentOutOfRangeException(nameof(offset));
            if (limit <= 0 || limit > 100) throw new ArgumentOutOfRangeException(nameof(limit));

            var ordered = new List<LedgerBurstBuilder>();
            var byIdentity = new Dictionary<LedgerIdentity, LedgerBurstBuilder>();
            for (int newestIndex = 0; newestIndex < _count; newestIndex++)
            {
                HitNumberSegment segment = GetNewest(newestIndex);
                var identity = new LedgerIdentity(segment);
                if (!byIdentity.TryGetValue(identity, out LedgerBurstBuilder burst))
                {
                    burst = new LedgerBurstBuilder(segment);
                    byIdentity.Add(identity, burst);
                    ordered.Add(burst);
                }
                burst.AddNewestFirst(segment);
            }

            int pageCount = Math.Max(0, Math.Min(limit, ordered.Count - Math.Min(offset, ordered.Count)));
            var bursts = new JArray();
            for (int i = 0; i < pageCount; i++)
                bursts.Add(ordered[offset + i].ToJson(nowSeconds));

            return new JObject
            {
                ["v"] = 1,
                ["generation"] = _generation,
                ["capacity"] = Capacity,
                ["retainedSegments"] = _count,
                ["droppedSegments"] = _droppedSegmentCount,
                ["oldestBurstMayBePartial"] = _droppedSegmentCount > 0,
                ["totalBursts"] = ordered.Count,
                ["offset"] = Math.Min(offset, ordered.Count),
                ["limit"] = limit,
                ["hasNewer"] = offset > 0,
                ["hasOlder"] = offset + pageCount < ordered.Count,
                ["bursts"] = bursts
            };
        }

        private void Add(HitNumberSegment segment)
        {
            if (segment == null) return;
            if (_count < Capacity)
            {
                _segments[(_start + _count) % Capacity] = segment;
                _count++;
                return;
            }

            _segments[_start] = segment;
            _start = (_start + 1) % Capacity;
            _droppedSegmentCount++;
        }

        private HitNumberSegment GetNewest(int newestIndex)
        {
            int logicalIndex = _count - 1 - newestIndex;
            return _segments[(_start + logicalIndex) % Capacity];
        }

        private readonly struct LedgerIdentity : IEquatable<LedgerIdentity>
        {
            internal LedgerIdentity(HitNumberSegment segment)
            {
                TargetId = segment.TargetId ?? string.Empty;
                BurstId = segment.BurstId ?? string.Empty;
                SyntheticSequence = BurstId.Length == 0 ? segment.Sequence : -1;
            }

            private string TargetId { get; }
            private string BurstId { get; }
            private int SyntheticSequence { get; }

            public bool Equals(LedgerIdentity other)
            {
                return SyntheticSequence == other.SyntheticSequence
                    && string.Equals(TargetId, other.TargetId, StringComparison.Ordinal)
                    && string.Equals(BurstId, other.BurstId, StringComparison.Ordinal);
            }

            public override bool Equals(object value)
            {
                return value is LedgerIdentity other && Equals(other);
            }

            public override int GetHashCode()
            {
                unchecked
                {
                    int hash = StringComparer.Ordinal.GetHashCode(TargetId);
                    hash = hash * 397 ^ StringComparer.Ordinal.GetHashCode(BurstId);
                    return hash * 397 ^ SyntheticSequence;
                }
            }
        }

        private sealed class LedgerBurstBuilder
        {
            private readonly List<HitNumberSegment> _newestFirst =
                new List<HitNumberSegment>();
            private long _totalDamage;
            private int _expectedHitCount;
            private double _lastArrivalSeconds;

            internal LedgerBurstBuilder(HitNumberSegment first)
            {
                TargetId = first.TargetId ?? string.Empty;
                BurstId = first.BurstId ?? string.Empty;
                _expectedHitCount = Math.Max(1, first.ExpectedBurstHitCount);
                _lastArrivalSeconds = first.ArrivalSeconds;
            }

            private string TargetId { get; }
            private string BurstId { get; }

            internal void AddNewestFirst(HitNumberSegment segment)
            {
                _newestFirst.Add(segment);
                _totalDamage = SaturatingAdd(_totalDamage, segment.Damage);
                _expectedHitCount = Math.Max(
                    _expectedHitCount,
                    Math.Max(_newestFirst.Count, segment.ExpectedBurstHitCount));
                _lastArrivalSeconds = Math.Max(_lastArrivalSeconds, segment.ArrivalSeconds);
            }

            internal JObject ToJson(double nowSeconds)
            {
                var segments = new JArray();
                for (int i = _newestFirst.Count - 1; i >= 0; i--)
                {
                    HitNumberSegment segment = _newestFirst[i];
                    segments.Add(new JObject
                    {
                        ["sequence"] = segment.Sequence,
                        ["damage"] = segment.Damage,
                        ["packed"] = segment.Packed,
                        ["effectText"] = segment.EffectText ?? string.Empty,
                        ["effectEmoji"] = segment.EffectEmoji ?? string.Empty,
                        ["lifeSteal"] = segment.LifeSteal,
                        ["shieldAbsorb"] = segment.ShieldAbsorb,
                        ["x"] = segment.TargetX,
                        ["y"] = segment.TargetY
                    });
                }

                return new JObject
                {
                    ["targetId"] = TargetId,
                    ["burstId"] = BurstId,
                    ["totalDamage"] = _totalDamage,
                    ["hitCount"] = _newestFirst.Count,
                    ["expectedHitCount"] = _expectedHitCount,
                    ["ageMs"] = Math.Max(0L, (long)Math.Round(
                        (nowSeconds - _lastArrivalSeconds) * 1000.0)),
                    ["segments"] = segments
                };
            }

            private static long SaturatingAdd(long left, int right)
            {
                if (right > 0 && left > long.MaxValue - right) return long.MaxValue;
                if (right < 0 && left < long.MinValue - right) return long.MinValue;
                return left + right;
            }
        }
    }
}
