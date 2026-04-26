using System.Collections.Generic;
using System.Linq;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class UiDataPacketParserTests
    {
        [Fact]
        public void NullOrEmpty_YieldsNothing()
        {
            Assert.Empty(UiDataPacketParser.Parse(null));
            Assert.Empty(UiDataPacketParser.Parse(""));
        }

        [Fact]
        public void SingleKv_KeyAndFullPiece()
        {
            var pairs = UiDataPacketParser.Parse("g:1234").ToList();
            Assert.Single(pairs);
            Assert.Equal("g", pairs[0].Key);
            // value 是完整 "key:val" 片段，与 WebOverlayForm._uiDataSnapshot 形态一致
            Assert.Equal("g:1234", pairs[0].Value);
        }

        [Fact]
        public void MultipleKv_AllParsed()
        {
            var pairs = UiDataPacketParser.Parse("g:1234|k:567|p:1").ToList();
            Assert.Equal(3, pairs.Count);
            Assert.Equal("g", pairs[0].Key);
            Assert.Equal("g:1234", pairs[0].Value);
            Assert.Equal("k", pairs[1].Key);
            Assert.Equal("k:567", pairs[1].Value);
            Assert.Equal("p", pairs[2].Key);
            Assert.Equal("p:1", pairs[2].Value);
        }

        [Fact]
        public void SegmentWithoutColon_Skipped()
        {
            // 旧格式占位段无冒号，应丢弃
            var pairs = UiDataPacketParser.Parse("legacy|g:42|noColon|k:7").ToList();
            Assert.Equal(2, pairs.Count);
            Assert.Equal("g", pairs[0].Key);
            Assert.Equal("k", pairs[1].Key);
        }

        [Fact]
        public void ColonInValue_OnlyFirstColonSplits()
        {
            // 形如 "bgm:title:subtitle"——key="bgm"，fullPiece 完整保留
            var pairs = UiDataPacketParser.Parse("bgm:title:subtitle").ToList();
            Assert.Single(pairs);
            Assert.Equal("bgm", pairs[0].Key);
            Assert.Equal("bgm:title:subtitle", pairs[0].Value);
        }

        [Fact]
        public void EmptyKeySegment_Skipped()
        {
            // ":val" 不是有效 KV（IndexOf > 0 排除）
            var pairs = UiDataPacketParser.Parse(":val|g:1").ToList();
            Assert.Single(pairs);
            Assert.Equal("g", pairs[0].Key);
        }

        // ── TryParseLegacy：旧版 (type|f1|f2) 格式探测 ──

        [Fact]
        public void TryParseLegacy_NullOrEmpty_False()
        {
            string type; string[] fields;
            Assert.False(UiDataPacketParser.TryParseLegacy(null, out type, out fields));
            Assert.Null(type); Assert.Null(fields);
            Assert.False(UiDataPacketParser.TryParseLegacy("", out type, out fields));
            Assert.Null(type); Assert.Null(fields);
        }

        [Fact]
        public void TryParseLegacy_KvFormat_NotLegacy()
        {
            string type; string[] fields;
            Assert.False(UiDataPacketParser.TryParseLegacy("g:1234", out type, out fields));
            Assert.False(UiDataPacketParser.TryParseLegacy("g:1234|k:5", out type, out fields));
        }

        [Fact]
        public void TryParseLegacy_SingleSegmentWithoutColon_NotLegacy()
        {
            // 第一段无 ":" 但只有一段不视为 legacy（pairs.Length < 2）
            string type; string[] fields;
            Assert.False(UiDataPacketParser.TryParseLegacy("orphan", out type, out fields));
        }

        [Fact]
        public void TryParseLegacy_TaskName_TypeAndFields()
        {
            string type; string[] fields;
            Assert.True(UiDataPacketParser.TryParseLegacy("task|拯救公主", out type, out fields));
            Assert.Equal("task", type);
            Assert.Equal(new[] { "拯救公主" }, fields);
        }

        [Fact]
        public void TryParseLegacy_AnnounceMultiField_AllFieldsPreserved()
        {
            string type; string[] fields;
            Assert.True(UiDataPacketParser.TryParseLegacy("announce|系统公告|额外字段", out type, out fields));
            Assert.Equal("announce", type);
            Assert.Equal(new[] { "系统公告", "额外字段" }, fields);
        }

        [Fact]
        public void TryParseLegacy_TypeWithColon_NotLegacy()
        {
            // 第一段含 ":" 即视为 KV 格式不走 legacy
            string type; string[] fields;
            Assert.False(UiDataPacketParser.TryParseLegacy("g:1|x|y", out type, out fields));
        }

        [Fact]
        public void TryParseLegacy_EmptyFields_PreservedAsEmpty()
        {
            // "task|" → fields = [""]
            string type; string[] fields;
            Assert.True(UiDataPacketParser.TryParseLegacy("task|", out type, out fields));
            Assert.Equal("task", type);
            Assert.Equal(new[] { "" }, fields);
        }
    }
}
