// CF7:ME — UiData value 解析共享 helper（C# 5）
// P2-5：原 TopRightToolsWidget.ParseUiBoolValue / NotchToolbarWidget.ParseUiIntValue 抽出，
// 让 RightContextWidget / ComboWidget / SafeExitPanelWidget 的引用与死 widget 文件解耦。
// 行为与原实现等价：兼容 "key:val" 完整片段或裸 value。

using System;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// UiData snapshot 取出的 fullPiece（"key:val"）解析为 bool / int 的共享 helper。
    /// 与 web UiData.dispatch 同源语义。
    /// </summary>
    public static class UiValueParser
    {
        /// <summary>
        /// 解析 bool。"1" / "true" / "yes" → true；其余 → false。
        /// 输入可以是 "key:val" 完整片段（自动剥前缀）或裸 value。
        /// </summary>
        public static bool ParseUiBoolValue(string piece)
        {
            if (string.IsNullOrEmpty(piece)) return false;
            int colon = piece.IndexOf(':');
            string val = colon >= 0 ? piece.Substring(colon + 1) : piece;
            if (string.IsNullOrEmpty(val)) return false;
            if (val == "1") return true;
            return val.Equals("true", StringComparison.OrdinalIgnoreCase)
                || val.Equals("yes", StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// 解析 int；解析失败返回 fallback。
        /// 输入可以是 "key:val" 完整片段或裸 value。
        /// </summary>
        public static int ParseUiIntValue(string piece, int fallback)
        {
            if (string.IsNullOrEmpty(piece)) return fallback;
            int colon = piece.IndexOf(':');
            string val = colon >= 0 ? piece.Substring(colon + 1) : piece;
            int parsed;
            if (int.TryParse(val, System.Globalization.NumberStyles.Integer,
                             System.Globalization.CultureInfo.InvariantCulture, out parsed))
                return parsed;
            return fallback;
        }
    }
}
