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
        private const float StageInflation = 14f;
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
            RectangleF stageBounds = RectangleF.Empty;
            for (int i = 0; i < frame.WorldRows.Count; i++)
            {
                HitNumberBurstRow row = frame.WorldRows[i];
                Include(ref stageBounds, ref hasBounds, row.Bounds);
                IncludePoint(ref stageBounds, ref hasBounds, row.AttachmentX, row.AttachmentY);
                IncludePoint(ref stageBounds, ref hasBounds, row.TargetX, row.TargetY - 28f);
            }
            for (int i = 0; i < frame.Items.Count; i++)
            {
                Include(
                    ref stageBounds,
                    ref hasBounds,
                    HitNumberLayoutEngine.EstimateItemBounds(frame.Items[i]));
            }
            if (!hasBounds) return default;

            stageBounds.Inflate(StageInflation, StageInflation);
            float scaleX = viewportWidth / HitNumberLayoutEngine.StageWidth;
            float scaleY = viewportHeight / HitNumberLayoutEngine.StageHeight;
            float mappedLeft = stageBounds.Left * scaleX;
            float mappedTop = stageBounds.Top * scaleY;
            float mappedRight = stageBounds.Right * scaleX;
            float mappedBottom = stageBounds.Bottom * scaleY;

            int minimumLeft = -MaximumHorizontalOverscanPixels;
            int minimumTop = -MaximumVerticalOverscanPixels;
            int maximumRight = (int)Math.Ceiling(viewportWidth) + MaximumHorizontalOverscanPixels;
            int maximumBottom = (int)Math.Ceiling(viewportHeight) + MaximumVerticalOverscanPixels;
            int left = Math.Max(minimumLeft, (int)Math.Floor(mappedLeft));
            int top = Math.Max(minimumTop, (int)Math.Floor(mappedTop));
            int right = Math.Min(maximumRight, (int)Math.Ceiling(mappedRight));
            int bottom = Math.Min(maximumBottom, (int)Math.Ceiling(mappedBottom));
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

        private static void IncludePoint(
            ref RectangleF bounds,
            ref bool hasBounds,
            float x,
            float y)
        {
            Include(ref bounds, ref hasBounds, new RectangleF(x - 2f, y - 2f, 4f, 4f));
        }
    }
}
