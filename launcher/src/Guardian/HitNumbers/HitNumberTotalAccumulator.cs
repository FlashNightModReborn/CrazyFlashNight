using System;
using System.Collections.Generic;
using System.Drawing;

namespace CF7Launcher.Guardian.HitNumbers
{
    /// <summary>
    /// “总伤”兼容模式的每目标标量状态。它不保存逐段数组；精确逐段由独立有界
    /// LedgerStore 承担，因此持续连射只增长数值而不会增长对象图。
    /// </summary>
    internal sealed class HitNumberTotalAccumulator
    {
        internal const double QuietSeconds = 1.25;
        internal const double FadeSeconds = 0.36;
        internal const double LifetimeSeconds = QuietSeconds + FadeSeconds;

        private readonly Dictionary<string, HitNumberTotalEntry> _byTarget =
            new Dictionary<string, HitNumberTotalEntry>(StringComparer.Ordinal);
        private readonly List<string> _expiredKeys = new List<string>();

        internal int ActiveTargetCountForTests => _byTarget.Count;

        internal void AddRange(
            IReadOnlyList<HitNumberSegment> source,
            int startIndex,
            int count)
        {
            if (source == null) throw new ArgumentNullException(nameof(source));
            if (startIndex < 0 || count < 0 || startIndex + count > source.Count)
                throw new ArgumentOutOfRangeException(nameof(startIndex));

            if (count == 0) return;
            double newestArrivalSeconds = source[startIndex].ArrivalSeconds;
            for (int i = 1; i < count; i++)
            {
                newestArrivalSeconds = Math.Max(
                    newestArrivalSeconds,
                    source[startIndex + i].ArrivalSeconds);
            }
            // Total 状态会在所有显示模式下同步维护，方便设置切换后直接重排。
            // 因此不能只在 Total 的 Snapshot() 中清理，否则长期使用 balanced/detail/
            // classic 并持续更换目标时，字典会按历史目标数累积。
            Prune(newestArrivalSeconds);

            for (int i = 0; i < count; i++) Add(source[startIndex + i]);
        }

        internal List<HitNumberTotalEntry> Snapshot(double nowSeconds)
        {
            Prune(nowSeconds);
            var result = new List<HitNumberTotalEntry>(_byTarget.Count);
            foreach (HitNumberTotalEntry entry in _byTarget.Values)
            {
                entry.AdvanceVisual(nowSeconds);
                result.Add(entry);
            }
            return result;
        }

        internal void Clear()
        {
            _byTarget.Clear();
            _expiredKeys.Clear();
        }

        private void Add(HitNumberSegment segment)
        {
            if (segment == null) return;
            // 旧总伤聚合器从不让 MISS 建立或刷新累计项；精确逐段事实仍已进入
            // LedgerStore，因此这里只恢复其视觉语义，不丢失对账信息。
            if (HitNumberPacking.IsMiss(segment.Packed)) return;
            string targetId = string.IsNullOrEmpty(segment.TargetId)
                ? "@" + segment.TargetX.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                    + ":" + segment.TargetY.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)
                : segment.TargetId;
            if (!_byTarget.TryGetValue(targetId, out HitNumberTotalEntry entry)
                || segment.ArrivalSeconds - entry.LastArrivalSeconds >= LifetimeSeconds)
            {
                entry = new HitNumberTotalEntry(targetId, segment);
                _byTarget[targetId] = entry;
            }
            entry.Add(segment);
        }

        private void Prune(double nowSeconds)
        {
            _expiredKeys.Clear();
            foreach (KeyValuePair<string, HitNumberTotalEntry> pair in _byTarget)
            {
                if (nowSeconds - pair.Value.LastArrivalSeconds >= LifetimeSeconds)
                    _expiredKeys.Add(pair.Key);
            }
            for (int i = 0; i < _expiredKeys.Count; i++)
                _byTarget.Remove(_expiredKeys[i]);
        }
    }

    internal sealed class HitNumberTotalEntry
    {
        private const int EffectFlagCount = 9;
        private const int ColorCount = 11;
        private const int VirtualFramesPerSecond = 24;
        private const int CounterCatchupFrames = 8;
        private const float FlagDecayStep = 0.05f;
        private const float FlagVisibilityFloor = 0.10f;
        private const float FlagVisibilityCeiling = 0.50f;
        private const float ColorDecayRatio = 0.15f;
        private const int ExecuteFlagBit = 2;

        private readonly long[] _effectFlagDamageSums = new long[EffectFlagCount];
        private readonly float[] _displayFlagScales = new float[EffectFlagCount];
        private readonly long[] _colorDamageSums = new long[ColorCount];
        private int _maximumSegmentDamage = int.MinValue;
        private int _effectFlags;
        private int _representativePacked;
        private float _displayR;
        private float _displayG;
        private float _displayB;
        private int _effectTextColorId;
        private double _lastVisualUpdateSeconds;
        private double _virtualFrameCarry;
        private string _flagScales = "000000000";

        internal HitNumberTotalEntry(string targetId, HitNumberSegment first)
        {
            TargetId = targetId ?? string.Empty;
            FirstSequence = first.Sequence;
            FirstArrivalSeconds = first.ArrivalSeconds;
            LastArrivalSeconds = first.ArrivalSeconds;
            _lastVisualUpdateSeconds = first.ArrivalSeconds;
            TargetX = first.TargetX;
            TargetY = first.TargetY;
        }

        internal string TargetId { get; }
        internal float TargetX { get; private set; }
        internal float TargetY { get; private set; }
        internal long TotalDamage { get; private set; }
        internal long DisplayDamage { get; private set; }
        internal int HitCount { get; private set; }
        internal int DisplayHitCount { get; private set; }
        internal int ExpectedHitCount { get; private set; }
        internal int FirstSequence { get; }
        internal double FirstArrivalSeconds { get; }
        internal double LastArrivalSeconds { get; private set; }
        internal string EffectText { get; private set; } = string.Empty;
        internal string CrushText { get; private set; } = string.Empty;
        internal string CrushEmoji { get; private set; } = string.Empty;
        internal float LifeSteal { get; private set; }
        internal float ShieldAbsorb { get; private set; }
        internal byte DisplayR => ToByte(_displayR);
        internal byte DisplayG => ToByte(_displayG);
        internal byte DisplayB => ToByte(_displayB);
        internal int DominantColorId => ResolveDominantColorId();
        internal int EffectTextColorId => _effectTextColorId;
        internal string FlagScales => _flagScales;

        internal int Packed
        {
            get
            {
                int packed = (_representativePacked & ~1023) | (_effectFlags & 511);
                return packed & ~(1 << 9);
            }
        }

        internal void Add(HitNumberSegment segment)
        {
            if (segment == null || HitNumberPacking.IsMiss(segment.Packed)) return;
            bool firstHit = HitCount == 0;
            if (!firstHit) AdvanceVisual(segment.ArrivalSeconds);

            TotalDamage = SaturatingAdd(TotalDamage, segment.Damage);
            if (HitCount < int.MaxValue) HitCount++;
            ExpectedHitCount = Math.Max(
                ExpectedHitCount,
                Math.Max(HitCount, segment.ExpectedBurstHitCount));
            int newFlags = HitNumberPacking.Flags(segment.Packed);
            _effectFlags |= newFlags;
            for (int bit = 0; bit < EffectFlagCount; bit++)
            {
                if ((newFlags & (1 << bit)) == 0) continue;
                _effectFlagDamageSums[bit] = SaturatingAdd(
                    _effectFlagDamageSums[bit],
                    segment.Damage);
                _displayFlagScales[bit] = 1f;
            }

            if (segment.Damage > _maximumSegmentDamage)
            {
                _maximumSegmentDamage = segment.Damage;
                _representativePacked = segment.Packed;
            }

            int colorId = (segment.Packed >> 18) & 15;
            ResolveColor(colorId, out byte r, out byte g, out byte b);
            _displayR = r;
            _displayG = g;
            _displayB = b;
            if (colorId >= 0 && colorId < ColorCount)
                _colorDamageSums[colorId] = SaturatingAdd(
                    _colorDamageSums[colorId],
                    segment.Damage);

            string effectText = string.IsNullOrWhiteSpace(segment.EffectText)
                ? string.Empty
                : segment.EffectText.Trim();
            if ((newFlags & 8) != 0 && effectText.Length > 0)
            {
                EffectText = effectText;
                _effectTextColorId = colorId;
            }
            if ((newFlags & 16) != 0)
            {
                CrushText = effectText.Length == 0 ? "粉" : effectText;
                CrushEmoji = string.IsNullOrWhiteSpace(segment.EffectEmoji)
                    ? string.Empty
                    : segment.EffectEmoji.Trim();
            }
            if (segment.LifeSteal > 0)
                LifeSteal = SaturatingFloatAdd(LifeSteal, segment.LifeSteal);
            if (segment.ShieldAbsorb > 0)
                ShieldAbsorb = SaturatingFloatAdd(ShieldAbsorb, segment.ShieldAbsorb);
            TargetX = segment.TargetX;
            TargetY = segment.TargetY;
            LastArrivalSeconds = Math.Max(LastArrivalSeconds, segment.ArrivalSeconds);

            if (firstHit)
            {
                DisplayDamage = TotalDamage;
                DisplayHitCount = HitCount;
                _effectTextColorId = colorId;
            }
            RefreshFlagScales();
        }

        internal void AdvanceVisual(double nowSeconds)
        {
            if (HitCount == 0 || nowSeconds <= _lastVisualUpdateSeconds) return;
            double elapsed = nowSeconds - _lastVisualUpdateSeconds;
            _lastVisualUpdateSeconds = nowSeconds;
            double virtualFrames = _virtualFrameCarry + elapsed * VirtualFramesPerSecond;
            int wholeFrames = (int)Math.Min(64.0, Math.Floor(virtualFrames + 1e-9));
            _virtualFrameCarry = virtualFrames - wholeFrames;
            if (wholeFrames <= 0) return;

            for (int frame = 0; frame < wholeFrames; frame++)
            {
                AdvanceCounters();
                AdvanceEffectFlags();
                AdvanceColor();
            }
            RefreshFlagScales();
        }

        private void AdvanceCounters()
        {
            if (DisplayHitCount < HitCount)
            {
                int delta = HitCount - DisplayHitCount;
                int rate = Math.Max(1, (delta + CounterCatchupFrames - 1)
                    / CounterCatchupFrames);
                DisplayHitCount = Math.Min(HitCount, DisplayHitCount + rate);
            }
            if (DisplayDamage < TotalDamage)
            {
                long delta = TotalDamage - DisplayDamage;
                long rate = delta / CounterCatchupFrames;
                if (delta % CounterCatchupFrames != 0) rate++;
                DisplayDamage = Math.Min(TotalDamage, DisplayDamage + Math.Max(1L, rate));
            }
        }

        private void AdvanceEffectFlags()
        {
            if (TotalDamage <= 0) return;
            for (int bit = 0; bit < EffectFlagCount; bit++)
            {
                float target;
                if (bit == ExecuteFlagBit)
                {
                    target = _effectFlagDamageSums[bit] > 0 ? 1f : 0f;
                }
                else
                {
                    double ratio = _effectFlagDamageSums[bit] / (double)TotalDamage;
                    if (ratio < FlagVisibilityFloor) target = 0f;
                    else if (ratio >= FlagVisibilityCeiling) target = 1f;
                    else target = (float)((ratio - FlagVisibilityFloor)
                        / (FlagVisibilityCeiling - FlagVisibilityFloor));
                }
                float current = _displayFlagScales[bit];
                if (current < target)
                    current = Math.Min(target, current + FlagDecayStep);
                else if (current > target)
                    current = Math.Max(target, current - FlagDecayStep);
                _displayFlagScales[bit] = current;
            }
        }

        private void AdvanceColor()
        {
            // 旧总伤协议仅在累计伤害为正时做贡献色回落；0/负值沿用代表段
            // packed 的来源色。否则 colorDamageSums 全为 0 时会错误地逐帧漂白。
            if (TotalDamage <= 0)
            {
                ResolveColor(
                    (_representativePacked >> 18) & 15,
                    out byte sourceR,
                    out byte sourceG,
                    out byte sourceB);
                _displayR = sourceR;
                _displayG = sourceG;
                _displayB = sourceB;
                return;
            }
            ResolveColor(ResolveDominantColorId(), out byte r, out byte g, out byte b);
            _displayR += (r - _displayR) * ColorDecayRatio;
            _displayG += (g - _displayG) * ColorDecayRatio;
            _displayB += (b - _displayB) * ColorDecayRatio;
        }

        private int ResolveDominantColorId()
        {
            long bestDamage = 0;
            int dominant = 0;
            for (int colorId = 0; colorId < ColorCount; colorId++)
            {
                if (_colorDamageSums[colorId] <= bestDamage) continue;
                bestDamage = _colorDamageSums[colorId];
                dominant = colorId;
            }
            return dominant;
        }

        private void RefreshFlagScales()
        {
            Span<char> encoded = stackalloc char[EffectFlagCount];
            for (int bit = 0; bit < EffectFlagCount; bit++)
            {
                float scale = _displayFlagScales[bit];
                int level = scale < 0.02f
                    ? 0
                    : (int)Math.Floor(scale * 9f + 0.5f);
                encoded[bit] = (char)('0' + Math.Max(0, Math.Min(9, level)));
            }
            if (_flagScales.AsSpan().SequenceEqual(encoded)) return;
            _flagScales = new string(encoded);
        }

        private static void ResolveColor(
            int colorId,
            out byte red,
            out byte green,
            out byte blue)
        {
            Color color = HitNumberPainter.ResolveColorId(colorId);
            red = color.R;
            green = color.G;
            blue = color.B;
        }

        private static byte ToByte(float value)
        {
            return (byte)Math.Max(0, Math.Min(255, (int)Math.Floor(value + 0.5f)));
        }

        private static long SaturatingAdd(long left, int right)
        {
            if (right > 0 && left > long.MaxValue - right) return long.MaxValue;
            if (right < 0 && left < long.MinValue - right) return long.MinValue;
            return left + right;
        }

        private static float SaturatingFloatAdd(float left, float right)
        {
            double sum = (double)left + right;
            if (double.IsNaN(sum)) return left;
            if (sum >= float.MaxValue) return float.MaxValue;
            if (sum <= float.MinValue) return float.MinValue;
            return (float)sum;
        }
    }
}
