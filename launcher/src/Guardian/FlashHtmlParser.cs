using System;
using System.Collections.Generic;
using System.Drawing;
using System.Text.RegularExpressions;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Flash htmlText 子集解析器。
    /// 处理 &lt;font color='#RRGGBB'&gt;、&lt;BR&gt;，剥离其他 HTML 标签。
    /// 可复用于所有需要渲染 Flash HTML 文本的 C# UI 组件。
    /// </summary>
    public static class FlashHtmlParser
    {
        public struct TextSegment
        {
            public string Text;
            public Color Color;
        }

        private static readonly Regex FontColorRegex = new Regex(
            @"<font\s+color=['""]?#([0-9A-Fa-f]{6})['""]?\s*>",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex FontCloseRegex = new Regex(
            @"</font\s*>",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex HtmlTagRegex = new Regex(
            @"<[^>]+>",
            RegexOptions.Compiled);

        /// <summary>
        /// 解析 Flash htmlText 子集为带颜色的文本段列表。
        /// &lt;BR&gt; 替换为 replaceChar（默认空格），&lt;font color&gt; 提取颜色，其他标签剥离。
        /// </summary>
        public static List<TextSegment> Parse(string raw, string brReplacement)
        {
            List<TextSegment> result = new List<TextSegment>();
            if (string.IsNullOrEmpty(raw))
            {
                result.Add(new TextSegment { Text = "", Color = Color.White });
                return result;
            }

            string text = Regex.Replace(raw, @"<BR\s*/?>", brReplacement ?? " ",
                RegexOptions.IgnoreCase);

            Color currentColor = Color.White;
            Stack<Color> colorStack = new Stack<Color>();
            int pos = 0;

            while (pos < text.Length)
            {
                Match fontOpen = FontColorRegex.Match(text, pos);
                Match fontClose = FontCloseRegex.Match(text, pos);

                int nextOpen = fontOpen.Success ? fontOpen.Index : int.MaxValue;
                int nextClose = fontClose.Success ? fontClose.Index : int.MaxValue;
                int nextTag = Math.Min(nextOpen, nextClose);

                Match anyTag = HtmlTagRegex.Match(text, pos);
                int nextAny = anyTag.Success ? anyTag.Index : int.MaxValue;
                int nextEvent = Math.Min(nextTag, nextAny);

                if (nextEvent == int.MaxValue)
                {
                    string remainder = text.Substring(pos);
                    if (remainder.Length > 0)
                        result.Add(new TextSegment { Text = remainder, Color = currentColor });
                    break;
                }

                if (nextEvent > pos)
                {
                    string before = text.Substring(pos, nextEvent - pos);
                    if (before.Length > 0)
                        result.Add(new TextSegment { Text = before, Color = currentColor });
                }

                if (nextEvent == nextOpen && fontOpen.Success)
                {
                    colorStack.Push(currentColor);
                    string hex = fontOpen.Groups[1].Value;
                    try
                    {
                        int r = Convert.ToInt32(hex.Substring(0, 2), 16);
                        int g = Convert.ToInt32(hex.Substring(2, 2), 16);
                        int b = Convert.ToInt32(hex.Substring(4, 2), 16);
                        currentColor = Color.FromArgb(r, g, b);
                    }
                    catch { }
                    pos = fontOpen.Index + fontOpen.Length;
                }
                else if (nextEvent == nextClose && fontClose.Success)
                {
                    if (colorStack.Count > 0)
                        currentColor = colorStack.Pop();
                    else
                        currentColor = Color.White;
                    pos = fontClose.Index + fontClose.Length;
                }
                else if (anyTag.Success && anyTag.Index == nextEvent)
                {
                    pos = anyTag.Index + anyTag.Length;
                }
            }

            if (result.Count == 0)
                result.Add(new TextSegment { Text = "", Color = Color.White });

            return result;
        }

        /// <summary>
        /// 将 segments 拼接为纯文本（用于测量、日志等）。
        /// </summary>
        public static string ToPlainText(List<TextSegment> segments)
        {
            string result = "";
            for (int i = 0; i < segments.Count; i++)
                result += segments[i].Text;
            return result;
        }
    }
}
