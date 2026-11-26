using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
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
        internal CombatNumberKind Kind;
        internal float StageX;
        internal float StageY;
        internal float CombinedScale = 1f;
        internal float Alpha = 1f;
        internal float CombinedBlur = 3f;
        internal int Value;
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
        internal float FontSizeOverride;
        internal Color? MainColorOverride;
        internal Color? OutlineColorOverride;
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
        private const int GlyphCacheCapacity = 1024;
        private const int GlyphMaskByteCapacity = 3 * 1024 * 1024;
        private const string NumericCharacters = "0123456789+-";
        private static readonly string[] NumericGlyphs = Array.ConvertAll(
            NumericCharacters.ToCharArray(), character => character.ToString());

        private readonly Dictionary<int, Font> _fontCache = new Dictionary<int, Font>();
        private readonly Dictionary<GlyphKey, LinkedListNode<GlyphMask>> _glyphCache = new();
        private readonly LinkedList<GlyphMask> _glyphLru = new();
        private int _glyphMaskBytes;
        private readonly List<TextSegment> _segments = new List<TextSegment>(10);
        private readonly List<RenderRun> _runs = new List<RenderRun>(12);
        private readonly List<PlacedGlyph> _glyphs = new(32);
        private Rectangle _itemBounds;
        private readonly Pen _outlinePen = new Pen(Color.Black, 1f)
        {
            LineJoin = LineJoin.Round
        };
        private readonly SolidBrush _glyphBrush = new SolidBrush(Color.White);
        private readonly StringFormat _typographic;
        private Bitmap _measureBitmap;
        private Graphics _measureGraphics;
        private float _measureDpi;
        private byte[] _coverageScratch = Array.Empty<byte>();
        private Bitmap _blitBitmap;
        private byte[] _blitPixels;
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
            using Matrix transform = graphics.Transform;
            bool useMasks = transform.IsIdentity && graphics.PageScale == 1f &&
                graphics.CompositingMode == CompositingMode.SourceOver &&
                graphics.PageUnit is GraphicsUnit.Display or GraphicsUnit.Pixel &&
                graphics.DpiX == graphics.DpiY;
            float dpiY = graphics.DpiY;
            Rectangle clip = Rectangle.Empty;
            InterpolationMode interpolation = default;
            PixelOffsetMode pixelOffset = default;
            if (useMasks)
            {
                RectangleF visible = graphics.VisibleClipBounds;
                clip = Rectangle.FromLTRB((int)MathF.Floor(visible.Left), (int)MathF.Floor(visible.Top),
                    (int)MathF.Ceiling(visible.Right), (int)MathF.Ceiling(visible.Bottom));
                interpolation = graphics.InterpolationMode;
                pixelOffset = graphics.PixelOffsetMode;
                graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
                graphics.PixelOffsetMode = PixelOffsetMode.Half;
            }

            int runCount = 0;
            try
            {
                for (int i = 0; i < items.Count; i++)
                {
                    runCount += PrepareItem(items[i], context, dpiY, useMasks ? null : graphics);
                    if (!useMasks) continue;
                    Rectangle visible = Rectangle.Intersect(_itemBounds, clip);
                    if (visible.Width > 0 && visible.Height > 0)
                        BlitItem(graphics, visible);
                }
            }
            finally
            {
                if (useMasks)
                {
                    graphics.InterpolationMode = interpolation;
                    graphics.PixelOffsetMode = pixelOffset;
                }
            }
            return new HitNumberPaintStats(items.Count, runCount);
        }

        internal HitNumberPaintStats PaintToPArgbSurface(
            IntPtr pixels, int surfaceWidth, int surfaceHeight, int strideBytes, float dpiY,
            IReadOnlyList<HitNumberPaintItem> items, HitNumberPaintContext context)
        {
            if (items == null) throw new ArgumentNullException(nameof(items));
            ThrowIfDisposed();
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return default;
            if (pixels == IntPtr.Zero) throw new ArgumentNullException(nameof(pixels));
            if (strideBytes < checked(surfaceWidth * 4))
                throw new ArgumentOutOfRangeException(nameof(strideBytes));
            var destination = new PArgbDestination(pixels, strideBytes, new Rectangle(0, 0, surfaceWidth, surfaceHeight));
            int runCount = 0;
            for (int i = 0; i < items.Count; i++)
            {
                runCount += PrepareItem(items[i], context, dpiY, null);
                CompositeItem(destination);
            }
            return new HitNumberPaintStats(items.Count, runCount);
        }

        private int PrepareItem(
            HitNumberPaintItem item,
            HitNumberPaintContext context,
            float dpiY,
            Graphics vectorGraphics)
        {
            float pixPerFlash = context.PixelsPerFlash;
            float bmpX = context.Viewport.Left + (item.StageX / 1024f) * context.Viewport.Width;
            float bmpY = context.Viewport.Top + (item.StageY / 576f) * context.Viewport.Height;

            Color outlineColor = item.OutlineColorOverride ?? Color.Black;
            byte alpha = (byte)(255 * Math.Max(0f, Math.Min(1f, item.Alpha)));
            float mainPt = MainPointSize(item, pixPerFlash);
            float penWidth = OutlineWidth(item, pixPerFlash);
            BuildRuns(item, pixPerFlash, mainPt);
            int runCount = _runs.Count;
            _glyphs.Clear();
            _itemBounds = Rectangle.Empty;
            if (alpha == 0) return runCount;

            float totalWidth = 0f;
            for (int i = 0; i < runCount; i++)
            {
                RenderRun run = _runs[i];
                run.Outline = run.FontIndex == FontIndexNumber ? outlineColor : Color.Black;
                run.Alpha = alpha;
                MeasureRun(ref run, dpiY, penWidth, vectorGraphics);
                _runs[i] = run;
                totalWidth += run.MeasuredWidth;
            }

            float drawX = bmpX - totalWidth / 2f;
            for (int i = 0; i < runCount; i++)
            {
                RenderRun run = _runs[i];
                PositionRun(ref run, drawX, bmpY, dpiY, penWidth, vectorGraphics);
                _runs[i] = run;
                drawX += run.MeasuredWidth;
            }

            if (item.HitCount > 1)
                PrepareHitCount(item.HitCount, drawX, bmpY, mainPt, penWidth, alpha, dpiY, vectorGraphics);
            return runCount;
        }

        private void BuildRuns(HitNumberPaintItem item, float pixPerFlash, float mainPt)
        {
            _segments.Clear();
            _runs.Clear();

            int flags = HitNumberPacking.Flags(item.Packed);
            Color mainColor = item.MainColorOverride ?? ResolveMainColor(item.Packed);
            Color labelColor = item.EffectTextColorOverride ?? mainColor;
            string mainText = HitNumberPacking.IsMiss(item.Packed) ? "MISS" : CombatNumberValue.Format(
                item.Value, item.Kind == CombatNumberKind.HealHp);
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
                    " 汲:" + CombatNumberValue.Format(CombatNumberValue.ClampToInteger(item.LifeSteal)),
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
                    " 🛡" + CombatNumberValue.Format(CombatNumberValue.ClampToInteger(item.ShieldAbsorb)),
                    Color.FromArgb(0x00, 0xCE, 0xD1), pt, true));
            }

            for (int i = 0; i < _segments.Count; i++)
                SegmentToRuns(_segments[i], _runs);
        }

        internal static float MainPointSize(HitNumberPaintItem item, float pixPerFlash)
        {
            float size = item.FontSizeOverride > 0f ? item.FontSizeOverride : HitNumberPacking.FontSize(item.Packed);
            if (size <= 0f) size = 28f;
            return Clamp(size * item.CombinedScale * pixPerFlash, 6f, 72f);
        }

        internal static float OutlineWidth(HitNumberPaintItem item, float pixPerFlash) =>
            Clamp(item.CombinedBlur * pixPerFlash * 1.2f, 1f, 8f);

        internal static float HitCountPointSize(float mainPt) => Clamp(mainPt * 0.55f, 6f, 36f);
        internal static float HitLabelPointSize(float numberPt) => Clamp(numberPt * 0.5f, 4f, 18f);

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

        private void PrepareHitCount(
            int hitCount,
            float drawX,
            float drawY,
            float mainPt,
            float penWidth,
            byte alpha,
            float dpiY,
            Graphics vectorGraphics)
        {
            float numberPt = HitCountPointSize(mainPt);
            float superscriptX = drawX + 2f;
            float superscriptY = drawY - mainPt * 0.35f;
            var number = new RenderRun
            {
                Text = hitCount.ToString(CultureInfo.InvariantCulture),
                Color = Color.FromArgb(0x00, 0xFF, 0xE0),
                Outline = Color.Black,
                Alpha = alpha,
                FontIndex = FontIndexNumber,
                FontPointSize = numberPt,
                Style = FontStyle.Bold | FontStyle.Italic
            };
            var hit = number;
            hit.Text = "hit";
            hit.FontIndex = FontIndexLabel;
            hit.FontPointSize = HitLabelPointSize(numberPt);
            MeasureRun(ref number, dpiY, penWidth * 0.9f, vectorGraphics);
            MeasureRun(ref hit, dpiY, penWidth * 0.6f, vectorGraphics);
            float pathRight = PositionRun(ref number, superscriptX, superscriptY, dpiY, penWidth * 0.9f, vectorGraphics);
            float hitY = superscriptY + dpiY * (number.Font.SizeInPoints - hit.Font.SizeInPoints) / 72f;
            PositionRun(ref hit, superscriptX + pathRight + 1f, hitY, dpiY, penWidth * 0.6f, vectorGraphics);
            _runs.Add(number);
            _runs.Add(hit);
        }

        private static float FlagScale(string levels, int bit)
        {
            if (string.IsNullOrEmpty(levels) || levels.Length != 9) return 1f;
            int level = levels[bit] - '0';
            if (level <= 0) return 0f;
            if (level >= 9) return 1f;
            return level / 9f;
        }

        internal static float VisualFlagScale(HitNumberPaintItem item, int bit)
        {
            return FlagScale(item.FlagScales, bit) *
                Clamp(item.SemanticDensityScale, 0f, 1f);
        }

        private static float Clamp(float value, float minimum, float maximum)
        {
            return Math.Max(minimum, Math.Min(value, maximum));
        }

        internal static bool IsEmojiCharacter(char c) =>
            char.IsHighSurrogate(c) || c is >= '\u2600' and <= '\u27BF' or >= '\u2B50' and <= '\u2B55';

        private static bool ContainsEmoji(string text)
        {
            for (int i = 0; i < text.Length; i++)
            {
                if (IsEmojiCharacter(text[i])) return true;
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
                    isEmoji = IsEmojiCharacter(c);
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

        private void MeasureRun(ref RenderRun run, float dpiY, float penWidth, Graphics vectorGraphics)
        {
            run.Font = GetCachedFont(run.FontIndex, run.Style, run.FontPointSize, out int fontKey);
            if (vectorGraphics != null)
            {
                run.MeasuredWidth = vectorGraphics.MeasureString(run.Text, run.Font, 9999, _typographic).Width;
                return;
            }

            run.FirstGlyph = _glyphs.Count;
            if (run.FontIndex == FontIndexNumber && run.Text.Length > 1 &&
                run.Text.AsSpan().IndexOfAnyExcept(NumericCharacters) < 0)
            {
                // The combat number font uses additive digit advances with GenericTypographic.
                foreach (char character in run.Text)
                    AddGlyph(ref run, NumericGlyphs[NumericCharacters.IndexOf(character)], fontKey, dpiY, penWidth);
            }
            else
            {
                AddGlyph(ref run, run.Text, fontKey, dpiY, penWidth);
            }
            run.GlyphCount = _glyphs.Count - run.FirstGlyph;
        }

        private void AddGlyph(ref RenderRun run, string text, int fontKey, float dpiY, float penWidth)
        {
            GlyphMask mask = GetCachedGlyph(text, run.Font, fontKey, dpiY, penWidth);
            _glyphs.Add(new PlacedGlyph { Mask = mask, Advance = run.MeasuredWidth });
            run.MeasuredWidth += mask.MeasuredWidth;
        }

        private float PositionRun(ref RenderRun run, float x, float y, float dpiY, float penWidth, Graphics vectorGraphics)
        {
            if (vectorGraphics != null)
                return DrawVectorGlyph(vectorGraphics, run, x, y, dpiY, penWidth);

            // The containing pixel keeps the cached raster aligned with GDI+'s path sampling.
            float pathRight = 0f;
            int originY = (int)MathF.Floor(y);
            int end = run.FirstGlyph + run.GlyphCount;
            for (int i = run.FirstGlyph; i < end; i++)
            {
                PlacedGlyph glyph = _glyphs[i];
                if (glyph.Mask.Bounds.IsEmpty) continue;
                glyph.Bounds = glyph.Mask.Bounds;
                glyph.Bounds.Offset((int)MathF.Floor(x + glyph.Advance), originY);
                _glyphs[i] = glyph;
                run.Bounds = run.Bounds.IsEmpty ? glyph.Bounds : Rectangle.Union(run.Bounds, glyph.Bounds);
                pathRight = Math.Max(pathRight, glyph.Advance + glyph.Mask.PathBoundsRight);
            }

            if (!run.Bounds.IsEmpty)
                _itemBounds = _itemBounds.IsEmpty ? run.Bounds : Rectangle.Union(_itemBounds, run.Bounds);
            return pathRight;
        }

        private GlyphMask GetCachedGlyph(string text, Font font, int fontKey, float dpiY, float penWidth)
        {
            int penBucket = (int)(penWidth * 4f + 0.5f);
            var key = new GlyphKey(text, fontKey, dpiY, penBucket);
            if (_glyphCache.TryGetValue(key, out LinkedListNode<GlyphMask> node))
            {
                if (!ReferenceEquals(_glyphLru.First, node))
                {
                    _glyphLru.Remove(node);
                    _glyphLru.AddFirst(node);
                }
                return node.Value;
            }

            Graphics measure = GetMeasureGraphics(dpiY);
            using GraphicsPath path = CreatePath(text, font, dpiY);
            float width = measure.MeasureString(text, font, 9999, _typographic).Width;
            GlyphMask glyph = RasterizeGlyph(key, path, width, penBucket * 0.25f);
            if (glyph.MaskBytes > GlyphMaskByteCapacity) return glyph;

            while (_glyphCache.Count >= GlyphCacheCapacity ||
                _glyphMaskBytes + glyph.MaskBytes > GlyphMaskByteCapacity)
            {
                GlyphMask last = _glyphLru.Last.Value;
                _glyphLru.RemoveLast();
                _glyphCache.Remove(last.Key);
                _glyphMaskBytes -= last.MaskBytes;
            }
            _glyphCache.Add(key, _glyphLru.AddFirst(glyph));
            _glyphMaskBytes += glyph.MaskBytes;
            return glyph;
        }

        private Graphics GetMeasureGraphics(float dpiY)
        {
            if (_measureGraphics != null && _measureDpi == dpiY) return _measureGraphics;
            _measureGraphics?.Dispose();
            _measureBitmap ??= new Bitmap(1, 1, PixelFormat.Format32bppPArgb);
            _measureBitmap.SetResolution(dpiY, dpiY);
            _measureGraphics = Graphics.FromImage(_measureBitmap);
            _measureGraphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            _measureDpi = dpiY;
            return _measureGraphics;
        }

        private GraphicsPath CreatePath(string text, Font font, float dpiY)
        {
            var path = new GraphicsPath();
            try
            {
                path.AddString(text, font.FontFamily, (int)font.Style, dpiY * font.SizeInPoints / 72f, PointF.Empty, _typographic);
                return path;
            }
            catch
            {
                path.Dispose();
                throw;
            }
        }

        private GlyphMask RasterizeGlyph(GlyphKey key, GraphicsPath path, float width, float penWidth)
        {
            if (path.PointCount == 0)
                return new GlyphMask(key, Rectangle.Empty, width, 0f, Array.Empty<byte>(), Array.Empty<byte>());

            RectangleF pathBounds = path.GetBounds();
            RectangleF padded = pathBounds;
            float margin = penWidth / 2f + 1f;
            padded.Inflate(margin, margin);
            var bounds = Rectangle.FromLTRB(
                (int)MathF.Floor(padded.Left), (int)MathF.Floor(padded.Top),
                (int)MathF.Ceiling(padded.Right), (int)MathF.Ceiling(padded.Bottom));

            using var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppPArgb);
            byte[] outline;
            byte[] fill;
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                graphics.SmoothingMode = SmoothingMode.AntiAlias;
                graphics.TranslateTransform(-bounds.X, -bounds.Y);
                _outlinePen.Width = penWidth;
                _outlinePen.Color = Color.White;
                graphics.DrawPath(_outlinePen, path);
                outline = ReadAlpha(bitmap);

                graphics.Clear(Color.Transparent);
                graphics.FillPath(Brushes.White, path);
                fill = ReadAlpha(bitmap);
            }
            return new GlyphMask(key, bounds, width, pathBounds.Right, outline, fill);
        }

        private static unsafe byte[] ReadAlpha(Bitmap bitmap)
        {
            var bounds = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            var alpha = new byte[checked(bounds.Width * bounds.Height)];
            BitmapData data = bitmap.LockBits(bounds, ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
            try
            {
                for (int y = 0; y < bounds.Height; y++)
                {
                    byte* source = (byte*)data.Scan0 + y * data.Stride + 3;
                    int row = y * bounds.Width;
                    for (int x = 0; x < bounds.Width; x++)
                        alpha[row + x] = source[x * 4];
                }
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
            return alpha;
        }

        private float DrawVectorGlyph(Graphics graphics, RenderRun run, float x, float y, float dpiY, float penWidth)
        {
            using GraphicsPath path = CreatePath(run.Text, run.Font, dpiY);
            GraphicsState state = graphics.Save();
            try
            {
                graphics.TranslateTransform(x, y);
                _outlinePen.Color = Color.FromArgb(run.Alpha, run.Outline);
                _outlinePen.Width = penWidth;
                _glyphBrush.Color = Color.FromArgb(run.Alpha, run.Color);
                graphics.DrawPath(_outlinePen, path);
                graphics.FillPath(_glyphBrush, path);
            }
            finally
            {
                graphics.Restore(state);
            }
            return path.GetBounds().Right;
        }

        private unsafe void BlitItem(Graphics graphics, Rectangle visible)
        {
            if (_blitBitmap == null || _blitBitmap.Width < visible.Width || _blitBitmap.Height < visible.Height)
            {
                int width = Math.Max(visible.Width, _blitBitmap?.Width ?? 0);
                int height = Math.Max(visible.Height, _blitBitmap?.Height ?? 0);
                _blitBitmap?.Dispose();
                _blitBitmap = null;
                _blitPixels = GC.AllocateUninitializedArray<byte>(checked(width * height * 4), pinned: true);
                fixed (byte* pixels = _blitPixels)
                    _blitBitmap = new Bitmap(width, height, width * 4, PixelFormat.Format32bppPArgb, (IntPtr)pixels);
            }

            int stride = _blitBitmap.Width * 4;
            for (int y = 0; y < visible.Height; y++)
                _blitPixels.AsSpan(y * stride, visible.Width * 4).Clear();
            fixed (byte* pixels = _blitPixels)
                CompositeItem(new PArgbDestination((IntPtr)pixels, stride, visible));
            graphics.DrawImageUnscaledAndClipped(_blitBitmap, visible);
        }

        private void CompositeItem(PArgbDestination destination)
        {
            foreach (RenderRun run in _runs)
            {
                Rectangle visible = Rectangle.Intersect(run.Bounds, destination.Bounds);
                if (visible.Width <= 0 || visible.Height <= 0) continue;

                int end = run.FirstGlyph + run.GlyphCount;
                if (run.Alpha < 255 && run.GlyphCount > 1 && HasOverlappingGlyphs(run))
                {
                    CompositeMergedRun(destination, visible, run, outline: true);
                    CompositeMergedRun(destination, visible, run, outline: false);
                    continue;
                }

                for (int i = run.FirstGlyph; i < end; i++)
                {
                    PlacedGlyph glyph = _glyphs[i];
                    CompositeMask(destination, glyph.Bounds, glyph.Mask.OutlineAlpha, run.Outline, run.Alpha);
                }
                for (int i = run.FirstGlyph; i < end; i++)
                {
                    PlacedGlyph glyph = _glyphs[i];
                    CompositeMask(destination, glyph.Bounds, glyph.Mask.FillAlpha, run.Color, run.Alpha);
                }
            }
        }

        private bool HasOverlappingGlyphs(RenderRun run)
        {
            int right = int.MinValue;
            int end = run.FirstGlyph + run.GlyphCount;
            for (int i = run.FirstGlyph; i < end; i++)
            {
                Rectangle bounds = _glyphs[i].Bounds;
                if (bounds.Left < right) return true;
                right = bounds.Right;
            }
            return false;
        }

        private void CompositeMergedRun(PArgbDestination destination, Rectangle visible, RenderRun run, bool outline)
        {
            int length = checked(visible.Width * visible.Height);
            if (_coverageScratch.Length < length)
                Array.Resize(ref _coverageScratch, Math.Max(length, _coverageScratch.Length * 2));
            _coverageScratch.AsSpan(0, length).Clear();
            int end = run.FirstGlyph + run.GlyphCount;
            for (int i = run.FirstGlyph; i < end; i++)
            {
                PlacedGlyph glyph = _glyphs[i];
                Rectangle overlap = Rectangle.Intersect(visible, glyph.Bounds);
                byte[] mask = outline ? glyph.Mask.OutlineAlpha : glyph.Mask.FillAlpha;
                for (int y = overlap.Top; y < overlap.Bottom; y++)
                {
                    int source = (y - glyph.Bounds.Top) * glyph.Bounds.Width + overlap.Left - glyph.Bounds.Left;
                    int target = (y - visible.Top) * visible.Width + overlap.Left - visible.Left;
                    for (int x = 0; x < overlap.Width; x++)
                        _coverageScratch[target + x] = Math.Max(_coverageScratch[target + x], mask[source + x]);
                }
            }
            CompositeMask(destination, visible, _coverageScratch, outline ? run.Outline : run.Color, run.Alpha);
        }

        private static unsafe void CompositeMask(
            PArgbDestination destination, Rectangle maskBounds, byte[] mask, Color color, byte alpha)
        {
            Rectangle visible = Rectangle.Intersect(maskBounds, destination.Bounds);
            if (visible.Width <= 0 || visible.Height <= 0) return;
            int blue = color.B;
            int green = color.G;
            int red = color.R;
            fixed (byte* maskPixels = mask)
            {
                for (int y = visible.Top; y < visible.Bottom; y++)
                {
                    byte* source = maskPixels + (y - maskBounds.Top) * maskBounds.Width + visible.Left - maskBounds.Left;
                    byte* target = (byte*)destination.Pixels + (y - destination.Bounds.Top) * destination.Stride +
                        (visible.Left - destination.Bounds.Left) * 4;
                    for (int x = 0; x < visible.Width; x++, target += 4)
                    {
                        int coverage = source[x];
                        if (coverage == 0) continue;
                        int sa = Div255(coverage * alpha);
                        if (sa == 0) continue;
                        int sb = Div255(blue * sa);
                        int sg = Div255(green * sa);
                        int sr = Div255(red * sa);
                        int da = target[3];
                        if (sa == 255 || da == 0)
                        {
                            target[0] = (byte)sb;
                            target[1] = (byte)sg;
                            target[2] = (byte)sr;
                            target[3] = (byte)sa;
                            continue;
                        }

                        int inverse = 255 - sa;
                        target[0] = (byte)(sb + Div255(target[0] * inverse));
                        target[1] = (byte)(sg + Div255(target[1] * inverse));
                        target[2] = (byte)(sr + Div255(target[2] * inverse));
                        target[3] = (byte)(sa + Div255(da * inverse));
                    }
                }
            }
        }

        private static int Div255(int value) => (value + 128 + ((value + 128) >> 8)) >> 8;


        private void ThrowIfDisposed()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(HitNumberPainter));
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _measureGraphics?.Dispose();
            _measureBitmap?.Dispose();
            _blitBitmap?.Dispose();
            _blitPixels = null;
            _glyphs.Clear();
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
            internal Color Outline;
            internal byte Alpha;
            internal float FontPointSize;
            internal int FontIndex;
            internal FontStyle Style;
            internal Font Font;
            internal float MeasuredWidth;
            internal int FirstGlyph;
            internal int GlyphCount;
            internal Rectangle Bounds;
        }

        private struct PlacedGlyph
        {
            internal GlyphMask Mask;
            internal float Advance;
            internal Rectangle Bounds;
        }

        private readonly record struct PArgbDestination(IntPtr Pixels, int Stride, Rectangle Bounds);
        private readonly record struct GlyphKey(string Text, int FontKey, float DpiY, int PenBucket);

        private sealed record GlyphMask(
            GlyphKey Key, Rectangle Bounds, float MeasuredWidth, float PathBoundsRight,
            byte[] OutlineAlpha, byte[] FillAlpha)
        {
            internal int MaskBytes => OutlineAlpha.Length + FillAlpha.Length;
        }

    }
}
