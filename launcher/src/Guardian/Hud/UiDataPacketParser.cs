using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 解析过一次的 UiData 包。tee 路径上 webOverlay / notchOverlay / nativeHud 三方共享，
    /// 避免每方各自再 Split('|')（旧实现：60s/15K UiData 包 × 3 split = 45K 字符串数组分配）。
    ///
    /// 字段语义：
    ///   Raw          原始 payload（透传给 web ExecScript / 旧版兜底）。
    ///   Pairs        Split('|') 一次得到；段顺序与 raw 一致。
    ///   IsLegacy     首段无 ':' 且总段数 ≥ 2 时为 true（与 web UiData.dispatch 同源探测）。
    ///   LegacyType   IsLegacy=true 时取首段；否则 null。
    ///   LegacyFields IsLegacy=true 时取剩余段；否则 null。
    /// </summary>
    public sealed class UiDataPacket
    {
        public readonly string Raw;
        public readonly string[] Pairs;
        public readonly bool IsLegacy;
        public readonly string LegacyType;
        public readonly string[] LegacyFields;

        private static readonly string[] EmptyPairs = new string[0];

        public UiDataPacket(string raw)
        {
            Raw = raw == null ? "" : raw;
            Pairs = string.IsNullOrEmpty(raw) ? EmptyPairs : raw.Split('|');
            if (Pairs.Length >= 2 && Pairs[0] != null && Pairs[0].IndexOf(':') < 0)
            {
                IsLegacy = true;
                LegacyType = Pairs[0];
                LegacyFields = new string[Pairs.Length - 1];
                Array.Copy(Pairs, 1, LegacyFields, 0, LegacyFields.Length);
            }
        }
    }

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
        /// <summary>
        /// 从已解析的 packet 复用 Pairs 产出 KV 序列；与 Parse(raw) 行为等价但零额外 split。
        /// </summary>
        public static IEnumerable<KeyValuePair<string, string>> ParseFrom(UiDataPacket pkt)
        {
            if (pkt == null) yield break;
            string[] pairs = pkt.Pairs;
            if (pairs == null) yield break;
            for (int i = 0; i < pairs.Length; i++)
            {
                string seg = pairs[i];
                if (seg == null) continue;
                int colon = seg.IndexOf(':');
                if (colon > 0)
                    yield return new KeyValuePair<string, string>(seg.Substring(0, colon), seg);
            }
        }

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
