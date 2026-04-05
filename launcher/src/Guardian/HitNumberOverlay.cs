using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 伤害数字 GDI+ 分层窗口覆盖层。
    /// 继承 OverlayBase 的 Win32 / Owner-following / UpdateLayeredWindow 模式。
    ///
    /// 关键差异：
    /// - 无独立 Timer —— 由 Flash frame 消息驱动（每帧一次 UpdateRender）
    /// - 覆盖整个 Flash viewport（伤害数字可出现在任意位置）
    /// - 8 方向偏移描边模拟 GlowFilter
    /// </summary>
    public class HitNumberOverlay : OverlayBase
    {
        #region Color Table (mirrors Flash HitNumberBatchProcessor.COLOR_TABLE)

        private static readonly Color[] ColorTable = {
            Color.White,
            Color.Red,
            Color.FromArgb(0xFF, 0xCC, 0x00),
            Color.FromArgb(0x66, 0x00, 0x33),
            Color.FromArgb(0x4A, 0x00, 0x99),
            Color.FromArgb(0xAC, 0x99, 0xFF),
            Color.FromArgb(0x00, 0x99, 0xFF),
            Color.FromArgb(0x7F, 0x00, 0x00),
            Color.FromArgb(0x7F, 0x6A, 0x00),
            Color.FromArgb(0xFF, 0x7F, 0x7F),
            Color.FromArgb(0xFF, 0xE7, 0x70)
        };

        #endregion

        #region 8-direction glow offsets

        private static readonly int[][] GlowOffsets = {
            new[]{-1,-1}, new[]{0,-1}, new[]{1,-1},
            new[]{-1, 0},              new[]{1, 0},
            new[]{-1, 1}, new[]{0, 1}, new[]{1, 1}
        };

        #endregion

        private readonly List<string> _earlyBuffer;
        private bool _ready;
        private string _currentRenderStr;

        // 字体缓存：key = (family_index << 16 | style << 8 | size_bucket)
        private readonly Dictionary<int, Font> _fontCache = new Dictionary<int, Font>();

        public HitNumberOverlay(Form owner, Control anchor)
            : base(owner, anchor, 1024f, 576f)
        {
            _earlyBuffer = new List<string>();
            _ready = false;
            _currentRenderStr = null;
        }

        #region Owner 跟随 (override)

        protected override void OnOwnerBecameVisible()
        {
            if (!string.IsNullOrEmpty(_currentRenderStr))
                PaintLayered();
        }

        #endregion

        #region Public interface (thread-safe via BeginInvoke)

        public void SetReady()
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(SetReady));
                return;
            }
            _ready = true;
            foreach (string s in _earlyBuffer)
                DoUpdateRender(s);
            _earlyBuffer.Clear();
        }

        /// <summary>
        /// 更新渲染数据。由 FrameTask 从 ReadLoop 线程调用。
        /// 通过 BeginInvoke 跳转到 UI 线程执行实际绘制。
        /// 空串或 null → 隐藏窗口。非空 → 显示并绘制。
        /// </summary>
        public void UpdateRender(string renderStr)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(UpdateRender), renderStr);
                return;
            }
            if (!_ready)
            {
                _earlyBuffer.Add(renderStr);
                return;
            }
            DoUpdateRender(renderStr);
        }

        /// <summary>
        /// 场景切换时清空。由 hn_reset handler 从 ReadLoop 线程调用。
        /// </summary>
        public void NotifyReset()
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(NotifyReset));
                return;
            }
            _currentRenderStr = null;
            DismissOverlay();
        }

        #endregion

        private void DoUpdateRender(string renderStr)
        {
            _currentRenderStr = renderStr;

            if (string.IsNullOrEmpty(renderStr))
            {
                DismissOverlay();
                return;
            }

            // 先绘制再显示：避免 ShowOverlay 与 PaintLayered 之间的间隙
            // 导致 DWM 合成一帧旧 bitmap 残影（Layered Window surface 在 Hide 后仍保留）
            if (_ownerVisible)
                PaintLayered();

            if (!_shown && _ownerVisible)
            {
                ShowOverlay();
            }
        }

        protected override void OnPositionChanged()
        {
            if (_shown && _ownerVisible && !string.IsNullOrEmpty(_currentRenderStr))
                PaintLayered();
        }

        /// <summary>
        /// 渲染描述符格式（stride=11）：
        ///   stgX,stgY,combinedScale,alpha,combinedBlur,damage,packed,efText,efEmoji,lifeSteal,shieldAbsorb
        ///   combinedScale = animScale * cam.sx（已含相机缩放）
        ///   combinedBlur  = blur * cam.sx
        ///   stgX/stgY 已含 SWF Matrix tx/ty 偏移
        /// </summary>
        private void PaintLayered()
        {
            string data = _currentRenderStr;
            if (string.IsNullOrEmpty(data)) return;

            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);

            int padX = 150, padY = 80;
            int bmpW = Math.Max(4, (int)vpW + padX * 2);
            int bmpH = Math.Max(4, (int)vpH + padY * 2);

            Point origin;
            GetAnchorScreenOrigin(out origin);

            int scrX = origin.X + (int)vpX - padX;
            int scrY = origin.Y + (int)vpY - padY;

            float pixPerFlash = vpW / 1024f;

            using (Bitmap bmp = new Bitmap(bmpW, bmpH, PixelFormat.Format32bppPArgb))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                    g.Clear(Color.Transparent);

                    string[] entries = data.Split(';');
                    for (int ei = 0; ei < entries.Length; ei++)
                    {
                        string[] fields = entries[ei].Split(',');
                        if (fields.Length < 12) continue;

                        float stgX = float.Parse(fields[0]);
                        float stgY = float.Parse(fields[1]);
                        float combinedScale = float.Parse(fields[2]);
                        float alpha = float.Parse(fields[3]);
                        float combinedBlur = float.Parse(fields[4]);
                        int damage = (int)float.Parse(fields[5]);
                        int packed = (int)float.Parse(fields[6]);
                        string efText = fields[7];
                        string efEmoji = fields[8];
                        float lifeSteal = float.Parse(fields[9]);
                        float shieldAbsorb = float.Parse(fields[10]);
                        int hitCount = (int)float.Parse(fields[11]);

                        // Flash 舞台坐标 → bitmap 局部坐标
                        float bmpX = (stgX / 1024f) * vpW + padX;
                        float bmpY = (stgY / 576f) * vpH + padY;

                        // 解码 packed
                        bool isMiss = ((packed >> 9) & 1) != 0;
                        int fontSize = (packed >> 10) & 255;
                        int colorId = (packed >> 18) & 15;
                        int flags = packed & 511;

                        if (fontSize == 0) fontSize = 28;
                        Color mainColor = ColorTable[Math.Min(colorId, ColorTable.Length - 1)];
                        byte a = (byte)(255 * Math.Max(0f, Math.Min(1f, alpha)));

                        // ======== 构建文本段 ========
                        List<TextSegment> segments = new List<TextSegment>();

                        // 主伤害数字
                        string mainText = isMiss ? "MISS" : damage.ToString();
                        float mainPt = fontSize * combinedScale * pixPerFlash;
                        mainPt = Math.Max(6f, Math.Min(mainPt, 72f));
                        segments.Add(new TextSegment(mainText, mainColor, mainPt));

                        // 效果标签（Flash 中 size=20，按比例缩放）
                        float labelPt = 20f * combinedScale * pixPerFlash;
                        labelPt = Math.Max(4f, Math.Min(labelPt, 40f));

                        // EF_DMG_TYPE_LABEL (bit 3)
                        if ((flags & 8) != 0 && !string.IsNullOrEmpty(efText))
                            segments.Add(new TextSegment(" " + efText, mainColor, labelPt, true));

                        // EF_CRUSH_LABEL (bit 4)
                        if ((flags & 16) != 0 && !string.IsNullOrEmpty(efText))
                        {
                            string crushText = " " + (string.IsNullOrEmpty(efEmoji) ? "" : efEmoji) + efText;
                            segments.Add(new TextSegment(crushText, Color.FromArgb(0x66, 0xBC, 0xF5), labelPt, true));
                        }

                        // EF_TOXIC (bit 1)
                        if ((flags & 2) != 0)
                            segments.Add(new TextSegment(" 毒", Color.FromArgb(0x66, 0xDD, 0x00), labelPt, true));

                        // EF_LIFESTEAL (bit 5)
                        if ((flags & 32) != 0 && lifeSteal > 0)
                        {
                            float lsPt = 15f * combinedScale * pixPerFlash;
                            lsPt = Math.Max(4f, Math.Min(lsPt, 30f));
                            segments.Add(new TextSegment(" 汲:" + ((int)lifeSteal).ToString(),
                                Color.FromArgb(0xBB, 0x00, 0xAA), lsPt, true));
                        }

                        // EF_CRUMBLE (bit 0)
                        if ((flags & 1) != 0)
                            segments.Add(new TextSegment(" 溃", Color.FromArgb(0xFF, 0x33, 0x33), labelPt, true));

                        // EF_EXECUTE (bit 2)
                        if ((flags & 4) != 0)
                        {
                            Color exeColor = ((flags & 128) != 0)
                                ? Color.FromArgb(0x66, 0x00, 0x33)
                                : Color.FromArgb(0x4A, 0x00, 0x99);
                            segments.Add(new TextSegment(" 斩", exeColor, labelPt, true));
                        }

                        // EF_SHIELD (bit 8)
                        if ((flags & 256) != 0 && shieldAbsorb > 0)
                        {
                            float shPt = 18f * combinedScale * pixPerFlash;
                            shPt = Math.Max(4f, Math.Min(shPt, 36f));
                            segments.Add(new TextSegment(" \uD83D\uDEE1" + ((int)shieldAbsorb).ToString(),
                                Color.FromArgb(0x00, 0xCE, 0xD1), shPt, true));
                        }

                        // ======== 展开段为渲染子段 ========
                        List<RenderRun> runs = new List<RenderRun>();
                        for (int si = 0; si < segments.Count; si++)
                        {
                            TextSegment seg = segments[si];
                            SegmentToRuns(seg, runs);
                        }

                        // 测量总宽度
                        float totalWidth = 0;
                        using (StringFormat measureFmt = new StringFormat(StringFormat.GenericTypographic))
                        {
                            measureFmt.FormatFlags |= StringFormatFlags.NoWrap;
                            for (int ri = 0; ri < runs.Count; ri++)
                            {
                                RenderRun run = runs[ri];
                                Font f = GetCachedFont(run.FontIdx, run.Style, run.FontPt);
                                SizeF sz = g.MeasureString(run.Text, f, 9999, measureFmt);
                                run.MeasuredWidth = sz.Width;
                                totalWidth += sz.Width;
                            }
                        }

                        float drawX = bmpX - totalWidth / 2f;
                        float drawY = bmpY;

                        float penWidth = combinedBlur * pixPerFlash * 1.2f;
                        penWidth = Math.Max(1.0f, Math.Min(penWidth, 8f));

                        // ======== 逐子段绘制 ========
                        using (StringFormat sf = new StringFormat(StringFormat.GenericTypographic))
                        {
                            sf.FormatFlags |= StringFormatFlags.NoWrap;

                            for (int ri = 0; ri < runs.Count; ri++)
                            {
                                RenderRun run = runs[ri];
                                Font f = GetCachedFont(run.FontIdx, run.Style, run.FontPt);

                                Color fgColor = Color.FromArgb(a, run.Color.R, run.Color.G, run.Color.B);

                                {
                                    using (GraphicsPath path = new GraphicsPath())
                                    {
                                        path.AddString(run.Text,
                                            f.FontFamily, (int)f.Style,
                                            g.DpiY * f.SizeInPoints / 72f,
                                            new PointF(drawX, drawY), sf);

                                        using (Pen outlinePen = new Pen(Color.FromArgb(a, 0, 0, 0), penWidth))
                                        {
                                            outlinePen.LineJoin = LineJoin.Round;
                                            g.DrawPath(outlinePen, path);
                                        }

                                        using (SolidBrush fgBrush = new SolidBrush(fgColor))
                                        {
                                            g.FillPath(fgBrush, path);
                                        }
                                    }
                                }

                                drawX += run.MeasuredWidth;
                            }
                        }

                        // ======== 段数上标：12hit ========
                        if (hitCount > 1)
                        {
                            float numPt = mainPt * 0.55f;
                            numPt = Math.Max(6f, Math.Min(numPt, 36f));
                            float hitPt = numPt * 0.5f;
                            hitPt = Math.Max(4f, Math.Min(hitPt, 18f));

                            string numText = hitCount.ToString();
                            string hitText = "hit";

                            float supX = drawX + 2f;
                            float supY = drawY - mainPt * 0.35f;

                            Font numFont = GetCachedFont(FONT_IDX_NUMBER, FontStyle.Bold | FontStyle.Italic, numPt);
                            Font hitFont = GetCachedFont(FONT_IDX_LABEL, FontStyle.Bold | FontStyle.Italic, hitPt);

                            using (StringFormat supFmt = new StringFormat(StringFormat.GenericTypographic))
                            {
                                supFmt.FormatFlags |= StringFormatFlags.NoWrap;
                                Color cyan = Color.FromArgb(a, 0x00, 0xFF, 0xE0);

                                using (GraphicsPath numPath = new GraphicsPath())
                                {
                                    float numEm = g.DpiY * numFont.SizeInPoints / 72f;
                                    numPath.AddString(numText,
                                        numFont.FontFamily, (int)numFont.Style,
                                        numEm, new PointF(supX, supY), supFmt);

                                    using (Pen bp = new Pen(Color.FromArgb(a, 0, 0, 0), penWidth * 0.9f))
                                    {
                                        bp.LineJoin = LineJoin.Round;
                                        g.DrawPath(bp, numPath);
                                    }
                                    using (SolidBrush fb = new SolidBrush(cyan))
                                    {
                                        g.FillPath(fb, numPath);
                                    }

                                    RectangleF numBounds = numPath.GetBounds();
                                    float hitX = numBounds.Right + 1f;
                                    float hitY2 = supY + numEm - g.DpiY * hitFont.SizeInPoints / 72f;

                                    using (GraphicsPath hitPath = new GraphicsPath())
                                    {
                                        float hitEm = g.DpiY * hitFont.SizeInPoints / 72f;
                                        hitPath.AddString(hitText,
                                            hitFont.FontFamily, (int)hitFont.Style,
                                            hitEm, new PointF(hitX, hitY2), supFmt);

                                        using (Pen bp2 = new Pen(Color.FromArgb(a, 0, 0, 0), penWidth * 0.6f))
                                        {
                                            bp2.LineJoin = LineJoin.Round;
                                            g.DrawPath(bp2, hitPath);
                                        }
                                        using (SolidBrush fb2 = new SolidBrush(cyan))
                                        {
                                            g.FillPath(fb2, hitPath);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                CommitBitmap(bmp, scrX, scrY, 255);
            }
        }

        // 字体族常量（index 用于缓存 key）
        private const int FONT_IDX_NUMBER = 0;
        private const int FONT_IDX_LABEL  = 1;
        private const int FONT_IDX_EMOJI  = 2;

        private const string FONT_NUMBER = "Arial Black";
        private const string FONT_LABEL  = "Microsoft YaHei";
        private const string FONT_EMOJI  = "Segoe UI Symbol";
        private const FontStyle FONT_LABEL_STYLE = FontStyle.Bold;

        private class TextSegment
        {
            public string Text;
            public Color Color;
            public float FontPt;
            public bool IsLabel;

            public TextSegment(string text, Color color, float fontPt, bool isLabel = false)
            {
                Text = text;
                Color = color;
                FontPt = fontPt;
                IsLabel = isLabel;
            }
        }

        private class RenderRun
        {
            public string Text;
            public Color Color;
            public float FontPt;
            public int FontIdx;
            public FontStyle Style;
            public float MeasuredWidth;
        }

        private static bool ContainsEmoji(string text)
        {
            for (int i = 0; i < text.Length; i++)
            {
                char c = text[i];
                if (char.IsHighSurrogate(c)) return true;
                if (c >= 0x2600 && c <= 0x27BF) return true;
                if (c >= 0x2B50 && c <= 0x2B55) return true;
            }
            return false;
        }

        private static void SegmentToRuns(TextSegment seg, List<RenderRun> runs)
        {
            string text = seg.Text;
            if (string.IsNullOrEmpty(text)) return;

            if (!ContainsEmoji(text))
            {
                runs.Add(new RenderRun
                {
                    Text = text,
                    Color = seg.Color,
                    FontPt = seg.FontPt,
                    FontIdx = seg.IsLabel ? FONT_IDX_LABEL : FONT_IDX_NUMBER,
                    Style = seg.IsLabel ? FONT_LABEL_STYLE : FontStyle.Regular
                });
                return;
            }

            int start = 0;
            bool curEmoji = false;

            for (int i = 0; i <= text.Length; i++)
            {
                bool isEmoji = false;
                if (i < text.Length)
                {
                    char c = text[i];
                    if (char.IsLowSurrogate(c)) continue;
                    isEmoji = char.IsHighSurrogate(c)
                           || (c >= 0x2600 && c <= 0x27BF)
                           || (c >= 0x2B50 && c <= 0x2B55);
                }

                if (i == 0) { curEmoji = isEmoji; continue; }

                if (i == text.Length || isEmoji != curEmoji)
                {
                    string part = text.Substring(start, i - start);
                    if (part.Length > 0)
                    {
                        runs.Add(new RenderRun
                        {
                            Text = part,
                            Color = seg.Color,
                            FontPt = curEmoji ? seg.FontPt * 1.3f : seg.FontPt,
                            FontIdx = curEmoji ? FONT_IDX_EMOJI
                                   : (seg.IsLabel ? FONT_IDX_LABEL : FONT_IDX_NUMBER),
                            Style = curEmoji ? FontStyle.Regular
                                 : (seg.IsLabel ? FONT_LABEL_STYLE : FontStyle.Regular)
                        });
                    }
                    start = i;
                    curEmoji = isEmoji;
                }
            }
        }

        private Font GetCachedFont(int fontIdx, FontStyle style, float pt)
        {
            int bucket = (int)(pt * 2 + 0.5f);
            int key = (fontIdx << 16) | ((int)style << 8) | bucket;

            Font f;
            if (_fontCache.TryGetValue(key, out f))
                return f;

            string family;
            switch (fontIdx)
            {
                case FONT_IDX_EMOJI:  family = FONT_EMOJI;  break;
                case FONT_IDX_LABEL:  family = FONT_LABEL;  break;
                default:              family = FONT_NUMBER;  break;
            }

            f = new Font(family, pt, style);
            _fontCache[key] = f;
            return f;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                foreach (Font f in _fontCache.Values)
                    f.Dispose();
                _fontCache.Clear();
            }
            base.Dispose(disposing);
        }
    }
}
