using System;
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

        /// <summary>
        /// 旧版（非 KV）格式探测：与 web UiData.dispatch 同源——第一段不含 ":" 且总段数 ≥ 2 视为
        /// "type|field1|field2|..." 一次性事件。当前在用 type：combo / currency / task / announce。
        ///
        /// 命中时 type 取首段，fields 取其余段（保留空字符串，不裁剪）。返回 false 时 type/fields 输出 null。
        /// </summary>
        public static bool TryParseLegacy(string payload, out string type, out string[] fields)
        {
            type = null;
            fields = null;
            if (string.IsNullOrEmpty(payload)) return false;
            string[] pairs = payload.Split('|');
            if (pairs.Length < 2) return false;
            if (pairs[0] == null || pairs[0].IndexOf(':') >= 0) return false;
            type = pairs[0];
            fields = new string[pairs.Length - 1];
            Array.Copy(pairs, 1, fields, 0, fields.Length);
            return true;
        }
    }
}
