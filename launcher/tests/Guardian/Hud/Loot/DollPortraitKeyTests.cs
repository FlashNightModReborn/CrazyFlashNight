using System.Collections.Generic;
using Xunit;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    /// <summary>
    /// 纸娃娃键（DollPortraitKey，FNV-1a 32bit → "纸娃娃-" + 8 位小写 hex）单测。
    /// 锚定值由独立 Python 参考实现（同一 FNV-1a / \x01 连接 / UTF-8 字节定义）
    /// 交叉计算得出，作为跨实现一致性证据：
    ///   t1（女 tuple）→ 8a44ae89；空元组 → bc9f7804；t4（男 全字段）→ bf1797ea。
    /// </summary>
    public class DollPortraitKeyTests
    {
        private static Dictionary<string, string> Tuple(
            string face = "", string hair = "", string mask = "", string head = "",
            string body = "", string leg = "", string hand = "", string foot = "",
            string neck = "", string gender = "")
        {
            return new Dictionary<string, string>
            {
                { "face", face }, { "hair", hair }, { "mask", mask },
                { "head", head }, { "body", body }, { "leg", leg },
                { "hand", hand }, { "foot", foot }, { "neck", neck },
                { "gender", gender }
            };
        }

        [Fact]
        public void Compute_FixedFemaleTuple_AnchoredHex()
        {
            var t = Tuple(
                face: "女变装-基本脸型",
                hair: "发型-女式-玫红色马尾",
                body: "佣兵-战术背心",
                gender: "女");
            Assert.Equal("纸娃娃-8a44ae89", DollPortraitKey.Compute(t));
        }

        [Fact]
        public void Compute_FixedMaleFullTuple_AnchoredHex()
        {
            var t = Tuple(
                face: "男变装-基本脸型",
                mask: "面具-劫案",
                head: "佣兵-贝雷帽",
                body: "佣兵-战术背心",
                leg: "佣兵-战术裤",
                hand: "佣兵-战术手套",
                foot: "佣兵-作战靴",
                gender: "男");
            Assert.Equal("纸娃娃-bf1797ea", DollPortraitKey.Compute(t));
        }

        [Fact]
        public void Compute_EmptyTuple_AnchoredHex()
        {
            Assert.Equal("纸娃娃-bc9f7804", DollPortraitKey.Compute(Tuple()));
            // null 元组与全空元组等价（字段全部归一为 ""）
            Assert.Equal("纸娃娃-bc9f7804", DollPortraitKey.Compute(null));
            Assert.Equal("纸娃娃-bc9f7804",
                DollPortraitKey.Compute(new Dictionary<string, string>()));
        }

        [Fact]
        public void Compute_NullAndMissingFields_NormalizeToEmpty()
        {
            var withNulls = new Dictionary<string, string>
            {
                { "face", null }, { "hair", "发型-女式-玫红色马尾" },
                { "gender", "女" }
            };
            var withEmpty = new Dictionary<string, string>
            {
                { "face", "" }, { "hair", "发型-女式-玫红色马尾" },
                { "gender", "女" }
            };
            var onlySet = new Dictionary<string, string>
            {
                { "hair", "发型-女式-玫红色马尾" },
                { "gender", "女" }
            };
            Assert.Equal(DollPortraitKey.Compute(withEmpty), DollPortraitKey.Compute(withNulls));
            Assert.Equal(DollPortraitKey.Compute(withEmpty), DollPortraitKey.Compute(onlySet));
        }

        [Fact]
        public void Compute_FieldOrderSensitive()
        {
            // 同一字符串落在不同字段（\x01 连接位置不同）必须产生不同键
            Assert.NotEqual(
                DollPortraitKey.Compute(Tuple(face: "x")),
                DollPortraitKey.Compute(Tuple(hair: "x")));
            Assert.NotEqual(
                DollPortraitKey.Compute(Tuple(head: "佣兵-贝雷帽")),
                DollPortraitKey.Compute(Tuple(body: "佣兵-贝雷帽")));
        }

        [Fact]
        public void Compute_Format_PrefixPlusEightLowerHex()
        {
            string key = DollPortraitKey.Compute(Tuple(gender: "男"));
            Assert.StartsWith("纸娃娃-", key);
            string hex = key.Substring("纸娃娃-".Length);
            Assert.Equal(8, hex.Length);
            Assert.Matches("^[0-9a-f]{8}$", hex);
        }
    }
}
