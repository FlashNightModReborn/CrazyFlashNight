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
    /// 复用 ToastOverlay 的 Win32 / Owner-following / UpdateLayeredWindow 模式。
    ///
    /// 关键差异：
    /// - 无独立 Timer —— 由 Flash frame 消息驱动（每帧一次 UpdateRender）
    /// - 覆盖整个 Flash viewport（伤害数字可出现在任意位置）
    /// - 8 方向偏移描边模拟 GlowFilter
    /// </summary>
    public class HitNumberOverlay : Form
    {
        #region Win32 (identical to ToastOverlay)

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst,
            ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc,
            ref POINT pptSrc, uint crKey, ref BLENDFUNCTION pblend, uint dwFlags);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll", ExactSpelling = true)]
        private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hObj);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteObject(IntPtr hObj);

        [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
        private static extern bool DeleteDC(IntPtr hdc);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int x, y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct SIZE { public int cx, cy; }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct BLENDFUNCTION
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        private const int SW_SHOWNOACTIVATE = 4;
        private const int SW_HIDE = 0;
        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const byte AC_SRC_OVER = 0x00;
        private const byte AC_SRC_ALPHA = 0x01;
        private const uint ULW_ALPHA = 0x02;

        private const int WS_EX_TOOLWINDOW = 0x00000080;
        private const int WS_EX_NOACTIVATE = 0x08000000;
        private const int WS_EX_LAYERED = 0x00080000;
        private const int WS_EX_TRANSPARENT = 0x00000020;
        private const int WM_NCHITTEST = 0x0084;
        private const int HTTRANSPARENT = -1;

        #endregion

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

        private readonly Form _owner;
        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly List<string> _earlyBuffer;
        private bool _ready;
        private bool _shown;
        private bool _ownerVisible;
        private string _currentRenderStr;

        // Font cache: 4 档位避免循环内 new Font
        private Font _numberFont;
        private Font _effectFont;
        private int _lastVpW;

        public HitNumberOverlay(Form owner, Control anchor)
        {
            _owner = owner;
            _anchor = anchor;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _earlyBuffer = new List<string>();
            _ready = false;
            _shown = false;
            _ownerVisible = true;
            _currentRenderStr = null;

            this.FormBorderStyle = FormBorderStyle.None;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.Manual;
            this.Owner = owner;

            CreateHandle();

            // 位置跟踪
            owner.Move += delegate { RepaintIfShown(); };
            owner.Resize += delegate { RepaintIfShown(); };
            anchor.Resize += delegate { RepaintIfShown(); };

            // Owner 可见性跟踪
            owner.Activated += delegate { OnOwnerActivated(); };
            owner.Deactivate += delegate { OnOwnerDeactivated(); };
            owner.Resize += delegate
            {
                if (owner.WindowState == FormWindowState.Minimized)
                    OnOwnerDeactivated();
                else
                    OnOwnerActivated();
            };
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
                             | WS_EX_LAYERED | WS_EX_TRANSPARENT;
                return cp;
            }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_NCHITTEST)
            {
                m.Result = (IntPtr)HTTRANSPARENT;
                return;
            }
            base.WndProc(ref m);
        }

        #region Owner following

        private void OnOwnerActivated()
        {
            _ownerVisible = true;
            if (_shown && !string.IsNullOrEmpty(_currentRenderStr))
            {
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                PaintLayered();
            }
        }

        private void OnOwnerDeactivated()
        {
            _ownerVisible = false;
            if (_shown)
                ShowWindow(this.Handle, SW_HIDE);
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
            if (_shown)
            {
                _shown = false;
                ShowWindow(this.Handle, SW_HIDE);
            }
        }

        #endregion

        private void DoUpdateRender(string renderStr)
        {
            _currentRenderStr = renderStr;

            if (string.IsNullOrEmpty(renderStr))
            {
                if (_shown)
                {
                    _shown = false;
                    ShowWindow(this.Handle, SW_HIDE);
                }
                return;
            }

            if (!_shown && _ownerVisible)
            {
                _shown = true;
                ShowWindow(this.Handle, SW_SHOWNOACTIVATE);
                SetWindowPos(this.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }

            if (_ownerVisible)
                PaintLayered();
        }

        private void RepaintIfShown()
        {
            if (_shown && _ownerVisible && !string.IsNullOrEmpty(_currentRenderStr))
                PaintLayered();
        }

        private void EnsureFont()
        {
            int vpW = (int)_mapper.ViewportWidth;
            if (vpW == _lastVpW) return;
            _lastVpW = vpW;

            float scale = vpW / 1024f;
            float numPt = 28f * scale;  // SWF base font size = 28pt
            numPt = Math.Max(8f, Math.Min(numPt, 56f));
            float efPt = 14f * scale;
            efPt = Math.Max(6f, Math.Min(efPt, 28f));

            if (_numberFont != null) _numberFont.Dispose();
            if (_effectFont != null) _effectFont.Dispose();
            _numberFont = new Font("Arial Black", numPt, FontStyle.Regular);
            _effectFont = new Font("Microsoft YaHei", efPt, FontStyle.Bold);
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
            try { origin = _anchor.PointToScreen(Point.Empty); }
            catch { origin = Point.Empty; }

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
                        // Flash buildHtml 将所有标签拼接在一行（<font> 标签改色不换行）
                        // C# 用分段绘制模拟：每段有自己的 (text, color, fontSizePt)

                        List<TextSegment> segments = new List<TextSegment>();

                        // 主伤害数字
                        string mainText = isMiss ? "MISS" : damage.ToString();
                        float mainPt = fontSize * combinedScale * pixPerFlash;
                        mainPt = Math.Max(6f, Math.Min(mainPt, 72f));
                        segments.Add(new TextSegment(mainText, mainColor, mainPt));

                        // 效果标签（Flash 中 size=20，按比例缩放）
                        float labelPt = 20f * combinedScale * pixPerFlash;
                        labelPt = Math.Max(4f, Math.Min(labelPt, 40f));

                        // EF_DMG_TYPE_LABEL (bit 3): " 真" / " 能" 等，用主伤害颜色
                        if ((flags & 8) != 0 && !string.IsNullOrEmpty(efText))
                            segments.Add(new TextSegment(" " + efText, mainColor, labelPt, true));

                        // EF_CRUSH_LABEL (bit 4): " ✨破击" 等，固定 #66bcf5
                        if ((flags & 16) != 0 && !string.IsNullOrEmpty(efText))
                        {
                            string crushText = " " + (string.IsNullOrEmpty(efEmoji) ? "" : efEmoji) + efText;
                            segments.Add(new TextSegment(crushText, Color.FromArgb(0x66, 0xBC, 0xF5), labelPt, true));
                        }

                        // EF_TOXIC (bit 1): " 毒"，固定 #66dd00
                        if ((flags & 2) != 0)
                            segments.Add(new TextSegment(" 毒", Color.FromArgb(0x66, 0xDD, 0x00), labelPt, true));

                        // EF_LIFESTEAL (bit 5): " 汲:X"，固定 #bb00aa，Flash size=15
                        if ((flags & 32) != 0 && lifeSteal > 0)
                        {
                            float lsPt = 15f * combinedScale * pixPerFlash;
                            lsPt = Math.Max(4f, Math.Min(lsPt, 30f));
                            segments.Add(new TextSegment(" 汲:" + ((int)lifeSteal).ToString(),
                                Color.FromArgb(0xBB, 0x00, 0xAA), lsPt, true));
                        }

                        // EF_CRUMBLE (bit 0): " 溃"，固定 #FF3333
                        if ((flags & 1) != 0)
                            segments.Add(new TextSegment(" 溃", Color.FromArgb(0xFF, 0x33, 0x33), labelPt, true));

                        // EF_EXECUTE (bit 2): " 斩"，敌方 #660033 / 友方 #4A0099
                        if ((flags & 4) != 0)
                        {
                            Color exeColor = ((flags & 128) != 0)
                                ? Color.FromArgb(0x66, 0x00, 0x33)
                                : Color.FromArgb(0x4A, 0x00, 0x99);
                            segments.Add(new TextSegment(" 斩", exeColor, labelPt, true));
                        }

                        // EF_SHIELD (bit 8): " 🛡X"，固定 #00CED1，Flash size=18
                        if ((flags & 256) != 0 && shieldAbsorb > 0)
                        {
                            float shPt = 18f * combinedScale * pixPerFlash;
                            shPt = Math.Max(4f, Math.Min(shPt, 36f));
                            // 🛡 = U+1F6E1，C# 中用 surrogate pair
                            segments.Add(new TextSegment(" \uD83D\uDEE1" + ((int)shieldAbsorb).ToString(),
                                Color.FromArgb(0x00, 0xCE, 0xD1), shPt, true));
                        }

                        // ======== 测量总宽度 → 居中 ========
                        // ======== 展开段为渲染子段（emoji / 非 emoji 分离）========
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
                                using (Font f = CreateRunFont(run))
                                {
                                    SizeF sz = g.MeasureString(run.Text, f, 9999, measureFmt);
                                    run.MeasuredWidth = sz.Width;
                                    run.ResolvedFont = f.Clone() as Font;
                                    totalWidth += sz.Width;
                                }
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
                                Font f = run.ResolvedFont;
                                if (f == null) continue;

                                Color fgColor = Color.FromArgb(a, run.Color.R, run.Color.G, run.Color.B);

                                {
                                    // 非 emoji: GraphicsPath 描边 + 填充
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
                                f.Dispose();
                            }
                        }

                        // ======== 段数上标（×N）========
                        // 独立于文本段，定位在主数字右上角
                        // 设计参考 Hades：小字号 + 上标偏移 + 白色描边 + 黄色填充 + 细体
                        if (hitCount > 1)
                        {
                            float countPt = mainPt * 0.55f;
                            countPt = Math.Max(6f, Math.Min(countPt, 36f));
                            string countText = "\u00D7" + hitCount.ToString();

                            float supX = drawX + 2f;
                            float supY = drawY - mainPt * 0.35f;

                            // 斜体 + 黑描边 + 荧光青填充
                            // 斜体与主数字的正体形成即时视觉区分
                            using (StringFormat supFmt = new StringFormat(StringFormat.GenericTypographic))
                            using (Font countFont = new Font(FONT_NUMBER, countPt, FontStyle.Bold | FontStyle.Italic))
                            using (GraphicsPath countPath = new GraphicsPath())
                            {
                                supFmt.FormatFlags |= StringFormatFlags.NoWrap;
                                float emSize = g.DpiY * countFont.SizeInPoints / 72f;
                                countPath.AddString(countText,
                                    countFont.FontFamily, (int)countFont.Style,
                                    emSize, new PointF(supX, supY), supFmt);

                                // 黑描边（与主数字一致，任何背景可读）
                                using (Pen blackPen = new Pen(Color.FromArgb(a, 0, 0, 0), penWidth * 0.9f))
                                {
                                    blackPen.LineJoin = LineJoin.Round;
                                    g.DrawPath(blackPen, countPath);
                                }

                                // 荧光青填充（高饱和、不与任何伤害色撞色）
                                using (SolidBrush countBrush = new SolidBrush(
                                    Color.FromArgb(a, 0x00, 0xFF, 0xE0)))
                                {
                                    g.FillPath(countBrush, countPath);
                                }
                            }
                        }
                    }
                }

                // UpdateLayeredWindow
                IntPtr hdcScreen = IntPtr.Zero;
                IntPtr hdcMem = CreateCompatibleDC(hdcScreen);
                IntPtr hBmp = bmp.GetHbitmap(Color.FromArgb(0));
                IntPtr hOld = SelectObject(hdcMem, hBmp);

                try
                {
                    POINT ptDst = new POINT { x = scrX, y = scrY };
                    SIZE sz = new SIZE { cx = bmpW, cy = bmpH };
                    POINT ptSrc = new POINT { x = 0, y = 0 };
                    BLENDFUNCTION blend = new BLENDFUNCTION
                    {
                        BlendOp = AC_SRC_OVER,
                        BlendFlags = 0,
                        SourceConstantAlpha = 255,
                        AlphaFormat = AC_SRC_ALPHA
                    };

                    UpdateLayeredWindow(this.Handle, hdcScreen,
                        ref ptDst, ref sz, hdcMem, ref ptSrc, 0, ref blend, ULW_ALPHA);
                }
                finally
                {
                    SelectObject(hdcMem, hOld);
                    DeleteObject(hBmp);
                    DeleteDC(hdcMem);
                }
            }
        }

        // 字体族常量
        private const string FONT_NUMBER = "Arial Black";          // 数字（匹配 SWF face="Arial-Black"）
        private const string FONT_LABEL = "Microsoft YaHei";       // 中文标签（粗体、内置、免嵌入）
        private const FontStyle FONT_LABEL_STYLE = FontStyle.Bold;

        /// <summary>内部文本段（单行内的一个颜色/大小片段）</summary>
        private class TextSegment
        {
            public string Text;
            public Color Color;
            public float FontPt;
            public bool IsLabel;       // true = 中文标签用 YaHei Bold，false = 数字用 Arial Black
            public float MeasuredWidth;
            public Font Font;

            public TextSegment(string text, Color color, float fontPt, bool isLabel = false)
            {
                Text = text;
                Color = color;
                FontPt = fontPt;
                IsLabel = isLabel;
            }
        }

        /// <summary>渲染子段</summary>
        private class RenderRun
        {
            public string Text;
            public Color Color;
            public float FontPt;
            public bool IsLabel;
            public float MeasuredWidth;
            public Font ResolvedFont;
        }

        /// <summary>
        /// Emoji → 中文替换。GDI+ GraphicsPath 不支持 emoji 字形轮廓，
        /// 且 DrawString font linking 在不同 Windows 版本上不可靠。
        /// 统一替换为 YaHei Bold 有字形的中文字，走 GraphicsPath 描边，
        /// 与所有其他标签视觉完全一致。
        /// </summary>
        private static string ReplaceEmoji(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            // SMP emoji（surrogate pairs）
            text = text.Replace("\uD83D\uDEE1", "\u76FE");  // 🛡 → 盾
            // BMP 符号
            text = text.Replace("\u2728", "\u2606");          // ✨ → ☆
            text = text.Replace("\u2620", "\u2620");          // ☠ → ☠ (YaHei 有此字形)
            return text;
        }

        /// <summary>将 TextSegment 转为 RenderRun（应用 emoji 替换）</summary>
        private static void SegmentToRuns(TextSegment seg, List<RenderRun> runs)
        {
            string text = ReplaceEmoji(seg.Text);
            if (string.IsNullOrEmpty(text)) return;
            runs.Add(new RenderRun
            {
                Text = text,
                Color = seg.Color,
                FontPt = seg.FontPt,
                IsLabel = seg.IsLabel
            });
        }

        /// <summary>根据 RenderRun 属性创建对应字体</summary>
        private static Font CreateRunFont(RenderRun run)
        {
            string family = run.IsLabel ? FONT_LABEL : FONT_NUMBER;
            FontStyle style = run.IsLabel ? FONT_LABEL_STYLE : FontStyle.Regular;
            return new Font(family, run.FontPt, style);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_numberFont != null) _numberFont.Dispose();
                if (_effectFont != null) _effectFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
