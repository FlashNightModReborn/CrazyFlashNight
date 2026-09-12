using System;
using System.Collections.Generic;
using System.Drawing;

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
        internal const int DescMaxWBase = 650;            // --tt-desc-max-w: 650px
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

        // ---- 智能拆分（TooltipConstants.as / shouldSplitWeb 同值）----
        private const double SPLIT_THRESHOLD = 96.0;
        private const int SMART_TOTAL_MULT = 2;
        private const int SMART_DESC_DIV = 2;
        private const int MERGE_MAX_INTRO_LINES = 20;
        private const double MERGE_CHARS_PER_LINE = 33.0;

        // ---- estimateMainWidth（TooltipConstants.as 同源 sqrt 公式）----
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
        internal static double CharWeight(char c)
        {
            if (c == ' ' || c == '\t') return 0.5;
            if (c < 128) return 1;
            if (IsWideChar(c)) return 2;
            if (c < 256) return 1;
            return 2;
        }

        internal static bool IsWideChar(char c)
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
            for (int i = 0; i < s.Length; i++)
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
                    continue;
                }
                double w = CharWeight(c);
                sc.Total += w;
                line += w;
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

        // ──────────── estimateMainWidth（sqrt 公式）────────────

        /// <summary>W = sqrt(r*total*6*15)，r 由 total/300 smoothstep 到 [0.618,1.5]；
        /// 下限 total*6/32，上限 maxLine*6+20，最终 clamp [minW,maxW]。</summary>
        internal static int EstimateMainWidth(TextScore s, int minW, int maxW)
        {
            if (s.Total <= 0) return minW;
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
            if (sqrtW > maxW) sqrtW = maxW;
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
                internal Color? Color;
                internal bool Bold;
                internal bool Italic;
                internal bool Underline;
                internal int? FontSize;
                internal string FontFace;
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
            if (runs == null || maxWidthPx <= 0) return outLines;

            // 行宽统一走浮点域：GDI+ 测宽 + letterSpacing×字符数（CSS letter-spacing
            // 对每个字符追加），软折边界按含 ls 的整段宽判。
            Func<string, RunFont, float> measureF =
                delegate (string t, RunFont f)
                { return measure(t, f) + t.Length * letterSpacingPx; };

            LineBuf cur = new LineBuf(lineHeightPx);
            foreach (NativeTooltipRun run in runs)
            {
                if (run == null || string.IsNullOrEmpty(run.Text)) continue;
                string t = run.Text;
                RunFont font = RunFont.Of(run);

                // run 边界断点（web 内联流：span 边界可断，规则同窗内字符）：
                // 前字符可断（空白/-/宽字符）或本 run 首字符为宽字符；
                // 开符后/闭符前禁断。
                if (cur.HasContent)
                {
                    char next = t[0];
                    if (next != '\n' && next != '\r'
                        && !IsOpeningPunct(cur.LastChar) && !IsClosingPunct(next)
                        && (cur.LastChar == ' ' || cur.LastChar == '-'
                            || IsWideChar(cur.LastChar) || IsWideChar(next)))
                    {
                        MarkBreak(cur);
                    }
                }

                int i = 0;
                while (i < t.Length)
                {
                    char c = t[i];
                    if (c == '\r' || c == '\n')
                    {
                        if (c == '\r' && i + 1 < t.Length && t[i + 1] == '\n') i++;
                        outLines.Add(cur.FlushLine());
                        i++;
                        continue;
                    }
                    // CSS 空白折叠：行首（换行/软断后）空白不渲染；
                    // 行内连续 space/tab 序列折叠为单个空格（white-space:normal）。
                    if (c == ' ' || c == '\t')
                    {
                        if (!cur.HasContent || cur.LastChar == ' ') { i++; continue; }
                        c = ' ';
                    }
                    // span 级测量：可并入末 slice 时按"整段文本+c"量宽取增量，
                    // 与 CSS 按完整 inline span 渲染的宽度一致（避免逐字累加的
                    // 单次测量边距/舍入膨胀）。
                    float cw = cur.TrialDelta(c, run, font, measureF);
                    if (cur.HasContent && cur.WidthF + cw > maxWidthPx)
                    {
                        if (cur.BrkSlice >= 0) BreakAt(cur, outLines, measureF);
                        else outLines.Add(cur.FlushLine());
                        continue;   // 同一字符在新行重试
                    }
                    cur.Append(c, run, font, cw);
                    if (CanBreakAfter(t, i)) MarkBreak(cur);
                    i++;
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
                return s.Color == (run != null ? run.Color : null)
                    && s.Bold == font.Bold && s.Italic == font.Italic
                    && s.Underline == font.Underline
                    && s.FontSize == font.FontSize && s.FontFace == font.FontFace;
            }

            /// <summary>追加字符的行宽增量（浮点，含 letter-spacing）：
            /// 可并入末 slice 时量整段文本取差。</summary>
            internal float TrialDelta(char c, NativeTooltipRun run, RunFont font,
                Func<string, RunFont, float> measure)
            {
                VisualLine.Slice last =
                    Slices.Count > 0 ? Slices[Slices.Count - 1] : null;
                if (last != null && SameStyle(last, run, font))
                    return measure(last.Text + c, font) - last.WidthF;
                return measure(c.ToString(), font);
            }

            internal void Append(char c, NativeTooltipRun run, RunFont font, float cw)
            {
                VisualLine.Slice last = Slices.Count > 0 ? Slices[Slices.Count - 1] : null;
                Color? color = run != null ? run.Color : null;
                if (last != null && SameStyle(last, run, font))
                {
                    last.Text += c;
                    last.WidthF += cw;
                    last.WidthPx = (int)Math.Round(last.WidthF);
                }
                else
                {
                    Slices.Add(new VisualLine.Slice
                    {
                        Text = c.ToString(),
                        Color = color,
                        Bold = font.Bold,
                        Italic = font.Italic,
                        Underline = font.Underline,
                        FontSize = font.FontSize,
                        FontFace = font.FontFace,
                        WidthF = cw,
                        WidthPx = (int)Math.Round(cw)
                    });
                }
                if (font.FontSize.HasValue && font.FontSize.Value > MaxFontCss)
                    MaxFontCss = font.FontSize.Value;
                WidthF += cw;
                LastChar = c;
            }

            internal VisualLine FlushLine()
            {
                float h = HeightF;
                VisualLine l = new VisualLine
                {
                    LineHeightF = h,
                    LineHeightPx = (int)Math.Round(h),
                    EndsLogicalLine = true
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
                hs.WidthF = measure(headText, mid.FontOf());
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
            foreach (VisualLine l in lines)
            {
                if (acc == null) acc = new VisualLine();
                foreach (VisualLine.Slice s in l.Slices)
                {
                    VisualLine.Slice last = acc.Slices.Count > 0
                        ? acc.Slices[acc.Slices.Count - 1] : null;
                    if (last != null && last.Color == s.Color
                        && last.Bold == s.Bold && last.Italic == s.Italic
                        && last.Underline == s.Underline
                        && last.FontSize == s.FontSize && last.FontFace == s.FontFace)
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
                Text = s.Text, Color = s.Color, Bold = s.Bold, Italic = s.Italic,
                Underline = s.Underline, FontSize = s.FontSize, FontFace = s.FontFace,
                WidthPx = s.WidthPx, WidthF = s.WidthF
            };
        }

        /// <summary>
        /// 位置 i（刚追加的字符）之后是否可断——CSS line-break/UAX14 近似：
        /// 开标点后、闭标点前禁断；空白/'-' 后、宽字符后、西文→宽字符边界可断。
        /// </summary>
        private static bool CanBreakAfter(string t, int i)
        {
            char c = t[i];
            if (IsOpeningPunct(c)) return false;
            if (i + 1 < t.Length && IsClosingPunct(t[i + 1])) return false;
            if (c == ' ' || c == '\t' || c == '-') return true;
            if (IsWideChar(c)) return true;
            return i + 1 < t.Length && IsWideChar(t[i + 1]);
        }

        /// <summary>开标点（UAX14 OP 近似）：其后禁止断行。</summary>
        private static bool IsOpeningPunct(char c)
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
        private static bool IsClosingPunct(char c)
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
        private static List<NativeTooltipRun> BuildColumnRuns(
            IEnumerable<NativeTooltipSection> sections)
        {
            List<NativeTooltipRun> runs = new List<NativeTooltipRun>();
            if (sections == null) return runs;
            foreach (NativeTooltipSection s in sections)
            {
                if (s == null) continue;
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
                else runs.AddRange(s.Runs);
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
            NativeTooltipDocument doc, IList<NativeTooltipSection> introSecs)
        {
            List<NativeTooltipRun> runs = new List<NativeTooltipRun>();
            if (doc.TitleRuns.Count > 0)
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

        internal sealed class Plan
        {
            /// <summary>整 tip 尺寸（物理 px）。</summary>
            internal Size TipSize;
            /// <summary>true=拆分（desc 独立侧栏）；false=合并单面板。</summary>
            internal bool Split;
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

            /// <summary>intro 面板内文本行（split 时仅 intro；merge 时含 desc 拼接）。</summary>
            internal List<VisualLine> IntroLines = new List<VisualLine>();
            /// <summary>desc 面板文本行（split）；pinned 时为 body 滚动单元整列。</summary>
            internal List<VisualLine> DescLines = new List<VisualLine>();

            /// <summary>intro/desc 的逻辑行视图：软换行续行并回所属逻辑行，
            /// 对应 web innerText 提取（innerText 不在软折处产生 \n，且丢弃空行）。
            /// parity-compare 的 text.intro/text.desc 应读这两列而非视觉行。</summary>
            internal List<VisualLine> IntroLogicalLines = new List<VisualLine>();
            internal List<VisualLine> DescLogicalLines = new List<VisualLine>();

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

            /// <summary>desc/pinned body 可滚动。</summary>
            internal bool DescScrollable;
            internal int DescVisibleLines;
            internal int DescTotalLines;
            internal int MaxScrollLine;
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
            float dpiScale = 1f)
        {
            return ComputePlan(doc,
                delegate (string t, RunFont f) { return measure(t, f.Bold); },
                lineHeightPx, scale, viewportWidthPx, viewportHeightPx,
                inspectionState, dpiScale);
        }

        internal static Plan ComputePlan(
            NativeTooltipDocument doc,
            Func<string, RunFont, int> measure,
            float lineHeightPx,
            float scale,
            int viewportWidthPx,
            int viewportHeightPx,
            string inspectionState = null,
            float dpiScale = 1f)
        {
            if (doc == null) throw new ArgumentNullException("doc");
            if (measure == null) throw new ArgumentNullException("measure");
            scale = Math.Max(0.25f, scale);
            lineHeightPx = Math.Max(1f, lineHeightPx);
            if (!(dpiScale > 0f) || float.IsNaN(dpiScale) || float.IsInfinity(dpiScale))
                dpiScale = 1f;
            // CSS px 视口（=Web innerWidth/innerHeight）：vh/vw 媒体规则与
            // 视口域常量都在此域求值，再按各自目标域换算物理 px。
            float vwCss = viewportWidthPx / dpiScale;
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
            bool hasIntro = doc.TitleRuns.Count > 0 || introSecs.Count > 0;
            bool hasDesc = descSecs.Count > 0;

            // ── plain 文本提示：无 icon 且 profile=simple → #panel-tooltip 原生样式
            //    （迁移前 Web 里 setText 短提示：灰渐变框 + pad 10/14 + maxw 480 + lh 1.5）
            if (!hasIcon && !plan.Pinned
                && doc.Profile == NativeTooltipProfile.Simple)
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
            plan.Split = hasDesc && ShouldSplit(descScore, introScore);

            bool wide = plan.LayoutWide;
            int pad = Px(PanelPadBase, scale);
            int introW = Px(wide ? BaseNum : 120, scale);
            int introMinH = Px(wide ? IntroMinHWideBase : IntroMinHNarrowBase, scale);
            int iconBox = Px(wide ? IconBoxWideBase : IconBoxNarrowBase, scale);
            int iconGap = Px(wide ? IconTextGapWideBase : IconTextGapNarrowBase, scale);
            int sbW = Px(ScrollbarWBase, scale);

            // 定位/降级判定域 = 视口 CSS px（Web innerWidth/innerHeight + transform 后
            // getBoundingClientRect 域）：inset(8)/stacked margin(32) 是 CSS px 常量，
            // 与物理 client 之间差 dpi 因子；元素自身尺寸仍走 scale。
            int insetClient = ViewportInsetBase;

            // intro-panel 存在条件：iconBlock || introInner（merge 时 desc 拼入 introInner）
            bool introPanelExists = hasIcon || hasIntro || (!plan.Split && hasDesc);
            // 文本列：title div 块 + intro 段列（columnHtml 边界规则）；
            // merge 时追加 '<br><br>' 分隔 + desc 段列。
            List<NativeTooltipRun> introRuns = IntroColumnRuns(doc, introSecs);
            if (!plan.Split && hasDesc) AppendMergedDesc(introRuns, descSecs);
            List<NativeTooltipRun> descRuns = BuildColumnRuns(descSecs);

            List<VisualLine> introLines = new List<VisualLine>();
            int introTextX = pad, introTextY = pad, introTextW = 0, introPanelH = 0;
            if (introPanelExists)
            {
                // icon→text 间距仅在文本元素存在时产生（flex gap 是两子项之间）
                bool introHasText = introRuns.Count > 0;
                introTextY = pad + (hasIcon
                    ? iconBox + (introHasText ? iconGap : 0) : 0);
                introTextW = introW - pad * 2;
                introLines = WrapRuns(introRuns, introTextW, measure, lh);
                if (introLines.Count > MaxRenderedLines)
                    introLines = introLines.GetRange(0, MaxRenderedLines);
                int textH = SumHeight(introLines, lh);
                introPanelH = Math.Max(introMinH, introTextY + textH + pad);
            }

            // desc 面板（split）：inline width = estimateMainWidth 的 CSS px 结果
            // 叠加 min-width:160（均在 CSS 域），再整体 ×scale → 物理 px。
            List<VisualLine> descLines = new List<VisualLine>();
            int descPanelW = 0, descPanelH = 0, descTextW = 0;
            if (plan.Split && hasDesc)
            {
                int estCss = EstimateMainWidth(descScore, 150, DescMaxWBase);
                descPanelW = Px(Math.Max(DescMinWBase, estCss), scale);
                descTextW = descPanelW - pad * 2 - sbW;   // scrollbar-gutter:stable 恒占
                descLines = WrapRuns(descRuns, descTextW, measure, lh);
                int contentH = SumHeight(descLines, lh) + pad * 2;
                // max-height:min(70vh,520px)：vh = 视口 CSS px（innerHeight 域，
                // 不随 transform 缩放）→ 先在本地 CSS 域取 min，再整体 ×scale。
                int maxH = Px(Math.Min(DescMaxHBase,
                    vhCss * DescMaxHViewportFrac), scale);
                descPanelH = Math.Max(lhInt + pad * 2, Math.Min(contentH, maxH));
            }

            // stacked 降级：post-transform CSS px 并排总宽 > vw - 2*8 → 竖排。
            // native totalW 是物理 px（=本地×overlayScale×dpi），判定式两边 ×dpi
            // → 物理域 availW = vw_css×dpi - 16×dpi = vpW - 16×dpi。
            int availW = viewportWidthPx - (int)Math.Round(insetClient * 2 * dpiScale);
            int totalW = (introPanelExists ? introW : 0) + descPanelW;
            if (plan.Split && descPanelW > 0 && introPanelExists && totalW > availW)
            {
                plan.Stacked = true;
                // calc(100vw - 32px) 作为本地单位参与 min/max-width → 物理 ×scale。
                int colCap = Px(vwCss - StackedMarginBase, scale);
                // intro-panel: width:min(200/120, vw-32)；min-height→0
                introW = Math.Min(introW, colCap);
                introTextW = introW - pad * 2;
                introLines = WrapRuns(introRuns, Math.Max(1, introTextW), measure, lh);
                if (introLines.Count > MaxRenderedLines)
                    introLines = introLines.GetRange(0, MaxRenderedLines);
                introPanelH = introTextY + SumHeight(introLines, lh) + pad;
                // desc: inline est width 仍生效，max-width:vw-32 截顶（min-width 160 兜底）
                descPanelW = Math.Min(descPanelW, colCap);
                descPanelW = Math.Max(Px(DescMinWBase, scale), descPanelW);
                descTextW = descPanelW - pad * 2 - sbW;
                descLines = WrapRuns(descRuns, descTextW, measure, lh);
                int contentH = SumHeight(descLines, lh) + pad * 2;
                int maxH = Px(Math.Min(DescMaxHBase,
                    vhCss * DescMaxHViewportFrac), scale);
                descPanelH = Math.Max(lhInt + pad * 2, Math.Min(contentH, maxH));
            }

            // ── 组装 ──
            plan.IntroLines = introLines;
            plan.IntroLogicalLines = MergeLogicalLines(introLines);
            plan.IntroContentLeftPx = introPanelExists ? introTextX : 0;
            plan.IntroContentTopPx = introTextY;

            if (plan.Split && hasDesc)
            {
                int tipW, tipH;
                if (plan.Stacked)
                {
                    tipW = Math.Max(introPanelExists ? introW : 0, descPanelW);
                    tipH = (introPanelExists ? introPanelH : 0) + descPanelH;
                    plan.IntroPanel = introPanelExists
                        ? new Rectangle(0, 0, introW, introPanelH) : Rectangle.Empty;
                    plan.DescPanel = new Rectangle(0,
                        introPanelExists ? introPanelH : 0, descPanelW, descPanelH);
                }
                else
                {
                    tipW = (introPanelExists ? introW : 0) + descPanelW;
                    tipH = Math.Max(introPanelExists ? introPanelH : 0, descPanelH);
                    plan.IntroPanel = introPanelExists
                        ? new Rectangle(0, 0, introW, introPanelH) : Rectangle.Empty;
                    plan.DescPanel = new Rectangle(
                        introPanelExists ? introW : 0, 0, descPanelW, descPanelH);
                }
                plan.TipSize = new Size(Math.Max(1, tipW), Math.Max(1, tipH));
                plan.DescLines = descLines;
                plan.DescLogicalLines = MergeLogicalLines(descLines);
                plan.DescTotalLines = descLines.Count;
                int viewH = descPanelH - pad * 2;
                plan.DescVisibleLines = VisibleLineCount(descLines, viewH);
                plan.MaxScrollLine = MaxStartLine(descLines, viewH);
                plan.DescScrollable = plan.MaxScrollLine > 0;
                plan.DescContentLeftPx = plan.DescPanel.X + pad;
                plan.DescContentTopPx = plan.DescPanel.Y + pad;
                plan.ScrollViewportRect = new Rectangle(
                    plan.DescPanel.X + pad, plan.DescPanel.Y + pad,
                    Math.Max(1, descTextW), Math.Max(1, viewH));
                if (hasIcon && !plan.IntroPanel.IsEmpty)
                {
                    int ix = plan.IntroPanel.X + pad
                        + (introW - pad * 2 - iconBox) / 2;
                    plan.IconRect = new Rectangle(ix, pad, iconBox, iconBox);
                }
            }
            else
            {
                // merge：单 intro 面板（Web 不滚动）
                plan.IntroPanel = introPanelExists
                    ? new Rectangle(0, 0, introW, introPanelH) : Rectangle.Empty;
                plan.TipSize = new Size(
                    Math.Max(1, introPanelExists ? introW : Px(BaseNum, scale)),
                    Math.Max(1, introPanelH));
                plan.DescLines = new List<VisualLine>();
                plan.DescLogicalLines = new List<VisualLine>();
                plan.DescTotalLines = 0;
                plan.DescVisibleLines = introLines.Count;
                plan.DescScrollable = false;
                plan.MaxScrollLine = 0;
                if (hasIcon && !plan.IntroPanel.IsEmpty)
                {
                    int ix = pad + (introW - pad * 2 - iconBox) / 2;
                    plan.IconRect = new Rectangle(ix, pad, iconBox, iconBox);
                }
            }

            // ── dense 检视状态条（status 为 _el 首子节点，位于全部面板上方）──
            if (doc.Profile == NativeTooltipProfile.Dense)
                ApplyInspectionStrip(plan, measure, scale, inspectionState);
            return plan;
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
                h += l.LineHeightF > 0 ? l.LineHeightF : fallbackLh;
            // 内容包围盒须向外取整：312.5px 不能装进312px视口，
            // 否则本可完整显示的短注释会凭空获得一行滚动和检视等待。
            return (int)Math.Ceiling(h);
        }

        /// <summary>视口内可见行数：逐行浮点累加，行顶进入可视区即计
        /// （web 末行可部分可见，截断由绘制层 clip 负责）。</summary>
        private static int VisibleLineCount(IList<VisualLine> lines, int viewH)
        {
            if (lines == null || lines.Count == 0) return 0;
            float acc = 0;
            int n = 0;
            foreach (VisualLine l in lines)
            {
                if (acc >= viewH) break;
                acc += l.LineHeightF > 0 ? l.LineHeightF : l.LineHeightPx;
                n++;
            }
            return Math.Max(1, n);
        }

        /// <summary>变行高下保证末行可见的最大起始行：自尾向前浮点累加，
        /// 取首个使剩余行总高 ≤ viewH 的行索引（空列/单行超高兜底 Count-1）。</summary>
        private static int MaxStartLine(IList<VisualLine> lines, int viewH)
        {
            if (lines == null || lines.Count == 0) return 0;
            int maxStart = lines.Count;
            float acc = 0;
            for (int i = lines.Count - 1; i >= 0; i--)
            {
                VisualLine l = lines[i];
                acc += l.LineHeightF > 0 ? l.LineHeightF : l.LineHeightPx;
                if (acc > viewH) break;
                maxStart = i;
            }
            if (maxStart >= lines.Count) maxStart = lines.Count - 1;
            return Math.Max(0, maxStart);
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
            bool wrapped = lines.Count > PlainLogicalLineCount(runs);
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

        private static int PlainLogicalLineCount(List<NativeTooltipRun> runs)
        {
            int count = 0;
            bool hasText = false;
            foreach (NativeTooltipRun run in runs)
            {
                if (run == null || string.IsNullOrEmpty(run.Text)) continue;
                string t = run.Text;
                for (int i = 0; i < t.Length; i++)
                {
                    char c = t[i];
                    if (c == '\r' || c == '\n')
                    {
                        if (c == '\r' && i + 1 < t.Length && t[i + 1] == '\n') i++;
                        count++;
                        hasText = false;
                    }
                    else if (c != ' ' && c != '\t') hasText = true;
                }
            }
            return count + (hasText ? 1 : 0);
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

            // body 滚动单元：intro 行 + desc 行（各自行高）
            plan.DescLines = new List<VisualLine>();
            plan.DescLines.AddRange(introLines);
            plan.DescLines.AddRange(descLines);
            plan.IntroLines = introLines;
            plan.IntroLogicalLines = MergeLogicalLines(introLines);
            plan.DescLogicalLines = MergeLogicalLines(plan.DescLines);
            plan.DescTotalLines = plan.DescLines.Count;

            // MaxScrollLine：保证末行可见的最大起始行（变行高浮点累加）
            plan.MaxScrollLine = MaxStartLine(plan.DescLines, bodyViewH);
            plan.DescScrollable = contentH > bodyViewH && plan.MaxScrollLine > 0;
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
