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
    /// 左下血条上方的原生物品获得/击杀播报。
    ///
    /// 渲染遵循“静态提高可读性、动态保持克制”的原则：五个共享槽位、内容驱动的微量化宽度、
    /// 按位数稳定的计数列；只在短入场、数字区合并反馈、退场及图标首轮动画内重绘。
    /// </summary>
    public sealed class LootFeedWidget : INativeHudWidget, IDisposable
    {
        private const float FlashX = 5f;
        private const float FlashBottomY = 460f;
        private const float MinCardW = 96f;
        private const float MaxCardW = 220f;
        private const float CardWidthQuantum = 8f;
        private const float CardH = 26f;
        private const float CardGap = 3f;
        private const float PendingRowH = 15f;
        private const int FadeInMs = 180;
        private const float EntryTravel = 4f;
        private const int CountTransitionMs = 180;
        private const int IconAnimationMs = 450;
        private const int BossEmphasisMs = 360;
        private const int VisualSampleMs = 32; // 与 NativeHud 33 ms 合成上限对齐，实际不超过约 30 fps

        private static readonly string[] CountColumnSamples =
        {
            string.Empty,
            "×9",
            "×99",
            "×999",
            "×9999",
            "×99999",
            "×999999",
            "×9999999",
            "×99999999",
            "×999999999",
            "×9999999999",
            "×99999999999",
            "×999999999999",
            "×9999999999999",
            "×99999999999999",
            "×999999999999999",
            "×9999999999999999",
            "×99999999999999999",
            "×999999999999999999",
            "×9999999999999999999"
        };

        private sealed class IngressEvent
        {
            internal string Kind;
            internal string Name;
            internal long Count;
            internal string Source;
            internal string Icon;
            internal int EliteLevel;
        }

        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly LootFeedModel _model;
        private readonly LootIconCatalog _icons;
        private readonly SingleFlightBatchQueue<IngressEvent> _ingressQueue =
            new SingleFlightBatchQueue<IngressEvent>();
        private bool _disposed;

        private Font _nameFont;
        private Font _metaFont;
        private float _lastFontScale = -1f;
        private readonly Dictionary<string, int> _textWidthCache =
            new Dictionary<string, int>(StringComparer.Ordinal);
        private readonly StringFormat _nameFormat;
        private readonly StringFormat _countFormat;
        private readonly StringFormat _centerFormat;
        private int _lastVisualSignature;
        private int _lastRepaintAtMs = -1000000;
        private Rectangle _lastPublishedBounds = Rectangle.Empty;

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
            _metaFont = NativeHudFonts.CreateUiFont(MetaFontPxForScale(1f), FontStyle.Regular, GraphicsUnit.Pixel);

            _nameFormat = new StringFormat(StringFormat.GenericTypographic)
            {
                Trimming = StringTrimming.EllipsisCharacter,
                LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap
            };
            _countFormat = new StringFormat(StringFormat.GenericTypographic)
            {
                Alignment = StringAlignment.Far,
                LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap
            };
            _centerFormat = new StringFormat(StringFormat.GenericTypographic)
            {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap
            };

            _anchor.Resize += OnAnchorResize;
        }

        #region INativeHudWidget

        public Rectangle ScreenBounds
        {
            get
            {
                if (!Visible || _anchor == null || !_anchor.IsHandleCreated)
                    return Rectangle.Empty;

                EnsureFont();
                float rowsH = _model.ActiveCount * (CardH + CardGap);
                if (_model.DisplayPendingCount > 0)
                    rowsH += PendingRowH;

                int screenX, screenBottom;
                _mapper.FlashToScreen(FlashX, FlashBottomY, out screenX, out screenBottom);
                int width = MeasureWidestCardPx();
                int rowsHeight = Math.Max(4, _mapper.ScaleH(rowsH));
                int entryTravel = Math.Max(1, _mapper.ScaleH(EntryTravel));
                // 入场从最终位置下方 settle；把最大位移静态纳入 composite bounds，
                // 避免高 viewport scale 下越过 NativeHud 的 union 矩形而被裁切。
                return new Rectangle(
                    screenX, screenBottom - rowsHeight, width, rowsHeight + entryTravel);
            }
        }

        public bool Visible { get { return _model.ActiveCount > 0; } }

        public bool WantsAnimationTick { get { return _model.WantsTick; } }

        public void Tick(int deltaMs)
        {
            bool wasTicking = WantsAnimationTick;
            LootFeedModel.Change change = _model.Tick(deltaMs);

            if ((change & LootFeedModel.Change.Geometry) != 0)
                PublishBoundsIfChanged();

            if (wasTicking != WantsAnimationTick)
                FireAnimationStateChanged();

            if (!Visible)
            {
                _lastVisualSignature = 0;
                return;
            }

            // 生命周期仍按 NativeHud 的 16 ms tick 推进；32 ms 采样与 overlay 的 33 ms
            // 合成上限共同把动态阶段限制在约 30 fps，静态持有阶段签名不变、零重绘。
            int signature = ComputeVisualSignature();
            if (signature != _lastVisualSignature
                && _model.NowMs - _lastRepaintAtMs >= VisualSampleMs)
            {
                _lastVisualSignature = signature;
                _lastRepaintAtMs = _model.NowMs;
                FireRepaint();
            }
        }

        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            if (!Visible) return;

            EnsureFont();
            float scale = GetViewportScale();
            int cardH = Math.Max(4, _mapper.ScaleH(CardH));
            int gap = Math.Max(1, _mapper.ScaleH(CardGap));
            int iconSize = Math.Max(4, cardH - Px(3, scale) * 2);
            int padX = Px(5, scale);
            int railWidth = Math.Max(1, Px(2, scale));

            int screenX, screenBottom;
            _mapper.FlashToScreen(FlashX, FlashBottomY, out screenX, out screenBottom);
            int localX = screenX - hudOrigin.X;
            int y = screenBottom - hudOrigin.Y;

            TextRenderingHint oldHint = g.TextRenderingHint;
            InterpolationMode oldInterpolation = g.InterpolationMode;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.InterpolationMode = InterpolationMode.HighQualityBilinear;
            try
            {
                IReadOnlyList<LootFeedModel.LootCard> cards = _model.Cards;
                for (int i = cards.Count - 1; i >= 0; i--)
                {
                    LootFeedModel.LootCard card = cards[i];
                    y -= cardH;
                    float alpha = LootFeedModel.AlphaFor(card, FadeInMs);
                    if (alpha > 0.01f)
                    {
                        float entry = LootFeedModel.SmoothStep(
                            Math.Min(1f, (float)card.VisibleAgeMs / FadeInMs));
                        int settleY = (int)Math.Round(Pxf(EntryTravel, scale) * (1f - entry));
                        int width = MeasureCardWidthPx(card);
                        Rectangle rect = new Rectangle(localX, y + settleY, width, cardH);
                        DrawCard(g, card, rect, iconSize, padX, railWidth, scale, alpha);
                    }
                    y -= gap;
                }

                int pending = _model.DisplayPendingCount;
                if (pending > 0)
                {
                    int rowH = Math.Max(4, _mapper.ScaleH(PendingRowH));
                    y -= rowH;
                    using (SolidBrush backing = new SolidBrush(Color.FromArgb(76, 0, 0, 0)))
                    using (SolidBrush textBrush = new SolidBrush(Color.FromArgb(220, 0xD8, 0xDB, 0xE2)))
                    {
                        int width = MeasureWidestCardPx();
                        g.FillRectangle(backing, localX, y, width, rowH);
                        g.DrawString("待显示 " + pending + " 项", _metaFont, textBrush,
                            new RectangleF(localX + padX, y, width - padX * 2, rowH), _nameFormat);
                    }
                }
            }
            finally
            {
                g.TextRenderingHint = oldHint;
                g.InterpolationMode = oldInterpolation;
            }
        }

        public bool TryHitTest(Point screenPt) { return false; }
        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }

        #endregion

        #region 公共 API（socket 线程入口）

        /// <summary>
        /// 烘焙完成通知：失效纸娃娃负缓存，并只在仍有对应可见卡片时申请重绘。
        /// </summary>
        public void NotifyIconReady(string iconRef)
        {
            if (string.IsNullOrEmpty(iconRef) || !CanPostToUi()) return;
            try
            {
                _anchor.BeginInvoke((Action)(delegate
                {
                    if (_disposed) return;
                    _icons.InvalidateDoll(iconRef);
                    IReadOnlyList<LootFeedModel.LootCard> cards = _model.Cards;
                    for (int i = 0; i < cards.Count; i++)
                    {
                        if (cards[i].Icon == iconRef)
                        {
                            _lastVisualSignature = ComputeVisualSignature();
                            _lastRepaintAtMs = _model.NowMs;
                            FireRepaint();
                            break;
                        }
                    }
                }));
            }
            catch (InvalidOperationException) { }
        }

        /// <summary>
        /// LootFeedTask 的 socket 线程入口。任意时刻最多只有一个 UI drain 在途；
        /// 同一批事件只做一次 bounds/重绘判定，避免 BeginInvoke 与 UpdateLayeredWindow 随击杀频率线性增长。
        /// </summary>
        public void AddEvent(
            string kind, string name, long count, string source, string icon, int eliteLevel = 0)
        {
            if (!CanPostToUi()) return;

            bool shouldPost = _ingressQueue.Enqueue(new IngressEvent
            {
                Kind = kind,
                Name = name,
                Count = count,
                Source = source,
                Icon = icon,
                EliteLevel = eliteLevel
            });

            if (shouldPost)
                PostDrain();
        }

        #endregion

        private void PostDrain()
        {
            try
            {
                _anchor.BeginInvoke((Action)DrainIngress);
            }
            catch (InvalidOperationException)
            {
                _ingressQueue.Abort();
            }
        }

        private void DrainIngress()
        {
            if (_disposed)
            {
                _ingressQueue.Abort();
                return;
            }

            List<IngressEvent> batch = _ingressQueue.BeginDrain();
            try
            {
                bool wasTicking = WantsAnimationTick;
                bool wasVisible = Visible;
                LootFeedModel.Change aggregate = LootFeedModel.Change.None;
                for (int i = 0; i < batch.Count; i++)
                {
                    IngressEvent item = batch[i];
                    aggregate |= _model.Add(
                        item.Kind, item.Name, item.Icon, item.Count, item.Source, item.EliteLevel);
                }

                if ((aggregate & LootFeedModel.Change.Geometry) != 0 || wasVisible != Visible)
                    PublishBoundsIfChanged();
                if (wasTicking != WantsAnimationTick)
                    FireAnimationStateChanged();

                // 首张卡必须立即可见；已在播放中的 feed 则交给下一次签名 tick 合并重绘。
                if (!wasVisible && Visible)
                {
                    _lastVisualSignature = ComputeVisualSignature();
                    _lastRepaintAtMs = _model.NowMs;
                    FireRepaint();
                }
            }
            catch (Exception ex)
            {
                // 事件订阅方异常也不能把 single-flight 永久卡在 scheduled 状态。
                LogManager.Log("[LootFeed] UI drain error: " + ex.Message);
            }
            finally
            {
                if (_ingressQueue.CompleteDrain())
                    PostDrain();
            }
        }

        private int ComputeVisualSignature()
        {
            unchecked
            {
                int signature = _model.ActiveCount * 31 + _model.DisplayPendingCount * 7;
                IReadOnlyList<LootFeedModel.LootCard> cards = _model.Cards;
                for (int i = 0; i < cards.Count; i++)
                {
                    LootFeedModel.LootCard card = cards[i];
                    signature = signature * 31 + (int)card.Sequence;
                    signature = signature * 31 + card.DisplayCount.GetHashCode();

                    if (card.VisibleAgeMs < FadeInMs)
                        signature = signature * 31 + 1000 + card.VisibleAgeMs / VisualSampleMs;
                    if (card.FadeElapsedMs > 0)
                        signature = signature * 31 + 2000 + card.FadeElapsedMs / VisualSampleMs;

                    int countAge = _model.NowMs - card.CountTransitionStartedMs;
                    if (card.PreviousDisplayCount != card.DisplayCount
                        && countAge >= 0 && countAge < CountTransitionMs)
                        signature = signature * 31 + 3000 + countAge / VisualSampleMs;

                    if (card.EliteLevel >= 2 && card.VisibleAgeMs < BossEmphasisMs)
                        signature = signature * 31 + 4000 + card.VisibleAgeMs / VisualSampleMs;

                    if (card.VisibleAgeMs <= IconAnimationMs && !string.IsNullOrEmpty(card.Icon))
                    {
                        LootIconCatalog.LootIconFrames frames;
                        if (_icons.TryGet(card.Icon, out frames) && frames.Animated)
                        {
                            int sampleMs = QuantizedIconTime(card.VisibleAgeMs);
                            signature = signature * 31 + 5000 + SelectFrameIndex(frames, sampleMs);
                        }
                    }
                }
                return signature;
            }
        }

        private void DrawCard(
            Graphics g, LootFeedModel.LootCard card, Rectangle rect,
            int iconSize, int padX, int railWidth, float scale, float alpha)
        {
            Color accent = AccentColor(card);
            byte fullAlpha = ToAlpha(255f * alpha);

            // 直角低透明底 + 文本区局部加深。静态对比度由底色承担，不依赖脉冲。
            using (SolidBrush baseBrush = new SolidBrush(Color.FromArgb(ToAlpha(108f * alpha), 8, 10, 14)))
                g.FillRectangle(baseBrush, rect);
            using (Pen hairline = new Pen(Color.FromArgb(
                ToAlpha(70f * alpha), 0xB8, 0xBE, 0xC8), 1f))
                g.DrawRectangle(hairline, rect.X, rect.Y, rect.Width - 1, rect.Height - 1);

            int iconX = rect.X + railWidth + padX;
            int iconY = rect.Y + (rect.Height - iconSize) / 2;
            int textX = iconX + iconSize + padX;
            using (SolidBrush contentBrush = new SolidBrush(Color.FromArgb(ToAlpha(58f * alpha), 0, 0, 0)))
                g.FillRectangle(contentBrush, textX - Px(2, scale), rect.Y + 1,
                    Math.Max(1, rect.Right - textX + Px(2, scale) - 1), rect.Height - 2);

            DrawRankRail(g, card, rect, railWidth, accent, alpha, scale);

            Bitmap icon = ResolveIcon(card);
            if (icon != null)
            {
                DrawBitmapAlpha(g, icon, new Rectangle(iconX, iconY, iconSize, iconSize), alpha);
            }
            else
            {
                using (SolidBrush placeholder = new SolidBrush(
                    Color.FromArgb(ToAlpha(92f * alpha), accent.R, accent.G, accent.B)))
                    g.FillRectangle(placeholder, iconX, iconY, iconSize, iconSize);
                string glyph = string.IsNullOrEmpty(card.Name) ? "?" : card.Name.Substring(0, 1);
                using (SolidBrush glyphBrush = new SolidBrush(Color.FromArgb(fullAlpha, 0xFA, 0xFB, 0xFC)))
                    g.DrawString(glyph, _nameFont, glyphBrush,
                        new RectangleF(iconX, iconY, iconSize, iconSize), _centerFormat);
            }

            DrawRankIconBorder(g, card, new Rectangle(iconX, iconY, iconSize, iconSize), accent, alpha);

            string countSample = CountColumnSample(card.DisplayCount);
            int countColumnWidth = countSample.Length > 0 ? MeasureTextCached(countSample) : 0;
            int rightPad = padX;
            int countGap = countColumnWidth > 0 ? Px(4, scale) : 0;
            RectangleF countRect = new RectangleF(
                rect.Right - rightPad - countColumnWidth,
                rect.Y,
                countColumnWidth,
                rect.Height);
            RectangleF nameRect = new RectangleF(
                textX,
                rect.Y,
                Math.Max(8, countRect.X - countGap - textX),
                rect.Height);

            using (SolidBrush nameBrush = new SolidBrush(Color.FromArgb(fullAlpha, 0xF4, 0xF6, 0xF8)))
                g.DrawString(card.Name ?? string.Empty, _nameFont, nameBrush, nameRect, _nameFormat);

            DrawCount(g, card, countRect, accent, alpha);
        }

        private void DrawRankRail(
            Graphics g, LootFeedModel.LootCard card, Rectangle rect,
            int railWidth, Color accent, float alpha, float scale)
        {
            byte railAlpha = ToAlpha(235f * alpha);
            using (SolidBrush rail = new SolidBrush(Color.FromArgb(railAlpha, accent.R, accent.G, accent.B)))
            {
                if (card.EliteLevel == 1)
                {
                    int segmentH = Math.Max(2, (rect.Height - Px(6, scale)) / 3);
                    int gap = Math.Max(1, Px(2, scale));
                    int y = rect.Y + Px(2, scale);
                    for (int i = 0; i < 3; i++)
                    {
                        g.FillRectangle(rail, rect.X, y, railWidth, segmentH);
                        y += segmentH + gap;
                    }
                }
                else if (card.EliteLevel >= 2)
                {
                    g.FillRectangle(rail, rect.X, rect.Y, railWidth, rect.Height);
                    g.FillRectangle(rail, rect.X + railWidth + 1, rect.Y + 2, 1, rect.Height - 4);
                    g.FillRectangle(rail, rect.X, rect.Y, rect.Width, 1);
                    g.FillRectangle(rail, rect.X, rect.Bottom - 1, rect.Width, 1);
                }
                else
                {
                    g.FillRectangle(rail, rect.X, rect.Y + 2, railWidth, rect.Height - 4);
                }
            }
        }

        private void DrawRankIconBorder(
            Graphics g, LootFeedModel.LootCard card, Rectangle iconRect,
            Color accent, float alpha)
        {
            if (card.EliteLevel <= 0) return;

            float emphasis = 0f;
            if (card.EliteLevel >= 2 && card.VisibleAgeMs < BossEmphasisMs)
                emphasis = 1f - LootFeedModel.SmoothStep(
                    (float)card.VisibleAgeMs / BossEmphasisMs);
            byte borderAlpha = ToAlpha((175f + 80f * emphasis) * alpha);
            using (Pen border = new Pen(Color.FromArgb(borderAlpha, accent.R, accent.G, accent.B), 1f))
                g.DrawRectangle(border, iconRect.X, iconRect.Y, iconRect.Width - 1, iconRect.Height - 1);
        }

        private void DrawCount(
            Graphics g, LootFeedModel.LootCard card, RectangleF rect,
            Color accent, float alpha)
        {
            string current = CountText(card.DisplayCount);
            int transitionAge = _model.NowMs - card.CountTransitionStartedMs;
            bool transitioning = card.PreviousDisplayCount != card.DisplayCount
                && transitionAge >= 0 && transitionAge < CountTransitionMs;

            if (!transitioning)
            {
                if (current.Length == 0) return;
                using (SolidBrush brush = new SolidBrush(
                    Color.FromArgb(ToAlpha(255f * alpha), accent.R, accent.G, accent.B)))
                    g.DrawString(current, _nameFont, brush, rect, _countFormat);
                return;
            }

            float t = LootFeedModel.SmoothStep((float)transitionAge / CountTransitionMs);
            float impulse = 1f - t;
            int impactLevel = CountImpactLevel(card.DisplayCount - card.PreviousDisplayCount);
            float impactStrength = card.Kind == "kill"
                ? 0.72f + impactLevel * 0.09f
                : 0.52f + impactLevel * 0.07f;
            impactStrength = Math.Min(1f, impactStrength);

            // 反馈只落在数字列：一层很短的色洗 + 1px 底沿，不放大整卡、不制造粒子。
            if (current.Length > 0 && rect.Width > 0f)
            {
                int washAlpha = ToAlpha(44f * alpha * impactStrength * impulse);
                int streakAlpha = ToAlpha(128f * alpha * impactStrength * impulse);
                using (SolidBrush wash = new SolidBrush(
                    Color.FromArgb(washAlpha, accent.R, accent.G, accent.B)))
                    g.FillRectangle(wash, rect);
                using (SolidBrush streak = new SolidBrush(
                    Color.FromArgb(streakAlpha, accent.R, accent.G, accent.B)))
                    g.FillRectangle(streak, rect.X, rect.Bottom - 1f,
                        Math.Max(1f, rect.Width * (0.55f + impactLevel * 0.1f)), 1f);
            }

            string previous = CountText(card.PreviousDisplayCount);
            if (previous.Length > 0)
            {
                using (SolidBrush oldBrush = new SolidBrush(
                    Color.FromArgb(ToAlpha(178f * alpha * (1f - t)), accent.R, accent.G, accent.B)))
                {
                    RectangleF oldRect = rect;
                    oldRect.Y -= 2f * t;
                    g.DrawString(previous, _nameFont, oldBrush, oldRect, _countFormat);
                }
            }
            if (current.Length > 0)
            {
                Color currentColor = BlendColor(accent, Color.White, 0.34f * impulse * impactStrength);
                using (SolidBrush newBrush = new SolidBrush(
                    Color.FromArgb(ToAlpha(255f * alpha * (0.68f + 0.32f * t)),
                        currentColor.R, currentColor.G, currentColor.B)))
                {
                    RectangleF newRect = rect;
                    newRect.Y += 2f * (1f - t);
                    g.DrawString(current, _nameFont, newBrush, newRect, _countFormat);
                }
            }
        }

        private Bitmap ResolveIcon(LootFeedModel.LootCard card)
        {
            if (string.IsNullOrEmpty(card.Icon)) return null;
            LootIconCatalog.LootIconFrames frames;
            if (!_icons.TryGet(card.Icon, out frames) || frames.First == null)
                return null;
            if (!frames.Animated)
                return frames.First;

            int sampleMs = QuantizedIconTime(card.VisibleAgeMs);
            return frames.Frames[SelectFrameIndex(frames, sampleMs)];
        }

        private static int QuantizedIconTime(int visibleAgeMs)
        {
            int bounded = Math.Max(0, Math.Min(IconAnimationMs, visibleAgeMs));
            return bounded / VisualSampleMs * VisualSampleMs;
        }

        /// <summary>
        /// 动画选帧：逐帧时长优先，否则走均匀 fps。调用方负责把时间限制在首轮动效窗口内。
        /// </summary>
        internal static int SelectFrameIndex(LootIconCatalog.LootIconFrames frames, long animMs)
        {
            if (frames == null || frames.Frames == null || frames.Frames.Length < 2 || animMs < 0)
                return 0;

            int[] durations = frames.DurationMs;
            if (durations != null && durations.Length == frames.Frames.Length)
            {
                long total = 0;
                for (int i = 0; i < durations.Length; i++)
                    total += Math.Max(0, durations[i]);
                if (total > 0)
                {
                    long time = animMs % total;
                    long accumulated = 0;
                    for (int i = 0; i < durations.Length; i++)
                    {
                        accumulated += Math.Max(0, durations[i]);
                        if (time < accumulated) return i;
                    }
                    return frames.Frames.Length - 1;
                }
            }
            return (int)((animMs * (long)frames.Fps) / 1000L % frames.Frames.Length);
        }

        private int MeasureCardWidthPx(LootFeedModel.LootCard card)
        {
            float scale = GetViewportScale();
            int cardH = Math.Max(4, _mapper.ScaleH(CardH));
            int iconSize = Math.Max(4, cardH - Px(3, scale) * 2);
            int padX = Px(5, scale);
            int railWidth = Math.Max(1, Px(2, scale));
            string countSample = CountColumnSample(card.DisplayCount);
            int countReserve = countSample.Length > 0 ? MeasureTextCached(countSample) : 0;
            int countGap = countReserve > 0 ? Px(4, scale) : 0;
            int required = railWidth + padX + iconSize + padX
                + MeasureTextCached(card.Name ?? string.Empty)
                + countGap + countReserve + padX;

            int minimum = _mapper.ScaleW(MinCardW);
            int maximum = _mapper.ScaleW(MaxCardW);
            int quantum = Math.Max(1, _mapper.ScaleW(CardWidthQuantum));
            return QuantizeWidthPx(required, minimum, maximum, quantum);
        }

        private int MeasureWidestCardPx()
        {
            int widest = _mapper.ScaleW(MinCardW);
            IReadOnlyList<LootFeedModel.LootCard> cards = _model.Cards;
            for (int i = 0; i < cards.Count; i++)
                widest = Math.Max(widest, MeasureCardWidthPx(cards[i]));
            return widest;
        }

        private int MeasureTextCached(string text)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int width;
            if (_textWidthCache.TryGetValue(text, out width)) return width;
            width = TextRenderer.MeasureText(text, _nameFont,
                new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding).Width;
            _textWidthCache[text] = width;
            return width;
        }

        private static string CountText(long count)
        {
            return count > 1 ? "×" + count : string.Empty;
        }

        internal static string CountColumnSample(long count)
        {
            int bucket = LootFeedModel.CountLayoutBucket(count);
            return CountColumnSamples[Math.Max(0, Math.Min(CountColumnSamples.Length - 1, bucket))];
        }

        internal static int QuantizeWidthPx(int required, int minimum, int maximum, int quantum)
        {
            minimum = Math.Max(1, minimum);
            maximum = Math.Max(minimum, maximum);
            quantum = Math.Max(1, quantum);
            if (required <= minimum) return minimum;
            if (required >= maximum) return maximum;
            int steps = (required - minimum + quantum - 1) / quantum;
            return Math.Min(maximum, minimum + steps * quantum);
        }

        internal static int CountImpactLevel(long delta)
        {
            if (delta >= 8) return 3;
            if (delta >= 4) return 2;
            if (delta >= 2) return 1;
            return 0;
        }

        private static Color AccentColor(LootFeedModel.LootCard card)
        {
            if (card.EliteLevel >= 2) return Color.FromArgb(0xFF, 0xD1, 0x66);
            if (card.EliteLevel == 1) return Color.FromArgb(0xFF, 0xB5, 0x47);
            switch (card.Kind)
            {
                case "money": return Color.FromArgb(0xFF, 0xD3, 0x4D);
                case "kpoint": return Color.FromArgb(0x62, 0xD6, 0xFF);
                case "intel": return Color.FromArgb(0xD5, 0xA6, 0xFF);
                case "kill": return Color.FromArgb(0xFF, 0x5C, 0x63);
                default: return Color.FromArgb(0xF2, 0xF4, 0xF7);
            }
        }

        private static void DrawBitmapAlpha(Graphics g, Bitmap bitmap, Rectangle destination, float alpha)
        {
            if (alpha >= 0.999f)
            {
                g.DrawImage(bitmap, destination, 0, 0, bitmap.Width, bitmap.Height, GraphicsUnit.Pixel);
                return;
            }

            using (System.Drawing.Imaging.ImageAttributes attributes =
                new System.Drawing.Imaging.ImageAttributes())
            {
                System.Drawing.Imaging.ColorMatrix matrix = new System.Drawing.Imaging.ColorMatrix();
                matrix.Matrix33 = Math.Max(0f, Math.Min(1f, alpha));
                attributes.SetColorMatrix(matrix);
                g.DrawImage(bitmap, destination, 0, 0, bitmap.Width, bitmap.Height,
                    GraphicsUnit.Pixel, attributes);
            }
        }

        private void EnsureFont()
        {
            float scale = GetViewportScale();
            if (Math.Abs(scale - _lastFontScale) < 0.01f && _nameFont != null && _metaFont != null)
                return;

            _lastFontScale = scale;
            if (_nameFont != null) _nameFont.Dispose();
            if (_metaFont != null) _metaFont.Dispose();
            _nameFont = NativeHudFonts.CreateUiFont(NameFontPxForScale(scale), FontStyle.Regular, GraphicsUnit.Pixel);
            _metaFont = NativeHudFonts.CreateUiFont(MetaFontPxForScale(scale), FontStyle.Regular, GraphicsUnit.Pixel);
            _textWidthCache.Clear();
        }

        private float GetViewportScale()
        {
            float viewportX, viewportY, viewportW, viewportH;
            _mapper.CalcViewport(out viewportX, out viewportY, out viewportW, out viewportH);
            if (viewportH <= 0) return 1f;
            return Math.Max(0.5f, viewportH / _mapper.StageHeight);
        }

        private void OnAnchorResize(object sender, EventArgs e)
        {
            _lastFontScale = -1f;
            PublishBoundsIfChanged();
            if (Visible)
            {
                _lastVisualSignature = ComputeVisualSignature();
                _lastRepaintAtMs = _model.NowMs;
                FireRepaint();
            }
        }

        private bool CanPostToUi()
        {
            return !_disposed && _anchor != null && !_anchor.IsDisposed && _anchor.IsHandleCreated;
        }

        private void PublishBoundsIfChanged()
        {
            Rectangle current = ScreenBounds;
            if (current == _lastPublishedBounds) return;
            _lastPublishedBounds = current;
            FireBounds();
        }

        private static Color BlendColor(Color from, Color to, float amount)
        {
            amount = Math.Max(0f, Math.Min(1f, amount));
            return Color.FromArgb(
                (int)Math.Round(from.R + (to.R - from.R) * amount),
                (int)Math.Round(from.G + (to.G - from.G) * amount),
                (int)Math.Round(from.B + (to.B - from.B) * amount));
        }

        private static byte ToAlpha(float value)
        {
            return (byte)Math.Max(0, Math.Min(255, (int)Math.Round(value)));
        }

        private static int Px(int basePixels, float scale)
        {
            return Math.Max(1, (int)Math.Round(basePixels * scale));
        }

        private static float Pxf(float basePixels, float scale)
        {
            return Math.Max(1f, basePixels * scale);
        }

        internal static float NameFontPxForScale(float scale)
        {
            return Math.Max(1f, 12f * scale);
        }

        private static float MetaFontPxForScale(float scale)
        {
            return Math.Max(1f, 10f * scale);
        }

        private void FireBounds()
        {
            EventHandler handler = BoundsOrVisibilityChanged;
            if (handler != null) handler(this, EventArgs.Empty);
        }

        private void FireRepaint()
        {
            EventHandler handler = RepaintRequested;
            if (handler != null) handler(this, EventArgs.Empty);
        }

        private void FireAnimationStateChanged()
        {
            EventHandler handler = AnimationStateChanged;
            if (handler != null) handler(this, EventArgs.Empty);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _anchor.Resize -= OnAnchorResize;
            _ingressQueue.Abort();
            if (_nameFont != null) { _nameFont.Dispose(); _nameFont = null; }
            if (_metaFont != null) { _metaFont.Dispose(); _metaFont = null; }
            _nameFormat.Dispose();
            _countFormat.Dispose();
            _centerFormat.Dispose();
            _icons.Dispose();
        }
    }
}
