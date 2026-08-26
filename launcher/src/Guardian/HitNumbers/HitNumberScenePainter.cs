using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace CF7Launcher.Guardian.HitNumbers
{
    /// <summary>
    /// 世界数字的轻量目标归属标记。默认、详细和总伤模式只绘制目标头顶的短距
    /// 指向符，不再绘制 Burst 卡片、长脊线或大面积边框；经典模式保持旧 Flash
    /// 的纯飘字表达，不额外叠加标记。
    /// </summary>
    internal sealed class HitNumberScenePainter : IDisposable
    {
        private readonly Dictionary<string, TargetAnchor> _anchors =
            new Dictionary<string, TargetAnchor>(StringComparer.Ordinal);
        private readonly Pen _anchorPen = new Pen(Color.Transparent, 1f)
        {
            StartCap = LineCap.Round,
            EndCap = LineCap.Round,
            LineJoin = LineJoin.Round
        };
        private bool _disposed;

        internal void DrawWorldRows(
            Graphics graphics,
            RectangleF viewport,
            IReadOnlyList<HitNumberBurstRow> rows,
            HitNumberDisplayMode mode)
        {
            if (graphics == null) throw new ArgumentNullException(nameof(graphics));
            if (rows == null) throw new ArgumentNullException(nameof(rows));
            ThrowIfDisposed();
            if (rows.Count == 0 || mode == HitNumberDisplayMode.Classic) return;

            float scaleX = viewport.Width / HitNumberLayoutEngine.StageWidth;
            float scaleY = viewport.Height / HitNumberLayoutEngine.StageHeight;
            Color accent = ResolveAccent(mode);
            _anchors.Clear();
            for (int i = 0; i < rows.Count; i++)
            {
                HitNumberBurstRow row = rows[i];
                if (!_anchors.TryGetValue(row.TargetId, out TargetAnchor existing)
                    || row.LastArrivalSeconds > existing.LastArrivalSeconds)
                {
                    _anchors[row.TargetId] = new TargetAnchor(row);
                }
            }

            _anchorPen.Width = Math.Max(1.2f, scaleX * 1.7f);
            foreach (TargetAnchor anchor in _anchors.Values)
            {
                int alpha = (int)(Math.Max(0.18f, Math.Min(1f, anchor.Alpha)) * 190f);
                _anchorPen.Color = Color.FromArgb(alpha, accent.R, accent.G, accent.B);

                float targetX = viewport.X + anchor.TargetX * scaleX;
                float targetY = viewport.Y + (anchor.TargetY - 29f) * scaleY;
                float attachmentX = viewport.X + anchor.AttachmentX * scaleX;
                float attachmentY = viewport.Y + anchor.AttachmentY * scaleY;

                float dx = attachmentX - targetX;
                float dy = attachmentY - targetY;
                float distance = (float)Math.Sqrt(dx * dx + dy * dy);
                if (distance > 2f)
                {
                    float visibleLength = Math.Min(distance, Math.Max(12f, 24f * scaleX));
                    float factor = visibleLength / distance;
                    graphics.DrawLine(
                        _anchorPen,
                        targetX,
                        targetY - 2f * scaleY,
                        targetX + dx * factor,
                        targetY + dy * factor);
                }

                float wingX = Math.Max(4f, 5.5f * scaleX);
                float wingY = Math.Max(3f, 4.5f * scaleY);
                graphics.DrawLine(
                    _anchorPen,
                    targetX - wingX,
                    targetY - wingY,
                    targetX,
                    targetY);
                graphics.DrawLine(
                    _anchorPen,
                    targetX,
                    targetY,
                    targetX + wingX,
                    targetY - wingY);
            }
        }

        private static Color ResolveAccent(HitNumberDisplayMode mode)
        {
            switch (mode)
            {
                case HitNumberDisplayMode.Detail:
                    return Color.FromArgb(77, 224, 205);
                case HitNumberDisplayMode.Total:
                    return Color.FromArgb(255, 191, 76);
                default:
                    return Color.FromArgb(255, 218, 96);
            }
        }

        private void ThrowIfDisposed()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(HitNumberScenePainter));
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _anchorPen.Dispose();
            _anchors.Clear();
        }

        private readonly struct TargetAnchor
        {
            internal TargetAnchor(HitNumberBurstRow row)
            {
                TargetX = row.TargetX;
                TargetY = row.TargetY;
                AttachmentX = row.AttachmentX;
                AttachmentY = row.AttachmentY;
                LastArrivalSeconds = row.LastArrivalSeconds;
                Alpha = row.Alpha;
            }

            internal float TargetX { get; }
            internal float TargetY { get; }
            internal float AttachmentX { get; }
            internal float AttachmentY { get; }
            internal double LastArrivalSeconds { get; }
            internal float Alpha { get; }
        }
    }
}
