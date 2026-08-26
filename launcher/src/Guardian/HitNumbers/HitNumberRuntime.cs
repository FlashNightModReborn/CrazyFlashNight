using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal enum HitNumberDisplayMode
    {
        Off,
        Balanced,
        Detail,
        Classic,
        Total
    }

    internal readonly struct HitNumberRuntimeOptions
    {
        internal HitNumberRuntimeOptions(HitNumberDisplayMode mode, int worldRowLimit)
        {
            if (worldRowLimit < 0) throw new ArgumentOutOfRangeException(nameof(worldRowLimit));
            Mode = mode;
            WorldRowLimit = worldRowLimit;
        }

        internal HitNumberDisplayMode Mode { get; }
        internal int WorldRowLimit { get; }
        internal bool SourceEnabled => Mode != HitNumberDisplayMode.Off;

        internal static HitNumberRuntimeOptions FromPreferences(string mode, int worldRowLimit)
        {
            HitNumberDisplayMode parsed = string.Equals(mode, "off", StringComparison.Ordinal)
                ? HitNumberDisplayMode.Off
                : string.Equals(mode, "detail", StringComparison.Ordinal)
                    ? HitNumberDisplayMode.Detail
                    : string.Equals(mode, "classic", StringComparison.Ordinal)
                        ? HitNumberDisplayMode.Classic
                        : string.Equals(mode, "total", StringComparison.Ordinal)
                            ? HitNumberDisplayMode.Total
                            : HitNumberDisplayMode.Balanced;
            return new HitNumberRuntimeOptions(parsed, Math.Max(0, worldRowLimit));
        }
    }

    internal sealed class HitNumberRuntimeSnapshot
    {
        internal HitNumberRuntimeSnapshot(
            int generation,
            HitNumberDisplayMode mode,
            HitNumberLayoutFrame frame,
            bool isReset = false)
        {
            Generation = generation;
            Mode = mode;
            Frame = frame;
            IsReset = isReset;
        }

        internal int Generation { get; }
        internal HitNumberDisplayMode Mode { get; }
        internal HitNumberLayoutFrame Frame { get; }
        internal bool IsReset { get; }
        internal bool IsDismiss => Frame == null && !IsReset;
    }

    /// <summary>
    /// C# 伤害数字的唯一运行态 reducer。世界事件只保留自然显示寿命，不按历史总命中数
    /// 增长；精确逐段对账另存于固定容量场景环，并且只在设置页请求时物化 JSON。
    /// 调用方负责串行化 ProcessFrame/Configure/Reset/BuildLedgerPage。
    /// </summary>
    internal sealed class HitNumberRuntime
    {
        private const int CompactHeadThreshold = 4096;
        internal const int MaximumExpectedBurstHitCount = 4096;

        private readonly Func<double> _clock;
        private readonly HitNumberBatchParser _batchParser = new HitNumberBatchParser();
        private readonly List<HitNumberSegment> _segments = new List<HitNumberSegment>(256);
        private readonly HitNumberLedgerStore _ledger = new HitNumberLedgerStore();
        private readonly HitNumberTotalAccumulator _totals = new HitNumberTotalAccumulator();
        private HitNumberRuntimeOptions _options = new HitNumberRuntimeOptions(
            HitNumberDisplayMode.Balanced,
            24);
        private HitNumberCamera _camera = HitNumberCamera.Identity;
        private int _head;
        private int _nextSequence;
        private int _generation;
        private bool _hasPublishedVisuals;

        internal HitNumberRuntime()
            : this(delegate { return Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency; })
        {
        }

        internal HitNumberRuntime(Func<double> clock)
        {
            _clock = clock ?? throw new ArgumentNullException(nameof(clock));
        }

        internal HitNumberRuntimeOptions Options => _options;
        internal int StoredSegmentCountForTests => _segments.Count - _head;
        internal int BackingSegmentCountForTests => _segments.Count;
        internal int LedgerSegmentCountForTests => _ledger.CountForTests;
        internal long LedgerDroppedSegmentCountForTests => _ledger.DroppedSegmentCountForTests;
        internal int TotalTargetCountForTests => _totals.ActiveTargetCountForTests;
        internal HitNumberCamera CameraForTests => _camera;

        internal HitNumberRuntimeSnapshot Configure(HitNumberRuntimeOptions options)
        {
            bool configurationChanged =
                _options.Mode != options.Mode ||
                _options.WorldRowLimit != options.WorldRowLimit;
            _options = options;
            if (configurationChanged) _generation++;
            if (!options.SourceEnabled)
            {
                ClearEvents();
                _totals.Clear();
                _hasPublishedVisuals = false;
                return new HitNumberRuntimeSnapshot(
                    _generation,
                    HitNumberDisplayMode.Off,
                    null,
                    true);
            }
            return BuildSnapshot(_clock());
        }

        internal HitNumberRuntimeSnapshot ProcessFrame(
            string cameraPayload,
            string hitPayload)
        {
            double now = _clock();
            if (!string.IsNullOrEmpty(cameraPayload) &&
                HitNumberBatchParser.TryParseCamera(cameraPayload, out HitNumberCamera camera))
            {
                _camera = camera;
            }

            if (!_options.SourceEnabled) return null;

            if (!string.IsNullOrEmpty(hitPayload))
            {
                int firstNewSegment = _segments.Count;
                int accepted = _batchParser.ParseBatch(
                    hitPayload,
                    now,
                    _segments,
                    ref _nextSequence);
                if (accepted > 0)
                {
                    _ledger.AddRange(_segments, firstNewSegment, accepted);
                    _totals.AddRange(_segments, firstNewSegment, accepted);
                }
            }

            PruneExpired(now);
            return BuildSnapshot(now);
        }

        internal HitNumberRuntimeSnapshot Reset()
        {
            ClearEvents();
            _totals.Clear();
            _ledger.Reset();
            _generation++;
            _hasPublishedVisuals = false;
            return new HitNumberRuntimeSnapshot(
                _generation,
                _options.Mode,
                null,
                true);
        }

        private HitNumberRuntimeSnapshot BuildSnapshot(double now)
        {
            PruneExpired(now);
            if (_options.Mode == HitNumberDisplayMode.Total)
            {
                HitNumberLayoutFrame totalFrame = HitNumberLayoutEngine.BuildTotalFrame(
                    _totals.Snapshot(now),
                    now,
                    _camera,
                    _options.WorldRowLimit);
                if (totalFrame.WorldRows.Count == 0)
                    return TakeDismissSnapshotIfNeeded();
                _hasPublishedVisuals = true;
                return new HitNumberRuntimeSnapshot(_generation, _options.Mode, totalFrame);
            }

            if (_head == _segments.Count) return TakeDismissSnapshotIfNeeded();

            HitNumberLayoutCandidate candidate =
                _options.Mode == HitNumberDisplayMode.Detail
                    ? HitNumberLayoutCandidate.FixedBurstStack
                    : _options.Mode == HitNumberDisplayMode.Classic
                        ? HitNumberLayoutCandidate.ClassicScatter
                        : HitNumberLayoutCandidate.BalancedSummary;
            double lifetime = _options.Mode == HitNumberDisplayMode.Classic
                ? HitNumberLayoutEngine.ClassicLifetimeSeconds
                : HitNumberLayoutEngine.DefaultLifetimeSeconds;
            HitNumberLayoutFrame frame = HitNumberLayoutEngine.BuildFrame(
                _segments,
                _head,
                now,
                candidate,
                _camera,
                _options.WorldRowLimit,
                lifetime,
                false);
            bool hasVisuals = frame.WorldRows.Count > 0;
            if (!hasVisuals) return TakeDismissSnapshotIfNeeded();
            _hasPublishedVisuals = true;
            return new HitNumberRuntimeSnapshot(_generation, _options.Mode, frame);
        }

        internal JObject BuildLedgerPage(int offset, int limit)
        {
            return _ledger.BuildPage(_clock(), offset, limit);
        }

        private HitNumberRuntimeSnapshot TakeDismissSnapshotIfNeeded()
        {
            if (!_hasPublishedVisuals) return null;
            _hasPublishedVisuals = false;
            return new HitNumberRuntimeSnapshot(_generation, _options.Mode, null);
        }

        private void PruneExpired(double now)
        {
            double oldestAllowed = now - HitNumberLayoutEngine.DefaultLifetimeSeconds;
            while (_head < _segments.Count &&
                _segments[_head].ArrivalSeconds <= oldestAllowed)
            {
                _head++;
            }

            if (_head == _segments.Count)
            {
                ClearEvents();
                return;
            }
            if (_head >= CompactHeadThreshold && (long)_head * 2L >= _segments.Count)
            {
                _segments.RemoveRange(0, _head);
                _head = 0;
            }
        }

        private void ClearEvents()
        {
            _segments.Clear();
            _head = 0;
            if (_nextSequence == int.MaxValue) _nextSequence = 0;
        }
    }

    /// <summary>
    /// AS2 hn 快车道解析器。字段扫描使用 span，批内字符串去重表每批清空，既避免
    /// Split 数组和重复 unit/burst 字符串，也不建立会随历史目标持续增长的全局别名表。
    /// </summary>
    internal sealed class HitNumberBatchParser
    {
        private const int FieldCount = 11;
        private readonly Dictionary<string, string> _batchStrings =
            new Dictionary<string, string>(StringComparer.Ordinal);

        internal int RejectedEntryCount { get; private set; }

        internal int ParseBatch(
            string payload,
            double arrivalSeconds,
            List<HitNumberSegment> destination,
            ref int nextSequence)
        {
            if (destination == null) throw new ArgumentNullException(nameof(destination));
            if (string.IsNullOrEmpty(payload)) return 0;

            _batchStrings.Clear();
            int accepted = 0;
            ReadOnlySpan<char> source = payload.AsSpan();
            int entryStart = 0;
            for (int i = 0; i <= source.Length; i++)
            {
                if (i != source.Length && source[i] != ';') continue;
                ReadOnlySpan<char> entry = source.Slice(entryStart, i - entryStart);
                if (TryParseEntry(entry, arrivalSeconds, nextSequence, out HitNumberSegment segment))
                {
                    destination.Add(segment);
                    accepted++;
                    if (nextSequence == int.MaxValue) nextSequence = int.MinValue;
                    else nextSequence++;
                }
                else if (!entry.IsEmpty)
                {
                    RejectedEntryCount++;
                }
                entryStart = i + 1;
            }
            _batchStrings.Clear();
            return accepted;
        }

        internal static bool TryParseCamera(string payload, out HitNumberCamera camera)
        {
            camera = HitNumberCamera.Identity;
            if (string.IsNullOrEmpty(payload)) return false;
            ReadOnlySpan<char> source = payload.AsSpan();
            Span<int> bounds = stackalloc int[6];
            if (SplitFields(source, '|', bounds) != 3 ||
                !TryFiniteFloat(Field(source, bounds, 0), out float x) ||
                !TryFiniteFloat(Field(source, bounds, 1), out float y) ||
                !TryFiniteFloat(Field(source, bounds, 2), out float scale) ||
                scale <= 0f || scale > 20f)
            {
                return false;
            }
            camera = new HitNumberCamera(x, y, scale);
            return true;
        }

        private bool TryParseEntry(
            ReadOnlySpan<char> entry,
            double arrivalSeconds,
            int sequence,
            out HitNumberSegment segment)
        {
            segment = null;
            Span<int> bounds = stackalloc int[FieldCount * 2];
            if (SplitFields(entry, '|', bounds) != FieldCount ||
                !TryFiniteDouble(Field(entry, bounds, 0), out double damageValue) ||
                !TryFiniteFloat(Field(entry, bounds, 1), out float worldX) ||
                !TryFiniteFloat(Field(entry, bounds, 2), out float worldY) ||
                !TryFiniteDouble(Field(entry, bounds, 3), out double packedValue) ||
                !TryFiniteFloat(Field(entry, bounds, 6), out float lifeSteal) ||
                !TryFiniteFloat(Field(entry, bounds, 7), out float shieldAbsorb) ||
                !int.TryParse(
                    Field(entry, bounds, 10),
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out int expectedHitCount) ||
                expectedHitCount <= 0)
            {
                return false;
            }

            // expectedHitCount 只用于 Burst 行的预留几何，不是事件接纳上限。
            // 异常大的元数据应钳位布局提示，而不能在“无限制/全部计数”模式下
            // 连同真实伤害段一起丢弃。
            expectedHitCount = Math.Min(
                expectedHitCount,
                HitNumberRuntime.MaximumExpectedBurstHitCount);

            segment = new HitNumberSegment
            {
                Sequence = sequence,
                TargetX = worldX,
                TargetY = worldY,
                ArrivalSeconds = arrivalSeconds,
                Damage = SaturatingInt(damageValue),
                Packed = SaturatingInt(packedValue),
                EffectText = Canonical(Field(entry, bounds, 4)),
                EffectEmoji = Canonical(Field(entry, bounds, 5)),
                LifeSteal = lifeSteal,
                ShieldAbsorb = shieldAbsorb,
                TargetId = Canonical(Field(entry, bounds, 8)),
                BurstId = Canonical(Field(entry, bounds, 9)),
                ExpectedBurstHitCount = expectedHitCount
            };
            return !string.IsNullOrEmpty(segment.BurstId);
        }

        private string Canonical(ReadOnlySpan<char> value)
        {
            if (value.IsEmpty) return string.Empty;
            string candidate = value.ToString();
            if (_batchStrings.TryGetValue(candidate, out string existing)) return existing;
            _batchStrings.Add(candidate, candidate);
            return candidate;
        }

        private static int SaturatingInt(double value)
        {
            if (value >= int.MaxValue) return int.MaxValue;
            if (value <= int.MinValue) return int.MinValue;
            return (int)value;
        }

        private static int SplitFields(ReadOnlySpan<char> source, char separator, Span<int> bounds)
        {
            int count = 0;
            int start = 0;
            for (int i = 0; i <= source.Length; i++)
            {
                if (i != source.Length && source[i] != separator) continue;
                if (count >= bounds.Length / 2) return count + 1;
                bounds[count * 2] = start;
                bounds[count * 2 + 1] = i - start;
                count++;
                start = i + 1;
            }
            return count;
        }

        private static ReadOnlySpan<char> Field(
            ReadOnlySpan<char> source,
            Span<int> bounds,
            int index)
        {
            return source.Slice(bounds[index * 2], bounds[index * 2 + 1]);
        }

        private static bool TryFiniteFloat(ReadOnlySpan<char> value, out float parsed)
        {
            return float.TryParse(
                    value,
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out parsed) &&
                !float.IsNaN(parsed) &&
                !float.IsInfinity(parsed);
        }

        private static bool TryFiniteDouble(ReadOnlySpan<char> value, out double parsed)
        {
            return double.TryParse(
                    value,
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out parsed) &&
                !double.IsNaN(parsed) &&
                !double.IsInfinity(parsed);
        }
    }
}
