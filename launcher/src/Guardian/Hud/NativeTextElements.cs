using System;
using System.Globalization;

namespace CF7Launcher.Guardian.Hud
{
    internal static class NativeTextElements
    {
        // Keep UTF-16 offsets stable across display normalization and style spans.
        internal static string NormalizeDisplay(string text)
        {
            if (string.IsNullOrEmpty(text)) return string.Empty;
            char[] repaired = null;
            for (int i = 0; i < text.Length; i++)
            {
                if (!char.IsSurrogate(text[i])) continue;
                if (char.IsSurrogatePair(text, i))
                {
                    i++;
                    continue;
                }
                repaired ??= text.ToCharArray();
                repaired[i] = '\uFFFD';
            }
            return repaired == null ? text : new string(repaired);
        }

        // Every entry starts one extended grapheme cluster. The end is text.Length.
        internal static int[] Starts(string text)
        {
            return StringInfo.ParseCombiningCharacters(text ?? string.Empty);
        }

        internal static string Truncate(string text, int maxCodeUnits)
        {
            text = NormalizeDisplay(text);
            if (maxCodeUnits <= 0) return string.Empty;
            if (text.Length <= maxCodeUnits) return text;
            int offset = 0;
            while (offset < maxCodeUnits)
            {
                int end = offset + StringInfo.GetNextTextElementLength(text.AsSpan(offset));
                if (end > maxCodeUnits) break;
                offset = end;
            }
            return text.Substring(0, offset);
        }
    }
}
