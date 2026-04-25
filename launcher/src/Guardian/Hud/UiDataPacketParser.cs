using System.Collections.Generic;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// UiData 合批包解析。共享 helper 避免 WebOverlayForm 与 NativeHudOverlay 漂移。
    ///
    /// 包格式: "key:val|key:val|..."
    /// - 各段以 '|' 分隔
    /// - 每段找首个 ':'，前缀作 key
    /// - 无冒号的段被丢弃（旧格式占位）
    /// - 输出 (key, fullPiece) 对，fullPiece 是包含 key:val 的完整字符串，与 WebOverlayForm._uiDataSnapshot 存的形态一致
    /// </summary>
    public static class UiDataPacketParser
    {
        public static IEnumerable<KeyValuePair<string, string>> Parse(string payload)
        {
            if (string.IsNullOrEmpty(payload)) yield break;
            string[] pairs = payload.Split('|');
            for (int i = 0; i < pairs.Length; i++)
            {
                string seg = pairs[i];
                if (seg == null) continue;
                int colon = seg.IndexOf(':');
                if (colon > 0)
                    yield return new KeyValuePair<string, string>(seg.Substring(0, colon), seg);
            }
        }
    }
}
