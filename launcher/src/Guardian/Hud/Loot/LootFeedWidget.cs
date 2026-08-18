using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud.Loot
{
    /// <summary>
    /// Loot feed 渲染单元：左下血条上方的物品获得播报卡（图标 + 名称 + ×n）。
    /// Native C# GDI+ 单渲染端（P1 决策：无 web fallback，零依赖过渡组件）。
    ///
    /// 数据通路：AS2 _root.发布战利品消息 → socket {"task":"loot"} → LootFeedTask
    ///   → LootFeedWidget.AddEvent（BeginInvoke 到 UI 线程）→ LootFeedModel → Paint
    ///
    /// 视觉：锚底 Flash (5,505)（贴底部 HUD 条顶 512），向上堆叠、新卡在最底；
    /// 卡片 = 左色条（kind 分色）+ 图标 + 名称 + ×n；超出 5 张折叠"还有 n 条"。
    /// 闲置时 Visible=false 且 WantsAnimationTick=false，零 tick 成本。
    /// </summary>
    public sealed class LootFeedWidget : INativeHudWidget, IDisposable
    {
        private const float FlashX = 5f;
        private const float FlashBottomY = 460f; // 与底部 HUD 条（顶 512）保持距离，远离血球
        private const float MaxCardW = 190f; // 内容宽度胶囊的宽度上限（超出省略号）
        private const float CardH = 26f;
        private const float CardGap = 3f;
        private const float OverflowRowH = 13f;
        private const int FadeInMs = 200;
        private const int PulseMs = 200; // 合并/新卡事件后的动效窗口（计数弹跳 + 底色/色条脉冲）

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly LootFeedModel _model;
        private readonly LootIconCatalog _icons;
        private long _animMs; // 动画全局时钟（Tick 推进），驱动动画图标帧（png-sequence 均匀帧率 / webp-animated 逐帧时长）

        private Font _nameFont;
        private float _lastFontScale = -1f;
        private readonly Dictionary<string, int> _textWidthCache =
            new Dictionary<string, int>(StringComparer.Ordinal);
        private int _lastVisualSignature;

        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged;

        public LootFeedWidget(Control anchor, LootIconCatalog icons)
        {
            if (anchor == null) throw new ArgumentNullException("anchor");
            if (icons == null) throw new ArgumentNullException("icons");
            _anchor = anchor;
            _icons = icons;
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _model = new LootFeedModel();
            _nameFont = NativeHudFonts.CreateUiFont(NameFontPxForScale(1f), FontStyle.Regular, GraphicsUnit.Pixel);
            _anchor.Resize += delegate { FireBounds(); };
        }

        #region INativeHudWidget

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible) return Rectangle.Empty;
                if (_anchor == null || !_anchor.IsHandleCreated) return Rectangle.Empty;
                EnsureFont();
                float scale = GetViewportScale();
                int cards = Math.Min(LootFeedModel.MaxVisibleCards, _model.ActiveCount);
                float rowsH = cards * (CardH + CardGap);
                if (_model.OverflowCount > 0) rowsH += OverflowRowH; // 与 Paint 的占位口径一致
                int scrX, scrBottom;
                _mapper.FlashToScreen(FlashX, FlashBottomY, out scrX, out scrBottom);
                int w = MeasureWidestCardPx(scale);
                int h = Math.Max(4, _mapper.ScaleH(rowsH));
                return new Rectangle(scrX, scrBottom - h, w, h);
            }
        }

        public bool Visible
        {
            get { return _model.ActiveCount > 0 || _model.DroppedCount > 0; }
        }

        public bool WantsAnimationTick { get { return Visible; } }

        public void Tick(int deltaMs)
        {
            bool had = _model.ActiveCount > 0;
            _animMs += Math.Max(0, deltaMs);
            bool removed = _model.Tick(deltaMs);
            bool has = _model.ActiveCount > 0;
            if (had != has) FireAnimationStateChanged();
            if (removed || had != has) FireBounds();
            if (!has && !had) return;

            // 重绘门控：仅可视状态实际变化才申请重绘（静态卡零重绘，
            // 缓解 NativeHud 单一 union 位图在全屏下的重绘放大）
            int sig = ComputeVisualSignature();
            if (sig != _lastVisualSignature)
            {
                _lastVisualSignature = sig;
                FireRepaint();
            }
        }

        /// <summary>
        /// 可视状态签名：卡片集合/计数、淡出相位（64ms 桶）、脉冲相位（32ms 桶）、
        /// 入场滑相位（32ms 桶）、动画图标当前帧。任何一项变化 ⇒ 签名变化 ⇒ 触发重绘。
        /// </summary>
        private int ComputeVisualSignature()
        {
            unchecked
            {
                int sig = _model.ActiveCount * 31 + _model.OverflowCount * 7;
                int now = _model.NowMs;
                IReadOnlyList<LootFeedModel.LootCard> cards = _model.Cards;
                int first = Math.Max(0, cards.Count - LootFeedModel.MaxVisibleCards);
                for (int i = first; i < cards.Count; i++)
                {
                    LootFeedModel.LootCard c = cards[i];
                    sig = sig * 31 + (int)c.Count;
                    int age = now - c.LastEventMs;
                    if (age > LootFeedModel.HoldMs)
                        sig = sig * 31 + ((LootFeedModel.HoldMs + LootFeedModel.FadeMs - age) >> 6);
                    else if (age < PulseMs)
                        sig = sig * 31 + 1000 + (age >> 5);
                    int bornAge = now - c.BornMs;
                    if (bornAge < FadeInMs)
                        sig = sig * 31 + 2000 + (bornAge >> 5);
                    if (!string.IsNullOrEmpty(c.Icon))
                    {
                        LootIconCatalog.LootIconFrames fr;
                        if (_icons.TryGet(c.Icon, out fr) && fr.Animated)
                            sig = sig * 31 + SelectFrameIndex(fr, _animMs);
                    }
                }
                return sig;
            }
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            if (!Visible) return;
            EnsureFont();
            float scale = GetViewportScale();
            int cardH = Math.Max(4, _mapper.ScaleH(CardH));
            int gap = Math.Max(1, _mapper.ScaleH(CardGap));
            int iconSz = cardH - Px(4, scale) * 2;
            int padX = Px(6, scale);
            float shadowOffset = Pxf(1f, scale);

            int scrX, scrBottom;
            _mapper.FlashToScreen(FlashX, FlashBottomY, out scrX, out scrBottom);
            int localX = scrX - hudOrigin.X;
            int localBottom = scrBottom - hudOrigin.Y;
            int maxCardW = _mapper.ScaleW(MaxCardW);
            int barW = BarWidthPx(scale);

            // 取最新 MaxVisibleCards 张；列表为 旧→新，绘制时新卡在底部
            IReadOnlyList<LootFeedModel.LootCard> cards = _model.Cards;
            int total = cards.Count;
            int first = Math.Max(0, total - LootFeedModel.MaxVisibleCards);
            int now = _model.NowMs;

            SmoothingMode oldSmooth = g.SmoothingMode;
            TextRenderingHint oldHint = g.TextRenderingHint;
            InterpolationMode oldInterp = g.InterpolationMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            try
            {
                int y = localBottom;

                for (int i = total - 1; i >= first; i--)
                {
                    LootFeedModel.LootCard card = cards[i];
                    y -= cardH;
                    float a = LootFeedModel.AlphaFor(card, now, FadeInMs);
                    if (a <= 0.01f) { y -= gap; continue; }

                    // 新卡左滑入场（FadeIn 窗口内二次方缓出，纯时间函数零对象）
                    int slideOff = 0;
                    int bornAge = now - card.BornMs;
                    if (bornAge < FadeInMs)
                    {
                        float st = 1f - (float)bornAge / FadeInMs;
                        slideOff = -(int)(12 * scale * st * st);
                    }

                    // 内容宽度胶囊：宽度随图标+文本实测伸缩，短文本不拖黑尾
                    int cardW = MeasureCardWidthPx(card, iconSz, padX, barW, maxCardW);
                    Rectangle cardRect = new Rectangle(localX + slideOff, y, cardW, cardH);
                    DrawCard(g, card, cardRect, iconSz, padX, barW, shadowOffset, scale, a, now);
                    y -= gap;
                }

                // 溢出折叠行：与卡片同规则先占位再绘制（此前直接画在 y 处，
                // 行体向下延伸压进顶部卡片区域导致被遮盖）
                int overflow = _model.OverflowCount;
                if (overflow > 0)
                {
                    int rowH = Math.Max(4, _mapper.ScaleH(OverflowRowH));
                    y -= rowH;
                    using (SolidBrush brush = new SolidBrush(Color.FromArgb(200, 0xAA, 0xAA, 0xAA)))
                    using (StringFormat sf = new StringFormat())
                    {
                        sf.Trimming = StringTrimming.EllipsisCharacter;
                        RectangleF rect = new RectangleF(localX + padX, y, maxCardW - padX, rowH);
                        g.DrawString("还有 " + overflow + " 条…", _nameFont, brush, rect, sf);
                    }
                }
            }
            finally
            {
                g.SmoothingMode = oldSmooth;
                g.TextRenderingHint = oldHint;
                g.InterpolationMode = oldInterp;
            }
        }

        public bool TryHitTest(Point screenPt) { return false; }
        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }

        #endregion

        #region 公共 API（socket 线程入口，内部 marshal 到 UI 线程）

        /// <summary>
        /// 烘焙完成通知（DollPortraitBakeService.PortraitReady 回调，任意线程）：
        /// 失效该 ref 的负缓存并申请重绘——仍在存活期内的占位卡片原地升级为胸像。
        /// </summary>
        public void NotifyIconReady(string iconRef)
        {
            if (string.IsNullOrEmpty(iconRef)) return;
            if (_anchor == null || _anchor.IsDisposed || !_anchor.IsHandleCreated) return;
            try
            {
                _anchor.BeginInvoke((Action)(delegate
                {
                    _icons.InvalidateDoll(iconRef);
                    FireRepaint();
                }));
            }
            catch (InvalidOperationException) { }
        }

        /// <summary>
        /// LootTask 调用点（socket 线程）。BeginInvoke 到 UI 线程再改模型；
        /// handle 未就绪/已销毁时静默丢弃（刻意不做 early-buffer：loot 事件只在 gameplay 后产生）。
        /// </summary>
        public void AddEvent(string kind, string name, long count, string source, string icon)
        {
            if (_anchor == null || _anchor.IsDisposed || !_anchor.IsHandleCreated) return;
            try
            {
                _anchor.BeginInvoke((Action)(delegate
                {
                    bool had = _model.ActiveCount > 0;
                    _model.Add(kind, name, icon, count, source);
                    if (!had && _model.ActiveCount > 0) FireAnimationStateChanged();
                    FireBounds();
                    FireRepaint();
                }));
            }
            catch (InvalidOperationException) { }
        }

        #endregion

        private void DrawCard(Graphics g, LootFeedModel.LootCard card, Rectangle rect,
            int iconSz, int padX, int barW, float shadowOffset, float scale, float a, int nowMs)
        {
            byte alpha = (byte)Math.Max(0, Math.Min(255, (int)(255 * a)));
            Color accent = KindColor(card.Kind);

            // 事件脉冲：合并/新卡后 PulseMs 内衰减；割草连杀时卡片持续脉动反馈
            int eventAge = nowMs - card.LastEventMs;
            float pulseT = eventAge < PulseMs ? 1f - (float)eventAge / PulseMs : 0f;

            // 半透明黑圆角底（低存在感：信息流背景刻意弱化；脉冲期短暂提亮）
            using (GraphicsPath path = RoundedRect(rect, Px(4, scale)))
            using (SolidBrush bg = new SolidBrush(Color.FromArgb((byte)((80 + 70 * pulseT) * a), 12, 12, 16)))
                g.FillPath(bg, path);

            // 左色条（脉冲期加宽）
            int barWPulse = barW + (int)Math.Round(2 * scale * pulseT);
            using (SolidBrush bar = new SolidBrush(Color.FromArgb(alpha, accent.R, accent.G, accent.B)))
                g.FillRectangle(bar, rect.X, rect.Y + 2, barWPulse, rect.Height - 4);

            // 图标（缺失 → kind 色占位块 + 名称首字）；动画按全局时钟选帧（逐帧时长优先，否则均匀 fps）
            int iconX = rect.X + padX + barW;
            int iconY = rect.Y + (rect.Height - iconSz) / 2;
            Bitmap icon = null;
            if (!string.IsNullOrEmpty(card.Icon))
            {
                LootIconCatalog.LootIconFrames iconFrames;
                if (_icons.TryGet(card.Icon, out iconFrames) && iconFrames.First != null)
                {
                    icon = iconFrames.Frames[SelectFrameIndex(iconFrames, _animMs)];
                }
            }
            if (icon != null)
            {
                DrawBitmapAlpha(g, icon, new Rectangle(iconX, iconY, iconSz, iconSz), a);
            }
            else
            {
                using (SolidBrush ph = new SolidBrush(Color.FromArgb((byte)(70 * a), accent.R, accent.G, accent.B)))
                    g.FillRectangle(ph, iconX, iconY, iconSz, iconSz);
                string glyph = string.IsNullOrEmpty(card.Name) ? "?" : card.Name.Substring(0, 1);
                using (SolidBrush fg = new SolidBrush(Color.FromArgb(alpha, 0xFF, 0xFF, 0xFF)))
                using (StringFormat sf = new StringFormat())
                {
                    sf.Alignment = StringAlignment.Center;
                    sf.LineAlignment = StringAlignment.Center;
                    g.DrawString(glyph, _nameFont, fg,
                        new RectangleF(iconX, iconY, iconSz, iconSz), sf);
                }
            }

            // 名称（白）+ ×n（kind 色常驻；脉冲期放大回弹——割草连杀时的主要反馈）
            string name = card.Name ?? "";
            string countStr = card.Count > 1 ? "×" + card.Count : "";
            float textX = iconX + iconSz + padX;
            float midY = rect.Y + rect.Height / 2f;

            int nameW = MeasureTextCached(name);
            int countW = countStr.Length > 0 ? MeasureTextCached(countStr) : 0;
            int countGap = countStr.Length > 0 ? Px(3, scale) : 0;
            // 脉冲余量已在卡宽侧承担（MeasureCardWidthPx 同款口径），这里只做减法还原
            int countReserve = countStr.Length > 0 ? countGap + (int)(countW * 1.45f) : 0;
            float nameAvailW = Math.Max(8, rect.Right - textX - padX - countReserve);

            using (StringFormat sf = new StringFormat(StringFormat.GenericTypographic))
            {
                sf.Trimming = StringTrimming.EllipsisCharacter;
                sf.LineAlignment = StringAlignment.Center;
                sf.FormatFlags = StringFormatFlags.NoWrap;
                byte sa = (byte)Math.Max(0, Math.Min(255, (int)(200 * a)));
                RectangleF nameRect = new RectangleF(textX, rect.Y, nameAvailW, rect.Height);
                using (SolidBrush shadowBrush = new SolidBrush(Color.FromArgb(sa, 0, 0, 0)))
                {
                    g.DrawString(name, _nameFont, shadowBrush,
                        new RectangleF(nameRect.X + shadowOffset, nameRect.Y + shadowOffset,
                            nameRect.Width, nameRect.Height), sf);
                }
                using (SolidBrush fg = new SolidBrush(Color.FromArgb(alpha, 0xFF, 0xFF, 0xFF)))
                    g.DrawString(name, _nameFont, fg, nameRect, sf);

                if (countStr.Length > 0)
                {
                    float countX = textX + Math.Min(nameW, nameAvailW) + countGap;
                    using (SolidBrush countBrush = new SolidBrush(Color.FromArgb(alpha, accent.R, accent.G, accent.B)))
                    using (SolidBrush countShadow = new SolidBrush(Color.FromArgb(sa, 0, 0, 0)))
                    using (StringFormat csf = new StringFormat(StringFormat.GenericTypographic))
                    {
                        csf.FormatFlags = StringFormatFlags.NoWrap;
                        csf.LineAlignment = StringAlignment.Center;
                        if (pulseT > 0.001f)
                        {
                            // 脉冲期：放大回弹（Graphics 变换，font 复用零分配）
                            float popS = 1f + 0.45f * pulseT * pulseT;
                            GraphicsContainer container = g.BeginContainer();
                            try
                            {
                                g.TranslateTransform(countX, midY);
                                g.ScaleTransform(popS, popS);
                                float dy = -_nameFont.Height / 2f;
                                g.DrawString(countStr, _nameFont, countShadow, shadowOffset, dy + shadowOffset, csf);
                                g.DrawString(countStr, _nameFont, countBrush, 0, dy, csf);
                            }
                            finally
                            {
                                g.EndContainer(container);
                            }
                        }
                        else
                        {
                            // 常规路径：无变换直接绘制（绝大多数帧走这里）
                            RectangleF countRect = new RectangleF(countX, rect.Y,
                                rect.Right - countX, rect.Height);
                            g.DrawString(countStr, _nameFont, countShadow,
                                new RectangleF(countRect.X + shadowOffset, countRect.Y + shadowOffset,
                                    countRect.Width, countRect.Height), csf);
                            g.DrawString(countStr, _nameFont, countBrush, countRect, csf);
                        }
                    }
                }
            }
        }

        private static string CardText(LootFeedModel.LootCard card)
        {
            return card.Count > 1 ? card.Name + " ×" + card.Count : card.Name;
        }

        /// <summary>
        /// 动画选帧：有逐帧时长（webp-animated）按 animMs % 总周期做累计时长查找；
        /// 否则维持均匀 fps 路径（png-sequence）。非动画/异常输入恒回第 0 帧。
        /// </summary>
        internal static int SelectFrameIndex(LootIconCatalog.LootIconFrames frames, long animMs)
        {
            if (frames == null || frames.Frames == null || frames.Frames.Length < 2 || animMs < 0) return 0;
            int[] durations = frames.DurationMs;
            if (durations != null && durations.Length == frames.Frames.Length)
            {
                long total = 0;
                for (int i = 0; i < durations.Length; i++) total += Math.Max(0, durations[i]);
                if (total > 0)
                {
                    long t = animMs % total;
                    long acc = 0;
                    for (int i = 0; i < durations.Length; i++)
                    {
                        acc += Math.Max(0, durations[i]);
                        if (t < acc) return i;
                    }
                    return frames.Frames.Length - 1;
                }
            }
            return (int)((animMs * (long)frames.Fps) / 1000L % frames.Frames.Length);
        }

        private static int BarWidthPx(float scale)
        {
            return Math.Max(2, Px(3, scale));
        }

        private int MeasureCardWidthPx(LootFeedModel.LootCard card, int iconSz, int padX, int barW, int maxCardW)
        {
            float scale = GetViewportScale();
            int nameW = MeasureTextCached(card.Name ?? "");
            int countW = card.Count > 1 ? MeasureTextCached("×" + card.Count) : 0;
            // 脉冲余量并入卡宽：×n 脉冲放大 1.45× 由卡片承担，不挤压名字宽度
            int w = barW + padX + iconSz + padX + nameW
                + (countW > 0 ? Px(3, scale) + (int)(countW * 1.45f) : 0)
                + padX + Px(8, scale);
            return Math.Max(barW + padX + iconSz + padX * 2, Math.Min(w, maxCardW));
        }

        /// <summary>文本宽度按内容缓存（合并/刷新反复重绘同一字符串，字体重建时清空）。</summary>
        private int MeasureTextCached(string text)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int w;
            if (_textWidthCache.TryGetValue(text, out w)) return w;
            w = TextRenderer.MeasureText(text, _nameFont,
                new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding).Width;
            _textWidthCache[text] = w;
            return w;
        }

        private int MeasureWidestCardPx(float scale)
        {
            int iconSz = Math.Max(4, _mapper.ScaleH(CardH)) - Px(4, scale) * 2;
            int padX = Px(6, scale);
            int barW = BarWidthPx(scale);
            int maxCardW = _mapper.ScaleW(MaxCardW);
            int widest = maxCardW / 2; // 兜底（overflow-only 等无卡场景）
            IReadOnlyList<LootFeedModel.LootCard> cards = _model.Cards;
            int first = Math.Max(0, cards.Count - LootFeedModel.MaxVisibleCards);
            for (int i = first; i < cards.Count; i++)
            {
                int w = MeasureCardWidthPx(cards[i], iconSz, padX, barW, maxCardW);
                if (w > widest) widest = w;
            }
            return widest;
        }

        private static void DrawBitmapAlpha(Graphics g, Bitmap bmp, Rectangle dest, float a)
        {
            if (a >= 0.999f)
            {
                g.DrawImage(bmp, dest, 0, 0, bmp.Width, bmp.Height, GraphicsUnit.Pixel);
                return;
            }
            System.Drawing.Imaging.ColorMatrix cm = new System.Drawing.Imaging.ColorMatrix();
            cm.Matrix33 = Math.Max(0f, Math.Min(1f, a));
            System.Drawing.Imaging.ImageAttributes attrs = new System.Drawing.Imaging.ImageAttributes();
            attrs.SetColorMatrix(cm);
            g.DrawImage(bmp, dest, 0, 0, bmp.Width, bmp.Height, GraphicsUnit.Pixel, attrs);
            attrs.Dispose();
        }

        private static GraphicsPath RoundedRect(Rectangle rect, int radius)
        {
            int d = Math.Max(2, radius * 2);
            GraphicsPath path = new GraphicsPath();
            path.AddArc(rect.X, rect.Y, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        private static Color KindColor(string kind)
        {
            switch (kind)
            {
                case "money": return Color.FromArgb(0xFF, 0xCC, 0x00);
                case "kpoint": return Color.FromArgb(0x66, 0xCC, 0xFF);
                case "intel": return Color.FromArgb(0xCC, 0x99, 0xFF);
                case "kill": return Color.FromArgb(0xE5, 0x48, 0x4D); // 击杀：绯红
                default: return Color.FromArgb(0xF0, 0xF0, 0xF0); // item / equip
            }
        }

        private void EnsureFont()
        {
            float scale = GetViewportScale();
            if (Math.Abs(scale - _lastFontScale) < 0.01f && _nameFont != null) return;
            _lastFontScale = scale;
            if (_nameFont != null) _nameFont.Dispose();
            _nameFont = NativeHudFonts.CreateUiFont(NameFontPxForScale(scale), FontStyle.Regular, GraphicsUnit.Pixel);
            _textWidthCache.Clear(); // 字号变化后旧宽度全部失效
        }

        private float GetViewportScale()
        {
            float vpX, vpY, vpW, vpH;
            _mapper.CalcViewport(out vpX, out vpY, out vpW, out vpH);
            if (vpH <= 0) return 1f;
            return Math.Max(0.5f, vpH / _mapper.StageHeight);
        }

        private static int Px(int basePx, float scale)
        {
            return Math.Max(1, (int)Math.Round(basePx * scale));
        }

        private static float Pxf(float basePx, float scale)
        {
            return Math.Max(1f, basePx * scale);
        }

        internal static float NameFontPxForScale(float scale)
        {
            return Math.Max(1f, 11f * scale);
        }

        private void FireBounds()
        {
            EventHandler h = BoundsOrVisibilityChanged;
            if (h != null) h(this, EventArgs.Empty);
        }
        private void FireRepaint()
        {
            EventHandler h = RepaintRequested;
            if (h != null) h(this, EventArgs.Empty);
        }
        private void FireAnimationStateChanged()
        {
            EventHandler h = AnimationStateChanged;
            if (h != null) h(this, EventArgs.Empty);
        }

        public void Dispose()
        {
            if (_nameFont != null) { _nameFont.Dispose(); _nameFont = null; }
            _icons.Dispose();
        }
    }
}
