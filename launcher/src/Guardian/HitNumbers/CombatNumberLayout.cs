using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal static partial class HitNumberLayoutEngine
    {
        // #303 治疗数字二级视觉通道（H1 校准版：绿芯语义不动，按 GDI+ 描边半覆盖校准敌方亮暗红描边）。
        internal static readonly Color AllyHealingColor = Color.FromArgb(0x52, 0xDE, 0x98);
        internal static readonly Color AllyHealingOutlineColor = Color.FromArgb(0x0B, 0x14, 0x10);
        internal static readonly Color EnemyHealingColor = Color.FromArgb(0x96, 0xF2, 0xAE);
        internal static readonly Color EnemyHealingOutlineColor = Color.FromArgb(0xC8, 0x20, 0x32);
        internal static readonly Color HealingColor = AllyHealingColor;

        internal const float HealingFontSize = 12.5f;
        internal const int HealingPackedFontSize = 13;
        internal const float AllyHealingBlur = 1.8f;
        internal const float EnemyHealingBlur = 2.8f;
        internal const float HealingAlphaScale = 0.92f;
        internal const float HealingShoulderOffsetX = 58f;
        internal const float HealingShoulderOffsetY = -42f;

        internal static HitNumberLayoutFrame BuildCombatFrame(
            IReadOnlyList<HitNumberSegment> damage, int start,
            IReadOnlyList<HitNumberTotalEntry> totals, IReadOnlyList<CombatNumberVisualEvent> healing,
            HitNumberDisplayMode mode, HitNumberCamera camera, double now, int rowLimit)
        {
            IReadOnlyList<HitNumberBalancedLane> balancedLanes = null;
            if (mode == HitNumberDisplayMode.Balanced)
            {
                if (damage != null && start < damage.Count)
                {
                    var acc = new HitNumberBalancedAccumulator();
                    acc.AddRange(damage, start, damage.Count - start);
                    balancedLanes = acc.Snapshot(now);
                }
                else
                {
                    balancedLanes = Array.Empty<HitNumberBalancedLane>();
                }
            }
            return BuildCombatFrame(
                damage, start, balancedLanes, totals, null, healing, mode, camera, now, rowLimit);
        }

        internal static HitNumberLayoutFrame BuildCombatFrame(
            IReadOnlyList<HitNumberSegment> damage, int start,
            IReadOnlyList<HitNumberBalancedLane> balancedLanes,
            IReadOnlyList<HitNumberTotalEntry> totals,
            IReadOnlyList<HitNumberMissFlash> totalMissFlashes,
            IReadOnlyList<CombatNumberVisualEvent> healing,
            HitNumberDisplayMode mode, HitNumberCamera camera, double now, int rowLimit)
        {
            HitNumberLayoutFrame frame;
            if (mode == HitNumberDisplayMode.Total)
            {
                frame = BuildTotalFrame(
                    totals ?? Array.Empty<HitNumberTotalEntry>(),
                    now,
                    camera,
                    rowLimit,
                    totalMissFlashes);
            }
            else if (mode == HitNumberDisplayMode.Balanced)
            {
                frame = BuildBalancedFrame(
                    balancedLanes ?? Array.Empty<HitNumberBalancedLane>(),
                    now,
                    camera,
                    rowLimit);
            }
            else
            {
                HitNumberLayoutCandidate candidate = mode == HitNumberDisplayMode.Detail
                    ? HitNumberLayoutCandidate.FixedBurstStack
                    : HitNumberLayoutCandidate.ClassicScatter;
                double lifetime = mode == HitNumberDisplayMode.Classic
                    ? ClassicLifetimeSeconds
                    : DefaultLifetimeSeconds;
                frame = BuildFrame(
                    damage ?? Array.Empty<HitNumberSegment>(),
                    start,
                    now,
                    candidate,
                    camera,
                    rowLimit,
                    lifetime,
                    false);
            }

            if (healing == null || healing.Count == 0) return frame;

            AppendHealingRows(frame, healing, mode, camera, now, rowLimit);
            ReserveSemanticRows(frame, rowLimit, mode);
            return frame;
        }

        internal static HitNumberSegment CreateHealingSample(CombatNumberVisualEvent value) => new HitNumberSegment
        {
            Kind = CombatNumberKind.HealHp,
            TargetId = value.LifecycleKey,
            PresentationTargetId = value.PresentationTargetKey,
            BurstId = "#heal:" + value.Sequence.ToString(CultureInfo.InvariantCulture),
            Sequence = value.Sequence,
            TargetX = value.Anchor.WorldX,
            TargetY = value.Anchor.WorldY,
            ArrivalSeconds = value.Published,
            VisualBornSeconds = value.Born,
            VisualAlpha = value.Alpha,
            Damage = value.Value,
            Packed = HitNumberPacking.Create(value.IsEnemy ? 128 : 0, false, HealingPackedFontSize, 0),
            ExpectedBurstHitCount = 1
        };

        private static HitNumberPaintItem ApplySemantic(HitNumberPaintItem item, HitNumberSegment sample, bool classic = false)
        {
            if (sample.Kind == CombatNumberKind.Damage) return item;
            bool isEnemy = (HitNumberPacking.Flags(sample.Packed) & 128) != 0;
            item.Kind = sample.Kind;
            item.FontSizeOverride = HealingFontSize;
            item.MainColorOverride = isEnemy ? EnemyHealingColor : AllyHealingColor;
            item.OutlineColorOverride = isEnemy ? EnemyHealingOutlineColor : AllyHealingOutlineColor;
            item.CombinedBlur = isEnemy ? EnemyHealingBlur : AllyHealingBlur;
            item.HitCount = 0;
            item.Alpha = classic ? 1f : sample.VisualAlpha * HealingAlphaScale;
            item.SourceSequence = -1;
            item.SourceTargetId = sample.TargetId;
            return item;
        }

        private static void AppendHealingRows(
            HitNumberLayoutFrame frame,
            IReadOnlyList<CombatNumberVisualEvent> healing,
            HitNumberDisplayMode mode,
            HitNumberCamera camera,
            double now,
            int rowLimit)
        {
            bool isClassic = mode == HitNumberDisplayMode.Classic;
            bool cumulativeValue = mode == HitNumberDisplayMode.Total;
            var candidates = new List<CombatNumberVisualEvent>(healing.Count);
            for (int i = 0; i < healing.Count; i++)
            {
                CombatNumberVisualEvent h = healing[i];
                double age = now - h.Published;
                if (age < 0) continue;
                if (isClassic && age >= ClassicLifetimeSeconds) continue;
                if (!isClassic && age >= DefaultLifetimeSeconds) continue;
                float stageX = camera.ToStageX(h.Anchor.WorldX);
                float stageY = camera.ToStageY(h.Anchor.WorldY);
                if (!IsTargetOnscreen(stageX, stageY)) continue;
                candidates.Add(h);
            }
            if (candidates.Count == 0) return;

            // 共享同一世界行预算：总候选超出 rowLimit 时按最新到达统一淘汰，保持伤害与治疗不超预算，
            // 且未淘汰的既有伤害坐标完全不变。
            if (rowLimit > 0 && frame.WorldRows.Count + candidates.Count > rowLimit)
            {
                var combined = new List<(bool IsHeal, int Index, double Arrival, int Sequence)>(
                    frame.WorldRows.Count + candidates.Count);
                for (int i = 0; i < frame.WorldRows.Count; i++)
                {
                    HitNumberBurstRow row = frame.WorldRows[i];
                    combined.Add((false, i, row.LastArrivalSeconds, row.FirstSequence));
                }
                for (int i = 0; i < candidates.Count; i++)
                {
                    CombatNumberVisualEvent h = candidates[i];
                    combined.Add((true, i, h.Published, h.Sequence));
                }
                combined.Sort((left, right) =>
                {
                    int arrival = right.Arrival.CompareTo(left.Arrival);
                    if (arrival != 0) return arrival;
                    if (left.IsHeal != right.IsHeal) return left.IsHeal ? 1 : -1;
                    return right.Sequence.CompareTo(left.Sequence);
                });

                var keepDamage = new bool[frame.WorldRows.Count];
                var keepHeal = new bool[candidates.Count];
                for (int i = 0; i < rowLimit; i++)
                {
                    if (combined[i].IsHeal) keepHeal[combined[i].Index] = true;
                    else keepDamage[combined[i].Index] = true;
                }

                for (int i = frame.WorldRows.Count - 1; i >= 0; i--)
                {
                    if (keepDamage[i]) continue;
                    HitNumberBurstRow evicted = frame.WorldRows[i];
                    frame.WorldRows.RemoveAt(i);
                    frame.WorldRowOmittedCount++;
                    frame.WorldSegmentOmittedCount = SaturatingCountAdd(
                        frame.WorldSegmentOmittedCount,
                        Math.Max(1, evicted.HitCount));
                    for (int j = frame.Items.Count - 1; j >= 0; j--)
                    {
                        HitNumberPaintItem item = frame.Items[j];
                        if (item.Kind == evicted.Kind
                            && item.SourceTargetId == evicted.TargetId
                            && item.SourceBurstId == evicted.BurstId)
                        {
                            frame.Items.RemoveAt(j);
                            if (item.VisualRole == HitNumberVisualRole.Detail) frame.DetailItemCount--;
                            else frame.SummaryItemCount--;
                        }
                    }
                }

                var keptHeals = new List<CombatNumberVisualEvent>();
                for (int i = 0; i < candidates.Count; i++)
                {
                    if (keepHeal[i]) keptHeals.Add(candidates[i]);
                    else frame.WorldRowOmittedCount++;
                }
                candidates = keptHeals;
            }

            // 按旧→新追加，最新治疗位于 Z-top。
            candidates.Sort((left, right) =>
            {
                int arrival = left.Published.CompareTo(right.Published);
                return arrival != 0 ? arrival : left.Sequence.CompareTo(right.Sequence);
            });

            for (int i = 0; i < candidates.Count; i++)
            {
                CombatNumberVisualEvent h = candidates[i];
                float targetStageX = camera.ToStageX(h.Anchor.WorldX);
                float targetStageY = camera.ToStageY(h.Anchor.WorldY);
                int displayedValue = cumulativeValue ? h.TotalValue : h.Value;
                Color fill = h.IsEnemy ? EnemyHealingColor : AllyHealingColor;
                Color outline = h.IsEnemy ? EnemyHealingOutlineColor : AllyHealingOutlineColor;
                float blur = h.IsEnemy ? EnemyHealingBlur : AllyHealingBlur;
                string burstId = "#heal:" + h.Sequence.ToString(CultureInfo.InvariantCulture);
                HitNumberVisualRole role = mode == HitNumberDisplayMode.Detail || isClassic
                    ? HitNumberVisualRole.Detail
                    : HitNumberVisualRole.Summary;

                float itemX;
                float itemY;
                float scale;
                float itemBlur;
                float alpha;

                if (isClassic)
                {
                    double age = Math.Max(0.0, now - h.Published);
                    int classicFrame = Math.Max(0, Math.Min(
                        ClassicScale.Length - 1,
                        (int)Math.Floor(age * 24.0)));
                    float randomX = StableClassicOffset(h.Sequence, 0x4F1BBCDCu);
                    float randomY = StableClassicOffset(h.Sequence, 0x91E10DA5u);
                    float offsetX = ClassicScale[classicFrame] * ClassicTextCenterX + ClassicTranslateX[classicFrame];
                    float offsetY = ClassicScale[classicFrame] * ClassicTextCenterY + ClassicTranslateY[classicFrame];
                    itemX = targetStageX + (randomX + offsetX) * camera.Scale;
                    itemY = targetStageY + (randomY + offsetY) * camera.Scale;
                    scale = ClassicScale[classicFrame] * camera.Scale;
                    itemBlur = Math.Min(ClassicBlur[classicFrame], blur) * camera.Scale;
                    alpha = 1f;
                }
                else
                {
                    // 治疗完全退出冲击层：无 1.46×/1.62× 暴涨脉冲、无白闪，稳态位于目标右肩轻浮。
                    float bornAge = (float)Math.Max(0.0, now - h.Born);
                    float gentleLift = -Math.Min(9f, bornAge * 12f);
                    itemX = Clamp(targetStageX + HealingShoulderOffsetX, 24f, StageWidth - 24f);
                    itemY = Clamp(targetStageY + HealingShoulderOffsetY + gentleLift, 16f, StageHeight - 24f);
                    scale = 1.0f;
                    itemBlur = blur;
                    alpha = h.Alpha * HealingAlphaScale;
                }

                var paintItem = new HitNumberPaintItem
                {
                    Kind = CombatNumberKind.HealHp,
                    StageX = itemX,
                    StageY = itemY,
                    CombinedScale = scale,
                    Alpha = alpha,
                    CombinedBlur = itemBlur,
                    Value = displayedValue,
                    Packed = HitNumberPacking.Create(h.IsEnemy ? 128 : 0, false, HealingPackedFontSize, 0),
                    FontSizeOverride = HealingFontSize,
                    HitCount = 0,
                    FlagScales = "000000000",
                    MainColorOverride = fill,
                    OutlineColorOverride = outline,
                    SourceSequence = -1,
                    SourceBurstId = burstId,
                    SourceTargetId = h.LifecycleKey,
                    SourceTargetX = targetStageX,
                    SourceTargetY = targetStageY,
                    VisualRole = role
                };
                RectangleF itemBounds = EstimateItemBounds(paintItem);

                frame.WorldRows.Add(new HitNumberBurstRow
                {
                    Kind = CombatNumberKind.HealHp,
                    TargetId = h.LifecycleKey,
                    BurstId = burstId,
                    TargetX = targetStageX,
                    TargetY = targetStageY,
                    Bounds = itemBounds,
                    AttachmentX = itemX,
                    AttachmentY = itemBounds.Bottom,
                    GrowthDirection = 0,
                    TotalDamage = 0,
                    HitCount = 0,
                    ExpectedHitCount = 1,
                    FirstSequence = h.Sequence,
                    FirstArrivalSeconds = h.Published,
                    LastArrivalSeconds = h.Published,
                    Alpha = alpha,
                    SuppressTargetAnchor = true
                });
                frame.Items.Add(paintItem);
                if (role == HitNumberVisualRole.Detail) frame.DetailItemCount++;
                else frame.SummaryItemCount++;
            }
        }

        /// <summary>
        /// 治疗行先优先停留在目标右肩；若与伤害或相邻治疗相交，优先切到目标左肩（贴近本单位），
        /// 仍拥挤时才按最近纵向空位避让，既保证零像素遮挡又不无故远离原单位。
        /// </summary>
        private static void ReserveSemanticRows(HitNumberLayoutFrame frame, int rowLimit, HitNumberDisplayMode mode)
        {
            var reserved = new List<RectangleF>();
            foreach (var row in frame.WorldRows)
                if (row.Kind == CombatNumberKind.Damage) reserved.Add(row.Bounds);
            foreach (var item in frame.Items)
                if (item.Kind == CombatNumberKind.Damage) reserved.Add(EstimateItemBounds(item));

            var semanticRows = new List<HitNumberBurstRow>();
            foreach (var row in frame.WorldRows)
                if (row.Kind != CombatNumberKind.Damage) semanticRows.Add(row);
            semanticRows.Sort((left, right) =>
            {
                int time = right.LastArrivalSeconds.CompareTo(left.LastArrivalSeconds);
                return time != 0 ? time : right.FirstSequence.CompareTo(left.FirstSequence);
            });

            bool allowOppositeShoulder = mode != HitNumberDisplayMode.Classic;
            foreach (var row in semanticRows)
            {
                var members = new List<HitNumberPaintItem>();
                RectangleF envelope = row.Bounds;
                foreach (var item in frame.Items)
                {
                    if (item.Kind == row.Kind && item.SourceTargetId == row.TargetId && item.SourceBurstId == row.BurstId)
                    {
                        members.Add(item);
                        envelope = RectangleF.Union(envelope, EstimateItemBounds(item));
                    }
                }
                if (members.Count == 0) continue;

                float dx = envelope.Width <= StageWidth - 8
                    ? Math.Clamp(0f, 4f - envelope.Left, StageWidth - 4f - envelope.Right)
                    : 0f;
                envelope.Offset(dx, 0f);
                float dy = envelope.Height <= StageHeight - 8
                    ? Math.Clamp(0f, 4f - envelope.Top, StageHeight - 4f - envelope.Bottom)
                    : 0f;

                bool fits = IsFree(envelope, dy, reserved);

                // 右肩被占据时先尝试切到左肩，避免治疗脱离目标向上/下远跳。
                if (!fits && allowOppositeShoulder)
                {
                    float currentCenterX = envelope.Left + envelope.Width / 2f;
                    float leftShoulderX = Clamp(row.TargetX - HealingShoulderOffsetX, 24f, StageWidth - 24f);
                    float altShiftX = leftShoulderX - currentCenterX;
                    RectangleF altEnvelope = envelope;
                    altEnvelope.Offset(altShiftX, 0f);
                    float clampShift = altEnvelope.Width <= StageWidth - 8
                        ? Math.Clamp(0f, 4f - altEnvelope.Left, StageWidth - 4f - altEnvelope.Right)
                        : 0f;
                    altEnvelope.Offset(clampShift, 0f);
                    if (IsFree(altEnvelope, dy, reserved))
                    {
                        dx += altShiftX + clampShift;
                        envelope = altEnvelope;
                        fits = true;
                    }
                }

                if (!fits)
                {
                    float nearest = float.PositiveInfinity;
                    foreach (var obstacle in reserved)
                    {
                        TryCandidate(obstacle.Top - 3f - envelope.Bottom);
                        TryCandidate(obstacle.Bottom + 3f - envelope.Top);
                    }
                    fits = float.IsFinite(nearest);
                    if (fits) dy = nearest;

                    void TryCandidate(float candidate)
                    {
                        if (Math.Abs(candidate) >= Math.Abs(nearest) || !IsFree(envelope, candidate, reserved)) return;
                        nearest = candidate;
                    }
                }

                if (!fits && rowLimit > 0)
                {
                    frame.WorldRows.Remove(row);
                    foreach (var item in members)
                    {
                        frame.Items.Remove(item);
                        if (item.VisualRole == HitNumberVisualRole.Detail) frame.DetailItemCount--;
                        else frame.SummaryItemCount--;
                    }
                    frame.WorldRowOmittedCount++;
                    continue;
                }

                foreach (var item in members)
                {
                    item.StageX += dx;
                    item.StageY += dy;
                }
                row.Bounds = new RectangleF(row.Bounds.X + dx, row.Bounds.Y + dy, row.Bounds.Width, row.Bounds.Height);
                row.AttachmentX += dx;
                row.AttachmentY += dy;
                envelope.Offset(0f, dy);
                reserved.Add(envelope);
            }
        }

        private static bool IsFree(RectangleF envelope, float dy, List<RectangleF> reserved)
        {
            envelope.Offset(0f, dy);
            if (envelope.Top < 4f || envelope.Bottom > StageHeight - 4f) return false;
            foreach (var obstacle in reserved)
                if (envelope.IntersectsWith(obstacle)) return false;
            return true;
        }
    }
}
