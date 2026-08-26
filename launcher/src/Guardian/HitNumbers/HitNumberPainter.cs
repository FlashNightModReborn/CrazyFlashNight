using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Globalization;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Guardian.HitNumbers
{
    internal enum HitNumberVisualRole
    {
        Detail,
        Summary
    }

    /// <summary>
    /// C# 伤害数字的结构化绘制快照。运行时布局和视觉样本工具共用该模型，
    /// 避免验收图另写一套看似相同、实际不等价的 Painter。
    /// </summary>
    internal sealed class HitNumberPaintItem
    {
        internal float StageX;
        internal float StageY;
        internal float CombinedScale = 1f;
        internal float Alpha = 1f;
        internal float CombinedBlur = 3f;
        internal int Damage;
        internal int Packed;
        internal string EffectText = string.Empty;
        internal string EffectEmoji = string.Empty;
        internal string CrushText = string.Empty;
        internal string CrushEmoji = string.Empty;
        internal float LifeSteal;
        internal float ShieldAbsorb;
        internal int HitCount = 1;
        internal string FlagScales = "999999999";
        // 与 FlagScales 的“贡献可见度”正交：各显示模式可在不伪造贡献档位的
        // 前提下压缩属性标签，逐发矩阵因此能保持密度且沿用同一语义算法。
        internal float SemanticDensityScale = 1f;
        internal Color? MainColorOverride;
        internal Color? EffectTextColorOverride;
        internal int SourceSequence;
        internal string SourceBurstId = string.Empty;
        internal string SourceTargetId = string.Empty;
        internal float SourceTargetX;
        internal float SourceTargetY;
        internal HitNumberVisualRole VisualRole = HitNumberVisualRole.Detail;
    }

    internal readonly struct HitNumberPaintContext
    {
        internal HitNumberPaintContext(RectangleF viewport)
        {
            Viewport = viewport;
        }

        internal RectangleF Viewport { get; }
        internal float PixelsPerFlash => Viewport.Width / 1024f;
    }

    internal readonly struct HitNumberPaintStats
    {
        internal HitNumberPaintStats(int itemCount, int runCount)
        {
            ItemCount = itemCount;
            RunCount = runCount;
        }

        internal int ItemCount { get; }
        internal int RunCount { get; }
    }

    /// <summary>
    /// 伤害数字生产 Painter。它只负责协议解析后的文字表达，不决定聚合、容量或布局。
    /// 实例持有字体和可复用工作列表，需与所属 UI/渲染线程同寿命使用。
    /// </summary>
    internal sealed class HitNumberPainter : IDisposable
    {
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

        private const int FontIndexNumber = 0;
        private const int FontIndexLabel = 1;
        private const int FontIndexEmoji = 2;
        private const string RoleNumber = "native.combat.number";
        private const string RoleLabel = "native.combat.label";
        private const string RoleEmoji = "native.hud.symbol";
        private const FontStyle LabelStyle = FontStyle.Bold;
        private const int GlyphCacheCapacity = 768;

        private readonly Dictionary<int, Font> _fontCache = new Dictionary<int, Font>();
        private readonly Dictionary<GlyphPathKey, LinkedListNode<GlyphPathEntry>> _glyphCache =
            new Dictionary<GlyphPathKey, LinkedListNode<GlyphPathEntry>>();
        private readonly LinkedList<GlyphPathEntry> _glyphLru =
            new LinkedList<GlyphPathEntry>();
        private readonly List<TextSegment> _segments = new List<TextSegment>(10);
        private readonly List<RenderRun> _runs = new List<RenderRun>(12);
        private readonly Pen _outlinePen = new Pen(Color.Black, 1f)
        {
            LineJoin = LineJoin.Round
        };
        private readonly SolidBrush _glyphBrush = new SolidBrush(Color.White);
        private readonly StringFormat _typographic;
        private bool _disposed;

        internal HitNumberPainter()
        {
            _typographic = new StringFormat(StringFormat.GenericTypographic);
            _typographic.FormatFlags |= StringFormatFlags.NoWrap;
        }

        internal HitNumberPaintStats Paint(
            Graphics graphics,
            IReadOnlyList<HitNumberPaintItem> items,
            HitNumberPaintContext context)
        {
            if (graphics == null) throw new ArgumentNullException(nameof(graphics));
            if (items == null) throw new ArgumentNullException(nameof(items));
            ThrowIfDisposed();

            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;

            int runCount = 0;
            for (int i = 0; i < items.Count; i++)
                runCount += PaintItem(graphics, items[i], context);
            return new HitNumberPaintStats(items.Count, runCount);
        }

        private int PaintItem(
            Graphics graphics,
            HitNumberPaintItem item,
            HitNumberPaintContext context)
        {
            float pixPerFlash = context.PixelsPerFlash;
            float bmpX = context.Viewport.Left + (item.StageX / 1024f) * context.Viewport.Width;
            float bmpY = context.Viewport.Top + (item.StageY / 576f) * context.Viewport.Height;

            bool isMiss = ((item.Packed >> 9) & 1) != 0;
            int fontSize = (item.Packed >> 10) & 255;
            int flags = item.Packed & 511;
            if (fontSize == 0) fontSize = 28;

            Color mainColor = item.MainColorOverride ?? ResolveMainColor(item.Packed);
            Color labelColor = item.EffectTextColorOverride ?? mainColor;
            byte alpha = (byte)(255 * Math.Max(0f, Math.Min(1f, item.Alpha)));

            _segments.Clear();
            _runs.Clear();

            string mainText = isMiss ? "MISS" : item.Damage.ToString(CultureInfo.InvariantCulture);
            float mainPt = Clamp(fontSize * item.CombinedScale * pixPerFlash, 6f, 72f);
            _segments.Add(new TextSegment(mainText, mainColor, mainPt, false));

            float labelPtBase = 20f * item.CombinedScale * pixPerFlash;
            if ((flags & 8) != 0 && !string.IsNullOrEmpty(item.EffectText) && VisualFlagScale(item, 3) > 0f)
            {
                float pt = Clamp(labelPtBase * VisualFlagScale(item, 3), 4f, 40f);
                _segments.Add(new TextSegment(" " + item.EffectText, labelColor, pt, true));
            }
            string crushText = string.IsNullOrEmpty(item.CrushText)
                ? item.EffectText
                : item.CrushText;
            string crushEmoji = string.IsNullOrEmpty(item.CrushEmoji)
                ? item.EffectEmoji
                : item.CrushEmoji;
            if ((flags & 16) != 0 && !string.IsNullOrEmpty(crushText) && VisualFlagScale(item, 4) > 0f)
            {
                float pt = Clamp(labelPtBase * VisualFlagScale(item, 4), 4f, 40f);
                string text = " " + (string.IsNullOrEmpty(crushEmoji) ? "" : crushEmoji) + crushText;
                _segments.Add(new TextSegment(text, Color.FromArgb(0x66, 0xBC, 0xF5), pt, true));
            }
            if ((flags & 2) != 0 && VisualFlagScale(item, 1) > 0f)
            {
                float pt = Clamp(labelPtBase * VisualFlagScale(item, 1), 4f, 40f);
                _segments.Add(new TextSegment(" 毒", Color.FromArgb(0x66, 0xDD, 0x00), pt, true));
            }
            if ((flags & 32) != 0 && item.LifeSteal > 0 && VisualFlagScale(item, 5) > 0f)
            {
                float pt = Clamp(15f * item.CombinedScale * pixPerFlash * VisualFlagScale(item, 5), 4f, 30f);
                _segments.Add(new TextSegment(
                    " 汲:" + ((int)item.LifeSteal).ToString(CultureInfo.InvariantCulture),
                    Color.FromArgb(0xBB, 0x00, 0xAA), pt, true));
            }
            if ((flags & 1) != 0 && VisualFlagScale(item, 0) > 0f)
            {
                float pt = Clamp(labelPtBase * VisualFlagScale(item, 0), 4f, 40f);
                _segments.Add(new TextSegment(" 溃", Color.FromArgb(0xFF, 0x33, 0x33), pt, true));
            }
            if ((flags & 4) != 0 && VisualFlagScale(item, 2) > 0f)
            {
                float pt = Clamp(labelPtBase * VisualFlagScale(item, 2), 4f, 40f);
                Color color = ((flags & 128) != 0)
                    ? Color.FromArgb(0x66, 0x00, 0x33)
                    : Color.FromArgb(0x4A, 0x00, 0x99);
                _segments.Add(new TextSegment(" 斩", color, pt, true));
            }
            if ((flags & 256) != 0 && item.ShieldAbsorb > 0 && VisualFlagScale(item, 8) > 0f)
            {
                float pt = Clamp(18f * item.CombinedScale * pixPerFlash * VisualFlagScale(item, 8), 4f, 36f);
                _segments.Add(new TextSegment(
                    " 🛡" + ((int)item.ShieldAbsorb).ToString(CultureInfo.InvariantCulture),
                    Color.FromArgb(0x00, 0xCE, 0xD1), pt, true));
            }

            for (int i = 0; i < _segments.Count; i++)
                SegmentToRuns(_segments[i], _runs);

            float totalWidth = 0f;
            for (int i = 0; i < _runs.Count; i++)
            {
                RenderRun run = _runs[i];
                Font font = GetCachedFont(
                    run.FontIndex,
                    run.Style,
                    run.FontPointSize,
                    out int fontKey);
                run.Glyph = GetCachedGlyph(graphics, run.Text, font, fontKey);
                run.MeasuredWidth = run.Glyph.MeasuredWidth;
                _runs[i] = run;
                totalWidth += run.MeasuredWidth;
            }

            float drawX = bmpX - totalWidth / 2f;
            float drawY = bmpY;
            float penWidth = Clamp(item.CombinedBlur * pixPerFlash * 1.2f, 1f, 8f);

            for (int i = 0; i < _runs.Count; i++)
            {
                RenderRun run = _runs[i];
                Color foreground = Color.FromArgb(alpha, run.Color.R, run.Color.G, run.Color.B);
                DrawCachedGlyph(
                    graphics,
                    run.Glyph,
                    drawX,
                    drawY,
                    penWidth,
                    alpha,
                    foreground);
                drawX += run.MeasuredWidth;
            }

            if (item.HitCount > 1)
                PaintHitCount(graphics, item.HitCount, drawX, drawY, mainPt, penWidth, alpha);

            return _runs.Count;
        }

        internal static Color ResolveMainColor(int packed)
        {
            int colorId = (packed >> 18) & 15;
            return ResolveColorId(colorId);
        }

        internal static Color ResolveColorId(int colorId)
        {
            return colorId >= 0 && colorId < ColorTable.Length
                ? ColorTable[colorId]
                : ColorTable[0];
        }

        private void PaintHitCount(
            Graphics graphics,
            int hitCount,
            float drawX,
            float drawY,
            float mainPt,
            float penWidth,
            byte alpha)
        {
            float numberPt = Clamp(mainPt * 0.55f, 6f, 36f);
            float hitPt = Clamp(numberPt * 0.5f, 4f, 18f);
            string numberText = hitCount.ToString(CultureInfo.InvariantCulture);
            const string hitText = "hit";
            float superscriptX = drawX + 2f;
            float superscriptY = drawY - mainPt * 0.35f;

            Font numberFont = GetCachedFont(
                FontIndexNumber,
                FontStyle.Bold | FontStyle.Italic,
                numberPt,
                out int numberFontKey);
            Font hitFont = GetCachedFont(
                FontIndexLabel,
                FontStyle.Bold | FontStyle.Italic,
                hitPt,
                out int hitFontKey);
            Color cyan = Color.FromArgb(alpha, 0x00, 0xFF, 0xE0);

            GlyphPathEntry numberGlyph = GetCachedGlyph(
                graphics,
                numberText,
                numberFont,
                numberFontKey);
            DrawCachedGlyph(
                graphics,
                numberGlyph,
                superscriptX,
                superscriptY,
                penWidth * 0.9f,
                alpha,
                cyan);

            float numberEm = graphics.DpiY * numberFont.SizeInPoints / 72f;
            float hitX = superscriptX + numberGlyph.Bounds.Right + 1f;
            float hitY = superscriptY + numberEm - graphics.DpiY * hitFont.SizeInPoints / 72f;
            GlyphPathEntry hitGlyph = GetCachedGlyph(
                graphics,
                hitText,
                hitFont,
                hitFontKey);
            DrawCachedGlyph(
                graphics,
                hitGlyph,
                hitX,
                hitY,
                penWidth * 0.6f,
                alpha,
                cyan);
        }

        private static float FlagScale(string levels, int bit)
        {
            if (string.IsNullOrEmpty(levels) || levels.Length != 9) return 1f;
            int level = levels[bit] - '0';
            if (level <= 0) return 0f;
            if (level >= 9) return 1f;
            return level / 9f;
        }

        private static float VisualFlagScale(HitNumberPaintItem item, int bit)
        {
            return FlagScale(item.FlagScales, bit) *
                Clamp(item.SemanticDensityScale, 0f, 1f);
        }

        private static float Clamp(float value, float minimum, float maximum)
        {
            return Math.Max(minimum, Math.Min(value, maximum));
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

        private static void SegmentToRuns(TextSegment segment, List<RenderRun> runs)
        {
            string text = segment.Text;
            if (string.IsNullOrEmpty(text)) return;

            if (!ContainsEmoji(text))
            {
                runs.Add(new RenderRun
                {
                    Text = text,
                    Color = segment.Color,
                    FontPointSize = segment.FontPointSize,
                    FontIndex = segment.IsLabel ? FontIndexLabel : FontIndexNumber,
                    Style = segment.IsLabel ? LabelStyle : FontStyle.Regular
                });
                return;
            }

            int start = 0;
            bool currentEmoji = false;
            for (int i = 0; i <= text.Length; i++)
            {
                bool isEmoji = false;
                if (i < text.Length)
                {
                    char c = text[i];
                    if (char.IsLowSurrogate(c)) continue;
                    isEmoji = char.IsHighSurrogate(c) ||
                        (c >= 0x2600 && c <= 0x27BF) ||
                        (c >= 0x2B50 && c <= 0x2B55);
                }
                if (i == 0)
                {
                    currentEmoji = isEmoji;
                    continue;
                }
                if (i != text.Length && isEmoji == currentEmoji) continue;

                string part = text.Substring(start, i - start);
                if (part.Length > 0)
                {
                    runs.Add(new RenderRun
                    {
                        Text = part,
                        Color = segment.Color,
                        FontPointSize = currentEmoji
                            ? segment.FontPointSize * 1.3f
                            : segment.FontPointSize,
                        FontIndex = currentEmoji
                            ? FontIndexEmoji
                            : (segment.IsLabel ? FontIndexLabel : FontIndexNumber),
                        Style = currentEmoji
                            ? FontStyle.Regular
                            : (segment.IsLabel ? LabelStyle : FontStyle.Regular)
                    });
                }
                start = i;
                currentEmoji = isEmoji;
            }
        }

        private Font GetCachedFont(
            int fontIndex,
            FontStyle style,
            float points,
            out int key)
        {
            int bucket = (int)(points * 2 + 0.5f);
            key = (fontIndex << 16) | ((int)style << 8) | bucket;
            if (_fontCache.TryGetValue(key, out Font font)) return font;

            string role = fontIndex switch
            {
                FontIndexEmoji => RoleEmoji,
                FontIndexLabel => RoleLabel,
                _ => RoleNumber
            };
            font = NativeHudFonts.CreateRoleFont(role, points, style, GraphicsUnit.Point);
            _fontCache[key] = font;
            return font;
        }

        private GlyphPathEntry GetCachedGlyph(
            Graphics graphics,
            string text,
            Font font,
            int fontKey)
        {
            int dpiKey = (int)(graphics.DpiY * 100f + 0.5f);
            var key = new GlyphPathKey(text, fontKey, dpiKey);
            if (_glyphCache.TryGetValue(key, out LinkedListNode<GlyphPathEntry> node))
            {
                if (!ReferenceEquals(_glyphLru.First, node))
                {
                    _glyphLru.Remove(node);
                    _glyphLru.AddFirst(node);
                }
                return node.Value;
            }

            var path = new GraphicsPath();
            path.AddString(
                text,
                font.FontFamily,
                (int)font.Style,
                graphics.DpiY * font.SizeInPoints / 72f,
                PointF.Empty,
                _typographic);
            var entry = new GlyphPathEntry(
                key,
                path,
                graphics.MeasureString(text, font, 9999, _typographic).Width,
                path.GetBounds());
            node = _glyphLru.AddFirst(entry);
            _glyphCache.Add(key, node);
            if (_glyphCache.Count > GlyphCacheCapacity)
            {
                LinkedListNode<GlyphPathEntry> last = _glyphLru.Last;
                _glyphLru.RemoveLast();
                _glyphCache.Remove(last.Value.Key);
                last.Value.Path.Dispose();
            }
            return entry;
        }

        private void DrawCachedGlyph(
            Graphics graphics,
            GlyphPathEntry glyph,
            float x,
            float y,
            float outlineWidth,
            byte alpha,
            Color foreground)
        {
            GraphicsState state = graphics.Save();
            try
            {
                graphics.TranslateTransform(x, y);
                _outlinePen.Color = Color.FromArgb(alpha, 0, 0, 0);
                _outlinePen.Width = outlineWidth;
                _glyphBrush.Color = foreground;
                graphics.DrawPath(_outlinePen, glyph.Path);
                graphics.FillPath(_glyphBrush, glyph.Path);
            }
            finally
            {
                graphics.Restore(state);
            }
        }

        private void ThrowIfDisposed()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(HitNumberPainter));
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            foreach (GlyphPathEntry entry in _glyphLru) entry.Path.Dispose();
            _glyphCache.Clear();
            _glyphLru.Clear();
            foreach (Font font in _fontCache.Values) font.Dispose();
            _fontCache.Clear();
            _outlinePen.Dispose();
            _glyphBrush.Dispose();
            _typographic.Dispose();
        }

        private readonly struct TextSegment
        {
            internal TextSegment(string text, Color color, float fontPointSize, bool isLabel)
            {
                Text = text;
                Color = color;
                FontPointSize = fontPointSize;
                IsLabel = isLabel;
            }

            internal string Text { get; }
            internal Color Color { get; }
            internal float FontPointSize { get; }
            internal bool IsLabel { get; }
        }

        private struct RenderRun
        {
            internal string Text;
            internal Color Color;
            internal float FontPointSize;
            internal int FontIndex;
            internal FontStyle Style;
            internal float MeasuredWidth;
            internal GlyphPathEntry Glyph;
        }

        private readonly struct GlyphPathKey : IEquatable<GlyphPathKey>
        {
            internal GlyphPathKey(string text, int fontKey, int dpiKey)
            {
                Text = text;
                FontKey = fontKey;
                DpiKey = dpiKey;
            }

            private string Text { get; }
            private int FontKey { get; }
            private int DpiKey { get; }

            public bool Equals(GlyphPathKey other)
            {
                return FontKey == other.FontKey && DpiKey == other.DpiKey &&
                    string.Equals(Text, other.Text, StringComparison.Ordinal);
            }

            public override bool Equals(object value)
            {
                return value is GlyphPathKey other && Equals(other);
            }

            public override int GetHashCode()
            {
                unchecked
                {
                    int hash = StringComparer.Ordinal.GetHashCode(Text ?? string.Empty);
                    return (hash * 397 ^ FontKey) * 397 ^ DpiKey;
                }
            }
        }

        private sealed class GlyphPathEntry
        {
            internal GlyphPathEntry(
                GlyphPathKey key,
                GraphicsPath path,
                float measuredWidth,
                RectangleF bounds)
            {
                Key = key;
                Path = path;
                MeasuredWidth = measuredWidth;
                Bounds = bounds;
            }

            internal GlyphPathKey Key { get; }
            internal GraphicsPath Path { get; }
            internal float MeasuredWidth { get; }
            internal RectangleF Bounds { get; }
        }
    }
}
