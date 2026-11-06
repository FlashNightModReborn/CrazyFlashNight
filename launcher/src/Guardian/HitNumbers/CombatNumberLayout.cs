using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal static partial class HitNumberLayoutEngine
    {
        internal static readonly Color HealingColor = Color.FromArgb(0x57, 0xE5, 0x90);
        internal static HitNumberLayoutFrame BuildCombatFrame(
            IReadOnlyList<HitNumberSegment> damage, int start,
            IReadOnlyList<HitNumberTotalEntry> totals, IReadOnlyList<CombatNumberVisualEvent> healing,
            HitNumberDisplayMode mode, HitNumberCamera camera, double now, int rowLimit)
        {
            HitNumberLayoutFrame frame;
            if (mode == HitNumberDisplayMode.Total)
            {
                if (healing.Count == 0) return BuildTotalFrame(totals, now, camera, rowLimit);
                var candidates = new List<HitNumberTotalEntry>(totals.Count + healing.Count);
                candidates.AddRange(totals);
                foreach (var value in healing) candidates.Add(HitNumberTotalEntry.ForHealing(value));
                frame = BuildTotalFrame(candidates, now, camera, rowLimit);
            }
            else
            {
                var candidate = mode == HitNumberDisplayMode.Detail ? HitNumberLayoutCandidate.FixedBurstStack
                    : mode == HitNumberDisplayMode.Classic ? HitNumberLayoutCandidate.ClassicScatter
                    : HitNumberLayoutCandidate.BalancedSummary;
                double lifetime = mode == HitNumberDisplayMode.Classic ? ClassicLifetimeSeconds : DefaultLifetimeSeconds;
                if (healing.Count == 0) return BuildFrame(damage, start, now, candidate, camera, rowLimit, lifetime, false);
                // 两个有序来源线性合并，保留现有最新 K 行快速投影。仅表现阶段适配候选，
                // 不把高频治疗输入塞进伤害 reducer、伤害随机序号或账本。
                var merged = new List<HitNumberSegment>(damage.Count - start + healing.Count);
                int nextDamage = start;
                foreach (var value in healing)
                {
                    var sample = CreateHealingSample(value);
                    while (nextDamage < damage.Count && (damage[nextDamage].ArrivalSeconds < sample.ArrivalSeconds
                        || (damage[nextDamage].ArrivalSeconds == sample.ArrivalSeconds && damage[nextDamage].Sequence <= sample.Sequence)))
                        merged.Add(damage[nextDamage++]);
                    merged.Add(sample);
                }
                while (nextDamage < damage.Count) merged.Add(damage[nextDamage++]);
                frame = BuildFrame(merged, 0, now, candidate, camera, rowLimit, lifetime, false);
            }
            ReserveSemanticRows(frame, rowLimit);
            return frame;
        }

        internal static HitNumberSegment CreateHealingSample(CombatNumberVisualEvent value) => new HitNumberSegment
        {
            Kind = CombatNumberKind.HealHp, TargetId = value.LifecycleKey,
            PresentationTargetId = value.PresentationTargetKey,
            BurstId = "#heal:" + value.Sequence.ToString(CultureInfo.InvariantCulture), Sequence = value.Sequence,
            TargetX = value.Anchor.WorldX, TargetY = value.Anchor.WorldY,
            ArrivalSeconds = value.Published, VisualBornSeconds = value.Born, VisualAlpha = value.Alpha,
            Damage = value.Value, Packed = HitNumberPacking.Create(0, false, BalancedFontSize, 0), ExpectedBurstHitCount = 1
        };

        private static HitNumberPaintItem ApplySemantic(HitNumberPaintItem item, HitNumberSegment sample, bool classic = false)
        {
            if (sample.Kind == CombatNumberKind.Damage) return item;
            item.Kind = sample.Kind;
            item.MainColorOverride = HealingColor;
            item.HitCount = 0;
            item.Alpha = classic ? 1f : sample.VisualAlpha;
            item.SourceSequence = -1;
            item.SourceTargetId = sample.TargetId;
            return item;
        }

        /// <summary>
        /// 语义行在同一世界预算内完成布局后统一预留实际字形包络。保持既有伤害固定栈，
        /// 新的恢复行从策略给出的原位选择最近空位，不再具有“脚边 +64/+8”专属坐标。
        /// 实例键不兼容时也能几何避让，无需将相邻单位猜成同一目标。
        /// </summary>
        private static void ReserveSemanticRows(HitNumberLayoutFrame frame, int rowLimit)
        {
            bool mixed = false;
            foreach (var row in frame.WorldRows) if (row.Kind == CombatNumberKind.Damage) { mixed = true; break; }
            var reserved = new List<RectangleF>();
            if (mixed)
            {
                foreach (var row in frame.WorldRows) if (row.Kind == CombatNumberKind.Damage) reserved.Add(row.Bounds);
                foreach (var item in frame.Items) if (item.Kind == CombatNumberKind.Damage) reserved.Add(EstimateItemBounds(item));
            }
            var semanticRows = new List<HitNumberBurstRow>();
            foreach (var row in frame.WorldRows) if (row.Kind != CombatNumberKind.Damage) semanticRows.Add(row);
            semanticRows.Sort((left, right) =>
            {
                int time = right.LastArrivalSeconds.CompareTo(left.LastArrivalSeconds);
                return time != 0 ? time : right.FirstSequence.CompareTo(left.FirstSequence);
            });
            // Painter 保留旧→新顺序；几何预留反向进行，拥挤时旧行不能挤掉新回执。
            foreach (var row in semanticRows)
            {
                var members = new List<HitNumberPaintItem>();
                RectangleF envelope = row.Bounds;
                foreach (var item in frame.Items)
                    if (item.Kind == row.Kind && item.SourceTargetId == row.TargetId && item.SourceBurstId == row.BurstId)
                    { members.Add(item); envelope = RectangleF.Union(envelope, EstimateItemBounds(item)); }
                if (members.Count == 0) continue;
                float dx = envelope.Width <= StageWidth - 8 ? Math.Clamp(0, 4 - envelope.Left, StageWidth - 4 - envelope.Right) : 0;
                envelope.Offset(dx, 0);
                float dy = envelope.Height <= StageHeight - 8 ? Math.Clamp(0, 4 - envelope.Top, StageHeight - 4 - envelope.Bottom) : 0;
                bool fits = IsFree(envelope, dy, reserved);
                if (!fits)
                {
                    float nearest = float.PositiveInfinity;
                    foreach (var obstacle in reserved)
                    {
                        TryCandidate(obstacle.Top - 3 - envelope.Bottom);
                        TryCandidate(obstacle.Bottom + 3 - envelope.Top);
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
                        if (item.VisualRole == HitNumberVisualRole.Detail) frame.DetailItemCount--; else frame.SummaryItemCount--;
                    }
                    frame.WorldRowOmittedCount++;
                    continue;
                }
                foreach (var item in members) { item.StageX += dx; item.StageY += dy; }
                row.Bounds = new RectangleF(row.Bounds.X + dx, row.Bounds.Y + dy, row.Bounds.Width, row.Bounds.Height);
                row.AttachmentX += dx; row.AttachmentY += dy;
                envelope.Offset(0, dy); reserved.Add(envelope);
            }
        }

        private static bool IsFree(RectangleF envelope, float dy, List<RectangleF> reserved)
        {
            envelope.Offset(0, dy);
            if (envelope.Top < 4 || envelope.Bottom > StageHeight - 4) return false;
            foreach (var obstacle in reserved) if (envelope.IntersectsWith(obstacle)) return false;
            return true;
        }
    }
}
