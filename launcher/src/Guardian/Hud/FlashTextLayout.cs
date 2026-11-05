using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>彩色消息共用的测量/换行结果；以字素为边界，绘制不再另做逐段排版。</summary>
    internal sealed class FlashTextLayout
    {
        internal readonly record struct Run(string Text, Color Color, float X, float Y);
        internal List<Run> Runs { get; } = new();
        internal int Height { get; private set; }
        internal int Width { get; private set; }

        internal static FlashTextLayout Measure(Graphics g, Font font,
            IReadOnlyList<FlashHtmlParser.TextSegment> segments, int width, StringFormat format)
        {
            var result = new FlashTextLayout();
            float lineHeight = (float)Math.Ceiling(font.GetHeight(g));
            float x = 0, y = 0, widest = 0;
            // 留出阴影和抗锯齿的一个像素，不让行末字形进入下一分区。
            float availableWidth = Math.Max(1, width - 2);
            foreach (var segment in segments)
            {
                string[] lines = (segment.Text ?? "").Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
                for (int line = 0; line < lines.Length; line++)
                {
                    string text = lines[line];
                    int[] starts = StringInfo.ParseCombiningCharacters(text);
                    int first = 0;
                    while (first < starts.Length)
                    {
                        int low = 0, high = starts.Length - first;
                        while (low < high)
                        {
                            int count = (low + high + 1) / 2;
                            int end = first + count < starts.Length ? starts[first + count] : text.Length;
                            float measured = g.MeasureString(text.Substring(starts[first], end - starts[first]), font, PointF.Empty, format).Width;
                            if (measured <= availableWidth - x) low = count; else high = count - 1;
                        }
                        if (low == 0 && x > 0) { widest = Math.Max(widest, x); x = 0; y += lineHeight; continue; }
                        int take = Math.Max(1, low);
                        int stop = first + take < starts.Length ? starts[first + take] : text.Length;
                        string run = text.Substring(starts[first], stop - starts[first]);
                        result.Runs.Add(new Run(run, segment.Color, x, y));
                        x += g.MeasureString(run, font, PointF.Empty, format).Width;
                        widest = Math.Max(widest, x);
                        first += take;
                        if (first < starts.Length) { x = 0; y += lineHeight; }
                    }
                    if (line + 1 < lines.Length) { x = 0; y += lineHeight; }
                }
            }
            result.Width = Math.Min(width, (int)Math.Ceiling(widest));
            result.Height = Math.Max(1, (int)Math.Ceiling(y + lineHeight));
            return result;
        }
    }
}
