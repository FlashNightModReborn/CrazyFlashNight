using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace CF7Launcher.Guardian.Hud.Tooltip
{
    /// <summary>
    /// NativeTooltipWidget 的纯布局计算器。输入 document + 文本测量回调 + 缩放 +
    /// 视口尺寸，输出 Plan（面板矩形/文本行/滚动参数/贴图框/关闭框等）。
    ///
    /// 与渲染解耦：测试可用确定性 measure 直接调用 ComputePlan 验证几何，
    /// 不必实例化 widget 或字体。
    ///
    /// 尺寸域约定（视觉权威 = 迁移前 Web：launcher/web/modules/tooltip.js 的
    /// .flash-tt-* 实现 + css/panels/foundation-top.css 的 --tt-* token +
    /// css/panels/foundation-rest.css 的面板/pinned 规则）：
    /// - 逻辑单位分两个 CSS px 域：tooltip **本地** CSS px（transform 前，
    ///   --tt-* token / vh/vw 规则 / inline width 所在域）与**视口** CSS px
    ///   （transform 后，=innerWidth/innerHeight，inset/gap/POINTER_EXCLUSION
    ///   与 stacked 判定所在域）。
    /// - scale = 物理 px / 本地 CSS px = overlayScale × dpi，widget 端按
    ///   max(0.25×dpi, clientH/864) 计算（overlay.css 的
    ///   --cf7-overlay-scale 在 CSS 域 clamp 为 max(0.25, innerHeight/864)，
    ///   FLASH_DESIGN_HEIGHT=864）。dpi = 宿主窗口 DeviceDpi/96；
    ///   viewport 取宿主整个 client 矩形物理 px（=innerWidth/innerHeight×dpi），
    ///   不是 Flash letterbox；vh/vw 与视口域常量经 viewport/dpi 回到 CSS 域。
    /// - Px(x) = round(x * scale)，最小 1px。
    ///
    /// 拆分/合并、估宽、定位夹取全部沿用 AS2/Web 同源规则（shouldSplitWeb、
    /// estimateMainWidth、positionFloating 四候选打分+8px inset 夹取），native
    /// 不另设阈值。
    /// </summary>
    internal static class NativeTooltipLayout
    {
        internal sealed class LayoutOptions
        {
            internal bool WholeSideWidth { get; init; }
            // Preset parity with Web. Native fonts and text boxes already scale together.
            internal bool NoSubOneWidthShrink { get; init; }
            internal bool UnclampSingleSideHeight { get; init; }
            internal bool BalanceWidth { get; init; }
            internal bool CompactRows { get; init; }
            internal bool CompactIntro { get; init; }
            internal bool TwoColumnSide { get; init; }

            internal static readonly LayoutOptions Legacy339 = new LayoutOptions();
            internal static readonly LayoutOptions Tier12 = CreateTier(false, false);
            internal static readonly LayoutOptions Tier13 = CreateTier(true, false);
            internal static readonly LayoutOptions Tier14 = CreateTier(true, true);
            internal static readonly LayoutOptions Default = Tier14;

            private static LayoutOptions CreateTier(bool compact, bool twoColumns) =>
                new LayoutOptions
                {
                    WholeSideWidth = true,
                    NoSubOneWidthShrink = true,
                    UnclampSingleSideHeight = true,
                    BalanceWidth = true,
                    CompactRows = compact,
                    CompactIntro = compact,
                    TwoColumnSide = twoColumns
                };
        }

        // ---- Web token（css/panels/foundation-top.css :root --tt-*）----
        internal const int BaseNum = 200;                 // --tt-intro-w: 200px（R2 锁宽）
        internal const int IntroMinHWideBase = 220;       // --tt-intro-min-h: 220px
        internal const int IntroMinHNarrowBase = 140;     // narrow: 140px（BG_HEIGHT_OFFSET+RATE*200）
        internal const int IconBoxWideBase = 192;         // --tt-icon-size: 192px
        internal const int IconBoxNarrowBase = 111;       // narrow icon: 111px（38*486.8%*0.6）
        internal const int IconTextGapWideBase = 17;      // --tt-icon-text-gap: 17px
        internal const int IconTextGapNarrowBase = 11;    // narrow: 11px（text._y130 - icon底118.5）
        internal const int PanelPadBase = 4;              // --tt-panel-pad: 4px
        internal const int DescMinWBase = 160;            // --tt-desc-min-w: 160px
        internal const int DescDefaultWBase = 280;        // 未达到拓宽门槛时的阅读宽度上限
        internal const int DescMaxWBase = 420;            // 达到字数/行数门槛后的阅读宽度上限
        internal const int DescBalanceMaxWBase = 560;
        internal const double DescExpandScoreThreshold = 900; // 显示权重，约 450 个汉字
        internal const int DescExpandLineThreshold = 18;  // 默认窄栏中的实际折行数
        internal const int DescMaxHBase = 520;            // .flash-tt-desc max-height: min(70vh,520px)
        internal const float DescMaxHViewportFrac = 0.70f;
        internal const int ScrollbarWBase = 6;            // ::-webkit-scrollbar width: 6px
        internal const int ScrollThumbMinHBase = 28;      // thumb min-height: 28px

        // ---- dense 检视状态条（.panel-tooltip-inspection-status，foundation-rest.css）----
        internal const int InspMinHBase = 23;             // min/max-height: 23px（border-box）
        internal const int InspCollapsedHBase = 2;        // inspect 稳态 = 折叠 2px 细条
        internal const int InspMarginBase = 7;            // margin-bottom: 7px
        internal const int InspPadXBase = 7;              // padding: 4px 7px
        internal const int InspBorderLBase = 2;           // border-left: 2px accent
        internal const int InspDotBase = 6;               // ::before 圆点 6px
        internal const int InspGapBase = 7;               // flex gap: 7px
        internal const int InspMeterWBase = 72;           // 进度槽 flex-basis: 72px
        internal const int InspMeterHBase = 2;            // meter height: 2px
        internal const int InspFontBase = 11;             // font-size: 11px / w600
        internal const string InspStatePending = "pending";
        internal const string InspStateInspect = "inspect";
        // 文案与 web inspectionLabel 同值
        internal const string InspPendingLabel = "继续停留，展开完整说明";
        internal const string InspInspectLabel = "已进入检视 · 滚轮阅读 · Esc 退出";

        // ---- 字体/行高（#panel-tooltip font-size:12px；rich lh 1.25）----
        internal const int FontPxBase = 12;
        internal const int FloatingTitleFontBase = 16;    // rich 主框物品名：居中加大
        internal const float LineHeightEm = 1.25f;        // --tt-intro/desc-line-height
        internal const float PlainLineHeightEm = 1.5f;    // #panel-tooltip line-height:1.5
        internal const int PlainPadXBase = 14;            // padding:10px 14px
        internal const int PlainPadYBase = 10;
        internal const int PlainMaxWBase = 480;           // max-width:480px

        // ---- pinned（.panel-tooltip-inspector-* + pinned rich 覆盖）----
        internal const int PinnedWidthBase = 360;         // width:min(360px,100vw-16px)
        internal const int PinnedBorderBase = 1;
        internal const int PinnedHeaderMinHBase = 30;
        internal const int PinnedHeaderPadLBase = 9;      // padding:4px 5px 4px 9px
        internal const int PinnedHeaderPadRBase = 5;
        internal const int PinnedHeaderPadYBase = 4;
        internal const int PinnedHeaderGapBase = 8;
        internal const int PinnedBodyPadBase = 8;         // --tt-panel-pad:8px（pinned 覆盖）
        internal const int PinnedGridIconColBase = 104;   // grid-template-columns:104px 1fr
        internal const int PinnedGridGapBase = 8;
        internal const int PinnedIconBase = 96;           // --tt-icon-size:96px
        internal const int PinnedCloseWBase = 24;
        internal const int PinnedCloseHBase = 22;
        internal const int PinnedScrollbarWBase = 7;
        internal const float PinnedIntroLineHeightEm = 1.4f;
        internal const float PinnedDescLineHeightEm = 1.45f;
        /// <summary>#panel-tooltip letter-spacing:0.3px——继承到 intro/desc/plain/pinned
        /// 全部 tooltip 文本（CSS letter-spacing 每字符追加，含末字符）。</summary>
        internal const float LetterSpacingCss = 0.3f;
        internal const int PinnedTitleFontBase = 11;
        internal const int PinnedKeycapFontBase = 9;
        internal const int PinnedKeycapPadXBase = 5;
        internal const int PinnedKeycapPadYBase = 1;

        // ---- positionFloating / 视口（tooltip.js）----
        internal const int ViewportInsetBase = 8;         // VIEWPORT_INSET
        internal const int AnchorGapBase = 10;            // ANCHOR_GAP
        internal const float PointerExcludeRadiusBase = 16f; // POINTER_EXCLUSION
        internal const float PlacementEps = 0.5f;         // PLACEMENT_EPS
        internal const int StackedMarginBase = 32;        // stacked: calc(100vw-32px)

        // ---- 子注释框（新视觉合同：黑底 80% + 1px 白描边，主面板下方竖排）----
        internal const int SubGapBase = 6;                // 框间间隙（CSS px）

        // ---- 书签式插条（rail，document.rail）：白色书签块自上而下排在图标左侧，
        //      块内文字横向左→右；块宽随文字测量，块间留固定间距 ----
        internal const int RailFontBase = 13;             // 书签字号（CSS px）
        internal const int RailBlockHBase = 22;           // 书签块高（CSS px）
        internal const int RailBlockGapBase = 4;          // 书签块间距（CSS px）
        internal const int RailTextPadXBase = 6;          // 文字与块左右边距（CSS px）
        internal const int RailShiftGapBase = 6;          // stacked 插条行与 intro 面板间距（CSS px）
        internal const int RailMaxWBase = 88;             // 单块最大宽，超出省略（CSS px）
        internal const int RailTextAlpha = 217;           // 插条文字不透明度（85%×255）

        // ---- 弹夹框（document.magazine，intro 面板底部 + 白线分隔）----
        internal const int MagDividerGapBase = 4;         // 正文/分隔线/框内容 的间距
        internal const int MagIconBase = 22;              // 弹夹图标边长（对齐弹夹名行）
        internal const int MagIconTextGapBase = 5;        // 图标与弹夹名间距
        internal const int MagLineGapBase = 1;            // 弹夹名行与子弹类型行间距

        // ---- 插件子框（role:"sub" + kind:"attachments"）----
        internal const int AttachIconBase = 20;           // 插件图标边长（CSS px）
        internal const int AttachIconGapBase = 5;         // 图标与效果文本间距
        internal const int AttachRowGapBase = 3;          // 插件行间距
        internal const int AttachTitleGapBase = 2;        // 标题与首行间距

        // ---- 智能拆分（TooltipConstants.as / shouldSplitWeb 同值）----
        private const double SPLIT_THRESHOLD = 96.0;
        private const int SMART_TOTAL_MULT = 2;
        private const int SMART_DESC_DIV = 2;
        private const int MERGE_MAX_INTRO_LINES = 20;
        private const double MERGE_CHARS_PER_LINE = 33.0;

        // ---- estimateMainWidth（sqrt 基础公式同源；阅读宽度门槛为原生布局合同）----
        private const double TT_PIX_PER_UNIT = 6.0;
        private const double TT_LINE_HEIGHT = 15.0;
        private const double TT_RATIO_MIN = 0.618;
        private const double TT_RATIO_MAX = 1.5;
        private const double TT_RATIO_SCORE_CAP = 300.0;
        private const double TT_MAX_LINES = 32.0;
        private const double TT_LINE_GUTTER = 20.0;
        /// <summary>AS2 MAX_RENDERED_LINES：渲染行数硬上限（intro 长文截断保护）。</summary>
        internal const int MaxRenderedLines = 32;

        /// <summary>CSS px → 物理 px。</summary>
        internal static int Px(float cssPx, float scale)
        {
            return Math.Max(1, (int)Math.Round(cssPx * Math.Max(0.25f, scale)));
        }

        // ──────────── 文本评分（htmlScoresBoth 同源）────────────

        internal struct TextScore
        {
            internal double Total;     // 全文本权重和
            internal double MaxLine;   // 最长单行权重
            internal int LineCount;    // 逻辑行数
        }

        /// <summary>字符权重：空格/tab=0.5，ASCII=1，CJK/全角=2。纯文本契约：标记按字面计。</summary>
        private static double CharWeight(int scalar)
        {
            if (scalar == ' ' || scalar == '\t') return 0.5;
            return scalar < 256 ? 1 : 2;
        }

        internal static bool IsWideChar(int c)
        {
            return (c >= 0x4E00 && c <= 0x9FFF)
                || (c >= 0x3000 && c <= 0x33FF)
                || (c >= 0xFF00 && c <= 0xFFEF)
                || c >= 0x10000;
        }

        internal static TextScore ScoreText(string s)
        {
            TextScore sc = new TextScore { LineCount = 1 };
            if (string.IsNullOrEmpty(s)) { sc.LineCount = 1; return sc; }
            double line = 0;
            s = NativeTextElements.NormalizeDisplay(s);
            for (int i = 0; i < s.Length;)
            {
                char c = s[i];
                if (c == '\n' || c == '\r')
                {
                    if (line > sc.MaxLine) sc.MaxLine = line;
                    line = 0;
                    sc.LineCount++;
                    // \r\n / \n\r 计一次断行
                    if (i + 1 < s.Length
                        && (s[i + 1] == '\n' || s[i + 1] == '\r') && s[i + 1] != c) i++;
                    i++;
                    continue;
                }
                // Size hints count a displayed element once, using its first scalar.
                double w = CharWeight(char.ConvertToUtf32(s, i));
                sc.Total += w;
                line += w;
                i += StringInfo.GetNextTextElementLength(s.AsSpan(i));
            }
            if (line > sc.MaxLine) sc.MaxLine = line;
            return sc;
        }

        internal static TextScore ScoreSections(IList<NativeTooltipSection> sections)
        {
            TextScore sum = new TextScore { LineCount = 0 };
            if (sections == null) return sum;
            foreach (NativeTooltipSection sec in sections)
            {
                if (sec == null) continue;
                TextScore s = ScoreText(sec.PlainText);
                sum.Total += s.Total;
                if (s.MaxLine > sum.MaxLine) sum.MaxLine = s.MaxLine;
                sum.LineCount += s.LineCount;
            }
            if (sum.LineCount == 0) sum.LineCount = 1;
            return sum;
        }

        // ──────────── estimateMainWidth（默认窄栏，过门槛后拓宽）────────────

        /// <summary>默认沿用 sqrt 公式，但宽度不超过 DescDefaultWBase；总显示权重、累计
        /// 逻辑行数或默认窄栏实际折行数超过门槛后才使用 maxW。</summary>
        internal static int EstimateMainWidth(TextScore s, int minW, int maxW,
            int renderedLineCount = 0)
        {
            if (s.Total <= 0) return minW;
            if (s.Total > DescExpandScoreThreshold
                || Math.Max(s.LineCount, renderedLineCount) > DescExpandLineThreshold)
                return Math.Max(minW, maxW);
            double t = s.Total / TT_RATIO_SCORE_CAP;
            if (t > 1) t = 1;
            double ss = t * t * (3 - 2 * t);
            double r = TT_RATIO_MIN + ss * (TT_RATIO_MAX - TT_RATIO_MIN);
            double sqrtW = Math.Sqrt(r * s.Total * TT_PIX_PER_UNIT * TT_LINE_HEIGHT);
            double wFloor = s.Total * TT_PIX_PER_UNIT / TT_MAX_LINES;
            if (sqrtW < wFloor) sqrtW = wFloor;
            if (s.MaxLine > 0)
            {
                double maxLineW = s.MaxLine * TT_PIX_PER_UNIT + TT_LINE_GUTTER;
                if (sqrtW > maxLineW) sqrtW = maxLineW;
            }
            if (sqrtW < minW) sqrtW = minW;
            double defaultCap = Math.Min(maxW, DescDefaultWBase);
            if (sqrtW > defaultCap) sqrtW = defaultCap;
            return (int)Math.Round(sqrtW);
        }

        // ──────────── 拆分判定（shouldSplitWeb 同源）────────────

        internal static bool ShouldSplit(TextScore desc, TextScore intro)
        {
            double total = desc.Total + intro.Total;
            if (total > SPLIT_THRESHOLD * SMART_TOTAL_MULT
                && desc.Total > SPLIT_THRESHOLD / SMART_DESC_DIV) return true;
            // merge 二次兜底：合并估算行数 > 20 仍强制 split
            if (total / MERGE_CHARS_PER_LINE > MERGE_MAX_INTRO_LINES) return true;
            return false;
        }

        // ──────────── 折行（保留 run 级样式 slice）────────────

        /// <summary>
        /// run 级字体样式（测量/绘图源）。FontSize 为 CSS px（web inline
        /// font-size:Npx）；FontFace 为 sanitizer 过的 legacy 别名（web
        /// CF7FontCatalog.legacyFamily 命中才生效，未命中继承正文体）。
        /// </summary>
        internal struct RunFont
        {
            internal bool Bold;
            internal bool Italic;
            internal bool Underline;
            internal int? FontSize;
            internal string FontFace;

            internal static RunFont Of(NativeTooltipRun r)
            {
                RunFont f = new RunFont();
                if (r != null)
                {
                    f.Bold = r.Bold;
                    f.Italic = r.Italic;
                    f.Underline = r.Underline;
                    f.FontSize = r.FontSize;
                    f.FontFace = r.FontFace;
                }
                return f;
            }
        }

        internal sealed class VisualLine
        {
            internal sealed class Slice
            {
                internal string Text;
                internal string PaintOverride;
                internal Color? Color;
                internal bool Bold;
                internal bool Italic;
                internal bool Underline;
                internal int? FontSize;
                internal string FontFace;
                internal NativeTooltipFaction Faction;
                internal int WidthPx;
                /// <summary>含 letter-spacing 的精确宽（物理 px 浮点），绘制推进用。</summary>
                internal float WidthF;

                internal RunFont FontOf()
                {
                    return new RunFont
                    {
                        Bold = Bold, Italic = Italic, Underline = Underline,
                        FontSize = FontSize, FontFace = FontFace
                    };
                }
            }

            internal List<Slice> Slices = new List<Slice>();
            internal bool IsBlank;
            /// <summary>本行行高（物理 px，四舍五入展示值）。</summary>
            internal int LineHeightPx;
            /// <summary>本行精确行高（物理 px 浮点）——随行内最大 run 字号增长
            /// （CSS line box = max(inline 高)）；绘制/滚动/高度累加一律用它，
            /// 避免逐行取整累计漂移（如 900px 视口 15.625 行高）。</summary>
            internal float LineHeightF;
            /// <summary>true=本行以硬断行（\n/流末）收尾，是一条逻辑行的结尾；
            /// false=软换行产生的续行。与 web innerText 语义对应（软折不产生 \n）。</summary>
            internal bool EndsLogicalLine;
            internal string IconName;
            // 行内图标相对该行的文本原点，纵向在绘制时按真实行高居中。
            internal Rectangle IconRect;
            internal int TextOffsetPx;
            internal VisualLine RightHalf;
            internal int RightHalfOffsetPx;

            internal float Height(float fallback) => LineHeightF > 0 ? LineHeightF
                : LineHeightPx > 0 ? LineHeightPx : fallback;

            internal float RowHeight(float fallback) => RightHalf == null
                ? Height(fallback) : Math.Max(Height(fallback), RightHalf.Height(fallback));
        }

        /// <summary>
        /// 把 run 序列折成视觉行——与 web 排版对齐：runs 是同一文本流内的内联
        /// span（样式分片），run 边界不产生断行；'\n'/'\r\n' 为唯一硬断行；
        /// 空 run 不占位（web runHtml 对空串返回 ''）。软换行：空格/'-' 后、
        /// 宽字符（CJK）逐字可断；开标点（（【等）后、闭标点（，。：等）前禁断；
        /// 换行后行首空白塌陷。measure(text,font) 返回物理 px 宽。
        /// </summary>
        internal static List<VisualLine> WrapRuns(
            IList<NativeTooltipRun> runs,
            int maxWidthPx,
            Func<string, bool, int> measure)
        {
            return WrapRuns(runs, maxWidthPx, measure, 0);
        }

        internal static List<VisualLine> WrapRuns(
            IList<NativeTooltipRun> runs,
            int maxWidthPx,
            Func<string, bool, int> measure,
            float lineHeightPx)
        {
            return WrapRuns(runs, maxWidthPx,
                delegate (string t, RunFont f) { return measure(t, f.Bold); },
                lineHeightPx);
        }

        internal static List<VisualLine> WrapRuns(
            IList<NativeTooltipRun> runs,
            int maxWidthPx,
            Func<string, RunFont, int> measure,
            float lineHeightPx)
        {
            return WrapRuns(runs, maxWidthPx, measure, lineHeightPx, 0f);
        }

        internal static List<VisualLine> WrapRuns(
            IList<NativeTooltipRun> runs,
            int maxWidthPx,
            Func<string, RunFont, int> measure,
            float lineHeightPx,
            float letterSpacingPx)
        {
            List<VisualLine> outLines = new List<VisualLine>();
            if (runs == null || runs.Count == 0 || maxWidthPx <= 0) return outLines;

            // Segment the complete inline stream. A cluster that crosses a style
            // boundary takes the style of its first UTF-16 unit.
            StringBuilder stream = new StringBuilder();
            foreach (NativeTooltipRun run in runs) stream.Append(run?.Text);
            string text = NativeTextElements.NormalizeDisplay(stream.ToString());
            int[] starts = NativeTextElements.Starts(text);
            Func<string, RunFont, float> measureF =
                (t, f) => measure(t, f) + (letterSpacingPx == 0f ? 0f
                    : NativeTextElements.Starts(t).Length * letterSpacingPx);

            LineBuf cur = new LineBuf(lineHeightPx);
            int runIndex = 0;
            int runEnd = runs[0]?.Text?.Length ?? 0;
            for (int i = 0; i < starts.Length; i++)
            {
                int start = starts[i];
                int end = i + 1 < starts.Length ? starts[i + 1] : text.Length;
                while (start >= runEnd) runEnd += runs[++runIndex]?.Text?.Length ?? 0;
                NativeTooltipRun run = runs[runIndex];
                int scalar = char.ConvertToUtf32(text, start);
                if (scalar == '\r' || scalar == '\n')
                {
                    outLines.Add(cur.FlushLine());
                    continue;
                }
                bool space = end == start + 1 && (scalar == ' ' || scalar == '\t');
                string paintOverride = null;
                if (scalar == 0x200B && letterSpacingPx == 0f)
                {
                    // A sequence of zero-width spaces has no ink. Keep its source
                    // span and break opportunity without shaping every prefix.
                    while (end < runEnd && text[end] == '\u200B')
                    {
                        i++;
                        end = i + 1 < starts.Length ? starts[i + 1] : text.Length;
                    }
                    paintOverride = string.Empty;
                }
                string element = space ? " " : text.Substring(start, end - start);
                RunFont font = RunFont.Of(run);
                while (!space || (cur.HasContent && cur.LastChar != ' '))
                {
                    float delta;
                    try
                    {
                        delta = paintOverride != null ? 0f : cur.TrialDelta(element, run, font, measureF);
                    }
                    catch (ExternalException)
                    {
                        if (cur.HasContent)
                        {
                            // Retry the complete element on a fresh line before
                            // attributing a GDI+ run limit to that element.
                            if (cur.BrkSlice >= 0) BreakAt(cur, outLines, measureF);
                            else outLines.Add(cur.FlushLine(endsLogicalLine: false));
                            continue;
                        }
                        paintOverride = "□";
                        delta = measureF(paintOverride, font);
                        LogManager.Log($"[NativeTooltip] GDI+ refused U+{scalar:X} at {start} ({end - start} UTF-16 units).");
                    }
                    if (!cur.HasContent || cur.WidthF + delta <= maxWidthPx)
                    {
                        cur.Append(element, run, font, delta, paintOverride);
                        int next = end < text.Length ? char.ConvertToUtf32(text, end) : -1;
                        if (scalar == 0x200B || CanBreakAfter(scalar, next)) MarkBreak(cur);
                        break;
                    }
                    if (cur.BrkSlice >= 0) BreakAt(cur, outLines, measureF);
                    else outLines.Add(cur.FlushLine(endsLogicalLine: false));
                }
            }
            if (cur.HasContent) outLines.Add(cur.FlushLine());
            return outLines;
        }

        /// <summary>当前构造行：slice 流 + 最近可断点（断点=该 slice 前 BrkLen 字符之后）。</summary>
        private sealed class LineBuf
        {
            internal readonly float BaseLh;
            internal readonly List<VisualLine.Slice> Slices =
                new List<VisualLine.Slice>();
            internal float WidthF;
            internal int BrkSlice = -1;
            internal int BrkLen;
            internal char LastChar;
            internal int MaxFontCss = FontPxBase;
            internal bool HasContent { get { return Slices.Count > 0; } }

            /// <summary>行高 = max(基准行高, 行内最大字号×1.25)——CSS line box
            /// 取行内最大 inline box 高；BaseLh=12×em 已含 scale，比例换算免传 scale。
            /// 全程浮点，四舍五入只发生在最终展示值上。</summary>
            internal float HeightF
            {
                get
                {
                    return Math.Max(BaseLh, BaseLh * MaxFontCss / FontPxBase);
                }
            }

            internal LineBuf(float lh) { BaseLh = Math.Max(1f, lh); }

            private static bool SameStyle(VisualLine.Slice s, NativeTooltipRun run,
                RunFont font)
            {
                return s.PaintOverride == null && s.Color == (run != null ? run.Color : null)
                    && s.Bold == font.Bold && s.Italic == font.Italic
                    && s.Underline == font.Underline
                    && s.FontSize == font.FontSize && s.FontFace == font.FontFace
                    && s.Faction == (run != null ? run.Faction : NativeTooltipFaction.None);
            }

            /// <summary>追加字符的行宽增量（浮点，含 letter-spacing）：
            /// 可并入末 slice 时量整段文本取差。</summary>
            internal float TrialDelta(string element, NativeTooltipRun run, RunFont font,
                Func<string, RunFont, float> measure)
            {
                VisualLine.Slice last =
                    Slices.Count > 0 ? Slices[Slices.Count - 1] : null;
                if (last != null && SameStyle(last, run, font))
                    return measure(last.Text + element, font) - last.WidthF;
                return measure(element, font);
            }

            internal void Append(string element, NativeTooltipRun run, RunFont font, float cw,
                string paintOverride)
            {
                VisualLine.Slice last = Slices.Count > 0 ? Slices[Slices.Count - 1] : null;
                Color? color = run != null ? run.Color : null;
                if (paintOverride == null && last != null && SameStyle(last, run, font))
                {
                    last.Text += element;
                    last.WidthF += cw;
                    last.WidthPx = (int)Math.Round(last.WidthF);
                }
                else
                {
                    Slices.Add(new VisualLine.Slice
                    {
                        Text = element,
                        PaintOverride = paintOverride,
                        Color = color,
                        Bold = font.Bold,
                        Italic = font.Italic,
                        Underline = font.Underline,
                        FontSize = font.FontSize,
                        FontFace = font.FontFace,
                        Faction = run != null ? run.Faction : NativeTooltipFaction.None,
                        WidthF = cw,
                        WidthPx = (int)Math.Round(cw)
                    });
                }
                if (font.FontSize.HasValue && font.FontSize.Value > MaxFontCss)
                    MaxFontCss = font.FontSize.Value;
                WidthF += cw;
                LastChar = element[element.Length - 1];
            }

            internal VisualLine FlushLine(bool endsLogicalLine = true)
            {
                float h = HeightF;
                VisualLine l = new VisualLine
                {
                    LineHeightF = h,
                    LineHeightPx = (int)Math.Round(h),
                    EndsLogicalLine = endsLogicalLine
                };
                l.Slices.AddRange(Slices);
                l.IsBlank = Slices.Count == 0;
                Slices.Clear();
                WidthF = 0f;
                BrkSlice = -1; BrkLen = 0; LastChar = '\0';
                MaxFontCss = FontPxBase;
                return l;
            }
        }

        private static void MarkBreak(LineBuf cur)
        {
            cur.BrkSlice = cur.Slices.Count - 1;
            cur.BrkLen = cur.Slices[cur.BrkSlice].Text.Length;
        }

        /// <summary>在最近断点处断行：断点前内容出行为一行，尾部留给新行。</summary>
        private static void BreakAt(LineBuf cur, List<VisualLine> outLines,
            Func<string, RunFont, float> measure)
        {
            VisualLine head = new VisualLine();
            for (int s = 0; s < cur.BrkSlice; s++) head.Slices.Add(cur.Slices[s]);
            VisualLine.Slice mid = cur.Slices[cur.BrkSlice];
            string headText = mid.Text.Substring(0, cur.BrkLen);
            string tailText = mid.Text.Substring(cur.BrkLen);
            if (headText.Length > 0)
            {
                VisualLine.Slice hs = CloneSlice(mid);
                hs.Text = headText;
                hs.WidthF = cur.BrkLen == mid.Text.Length ? mid.WidthF : measure(headText, mid.FontOf());
                hs.WidthPx = (int)Math.Round(hs.WidthF);
                head.Slices.Add(hs);
            }
            head.IsBlank = head.Slices.Count == 0;
            head.LineHeightF = HeightOf(head.Slices, cur.BaseLh);
            head.LineHeightPx = (int)Math.Round(head.LineHeightF);
            head.EndsLogicalLine = false;
            outLines.Add(head);

            cur.Slices.RemoveRange(0, cur.BrkSlice + 1);
            if (tailText.Length > 0)
            {
                VisualLine.Slice ts = CloneSlice(mid);
                ts.Text = tailText;
                ts.WidthF = measure(tailText, ts.FontOf());
                ts.WidthPx = (int)Math.Round(ts.WidthF);
                cur.Slices.Insert(0, ts);
            }
            cur.WidthF = 0f;
            cur.MaxFontCss = FontPxBase;
            foreach (VisualLine.Slice s in cur.Slices)
            {
                cur.WidthF += s.WidthF;
                if (s.FontSize.HasValue && s.FontSize.Value > cur.MaxFontCss)
                    cur.MaxFontCss = s.FontSize.Value;
            }
            cur.BrkSlice = -1;
            cur.BrkLen = 0;
            cur.LastChar = cur.Slices.Count > 0
                ? cur.Slices[cur.Slices.Count - 1].Text[
                    cur.Slices[cur.Slices.Count - 1].Text.Length - 1]
                : '\0';
        }

        /// <summary>
        /// 视觉行 → 逻辑行（web innerText 同构）：把软换行续行的 slice 并回
        /// 所属逻辑行；空逻辑行丢弃（fixture innerText 提取同样丢空行）。
        /// </summary>
        internal static List<VisualLine> MergeLogicalLines(List<VisualLine> lines)
        {
            List<VisualLine> outp = new List<VisualLine>();
            VisualLine acc = null;
            foreach (VisualLine l in InReadingOrder(lines))
            {
                if (acc == null) acc = new VisualLine();
                foreach (VisualLine.Slice s in l.Slices)
                {
                    VisualLine.Slice last = acc.Slices.Count > 0
                        ? acc.Slices[acc.Slices.Count - 1] : null;
                    if (last != null && last.PaintOverride == null && s.PaintOverride == null && last.Color == s.Color
                        && last.Bold == s.Bold && last.Italic == s.Italic
                        && last.Underline == s.Underline
                        && last.FontSize == s.FontSize && last.FontFace == s.FontFace
                        && last.Faction == s.Faction)
                    {
                        last.Text += s.Text;
                        last.WidthF += s.WidthF;
                        last.WidthPx = (int)Math.Round(last.WidthF);
                    }
                    else
                    {
                        acc.Slices.Add(CloneSlice(s));
                    }
                }
                // 逻辑行高 = 构成它的各视觉行真实高之和（软折续行仍占垂直空间）
                acc.LineHeightF += l.LineHeightF > 0 ? l.LineHeightF : l.LineHeightPx;
                if (l.EndsLogicalLine)
                {
                    if (acc.Slices.Count > 0)
                    {
                        acc.LineHeightPx = (int)Math.Round(acc.LineHeightF);
                        outp.Add(acc);
                    }
                    acc = null;
                }
            }
            if (acc != null && acc.Slices.Count > 0)
            {
                acc.LineHeightPx = (int)Math.Round(acc.LineHeightF);
                outp.Add(acc);
            }
            return outp;
        }

        internal static IEnumerable<VisualLine> InReadingOrder(IEnumerable<VisualLine> lines)
        {
            foreach (VisualLine line in lines)
            {
                yield return line;
                if (line.RightHalf != null) yield return line.RightHalf;
            }
        }

        private static void PairShortLines(List<VisualLine> lines, int halfW, int gap,
            Func<VisualLine, bool> eligible)
        {
            int write = 0;
            for (int read = 0; read < lines.Count; read++)
            {
                VisualLine left = lines[read];
                if (read + 1 < lines.Count && eligible(left) && eligible(lines[read + 1]))
                {
                    left.RightHalf = lines[++read];
                    left.RightHalfOffsetPx = halfW + gap;
                }
                lines[write++] = left;
            }
            lines.RemoveRange(write, lines.Count - write);
        }

        private static List<VisualLine> BuildIntroLines(List<NativeTooltipRun> runs,
            int textW, float scale, Func<string, RunFont, int> measure, float lh, bool compact)
        {
            List<VisualLine> lines = WrapRuns(runs, textW, measure, lh);
            if (!compact) return lines;
            int gap = Px(6, scale);
            int halfW = (textW - gap) / 2;
            var eligible = new HashSet<VisualLine>();
            bool startsLogicalLine = true;
            foreach (VisualLine line in lines)
            {
                if (startsLogicalLine && line.EndsLogicalLine && !line.IsBlank
                    && RenderedLineWidth(line, measure) <= halfW)
                {
                    var text = new StringBuilder();
                    foreach (var slice in line.Slices) text.Append(slice.Text);
                    string value = text.ToString();
                    if ((value.Contains('：') || value.Contains(':'))
                        && !value.StartsWith("固有结构", StringComparison.Ordinal)
                        && !value.StartsWith("禁止挂点", StringComparison.Ordinal))
                        eligible.Add(line);
                }
                startsLogicalLine = line.EndsLogicalLine;
            }
            PairShortLines(lines, halfW, gap, eligible.Contains);
            return lines;
        }

        /// <summary>由 slice 集合求行高（断行后头行/余行各自重算，同 CSS line box）。</summary>
        private static float HeightOf(IList<VisualLine.Slice> slices, float baseLh)
        {
            int maxFont = FontPxBase;
            foreach (VisualLine.Slice s in slices)
                if (s.FontSize.HasValue && s.FontSize.Value > maxFont)
                    maxFont = s.FontSize.Value;
            return Math.Max(baseLh, baseLh * maxFont / FontPxBase);
        }

        private static VisualLine.Slice CloneSlice(VisualLine.Slice s)
        {
            return new VisualLine.Slice
            {
                Text = s.Text, PaintOverride = s.PaintOverride, Color = s.Color, Bold = s.Bold, Italic = s.Italic,
                Underline = s.Underline, FontSize = s.FontSize, FontFace = s.FontFace,
                Faction = s.Faction, WidthPx = s.WidthPx, WidthF = s.WidthF
            };
        }

        /// <summary>
        /// 当前字素之后是否可断——CSS line-break/UAX14 近似：
        /// 开标点后、闭标点前禁断；空白/'-' 后、宽字符后、西文→宽字符边界可断。
        /// </summary>
        private static bool CanBreakAfter(int scalar, int next)
        {
            if (IsOpeningPunct(scalar) || IsClosingPunct(next)) return false;
            return scalar == ' ' || scalar == '\t' || scalar == '-'
                || IsWideChar(scalar) || IsWideChar(next);
        }

        /// <summary>开标点（UAX14 OP 近似）：其后禁止断行。</summary>
        private static bool IsOpeningPunct(int c)
        {
            switch (c)
            {
                case '(': case '[': case '{':
                case '（': case '【': case '《': case '「': case '『': case '〈':
                case '‘': case '“':
                    return true;
            }
            return false;
        }

        /// <summary>闭标点（UAX14 CL/IS 近似）：其前禁止断行。</summary>
        private static bool IsClosingPunct(int c)
        {
            switch (c)
            {
                case ',': case '.': case ';': case ':': case '!': case '?':
                case ')': case ']': case '}': case '%': case '\'': case '"':
                case '，': case '。': case '、': case '；': case '：':
                case '！': case '？':
                case '）': case '】': case '》': case '」': case '』': case '〉':
                case '’': case '”': case '％':
                    return true;
            }
            return false;
        }

        // ──────────── 段落提取 / columnHtml 同构拼接 ────────────

        private static List<NativeTooltipSection> SectionsOf(
            NativeTooltipDocument doc, NativeTooltipSectionRole role)
        {
            List<NativeTooltipSection> list = new List<NativeTooltipSection>();
            foreach (NativeTooltipSection s in doc.SectionsByRole(role)) list.Add(s);
            return list;
        }

        /// <summary>desc 栏内容 = description + body 段（按文档序）。</summary>
        internal static List<NativeTooltipSection> DescSections(NativeTooltipDocument doc)
        {
            List<NativeTooltipSection> list = new List<NativeTooltipSection>();
            foreach (NativeTooltipSection s in doc.Sections)
            {
                if (s == null) continue;
                if (s.Role == NativeTooltipSectionRole.Description
                    || s.Role == NativeTooltipSectionRole.Body) list.Add(s);
            }
            return list;
        }

        private static NativeTooltipRun BreakRun()
        {
            return new NativeTooltipRun("\n", null, false);
        }

        /// <summary>
        /// web tooltip-document.js columnHtml 同构：按文档序拼接指定 section 集；
        /// 相邻 section 间仅在前段输出未以断行结尾时补一个 '\n'（web:
        /// `if (out && !atLineStart) out += '&lt;br&gt;'`）；整段无可见文本的
        /// section 计一个空行（web: `if (!inner) inner = '&lt;br&gt;'`）。
        /// </summary>
        private static List<VisualLine> BuildUpgradeLines(
            IList<NativeTooltipSection> sections, int textW, float scale, Func<string, RunFont, int> measure, float lh,
            bool leadingBlank, bool compactRows)
        {
            List<VisualLine> lines = new List<VisualLine>();
            if (sections == null) return lines;
            int iconPx = Px(22, scale);
            int iconGap = Px(AttachIconGapBase, scale);
            foreach (NativeTooltipSection sec in sections)
            {
                if (sec == null || sec.Kind != "upgrades" || !sec.IsAttachments) continue;
                if (leadingBlank)
                {
                    lines.Add(new VisualLine
                    {
                        IsBlank = true, LineHeightF = lh,
                        LineHeightPx = (int)Math.Round(lh), EndsLogicalLine = true
                    });
                }
                if (!string.IsNullOrEmpty(sec.Title))
                {
                    List<NativeTooltipRun> titleRuns = new List<NativeTooltipRun>();
                    titleRuns.Add(new NativeTooltipRun(sec.Title, null, true));
                    List<VisualLine> titleLines = WrapRuns(titleRuns, textW, measure, lh);
                    lines.AddRange(titleLines);
                }
                VisualLine previousShort = null;
                int childIndent = Px(8, scale);
                int columnGap = Px(8, scale);
                int halfW = (textW - childIndent - columnGap) / 2;
                bool pair = compactRows && textW >= Px(300, scale);
                for (int i = 0; i < sec.Rows.Count; i++)
                {
                    NativeTooltipAttachmentRow row = sec.Rows[i];
                    bool child = row.Depth == 1;
                    int indent = child ? childIndent : 0;
                    List<NativeTooltipRun> content = new List<NativeTooltipRun>();
                    if (child || row.Runs.Count == 0)
                        content.Add(new NativeTooltipRun(row.Name, null, true));
                    else
                        content.AddRange(row.Runs);
                    if (child) content.AddRange(row.Runs);
                    content = ExpandFactionRuns(content);
                    int rowTextW = Math.Max(1, textW - indent - (child ? iconPx + iconGap : 0));
                    List<VisualLine> wrapped = WrapRuns(content, rowTextW, measure, lh);
                    for (int j = 0; j < wrapped.Count; j++)
                    {
                        VisualLine line = wrapped[j];
                        if (child)
                        {
                            line.TextOffsetPx = indent + iconPx + iconGap;
                            if (j == 0)
                            {
                                line.IconName = row.IconName;
                                line.LineHeightF = Math.Max(line.LineHeightF, iconPx);
                                line.LineHeightPx = Math.Max(line.LineHeightPx, iconPx);
                                line.IconRect = new Rectangle(indent, 0, iconPx, iconPx);
                            }
                        }
                    }
                    bool shortChild = pair && child && wrapped.Count == 1 && !HasHardBreak(content)
                        && RenderedLineWidth(wrapped[0], measure) - indent <= halfW;
                    if (shortChild && previousShort != null)
                    {
                        previousShort.RightHalf = wrapped[0];
                        previousShort.RightHalfOffsetPx = halfW + columnGap;
                        previousShort = null;
                    }
                    else
                    {
                        lines.AddRange(wrapped);
                        previousShort = shortChild ? wrapped[0] : null;
                    }
                }
                leadingBlank = false;
            }
            return lines;
        }

        private static List<NativeTooltipRun> BuildColumnRuns(
            IEnumerable<NativeTooltipSection> sections, bool includeUpgradeText = true)
        {
            List<NativeTooltipRun> runs = new List<NativeTooltipRun>();
            if (sections == null) return runs;
            foreach (NativeTooltipSection s in sections)
            {
                if (s == null || (s.Kind == "upgrades" && s.IsAttachments && !includeUpgradeText)) continue;
                bool empty = true;
                if (s.Runs != null)
                {
                    foreach (NativeTooltipRun r in s.Runs)
                    {
                        if (r != null && !string.IsNullOrEmpty(r.Text))
                        {
                            empty = false;
                            break;
                        }
                    }
                }
                if (runs.Count > 0 && !EndsWithBreak(runs)) runs.Add(BreakRun());
                if (empty) runs.Add(BreakRun());
                else runs.AddRange(ExpandFactionRuns(s.Runs));
            }
            return runs;
        }

        /// <summary>run 列表最后可见文本是否以断行结尾（web atLineStart 判定）。</summary>
        private static bool EndsWithBreak(List<NativeTooltipRun> runs)
        {
            for (int i = runs.Count - 1; i >= 0; i--)
            {
                string t = runs[i] != null ? runs[i].Text : null;
                if (string.IsNullOrEmpty(t)) continue;
                return t[t.Length - 1] == '\n' || t[t.Length - 1] == '\r';
            }
            return false;
        }

        /// <summary>
        /// intro 栏 = title 块（.ntt-title 为 div 块级，独占一行）+ intro 段列
        /// （web: `titleHtml + columnHtml(doc,{intro:true})`）。
        /// </summary>
        private static List<NativeTooltipRun> IntroColumnRuns(
            NativeTooltipDocument doc, IList<NativeTooltipSection> introSecs,
            bool includeTitle = true)
        {
            List<NativeTooltipRun> runs = new List<NativeTooltipRun>();
            if (includeTitle && doc.TitleRuns.Count > 0)
            {
                runs.AddRange(doc.TitleRuns);
                runs.Add(BreakRun());
            }
            runs.AddRange(BuildColumnRuns(introSecs));
            return runs;
        }

        /// <summary>
        /// merge：desc 列拼进 intro 尾部，固定 '&lt;br&gt;&lt;br&gt;' 分隔
        /// （web buildItemRichHtml merge 分支：`sep = introColumn 或 meta 且
        /// descColumn ? '&lt;br&gt;&lt;br&gt;' : ''`）。
        /// </summary>
        private static void AppendMergedDesc(List<NativeTooltipRun> introRuns,
            IList<NativeTooltipSection> descSecs)
        {
            List<NativeTooltipRun> descRuns = BuildColumnRuns(descSecs);
            if (descRuns.Count == 0) return;
            if (introRuns.Count > 0)
                introRuns.Add(new NativeTooltipRun("\n\n", null, false));
            introRuns.AddRange(descRuns);
        }

        // ──────────── Plan ────────────

        internal enum ReadingTarget { None, Side, WholeRich, PinnedBody }

        internal sealed class Plan
        {
            /// <summary>整 tip 尺寸（物理 px）。</summary>
            internal Size TipSize;
            /// <summary>true=拆分（desc 独立侧栏）；false=合并单面板。</summary>
            internal bool Split;
            internal int SideColumns = 1;
            /// <summary>true=stacked 降级（并排放不下→竖排）。</summary>
            internal bool Stacked;
            /// <summary>true=pinned 检视器（壳+header+body 滚动）。</summary>
            internal bool Pinned;
            /// <summary>true=plain 文本提示（非 rich 骨架：单灰渐变框 pad10/14）。</summary>
            internal bool Plain;
            /// <summary>layoutType=="wide"（默认）；false=narrow。</summary>
            internal bool LayoutWide = true;
            internal float Scale = 1f;

            internal string Title;
            internal string IconName;

            /// <summary>intro 面板矩形（tip 相对）。无 intro 面板时 Empty。</summary>
            internal Rectangle IntroPanel;
            /// <summary>desc 面板矩形（tip 相对）。仅 split 非 pinned 时有。</summary>
            internal Rectangle DescPanel;
            /// <summary>图标贴图框（tip 相对）。</summary>
            internal Rectangle IconRect;

            /// <summary>书签式插条块（最多 2 个，tip 相对；文字横向左→右）。
            /// 空 = 无插条。stacked 降级时块横向排列在 intro 面板上方。</summary>
            internal List<RailBlock> RailBlocks = new List<RailBlock>();
            /// <summary>插条让位量：并排=整列右移宽度（列宽+间距）；stacked=下方整体下移高度。</summary>
            internal int RailShift;

            /// <summary>单个书签块（矩形 + 文本 + 字号 + 文字水平内边距）。
            /// 块缘与文字都朝图片一侧对齐：图片左侧时靠右，镜像到右侧时靠左；
            /// PadX 给出该侧留白，与 Web --tt-rail-text-pad-x 同源。</summary>
            internal sealed class RailBlock
            {
                internal Rectangle Rect;
                internal string Text;
                internal int FontPx;
                internal int PadX;
            }

            /// <summary>弹夹框内容区（intro 面板底部；上方一条白线与正文分隔）。
            /// 图标与弹夹名同在第一行，子弹类型另起第二行。</summary>
            internal Rectangle MagazineRow;
            internal Rectangle MagazineIconRect;
            internal int MagazineDividerY;
            internal int MagazineTextLeftPx;
            internal int MagazineFontPx;
            internal int MagazineNameTopPx;
            internal int MagazineNameH;
            internal int MagazineAmmoTopPx;
            internal int MagazineAmmoH;
            internal string MagazineName;
            internal string MagazineIconName;
            internal string MagazineAmmo;

            /// <summary>intro 面板内全部文本行（split 时仅 intro；merge 时含 desc 拼接）。</summary>
            internal List<VisualLine> IntroLines = new List<VisualLine>();
            /// <summary>rich 主框独立标题与正文；标题居中加大，正文保持原对齐。</summary>
            internal List<VisualLine> IntroTitleLines = new List<VisualLine>();
            internal List<VisualLine> IntroBodyLines = new List<VisualLine>();
            internal int IntroTitleTopPx;
            /// <summary>desc 面板文本行（split）；pinned 时为 body 滚动单元整列。</summary>
            internal List<VisualLine> DescLines = new List<VisualLine>();

            /// <summary>intro/desc 的逻辑行视图：软换行续行并回所属逻辑行，
            /// 对应 web innerText 提取（innerText 不在软折处产生 \n，且丢弃空行）。
            /// parity-compare 的 text.intro/text.desc 应读这两列而非视觉行。</summary>
            internal List<VisualLine> IntroLogicalLines = new List<VisualLine>();
            internal List<VisualLine> DescLogicalLines = new List<VisualLine>();

            /// <summary>子注释框（role:"sub" 段，主面板下方竖排堆叠的独立框体，
            /// 黑底 80% + 1px 白描边）。空 = 无子框。plain/pinned 路径恒空
            /// （sub 段退化为 body 内联进描述栏）。</summary>
            internal List<SubBox> Subs = new List<SubBox>();

            /// <summary>单个子注释框（tip 相对坐标）。attachments 子框用 TitleLines +
            /// Rows（逐行图标+效果），普通子框用 Lines。</summary>
            internal sealed class SubBox
            {
                internal Rectangle Panel;
                internal List<VisualLine> Lines = new List<VisualLine>();
                internal int ContentLeftPx;
                internal int ContentTopPx;

                internal bool Attachments;
                internal List<VisualLine> TitleLines = new List<VisualLine>();
                internal int TitleTopPx;
                internal List<SubRow> Rows = new List<SubRow>();

                internal void Offset(int dx, int dy)
                {
                    Panel.Offset(dx, dy);
                    ContentLeftPx += dx;
                    ContentTopPx += dy;
                    TitleTopPx += dy;
                    foreach (SubRow row in Rows) row.Offset(dx, dy);
                }
            }

            /// <summary>结构子框内一行：名称 Lines 与附属 EffectLines 分行绘制。</summary>
            internal sealed class SubRow
            {
                internal Rectangle IconRect;
                internal string IconName;
                internal bool IconIsNpc;
                internal int RowTopPx;
                internal int RowBottomPx;
                internal int RowLeftPx;
                internal int RowWidthPx;
                internal int TextLeftPx;
                internal int TextTopPx;
                internal List<VisualLine> Lines = new List<VisualLine>();
                internal int EffectLeftPx;
                internal int EffectTopPx;
                internal List<VisualLine> EffectLines = new List<VisualLine>();

                internal void Offset(int dx, int dy)
                {
                    if (!IconRect.IsEmpty) IconRect.Offset(dx, dy);
                    TextLeftPx += dx;
                    EffectLeftPx += dx;
                    RowLeftPx += dx;
                    TextTopPx += dy;
                    EffectTopPx += dy;
                    RowTopPx += dy;
                    RowBottomPx += dy;
                }
            }

            /// <summary>intro 文本起点（tip 相对）。</summary>
            internal int IntroContentLeftPx;
            internal int IntroContentTopPx;
            /// <summary>desc 文本起点（tip 相对）。</summary>
            internal int DescContentLeftPx;
            internal int DescContentTopPx;

            /// <summary>非 pinned 基准行高（物理 px，展示/兜底值；逐行真实高见
            /// VisualLine.LineHeightF——含大字 run 的行按 CSS line box 抬高）。</summary>
            internal int LineHeightPx;
            internal int LineHeightIntroPx;
            internal int LineHeightDescPx;

            /// <summary>dense 检视状态条（tip 相对，位于所有面板上方）；无则 Empty。</summary>
            internal Rectangle InspStrip;
            /// <summary>条内 pending 进度槽宽（物理 px）；仅 pending 用。</summary>
            internal int InspMeterW;
            /// <summary>绘制态："pending" / "inspect" / null。</summary>
            internal string InspState;

            /// <summary>SolvePlacement 实际落侧（"left"/"right"/"top"/"bottom"）；
            /// 由 widget 在定位后回写，供 parity-compare 直接核对而非反推。</summary>
            internal string Side;

            /// <summary>整组已按 Side=="left" 横向镜像（Web rich[data-side="left"]
            /// 的 row-reverse）。widget 在 SolvePlacement 后按 Side 幂等回写。</summary>
            internal bool Mirrored;

            /// <summary>当前唯一阅读视口及其完整内容高度，使用物理像素。</summary>
            internal ReadingTarget Target;
            internal int ContentHeightPx;
            internal int MaxOffsetPx => Math.Max(0, ContentHeightPx - ScrollViewportRect.Height);
            internal bool DescScrollable => MaxOffsetPx > 0;
            internal int DescVisibleLines;
            internal int DescTotalLines;
            internal int MaxScrollLine => (int)Math.Ceiling(MaxOffsetPx / (double)Math.Max(1, LineHeightPx));
            /// <summary>滚动文本可视区（tip 相对）。</summary>
            internal Rectangle ScrollViewportRect;

            // pinned 专属（tip 相对坐标）
            internal Rectangle HeaderRect;
            internal Rectangle CloseRect;
            /// <summary>pinned body 裁剪可视区（tip 相对）。</summary>
            internal Rectangle BodyRect;
            /// <summary>pinned body 内 intro 面板（BodyRect 内容系，滚动前）。</summary>
            internal Rectangle PinnedIntroRect;
            /// <summary>pinned body 内 desc 面板（merge 时 Empty）。</summary>
            internal Rectangle PinnedDescRect;
            /// <summary>pinned body 内 icon 框（PinnedIntroRect 内容系）。</summary>
            internal Rectangle PinnedIconRect;
            /// <summary>pinned body 内 intro 文本起点（PinnedIntroRect 相对）。</summary>
            internal int PinnedTextX;
            internal int PinnedTextY;

            /// <summary>
            /// 整组横向镜像（Web .flash-tt-rich[data-side="left"] 的 row-reverse）：
            /// 主框换到右缘、侧栏（desc + sub 子框）转到左侧，插条跟到图片右侧。
            /// 只镜像面板/插条矩形；普通面板内文与图标保持左对齐，按"相对面板左缘的
            /// 偏移"重算。书签矩形镜像后自然从右缘对齐转为左缘对齐，绘制层再根据
            /// Mirrored 切换文字靠向。对自身取逆（镜像两次还原），widget 按 Side 幂等调用。
            /// pinned 有独立外壳几何，不走本方法。
            /// </summary>
            internal void MirrorHorizontally()
            {
                int w = TipSize.Width;
                bool hasIntro = !IntroPanel.IsEmpty;
                bool hasDesc = !DescPanel.IsEmpty;
                int introOff = hasIntro ? IntroContentLeftPx - IntroPanel.X : 0;
                int iconOff = hasIntro && !IconRect.IsEmpty ? IconRect.X - IntroPanel.X : 0;
                int magRowOff = hasIntro && !MagazineRow.IsEmpty
                    ? MagazineRow.X - IntroPanel.X : 0;
                int magIconOff = !MagazineRow.IsEmpty && !MagazineIconRect.IsEmpty
                    ? MagazineIconRect.X - MagazineRow.X : 0;
                int magTextOff = !MagazineRow.IsEmpty
                    ? MagazineTextLeftPx - MagazineRow.X : 0;

                foreach (RailBlock rb in RailBlocks) rb.Rect = MirrorX(rb.Rect, w);
                if (hasIntro) IntroPanel = MirrorX(IntroPanel, w);
                Rectangle sideBounds = SideBounds();
                int sideDx = w - sideBounds.Right - sideBounds.X;
                if (hasDesc)
                {
                    DescPanel.Offset(sideDx, 0);
                    DescContentLeftPx += sideDx;
                }
                foreach (SubBox sb in Subs) sb.Offset(sideDx, 0);

                if (hasIntro) IntroContentLeftPx = IntroPanel.X + introOff;
                if (hasIntro && !IconRect.IsEmpty)
                    IconRect = new Rectangle(IntroPanel.X + iconOff, IconRect.Y,
                        IconRect.Width, IconRect.Height);
                if (!ScrollViewportRect.IsEmpty)
                {
                    if (Target == ReadingTarget.Side) ScrollViewportRect.Offset(sideDx, 0);
                    else ScrollViewportRect = MirrorX(ScrollViewportRect, w);
                }
                if (hasIntro && !MagazineRow.IsEmpty)
                {
                    MagazineRow = new Rectangle(IntroPanel.X + magRowOff, MagazineRow.Y,
                        MagazineRow.Width, MagazineRow.Height);
                    if (!MagazineIconRect.IsEmpty)
                        MagazineIconRect = new Rectangle(MagazineRow.X + magIconOff,
                            MagazineIconRect.Y, MagazineIconRect.Width,
                            MagazineIconRect.Height);
                    MagazineTextLeftPx = MagazineRow.X + magTextOff;
                }
                Mirrored = !Mirrored;
            }

            internal Rectangle SideBounds()
            {
                Rectangle bounds = DescPanel;
                foreach (SubBox sub in Subs)
                    bounds = bounds.IsEmpty ? sub.Panel : Rectangle.Union(bounds, sub.Panel);
                return bounds;
            }

            private static Rectangle MirrorX(Rectangle r, int width)
            {
                return new Rectangle(width - (r.X + r.Width), r.Y, r.Width, r.Height);
            }
        }

        // ──────────── 顶层入口 ────────────

        /// <summary>
        /// <paramref name="measure"/>(text,font) → 物理 px 宽；
        /// <paramref name="lineHeightPx"/> = 非 pinned 基准行高（物理 px 浮点，
        /// widget 传 12×1.25×scale；行内更大 run 字号按 CSS line box 逐行抬高，
        /// 基准保持浮点避免逐行取整漂移）；
        /// <paramref name="scale"/> = 物理 px / tooltip 本地 CSS px
        /// （max(0.25×dpi, clientH/864) = overlayScale×dpi）；
        /// viewport 为宿主窗口 client 物理 px；
        /// <paramref name="dpiScale"/> = 宿主窗口 DPI 缩放（物理 px / 视口 CSS px，
        /// DeviceDpi/96f）——Web 的 innerWidth/innerHeight、vh/vw 单位与
        /// positionFloating 常量（inset/gap/pointer 半径）都在 CSS px 视口域求值：
        /// vwCss = viewportW/dpiScale、vhCss = viewportH/dpiScale。
        /// <paramref name="inspectionState"/> = input 侧检视投影
        /// （"idle"/"scan"/"pending"/"inspect"）；dense 且 pending/inspect 时
        /// 顶部出现状态条（web ensureInspectionStatus：_el 首子节点），tip 加高。
        /// </summary>
        internal static Plan ComputePlan(
            NativeTooltipDocument doc,
            Func<string, bool, int> measure,
            float lineHeightPx,
            float scale,
            int viewportWidthPx,
            int viewportHeightPx,
            string inspectionState = null,
            float dpiScale = 1f,
            LayoutOptions options = null,
            int clearWidthPx = 0)
        {
            return ComputePlan(doc,
                delegate (string t, RunFont f) { return measure(t, f.Bold); },
                lineHeightPx, scale, viewportWidthPx, viewportHeightPx,
                inspectionState, dpiScale, options, clearWidthPx);
        }

        internal static Plan ComputePlan(
            NativeTooltipDocument doc,
            Func<string, RunFont, int> measure,
            float lineHeightPx,
            float scale,
            int viewportWidthPx,
            int viewportHeightPx,
            string inspectionState = null,
            float dpiScale = 1f,
            LayoutOptions options = null,
            int clearWidthPx = 0)
        {
            options ??= LayoutOptions.Default;
            if (doc == null) throw new ArgumentNullException("doc");
            if (measure == null) throw new ArgumentNullException("measure");
            scale = Math.Max(0.25f, scale);
            lineHeightPx = Math.Max(1f, lineHeightPx);
            if (!(dpiScale > 0f) || float.IsNaN(dpiScale) || float.IsInfinity(dpiScale))
                dpiScale = 1f;
            // CSS px 视口（=Web innerWidth/innerHeight）：vh/vw 媒体规则与
            // 视口域常量都在此域求值，再按各自目标域换算物理 px。
            float vhCss = viewportHeightPx / dpiScale;

            Plan plan = new Plan();
            plan.Scale = scale;
            plan.LayoutWide = doc.LayoutType != "narrow";
            plan.Pinned = doc.Profile == NativeTooltipProfile.Pinned;
            plan.Title = doc.Title;
            plan.IconName = doc.Icon != null ? doc.Icon.Name : null;

            bool hasIcon = doc.Icon != null && !string.IsNullOrEmpty(doc.Icon.Name);
            List<NativeTooltipSection> introSecs = SectionsOf(doc, NativeTooltipSectionRole.Intro);
            List<NativeTooltipSection> descSecs = DescSections(doc);
            List<NativeTooltipSection> subSecs = SectionsOf(doc, NativeTooltipSectionRole.Sub);
            bool hasIntro = doc.TitleRuns.Count > 0 || introSecs.Count > 0;
            bool hasDesc = descSecs.Count > 0;

            // ── plain 文本提示：无 icon 且 profile=simple → #panel-tooltip 原生样式
            //    （迁移前 Web 里 setText 短提示：灰渐变框 + pad 10/14 + maxw 480 + lh 1.5）
            bool isPlain = !hasIcon && !plan.Pinned
                && doc.Profile == NativeTooltipProfile.Simple;
            // plain/pinned 不支持子框堆叠：sub 段按 body 同文档序内联进描述栏，不丢内容
            // （rich float 路径保留 subSecs，装配完主面板后堆叠）
            if ((isPlain || plan.Pinned) && subSecs.Count > 0)
            {
                descSecs.AddRange(subSecs);
                subSecs.Clear();
            }
            if (isPlain)
            {
                ComputePlain(doc, measure, scale, viewportWidthPx, viewportHeightPx,
                    dpiScale, plan, introSecs, descSecs);
                return plan;
            }

            if (plan.Pinned)
            {
                ComputePinned(doc, measure, scale, viewportWidthPx, viewportHeightPx,
                    dpiScale, plan, hasIcon, hasDesc, introSecs, descSecs);
                return plan;
            }

            // ── rich 浮动面板（dense / 带 icon 的 simple）──
            float lh = lineHeightPx;
            int lhInt = Math.Max(1, (int)Math.Round(lh));
            plan.LineHeightPx = lhInt;
            plan.LineHeightIntroPx = lhInt;
            plan.LineHeightDescPx = lhInt;

            TextScore descScore = ScoreSections(descSecs);
            TextScore introScore = ScoreSections(introSecs);
            if (doc.TitleRuns.Count > 0)
            {
                TextScore ts = ScoreText(doc.Title);
                introScore.Total += ts.Total;
                if (ts.MaxLine > introScore.MaxLine) introScore.MaxLine = ts.MaxLine;
            }
            // desc 为空时强制 merge（buildItemRichHtml: !desc → doSplit=false）
            bool hasUpgrades = false;
            for (int i = 0; i < descSecs.Count; i++)
                if (descSecs[i].Kind == "upgrades") { hasUpgrades = true; break; }
            plan.Split = hasDesc && (hasUpgrades || ShouldSplit(descScore, introScore));

            bool wide = plan.LayoutWide;
            int pad = Px(PanelPadBase, scale);
            int introW = Px(wide ? BaseNum : 120, scale);
            bool compactIcon = options.CompactIntro && wide && vhCss < 660;
            int introMinH = Px(compactIcon ? 164 : wide ? IntroMinHWideBase : IntroMinHNarrowBase, scale);
            int iconBox = Px(compactIcon ? 144 : wide ? IconBoxWideBase : IconBoxNarrowBase, scale);
            int iconGap = Px(compactIcon ? 10 : wide ? IconTextGapWideBase : IconTextGapNarrowBase, scale);
            int sbW = Px(ScrollbarWBase, scale);

            // 定位/降级判定域 = 视口 CSS px（Web innerWidth/innerHeight + transform 后
            // getBoundingClientRect 域）：inset(8)/stacked margin(32) 是 CSS px 常量，
            // 与物理 client 之间差 dpi 因子；元素自身尺寸仍走 scale。
            int inset = (int)Math.Round(ViewportInsetBase * dpiScale);
            int availableWidth = Math.Max(1, viewportWidthPx - inset * 2);
            int heightBudget = Math.Max(1, viewportHeightPx - inset * 2
                - (doc.Profile == NativeTooltipProfile.Dense
                    ? Px(InspMinHBase, scale) + Px(InspMarginBase, scale) : 0));
            bool introPanelExists = hasIcon || hasIntro || (!plan.Split && hasDesc);
            int railWidth = 0;
            if (introPanelExists && doc.Rail != null)
                foreach (var label in doc.Rail.Texts)
                    railWidth = Math.Max(railWidth, RailBlockWidth(label, scale, measure));
            int railAttachX = (hasIcon ? (introW - iconBox) / 2 : pad) + Px(1, scale);
            int railShift = Math.Max(0, railWidth - railAttachX);
            int mainWidthPx = (introPanelExists ? introW : 0) + railShift;
            int sideAvail = availableWidth - mainWidthPx;
            bool useClearWidth = clearWidthPx > 0
                && (options.WholeSideWidth || options.BalanceWidth || options.TwoColumnSide);
            int minReadableSide = Px(200, scale);
            int effectiveSideAvail = useClearWidth
                ? Math.Min(sideAvail, Math.Max(minReadableSide, clearWidthPx - mainWidthPx))
                : sideAvail;
            int subGap = Px(options.CompactRows ? 4 : SubGapBase, scale);
            int cut = 0;
            SideLayout sideLayout = null;
            if (plan.Split || subSecs.Count > 0)
            {
                int requiredAcqW = 0;
                foreach (var sec in subSecs)
                    if (sec.Kind == "acquisition" && sec.Rows.Count > 0)
                        requiredAcqW = Math.Max(requiredAcqW, RequiredAcquisitionWidth(sec, pad, scale, measure) + sbW);

                var descRuns = plan.Split ? BuildColumnRuns(descSecs, false) : null;
                SideLayout MeasureSide(int width) => new SideLayout(width, subGap,
                    descRuns, descSecs, subSecs, measure, lh, scale, pad, sbW, options.CompactRows);
                TextScore sideScore = options.WholeSideWidth
                    ? ScoreSide(plan.Split ? descSecs : null, subSecs, options.CompactRows)
                    : plan.Split ? descScore : ScoreSections(subSecs);
                int minW = Px(DescMinWBase, scale);
                int widthBase = Math.Max(DescMinWBase, EstimateMainWidth(sideScore, 150, DescMaxWBase));
                if (options.WholeSideWidth && (subSecs.Count > 0 || sideScore.Total >= 120))
                    widthBase = Math.Max(200, widthBase);
                int expansionBase = options.BalanceWidth
                    ? Math.Max(DescDefaultWBase, (int)Math.Min(DescMaxWBase, sideScore.MaxLine * 6 + 28))
                    : DescMaxWBase;
                int normalCap = Px(DescMaxWBase, scale);
                int width = Math.Max(requiredAcqW, Px(Math.Min(widthBase, expansionBase), scale));
                if (!options.WholeSideWidth && plan.Split && width < normalCap)
                {
                    int probeWidth = Math.Max(1, width - pad * 2 - sbW);
                    int count = WrapRuns(descRuns, probeWidth, measure, lh).Count
                        + BuildUpgradeLines(descSecs, probeWidth, scale, measure, lh,
                            descRuns.Count > 0, options.CompactRows).Count;
                    width = Math.Max(width,
                        Px(EstimateMainWidth(sideScore, 150, expansionBase, count), scale));
                }
                plan.Stacked = sideAvail < (options.BalanceWidth || options.WholeSideWidth ? minW : width);
                int stackedCap = Math.Max(1, availableWidth - sbW);
                int sideCap = plan.Stacked ? stackedCap : Math.Max(minW, effectiveSideAvail);
                int effectiveMax = Math.Min(sideCap,
                    Px(options.BalanceWidth ? DescBalanceMaxWBase : DescMaxWBase, scale));
                int initW = options.BalanceWidth || options.WholeSideWidth
                    ? Math.Min(effectiveMax, width) : Math.Min(sideCap, width);
                sideLayout = MeasureSide(initW);
                if (options.WholeSideWidth && Math.Round(sideLayout.Height / lh, MidpointRounding.AwayFromZero)
                    > DescExpandLineThreshold)
                {
                    int expandedW = Math.Min(effectiveMax, Math.Max(initW, Px(expansionBase, scale)));
                    if (expandedW > initW) sideLayout = MeasureSide(expandedW);
                }

                if (options.BalanceWidth)
                    sideLayout = BalanceSideWidth(sideLayout, MeasureSide, effectiveMax,
                        heightBudget, requiredAcqW, minW, scale, pad * 2 + sbW, measure);

                int panelCount = sideLayout.Heights.Count;
                if (options.TwoColumnSide && !plan.Stacked && panelCount >= 2
                    && sideLayout.Height > heightBudget)
                {
                    int maxTooltipW = Math.Min(availableWidth,
                        Math.Max(Px(860, scale), (int)Math.Round(availableWidth * 0.82, MidpointRounding.AwayFromZero)));
                    if (useClearWidth) maxTooltipW = Math.Min(maxTooltipW, clearWidthPx);
                    int twoColBudget = maxTooltipW - mainWidthPx;
                    if (twoColBudget >= Px(540, scale))
                    {
                        int colW = Math.Min(Px(380, scale), (twoColBudget - subGap) / 2);
                        SideLayout twoColumns = MeasureSide(colW);
                        int bestCut = BestSideCut(twoColumns, subGap, out int bestHeight);
                        if (bestHeight <= heightBudget || bestHeight < sideLayout.Height - Px(48, scale))
                        {
                            cut = bestCut;
                            sideLayout = twoColumns;
                            plan.SideColumns = 2;
                        }
                    }
                }
            }
            else
            {
                plan.Stacked = (introPanelExists ? introW : 0) + railShift > availableWidth;
            }

            int columnCap = plan.Stacked ? Math.Max(1, availableWidth - sbW) : availableWidth;
            introW = Math.Min(introW, columnCap);
            iconBox = Math.Min(iconBox, Math.Max(1, introW - pad * 2));
            // rich 浮动主框标题独立排版；正文与 merge desc 保持原有拼装规则。
            List<NativeTooltipRun> introRuns = IntroColumnRuns(doc, introSecs, false);
            if (!plan.Split && hasDesc) AppendMergedDesc(introRuns, descSecs);


            List<VisualLine> introLines = new List<VisualLine>();
            int introTextX = pad, introTextY = pad, introTextW = 0, introPanelH = 0;
            if (introPanelExists)
            {
                // icon→text 间距仅在文本元素存在时产生（flex gap 是两子项之间）
                bool introHasText = introRuns.Count > 0 || doc.TitleRuns.Count > 0;
                introTextY = pad + (hasIcon
                    ? iconBox + (introHasText ? iconGap : 0) : 0);
                introTextW = introW - pad * 2;
                if (doc.TitleRuns.Count > 0)
                {
                    List<NativeTooltipRun> titleRuns = new List<NativeTooltipRun>();
                    foreach (NativeTooltipRun run in doc.TitleRuns)
                    {
                        titleRuns.Add(new NativeTooltipRun(run.Text, run.Color, true,
                            run.Italic, run.Underline, FloatingTitleFontBase, run.FontFace));
                    }
                    plan.IntroTitleTopPx = introTextY;
                    plan.IntroTitleLines = WrapRuns(titleRuns, introTextW, measure, lh);
                    introTextY += SumHeight(plan.IntroTitleLines, lh);
                }
                introLines = BuildIntroLines(introRuns, introTextW, scale, measure, lh,
                    options.CompactIntro && wide && plan.Split);
                plan.IntroBodyLines = introLines;
                plan.IntroLines.AddRange(plan.IntroTitleLines);
                plan.IntroLines.AddRange(introLines);
                int textH = SumHeight(introLines, lh);
                introPanelH = Math.Max(plan.Stacked ? 0 : introMinH, introTextY + textH + pad);
            }

            // ── 弹夹独立行：接在 intro 正文底部，白线分隔，行高=小图标高 ──
            if (introPanelExists)
            {
                int magExtra = ApplyMagazineRow(plan, doc, scale, pad, introTextX,
                    introTextY, introTextW, SumHeight(introLines, lh));
                if (magExtra > 0)
                    introPanelH = Math.Max(introPanelH,
                        introTextY + SumHeight(introLines, lh) + magExtra + pad);
            }

            // ── 组装 ──
            plan.IntroLogicalLines = MergeLogicalLines(plan.IntroLines);
            plan.IntroContentLeftPx = introPanelExists ? introTextX : 0;
            plan.IntroContentTopPx = introTextY;

            if (introPanelExists)
            {
                plan.IntroPanel = new Rectangle(0, 0, introW, introPanelH);
                if (hasIcon)
                    plan.IconRect = new Rectangle((introW - iconBox) / 2, pad, iconBox, iconBox);
            }
            int sideWidth = sideLayout == null ? 0
                : cut > 0 ? sideLayout.Width * 2 + subGap : sideLayout.Width;
            int mainW = plan.IntroPanel.Width;
            int tipW = plan.Stacked ? Math.Max(mainW, sideWidth) : mainW + sideWidth;
            plan.TipSize = new Size(Math.Max(1, tipW), Math.Max(1, introPanelH));

            ApplyRail(plan, doc, scale, measure);
            if (sideLayout != null)
            {
                int x = plan.Stacked ? 0 : plan.IntroPanel.Right;
                int y = plan.Stacked ? (introPanelExists ? plan.TipSize.Height : 0) : 0;
                PlaceSideColumn(plan, sideLayout, x, y, pad, subGap, cut);
            }

            Rectangle side = plan.SideBounds();
            if (!side.IsEmpty)
                plan.TipSize = new Size(plan.TipSize.Width, Math.Max(plan.TipSize.Height, side.Bottom));
            bool whole = plan.Stacked || plan.IntroPanel.Height > heightBudget || side.IsEmpty;
            plan.Target = whole ? ReadingTarget.WholeRich : ReadingTarget.Side;
            var content = whole ? new Rectangle(Point.Empty, plan.TipSize) : side;
            plan.ContentHeightPx = content.Height;
            int limit = heightBudget;
            // A single side panel retains the established reading height; grouped panels share the window budget.
            if (!whole && !options.UnclampSingleSideHeight && subSecs.Count + (plan.Split ? 1 : 0) == 1)
                limit = Math.Min(limit, Math.Max(1, Px(Math.Min(DescMaxHBase, vhCss * DescMaxHViewportFrac), scale)));
            content.Height = Math.Min(content.Height, limit);
            plan.ScrollViewportRect = content;
            plan.TipSize = new Size(plan.TipSize.Width,
                whole ? content.Height : Math.Max(plan.IntroPanel.Height, content.Bottom));
            plan.DescVisibleLines = plan.Split
                ? VisibleLineCount(plan.DescLines, Math.Max(0, content.Bottom - plan.DescContentTopPx - pad))
                : plan.IntroLines.Count;

            // ── dense 检视状态条（status 为 _el 首子节点，位于全部面板上方）──
            if (doc.Profile == NativeTooltipProfile.Dense)
                ApplyInspectionStrip(plan, measure, scale, inspectionState);
            return plan;
        }

        private static TextScore ScoreSide(List<NativeTooltipSection> desc,
            List<NativeTooltipSection> subs, bool compactRows)
        {
            TextScore score = new TextScore();
            void Add(TextScore part)
            {
                score.Total += part.Total;
                score.MaxLine = Math.Max(score.MaxLine, part.MaxLine);
                score.LineCount += part.LineCount;
            }
            void AddSection(NativeTooltipSection section)
            {
                if (!section.IsAttachments)
                {
                    Add(ScoreText(section.PlainText));
                    return;
                }
                if (!string.IsNullOrEmpty(section.Title)) Add(ScoreText(section.Title));
                foreach (var row in section.Rows)
                {
                    string effects = RunsText(row.Runs);
                    string name = row.Name ?? "";
                    if (name.Length > 0 && effects.Length > 0
                        && (section.Kind == "modinfo" || section.Kind == "attachments"))
                    {
                        string separator = compactRows && section.Kind == "attachments" && !HasHardBreak(row.Runs)
                            ? "：" : "\n";
                        Add(ScoreText(name + separator + effects));
                    }
                    else
                    {
                        if (section.Kind == "upgrades" && row.Depth != 1 && effects.Length > 0) name = "";
                        Add(ScoreText(name + effects));
                    }
                }
            }

            if (desc != null)
                foreach (var section in desc) AddSection(section);
            foreach (var section in subs) AddSection(section);
            score.LineCount += 2 * Math.Max(0, subs.Count + (desc == null ? 0 : 1) - 1);
            return score;
        }

        private static string RunsText(IList<NativeTooltipRun> runs)
        {
            var text = new StringBuilder();
            foreach (var run in runs) text.Append(run.Text);
            return text.ToString();
        }

        private static bool HasHardBreak(IList<NativeTooltipRun> runs)
        {
            foreach (var run in runs)
                if (run?.Text?.Contains('\n') == true || run?.Text?.Contains('\r') == true) return true;
            return false;
        }

        /// <summary>一次宽度探测的自然布局，最终选中的探测直接用于绘制。</summary>
        private sealed class SideLayout
        {
            internal readonly int Width;
            internal readonly int Height;
            internal readonly List<int> Heights = new List<int>();
            internal readonly List<VisualLine> Desc;
            internal readonly List<Plan.SubBox> Subs = new List<Plan.SubBox>();

            internal SideLayout(int width, int gap, List<NativeTooltipRun> descRuns,
                List<NativeTooltipSection> descSecs, List<NativeTooltipSection> subSecs,
                Func<string, RunFont, int> measure, float lh, float scale, int pad, int gutter,
                bool compactRows)
            {
                Width = width;
                if (descRuns != null)
                {
                    int textW = Math.Max(1, width - pad * 2 - gutter);
                    Desc = WrapRuns(descRuns, textW, measure, lh);
                    Desc.AddRange(BuildUpgradeLines(descSecs, textW, scale, measure, lh,
                        Desc.Count > 0, compactRows));
                    Heights.Add(SumHeight(Desc, lh) + pad * 2);
                }
                else Desc = new List<VisualLine>();
                foreach (var sec in subSecs)
                {
                    var box = sec.IsAttachments
                        ? BuildAttachmentsBox(sec, width, pad, scale, measure, lh, gutter, compactRows)
                        : BuildTextSubBox(sec, 0, 0, width, pad, scale, measure, lh, gutter);
                    Subs.Add(box);
                    Heights.Add(box.Panel.Height);
                }
                Height = Math.Max(0, Heights.Count - 1) * gap;
                foreach (int h in Heights) Height += h;
            }

            internal int MaxLineWidth(int pad, Func<string, RunFont, int> measure)
            {
                float max = 0;
                void Include(List<VisualLine> lines, int left)
                {
                    foreach (VisualLine line in lines)
                    {
                        max = Math.Max(max, left + RenderedLineWidth(line, measure));
                        if (line.RightHalf != null)
                            max = Math.Max(max, left + line.RightHalfOffsetPx
                                + RenderedLineWidth(line.RightHalf, measure));
                    }
                }
                Include(Desc, 0);
                foreach (var sub in Subs)
                {
                    Include(sub.Lines, 0);
                    Include(sub.TitleLines, 0);
                    foreach (var row in sub.Rows)
                    {
                        if (!row.IconRect.IsEmpty) max = Math.Max(max, row.IconRect.Right - pad);
                        Include(row.Lines, row.TextLeftPx - pad);
                        Include(row.EffectLines, row.EffectLeftPx - pad);
                    }
                }
                return (int)Math.Ceiling(max);
            }
        }

        private static float RenderedLineWidth(VisualLine line, Func<string, RunFont, int> measure)
        {
            float width = line.TextOffsetPx + NaturalLineWidth(line, measure);
            int markWidth = Math.Max(1, (int)Math.Round(line.Height(1))) + 2;
            foreach (var slice in line.Slices)
            {
                if (IsALegionSlice(slice)) width += markWidth;
                if (IsWarlordSlice(slice)) width += markWidth;
                if (IsNoahSlice(slice)) width += markWidth;
            }
            return Math.Max(line.IconRect.Right, width);
        }

        private static readonly System.Text.RegularExpressions.Regex FactionNamePattern =
            new System.Text.RegularExpressions.Regex(
                @"(A兵团|Andy|安迪烙|格格巫|丽丽丝|小F|\b(?:Boy|King|Pig|Blue|The\s+Girl|Shop\s*Girl)\b)|(军阀|军队|将军|莱昂利亚|自由革命军|\b(?:General|Gazer)\b)|(诺亚|Noah)",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase
                | System.Text.RegularExpressions.RegexOptions.CultureInvariant);

        private static List<NativeTooltipRun> ExpandFactionRuns(IList<NativeTooltipRun> source)
        {
            var output = new List<NativeTooltipRun>();
            if (source == null) return output;
            foreach (NativeTooltipRun run in source)
            {
                if (run == null || string.IsNullOrEmpty(run.Text))
                {
                    output.Add(run);
                    continue;
                }
                var matches = FactionNamePattern.Matches(run.Text);
                if (matches.Count == 0)
                {
                    output.Add(run);
                    continue;
                }
                int from = 0;
                foreach (System.Text.RegularExpressions.Match match in matches)
                {
                    if (match.Index > from)
                        output.Add(CopyRun(run, run.Text.Substring(from, match.Index - from),
                            NativeTooltipFaction.None));
                    NativeTooltipFaction faction = match.Groups[1].Success
                        ? NativeTooltipFaction.ALegion
                        : match.Groups[2].Success ? NativeTooltipFaction.Warlord : NativeTooltipFaction.Noah;
                    output.Add(CopyRun(run, match.Value, faction));
                    from = match.Index + match.Length;
                }
                if (from < run.Text.Length)
                    output.Add(CopyRun(run, run.Text.Substring(from), NativeTooltipFaction.None));
            }
            return output;
        }

        private static NativeTooltipRun CopyRun(NativeTooltipRun source, string text,
            NativeTooltipFaction faction)
        {
            var run = new NativeTooltipRun(text, source.Color, source.Bold,
                source.Italic, source.Underline, source.FontSize, source.FontFace);
            run.Faction = faction;
            if (faction == NativeTooltipFaction.None) return run;
            run.Color = faction == NativeTooltipFaction.ALegion ? Color.FromArgb(255, 0, 0)
                : faction == NativeTooltipFaction.Warlord ? Color.FromArgb(255, 255, 224)
                : Color.FromArgb(126, 182, 255);
            run.Underline = true;
            return run;
        }

        internal static bool IsALegionSlice(VisualLine.Slice slice)
        {
            return slice.Faction == NativeTooltipFaction.ALegion;
        }

        internal static bool IsWarlordSlice(VisualLine.Slice slice)
        {
            return slice.Faction == NativeTooltipFaction.Warlord;
        }

        internal static bool IsNoahSlice(VisualLine.Slice slice)
        {
            return slice.Faction == NativeTooltipFaction.Noah;
        }


        private static SideLayout BalanceSideWidth(SideLayout initial, Func<int, SideLayout> probe,
            int effectiveMax, int heightBudget, int requiredAcqW, int minW, float scale,
            int chromeW, Func<string, RunFont, int> measure)
        {
            int tolerance = Px(16, scale);
            if (initial.Height > heightBudget)
            {
                if (initial.Width >= effectiveMax) return initial;
                SideLayout best = probe(effectiveMax);
                if (best.Height > heightBudget) return best;
                int low = initial.Width;
                for (int i = 0; i < 4 && best.Width - low > tolerance; i++)
                {
                    SideLayout candidate = probe(low + (best.Width - low) / 2);
                    if (candidate.Height <= heightBudget) best = candidate;
                    else low = candidate.Width;
                }
                return best;
            }

            int fit = Math.Max(Math.Max(minW, requiredAcqW),
                initial.MaxLineWidth(Px(PanelPadBase, scale), measure) + chromeW);
            if (initial.Width - fit < tolerance) return initial;
            SideLayout shrink = probe(fit);
            return shrink.Height <= initial.Height ? shrink : initial;
        }

        private static int BestSideCut(SideLayout side, int gap, out int bestHeight)
        {
            int bestCut = 1, bestLeft = 0, bestRight = 0, left = -gap;
            bestHeight = int.MaxValue;
            for (int cut = 1; cut < side.Heights.Count; cut++)
            {
                left += side.Heights[cut - 1] + gap;
                int right = side.Height - left - gap;
                int height = Math.Max(left, right);
                if (height < bestHeight || (height == bestHeight && left >= right
                    && (bestLeft < bestRight || left - right < bestLeft - bestRight)))
                {
                    bestCut = cut;
                    bestHeight = height;
                    bestLeft = left;
                    bestRight = right;
                }
            }
            return bestCut;
        }

        private static void PlaceSideColumn(Plan plan, SideLayout side, int x, int y,
            int pad, int gap, int cut)
        {
            int startY = y;
            int panel = 0;
            if (plan.Split)
            {
                plan.DescPanel = new Rectangle(x, y, side.Width, side.Heights[0]);
                plan.DescLines = side.Desc;
                plan.DescLogicalLines = MergeLogicalLines(side.Desc);
                plan.DescTotalLines = side.Desc.Count;
                plan.DescContentLeftPx = x + pad;
                plan.DescContentTopPx = y + pad;
                y += side.Heights[0] + gap;
                panel++;
            }
            foreach (var sub in side.Subs)
            {
                if (cut > 0 && panel == cut)
                {
                    x += side.Width + gap;
                    y = startY;
                }
                sub.Offset(x, y);
                plan.Subs.Add(sub);
                y += sub.Panel.Height + gap;
                panel++;
            }
        }

        private static int RequiredAcquisitionWidth(NativeTooltipSection sec,
            int pad, float scale, Func<string, RunFont, int> measure)
        {
            int required = 0;
            int iconPx = Px(AttachIconBase, scale);
            int iconGap = Px(AttachIconGapBase, scale);
            for (int i = 0; i < sec.Rows.Count; i++)
            {
                NativeTooltipAttachmentRow row = sec.Rows[i];
                if (string.IsNullOrEmpty(row.Name)) continue;
                int depth = row.Depth == 1 ? 1 : 0;
                int rowIndent = depth == 0 ? 0 : Px(8, scale);
                bool showIcon = depth == 1 || !string.IsNullOrEmpty(row.IconName);
                int textW = measure(row.Name, new RunFont { Bold = true });
                for (int r = 0; r < row.Runs.Count; r++)
                    textW += measure(row.Runs[r].Text, RunFont.Of(row.Runs[r]));
                required = Math.Max(required, pad * 2 + rowIndent
                    + (showIcon ? iconPx + iconGap : 0) + textW);
            }
            return required;
        }

        /// <summary>普通子注释框：按最终宽度折行，完整高度用于外层视口。</summary>
        private static Plan.SubBox BuildTextSubBox(NativeTooltipSection sec,
            int x, int y, int w, int pad, float scale,
            Func<string, RunFont, int> measure, float lh, int gutter)
        {
            List<NativeTooltipRun> runs = BuildColumnRuns(
                new List<NativeTooltipSection> { sec });
            List<VisualLine> lines = WrapRuns(runs,
                Math.Max(1, w - pad * 2 - gutter), measure, lh);
            int h = Math.Max(1, SumHeight(lines, lh) + pad * 2);
            Plan.SubBox box = new Plan.SubBox();
            box.Panel = new Rectangle(x, y, w, h);
            box.Lines = lines;
            box.ContentLeftPx = x + pad;
            box.ContentTopPx = y + pad;
            return box;
        }

        private static Plan.SubBox BuildAttachmentsBox(NativeTooltipSection sec,
            int w, int pad, float scale, Func<string, RunFont, int> measure, float lh,
            int gutter, bool compactRows)
        {
            int contentW = Math.Max(1, w - pad * 2 - gutter);
            int iconPx = Px(AttachIconBase, scale);
            int iconGap = Px(AttachIconGapBase, scale);
            int titleGap = Px(compactRows ? 1 : AttachTitleGapBase, scale);
            bool acquisition = sec.Kind == "acquisition";
            bool modInfo = sec.Kind == "modinfo";
            int rowGap = Px(compactRows ? (modInfo ? 1 : 2) : AttachRowGapBase, scale);
            int effectGap = Px(1, scale);
            int childIndent = Px(8, scale);
            int columnGap = Px(8, scale);
            int halfW = (contentW - childIndent - columnGap) / 2;
            bool canPair = compactRows && (acquisition || modInfo) && contentW >= Px(300, scale);

            Plan.SubBox box = new Plan.SubBox
            {
                Attachments = true,
                ContentLeftPx = pad,
                ContentTopPx = pad
            };
            int cursor = pad;
            if (!string.IsNullOrEmpty(sec.Title))
            {
                var titleRuns = new[] { new NativeTooltipRun(sec.Title, null, true) };
                box.TitleLines = WrapRuns(titleRuns, contentW, measure, lh);
                box.TitleTopPx = cursor;
                cursor += SumHeight(box.TitleLines, lh) + titleGap;
            }

            bool acquisitionNoWrap = acquisition && w - gutter >= RequiredAcquisitionWidth(sec, pad, scale, measure);
            Plan.SubRow previousShort = null;
            int previousShortIndent = -1;
            for (int i = 0; i < sec.Rows.Count; i++)
            {
                NativeTooltipAttachmentRow row = sec.Rows[i];
                bool hasName = !string.IsNullOrEmpty(row.Name);
                if (!hasName && (!(modInfo || acquisition) || row.Runs.Count == 0))
                {
                    previousShort = null;
                    previousShortIndent = -1;
                    continue;
                }
                bool child = row.Depth == 1;
                int rowIndent = child ? childIndent : 0;
                int effectIndent = modInfo ? 0 : Px(12, scale);
                bool showIcon = (!acquisition && !modInfo)
                    || (acquisition && (child || !string.IsNullOrEmpty(row.IconName)));
                int iconW = showIcon ? iconPx + iconGap : 0;
                int nameTextW = Math.Max(1, contentW - rowIndent - iconW);
                bool inlineEffect = compactRows && sec.Kind == "attachments" && hasName
                    && row.Runs.Count > 0 && !HasHardBreak(row.Runs);
                bool singleFlow = acquisition || inlineEffect;

                var nameRuns = new List<NativeTooltipRun>();
                if (hasName)
                    nameRuns.Add(new NativeTooltipRun(inlineEffect ? row.Name + "：" : row.Name, null, true));
                if (singleFlow) nameRuns.AddRange(row.Runs);
                nameRuns = ExpandFactionRuns(nameRuns);
                var nameLines = WrapRuns(nameRuns,
                    acquisitionNoWrap ? int.MaxValue / 4 : nameTextW, measure, lh);
                var effectLines = singleFlow ? new List<VisualLine>()
                    : WrapRuns(ExpandFactionRuns(row.Runs), Math.Max(1, nameTextW - effectIndent), measure, lh);
                int nameH = SumHeight(nameLines, lh);
                int effectH = SumHeight(effectLines, lh);
                int blockGap = nameH > 0 && effectH > 0 ? effectGap : 0;
                int textH = nameH + blockGap + effectH;
                int rowH = Math.Max(!modInfo ? iconPx : 0, textH);

                int left = pad + rowIndent;
                int top = Math.Max(0, (rowH - textH) / 2);
                var subRow = new Plan.SubRow
                {
                    IconName = row.IconName,
                    IconIsNpc = showIcon && acquisition && !string.IsNullOrEmpty(row.IconName),
                    IconRect = showIcon ? new Rectangle(left, (rowH - iconPx) / 2, iconPx, iconPx) : Rectangle.Empty,
                    RowBottomPx = rowH,
                    RowLeftPx = left,
                    RowWidthPx = contentW - rowIndent,
                    TextLeftPx = left + iconW,
                    TextTopPx = top,
                    Lines = nameLines,
                    EffectLeftPx = left + iconW + effectIndent,
                    EffectTopPx = top + nameH + blockGap,
                    EffectLines = effectLines
                };
                var pairLines = modInfo ? effectLines : nameLines;
                int currentIndent = modInfo ? LeadingIndentCount(RowPlainText(row.Runs)) : 0;
                bool modInfoBlocked = modInfo && IsModInfoHeadingOrParent(sec.Rows, i);
                bool shortChild = canPair && child && (!modInfo || !hasName) && !modInfoBlocked
                    && pairLines.Count == 1 && !HasHardBreak(modInfo ? row.Runs : nameRuns)
                    && RenderedLineWidth(pairLines[0], measure) + iconW <= halfW;
                if (shortChild && previousShort != null && (!modInfo || currentIndent == previousShortIndent))
                {
                    previousShort.RowWidthPx = halfW;
                    subRow.RowWidthPx = halfW;
                    subRow.Offset(halfW + columnGap, previousShort.RowTopPx);
                    cursor = Math.Max(previousShort.RowBottomPx, subRow.RowBottomPx) + rowGap;
                    previousShort = null;
                    previousShortIndent = -1;
                }
                else
                {
                    subRow.Offset(0, cursor);
                    cursor = subRow.RowBottomPx + rowGap;
                    previousShort = shortChild ? subRow : null;
                    previousShortIndent = shortChild ? currentIndent : -1;
                }
                box.Rows.Add(subRow);
            }
            if (box.Rows.Count > 0) cursor -= rowGap;

            box.Panel = new Rectangle(0, 0, w, Math.Max(1, cursor + pad));
            return box;
        }

        private static string RowPlainText(IList<NativeTooltipRun> runs)
        {
            if (runs == null || runs.Count == 0) return string.Empty;
            var sb = new StringBuilder();
            for (int i = 0; i < runs.Count; i++)
                if (runs[i] != null && !string.IsNullOrEmpty(runs[i].Text))
                    sb.Append(runs[i].Text);
            return sb.ToString();
        }

        private static int LeadingIndentCount(string text)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int count = 0;
            for (int i = 0; i < text.Length; i++)
            {
                char ch = text[i];
                if (ch == ' ' || ch == '\u00a0') count++;
                else if (ch == '\u3000') count += 2;
                else break;
            }
            return count;
        }

        private static bool IsModInfoHeadingOrParent(IList<NativeTooltipAttachmentRow> rows, int index)
        {
            if (rows == null || index < 0 || index >= rows.Count) return true;
            string raw = RowPlainText(rows[index].Runs);
            string trimmed = raw.Trim();
            if (string.IsNullOrEmpty(trimmed)) return true;
            if (trimmed[0] == '【') return true;
            char last = trimmed[trimmed.Length - 1];
            if (last == '：' || last == ':') return true;
            int indent = LeadingIndentCount(raw);
            if (index + 1 < rows.Count)
            {
                var next = rows[index + 1];
                if (next != null && next.Depth == 1 && string.IsNullOrEmpty(next.Name))
                {
                    if (LeadingIndentCount(RowPlainText(next.Runs)) > indent) return true;
                }
            }
            return false;
        }

        /// <summary>
        /// 弹夹框（document.magazine）：接在 intro 正文最后一行之下，上边缘一条白线
        /// 与正文分隔。第一行 = 弹夹图标（正方形，边长 MagIconBase，与弹夹名垂直居中）
        /// + 弹夹名；第二行 = 子弹类型（可选，与弹夹名同左缘）。返回附加高度
        /// （0 = 无弹夹部件）。
        /// </summary>
        private static int ApplyMagazineRow(Plan plan, NativeTooltipDocument doc,
            float scale, int pad, int textLeft, int textTop, int textWidth, int textHeight)
        {
            NativeTooltipMagazine mag = doc.Magazine;
            if (mag == null || string.IsNullOrEmpty(mag.Name)) return 0;

            int fontPx = Px(FontPxBase, scale);
            int fontLine = Px(FontPxBase * 1.25f, scale);
            int iconPx = Px(MagIconBase, scale);
            int iconGap = Px(MagIconTextGapBase, scale);
            int gap = Px(MagDividerGapBase, scale);
            int lineGap = Px(MagLineGapBase, scale);

            bool hasAmmo = !string.IsNullOrEmpty(mag.Ammo);
            int nameLineH = Math.Max(fontLine, iconPx);
            int ammoBlockH = hasAmmo ? lineGap + fontLine : 0;

            int dividerY = textTop + textHeight + gap;
            int rowTop = dividerY + gap;
            int rowH = nameLineH + ammoBlockH;

            plan.MagazineName = mag.Name;
            plan.MagazineIconName = mag.IconName;
            plan.MagazineAmmo = hasAmmo ? mag.Ammo : null;
            plan.MagazineFontPx = fontPx;
            plan.MagazineDividerY = dividerY;
            plan.MagazineRow = new Rectangle(textLeft, rowTop, textWidth, rowH);
            plan.MagazineIconRect = new Rectangle(textLeft,
                rowTop + (nameLineH - iconPx) / 2, iconPx, iconPx);
            plan.MagazineTextLeftPx = textLeft + iconPx + iconGap;
            plan.MagazineNameTopPx = rowTop + Math.Max(0, (nameLineH - fontLine) / 2);
            plan.MagazineNameH = fontLine;
            plan.MagazineAmmoTopPx = hasAmmo ? rowTop + nameLineH + lineGap : 0;
            plan.MagazineAmmoH = hasAmmo ? fontLine : 0;
            return gap + gap + rowH;
        }

        /// <summary>
        /// 书签式插条（document.rail）：白色块自上而下排在图标左侧，块内文字横向
        /// 左→右；块宽 = 文字测量宽 + 2×左右内边距（上限 RailMaxWBase，超出绘制省略），
        /// 块高 RailBlockHBase，块间 RailBlockGapBase。
        /// 并排时整列（宽 = 最宽块 + 间距）并入 TipSize，面板/图标/子框整体右移；
        /// stacked 降级时书签横排（超出换行）在 intro 面板上方，整组下移。
        /// </summary>
        private static int RailBlockWidth(string text, float scale, Func<string, RunFont, int> measure)
        {
            int labelWidth = string.IsNullOrEmpty(text) ? 0 : measure(text, new RunFont { Bold = true });
            return Math.Max(Px(24, scale), Math.Min(Px(RailMaxWBase, scale), labelWidth + 2 * Px(RailTextPadXBase, scale)));
        }

        private static void ApplyRail(Plan plan, NativeTooltipDocument doc, float scale,
            Func<string, RunFont, int> measure)
        {
            if (doc.Rail == null || doc.Rail.Texts.Count == 0) return;
            if (plan.IntroPanel.IsEmpty) return;

            int fontPx = Px(RailFontBase, scale);
            int blockH = Px(RailBlockHBase, scale);
            int gap = Px(RailBlockGapBase, scale);
            int padX = Px(RailTextPadXBase, scale);

            List<int> widths = new List<int>();
            int widest = 0;
            for (int i = 0; i < doc.Rail.Texts.Count; i++)
            {
                string text = doc.Rail.Texts[i];
                int w = RailBlockWidth(text, scale, measure);
                widths.Add(w);
                if (w > widest) widest = w;
            }

            if (plan.Stacked)
            {
                int rowW = Math.Max(1, plan.TipSize.Width);
                int x = 0, y = 0;
                for (int i = 0; i < doc.Rail.Texts.Count; i++)
                {
                    int w = Math.Min(widths[i], rowW);
                    if (x > 0 && x + w > rowW) { x = 0; y += blockH + gap; }
                    Plan.RailBlock block = new Plan.RailBlock();
                    block.Rect = new Rectangle(x, y, w, blockH);
                    block.Text = doc.Rail.Texts[i];
                    block.FontPx = fontPx;
                    plan.RailBlocks.Add(block);
                    x += w + gap;
                }
                int shift = y + blockH + Px(RailShiftGapBase, scale);
                ShiftPanelsDown(plan, shift);
                plan.RailShift = shift;
                plan.TipSize = new Size(rowW, plan.TipSize.Height + shift);
                return;
            }

            int top = !plan.IconRect.IsEmpty
                ? plan.IconRect.Y
                : plan.IntroPanel.Y + Px(PanelPadBase, scale);
            // 书签右缘贴合图标左缘。矮视口缩图标后，贴合点随图标居中位置移动。
            int attachX = (!plan.IconRect.IsEmpty ? plan.IconRect.X : Px(PanelPadBase, scale))
                + Px(1, scale);
            int dx = Math.Max(0, widest - attachX);
            int right = attachX + dx;
            for (int i = 0; i < doc.Rail.Texts.Count; i++)
            {
                Plan.RailBlock block = new Plan.RailBlock();
                block.Rect = new Rectangle(right - widths[i], top + i * (blockH + gap), widths[i], blockH);
                block.Text = doc.Rail.Texts[i];
                block.FontPx = fontPx;
                block.PadX = padX;
                plan.RailBlocks.Add(block);
            }
            ShiftPanelsRight(plan, dx);
            plan.RailShift = dx;
            plan.TipSize = new Size(plan.TipSize.Width + dx, plan.TipSize.Height);
        }

        /// <summary>stacked 插条行占位后整体下移：面板/图标/正文/弹夹行同步，
        /// SolvePlacement 仍按含插条行的总高避让（子框在 ApplyRail 之后计算）。</summary>
        private static void ShiftPanelsDown(Plan plan, int dy)
        {
            if (dy == 0) return;
            if (!plan.IntroPanel.IsEmpty) plan.IntroPanel.Offset(0, dy);
            if (!plan.DescPanel.IsEmpty) plan.DescPanel.Offset(0, dy);
            if (!plan.IconRect.IsEmpty) plan.IconRect.Offset(0, dy);
            if (!plan.ScrollViewportRect.IsEmpty) plan.ScrollViewportRect.Offset(0, dy);
            if (!plan.MagazineRow.IsEmpty) plan.MagazineRow.Offset(0, dy);
            if (!plan.MagazineIconRect.IsEmpty) plan.MagazineIconRect.Offset(0, dy);
            if (plan.MagazineDividerY > 0) plan.MagazineDividerY += dy;
            if (plan.MagazineNameTopPx > 0) plan.MagazineNameTopPx += dy;
            if (plan.MagazineAmmoTopPx > 0) plan.MagazineAmmoTopPx += dy;
            plan.IntroTitleTopPx += dy;
            plan.IntroContentTopPx += dy;
            plan.DescContentTopPx += dy;
        }

        /// <summary>插条占位后整体右移：面板/图标/正文左缘/滚动视口/弹夹行同步，
        /// 使子框与主面板左缘对齐、SolvePlacement 仍按含插条的总宽避让。</summary>
        private static void ShiftPanelsRight(Plan plan, int dx)
        {
            if (dx == 0) return;
            if (!plan.IntroPanel.IsEmpty) plan.IntroPanel.Offset(dx, 0);
            if (!plan.DescPanel.IsEmpty) plan.DescPanel.Offset(dx, 0);
            if (!plan.IconRect.IsEmpty) plan.IconRect.Offset(dx, 0);
            if (!plan.ScrollViewportRect.IsEmpty) plan.ScrollViewportRect.Offset(dx, 0);
            if (!plan.MagazineRow.IsEmpty) plan.MagazineRow.Offset(dx, 0);
            if (!plan.MagazineIconRect.IsEmpty) plan.MagazineIconRect.Offset(dx, 0);
            plan.MagazineTextLeftPx += dx;
            plan.IntroContentLeftPx += dx;
            plan.DescContentLeftPx += dx;
        }

        /// <summary>
        /// web ensureInspectionStatus + setInspectionState：
        /// - dense && pending → 23px 状态条（文案 + 72px 进度槽），margin-bottom 7px；
        /// - dense && inspect → 稳态为 collapse 动画终态的 2px accent 细条
        ///   （web 在进入检视约 1.2s 后折叠，native 无动画时钟直接取稳态）；
        /// - scan/idle/非 dense → 无条。
        /// 条宽 = fit-content（max-width:100%）：
        ///   2px 左边条 + pad7 + dot6 + gap7 + 文案 +（pending: gap7 + 72px 槽）+ pad7。
        /// 文案宽以 measure 回调按字号比折算（measure 为 12px 主体字，本条 11px）。
        /// </summary>
        private static void ApplyInspectionStrip(Plan plan,
            Func<string, RunFont, int> measure, float scale, string state)
        {
            bool pending = state == InspStatePending;
            if (!pending && state != InspStateInspect) return;
            int stripH = pending ? Px(InspMinHBase, scale) : Px(InspCollapsedHBase, scale);
            int margin = Px(InspMarginBase, scale);
            string label = pending ? InspPendingLabel : InspInspectLabel;
            int copyW = (int)Math.Round(
                measure(label, new RunFont { Bold = true })
                    * (InspFontBase / (double)FontPxBase));
            int w = Px(InspBorderLBase + InspPadXBase + InspDotBase + InspGapBase, scale)
                + copyW
                + (pending ? Px(InspGapBase + InspMeterWBase, scale) : 0)
                + Px(InspPadXBase, scale);
            w = Math.Max(Px(24, scale), Math.Min(w, plan.TipSize.Width));

            int off = stripH + margin;
            if (!plan.IntroPanel.IsEmpty) plan.IntroPanel.Offset(0, off);
            if (!plan.DescPanel.IsEmpty) plan.DescPanel.Offset(0, off);
            if (!plan.IconRect.IsEmpty) plan.IconRect.Offset(0, off);
            if (!plan.ScrollViewportRect.IsEmpty) plan.ScrollViewportRect.Offset(0, off);
            foreach (Plan.SubBox sb in plan.Subs) sb.Offset(0, off);
            foreach (Plan.RailBlock rb in plan.RailBlocks) rb.Rect.Offset(0, off);
            if (!plan.MagazineRow.IsEmpty) plan.MagazineRow.Offset(0, off);
            if (!plan.MagazineIconRect.IsEmpty) plan.MagazineIconRect.Offset(0, off);
            if (plan.MagazineDividerY > 0) plan.MagazineDividerY += off;
            if (plan.MagazineNameTopPx > 0) plan.MagazineNameTopPx += off;
            if (plan.MagazineAmmoTopPx > 0) plan.MagazineAmmoTopPx += off;
            plan.IntroTitleTopPx += off;
            plan.IntroContentTopPx += off;
            plan.DescContentTopPx += off;
            plan.TipSize = new Size(Math.Max(plan.TipSize.Width, w),
                plan.TipSize.Height + off);
            plan.InspStrip = new Rectangle(0, 0, w, stripH);
            plan.InspState = pending ? InspStatePending : InspStateInspect;
            plan.InspMeterW = pending ? Px(InspMeterWBase, scale) : 0;
        }

        /// <summary>逐行真实高浮点累加，只在出口取整一次（避免 15.625 类
        /// 行高逐行取整的累计漂移）。</summary>
        private static int SumHeight(IList<VisualLine> lines, float fallbackLh)
        {
            float h = 0;
            foreach (VisualLine l in lines)
                h += l.RowHeight(fallbackLh);
            // 内容包围盒须向外取整：312.5px 不能装进312px视口，
            // 否则本可完整显示的短注释会凭空获得一行滚动和检视等待。
            return (int)Math.Ceiling(h);
        }

        /// <summary>视口内可见行数：逐行浮点累加，行顶进入可视区即计
        /// （web 末行可部分可见，截断由绘制层 clip 负责）。</summary>
        private static int VisibleLineCount(IList<VisualLine> lines, int viewH)
        {
            if (lines == null || lines.Count == 0 || viewH <= 0) return 0;
            float acc = 0;
            int n = 0;
            foreach (VisualLine l in lines)
            {
                if (acc >= viewH) break;
                acc += l.RowHeight(0);
                n++;
            }
            return Math.Max(1, n);
        }

        // ── plain 短提示（#panel-tooltip 原生框）──

        private static void ComputePlain(
            NativeTooltipDocument doc,
            Func<string, RunFont, int> measure,
            float scale, int vpW, int vpH, float dpiScale,
            Plan plan,
            List<NativeTooltipSection> introSecs,
            List<NativeTooltipSection> descSecs)
        {
            plan.Plain = true;
            int padX = Px(PlainPadXBase, scale);
            int padY = Px(PlainPadYBase, scale);
            float lh = FontPxBase * PlainLineHeightEm * scale;
            int lhInt = Math.Max(1, (int)Math.Round(lh));
            plan.LineHeightPx = lhInt;
            plan.LineHeightIntroPx = lhInt;
            plan.LineHeightDescPx = lhInt;
            // max-width:480px 只是上限（overlay.css 全局 box-sizing:border-box →
            // 480 含 padding）；#panel-tooltip position:fixed + width:auto =
            // shrink-to-fit：真实宽 = min(max-content + 2·padX, cap)。
            // 视口 inset 8 双边兜底保留为 cap 下限钳制（视口 CSS px 域常量 ×dpi）。
            int capW = Math.Min(Px(PlainMaxWBase, scale),
                Math.Max(Px(60, scale),
                    vpW - (int)Math.Round(ViewportInsetBase * 2 * dpiScale)));
            int textCapW = Math.Max(1, capW - padX * 2);

            List<NativeTooltipRun> runs = new List<NativeTooltipRun>();
            if (doc.TitleRuns.Count > 0)
            {
                runs.AddRange(doc.TitleRuns);
                runs.Add(BreakRun());
            }
            runs.AddRange(BuildColumnRuns(doc.Sections));
            // 先在宽度上限内排版；出现软折行就使用 cap，否则按最长逻辑行收缩。
            // 不做无界逐字测宽：长文本会使整段测量与缓存呈平方增长。
            List<VisualLine> lines = WrapRuns(runs, textCapW, measure, lh);
            bool wrapped = lines.Exists(line => !line.EndsLogicalLine);
            float maxContent = 0f;
            foreach (VisualLine l in lines)
            {
                float lw = NaturalLineWidth(l, measure);
                if (lw > maxContent) maxContent = lw;
            }
            if (wrapped) maxContent = textCapW;
            if (lines.Count > MaxRenderedLines)
                lines = lines.GetRange(0, MaxRenderedLines);
            int panelW = Math.Min(capW,
                (int)Math.Ceiling(maxContent) + padX * 2);
            int h = padY * 2 + SumHeight(lines, lh);
            plan.IntroPanel = new Rectangle(0, 0, panelW, h);
            plan.TipSize = new Size(panelW, h);
            plan.IntroLines = lines;
            plan.IntroLogicalLines = MergeLogicalLines(lines);
            plan.IntroContentLeftPx = padX;
            plan.IntroContentTopPx = padY;
        }

        /// <summary>逻辑行自然宽（max-content 语义）：slice 宽和；行尾可塌陷空白
        /// 剔除后按原字体重量（CSS line-end white-space removal——尾部空白可跨
        /// 多个样式 slice，直到遇到含非空白字符的 slice 为止）。</summary>
        private static float NaturalLineWidth(VisualLine line,
            Func<string, RunFont, int> measure)
        {
            float w = 0f;
            int n = line.Slices.Count;
            for (int i = 0; i < n; i++) w += line.Slices[i].WidthF;
            for (int i = n - 1; i >= 0; i--)
            {
                VisualLine.Slice s = line.Slices[i];
                string trimmed = s.Text.TrimEnd(' ', '\t');
                if (trimmed.Length == s.Text.Length) break;
                w += (trimmed.Length > 0 ? measure(trimmed, s.FontOf()) : 0)
                    - s.WidthF;
                if (trimmed.Length > 0) break;
            }
            return w;
        }

        // ── pinned 检视器（inspector shell + body 滚动）──

        private static void ComputePinned(
            NativeTooltipDocument doc,
            Func<string, RunFont, int> measure,
            float scale, int vpW, int vpH, float dpiScale,
            Plan plan,
            bool hasIcon, bool hasDesc,
            List<NativeTooltipSection> introSecs,
            List<NativeTooltipSection> descSecs)
        {
            int border = Px(PinnedBorderBase, scale);
            int bodyPad = Px(PinnedBodyPadBase, scale);
            int sbW = Px(PinnedScrollbarWBase, scale);
            float lhIntro = FontPxBase * PinnedIntroLineHeightEm * scale;
            float lhDesc = FontPxBase * PinnedDescLineHeightEm * scale;
            int lhIntroInt = Math.Max(1, (int)Math.Round(lhIntro));
            plan.LineHeightIntroPx = lhIntroInt;
            plan.LineHeightDescPx = Math.Max(1, (int)Math.Round(lhDesc));
            plan.LineHeightPx = lhIntroInt;

            // shell 宽 = min(360px, 100vw-16px)：vw 在本地单位规则内求值
            // （CSS px 视口 = vpW/dpi）→ 物理 ×scale
            int shellW = Px(Math.Min(PinnedWidthBase,
                vpW / dpiScale - ViewportInsetBase * 2), scale);
            shellW = Math.Max(Px(120, scale), shellW);
            int headerH = Px(PinnedHeaderMinHBase, scale);
            // body 内宽 = 壳内 - 边 - 滚动条槽
            int bodyW = shellW - border * 2 - sbW;
            int richW = bodyW;                            // .flash-tt-rich width:100%

            // intro-panel：grid 104px | 1fr，pad 8；无 icon 时唯一 item 落第一列（Web 网格语义）
            int iconSize = Px(PinnedIconBase, scale);
            int iconCol = Px(PinnedGridIconColBase, scale);
            int gridGap = Px(PinnedGridGapBase, scale);
            int textColW = hasIcon ? richW - iconCol - gridGap : iconCol;
            // merge：desc 拼入 intro 文本列（Web 同规则 shouldSplit + '<br><br>' 分隔）
            TextScore descScore = ScoreSections(descSecs);
            TextScore introScore = ScoreSections(introSecs);
            plan.Split = hasDesc && ShouldSplit(descScore, introScore);

            List<NativeTooltipRun> introRuns = IntroColumnRuns(doc, introSecs);
            if (!plan.Split && hasDesc) AppendMergedDesc(introRuns, descSecs);
            List<VisualLine> introLines = WrapRuns(introRuns,
                Math.Max(1, textColW - bodyPad * 2), measure, lhIntro);
            int introPanelH = Math.Max(
                hasIcon ? iconSize : 0,
                SumHeight(introLines, lhIntro)) + bodyPad * 2;
            plan.PinnedIntroRect = new Rectangle(0, 0, richW, introPanelH);
            // icon 在 104px 网格列内居中（.flash-tt-icon justify-content:center）
            plan.PinnedIconRect = hasIcon
                ? new Rectangle(bodyPad + Math.Max(0, (iconCol - iconSize) / 2),
                    bodyPad, iconSize, iconSize)
                : Rectangle.Empty;
            plan.PinnedTextX = (hasIcon ? iconCol + gridGap : 0) + bodyPad;
            plan.PinnedTextY = bodyPad;

            // desc 面板（split）：宽 100%、overflow:visible 随 body 滚
            List<VisualLine> descLines = new List<VisualLine>();
            int descPanelH = 0;
            if (plan.Split && hasDesc)
            {
                descLines = WrapRuns(BuildColumnRuns(descSecs),
                    Math.Max(1, richW - bodyPad * 2), measure, lhDesc);
                descPanelH = SumHeight(descLines, lhDesc) + bodyPad * 2;
            }
            plan.PinnedDescRect = plan.Split && hasDesc
                ? new Rectangle(0, introPanelH, richW, descPanelH)
                : Rectangle.Empty;

            // body 滚动：可视高 = min(内容高, 壳 max-height - header - border)；
            // web max-height:calc((100vh-16px)/overlayScale) 是本地单位规则，
            // 目标是让 transform 后壳高 ≤ vh-16 → 物理 = (vh_css-16)×dpi = vpH-16×dpi
            int contentH = introPanelH + descPanelH;
            int shellMaxH = Math.Max(headerH + border * 2 + lhIntroInt,
                vpH - (int)Math.Round(ViewportInsetBase * 2 * dpiScale));
            int bodyViewH = Math.Min(contentH, shellMaxH - headerH - border * 2);
            bodyViewH = Math.Max(lhIntroInt, bodyViewH);
            int shellH = headerH + border * 2 + bodyViewH;

            plan.TipSize = new Size(shellW, shellH);
            plan.IntroPanel = new Rectangle(0, 0, shellW, shellH); // 壳=整面板（绘壳用）
            plan.HeaderRect = new Rectangle(border, border,
                shellW - border * 2, headerH);
            int closeW = Px(PinnedCloseWBase, scale);
            int closeH = Px(PinnedCloseHBase, scale);
            plan.CloseRect = new Rectangle(
                shellW - border - Px(PinnedHeaderPadRBase, scale) - closeW,
                border + (headerH - closeH) / 2,
                closeW, closeH);
            plan.BodyRect = new Rectangle(border, border + headerH,
                shellW - border * 2, bodyViewH);
            plan.ScrollViewportRect = plan.BodyRect;
            plan.Target = ReadingTarget.PinnedBody;
            plan.ContentHeightPx = contentH;

            // body 滚动单元：intro 行 + desc 行（各自行高）
            plan.DescLines = new List<VisualLine>();
            plan.DescLines.AddRange(introLines);
            plan.DescLines.AddRange(descLines);
            plan.IntroLines = introLines;
            plan.IntroLogicalLines = MergeLogicalLines(introLines);
            plan.DescLogicalLines = MergeLogicalLines(plan.DescLines);
            plan.DescTotalLines = plan.DescLines.Count;

            plan.DescVisibleLines = VisibleLineCount(plan.DescLines, bodyViewH);
            plan.DescContentLeftPx = 0;
            plan.DescContentTopPx = 0;
        }

        // ──────────── positionFloating 四候选定位 ────────────

        /// <summary>
        /// tooltip.js positionFloating 同源：left/right/top/bottom 四候选；
        /// lockedSide 可行则锁定；否则按 overflow*1e6 + pointerOverlap*1e4 +
        /// anchorOverlap*1e2 + shift*10 + 序号 打分取最小；最终夹取 inset。
        /// anchored=true（pinned）时指针互斥半径取 0。
        ///
        /// 定位域 = 视口 CSS px（Web innerWidth/innerHeight 坐标，anchor 与
        /// getBoundingClientRect 同为 transform 后 CSS px）：
        /// inset(8)/gap(10)/pointer 半径(16)/eps(0.5) 均为 CSS px 常量——不随
        /// overlay scale 缩放，但随 DPI 缩放（物理 = ×dpiScale）。
        /// anchorPt/tipSize/viewport 均已为物理 px；scale 只作用于 tooltip 自身
        /// 尺寸（tipSize 已含）。无元素 anchor 与 Web 相同，退化为零面积鼠标点。
        /// 参数 scale 仅作签名兼容保留。
        /// </summary>
        internal static Rectangle SolvePlacement(
            Point anchorPt, Size tipSize, Rectangle viewport,
            string lockedSide, float scale, out string side)
        {
            return SolvePlacement(anchorPt, tipSize, viewport, lockedSide, scale, 1f, false, out side);
        }

        internal static Rectangle SolvePlacement(
            Point anchorPt, Size tipSize, Rectangle viewport,
            string lockedSide, float scale, bool anchored, out string side)
        {
            return SolvePlacement(anchorPt, tipSize, viewport, lockedSide, scale, 1f, anchored, out side);
        }

        internal static Rectangle SolvePlacement(
            Point anchorPt, Size tipSize, Rectangle viewport,
            string lockedSide, float scale, float dpiScale, bool anchored,
            out string side)
        {
            return SolvePlacement(new Rectangle(anchorPt, Size.Empty), anchorPt, tipSize,
                viewport, lockedSide, null, dpiScale, anchored, out side);
        }

        /// <summary>与 Web 相同：元素矩形用于候选边界，实际鼠标点只参与碰撞评分。</summary>
        internal static Rectangle SolvePlacement(Rectangle anchorRect, Point pointer,
            Size tipSize, Rectangle viewport, string lockedSide, string placementHint,
            float dpiScale, bool anchored, out string side)
        {
            if (!(dpiScale > 0f) || float.IsNaN(dpiScale) || float.IsInfinity(dpiScale))
                dpiScale = 1f;
            int inset = Math.Max(1, (int)Math.Round(ViewportInsetBase * dpiScale));
            int gap = (int)Math.Round(AnchorGapBase * dpiScale);
            float pointerR = anchored ? 0f : PointerExcludeRadiusBase * dpiScale;
            double eps = PlacementEps * dpiScale;
            int vw = viewport.Width, vh = viewport.Height;
            int vx = viewport.X, vy = viewport.Y;
            int tw = Math.Max(1, tipSize.Width), th = Math.Max(1, tipSize.Height);

            // 触发元素的边缘决定位置；无元素时 anchorRect 退化为零面积点。
            Rectangle[] c = new Rectangle[4];
            string[] names = { "left", "right", "top", "bottom" };
            c[0] = new Rectangle(anchorRect.Left - tw - gap, anchorRect.Top, tw, th); // left
            c[1] = new Rectangle(anchorRect.Right + gap, anchorRect.Top, tw, th);  // right
            c[2] = new Rectangle(anchorRect.Left, anchorRect.Top - th - gap, tw, th); // top
            c[3] = new Rectangle(anchorRect.Left, anchorRect.Bottom + gap, tw, th);  // bottom

            int lockedIdx = IndexOfSide(lockedSide);
            if (lockedIdx >= 0 && Feasible(names[lockedIdx], c[lockedIdx], inset, vx, vy, vw, vh, eps))
            {
                side = names[lockedIdx];
                return Clamp(c[lockedIdx], inset, vx, vy, vw, vh);
            }

            int hintIdx = IndexOfSide(placementHint);
            if (hintIdx >= 0 && Feasible(names[hintIdx], c[hintIdx], inset, vx, vy, vw, vh, eps))
            {
                side = names[hintIdx];
                return Clamp(c[hintIdx], inset, vx, vy, vw, vh);
            }

            Rectangle pointerRect = new Rectangle(
                (int)Math.Round(pointer.X - pointerR),
                (int)Math.Round(pointer.Y - pointerR),
                (int)Math.Round(pointerR * 2), (int)Math.Round(pointerR * 2));

            double best = double.MaxValue;
            int bestIdx = 1;
            Rectangle bestRect = c[1];
            for (int i = 0; i < 4; i++)
            {
                Rectangle raw = c[i];
                Rectangle cl = Clamp(raw, inset, vx, vy, vw, vh);
                // Web 对夹取后的矩形求 overflow（正常布局下为 0，超大 tip 才有值）
                double overflow = Math.Max(0, vx + inset - cl.X)
                    + Math.Max(0, vy + inset - cl.Y)
                    + Math.Max(0, cl.Right - (vx + vw - inset))
                    + Math.Max(0, cl.Bottom - (vy + vh - inset));
                double pointerOv = OverlapArea(cl, pointerRect);
                double anchorOv = OverlapArea(cl, anchorRect);
                double shift = Math.Abs(cl.X - raw.X) + Math.Abs(cl.Y - raw.Y);
                double score = overflow * 1000000.0 + pointerOv * 10000.0
                    + anchorOv * 100.0 + shift * 10.0 + i;
                if (score < best) { best = score; bestIdx = i; bestRect = cl; }
            }
            side = names[bestIdx];
            return bestRect;
        }

        private static int IndexOfSide(string side)
        {
            switch (side)
            {
                case "left": return 0;
                case "right": return 1;
                case "top": return 2;
                case "bottom": return 3;
                default: return -1;
            }
        }

        private static bool Feasible(string name, Rectangle r,
            int inset, int vx, int vy, int vw, int vh, double eps)
        {
            switch (name)
            {
                case "left": return r.X >= vx + inset - eps;
                case "right": return r.Right <= vx + vw - inset + eps;
                case "top": return r.Y >= vy + inset - eps;
                default: return r.Bottom <= vy + vh - inset + eps;
            }
        }

        private static Rectangle Clamp(Rectangle r, int inset, int vx, int vy, int vw, int vh)
        {
            int maxX = Math.Max(vx + inset, vx + vw - r.Width - inset);
            int maxY = Math.Max(vy + inset, vy + vh - r.Height - inset);
            int x = Math.Max(vx + inset, Math.Min(r.X, maxX));
            int y = Math.Max(vy + inset, Math.Min(r.Y, maxY));
            return new Rectangle(x, y, r.Width, r.Height);
        }

        private static double OverlapArea(Rectangle a, Rectangle b)
        {
            int w = Math.Max(0, Math.Min(a.Right, b.Right) - Math.Max(a.X, b.X));
            int h = Math.Max(0, Math.Min(a.Bottom, b.Bottom) - Math.Max(a.Y, b.Y));
            return (double)w * h;
        }
    }
}
