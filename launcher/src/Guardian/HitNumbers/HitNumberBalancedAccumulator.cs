using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal readonly struct BalancedLaneKey : IEquatable<BalancedLaneKey>
    {
        internal BalancedLaneKey(
            bool isMiss,
            int colorId,
            bool isCrush,
            bool hasExecute,
            string effectKey)
        {
            IsMiss = isMiss;
            ColorId = isMiss ? 0 : colorId;
            IsCrush = !isMiss && isCrush;
            HasExecute = !isMiss && hasExecute;
            EffectKey = isMiss ? string.Empty : (effectKey ?? string.Empty);
        }

        internal bool IsMiss { get; }
        internal int ColorId { get; }
        internal bool IsCrush { get; }
        internal bool HasExecute { get; }
        internal string EffectKey { get; }

        internal string ToLaneId()
        {
            if (IsMiss) return "#lane:miss";
            return "#lane:" + ColorId.ToString(CultureInfo.InvariantCulture)
                + (IsCrush ? ":P:" : ":")
                + EffectKey
                + (HasExecute ? ":X" : string.Empty);
        }

        public bool Equals(BalancedLaneKey other)
        {
            return IsMiss == other.IsMiss
                && ColorId == other.ColorId
                && IsCrush == other.IsCrush
                && HasExecute == other.HasExecute
                && string.Equals(EffectKey, other.EffectKey, StringComparison.Ordinal);
        }

        public override bool Equals(object value) => value is BalancedLaneKey other && Equals(other);

        public override int GetHashCode()
        {
            unchecked
            {
                int hash = IsMiss ? 17 : 31;
                hash = hash * 397 ^ ColorId;
                hash = hash * 397 ^ (IsCrush ? 1 : 0);
                hash = hash * 397 ^ (HasExecute ? 2 : 0);
                return hash * 397 ^ StringComparer.Ordinal.GetHashCode(EffectKey);
            }
        }
    }

    /// <summary>
    /// 候选 B1“平衡 · 语义分轨摘要”的每目标有界状态归约器。
    /// 信息层按 (TargetId, 伤害色/挡拆状态 + 主属性 + 斩杀) 分轨固定槽位展示；
    /// 冲击层用分档累积能量、自适应亮度白闪、描边瞬时加粗与重击微震颤提供瞬态打击感，
    /// 不改变稳态槽位、不保存逐段历史数组。
    /// </summary>
    internal sealed class HitNumberBalancedAccumulator
    {
        internal const double QuietSeconds = 0.72;
        internal const double FadeSeconds = 0.36;
        internal const double LifetimeSeconds = QuietSeconds + FadeSeconds;
        internal const double MissLaneLifetimeSeconds = 0.65;
        internal const double RecentHitMissSuppressSeconds = 0.35;
        internal const int LanesPerTarget = 3;
        internal const int MaximumTargets = 512;

        internal const float ImpactPeakBonus = 0.42f;
        internal const double BaseHoldSeconds = 0.075;
        internal const double DecayTauSeconds = 0.18;
        internal const float BaseFlashStrength = 0.55f;
        internal const double MicroShakeDurationSeconds = 0.12;
        internal const double SlideInDurationSeconds = 0.14;
        internal const float SlotVerticalStep = 38f;
        internal const float SemanticDensityScale = 0.56f;

        private readonly Dictionary<string, TargetLaneTable> _byTarget =
            new Dictionary<string, TargetLaneTable>(StringComparer.Ordinal);
        private readonly List<string> _expiredTargets = new List<string>();
        private readonly List<BalancedLaneKey> _expiredKeys = new List<BalancedLaneKey>();
        private readonly List<HitNumberBalancedLane> _snapshot = new List<HitNumberBalancedLane>();
        private readonly List<HitNumberBalancedLane> _sortScratch = new List<HitNumberBalancedLane>(LanesPerTarget + 1);

        internal int ActiveTargetCountForTests => _byTarget.Count;
        internal bool HasState => _byTarget.Count > 0;

        internal void AddRange(IReadOnlyList<HitNumberSegment> source, int startIndex, int count)
        {
            if (source == null) throw new ArgumentNullException(nameof(source));
            if (startIndex < 0 || count < 0 || startIndex + count > source.Count)
                throw new ArgumentOutOfRangeException(nameof(startIndex));
            if (count == 0) return;

            double newestArrival = source[startIndex].ArrivalSeconds;
            for (int i = 1; i < count; i++)
                newestArrival = Math.Max(newestArrival, source[startIndex + i].ArrivalSeconds);
            Prune(newestArrival);

            for (int i = 0; i < count; i++) Add(source[startIndex + i]);
        }

        internal List<HitNumberBalancedLane> Snapshot(double nowSeconds)
        {
            Prune(nowSeconds);
            _snapshot.Clear();
            foreach (TargetLaneTable table in _byTarget.Values)
            {
                foreach (HitNumberBalancedLane lane in table.Lanes.Values)
                {
                    lane.AdvanceVisual(nowSeconds);
                    _snapshot.Add(lane);
                }
            }
            return _snapshot;
        }

        internal void Clear()
        {
            _byTarget.Clear();
            _expiredTargets.Clear();
            _expiredKeys.Clear();
            _snapshot.Clear();
            _sortScratch.Clear();
        }

        internal static BalancedLaneKey BuildLaneKey(HitNumberSegment segment)
        {
            bool isMiss = HitNumberPacking.IsMiss(segment.Packed);
            if (isMiss) return new BalancedLaneKey(true, 0, false, false, string.Empty);

            int flags = HitNumberPacking.Flags(segment.Packed);
            int colorId = (segment.Packed >> 18) & 15;
            bool hasExecute = (flags & 4) != 0;
            string trimmed = string.IsNullOrWhiteSpace(segment.EffectText)
                ? string.Empty
                : segment.EffectText.Trim();
            if ((flags & 8) != 0 && trimmed.Length > 0)
                return new BalancedLaneKey(false, colorId, false, hasExecute, trimmed);
            if ((flags & 16) != 0 && trimmed.Length > 0)
                return new BalancedLaneKey(false, colorId, true, hasExecute, trimmed);
            return new BalancedLaneKey(false, colorId, false, hasExecute, string.Empty);
        }

        private void Add(HitNumberSegment segment)
        {
            if (segment == null) return;
            string targetId = ResolveTargetId(segment);
            if (!_byTarget.TryGetValue(targetId, out TargetLaneTable table))
            {
                if (_byTarget.Count >= MaximumTargets) EvictOldestTarget();
                table = new TargetLaneTable();
                _byTarget[targetId] = table;
            }

            BalancedLaneKey key = BuildLaneKey(segment);
            double now = segment.ArrivalSeconds;
            if (key.IsMiss)
            {
                foreach (HitNumberBalancedLane existing in table.Lanes.Values)
                {
                    if (!existing.IsMissLane && now - existing.LastArrivalSeconds < RecentHitMissSuppressSeconds)
                        return;
                }
            }
            else
            {
                table.Lanes.Remove(new BalancedLaneKey(true, 0, false, false, string.Empty));
            }

            double laneLife = key.IsMiss ? MissLaneLifetimeSeconds : LifetimeSeconds;
            bool isNew = !table.Lanes.TryGetValue(key, out HitNumberBalancedLane lane)
                || now - lane.LastArrivalSeconds >= laneLife;

            if (isNew)
            {
                if (table.Lanes.ContainsKey(key)) table.Lanes.Remove(key);
                if (table.Lanes.Count >= LanesPerTarget)
                    EvictLowestPriorityLane(table, now);

                int slotIndex = AllocateLowestFreeSlot(table);
                lane = new HitNumberBalancedLane(targetId, key, slotIndex, segment);
                table.Lanes[key] = lane;
            }

            lane.Add(segment, isNew);
            table.LastArrivalSeconds = Math.Max(table.LastArrivalSeconds, now);
        }

        private void Prune(double nowSeconds)
        {
            _expiredTargets.Clear();
            foreach (KeyValuePair<string, TargetLaneTable> pair in _byTarget)
            {
                TargetLaneTable table = pair.Value;
                _expiredKeys.Clear();
                foreach (KeyValuePair<BalancedLaneKey, HitNumberBalancedLane> lanePair in table.Lanes)
                {
                    double life = lanePair.Value.IsMissLane ? MissLaneLifetimeSeconds : LifetimeSeconds;
                    if (nowSeconds - lanePair.Value.LastArrivalSeconds >= life)
                        _expiredKeys.Add(lanePair.Key);
                }

                if (_expiredKeys.Count > 0)
                {
                    for (int i = 0; i < _expiredKeys.Count; i++)
                        table.Lanes.Remove(_expiredKeys[i]);

                    // 仅在有轨道自然消散后收敛腾出的低位槽，存活期内绝不按伤害反超互换槽位。
                    if (table.Lanes.Count > 0) CompactSlots(table);
                }

                if (table.Lanes.Count == 0)
                    _expiredTargets.Add(pair.Key);
            }

            for (int i = 0; i < _expiredTargets.Count; i++)
                _byTarget.Remove(_expiredTargets[i]);
        }

        private void CompactSlots(TargetLaneTable table)
        {
            _sortScratch.Clear();
            foreach (HitNumberBalancedLane lane in table.Lanes.Values)
                _sortScratch.Add(lane);
            _sortScratch.Sort(delegate(HitNumberBalancedLane left, HitNumberBalancedLane right)
            {
                int slot = left.SlotIndex.CompareTo(right.SlotIndex);
                return slot != 0 ? slot : left.FirstSequence.CompareTo(right.FirstSequence);
            });
            for (int i = 0; i < _sortScratch.Count; i++)
                _sortScratch[i].SetSlotIndex(i);
        }

        private static int AllocateLowestFreeSlot(TargetLaneTable table)
        {
            int usedMask = 0;
            foreach (HitNumberBalancedLane lane in table.Lanes.Values)
            {
                if (lane.SlotIndex >= 0 && lane.SlotIndex < 31)
                    usedMask |= 1 << lane.SlotIndex;
            }
            for (int slot = 0; slot < LanesPerTarget; slot++)
            {
                if ((usedMask & (1 << slot)) == 0) return slot;
            }
            return table.Lanes.Count;
        }

        private static void EvictLowestPriorityLane(TargetLaneTable table, double nowSeconds)
        {
            bool hasCandidate = false;
            BalancedLaneKey worstKey = default;
            double worstScore = double.PositiveInfinity;
            foreach (KeyValuePair<BalancedLaneKey, HitNumberBalancedLane> pair in table.Lanes)
            {
                HitNumberBalancedLane lane = pair.Value;
                double age = Math.Max(0.0, nowSeconds - lane.LastArrivalSeconds);
                double score = lane.IsMissLane
                    ? -1.0 - age
                    : ((lane.Flags & 4) != 0 ? 1e12 : 0.0) + lane.TotalDamage / (1.0 + age * 3.0);
                if (!hasCandidate || score < worstScore)
                {
                    hasCandidate = true;
                    worstScore = score;
                    worstKey = pair.Key;
                }
            }
            if (hasCandidate) table.Lanes.Remove(worstKey);
        }

        private void EvictOldestTarget()
        {
            string oldestKey = null;
            double oldestTime = double.PositiveInfinity;
            foreach (KeyValuePair<string, TargetLaneTable> pair in _byTarget)
            {
                if (pair.Value.LastArrivalSeconds < oldestTime)
                {
                    oldestTime = pair.Value.LastArrivalSeconds;
                    oldestKey = pair.Key;
                }
            }
            if (oldestKey != null) _byTarget.Remove(oldestKey);
        }

        private static string ResolveTargetId(HitNumberSegment segment)
        {
            if (!string.IsNullOrEmpty(segment.PresentationTargetId)) return segment.PresentationTargetId;
            return string.IsNullOrEmpty(segment.TargetId)
                ? "@" + segment.TargetX.ToString("0.###", CultureInfo.InvariantCulture)
                  + ":" + segment.TargetY.ToString("0.###", CultureInfo.InvariantCulture)
                : segment.TargetId;
        }

        private sealed class TargetLaneTable
        {
            internal readonly Dictionary<BalancedLaneKey, HitNumberBalancedLane> Lanes =
                new Dictionary<BalancedLaneKey, HitNumberBalancedLane>(LanesPerTarget + 1);
            internal double LastArrivalSeconds;
        }
    }

    internal sealed class HitNumberBalancedLane
    {
        private const int EffectFlagCount = 9;
        private const int VirtualFramesPerSecond = 24;
        private const float FlagDecayStep = 0.05f;
        private const float FlagVisibilityFloor = 0.10f;
        private const float FlagVisibilityCeiling = 0.50f;
        private const int ExecuteFlagBit = 2;

        private readonly long[] _effectFlagDamageSums = new long[EffectFlagCount];
        private readonly float[] _displayFlagScales = new float[EffectFlagCount];
        private double _lastVisualUpdateSeconds;
        private double _virtualFrameCarry;
        private int _representativePacked;
        private int _maximumSegmentDamage = int.MinValue;
        private string _flagScales = "000000000";

        internal HitNumberBalancedLane(
            string targetId,
            BalancedLaneKey key,
            int slotIndex,
            HitNumberSegment first)
        {
            TargetId = targetId ?? string.Empty;
            Key = key;
            LaneId = key.ToLaneId();
            IsMissLane = key.IsMiss;
            SlotIndex = slotIndex;
            FirstSequence = first.Sequence;
            LastSequence = first.Sequence;
            FirstArrivalSeconds = first.ArrivalSeconds;
            LastArrivalSeconds = first.ArrivalSeconds;
            BornSeconds = first.ArrivalSeconds;
            _lastVisualUpdateSeconds = first.ArrivalSeconds;
            TargetX = first.TargetX;
            TargetY = first.TargetY;
            MainColorId = key.ColorId;
            EffectTextColorId = key.ColorId;
            MaxDamageSize = HitNumberPacking.FontSize(first.Packed);
            _representativePacked = first.Packed;
            VisualOffsetY = -(slotIndex * HitNumberBalancedAccumulator.SlotVerticalStep);
        }

        internal string TargetId { get; }
        internal BalancedLaneKey Key { get; }
        internal string LaneId { get; }
        internal bool IsMissLane { get; }
        internal int SlotIndex { get; private set; }
        internal float TargetX { get; private set; }
        internal float TargetY { get; private set; }
        internal int FirstSequence { get; }
        internal int LastSequence { get; private set; }
        internal double FirstArrivalSeconds { get; }
        internal double LastArrivalSeconds { get; private set; }
        internal double BornSeconds { get; }
        internal long TotalDamage { get; private set; }
        internal long DisplayDamage { get; private set; }
        internal int HitCount { get; private set; }
        internal int DisplayHitCount { get; private set; }
        internal int ExpectedHitCount { get; private set; }
        internal int Flags { get; private set; }
        internal int MainColorId { get; }
        internal int EffectTextColorId { get; private set; }
        internal int MaxDamageSize { get; private set; }
        internal string EffectText { get; private set; } = string.Empty;
        internal string CrushText { get; private set; } = string.Empty;
        internal string CrushEmoji { get; private set; } = string.Empty;
        internal float LifeSteal { get; private set; }
        internal float ShieldAbsorb { get; private set; }
        internal string FlagScales => _flagScales;

        // 冲击层瞬态状态（不进入账本、不改变槽位拓扑）
        internal float ImpactEnergy { get; private set; }
        internal double HoldUntilSeconds { get; private set; }
        internal double FlashUntilSeconds { get; private set; }
        internal float FlashPeak { get; private set; }
        internal double ShakeStartSeconds { get; private set; }
        internal double ShakeUntilSeconds { get; private set; }
        internal int LastHitTier { get; private set; }
        internal float VisualOffsetY { get; private set; }

        internal int Packed
        {
            get
            {
                if (IsMissLane) return HitNumberPacking.Create(0, true, 14, 0);
                int packed = (_representativePacked & ~1023) | (Flags & 511);
                return packed & ~(1 << 9);
            }
        }

        internal void SetSlotIndex(int slotIndex)
        {
            SlotIndex = Math.Max(0, slotIndex);
        }

        internal void Add(HitNumberSegment segment, bool isFirst)
        {
            if (segment == null) return;
            double now = segment.ArrivalSeconds;
            double gap = isFirst ? double.PositiveInfinity : Math.Max(0.0, now - LastArrivalSeconds);
            if (!isFirst) AdvanceVisual(now);

            TargetX = segment.TargetX;
            TargetY = segment.TargetY;
            LastArrivalSeconds = Math.Max(LastArrivalSeconds, now);
            LastSequence = Math.Max(LastSequence, segment.Sequence);

            if (IsMissLane || HitNumberPacking.IsMiss(segment.Packed))
            {
                ExpectedHitCount = Math.Max(1, ExpectedHitCount);
                return;
            }

            int segFlags = HitNumberPacking.Flags(segment.Packed);
            int segDamageSize = HitNumberPacking.FontSize(segment.Packed);
            int tier = ComputeHitTier(segment, segFlags, segDamageSize, isFirst, gap);
            ApplyImpactEnergy(tier, now);

            TotalDamage = SaturatingAdd(TotalDamage, segment.Damage);
            if (HitCount < int.MaxValue) HitCount++;
            ExpectedHitCount = Math.Max(ExpectedHitCount, Math.Max(HitCount, segment.ExpectedBurstHitCount));
            Flags |= segFlags;
            MaxDamageSize = Math.Max(MaxDamageSize, segDamageSize);

            for (int bit = 0; bit < EffectFlagCount; bit++)
            {
                if ((segFlags & (1 << bit)) == 0) continue;
                _effectFlagDamageSums[bit] = SaturatingAdd(_effectFlagDamageSums[bit], segment.Damage);
                _displayFlagScales[bit] = 1f;
            }

            if (segment.Damage > _maximumSegmentDamage)
            {
                _maximumSegmentDamage = segment.Damage;
                _representativePacked = segment.Packed;
            }

            string text = string.IsNullOrWhiteSpace(segment.EffectText)
                ? string.Empty
                : segment.EffectText.Trim();
            if ((segFlags & 8) != 0 && text.Length > 0)
            {
                EffectText = text;
                EffectTextColorId = MainColorId;
            }
            if ((segFlags & 16) != 0)
            {
                CrushText = text.Length == 0 ? "粉" : text;
                CrushEmoji = string.IsNullOrWhiteSpace(segment.EffectEmoji)
                    ? string.Empty
                    : segment.EffectEmoji.Trim();
            }
            if (segment.LifeSteal > 0)
                LifeSteal = SaturatingFloatAdd(LifeSteal, segment.LifeSteal);
            if (segment.ShieldAbsorb > 0)
                ShieldAbsorb = SaturatingFloatAdd(ShieldAbsorb, segment.ShieldAbsorb);

            DisplayDamage = TotalDamage;
            DisplayHitCount = HitCount;
            if (isFirst)
            {
                EffectTextColorId = MainColorId;
            }
            RefreshFlagScales();
        }

        internal void AdvanceVisual(double nowSeconds)
        {
            double elapsed = nowSeconds - _lastVisualUpdateSeconds;
            if (elapsed > 0.0)
            {
                _lastVisualUpdateSeconds = nowSeconds;

                if (!IsMissLane && HitCount > 0)
                {
                    double virtualFrames = _virtualFrameCarry + elapsed * VirtualFramesPerSecond;
                    int wholeFrames = (int)Math.Min(64.0, Math.Floor(virtualFrames + 1e-9));
                    _virtualFrameCarry = virtualFrames - wholeFrames;
                    for (int frame = 0; frame < wholeFrames; frame++)
                    {
                        AdvanceEffectFlags();
                    }
                    if (wholeFrames > 0) RefreshFlagScales();

                    // 冲击能量在停留期后按指数衰减，保持高射速下的持续鼓胀与重击尖峰。
                    if (nowSeconds >= HoldUntilSeconds && ImpactEnergy > 0.001f)
                    {
                        double decayWindow = Math.Min(elapsed, nowSeconds - HoldUntilSeconds);
                        if (decayWindow > 0.0)
                        {
                            ImpactEnergy *= (float)Math.Exp(-decayWindow / HitNumberBalancedAccumulator.DecayTauSeconds);
                            if (ImpactEnergy < 0.004f) ImpactEnergy = 0f;
                        }
                    }
                    if (nowSeconds >= FlashUntilSeconds) FlashPeak = 0f;
                }
            }

            float targetOffsetY = -(SlotIndex * HitNumberBalancedAccumulator.SlotVerticalStep);
            if (elapsed > 0.0 && Math.Abs(targetOffsetY - VisualOffsetY) > 0.01f)
            {
                float settle = 1f - (float)Math.Exp(-elapsed / 0.055);
                VisualOffsetY += (targetOffsetY - VisualOffsetY) * Math.Clamp(settle, 0f, 1f);
            }
            else if (Math.Abs(targetOffsetY - VisualOffsetY) <= 0.01f)
            {
                VisualOffsetY = targetOffsetY;
            }
        }

        internal float ComputeSlideInOffsetY(double nowSeconds)
        {
            if (IsMissLane || SlotIndex <= 0) return 0f;
            double bornAge = Math.Max(0.0, nowSeconds - BornSeconds);
            if (bornAge >= HitNumberBalancedAccumulator.SlideInDurationSeconds) return 0f;
            float progress = (float)(bornAge / HitNumberBalancedAccumulator.SlideInDurationSeconds);
            // 从本槽下方 6px 弹入并轻微过冲（~0.6px），保持与下槽 >=28px 安全间距且具备机械卡位感。
            return 6f * (1f - EaseOutBack(progress));
        }

        internal Color ComputeDisplayMainColor(double nowSeconds)
        {
            if (IsMissLane) return Color.FromArgb(0xD8, 0xE2, 0xEC);
            Color baseColor = HitNumberPainter.ResolveColorId(MainColorId);
            if (nowSeconds >= FlashUntilSeconds || FlashPeak <= 0f) return baseColor;
            float rem = (float)Math.Clamp((FlashUntilSeconds - nowSeconds) / 0.065, 0.0, 1.0);
            float amount = rem * FlashPeak * HitNumberBalancedAccumulator.BaseFlashStrength;
            return BlendTowardsWhiteAdaptive(baseColor, amount);
        }

        internal static Color BlendTowardsWhiteAdaptive(Color baseColor, float amount)
        {
            if (amount <= 0.005f) return baseColor;
            // 按感知亮度自适应降幅：深色/饱和伤害充分白闪，浅黄/浅粉挡拆过穿防洗白撞脸 MISS。
            float lum = (0.299f * baseColor.R + 0.587f * baseColor.G + 0.114f * baseColor.B) / 255f;
            float damp = Math.Clamp(1.08f - lum * 0.82f, 0.22f, 1.0f);
            float w = Math.Clamp(amount, 0f, 0.85f) * damp;
            byte r = (byte)Math.Clamp((int)Math.Round(baseColor.R + (255 - baseColor.R) * w), 0, 255);
            byte g = (byte)Math.Clamp((int)Math.Round(baseColor.G + (255 - baseColor.G) * w), 0, 255);
            byte b = (byte)Math.Clamp((int)Math.Round(baseColor.B + (255 - baseColor.B) * w), 0, 255);
            return Color.FromArgb(r, g, b);
        }

        internal float ComputeFontSize()
        {
            if (IsMissLane) return 13.5f;
            float sizeMul = Math.Clamp(0.82f + ((MaxDamageSize - 18f) / 20f) * 0.33f, 0.82f, 1.15f);
            float rankMul = SlotIndex == 0 ? 1.0f : 0.88f;
            return 18f * sizeMul * rankMul;
        }

        internal float ComputeScale()
        {
            if (IsMissLane) return 1.0f;
            return 1.0f + Math.Clamp(ImpactEnergy, 0f, 1.15f) * HitNumberBalancedAccumulator.ImpactPeakBonus;
        }

        internal float ComputeBlur()
        {
            if (IsMissLane) return 1.8f;
            return 2.4f + Math.Clamp(ImpactEnergy, 0f, 1.15f) * 1.45f;
        }

        internal void ComputeShake(double nowSeconds, out float dx, out float dy)
        {
            if (IsMissLane || nowSeconds >= ShakeUntilSeconds)
            {
                dx = 0f;
                dy = 0f;
                return;
            }
            double sAge = Math.Max(0.0, nowSeconds - ShakeStartSeconds);
            float damp = (float)Math.Clamp(
                (ShakeUntilSeconds - nowSeconds) / HitNumberBalancedAccumulator.MicroShakeDurationSeconds,
                0.0,
                1.0);
            dx = (float)(Math.Sin(sAge * 130.0) * 2.4 * damp);
            dy = (float)(Math.Cos(sAge * 170.0) * 1.6 * damp);
        }

        private int ComputeHitTier(
            HitNumberSegment segment,
            int segFlags,
            int segDamageSize,
            bool isFirst,
            double gapSeconds)
        {
            bool isSpecial = (segFlags & (1 | 4 | 16)) != 0;
            double average = HitCount > 0 ? TotalDamage / (double)HitCount : segment.Damage;
            if (isSpecial || segDamageSize >= 34 || (!isFirst && average > 0 && segment.Damage >= average * 2.0))
                return 3;
            bool isGraze = MainColorId == 7 || MainColorId == 8 || segDamageSize <= 19;
            if (isGraze && !isFirst && gapSeconds < 0.30)
                return 0;
            if (isFirst || gapSeconds >= 0.30 || (average > 0 && segment.Damage >= average * 1.35))
                return 2;
            return 1;
        }

        private void ApplyImpactEnergy(int tier, double nowSeconds)
        {
            LastHitTier = tier;
            double hold = HitNumberBalancedAccumulator.BaseHoldSeconds;
            switch (tier)
            {
                case 0:
                    ImpactEnergy = Math.Min(0.38f, ImpactEnergy + 0.14f);
                    HoldUntilSeconds = Math.Max(HoldUntilSeconds, nowSeconds + hold * 0.25);
                    FlashUntilSeconds = Math.Max(FlashUntilSeconds, nowSeconds + 0.035);
                    FlashPeak = Math.Max(FlashPeak, 0.35f);
                    break;
                case 1:
                    ImpactEnergy = Math.Min(0.76f, ImpactEnergy + 0.26f);
                    HoldUntilSeconds = Math.Max(HoldUntilSeconds, nowSeconds + hold * 0.55);
                    FlashUntilSeconds = Math.Max(FlashUntilSeconds, nowSeconds + 0.048);
                    FlashPeak = Math.Max(FlashPeak, 0.60f);
                    break;
                case 2:
                    ImpactEnergy = Math.Min(0.95f, Math.Max(ImpactEnergy + 0.38f, 0.78f));
                    HoldUntilSeconds = Math.Max(HoldUntilSeconds, nowSeconds + hold * 0.90);
                    FlashUntilSeconds = Math.Max(FlashUntilSeconds, nowSeconds + 0.060);
                    FlashPeak = Math.Max(FlashPeak, 0.85f);
                    break;
                default:
                    ImpactEnergy = 1.08f;
                    HoldUntilSeconds = Math.Max(HoldUntilSeconds, nowSeconds + hold * 1.25);
                    FlashUntilSeconds = Math.Max(FlashUntilSeconds, nowSeconds + 0.075);
                    FlashPeak = 1.0f;
                    ShakeStartSeconds = nowSeconds;
                    ShakeUntilSeconds = nowSeconds + HitNumberBalancedAccumulator.MicroShakeDurationSeconds;
                    break;
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

        private void RefreshFlagScales()
        {
            Span<char> encoded = stackalloc char[EffectFlagCount];
            for (int bit = 0; bit < EffectFlagCount; bit++)
            {
                float scale = _displayFlagScales[bit];
                int level = scale < 0.02f ? 0 : (int)Math.Floor(scale * 9f + 0.5f);
                encoded[bit] = (char)('0' + Math.Max(0, Math.Min(9, level)));
            }
            if (_flagScales.AsSpan().SequenceEqual(encoded)) return;
            _flagScales = new string(encoded);
        }

        private static float EaseOutBack(float t)
        {
            const float c1 = 1.70158f;
            const float c3 = c1 + 1f;
            float x = Math.Clamp(t, 0f, 1f) - 1f;
            return 1f + c3 * x * x * x + c1 * x * x;
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
