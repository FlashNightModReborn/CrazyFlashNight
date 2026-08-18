using System.Collections.Generic;
using System.Text;

namespace CF7Launcher.Guardian.Hud.Loot
{
    /// <summary>
    /// 纸娃娃头像键（"纸娃娃-xxxxxxxx"）的唯一计算点（C# 单点，Web/AS2 均不重算）。
    ///
    /// 输入串 = 依次取外观元组 face,hair,mask,head,body,leg,hand,foot,neck,gender
    /// （null 归一为空串），以 \x01 连接；对其 UTF-8 字节做 FNV-1a 32bit
    /// （offset 0x811c9dc5，每字节 ^= 后 *= 0x01000193，uint 自然回绕），
    /// 输出 8 位小写 hex，加 "纸娃娃-" 前缀。
    ///
    /// 同一个键同时是 loot feed 图标 ref 与运行时缓存文件名（&lt;hex&gt;.png，
    /// DollBakeTask 落盘、LootIconCatalog 第四源读取；文件名只用 hex，前缀只进日志）。
    /// </summary>
    internal static class DollPortraitKey
    {
        internal const string Prefix = "纸娃娃-";

        /// <summary>键字段顺序（契约固定，改动即全部键失效）。</summary>
        internal static readonly string[] Fields =
        {
            "face", "hair", "mask", "head", "body",
            "leg", "hand", "foot", "neck", "gender"
        };

        /// <summary>由已归一化的元组计算完整图标键（"纸娃娃-" + 8 位小写 hex）。</summary>
        internal static string Compute(IReadOnlyDictionary<string, string> tuple)
        {
            return Prefix + ComputeHex(tuple);
        }

        /// <summary>只取 8 位小写 hex 部分（文件名用）。</summary>
        internal static string ComputeHex(IReadOnlyDictionary<string, string> tuple)
        {
            uint hash = 0x811c9dc5u;
            for (int i = 0; i < Fields.Length; i++)
            {
                if (i > 0) hash = Step(hash, 0x01);
                string value;
                if (tuple == null || !tuple.TryGetValue(Fields[i], out value) || value == null)
                    value = string.Empty;
                byte[] bytes = Encoding.UTF8.GetBytes(value);
                for (int b = 0; b < bytes.Length; b++)
                    hash = Step(hash, bytes[b]);
            }
            return hash.ToString("x8");
        }

        private static uint Step(uint hash, byte b)
        {
            unchecked
            {
                hash ^= b;
                hash *= 0x01000193u;
                return hash;
            }
        }
    }
}
