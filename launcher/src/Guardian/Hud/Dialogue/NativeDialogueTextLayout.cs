using System;
using System.Collections.Generic;
using System.Drawing;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Tooltip;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>
    /// 对话正文的纯排版器：复用原生注释的受限 HTML 展开器 → 字形序列 → 贪心折行。
    ///
    /// 与渲染解耦：measure 由调用方注入（widget 用 GDI+ MeasureString，测试可注入
    /// 确定性宽度函数）。折行规则贴近旧 Flash 文本域：
    /// - '\n'（&lt;BR&gt; 展开产物）硬断行；
    /// - CJK 逐字可断；开标点（（【《「『“‘）后不晚断、闭标点（，。：；！？、）】》”’…%）不前断
    ///   ——折行边界落在禁断对时向前回溯一字；
    /// - 连续超宽串（长拉丁/无标点）允许硬折，不允许行溢出。
    ///
    /// 字形序含 '\n' 占位（计 1 个打字节拍、宽 0），Line.Runs 只含可绘制段。
    /// 打字显示按 glyph 序截断：visibleChars 是绝对 glyph 下标阈值。
    /// </summary>
    internal static class NativeDialogueTextLayout
    {
        internal struct Glyph
        {
            internal char C;
            internal Color Color;
            internal bool Newline;
        }

        /// <summary>一行内同色连续段。GlyphStart 为段首在 glyph 序的绝对下标。</summary>
        internal sealed class Run
        {
            internal string Text;
            internal Color Color;
            internal int GlyphStart;
            /// <summary>段首在行内的序号（用于查 Line.PrefixW 得起始 x）。</summary>
            internal int LineOffset;
        }

        internal sealed class Line
        {
            internal readonly List<Run> Runs = new List<Run>();
            /// <summary>行内前缀宽（物理 px 浮点），长度 = 行可绘制 glyph 数 + 1。</summary>
            internal float[] PrefixW;
            /// <summary>行首 glyph 的绝对下标（含此前 '\n' 占位）。</summary>
            internal int GlyphStart = -1;
            /// <summary>行末 glyph 的绝对下标 + 1（本行覆盖的 glyph 区间尾）。</summary>
            internal int GlyphEnd;
            internal int GlyphCount;
            internal float WidthF;
            /// <summary>段首行缩进（局部 px；非段首行=0）。Flash TextFormat.indent 语义。</summary>
            internal float Indent;
            /// <summary>true = 本行以硬断行收尾（&lt;BR&gt;/\n/流末）。</summary>
            internal bool EndsLogicalLine;
        }

        internal sealed class Plan
        {
            internal readonly List<Line> Lines = new List<Line>();
            /// <summary>打字总节拍数 = glyph 序长度（含 '\n' 占位）。</summary>
            internal int TotalGlyphs;
            internal string SourceKey;
        }

        // 闭标点：不可出现在行首。
        private const string ClosingPunct = "，。：；！？、）】》」』’”…‰％·—ˇ‖』";
        // 开标点：不可出现在行尾。
        private const string OpeningPunct = "（【《「『“‘〈《〖〔［｛";

        internal static bool IsClosingPunct(char c)
        {
            if (ClosingPunct.IndexOf(c) >= 0) return true;
            // ASCII 闭标点（逗句号等可直接断前的安全集合）
            return c == ',' || c == '.' || c == '!' || c == '?' || c == ';' || c == ':'
                || c == ')' || c == ']' || c == '}' || c == '%' || c == '>';
        }

        internal static bool IsOpeningPunct(char c)
        {
            if (OpeningPunct.IndexOf(c) >= 0) return true;
            return c == '(' || c == '[' || c == '{' || c == '<';
        }

        /// <summary>prev→next 之间允许折行。</summary>
        internal static bool CanBreakAfter(char prev, char next)
        {
            return !IsOpeningPunct(prev) && !IsClosingPunct(next);
        }

        /// <summary>
        /// 解析 + 折行。rawText 为 AS2 正文（可含 &lt;font color&gt;/&lt;BR&gt;），
        /// charWidth 返回单字物理 px 宽（浮点）。maxWidthPx ≤ 0 返回空 Plan。
        /// </summary>
        internal static Plan Build(string rawText, int maxWidthPx,
            Func<char, float> charWidth, Color? defaultColor = null,
            bool parseMarkup = true, float firstLineIndent = 0f)
        {
            Plan plan = new Plan();
            if (charWidth == null || maxWidthPx <= 0) return plan;

            Color baseColor = defaultColor ?? Color.White;
            // parseMarkup=false：字段 html=false（如 人物名字），标签按字面渲染不剥离。
            List<NativeTooltipRun> segs = parseMarkup
                ? NativeTooltipMarkup.Flatten(rawText ?? "", baseColor, false)
                : new List<NativeTooltipRun> { new NativeTooltipRun(rawText ?? "", baseColor, false) };

            // 1) 展平成 glyph 序（'\n' 为占位 glyph）
            List<Glyph> glyphs = new List<Glyph>();
            for (int s = 0; s < segs.Count; s++)
            {
                string t = segs[s].Text;
                if (string.IsNullOrEmpty(t)) continue;
                Color color = segs[s].Color ?? baseColor;
                for (int j = 0; j < t.Length; j++)
                {
                    char c = t[j];
                    if (c == '\r') continue;
                    glyphs.Add(new Glyph { C = c, Color = color, Newline = (c == '\n') });
                }
            }
            plan.TotalGlyphs = glyphs.Count;
            if (glyphs.Count == 0) return plan;

            // 2) 逐字宽度（'\n' 宽 0）
            float[] widths = new float[glyphs.Count];
            for (int j = 0; j < glyphs.Count; j++)
                widths[j] = glyphs[j].Newline ? 0f : Math.Max(0f, charWidth(glyphs[j].C));

            // 3) 贪心折行（回溯修禁断对）。curIndent = 段首行缩进（首行与逻辑断行后的行）。
            List<int> cur = new List<int>();
            float curW = 0f;
            float curIndent = firstLineIndent;
            int i = 0;
            while (i < glyphs.Count)
            {
                Glyph g = glyphs[i];
                if (g.Newline)
                {
                    Flush(plan, glyphs, widths, cur, curW, true, curIndent);
                    cur = new List<int>();
                    curW = 0f;
                    curIndent = firstLineIndent;
                    i++;
                    continue;
                }
                if (cur.Count > 0 && curW + widths[i] > maxWidthPx - curIndent)
                {
                    // 禁断回溯：若 (cur末, i) 禁断，把 cur 末字让给下一行，重试。
                    List<int> carry = new List<int>();
                    while (cur.Count > 1
                        && !CanBreakAfter(glyphs[cur[cur.Count - 1]].C,
                            carry.Count == 0 ? g.C : glyphs[carry[0]].C))
                    {
                        int last = cur.Count - 1;
                        carry.Insert(0, cur[last]);
                        curW -= widths[cur[last]];
                        cur.RemoveAt(last);
                    }
                    Flush(plan, glyphs, widths, cur, curW, false, curIndent);
                    cur = carry;
                    curW = 0f;
                    for (int k = 0; k < cur.Count; k++) curW += widths[cur[k]];
                    curIndent = 0f;   // 软折行不产生新段首
                    continue;   // 同一 glyph 在新行重试（carry 自身仍超宽时再折）
                }
                cur.Add(i);
                curW += widths[i];
                i++;
            }
            Flush(plan, glyphs, widths, cur, curW, true, curIndent);
            return plan;
        }

        private static void Flush(Plan plan, List<Glyph> glyphs, float[] widths,
            List<int> lineIdx, float lineW, bool endsLogical, float indent)
        {
            if (lineIdx == null || lineIdx.Count == 0)
            {
                // 空行（\n 连续或流末）保留占位：占一行高度，无 run。
                if (endsLogical)
                    plan.Lines.Add(new Line { PrefixW = new float[1] });
                return;
            }
            Line line = new Line();
            line.GlyphStart = lineIdx[0];
            line.GlyphEnd = lineIdx[lineIdx.Count - 1] + 1;
            line.GlyphCount = lineIdx.Count;
            line.WidthF = lineW + indent;
            line.Indent = indent;
            line.EndsLogicalLine = endsLogical;

            float[] prefix = new float[lineIdx.Count + 1];
            for (int k = 0; k < lineIdx.Count; k++)
                prefix[k + 1] = prefix[k] + widths[lineIdx[k]];
            line.PrefixW = prefix;

            // 同色聚合为 run
            int segStart = 0;
            while (segStart < lineIdx.Count)
            {
                Color color = glyphs[lineIdx[segStart]].Color;
                int segEnd = segStart + 1;
                while (segEnd < lineIdx.Count
                    && glyphs[lineIdx[segEnd]].Color == color) segEnd++;
                System.Text.StringBuilder sb = new System.Text.StringBuilder(segEnd - segStart);
                for (int k = segStart; k < segEnd; k++)
                    sb.Append(glyphs[lineIdx[k]].C);
                line.Runs.Add(new Run
                {
                    Text = sb.ToString(),
                    Color = color,
                    GlyphStart = lineIdx[segStart],
                    LineOffset = segStart
                });
                segStart = segEnd;
            }
            plan.Lines.Add(line);
        }

        /// <summary>
        /// 打字可见窗口：visibleChars 阈值下最后一个需要显示的行下标。
        /// 用于 Flash 式自动滚底（行数超容量时只画末 capacity 行）。
        /// </summary>
        internal static int LastNeededLine(Plan plan, int visibleChars)
        {
            if (plan == null || plan.Lines.Count == 0) return 0;
            if (visibleChars <= 0) return 0;
            for (int i = plan.Lines.Count - 1; i >= 0; i--)
            {
                Line l = plan.Lines[i];
                if (l.GlyphStart >= 0 && l.GlyphStart < visibleChars) return i;
                if (l.GlyphStart < 0 && i == 0) return 0;
            }
            return plan.Lines.Count - 1;
        }
    }
}
