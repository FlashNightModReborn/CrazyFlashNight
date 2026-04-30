// CF7:ME — UiDataPacket 单测（C# 5）
// 覆盖 P1 perf 引入的 packet 构造分类逻辑：legacy / 标准 KV / 空 / 边界

using System.Collections.Generic;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class UiDataPacketTests
    {
        // ── 空 / null 输入：Pairs 为空数组（非 null）、IsLegacy=false ──────────────────────────────

        [Fact]
        public void Null_Raw_Yields_Empty_Pairs_Non_Legacy()
        {
            UiDataPacket pkt = new UiDataPacket(null);
            Assert.Equal("", pkt.Raw);
            Assert.NotNull(pkt.Pairs);
            Assert.Empty(pkt.Pairs);
            Assert.False(pkt.IsLegacy);
            Assert.Null(pkt.LegacyType);
            Assert.Null(pkt.LegacyFields);
        }

        [Fact]
        public void Empty_Raw_Yields_Empty_Pairs_Non_Legacy()
        {
            UiDataPacket pkt = new UiDataPacket("");
            Assert.Equal("", pkt.Raw);
            Assert.NotNull(pkt.Pairs);
            Assert.Empty(pkt.Pairs);
            Assert.False(pkt.IsLegacy);
        }

        // ── 标准 KV：单段 / 多段 ───────────────────────────────────────────────────────────────────

        [Fact]
        public void Single_Kv_Pair_Is_Not_Legacy()
        {
            // 单段（pairs.Length == 1）即便首段无 ":"，也不被识别为 legacy（>= 2 段才考虑）
            UiDataPacket pkt = new UiDataPacket("g:1234");
            Assert.False(pkt.IsLegacy);
            Assert.Single(pkt.Pairs);
            Assert.Equal("g:1234", pkt.Pairs[0]);
        }

        [Fact]
        public void Multi_Kv_With_Colons_Is_Not_Legacy()
        {
            UiDataPacket pkt = new UiDataPacket("g:1234|k:567|s:1");
            Assert.False(pkt.IsLegacy);
            Assert.Equal(3, pkt.Pairs.Length);
            Assert.Equal("g:1234", pkt.Pairs[0]);
            Assert.Equal("k:567", pkt.Pairs[1]);
            Assert.Equal("s:1", pkt.Pairs[2]);
        }

        [Fact]
        public void Single_Bare_Token_Is_Not_Legacy()
        {
            // 单段无 ":" 不会被识别为 legacy（>= 2 段才考虑）
            UiDataPacket pkt = new UiDataPacket("hello");
            Assert.False(pkt.IsLegacy);
            Assert.Single(pkt.Pairs);
        }

        // ── Legacy 格式：首段无 ":" + 总段数 >= 2 ───────────────────────────────────────────────

        [Fact]
        public void Legacy_Two_Segments_Detected()
        {
            UiDataPacket pkt = new UiDataPacket("task|新任务");
            Assert.True(pkt.IsLegacy);
            Assert.Equal("task", pkt.LegacyType);
            Assert.NotNull(pkt.LegacyFields);
            Assert.Single(pkt.LegacyFields);
            Assert.Equal("新任务", pkt.LegacyFields[0]);
        }

        [Fact]
        public void Legacy_Currency_With_Three_Fields()
        {
            UiDataPacket pkt = new UiDataPacket("currency|gold|1234|+50");
            Assert.True(pkt.IsLegacy);
            Assert.Equal("currency", pkt.LegacyType);
            Assert.Equal(3, pkt.LegacyFields.Length);
            Assert.Equal("gold", pkt.LegacyFields[0]);
            Assert.Equal("1234", pkt.LegacyFields[1]);
            Assert.Equal("+50", pkt.LegacyFields[2]);
        }

        [Fact]
        public void Legacy_Combo_With_Empty_Trailing_Field_Preserved()
        {
            // 末尾空字段保留，不裁剪
            UiDataPacket pkt = new UiDataPacket("combo|波动拳||");
            Assert.True(pkt.IsLegacy);
            Assert.Equal("combo", pkt.LegacyType);
            Assert.Equal(3, pkt.LegacyFields.Length);
            Assert.Equal("波动拳", pkt.LegacyFields[0]);
            Assert.Equal("", pkt.LegacyFields[1]);
            Assert.Equal("", pkt.LegacyFields[2]);
        }

        // ── 边界：首段含 ":" 即便后面有 "|" 也不是 legacy ──────────────────────────────────────

        [Fact]
        public void First_Segment_Has_Colon_Is_Kv_Not_Legacy()
        {
            // 首段 "type:foo" 含 ":" → 走 KV 路径，IsLegacy=false
            UiDataPacket pkt = new UiDataPacket("type:foo|extra");
            Assert.False(pkt.IsLegacy);
            Assert.Equal(2, pkt.Pairs.Length);
        }

        // ── 边界：纯 "|" 分隔符 ────────────────────────────────────────────────────────────────

        [Fact]
        public void Pipe_Only_Yields_Two_Empty_Pairs()
        {
            // "|" → split 出 ["", ""] —— 首段 "" 无 ":"，长度 == 2 → 命中 legacy 探测
            // 但 type 是 ""；下游消费者应能容忍空 type（无 widget 订阅 "" type）
            UiDataPacket pkt = new UiDataPacket("|");
            Assert.Equal(2, pkt.Pairs.Length);
            Assert.True(pkt.IsLegacy);
            Assert.Equal("", pkt.LegacyType);
            Assert.Single(pkt.LegacyFields);
            Assert.Equal("", pkt.LegacyFields[0]);
        }

        // ── ParseFrom 与 packet 共享 Pairs：行为等价于 Parse(raw) ──────────────────────────────

        [Fact]
        public void ParseFrom_Yields_Kv_Pairs_For_Standard_Payload()
        {
            UiDataPacket pkt = new UiDataPacket("g:1234|k:567|s:1");
            List<KeyValuePair<string, string>> kvs = new List<KeyValuePair<string, string>>();
            foreach (KeyValuePair<string, string> kv in UiDataPacketParser.ParseFrom(pkt))
                kvs.Add(kv);
            Assert.Equal(3, kvs.Count);
            Assert.Equal("g", kvs[0].Key);
            Assert.Equal("g:1234", kvs[0].Value); // value 是完整 "key:val" 片段
            Assert.Equal("k", kvs[1].Key);
            Assert.Equal("k:567", kvs[1].Value);
            Assert.Equal("s", kvs[2].Key);
        }

        [Fact]
        public void ParseFrom_Skips_Segments_Without_Colon()
        {
            // 包含一个无冒号段：被丢弃，与 Parse(raw) 行为等价
            UiDataPacket pkt = new UiDataPacket("g:1234|invalid|k:567");
            List<KeyValuePair<string, string>> kvs = new List<KeyValuePair<string, string>>();
            foreach (KeyValuePair<string, string> kv in UiDataPacketParser.ParseFrom(pkt))
                kvs.Add(kv);
            Assert.Equal(2, kvs.Count);
            Assert.Equal("g", kvs[0].Key);
            Assert.Equal("k", kvs[1].Key);
        }

        [Fact]
        public void ParseFrom_Null_Packet_Yields_Empty()
        {
            List<KeyValuePair<string, string>> kvs = new List<KeyValuePair<string, string>>();
            foreach (KeyValuePair<string, string> kv in UiDataPacketParser.ParseFrom(null))
                kvs.Add(kv);
            Assert.Empty(kvs);
        }

        // ── ParseFrom vs Parse(raw) 行为 1:1 等价性回归 ────────────────────────────────────────

        [Theory]
        [InlineData("")]
        [InlineData("g:1234")]
        [InlineData("g:1234|k:567|s:1")]
        [InlineData("invalid")]
        [InlineData("g:1234|invalid|k:567")]
        [InlineData("a:b:c")]                    // value 含 ":" 时 key="a"，value="a:b:c"
        public void ParseFrom_Equivalent_To_Parse(string raw)
        {
            UiDataPacket pkt = new UiDataPacket(raw);
            List<KeyValuePair<string, string>> fromPkt = new List<KeyValuePair<string, string>>();
            foreach (KeyValuePair<string, string> kv in UiDataPacketParser.ParseFrom(pkt))
                fromPkt.Add(kv);
            List<KeyValuePair<string, string>> fromRaw = new List<KeyValuePair<string, string>>();
            foreach (KeyValuePair<string, string> kv in UiDataPacketParser.Parse(raw))
                fromRaw.Add(kv);
            Assert.Equal(fromRaw.Count, fromPkt.Count);
            for (int i = 0; i < fromRaw.Count; i++)
            {
                Assert.Equal(fromRaw[i].Key, fromPkt[i].Key);
                Assert.Equal(fromRaw[i].Value, fromPkt[i].Value);
            }
        }
    }
}
