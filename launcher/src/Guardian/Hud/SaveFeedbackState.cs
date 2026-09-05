using System;
using System.Drawing;

namespace CF7Launcher.Guardian.Hud
{
    internal enum SaveFeedbackVisual { None, Saving, SavedBright, Saved, SavedDim, Unconfirmed }

    // 只观察完整存盘的 sv 事实，不调用保存，也不授予退出权限。
    internal sealed class SaveFeedbackState
    {
        private readonly Func<long> _clock;
        private readonly Func<DateTime> _wallClock;
        private int _status;
        private long _savedAt;
        private SaveFeedbackVisual _publishedVisual;

        internal SaveFeedbackState(Func<long> clock = null, Func<DateTime> wallClock = null)
        {
            _clock = clock ?? (() => Environment.TickCount64);
            _wallClock = wallClock ?? (() => DateTime.Now);
        }

        internal long CompletedSaveCount { get; private set; }
        internal DateTime? LastSavedAt { get; private set; }

        // 保留一次到期 tick，让最后一次清除重绘发出；面板隐藏期间不申请额外定时器。
        internal bool NeedsTick => _status == 2 && _publishedVisual != SaveFeedbackVisual.None;

        internal SaveFeedbackVisual Visual
        {
            get
            {
                if (_status == 1) return SaveFeedbackVisual.Saving;
                if (_status == 3) return SaveFeedbackVisual.Unconfirmed;
                if (_status != 2) return SaveFeedbackVisual.None;
                long age = Math.Max(0, _clock() - _savedAt);
                if (age < 160) return SaveFeedbackVisual.SavedBright;
                if (age < 900) return SaveFeedbackVisual.Saved;
                if (age < 1200) return SaveFeedbackVisual.SavedDim;
                return SaveFeedbackVisual.None;
            }
        }

        internal string Hint
        {
            get
            {
                if (_status == 1) return "正在存盘";
                if (_status == 3) return "保存未确认，请重试";
                return LastSavedAt.HasValue
                    ? "已保存 " + LastSavedAt.Value.ToString("HH:mm:ss") + " · " + CompletedSaveCount + " 次"
                    : "";
            }
        }

        internal bool HandlePacket(UiDataPacket packet)
        {
            if (packet == null || packet.IsLegacy) return false;
            foreach (var pair in UiDataPacketParser.ParseFrom(packet))
            {
                if (pair.Key == "s" && !UiValueParser.ParseUiBoolValue(pair.Value)) Reset();
                if (pair.Key != "sv") continue;
                int status = UiValueParser.ParseUiIntValue(pair.Value, 0);
                if (status < 1 || status > 3) continue;
                _status = status;
                if (status == 2)
                {
                    CompletedSaveCount++;
                    LastSavedAt = _wallClock();
                    _savedAt = _clock();
                }
            }
            // 同包开始/完成只展示最终事实，不在成功之后伪造“存盘中”。
            return Tick();
        }

        internal void Reset()
        {
            _status = 0;
            CompletedSaveCount = 0;
            LastSavedAt = null;
        }

        internal bool Tick()
        {
            SaveFeedbackVisual next = Visual;
            if (next == _publishedVisual) return false;
            _publishedVisual = next;
            return true;
        }

        internal static void PaintAccent(Graphics g, Rectangle button, float scale, SaveFeedbackVisual visual)
        {
            if (visual == SaveFeedbackVisual.None) return;
            bool saved = visual == SaveFeedbackVisual.SavedBright
                || visual == SaveFeedbackVisual.Saved || visual == SaveFeedbackVisual.SavedDim;
            Color color = saved ? NativeHudTheme.Success : NativeHudTheme.Warning;
            int alpha = visual == SaveFeedbackVisual.SavedDim ? 72
                : visual == SaveFeedbackVisual.Saved ? 168 : 240;
            int inset = WidgetScaler.Px(3, scale);
            Rectangle inner = Rectangle.Inflate(button, -inset, -inset);
            if (inner.Width < 4 || inner.Height < 4) return;
            using (var wash = new SolidBrush(Color.FromArgb(alpha / 6, color)))
            using (var stroke = new Pen(Color.FromArgb(alpha, color), Math.Max(1f, scale)))
            {
                g.FillRectangle(wash, inner);
                // 所有像素留在原按钮内，不改变 HUD union 或命中范围。
                g.DrawRectangle(stroke, inner.X, inner.Y, inner.Width - 1, inner.Height - 1);
                float x = inner.Right - 9 * scale, y = inner.Bottom - 5 * scale;
                if (saved)
                {
                    g.DrawLines(stroke, new[] {
                        new PointF(x, y), new PointF(x + 2 * scale, y + 2 * scale),
                        new PointF(x + 6 * scale, y - 3 * scale) });
                }
                else if (visual == SaveFeedbackVisual.Unconfirmed)
                {
                    g.DrawLine(stroke, x + 4 * scale, y - 5 * scale, x + 4 * scale, y - scale);
                    g.DrawLine(stroke, x + 4 * scale, y + scale, x + 4 * scale, y + 2 * scale);
                }
                else
                    g.DrawLine(stroke, inner.Left + 2 * scale, inner.Bottom - 3 * scale,
                        inner.Right - 2 * scale, inner.Bottom - 3 * scale);
            }
        }
    }
}
