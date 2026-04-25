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
    }
}
