using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal enum HitNumberLayoutCandidate
    {
        FixedBurstStack,
        BalancedSummary,
        ClassicScatter,
        TargetTotal
    }

    internal readonly struct HitNumberCamera
    {
        internal HitNumberCamera(float offsetX, float offsetY, float scale)
        {
            OffsetX = offsetX;
            OffsetY = offsetY;
            Scale = scale;
        }

        internal float OffsetX { get; }
        internal float OffsetY { get; }
        internal float Scale { get; }
        internal static HitNumberCamera Identity => new HitNumberCamera(0f, 0f, 1f);

        internal float ToStageX(float worldX) => OffsetX + worldX * Scale;
        internal float ToStageY(float worldY) => OffsetY + worldY * Scale;
    }

    /// <summary>
    /// 一段伤害的视觉输入。段的权威定义是一发子弹造成的伤害；联弹应在进入本层前
    /// 展开成多个具有同一 BurstId 的虚拟子弹段，本层同时保留逐段和攻击总计。
    /// </summary>
    internal sealed class HitNumberSegment
    {
        internal int Sequence;
        internal string BurstId = string.Empty;
        internal string TargetId = string.Empty;
        internal float TargetX;
        internal float TargetY;
        internal double ArrivalSeconds;
        internal int ExpectedBurstHitCount;
        internal int Damage;
        internal int Packed;
        internal string EffectText = string.Empty;
        internal string EffectEmoji = string.Empty;
        internal float LifeSteal;
        internal float ShieldAbsorb;
    }

    /// <summary>
    /// 一次攻击在固定目标栈中的稳定行。Bounds、AttachmentX 和行顺序全部只依赖
    /// 目标锚点、Burst 自身内容和新旧次序，不读取邻近目标，不进行动态避碰。
    /// </summary>
    internal sealed class HitNumberBurstRow
    {
        internal string TargetId = string.Empty;
        internal string BurstId = string.Empty;
        internal float TargetX;
        internal float TargetY;
        internal RectangleF Bounds;
        internal float AttachmentX;
        internal float AttachmentY;
        internal int GrowthDirection;
        internal long TotalDamage;
        internal int HitCount;
        internal int ExpectedHitCount;
        internal int FirstSequence;
        internal double FirstArrivalSeconds;
        internal double LastArrivalSeconds;
        internal string AttributeSummary = string.Empty;
        internal float Alpha = 1f;
        internal List<HitNumberSegment> Segments { get; } = new List<HitNumberSegment>();
    }

    internal sealed class HitNumberLayoutFrame
    {
        internal HitNumberLayoutCandidate Candidate;
        internal List<HitNumberPaintItem> Items { get; } = new List<HitNumberPaintItem>();
        internal List<HitNumberBurstRow> WorldRows { get; } = new List<HitNumberBurstRow>();
        internal int InputActiveSegmentCount;
        internal int OffscreenCulledSegmentCount;
        internal int DetailItemCount;
        internal int SummaryItemCount;
        internal int WorldRowOmittedCount;
        internal int WorldSegmentOmittedCount;
        internal float EstimatedOverlapRatio;
        internal int CausalOwnershipViolationCount;
    }

    internal static class HitNumberPacking
    {
        internal static int Create(
            int flags,
            bool isMiss,
            int fontSize,
            int colorId)
        {
            int packed = flags & 511;
            if (isMiss) packed |= 1 << 9;
            packed |= (Math.Max(0, Math.Min(255, fontSize)) & 255) << 10;
            packed |= (Math.Max(0, Math.Min(15, colorId)) & 15) << 18;
            return packed;
        }

        internal static int WithFontSize(int packed, int fontSize)
        {
            return (packed & ~(255 << 10)) |
                ((Math.Max(0, Math.Min(255, fontSize)) & 255) << 10);
        }

        internal static int WithFlags(int packed, int flags)
        {
            return (packed & ~511) | (flags & 511);
        }

        internal static int FontSize(int packed)
        {
            int size = (packed >> 10) & 255;
            return size == 0 ? 28 : size;
        }

        internal static int Flags(int packed) => packed & 511;

        internal static bool IsMiss(int packed) => (packed & (1 << 9)) != 0;
    }

    /// <summary>
    /// detail/balanced 生产布局器：detail 在世界内按 Burst 固定成行并展示逐段；
    /// balanced 在同一固定栈中只投影攻击总计。精确逐段历史由独立 LedgerStore
    /// 承担，不进入世界布局或 layered-window paint；世界层禁用邻居驱动方向与
    /// 动态避碰。有限 detail 每目标只保留最新六行以维持可读性，显式无限制
    /// 仍完整投影；唯一输入剔除是目标位于舞台外加 100px margin。
    /// </summary>
    internal static class HitNumberLayoutEngine
    {
        internal const float StageWidth = 1024f;
        internal const float StageHeight = 576f;
        internal const double DefaultLifetimeSeconds = 1.08;
        internal const double ClassicLifetimeSeconds = 14.0 / 24.0;

        internal const float StageMarginForTests = 8f;
        private const float TargetConnectorGap = 14f;
        private const float RowGap = 1f;
        private const int BalancedRowsPerTarget = 3;
        private const int LimitedDetailRowsPerTarget = 6;
        private const int BalancedFontSize = 20;
        private const int EffectFlagCount = 9;
        private const int ColorCount = 11;
        private const int ExecuteFlagBit = 2;
        private const float FlagVisibilityFloor = 0.10f;
        private const float FlagVisibilityCeiling = 0.50f;
        private const float FlagDecayStep = 0.05f;
        private const float ColorDecayRetention = 0.85f;
        private const float ClassicPositionOffset = 60f;
        private const float ClassicTextCenterX = 114.5f;
        private const float ClassicTextCenterY = 19.65f;
        private static readonly float[] ClassicScale =
        {
            1.3176f, 1.3176f, 1.3176f, 1.3176f,
            1.0687f, 1.0458f, 1.0229f, 1f, 1f,
            0.9291f, 0.9056f, 0.7130667f, 0.5205333f, 0.3280f
        };
        private static readonly float[] ClassicBlur =
        {
            4f, 4f, 4f, 4f, 3f, 3f, 3f, 3f, 3f,
            2f, 2f, 1.6666667f, 1.3333333f, 1f
        };
        private static readonly float[] ClassicTranslateX =
        {
            -241.65f, -241.65f, -241.65f, -241.65f,
            -196f, -191.8f, -187.6f, -183.4f, -183.4f,
            -170.4f, -166.1f, -140.3f, -114.5f, -88.7f
        };
        private static readonly float[] ClassicTranslateY =
        {
            -136f, -136f, -136f, -136f,
            -131.1f, -130.65f, -130.2f, -129.75f, -129.75f,
            -135.85f, -137.9f, -137.43333f, -136.96667f, -136.5f
        };

        internal static HitNumberLayoutFrame BuildFrame(
            IReadOnlyList<HitNumberSegment> source,
            double nowSeconds,
            HitNumberLayoutCandidate candidate,
            double lifetimeSeconds = DefaultLifetimeSeconds)
        {
            return BuildFrame(
                source,
                0,
                nowSeconds,
                candidate,
                HitNumberCamera.Identity,
                0,
                lifetimeSeconds,
                true);
        }

        internal static HitNumberLayoutFrame BuildFrame(
            IReadOnlyList<HitNumberSegment> source,
            int sourceStartIndex,
            double nowSeconds,
            HitNumberLayoutCandidate candidate,
            HitNumberCamera camera,
            int worldRowLimit,
            double lifetimeSeconds,
            bool includeDiagnostics)
        {
            if (source == null) throw new ArgumentNullException(nameof(source));
            if (sourceStartIndex < 0 || sourceStartIndex > source.Count)
                throw new ArgumentOutOfRangeException(nameof(sourceStartIndex));
            if (worldRowLimit < 0) throw new ArgumentOutOfRangeException(nameof(worldRowLimit));
            if (lifetimeSeconds <= 0) throw new ArgumentOutOfRangeException(nameof(lifetimeSeconds));

            var frame = new HitNumberLayoutFrame { Candidate = candidate };
            var groups = new Dictionary<string, List<ActiveSegment>>(StringComparer.Ordinal);
            var groupOrder = new List<string>();

            // 生产常态的有限世界投影不需要把窗口内所有旧 Burst 都物化成对象树。
            // 运行时 source 按 arrival/sequence 追加，因此从尾部扫描即可确定最新 K 个
            // Burst；只为它们建立 ActiveSegment/BurstSlice。诊断路径仍走下方完整
            // 物化，以便对照有限投影的选择结果；精确日志不经过本布局器。
            bool limitedProjectionFastPath =
                !includeDiagnostics && worldRowLimit > 0 &&
                IsSourceChronological(source, sourceStartIndex);
            HashSet<BurstIdentity> selectedWorldBursts = null;
            if (limitedProjectionFastPath)
            {
                var seenBursts = new HashSet<BurstIdentity>();
                selectedWorldBursts = new HashSet<BurstIdentity>();
                int perTargetRowLimit = PerTargetWorldRowLimit(candidate, worldRowLimit);
                Dictionary<string, int> selectedBurstsPerTarget =
                    perTargetRowLimit > 0
                        ? new Dictionary<string, int>(StringComparer.Ordinal)
                        : null;
                for (int i = source.Count - 1; i >= sourceStartIndex; i--)
                {
                    HitNumberSegment segment = source[i];
                    double age = nowSeconds - segment.ArrivalSeconds;
                    if (age < 0 || age >= lifetimeSeconds) continue;
                    frame.InputActiveSegmentCount++;

                    float stageX = camera.ToStageX(segment.TargetX);
                    float stageY = camera.ToStageY(segment.TargetY);
                    if (!IsTargetOnscreen(stageX, stageY))
                    {
                        frame.OffscreenCulledSegmentCount++;
                        continue;
                    }

                    string targetId = TargetKey(segment);
                    var identity = new BurstIdentity(targetId, segment);
                    if (!seenBursts.Add(identity)) continue;
                    if (selectedBurstsPerTarget != null)
                    {
                        selectedBurstsPerTarget.TryGetValue(targetId, out int targetCount);
                        if (targetCount >= perTargetRowLimit) continue;
                        selectedBurstsPerTarget[targetId] = targetCount + 1;
                    }
                    if (selectedWorldBursts.Count < worldRowLimit)
                        selectedWorldBursts.Add(identity);
                }
                frame.WorldRowOmittedCount = seenBursts.Count - selectedWorldBursts.Count;
            }

            int selectedVisibleSegments = 0;
            for (int i = sourceStartIndex; i < source.Count; i++)
            {
                HitNumberSegment segment = source[i];
                double age = nowSeconds - segment.ArrivalSeconds;
                if (age < 0 || age >= lifetimeSeconds) continue;
                if (!limitedProjectionFastPath) frame.InputActiveSegmentCount++;

                float stageX = camera.ToStageX(segment.TargetX);
                float stageY = camera.ToStageY(segment.TargetY);
                if (!IsTargetOnscreen(stageX, stageY))
                {
                    if (!limitedProjectionFastPath) frame.OffscreenCulledSegmentCount++;
                    continue;
                }

                string targetId = TargetKey(segment);
                if (limitedProjectionFastPath &&
                    !selectedWorldBursts.Contains(new BurstIdentity(targetId, segment)))
                {
                    continue;
                }
                selectedVisibleSegments++;
                if (!groups.TryGetValue(targetId, out List<ActiveSegment> group))
                {
                    group = new List<ActiveSegment>();
                    groups.Add(targetId, group);
                    groupOrder.Add(targetId);
                }
                group.Add(new ActiveSegment(
                    segment,
                    age,
                    age / lifetimeSeconds,
                    stageX,
                    stageY));
            }
            if (limitedProjectionFastPath)
            {
                int visibleSegments =
                    frame.InputActiveSegmentCount - frame.OffscreenCulledSegmentCount;
                frame.WorldSegmentOmittedCount = visibleSegments - selectedVisibleSegments;
            }

            var burstsByTarget = new List<List<BurstSlice>>(groupOrder.Count);
            var allBursts = new List<BurstSlice>();
            int materializedPerTargetRowLimit =
                PerTargetWorldRowLimit(candidate, worldRowLimit);
            for (int groupIndex = 0; groupIndex < groupOrder.Count; groupIndex++)
            {
                string targetId = groupOrder[groupIndex];
                List<ActiveSegment> group = groups[targetId];
                if (!IsActiveSorted(group)) group.Sort(CompareActive);
                List<BurstSlice> bursts = BuildBurstSlices(group, targetId);
                if (!IsBurstSorted(bursts)) bursts.Sort(CompareBurst);
                if (materializedPerTargetRowLimit > 0
                    && bursts.Count > materializedPerTargetRowLimit)
                {
                    int removeCount = bursts.Count - materializedPerTargetRowLimit;
                    for (int i = 0; i < removeCount; i++)
                        frame.WorldSegmentOmittedCount += bursts[i].Segments.Count;
                    frame.WorldRowOmittedCount += removeCount;
                    bursts = bursts.GetRange(removeCount, materializedPerTargetRowLimit);
                }
                burstsByTarget.Add(bursts);
                allBursts.AddRange(bursts);
            }

            HashSet<BurstSlice> worldBursts = null;
            if (worldRowLimit > 0 && allBursts.Count > worldRowLimit)
            {
                var newest = new PriorityQueue<BurstSlice, BurstSlice>(
                    worldRowLimit,
                    BurstOldestFirstComparer.Instance);
                int totalSegments = 0;
                for (int i = 0; i < allBursts.Count; i++)
                {
                    BurstSlice burst = allBursts[i];
                    totalSegments += burst.Segments.Count;
                    newest.Enqueue(burst, burst);
                    if (newest.Count > worldRowLimit) newest.Dequeue();
                }
                worldBursts = new HashSet<BurstSlice>();
                int selectedSegments = 0;
                foreach (var item in newest.UnorderedItems)
                {
                    worldBursts.Add(item.Element);
                    selectedSegments += item.Element.Segments.Count;
                }
                frame.WorldRowOmittedCount += allBursts.Count - worldRowLimit;
                frame.WorldSegmentOmittedCount += totalSegments - selectedSegments;
            }

            // 各目标内部保持旧→新构造稳定栈；目标之间则按最后一次可见命中排序，
            // 让最新受击目标最后进入 Painter（Z-top）。这沿用总伤模式已经验证过
            // 的遮挡策略，不引入邻居驱动的位置变化。
            burstsByTarget.Sort(delegate(
                List<BurstSlice> left,
                List<BurstSlice> right)
            {
                BurstSlice leftNewest = NewestSelectedBurst(left, worldBursts);
                BurstSlice rightNewest = NewestSelectedBurst(right, worldBursts);
                if (leftNewest == null) return rightNewest == null ? 0 : -1;
                if (rightNewest == null) return 1;
                int arrival = leftNewest.LastArrivalSeconds.CompareTo(
                    rightNewest.LastArrivalSeconds);
                return arrival != 0
                    ? arrival
                    : leftNewest.LastSequence.CompareTo(rightNewest.LastSequence);
            });

            for (int groupIndex = 0; groupIndex < burstsByTarget.Count; groupIndex++)
            {
                List<BurstSlice> bursts = burstsByTarget[groupIndex];
                if (worldBursts != null)
                    bursts = bursts.FindAll(delegate(BurstSlice burst) { return worldBursts.Contains(burst); });

                if (candidate == HitNumberLayoutCandidate.ClassicScatter)
                    BuildClassicBursts(frame, bursts, camera);
                else
                    BuildTargetStack(
                        frame,
                        bursts,
                        candidate == HitNumberLayoutCandidate.FixedBurstStack,
                        candidate == HitNumberLayoutCandidate.BalancedSummary);
            }

            if (includeDiagnostics)
            {
                frame.EstimatedOverlapRatio = EstimateOverlapRatio(frame.Items);
                EvaluateStructuredMetrics(frame);
            }
            return frame;
        }

        private static BurstSlice NewestSelectedBurst(
            List<BurstSlice> bursts,
            HashSet<BurstSlice> selected)
        {
            for (int i = bursts.Count - 1; i >= 0; i--)
            {
                if (selected == null || selected.Contains(bursts[i])) return bursts[i];
            }
            return null;
        }

        private static void BuildTargetStack(
            HitNumberLayoutFrame frame,
            List<BurstSlice> bursts,
            bool includeWorldDetails,
            bool centerOnTarget)
        {
            if (bursts.Count == 0) return;

            BurstSlice newest = bursts[bursts.Count - 1];
            float targetX = newest.TargetX;
            float targetY = newest.TargetY;
            var specs = new RowSpec[bursts.Count];
            float maximumWidth = 0f;
            for (int i = 0; i < bursts.Count; i++)
            {
                specs[i] = RowSpec.Create(bursts[i], includeWorldDetails);
                maximumWidth = Math.Max(maximumWidth, specs[i].Width);
            }

            int growthDirection = centerOnTarget
                ? 0
                : ChooseGrowthDirection(targetX, maximumWidth);
            float cursorBottom = Clamp(targetY - 48f, 64f, StageHeight - 12f);
            var rows = new List<HitNumberBurstRow>(bursts.Count);
            var items = new List<HitNumberPaintItem>();

            for (int burstIndex = bursts.Count - 1; burstIndex >= 0; burstIndex--)
            {
                BurstSlice burst = bursts[burstIndex];
                RowSpec spec = specs[burstIndex];
                RectangleF bounds = PlaceRow(targetX, cursorBottom, spec, growthDirection);
                HitNumberBurstRow row = CreateRow(burst, bounds, growthDirection);
                rows.Add(row);
                BuildRowItems(row, burst, spec, includeWorldDetails, items);
                // 新 Burst 在出现的第一帧就占用完整槽位。透明度仍平滑淡入，但几何
                // 不做“挤入”插值，否则高频攻击会让相邻行在前 100 ms 内持续互压。
                cursorBottom -= spec.Height + RowGap;
            }

            TranslateStackIntoStage(rows, items);
            for (int i = 0; i < rows.Count; i++) frame.WorldRows.Add(rows[i]);
            for (int i = 0; i < items.Count; i++)
            {
                frame.Items.Add(items[i]);
                if (items[i].VisualRole == HitNumberVisualRole.Detail) frame.DetailItemCount++;
                else frame.SummaryItemCount++;
            }
        }

        private static void BuildClassicBursts(
            HitNumberLayoutFrame frame,
            List<BurstSlice> bursts,
            HitNumberCamera camera)
        {
            for (int burstIndex = 0; burstIndex < bursts.Count; burstIndex++)
            {
                BurstSlice burst = bursts[burstIndex];
                RectangleF bounds = RectangleF.Empty;
                bool hasBounds = false;
                for (int i = 0; i < burst.Segments.Count; i++)
                {
                    HitNumberPaintItem item = ToClassicItem(burst.Segments[i], camera);
                    frame.Items.Add(item);
                    frame.DetailItemCount++;
                    RectangleF itemBounds = EstimateItemBounds(item);
                    bounds = hasBounds ? RectangleF.Union(bounds, itemBounds) : itemBounds;
                    hasBounds = true;
                }
                if (!hasBounds) continue;
                HitNumberBurstRow row = CreateRow(burst, bounds, 0);
                row.AttachmentX = row.TargetX;
                row.AttachmentY = row.TargetY - 28f;
                frame.WorldRows.Add(row);
            }
        }

        private static RectangleF PlaceRow(
            float targetX,
            float cursorBottom,
            RowSpec spec,
            int growthDirection)
        {
            float left;
            if (growthDirection < 0)
                left = targetX - TargetConnectorGap - spec.Width;
            else if (growthDirection > 0)
                left = targetX + TargetConnectorGap;
            else
                left = targetX - spec.Width / 2f;

            left = Clamp(
                left,
                StageMarginForTests,
                StageWidth - StageMarginForTests - spec.Width);
            return new RectangleF(left, cursorBottom - spec.Height, spec.Width, spec.Height);
        }

        private static int ChooseGrowthDirection(float targetX, float maximumWidth)
        {
            if (Math.Abs(targetX - StageWidth / 2f) <= 46f) return 0;

            int preferred = targetX < StageWidth / 2f ? -1 : 1;
            if (FitsDirection(targetX, maximumWidth, preferred)) return preferred;
            if (FitsDirection(targetX, maximumWidth, -preferred)) return -preferred;
            return 0;
        }

        private static bool FitsDirection(float targetX, float width, int direction)
        {
            float left = direction < 0
                ? targetX - TargetConnectorGap - width
                : targetX + TargetConnectorGap;
            return left >= StageMarginForTests &&
                left + width <= StageWidth - StageMarginForTests;
        }

        private static HitNumberBurstRow CreateRow(
            BurstSlice burst,
            RectangleF bounds,
            int growthDirection)
        {
            var row = new HitNumberBurstRow
            {
                TargetId = burst.TargetId,
                BurstId = burst.Id,
                TargetX = burst.TargetX,
                TargetY = burst.TargetY,
                Bounds = bounds,
                AttachmentX = growthDirection < 0
                    ? bounds.Right
                    : growthDirection > 0 ? bounds.Left : bounds.Left + bounds.Width / 2f,
                AttachmentY = bounds.Bottom,
                GrowthDirection = growthDirection,
                TotalDamage = burst.TotalDamage,
                HitCount = burst.Segments.Count,
                ExpectedHitCount = burst.ExpectedHitCount,
                FirstSequence = burst.FirstSequence,
                FirstArrivalSeconds = burst.FirstArrivalSeconds,
                LastArrivalSeconds = burst.LastArrivalSeconds,
                AttributeSummary = burst.VisualProjection.AttributeSummary,
                Alpha = BurstAlpha(burst)
            };
            for (int i = 0; i < burst.Segments.Count; i++)
                row.Segments.Add(burst.Segments[i].Segment);
            return row;
        }

        private static void BuildRowItems(
            HitNumberBurstRow row,
            BurstSlice burst,
            RowSpec spec,
            bool includeWorldDetails,
            List<HitNumberPaintItem> destination)
        {
            if (includeWorldDetails && burst.Segments.Count == 1)
            {
                HitNumberPaintItem only = ToDetailItem(burst.Segments[0], spec.DetailFontSize);
                only.StageX = row.Bounds.Left + row.Bounds.Width / 2f;
                only.StageY = row.Bounds.Top + spec.TopPadding + ImpactLift(burst.Segments[0].AgeSeconds);
                destination.Add(only);
                return;
            }

            bool summaryAtRight = includeWorldDetails && row.GrowthDirection < 0;
            float summaryX = summaryAtRight
                ? row.Bounds.Right - spec.SummaryWidth / 2f - spec.HorizontalPadding
                : row.Bounds.Left + spec.SummaryWidth / 2f + spec.HorizontalPadding;
            float summaryY = row.Bounds.Top + spec.TopPadding;
            destination.Add(BuildSummaryItem(
                burst,
                summaryX,
                summaryY,
                spec.SummaryFontSize,
                !includeWorldDetails));

            if (!includeWorldDetails) return;

            float detailsLeft = summaryAtRight
                ? row.Bounds.Left + spec.HorizontalPadding
                : row.Bounds.Left + spec.HorizontalPadding + spec.SummaryWidth;
            for (int i = 0; i < burst.Segments.Count; i++)
            {
                int detailRow = i / spec.DetailColumns;
                int detailColumn = i % spec.DetailColumns;
                HitNumberPaintItem item = ToDetailItem(burst.Segments[i], spec.DetailFontSize);
                item.StageX = detailsLeft + (detailColumn + 0.5f) * spec.DetailCellWidth;
                item.StageY = row.Bounds.Top + spec.TopPadding
                    + detailRow * spec.DetailLineHeight
                    + ImpactLift(burst.Segments[i].AgeSeconds);
                destination.Add(item);
            }
        }

        private static HitNumberPaintItem BuildSummaryItem(
            BurstSlice burst,
            float x,
            float y,
            int fontSize,
            bool includeAttributes)
        {
            int displayedTotal = ClampLongToInt(burst.TotalDamage);
            ActiveSegment representative = burst.Segments[0];
            long largestMagnitude = long.MinValue;
            bool allMiss = true;
            for (int i = 0; i < burst.Segments.Count; i++)
            {
                ActiveSegment candidate = burst.Segments[i];
                long magnitude = Math.Abs((long)candidate.Segment.Damage);
                if (magnitude > largestMagnitude)
                {
                    largestMagnitude = magnitude;
                    representative = candidate;
                }
                if (!HitNumberPacking.IsMiss(candidate.Segment.Packed)) allMiss = false;
            }

            BurstVisualProjection projection = burst.VisualProjection;
            int packed = HitNumberPacking.WithFontSize(representative.Segment.Packed, fontSize);
            packed &= ~(1 << 9);
            packed = HitNumberPacking.WithFlags(
                packed,
                includeAttributes && !allMiss ? projection.Flags : 0);
            if (allMiss) packed |= 1 << 9;

            return new HitNumberPaintItem
            {
                StageX = x,
                StageY = y + BurstImpactLift(burst),
                CombinedScale = BurstImpactScale(burst),
                Alpha = BurstAlpha(burst),
                CombinedBlur = 2.8f,
                Damage = displayedTotal,
                Packed = packed,
                EffectText = includeAttributes ? projection.EffectText : string.Empty,
                CrushText = includeAttributes ? projection.CrushText : string.Empty,
                CrushEmoji = includeAttributes ? projection.CrushEmoji : string.Empty,
                LifeSteal = includeAttributes ? projection.LifeSteal : 0f,
                ShieldAbsorb = includeAttributes ? projection.ShieldAbsorb : 0f,
                HitCount = burst.Segments.Count,
                FlagScales = includeAttributes ? projection.FlagScales : "000000000",
                SemanticDensityScale = includeAttributes ? 4f / 9f : 1f,
                MainColorOverride = allMiss ? null : projection.MainColor,
                EffectTextColorOverride = includeAttributes && !allMiss
                    ? projection.EffectTextColor
                    : null,
                SourceSequence = -1,
                SourceBurstId = burst.Id,
                SourceTargetId = burst.TargetId,
                SourceTargetX = burst.TargetX,
                SourceTargetY = burst.TargetY,
                VisualRole = HitNumberVisualRole.Summary
            };
        }

        private static HitNumberPaintItem ToDetailItem(ActiveSegment active, int fontSize)
        {
            HitNumberSegment segment = active.Segment;
            float alpha = active.Progress01 <= 0.78
                ? 1f
                : (float)Math.Max(0.16, (1.0 - active.Progress01) / 0.22);
            return new HitNumberPaintItem
            {
                StageX = active.StageX,
                StageY = active.StageY,
                CombinedScale = ImpactScale(active.AgeSeconds),
                Alpha = alpha,
                CombinedBlur = 2.0f,
                Damage = segment.Damage,
                Packed = HitNumberPacking.WithFontSize(segment.Packed, fontSize),
                EffectText = segment.EffectText,
                EffectEmoji = segment.EffectEmoji,
                LifeSteal = segment.LifeSteal,
                ShieldAbsorb = segment.ShieldAbsorb,
                HitCount = 1,
                FlagScales = "999999999",
                SemanticDensityScale = 1f / 3f,
                // 属性文字始终冻结为该逐段输入的来源色。当前主数字也使用同色，
                // 但显式解耦可防止以后增加主数字脉冲/过渡时连带污染属性色。
                EffectTextColorOverride = HitNumberPainter.ResolveMainColor(segment.Packed),
                SourceSequence = segment.Sequence,
                SourceBurstId = segment.BurstId,
                SourceTargetId = segment.TargetId,
                SourceTargetX = active.StageX,
                SourceTargetY = active.StageY,
                VisualRole = HitNumberVisualRole.Detail
            };
        }

        private static HitNumberPaintItem ToClassicItem(
            ActiveSegment active,
            HitNumberCamera camera)
        {
            int frame = Math.Max(0, Math.Min(
                ClassicScale.Length - 1,
                (int)Math.Floor(active.AgeSeconds * 24.0)));
            float randomX = StableClassicOffset(active.Segment.Sequence, 0x4F1BBCDCu);
            float randomY = StableClassicOffset(active.Segment.Sequence, 0x91E10DA5u);
            float offsetX = ClassicScale[frame] * ClassicTextCenterX
                + ClassicTranslateX[frame];
            float offsetY = ClassicScale[frame] * ClassicTextCenterY
                + ClassicTranslateY[frame];
            HitNumberSegment segment = active.Segment;
            return new HitNumberPaintItem
            {
                StageX = active.StageX + (randomX + offsetX) * camera.Scale,
                StageY = active.StageY + (randomY + offsetY) * camera.Scale,
                CombinedScale = ClassicScale[frame] * camera.Scale,
                Alpha = 1f,
                CombinedBlur = ClassicBlur[frame] * camera.Scale,
                Damage = segment.Damage,
                Packed = HitNumberPacking.WithFontSize(segment.Packed, BalancedFontSize),
                EffectText = segment.EffectText,
                EffectEmoji = segment.EffectEmoji,
                LifeSteal = segment.LifeSteal,
                ShieldAbsorb = segment.ShieldAbsorb,
                HitCount = 1,
                FlagScales = "999999999",
                SemanticDensityScale = 4f / 9f,
                EffectTextColorOverride = HitNumberPainter.ResolveMainColor(segment.Packed),
                SourceSequence = segment.Sequence,
                SourceBurstId = segment.BurstId,
                SourceTargetId = segment.TargetId,
                SourceTargetX = active.StageX,
                SourceTargetY = active.StageY,
                VisualRole = HitNumberVisualRole.Detail
            };
        }

        internal static HitNumberLayoutFrame BuildTotalFrame(
            IReadOnlyList<HitNumberTotalEntry> source,
            double nowSeconds,
            HitNumberCamera camera,
            int worldRowLimit)
        {
            if (source == null) throw new ArgumentNullException(nameof(source));
            if (worldRowLimit < 0) throw new ArgumentOutOfRangeException(nameof(worldRowLimit));

            var visible = new List<HitNumberTotalEntry>();
            var stagePositions = new Dictionary<HitNumberTotalEntry, PointF>();
            var frame = new HitNumberLayoutFrame { Candidate = HitNumberLayoutCandidate.TargetTotal };
            for (int i = 0; i < source.Count; i++)
            {
                HitNumberTotalEntry entry = source[i];
                frame.InputActiveSegmentCount = SaturatingCountAdd(
                    frame.InputActiveSegmentCount,
                    entry.HitCount);
                float stageX = camera.ToStageX(entry.TargetX);
                float stageY = camera.ToStageY(entry.TargetY);
                if (!IsTargetOnscreen(stageX, stageY))
                {
                    frame.OffscreenCulledSegmentCount = SaturatingCountAdd(
                        frame.OffscreenCulledSegmentCount,
                        entry.HitCount);
                    continue;
                }
                visible.Add(entry);
                stagePositions[entry] = new PointF(stageX, stageY);
            }
            visible.Sort(delegate(HitNumberTotalEntry left, HitNumberTotalEntry right)
            {
                int arrival = right.LastArrivalSeconds.CompareTo(left.LastArrivalSeconds);
                return arrival != 0 ? arrival : right.FirstSequence.CompareTo(left.FirstSequence);
            });
            if (worldRowLimit > 0 && visible.Count > worldRowLimit)
            {
                frame.WorldRowOmittedCount = visible.Count - worldRowLimit;
                for (int i = worldRowLimit; i < visible.Count; i++)
                    frame.WorldSegmentOmittedCount = SaturatingCountAdd(
                        frame.WorldSegmentOmittedCount,
                    visible[i].HitCount);
                visible.RemoveRange(worldRowLimit, visible.Count - worldRowLimit);
            }
            // 上限选择必须 newest-first，但 Painter 是顺序覆盖；恢复旧聚合器“新目标
            // 最后绘制、位于 Z-top”的语义后再进入绘制列表。
            visible.Sort(delegate(HitNumberTotalEntry left, HitNumberTotalEntry right)
            {
                int arrival = left.LastArrivalSeconds.CompareTo(right.LastArrivalSeconds);
                return arrival != 0 ? arrival : left.FirstSequence.CompareTo(right.FirstSequence);
            });

            for (int i = 0; i < visible.Count; i++)
            {
                HitNumberTotalEntry entry = visible[i];
                PointF target = stagePositions[entry];
                float age = (float)Math.Max(0.0, nowSeconds - entry.LastArrivalSeconds);
                float alpha = age <= HitNumberTotalAccumulator.QuietSeconds
                    ? 1f
                    : Clamp(
                        1f - (age - (float)HitNumberTotalAccumulator.QuietSeconds)
                            / (float)HitNumberTotalAccumulator.FadeSeconds,
                        0f,
                        1f);
                float width = 156f;
                float height = 32f;
                float left = Clamp(
                    target.X - width / 2f,
                    StageMarginForTests,
                    StageWidth - StageMarginForTests - width);
                float top = Clamp(
                    target.Y - 78f,
                    StageMarginForTests,
                    StageHeight - StageMarginForTests - height);
                string attributes = BuildTotalAttributeSummary(entry, 4);
                var row = new HitNumberBurstRow
                {
                    TargetId = entry.TargetId,
                    BurstId = "#total",
                    TargetX = target.X,
                    TargetY = target.Y,
                    Bounds = new RectangleF(left, top, width, height),
                    AttachmentX = target.X,
                    AttachmentY = top + height,
                    GrowthDirection = 0,
                    TotalDamage = entry.TotalDamage,
                    HitCount = entry.HitCount,
                    ExpectedHitCount = entry.ExpectedHitCount,
                    FirstSequence = entry.FirstSequence,
                    FirstArrivalSeconds = entry.FirstArrivalSeconds,
                    LastArrivalSeconds = entry.LastArrivalSeconds,
                    AttributeSummary = attributes,
                    Alpha = alpha
                };
                frame.WorldRows.Add(row);
                int packed = HitNumberPacking.WithFontSize(entry.Packed, BalancedFontSize);
                frame.Items.Add(new HitNumberPaintItem
                {
                    StageX = left + width / 2f,
                    StageY = top + TotalImpactLift(age),
                    CombinedScale = TotalImpactScale(age, entry.HitCount),
                    Alpha = alpha,
                    CombinedBlur = age < 0.10f ? 3.8f : 2.8f,
                    Damage = ClampLongToInt(entry.DisplayDamage),
                    Packed = packed,
                    EffectText = entry.EffectText,
                    CrushText = entry.CrushText,
                    CrushEmoji = entry.CrushEmoji,
                    LifeSteal = entry.LifeSteal,
                    ShieldAbsorb = entry.ShieldAbsorb,
                    HitCount = entry.DisplayHitCount,
                    FlagScales = entry.FlagScales,
                    MainColorOverride = Color.FromArgb(
                        entry.DisplayR,
                        entry.DisplayG,
                        entry.DisplayB),
                    EffectTextColorOverride = HitNumberPainter.ResolveColorId(
                        entry.EffectTextColorId),
                    SourceSequence = entry.FirstSequence,
                    SourceBurstId = "#total",
                    SourceTargetId = entry.TargetId,
                    SourceTargetX = target.X,
                    SourceTargetY = target.Y,
                    VisualRole = HitNumberVisualRole.Summary
                });
                frame.SummaryItemCount++;
            }
            return frame;
        }

        private static string BuildTotalAttributeSummary(
            HitNumberTotalEntry entry,
            int maximumLabels)
        {
            int flags = HitNumberPacking.Flags(entry.Packed);
            var labels = new List<string>(7);
            var seen = new HashSet<string>(StringComparer.Ordinal);
            if ((flags & 8) != 0 && !string.IsNullOrWhiteSpace(entry.EffectText))
                AddLabel(labels, seen, entry.EffectText.Trim());
            if ((flags & 16) != 0)
            {
                string crush = string.IsNullOrWhiteSpace(entry.CrushText)
                    ? "粉"
                    : entry.CrushText.Trim();
                AddLabel(labels, seen, crush);
            }
            if ((flags & 2) != 0) AddLabel(labels, seen, "毒");
            if ((flags & 1) != 0) AddLabel(labels, seen, "溃");
            if ((flags & 4) != 0) AddLabel(labels, seen, "斩");
            if ((flags & 32) != 0 && entry.LifeSteal > 0) AddLabel(labels, seen, "汲");
            if ((flags & 256) != 0 && entry.ShieldAbsorb > 0) AddLabel(labels, seen, "盾");
            if (labels.Count == 0) return string.Empty;
            int take = Math.Min(maximumLabels, labels.Count);
            string value = string.Join("·", labels.GetRange(0, take));
            if (take < labels.Count)
                value += "＋" + (labels.Count - take).ToString(CultureInfo.InvariantCulture);
            return value;
        }

        /// <summary>
        /// 把一次攻击的逐段事实投影成平衡模式的一条紧凑视觉。语义沿用旧总伤：
        /// 主数字先显示最新段来源色，再回落到伤害贡献占优色；属性文字保持自己的
        /// 来源色；标准效果保留独立颜色、精确数值和贡献强度。逐发事实仍由行数据
        /// 与 LedgerStore 保存，此处只负责世界层投影。
        /// </summary>
        private static BurstVisualProjection BuildBurstVisualProjection(BurstSlice burst)
        {
            Span<long> flagDamageSums = stackalloc long[EffectFlagCount];
            Span<double> latestFlagAges = stackalloc double[EffectFlagCount];
            Span<int> latestFlagSequences = stackalloc int[EffectFlagCount];
            Span<long> colorDamageSums = stackalloc long[ColorCount];
            for (int bit = 0; bit < EffectFlagCount; bit++)
            {
                latestFlagAges[bit] = double.MaxValue;
                latestFlagSequences[bit] = int.MinValue;
            }

            int flags = 0;
            int latestColorId = 0;
            double latestAge = double.MaxValue;
            int latestSequence = int.MinValue;
            string effectText = string.Empty;
            int effectTextColorId = 0;
            double effectTextAge = double.MaxValue;
            int effectTextSequence = int.MinValue;
            string crushText = string.Empty;
            string crushEmoji = string.Empty;
            double crushAge = double.MaxValue;
            int crushSequence = int.MinValue;
            float lifeSteal = 0f;
            float shieldAbsorb = 0f;
            bool hasNonMiss = false;

            for (int i = 0; i < burst.Segments.Count; i++)
            {
                ActiveSegment active = burst.Segments[i];
                HitNumberSegment segment = active.Segment;
                if (HitNumberPacking.IsMiss(segment.Packed)) continue;
                hasNonMiss = true;

                int segmentFlags = HitNumberPacking.Flags(segment.Packed);
                flags |= segmentFlags;
                for (int bit = 0; bit < EffectFlagCount; bit++)
                {
                    if ((segmentFlags & (1 << bit)) == 0) continue;
                    flagDamageSums[bit] = SaturatingLongAdd(
                        flagDamageSums[bit],
                        segment.Damage);
                    if (IsNewerVisualSample(
                        active.AgeSeconds,
                        segment.Sequence,
                        latestFlagAges[bit],
                        latestFlagSequences[bit]))
                    {
                        latestFlagAges[bit] = active.AgeSeconds;
                        latestFlagSequences[bit] = segment.Sequence;
                    }
                }

                int colorId = (segment.Packed >> 18) & 15;
                if (colorId >= 0 && colorId < ColorCount)
                {
                    colorDamageSums[colorId] = SaturatingLongAdd(
                        colorDamageSums[colorId],
                        segment.Damage);
                }
                if (IsNewerVisualSample(
                    active.AgeSeconds,
                    segment.Sequence,
                    latestAge,
                    latestSequence))
                {
                    latestAge = active.AgeSeconds;
                    latestSequence = segment.Sequence;
                    latestColorId = colorId;
                }

                string text = string.IsNullOrWhiteSpace(segment.EffectText)
                    ? string.Empty
                    : segment.EffectText.Trim();
                if ((segmentFlags & 8) != 0 && text.Length > 0 &&
                    IsNewerVisualSample(
                        active.AgeSeconds,
                        segment.Sequence,
                        effectTextAge,
                        effectTextSequence))
                {
                    effectText = text;
                    effectTextColorId = colorId;
                    effectTextAge = active.AgeSeconds;
                    effectTextSequence = segment.Sequence;
                }
                if ((segmentFlags & 16) != 0 &&
                    IsNewerVisualSample(
                        active.AgeSeconds,
                        segment.Sequence,
                        crushAge,
                        crushSequence))
                {
                    crushText = text.Length == 0 ? "粉" : text;
                    crushEmoji = string.IsNullOrWhiteSpace(segment.EffectEmoji)
                        ? string.Empty
                        : segment.EffectEmoji.Trim();
                    crushAge = active.AgeSeconds;
                    crushSequence = segment.Sequence;
                }
                if (segment.LifeSteal > 0)
                    lifeSteal = SaturatingFloatAdd(lifeSteal, segment.LifeSteal);
                if (segment.ShieldAbsorb > 0)
                    shieldAbsorb = SaturatingFloatAdd(shieldAbsorb, segment.ShieldAbsorb);
            }

            string attributeSummary = BuildAttributeSummary(
                burst.Segments,
                int.MaxValue);
            if (!hasNonMiss)
            {
                Color fallback = HitNumberPainter.ResolveMainColor(
                    burst.Segments[0].Segment.Packed);
                return new BurstVisualProjection(
                    0,
                    fallback,
                    fallback,
                    string.Empty,
                    string.Empty,
                    string.Empty,
                    0f,
                    0f,
                    "000000000",
                    attributeSummary);
            }

            int dominantColorId = 0;
            long bestDamage = 0;
            for (int colorId = 0; colorId < ColorCount; colorId++)
            {
                if (colorDamageSums[colorId] <= bestDamage) continue;
                bestDamage = colorDamageSums[colorId];
                dominantColorId = colorId;
            }
            // 0/负伤（常见于纯盾或特殊反馈）没有正贡献主体，必须保持最新
            // non-MISS 段的来源色；否则默认 dominant=0 会让数字逐帧漂白。
            if (bestDamage <= 0) dominantColorId = latestColorId;
            Color latestColor = HitNumberPainter.ResolveColorId(latestColorId);
            Color dominantColor = HitNumberPainter.ResolveColorId(dominantColorId);
            int elapsedFrames = Math.Min(
                64,
                Math.Max(0, (int)Math.Floor(latestAge * 24.0 + 1e-9)));
            float latestRetention = (float)Math.Pow(
                ColorDecayRetention,
                elapsedFrames);
            Color mainColor = Color.FromArgb(
                BlendChannel(dominantColor.R, latestColor.R, latestRetention),
                BlendChannel(dominantColor.G, latestColor.G, latestRetention),
                BlendChannel(dominantColor.B, latestColor.B, latestRetention));
            string flagScales = BuildBurstFlagScales(
                flags,
                burst.TotalDamage,
                flagDamageSums,
                latestFlagAges);

            return new BurstVisualProjection(
                flags,
                mainColor,
                HitNumberPainter.ResolveColorId(effectTextColorId),
                effectText,
                crushText,
                crushEmoji,
                lifeSteal,
                shieldAbsorb,
                flagScales,
                attributeSummary);
        }

        private static string BuildBurstFlagScales(
            int flags,
            long totalDamage,
            ReadOnlySpan<long> flagDamageSums,
            ReadOnlySpan<double> latestFlagAges)
        {
            Span<char> encoded = stackalloc char[EffectFlagCount];
            for (int bit = 0; bit < EffectFlagCount; bit++)
            {
                if ((flags & (1 << bit)) == 0)
                {
                    encoded[bit] = '0';
                    continue;
                }

                float target = 1f;
                if (totalDamage > 0)
                {
                    if (bit == ExecuteFlagBit)
                    {
                        target = flagDamageSums[bit] > 0 ? 1f : 0f;
                    }
                    else
                    {
                        double ratio = flagDamageSums[bit] / (double)totalDamage;
                        if (ratio < FlagVisibilityFloor) target = 0f;
                        else if (ratio >= FlagVisibilityCeiling) target = 1f;
                        else target = (float)((ratio - FlagVisibilityFloor) /
                            (FlagVisibilityCeiling - FlagVisibilityFloor));
                    }
                }

                int elapsedFrames = Math.Min(
                    64,
                    Math.Max(0, (int)Math.Floor(latestFlagAges[bit] * 24.0 + 1e-9)));
                float transient = Math.Max(0f, 1f - elapsedFrames * FlagDecayStep);
                float scale = Math.Max(target, transient);
                int level = scale < 0.02f
                    ? 0
                    : (int)Math.Floor(scale * 9f + 0.5f);
                encoded[bit] = (char)('0' + Math.Max(0, Math.Min(9, level)));
            }
            return new string(encoded);
        }

        private static bool IsNewerVisualSample(
            double candidateAge,
            int candidateSequence,
            double currentAge,
            int currentSequence)
        {
            return candidateAge < currentAge ||
                (candidateAge == currentAge && candidateSequence > currentSequence);
        }

        private static byte BlendChannel(byte target, byte source, float sourceWeight)
        {
            float value = target + (source - target) * Clamp(sourceWeight, 0f, 1f);
            return (byte)Math.Max(0, Math.Min(255, (int)Math.Floor(value + 0.5f)));
        }

        private static long SaturatingLongAdd(long left, int right)
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
            return (float)sum;
        }

        private static List<BurstSlice> BuildBurstSlices(
            List<ActiveSegment> group,
            string targetId)
        {
            var slices = new List<BurstSlice>();
            var byId = new Dictionary<BurstIdentity, BurstSlice>();
            for (int i = 0; i < group.Count; i++)
            {
                ActiveSegment active = group[i];
                string sourceId = active.Segment.BurstId;
                string displayId = string.IsNullOrEmpty(sourceId)
                    ? "#segment:" + active.Segment.Sequence.ToString(CultureInfo.InvariantCulture)
                    : sourceId;
                var identity = new BurstIdentity(targetId, active.Segment);
                if (!byId.TryGetValue(identity, out BurstSlice slice))
                {
                    slice = new BurstSlice(displayId, targetId, active);
                    byId.Add(identity, slice);
                    slices.Add(slice);
                }
                slice.Add(active);
            }
            return slices;
        }

        private static void TranslateStackIntoStage(
            List<HitNumberBurstRow> rows,
            List<HitNumberPaintItem> items)
        {
            if (rows.Count == 0) return;
            float top = float.MaxValue;
            float bottom = float.MinValue;
            for (int i = 0; i < rows.Count; i++)
            {
                top = Math.Min(top, rows[i].Bounds.Top);
                bottom = Math.Max(bottom, rows[i].Bounds.Bottom);
            }

            float deltaY = 0f;
            if (top < StageMarginForTests) deltaY = StageMarginForTests - top;
            if (bottom + deltaY > StageHeight - StageMarginForTests)
                deltaY -= bottom + deltaY - (StageHeight - StageMarginForTests);
            if (Math.Abs(deltaY) < 0.001f) return;

            for (int i = 0; i < rows.Count; i++)
            {
                HitNumberBurstRow row = rows[i];
                row.Bounds = new RectangleF(
                    row.Bounds.X,
                    row.Bounds.Y + deltaY,
                    row.Bounds.Width,
                    row.Bounds.Height);
                row.AttachmentY += deltaY;
            }
            for (int i = 0; i < items.Count; i++) items[i].StageY += deltaY;
        }

        private static string BuildAttributeSummary(
            IReadOnlyList<ActiveSegment> segments,
            int maximumLabels)
        {
            var labels = new List<string>();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            for (int i = 0; i < segments.Count; i++)
            {
                HitNumberSegment segment = segments[i].Segment;
                int flags = HitNumberPacking.Flags(segment.Packed);
                if ((flags & 8) != 0 && !string.IsNullOrWhiteSpace(segment.EffectText))
                    AddLabel(labels, seen, segment.EffectText.Trim());
                if ((flags & 16) != 0)
                {
                    string crush = string.IsNullOrWhiteSpace(segment.EffectText)
                        ? "粉"
                        : segment.EffectText.Trim();
                    AddLabel(labels, seen, crush);
                }
                if ((flags & 2) != 0) AddLabel(labels, seen, "毒");
                if ((flags & 1) != 0) AddLabel(labels, seen, "溃");
                if ((flags & 4) != 0) AddLabel(labels, seen, "斩");
                if ((flags & 32) != 0 && segment.LifeSteal > 0) AddLabel(labels, seen, "汲");
                if ((flags & 256) != 0 && segment.ShieldAbsorb > 0) AddLabel(labels, seen, "盾");
            }

            if (labels.Count == 0) return string.Empty;
            int take = Math.Min(maximumLabels, labels.Count);
            string value = string.Join("·", labels.GetRange(0, take));
            if (take < labels.Count) value += "＋" + (labels.Count - take).ToString(CultureInfo.InvariantCulture);
            return value;
        }

        private static void AddLabel(
            List<string> labels,
            HashSet<string> seen,
            string value)
        {
            if (!string.IsNullOrEmpty(value) && seen.Add(value)) labels.Add(value);
        }

        private static float BurstAlpha(BurstSlice burst)
        {
            double newestProgress = 1.0;
            for (int i = 0; i < burst.Segments.Count; i++)
                newestProgress = Math.Min(newestProgress, burst.Segments[i].Progress01);
            float retention = newestProgress <= 0.80
                ? 1f
                : (float)Math.Max(0.18, (1.0 - newestProgress) / 0.20);
            return retention;
        }

        private static float BurstImpactScale(BurstSlice burst)
        {
            double newestAge = double.MaxValue;
            for (int i = 0; i < burst.Segments.Count; i++)
                newestAge = Math.Min(newestAge, burst.Segments[i].AgeSeconds);
            return ImpactScale(newestAge);
        }

        private static float BurstImpactLift(BurstSlice burst)
        {
            double newestAge = double.MaxValue;
            for (int i = 0; i < burst.Segments.Count; i++)
                newestAge = Math.Min(newestAge, burst.Segments[i].AgeSeconds);
            return ImpactLift(newestAge);
        }

        private static float ImpactScale(double ageSeconds)
        {
            float age = (float)Math.Max(0.0, ageSeconds);
            if (age < 0.055f) return Lerp(1.46f, 1.08f, age / 0.055f);
            if (age < 0.13f) return Lerp(1.08f, 0.96f, (age - 0.055f) / 0.075f);
            if (age < 0.22f) return Lerp(0.96f, 1f, (age - 0.13f) / 0.09f);
            return 1f;
        }

        private static float ImpactLift(double ageSeconds)
        {
            float age = (float)Math.Max(0.0, ageSeconds);
            if (age < 0.08f) return Lerp(6f, -8f, age / 0.08f);
            return -8f - Math.Min(1f, (age - 0.08f) / 0.30f) * 7f;
        }

        private static float TotalImpactLift(float age)
        {
            return age < 0.12f ? Lerp(6f, -7f, age / 0.12f) : -7f;
        }

        private static float TotalImpactScale(float age, int hitCount)
        {
            // 旧总伤使用“frame rewind + 6 帧 pulse”双反馈。20px 基准下完整旧峰值
            // 接近 40px，会重新引入已经由人工否决的大字号；保留双阶段曲线与持续
            // 命中的打击感，同时把短峰限制在 1.62×，稳态仍严格回到 1.0×。
            float virtualFrame = Math.Max(0f, age) * 24f;
            int startFrame = hitCount > 1 ? 3 : 0;
            int frame = Math.Min(7, startFrame + (int)Math.Floor(virtualFrame));
            float pulse = virtualFrame < 6f
                ? 1f + 0.5f * (1f - virtualFrame / 6f)
                : 1f;
            return Math.Min(1.62f, ClassicScale[frame] * pulse);
        }

        private static float StableClassicOffset(int sequence, uint salt)
        {
            uint value = unchecked((uint)sequence) ^ salt;
            value ^= value >> 16;
            value *= 0x7FEB352Du;
            value ^= value >> 15;
            value *= 0x846CA68Bu;
            value ^= value >> 16;
            float unit = (value & 0x00FFFFFFu) / 16777215f;
            return (unit * 2f - 1f) * ClassicPositionOffset;
        }

        private static int SaturatingCountAdd(int left, int right)
        {
            if (right > 0 && left > int.MaxValue - right) return int.MaxValue;
            return left + right;
        }

        private static float Lerp(float left, float right, float progress)
        {
            return left + (right - left) * Clamp(progress, 0f, 1f);
        }

        private static void EvaluateStructuredMetrics(HitNumberLayoutFrame frame)
        {
            var rows = new Dictionary<string, HitNumberBurstRow>(StringComparer.Ordinal);
            for (int i = 0; i < frame.WorldRows.Count; i++)
            {
                HitNumberBurstRow row = frame.WorldRows[i];
                rows[RowKey(row.TargetId, row.BurstId, row.FirstSequence)] = row;
            }

            for (int i = 0; i < frame.Items.Count; i++)
            {
                HitNumberPaintItem item = frame.Items[i];
                string key = RowKey(item.SourceTargetId, item.SourceBurstId, item.SourceSequence);
                if (!rows.TryGetValue(key, out _))
                {
                    frame.CausalOwnershipViolationCount++;
                    continue;
                }
            }
        }

        private static string RowKey(string targetId, string burstId, int sequence)
        {
            string normalizedBurst = string.IsNullOrEmpty(burstId)
                ? "#segment:" + sequence.ToString(CultureInfo.InvariantCulture)
                : burstId;
            return targetId + "\u001F" + normalizedBurst;
        }

        internal static RectangleF EstimateItemBounds(HitNumberPaintItem item)
        {
            return EstimateItemBoundsCore(
                item.StageX,
                item.StageY,
                item.CombinedScale,
                item.CombinedBlur,
                item.Damage,
                item.Packed,
                item.EffectText,
                item.EffectEmoji,
                item.CrushText,
                item.CrushEmoji,
                item.LifeSteal,
                item.ShieldAbsorb,
                item.HitCount,
                item.FlagScales,
                item.SemanticDensityScale);
        }

        private static RectangleF EstimateDetailBounds(
            ActiveSegment active,
            int fontSize,
            float combinedScale)
        {
            HitNumberSegment segment = active.Segment;
            return EstimateItemBoundsCore(
                active.StageX,
                active.StageY,
                combinedScale,
                2.0f,
                segment.Damage,
                HitNumberPacking.WithFontSize(segment.Packed, fontSize),
                segment.EffectText,
                segment.EffectEmoji,
                string.Empty,
                string.Empty,
                segment.LifeSteal,
                segment.ShieldAbsorb,
                1,
                "999999999",
                1f / 3f);
        }

        private static RectangleF EstimateItemBoundsCore(
            float stageX,
            float stageY,
            float combinedScale,
            float combinedBlur,
            int damage,
            int packed,
            string effectText,
            string effectEmoji,
            string crushText,
            string crushEmoji,
            float lifeSteal,
            float shieldAbsorb,
            int hitCount,
            string flagScales,
            float semanticDensityScale)
        {
            int size = HitNumberPacking.FontSize(packed);
            // Painter 使用 point 字体；在常见 96-120 DPI 下，字形像素高于同值的
            // Flash 舞台像素。这里以保守 em 估算完整数字、标签、hit 上标和描边，
            // 避免 tight layered-window surface 把真实字形裁掉。
            float visualSize = Math.Max(8f, Math.Min(72f, size * combinedScale));
            float mainEm = visualSize * 1.60f;
            int mainGlyphCount = HitNumberPacking.IsMiss(packed)
                ? 4
                : SignedDigitCount(damage);
            float width = EstimateRunWidth(mainGlyphCount, mainEm, 0.82f) + 8f;
            float maximumEm = mainEm;
            int flags = HitNumberPacking.Flags(packed);
            float labelVisualSize = Math.Max(4f, Math.Min(40f, 20f * combinedScale));
            float densityScale = Clamp(semanticDensityScale, 0f, 1f);
            if ((flags & 8) != 0 && !string.IsNullOrEmpty(effectText))
                AddEstimatedLabel(ref width, ref maximumEm, effectText.Length + 1,
                    labelVisualSize, EstimateFlagScale(flagScales, 3) * densityScale);
            string resolvedCrushText = string.IsNullOrEmpty(crushText)
                ? effectText
                : crushText;
            string resolvedCrushEmoji = string.IsNullOrEmpty(crushEmoji)
                ? effectEmoji
                : crushEmoji;
            if ((flags & 16) != 0 && !string.IsNullOrEmpty(resolvedCrushText))
                AddEstimatedLabel(ref width, ref maximumEm,
                    1 + (resolvedCrushEmoji == null ? 0 : resolvedCrushEmoji.Length)
                        + resolvedCrushText.Length,
                    labelVisualSize, EstimateFlagScale(flagScales, 4) * densityScale);
            if ((flags & 2) != 0)
                AddEstimatedLabel(ref width, ref maximumEm, 2,
                    labelVisualSize, EstimateFlagScale(flagScales, 1) * densityScale);
            if ((flags & 32) != 0 && lifeSteal > 0)
                AddEstimatedLabel(ref width, ref maximumEm,
                    3 + SignedDigitCount((int)lifeSteal),
                    Math.Max(4f, Math.Min(30f, 15f * combinedScale)),
                    EstimateFlagScale(flagScales, 5) * densityScale);
            if ((flags & 1) != 0)
                AddEstimatedLabel(ref width, ref maximumEm, 2,
                    labelVisualSize, EstimateFlagScale(flagScales, 0) * densityScale);
            if ((flags & 4) != 0)
                AddEstimatedLabel(ref width, ref maximumEm, 2,
                    labelVisualSize, EstimateFlagScale(flagScales, 2) * densityScale);
            if ((flags & 256) != 0 && shieldAbsorb > 0)
                AddEstimatedLabel(ref width, ref maximumEm,
                    3 + SignedDigitCount((int)shieldAbsorb),
                    Math.Max(4f, Math.Min(36f, 18f * combinedScale)),
                    EstimateFlagScale(flagScales, 8) * densityScale);
            if (hitCount > 1)
            {
                float hitNumberEm = mainEm * 0.55f;
                float hitExtra = 6f
                    + EstimateRunWidth(SignedDigitCount(hitCount), hitNumberEm, 0.82f)
                    + EstimateRunWidth(3, hitNumberEm * 0.5f, 0.72f);
                // hit 上标从已居中的正文右缘继续绘制；用双倍余量把非对称尾部
                // 包进以 StageX 为中心的估算矩形。
                width += hitExtra * 2f;
                maximumEm = Math.Max(maximumEm, hitNumberEm);
            }
            float outline = Math.Max(2f, combinedBlur * 1.2f) + 4f;
            float topExtent = mainEm * 0.52f + outline;
            float bottomExtent = maximumEm * 1.28f + outline;
            return new RectangleF(
                stageX - width / 2f,
                stageY - topExtent,
                width,
                topExtent + bottomExtent);
        }

        private static void AddEstimatedLabel(
            ref float width,
            ref float maximumEm,
            int glyphCount,
            float pointSize,
            float scale)
        {
            if (scale <= 0f || glyphCount <= 0) return;
            float em = Math.Max(4f, Math.Min(40f, pointSize * scale)) * 1.60f;
            width += EstimateRunWidth(glyphCount, em, 1f);
            maximumEm = Math.Max(maximumEm, em);
        }

        private static float EstimateRunWidth(int glyphCount, float em, float glyphRatio)
        {
            return glyphCount <= 0 ? 0f : glyphCount * em * glyphRatio;
        }

        private static int SignedDigitCount(int value)
        {
            long magnitude = value;
            int digits = magnitude < 0 ? 1 : 0;
            if (magnitude < 0) magnitude = -magnitude;
            do
            {
                digits++;
                magnitude /= 10;
            } while (magnitude > 0);
            return digits;
        }

        private static float EstimateFlagScale(string levels, int bit)
        {
            if (string.IsNullOrEmpty(levels) || levels.Length != 9) return 1f;
            int level = levels[bit] - '0';
            if (level <= 0) return 0f;
            return level >= 9 ? 1f : level / 9f;
        }

        private static int PerTargetWorldRowLimit(
            HitNumberLayoutCandidate candidate,
            int worldRowLimit)
        {
            if (candidate == HitNumberLayoutCandidate.BalancedSummary)
                return BalancedRowsPerTarget;
            if (candidate == HitNumberLayoutCandidate.FixedBurstStack && worldRowLimit > 0)
                return LimitedDetailRowsPerTarget;
            return 0;
        }

        private static float EstimateOverlapRatio(IReadOnlyList<HitNumberPaintItem> items)
        {
            if (items.Count < 2) return 0f;
            float totalArea = 0f;
            float overlapArea = 0f;
            var bounds = new RectangleF[items.Count];
            for (int i = 0; i < items.Count; i++)
            {
                bounds[i] = EstimateItemBounds(items[i]);
                totalArea += bounds[i].Width * bounds[i].Height;
            }
            for (int i = 0; i < bounds.Length; i++)
            {
                for (int j = i + 1; j < bounds.Length; j++)
                    overlapArea += IntersectionArea(bounds[i], bounds[j]);
            }
            return totalArea <= 0f ? 0f : Math.Min(1f, overlapArea / totalArea);
        }

        private static float IntersectionArea(RectangleF a, RectangleF b)
        {
            RectangleF intersection = RectangleF.Intersect(a, b);
            return intersection.IsEmpty ? 0f : intersection.Width * intersection.Height;
        }

        private static bool IsTargetOnscreen(float x, float y)
        {
            const float margin = 100f;
            return x >= -margin && x <= StageWidth + margin &&
                y >= -margin && y <= StageHeight + margin;
        }

        private static string TargetKey(HitNumberSegment segment)
        {
            return string.IsNullOrEmpty(segment.TargetId)
                ? "@" + segment.TargetX.ToString("0.###", CultureInfo.InvariantCulture) +
                  ":" + segment.TargetY.ToString("0.###", CultureInfo.InvariantCulture)
                : segment.TargetId;
        }

        private static int CompareActive(ActiveSegment left, ActiveSegment right)
        {
            int arrival = left.Segment.ArrivalSeconds.CompareTo(right.Segment.ArrivalSeconds);
            return arrival != 0 ? arrival : left.Segment.Sequence.CompareTo(right.Segment.Sequence);
        }

        private static int CompareBurst(BurstSlice left, BurstSlice right)
        {
            int arrival = left.FirstArrivalSeconds.CompareTo(right.FirstArrivalSeconds);
            return arrival != 0 ? arrival : left.FirstSequence.CompareTo(right.FirstSequence);
        }

        private static bool IsActiveSorted(List<ActiveSegment> segments)
        {
            for (int i = 1; i < segments.Count; i++)
            {
                if (CompareActive(segments[i - 1], segments[i]) > 0) return false;
            }
            return true;
        }

        private static bool IsSourceChronological(
            IReadOnlyList<HitNumberSegment> source,
            int startIndex)
        {
            for (int i = startIndex + 1; i < source.Count; i++)
            {
                HitNumberSegment previous = source[i - 1];
                HitNumberSegment current = source[i];
                int arrival = previous.ArrivalSeconds.CompareTo(current.ArrivalSeconds);
                if (arrival > 0 || (arrival == 0 && previous.Sequence > current.Sequence))
                    return false;
            }
            return true;
        }

        private static bool IsBurstSorted(List<BurstSlice> bursts)
        {
            for (int i = 1; i < bursts.Count; i++)
            {
                if (CompareBurst(bursts[i - 1], bursts[i]) > 0) return false;
            }
            return true;
        }

        private static int ClampLongToInt(long value)
        {
            return value > int.MaxValue
                ? int.MaxValue
                : value < int.MinValue ? int.MinValue : (int)value;
        }

        private static float Clamp(float value, float minimum, float maximum)
        {
            return Math.Max(minimum, Math.Min(value, maximum));
        }

        private readonly struct BurstVisualProjection
        {
            internal BurstVisualProjection(
                int flags,
                Color mainColor,
                Color effectTextColor,
                string effectText,
                string crushText,
                string crushEmoji,
                float lifeSteal,
                float shieldAbsorb,
                string flagScales,
                string attributeSummary)
            {
                Flags = flags;
                MainColor = mainColor;
                EffectTextColor = effectTextColor;
                EffectText = effectText ?? string.Empty;
                CrushText = crushText ?? string.Empty;
                CrushEmoji = crushEmoji ?? string.Empty;
                LifeSteal = lifeSteal;
                ShieldAbsorb = shieldAbsorb;
                FlagScales = flagScales ?? "000000000";
                AttributeSummary = attributeSummary ?? string.Empty;
            }

            internal int Flags { get; }
            internal Color MainColor { get; }
            internal Color EffectTextColor { get; }
            internal string EffectText { get; }
            internal string CrushText { get; }
            internal string CrushEmoji { get; }
            internal float LifeSteal { get; }
            internal float ShieldAbsorb { get; }
            internal string FlagScales { get; }
            internal string AttributeSummary { get; }
        }

        private sealed class BurstSlice
        {
            private BurstVisualProjection? _visualProjection;

            internal BurstSlice(string id, string targetId, ActiveSegment first)
            {
                Id = id;
                TargetId = targetId;
                TargetX = first.StageX;
                TargetY = first.StageY;
                FirstSequence = first.Segment.Sequence;
                FirstArrivalSeconds = first.Segment.ArrivalSeconds;
                LastArrivalSeconds = first.Segment.ArrivalSeconds;
                LastSequence = first.Segment.Sequence;
                ExpectedHitCount = Math.Max(1, first.Segment.ExpectedBurstHitCount);
            }

            internal string Id { get; }
            internal string TargetId { get; }
            internal float TargetX { get; private set; }
            internal float TargetY { get; private set; }
            internal int FirstSequence { get; private set; }
            internal double FirstArrivalSeconds { get; private set; }
            internal double LastArrivalSeconds { get; private set; }
            internal int LastSequence { get; private set; }
            internal int ExpectedHitCount { get; private set; }
            internal long TotalDamage { get; private set; }
            internal List<ActiveSegment> Segments { get; } = new List<ActiveSegment>();
            internal BurstVisualProjection VisualProjection
            {
                get
                {
                    if (!_visualProjection.HasValue)
                        _visualProjection = BuildBurstVisualProjection(this);
                    return _visualProjection.Value;
                }
            }

            internal void Add(ActiveSegment active)
            {
                _visualProjection = null;
                Segments.Add(active);
                TotalDamage += active.Segment.Damage;
                ExpectedHitCount = Math.Max(
                    ExpectedHitCount,
                    Math.Max(Segments.Count, active.Segment.ExpectedBurstHitCount));
                if (active.Segment.ArrivalSeconds < FirstArrivalSeconds)
                {
                    FirstArrivalSeconds = active.Segment.ArrivalSeconds;
                    FirstSequence = active.Segment.Sequence;
                }
                if (active.Segment.ArrivalSeconds > LastArrivalSeconds ||
                    (active.Segment.ArrivalSeconds == LastArrivalSeconds &&
                     active.Segment.Sequence >= LastSequence))
                {
                    LastArrivalSeconds = active.Segment.ArrivalSeconds;
                    LastSequence = active.Segment.Sequence;
                    TargetX = active.StageX;
                    TargetY = active.StageY;
                }
            }
        }

        private sealed class BurstOldestFirstComparer : IComparer<BurstSlice>
        {
            internal static readonly BurstOldestFirstComparer Instance =
                new BurstOldestFirstComparer();

            public int Compare(BurstSlice left, BurstSlice right)
            {
                if (ReferenceEquals(left, right)) return 0;
                if (left == null) return -1;
                if (right == null) return 1;
                int arrival = left.LastArrivalSeconds.CompareTo(right.LastArrivalSeconds);
                return arrival != 0
                    ? arrival
                    : left.LastSequence.CompareTo(right.LastSequence);
            }
        }

        private readonly struct BurstIdentity : IEquatable<BurstIdentity>
        {
            internal BurstIdentity(string targetId, HitNumberSegment segment)
            {
                TargetId = targetId ?? string.Empty;
                BurstId = segment.BurstId ?? string.Empty;
                SyntheticSequence = BurstId.Length == 0 ? segment.Sequence : -1;
            }

            private string TargetId { get; }
            private string BurstId { get; }
            private int SyntheticSequence { get; }

            public bool Equals(BurstIdentity other)
            {
                return SyntheticSequence == other.SyntheticSequence &&
                    string.Equals(TargetId, other.TargetId, StringComparison.Ordinal) &&
                    string.Equals(BurstId, other.BurstId, StringComparison.Ordinal);
            }

            public override bool Equals(object value)
            {
                return value is BurstIdentity other && Equals(other);
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

        private readonly struct RowSpec
        {
            private RowSpec(
                float width,
                float height,
                float summaryWidth,
                float detailCellWidth,
                float detailLineHeight,
                float topPadding,
                float horizontalPadding,
                int detailColumns,
                int detailFontSize,
                int summaryFontSize)
            {
                Width = width;
                Height = height;
                SummaryWidth = summaryWidth;
                DetailCellWidth = detailCellWidth;
                DetailLineHeight = detailLineHeight;
                TopPadding = topPadding;
                HorizontalPadding = horizontalPadding;
                DetailColumns = detailColumns;
                DetailFontSize = detailFontSize;
                SummaryFontSize = summaryFontSize;
            }

            internal float Width { get; }
            internal float Height { get; }
            internal float SummaryWidth { get; }
            internal float DetailCellWidth { get; }
            internal float DetailLineHeight { get; }
            internal float TopPadding { get; }
            internal float HorizontalPadding { get; }
            internal int DetailColumns { get; }
            internal int DetailFontSize { get; }
            internal int SummaryFontSize { get; }

            internal static RowSpec Create(BurstSlice burst, bool includeWorldDetails)
            {
                int segmentCount = Math.Max(1, burst.ExpectedHitCount);
                if (!includeWorldDetails)
                {
                    return new RowSpec(
                        148f,
                        29f,
                        136f,
                        0f,
                        0f,
                        4f,
                        6f,
                        1,
                        0,
                        BalancedFontSize);
                }

                if (segmentCount <= 1)
                {
                    const int singleFont = 14;
                    float singleWidth = 116f;
                    if (burst.Segments.Count > 0)
                    {
                        singleWidth = Math.Max(
                            singleWidth,
                            EstimateDetailBounds(
                                burst.Segments[0],
                                singleFont,
                                1.46f).Width + 10f);
                    }
                    return new RowSpec(
                        Math.Min(StageWidth - StageMarginForTests * 2f, singleWidth),
                        22f,
                        0f,
                        singleWidth,
                        18f,
                        2f,
                        4f,
                        1,
                        singleFont,
                        0);
                }

                int columns;
                float minimumCellWidth;
                float lineHeight;
                int detailFont;
                if (segmentCount <= 4)
                {
                    columns = segmentCount;
                    minimumCellWidth = 46f;
                    lineHeight = 18f;
                    detailFont = 12;
                }
                else if (segmentCount <= 8)
                {
                    columns = 3;
                    minimumCellWidth = 46f;
                    lineHeight = 18f;
                    detailFont = 12;
                }
                else if (segmentCount <= 16)
                {
                    columns = 6;
                    minimumCellWidth = 40f;
                    lineHeight = 17f;
                    detailFont = 11;
                }
                else if (segmentCount <= 40)
                {
                    columns = 8;
                    minimumCellWidth = 35f;
                    lineHeight = 16f;
                    detailFont = 10;
                }
                else
                {
                    columns = 12;
                    minimumCellWidth = 29f;
                    lineHeight = 15f;
                    detailFont = 9;
                }

                // 固定 29-46px 单元只能容纳三位数；五位以上再带“热/毒”等标签时
                // 相邻逐段项会真实相交。用生产 Painter 的保守边界为本 Burst 选择
                // 统一单元宽度，并在舞台宽度不足时减少列数、增加行数。这样不截断
                // 数字，也不改变任何逐段值或属性。
                float cellWidth = minimumCellWidth;
                float requiredLineHeight = lineHeight;
                for (int i = 0; i < burst.Segments.Count; i++)
                {
                    RectangleF sampleBounds = EstimateDetailBounds(
                        burst.Segments[i],
                        detailFont,
                        1.46f);
                    cellWidth = Math.Max(
                        cellWidth,
                        sampleBounds.Width + 8f);
                    requiredLineHeight = Math.Max(
                        requiredLineHeight,
                        sampleBounds.Height + 5f);
                }

                HitNumberPaintItem summary = BuildSummaryItem(
                    burst,
                    0f,
                    0f,
                    16,
                    false);
                summary.CombinedScale = 1.46f;
                summary.HitCount = Math.Max(summary.HitCount, segmentCount);
                float summaryWidth = Math.Max(
                    84f,
                    EstimateItemBounds(summary).Width + 8f);
                const float horizontalPadding = 6f;
                float maximumRowWidth = StageWidth - StageMarginForTests * 2f;
                float availableDetailWidth = Math.Max(
                    minimumCellWidth,
                    maximumRowWidth - summaryWidth - horizontalPadding * 2f);
                int fittingColumns = Math.Max(
                    1,
                    (int)Math.Floor(availableDetailWidth / cellWidth));
                columns = Math.Min(columns, fittingColumns);
                if (columns == 1 && cellWidth > availableDetailWidth)
                    cellWidth = availableDetailWidth;

                lineHeight = requiredLineHeight;
                int rows = (segmentCount + columns - 1) / columns;
                float width = summaryWidth + columns * cellWidth + horizontalPadding * 2f;
                float height = Math.Max(22f, rows * lineHeight + 5f);
                return new RowSpec(
                    width,
                    height,
                    summaryWidth,
                    cellWidth,
                    lineHeight,
                    2f,
                    horizontalPadding,
                    columns,
                    detailFont,
                    16);
            }
        }

        private readonly struct ActiveSegment
        {
            internal ActiveSegment(
                HitNumberSegment segment,
                double ageSeconds,
                double progress01,
                float stageX,
                float stageY)
            {
                Segment = segment;
                AgeSeconds = ageSeconds;
                Progress01 = progress01;
                StageX = stageX;
                StageY = stageY;
            }

            internal HitNumberSegment Segment { get; }
            internal double AgeSeconds { get; }
            internal double Progress01 { get; }
            internal float StageX { get; }
            internal float StageY { get; }
        }
    }
}
