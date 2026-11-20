using System;
using System.Collections.Generic;
using System.Drawing;
using System.Text;
using CF7Launcher.Guardian.Hud.Tooltip;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>对白独有的段首缩进、中文禁断及硬换行。索引以显示串的扩展字素为单位。</summary>
    internal static class NativeDialogueTextLayout
    {
        internal sealed class Run
        {
            internal const string MissingMark = "□";
            internal string Text;
            internal bool GdiRefused;
            internal string PaintText => GdiRefused ? MissingMark : Text;
            internal Color Color;
            internal int FirstElement;
            internal int[] Offsets; // 相对于 Text 的 UTF-16 边界，包括末端
            internal float X;
            internal float Width;
        }

        internal sealed class Line
        {
            internal List<Run> Runs;
            internal int FirstElement;
            internal int EndElement;
            internal float WidthF;
        }

        internal sealed class Plan
        {
            internal readonly List<Line> Lines = new List<Line>();
            internal int TotalElements;
            internal IEnumerator<Line> Pending;
            internal Action<Line> CreateRuns;

            internal Line GetDrawableLine(int index)
            {
                var line = Lines[index];
                if (line.Runs == null) CreateRuns(line);
                return line;
            }

            internal bool PrepareLine(int index)
            {
                while (Lines.Count <= index && Pending != null)
                {
                    if (Pending.MoveNext()) Lines.Add(Pending.Current);
                    else { Pending.Dispose(); Pending = null; }
                }
                return index < Lines.Count;
            }

            internal void PrepareThrough(int visible)
            {
                while (Pending != null && (Lines.Count == 0 || Lines[^1].EndElement < visible))
                    PrepareLine(Lines.Count);
            }
        }

        private const string ClosingPunct = "，。：；！？、）】》」』’”…‰％·—ˇ‖,!.?;:)]}%>";
        private const string OpeningPunct = "（【《「『“‘〈〖〔［｛([{<";

        // 统一展开后分段，跨颜色的一个字素继承其首码元的颜色。保留原有 CR 忽略、LF 占一拍的语义。
        private sealed class DisplayText
        {
            internal readonly string Text;
            internal readonly int[] Offsets;
            internal readonly Color[] Colors;
            internal readonly int[] StyleEnds;

            internal DisplayText(List<NativeTooltipRun> spans, Color defaultColor)
            {
                var text = new StringBuilder();
                var ends = new List<int>();
                var colors = new List<Color>();
                foreach (var span in spans)
                {
                    if (string.IsNullOrEmpty(span.Text)) continue;
                    text.Append(span.Text.Replace("\r", ""));
                    ends.Add(text.Length);
                    colors.Add(span.Color ?? defaultColor);
                }
                Text = NativeTextElements.NormalizeDisplay(text.ToString());
                int[] starts = NativeTextElements.Starts(Text);
                Colors = new Color[starts.Length];
                StyleEnds = new int[starts.Length];
                Offsets = new int[starts.Length + 1];
                starts.CopyTo(Offsets, 0);
                Offsets[starts.Length] = Text.Length;
                int style = 0;
                for (int i = 0; i < starts.Length; i++)
                {
                    while (starts[i] >= ends[style]) style++;
                    Colors[i] = colors[style];
                }
                for (int i = starts.Length - 1; i >= 0; i--)
                    StyleEnds[i] = i + 1 < starts.Length && Colors[i].ToArgb() == Colors[i + 1].ToArgb()
                        ? StyleEnds[i + 1] : i + 1;
            }

            internal string Slice(int first, int end)
            {
                return Text.Substring(Offsets[first], Offsets[end] - Offsets[first]);
            }

            internal char LeadingChar(int element) => Text[Offsets[element]];
        }

        internal static Plan Build(string rawText, int maxWidthPx, Func<string, float> measure,
            Color? defaultColor = null, bool parseMarkup = true, float firstLineIndent = 0f, bool deferLines = false)
        {
            var plan = new Plan();
            if (measure == null || maxWidthPx <= 0) return plan;
            var color = defaultColor ?? Color.White;
            var spans = parseMarkup ? NativeTooltipMarkup.Flatten(rawText ?? "", color, false)
                : new List<NativeTooltipRun> { new NativeTooltipRun(rawText ?? "", color, false) };
            var source = new DisplayText(spans, color);
            plan.TotalElements = source.Colors.Length;
            if (plan.TotalElements == 0) return plan;

            var widths = new RunMeasure(measure);
            plan.Pending = Wrap(source, maxWidthPx, firstLineIndent, widths).GetEnumerator();
            plan.CreateRuns = line => MakeDrawable(source, line, widths);
            if (!deferLines)
            {
                plan.PrepareLine(int.MaxValue);
                for (int i = 0; i < plan.Lines.Count; i++) plan.GetDrawableLine(i);
            }
            return plan;
        }

        // 索引在采用时一次冻结。长文只展开用户看到的行，已展开的几何随本句复用。
        private static IEnumerable<Line> Wrap(DisplayText source, int maxWidthPx, float firstLineIndent, RunMeasure measure)
        {
            int paragraphStart = 0;
            for (int i = 0; i <= source.Colors.Length; i++)
            {
                if (i < source.Colors.Length && source.LeadingChar(i) != '\n') continue;
                if (i == paragraphStart)
                    yield return new Line { FirstElement = i, EndElement = i };
                int lineStart = paragraphStart;
                while (lineStart < i)
                {
                    float indent = lineStart == paragraphStart ? firstLineIndent : 0;
                    int end = FitLine(source, lineStart, i, maxWidthPx - indent, measure);
                    if (end < i)
                    {
                        // 禁断标点向下行回退；一个超宽字素本身仍完整保留。
                        while (end > lineStart + 1 && (OpeningPunct.IndexOf(source.LeadingChar(end - 1)) >= 0
                            || ClosingPunct.IndexOf(source.LeadingChar(end)) >= 0))
                            end--;
                    }
                    yield return new Line { FirstElement = lineStart, EndElement = end, WidthF = indent };
                    lineStart = end;
                }
                paragraphStart = i + 1;
            }
        }

        // 仅布局期间保留本句的少量重复 run 宽度，完整字符串和同一 font/format 是键的含义。
        // 估计值只选试量位置，折行必须由完整 run 的真实宽度决定。
        private sealed class RunMeasure
        {
            private readonly Func<string, float> _measure;
            private readonly Dictionary<string, float> _recent = new Dictionary<string, float>(StringComparer.Ordinal);
            internal float MeanAdvance = 12;
            private string _refused;

            internal RunMeasure(Func<string, float> measure) { _measure = measure; }
            internal float Width(string text, int elements)
            {
                if (text == _refused) return float.PositiveInfinity;
                if (!_recent.TryGetValue(text, out float width))
                {
                    width = _measure(text);
                    if (float.IsPositiveInfinity(width)) _refused = text;
                    if (text.Length <= 128)
                    {
                        if (_recent.Count == 128) _recent.Clear();
                        _recent.Add(text, width);
                    }
                }
                if (width > 0 && float.IsFinite(width)) MeanAdvance = width / elements;
                return width;
            }
        }

        private static int FitLine(DisplayText source, int first, int end, float available, RunMeasure measure)
        {
            int start = first;
            while (start < end)
            {
                int limit = Math.Min(source.StyleEnds[start], end) - start;
                int fit = 0, over = limit + 1;
                // 先按最近实际 advance 估算。在已知能容纳/不能容纳的数目之间缩小区间。
                int trial = (int)Math.Clamp(available / measure.MeanAdvance, 1, limit);
                float width = 0;
                for (int tries = 0; over - fit > 1; tries++)
                {
                    width = measure.Width(source.Slice(start, start + trial), trial);
                    if (width <= available) fit = trial;
                    else over = trial;
                    if (fit == limit || over - fit == 1) break;
                    if (tries >= 2 && over <= limit)
                        trial = fit + (over - fit) / 2;
                    else
                    {
                        // 零宽字素串逐步倍增，不反复测整段剩余正文。
                        float estimate = width > 0 ? trial * (available / width) : trial * 2f;
                        int ceiling = over <= limit ? over - 1 : Math.Min(limit, trial + Math.Max(1, trial));
                        trial = (int)Math.Clamp(estimate, fit + 1, ceiling);
                    }
                }
                if (fit < limit) return Math.Max(first + 1, start + fit);
                start += fit;
                available -= width;
            }
            return end;
        }

        // 跳到末尾时，中间未浏览行只需确定断点；仅为实际可见行分配字符串、UTF-16 range 与绘制坐标。
        private static void MakeDrawable(DisplayText source, Line line, RunMeasure measure)
        {
            int first = line.FirstElement, end = line.EndElement;
            line.Runs = new List<Run>();
            while (first < end)
            {
                int next = Math.Min(source.StyleEnds[first], end);
                string text = source.Slice(first, next);
                float width = measure.Width(text, next - first);
                // GDI+ 可能拒绝很长的合法串。先缩短同色 run，但决不从一个 EGC 内部切分。
                while (float.IsPositiveInfinity(width) && next - first > 1)
                {
                    next = first + (next - first) / 2;
                    text = source.Slice(first, next);
                    width = measure.Width(text, next - first);
                }
                bool refused = float.IsPositiveInfinity(width);
                if (refused)
                {
                    width = measure.Width(Run.MissingMark, 1);
                    if (!float.IsFinite(width)) throw new InvalidOperationException("GDI+ cannot measure the missing-glyph mark.");
                }
                int[] offsets = new int[next - first + 1];
                for (int i = first; i <= next; i++) offsets[i - first] = source.Offsets[i] - source.Offsets[first];
                line.Runs.Add(new Run { Text = text, GdiRefused = refused, FirstElement = first, Color = source.Colors[first],
                    Offsets = offsets, X = line.WidthF, Width = width });
                line.WidthF += width;
                first = next;
            }
        }

        internal static int LastNeededLine(Plan plan, int visibleElements)
        {
            if (plan == null || visibleElements <= 0) return 0;
            plan.PrepareThrough(visibleElements);
            if (plan.Lines.Count == 0) return 0;
            int lo = 0, hi = plan.Lines.Count;
            while (hi - lo > 1)
            {
                int mid = lo + (hi - lo) / 2;
                if (plan.Lines[mid].FirstElement < visibleElements) lo = mid;
                else hi = mid;
            }
            return lo;
        }
    }
}
