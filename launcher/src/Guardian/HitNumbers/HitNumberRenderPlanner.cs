using System;
using System.Drawing;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal readonly struct HitNumberRenderRegion
    {
        internal HitNumberRenderRegion(Rectangle pixelBounds, RectangleF localViewport)
        {
            PixelBounds = pixelBounds;
            LocalViewport = localViewport;
        }

        internal Rectangle PixelBounds { get; }
        internal RectangleF LocalViewport { get; }
        internal bool IsEmpty => PixelBounds.Width <= 0 || PixelBounds.Height <= 0;
    }

    /// <summary>
    /// 把当前世界行的实际视觉范围换算为 layered-window 紧边界。常态只清空和提交
    /// 命中数字附近的像素。精确账本已经迁入 Web 设置面板，因此本窗口永远不需要
    /// 为日志扩成全视口；边界规划是纯函数，可由单测和视觉 harness 复用。
    /// </summary>
    internal static class HitNumberRenderPlanner
    {
        private const float StageInflation = 4f;
        // Bounds stay deterministic across 96–144 DPI. The point-to-pixel ceiling is
        // paired with the advance ratios of the combat font roles, rather than full ems.
        private const float MaximumPixelsPerPoint = 144f / 72f;
        private const int MaximumHorizontalOverscanPixels = 150;
        private const int MaximumVerticalOverscanPixels = 80;

        internal static HitNumberRenderRegion Plan(
            HitNumberLayoutFrame frame,
            float viewportWidth,
            float viewportHeight)
        {
            if (frame == null || viewportWidth <= 0f || viewportHeight <= 0f)
                return default;

            bool hasBounds = false;
            RectangleF bounds = RectangleF.Empty;
            float scaleX = viewportWidth / HitNumberLayoutEngine.StageWidth;
            float scaleY = viewportHeight / HitNumberLayoutEngine.StageHeight;
            if (frame.Candidate == HitNumberLayoutCandidate.FixedBurstStack ||
                frame.Candidate == HitNumberLayoutCandidate.TargetTotal)
            {
                for (int i = 0; i < frame.WorldRows.Count; i++)
                {
                    HitNumberBurstRow row = frame.WorldRows[i];
                    if (row.Kind == CombatNumberKind.Damage && !row.SuppressTargetAnchor)
                        Include(ref bounds, ref hasBounds, EstimateAnchorBounds(row, scaleX, scaleY));
                }
            }
            for (int i = 0; i < frame.Items.Count; i++)
            {
                Include(
                    ref bounds,
                    ref hasBounds,
                    EstimateRenderItemBounds(frame.Items[i], viewportWidth, viewportHeight));
            }
            if (!hasBounds) return default;

            bounds.Inflate(Math.Max(4f, StageInflation * scaleX), Math.Max(4f, StageInflation * scaleY));

            int minimumLeft = -MaximumHorizontalOverscanPixels;
            int minimumTop = -MaximumVerticalOverscanPixels;
            int maximumRight = (int)Math.Ceiling(viewportWidth) + MaximumHorizontalOverscanPixels;
            int maximumBottom = (int)Math.Ceiling(viewportHeight) + MaximumVerticalOverscanPixels;
            int left = Math.Max(minimumLeft, (int)Math.Floor(bounds.Left));
            int top = Math.Max(minimumTop, (int)Math.Floor(bounds.Top));
            int right = Math.Min(maximumRight, (int)Math.Ceiling(bounds.Right));
            int bottom = Math.Min(maximumBottom, (int)Math.Ceiling(bounds.Bottom));
            if (right <= left || bottom <= top) return default;

            var pixels = Rectangle.FromLTRB(left, top, right, bottom);
            return new HitNumberRenderRegion(
                pixels,
                new RectangleF(-left, -top, viewportWidth, viewportHeight));
        }

        internal static int QuantizeSurfaceCapacity(int required)
        {
            if (required <= 0) return 4;
            const int quantum = 64;
            return checked(Math.Max(4, ((required + quantum - 1) / quantum) * quantum));
        }

        private static void Include(
            ref RectangleF bounds,
            ref bool hasBounds,
            RectangleF value)
        {
            if (value.Width <= 0f || value.Height <= 0f) return;
            if (!hasBounds)
            {
                bounds = value;
                hasBounds = true;
                return;
            }
            bounds = RectangleF.Union(bounds, value);
        }

        private static RectangleF EstimateAnchorBounds(HitNumberBurstRow row, float scaleX, float scaleY)
        {
            // ScenePainter measures the stem in pixels, including at non-uniform viewport scales.
            float x = row.TargetX * scaleX;
            float y = (row.TargetY - 29f) * scaleY;
            float wingX = Math.Max(4f, 5.5f * scaleX);
            float wingY = Math.Max(3f, 4.5f * scaleY);
            float left = x - wingX;
            float right = x + wingX;
            float top = y - wingY;
            float bottom = y;
            float dx = row.AttachmentX * scaleX - x;
            float dy = row.AttachmentY * scaleY - y;
            float distance = MathF.Sqrt(dx * dx + dy * dy);
            if (distance > 2f)
            {
                float factor = Math.Min(distance, Math.Max(12f, 24f * scaleX)) / distance;
                left = Math.Min(left, x + dx * factor);
                right = Math.Max(right, x + dx * factor);
                top = Math.Min(top, y + dy * factor);
                bottom = Math.Max(bottom, y + dy * factor);
            }

            float penMargin = Math.Max(1.2f, 1.7f * scaleX) + 2f;
            return RectangleF.FromLTRB(left - penMargin, top - penMargin, right + penMargin, bottom + penMargin);
        }

        private static RectangleF EstimateRenderItemBounds(
            HitNumberPaintItem item, float viewportWidth, float viewportHeight)
        {
            float scaleX = viewportWidth / HitNumberLayoutEngine.StageWidth;
            float mainPt = HitNumberPainter.MainPointSize(item, scaleX);
            float maximumEm = MaximumEm(mainPt);
            float runsWidth = maximumEm * (HitNumberPacking.IsMiss(item.Packed)
                ? 2.95f
                : NumberAdvance(item.Value, item.Kind == CombatNumberKind.HealHp));
            int flags = HitNumberPacking.Flags(item.Packed);
            float labelScale = item.CombinedScale * scaleX;
            if ((flags & 8) != 0 && !string.IsNullOrEmpty(item.EffectText))
                Label(20f, 40f, 3, 0.35f, item.EffectText);
            string crushText = string.IsNullOrEmpty(item.CrushText) ? item.EffectText : item.CrushText;
            if ((flags & 16) != 0 && !string.IsNullOrEmpty(crushText))
                Label(20f, 40f, 4, 0.35f, crushText,
                    string.IsNullOrEmpty(item.CrushEmoji) ? item.EffectEmoji : item.CrushEmoji);
            if ((flags & 2) != 0) Label(20f, 40f, 1, 1.4f);
            if ((flags & 1) != 0) Label(20f, 40f, 0, 1.4f);
            if ((flags & 4) != 0) Label(20f, 40f, 2, 1.4f);
            if ((flags & 32) != 0 && item.LifeSteal > 0f)
                Label(15f, 30f, 5, 1.75f + NumberAdvance(CombatNumberValue.ClampToInteger(item.LifeSteal)));
            if ((flags & 256) != 0 && item.ShieldAbsorb > 0f)
                Label(18f, 36f, 8, 0.35f + NumberAdvance(CombatNumberValue.ClampToInteger(item.ShieldAbsorb)), "🛡");

            float outline = HitNumberPainter.OutlineWidth(item, scaleX) / 2f;
            float leftExtent = runsWidth / 2f + outline + 2f;
            float rightExtent = leftExtent;
            float topExtent = outline + 4f;
            if (item.HitCount > 1)
            {
                float numberPt = HitNumberPainter.HitCountPointSize(mainPt);
                float hitPt = HitNumberPainter.HitLabelPointSize(numberPt);
                rightExtent += 5f + MaximumEm(numberPt) * (NumberAdvance(item.HitCount) + 0.16f)
                    + MaximumEm(hitPt) * 1.65f;
                topExtent = Math.Max(topExtent, mainPt * 0.35f + outline + 3f);
            }
            // Arial Black descends to ~1.12 em and Microsoft YaHei labels to ~1.20 em at 144 DPI.
            float bottomExtent = maximumEm * 1.20f + outline;
            float x = item.StageX * scaleX;
            float y = item.StageY / HitNumberLayoutEngine.StageHeight * viewportHeight;
            return RectangleF.FromLTRB(x - leftExtent, y - topExtent, x + rightExtent, y + bottomExtent);

            void Label(float basePt, float maxPt, int bit, float advance, string text = null, string prefix = null)
            {
                float flagScale = HitNumberPainter.VisualFlagScale(item, bit);
                if (flagScale <= 0f) return;
                float pt = Math.Clamp(basePt * labelScale * flagScale, 4f, maxPt);
                float em = MaximumEm(pt);
                float emojiEm = MaximumEm(pt * 1.3f);
                runsWidth += em * advance;
                maximumEm = Math.Max(maximumEm, em);
                IncludeText(text, em, emojiEm, ref runsWidth, ref maximumEm);
                IncludeText(prefix, em, emojiEm, ref runsWidth, ref maximumEm);
            }
        }

        // A cached font may have been created by another size in the same half-point bucket.
        private static float MaximumEm(float pointSize) => (pointSize + 0.5f) * MaximumPixelsPerPoint;

        private static float NumberAdvance(int value, bool positiveSign = false)
        {
            long magnitude = Math.Abs((long)value);
            int digits = 1;
            for (; magnitude >= 10; magnitude /= 10) digits++;
            return digits * 0.68f + (value < 0 ? 0.42f : 0f) + (positiveSign ? 0.72f : 0f);
        }

        private static void IncludeText(string text, float em, float emojiEm, ref float width, ref float maximumEm)
        {
            if (string.IsNullOrEmpty(text)) return;
            for (int i = 0; i < text.Length; i++)
            {
                char c = text[i];
                if (HitNumberPainter.IsEmojiCharacter(c))
                {
                    width += emojiEm * 1.1f;
                    maximumEm = Math.Max(maximumEm, emojiEm);
                    if (char.IsHighSurrogate(c) && i + 1 < text.Length && char.IsLowSurrogate(text[i + 1])) i++;
                }
                else
                {
                    width += em * (c == ' ' ? 0.35f : c < 128 ? 1.05f : 1.1f);
                }
            }
        }
    }
}
