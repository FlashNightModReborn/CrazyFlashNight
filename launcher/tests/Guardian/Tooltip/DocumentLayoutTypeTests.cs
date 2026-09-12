using CF7Launcher.Guardian.Hud.Tooltip;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Tooltip
{
    public class DocumentLayoutTypeTests
    {
        [Theory]
        [InlineData("wide")]
        [InlineData("narrow")]
        public void LayoutTypeSurvivesHostSanitizationAndNativeParsing(string layoutType)
        {
            var wire = new JObject { ["version"] = 1, ["title"] = "同一物品图标", ["layoutType"] = layoutType };
            Assert.True(TooltipDocumentSanitizer.TrySanitize(wire, out var sanitized));
            Assert.Equal(layoutType, (string)sanitized["layoutType"]);
            var document = NativeTooltipDocument.FromPayload(sanitized);
            Assert.NotNull(document);
            Assert.Equal(layoutType, document.LayoutType);
        }

        [Fact]
        public void InvalidLayoutDoesNotPassTheHostWhitelist()
        {
            var wire = new JObject { ["version"] = 1, ["title"] = "材料", ["layoutType"] = new JObject { ["width"] = 999999 } };
            Assert.True(TooltipDocumentSanitizer.TrySanitize(wire, out var sanitized));
            Assert.Null(sanitized["layoutType"]);
            Assert.Equal("wide", NativeTooltipDocument.FromPayload(sanitized).LayoutType);
        }
        [Theory]
        [InlineData("<font color='#000000' size='15'>黑字</font>", 0)]
        [InlineData("<font face='fixedsys' color=#aabbcc size='15'>字</font>", 0xAABBCC)]
        public void LegacyColorSurvivesAdjacentFontAttributes(string html, int rgb)
        {
            var wire = new JObject { ["version"] = 1, ["sections"] = new JArray(
                new JObject { ["role"] = "body", ["runs"] = new JArray(new JObject { ["text"] = html }) }) };
            var doc = NativeTooltipDocument.FromLegacyHtmlDocument(wire);
            Assert.Equal(rgb, doc.Sections[0].Runs[0].Color.Value.ToArgb() & 0xFFFFFF);
        }
    }

    /// <summary>
    /// document v1 可选 run 样式（italic/underline/fontSize/fontFace）：
    /// wire → sanitizer → NativeTooltipDocument 解析全链、legacy HTML 展开、构造兼容。
    /// 语义对齐迁移前 Web convertAS2Html（tooltip.js as2FontStyle）。
    /// </summary>
    public class DocumentRunStyleTests
    {
        private static JObject DocWithRuns(params object[] runs)
        {
            var arr = new JArray();
            foreach (object r in runs) arr.Add(r is string ? new JValue((string)r) : (JToken)(JObject)r);
            return new JObject
            {
                ["version"] = 1,
                ["sections"] = new JArray(new JObject { ["role"] = "body", ["runs"] = arr })
            };
        }

        private static NativeTooltipDocument LegacyDoc(string html)
        {
            return NativeTooltipDocument.FromLegacyHtmlDocument(DocWithRuns(
                new JObject { ["text"] = html }));
        }

        [Fact]
        public void RunStyleKeysSurviveSanitizeAndParse()
        {
            // wire → TrySanitize → FromPayload 全链
            var wire = DocWithRuns(new JObject
            {
                ["text"] = "样式",
                ["italic"] = true,
                ["underline"] = true,
                ["fontSize"] = 15,
                ["fontFace"] = "ms mincho",
                ["color"] = "#abc"
            });
            Assert.True(TooltipDocumentSanitizer.TrySanitize(wire, out var sanitized));
            var doc = NativeTooltipDocument.FromPayload(sanitized);
            Assert.NotNull(doc);
            NativeTooltipRun run = doc.Sections[0].Runs[0];
            Assert.True(run.Italic);
            Assert.True(run.Underline);
            Assert.Equal(15, run.FontSize);
            Assert.Equal("ms mincho", run.FontFace);
            Assert.Equal(0xAABBCC, run.Color.Value.ToArgb() & 0xFFFFFF); // 3 位 hex 展开
        }

        [Fact]
        public void RunStyleKeysParseDirectWithoutSanitizer()
        {
            // 不经 sanitizer 的容错读取（诊断/测试入口直喂 document）
            var wire = DocWithRuns(new JObject
            {
                ["text"] = "x",
                ["italic"] = "yes",            // 非 bool → false
                ["underline"] = 1,             // 整数容错 → true（ReadBool 既有语义）
                ["fontSize"] = "15px",         // 字符串按 parseInt 语义
                ["fontFace"] = "x' onmouseover='a'" // 再过滤一次
            });
            var doc = NativeTooltipDocument.FromPayload(wire);
            NativeTooltipRun run = doc.Sections[0].Runs[0];
            Assert.False(run.Italic);
            Assert.True(run.Underline);
            Assert.Equal(15, run.FontSize);
            Assert.DoesNotContain("'", run.FontFace);
            Assert.DoesNotContain("(", run.FontFace);
        }

        [Theory]
        [InlineData("<i>斜</i>", true, false)]
        [InlineData("<em>斜</em>", true, false)]
        [InlineData("<u>线</u>", false, true)]
        public void LegacyMarkupExpandsItalicUnderline(string html, bool italic, bool underline)
        {
            NativeTooltipRun run = LegacyDoc(html).Sections[0].Runs[0];
            Assert.Equal(italic, run.Italic);
            Assert.Equal(underline, run.Underline);
        }

        [Fact]
        public void LegacyMarkupExpandsFontSizeAndFace()
        {
            NativeTooltipRun run = LegacyDoc("<font size='30'>大</font>").Sections[0].Runs[0];
            Assert.Equal(30, run.FontSize);

            run = LegacyDoc("<font face='ms mincho'>字</font>").Sections[0].Runs[0];
            Assert.Equal("ms mincho", run.FontFace);

            // 真实语料形态：color+size 同标签、face+u 嵌套
            run = LegacyDoc("<font color=\"#000000\" size=\"15\">黑字</font>").Sections[0].Runs[0];
            Assert.Equal(0, run.Color.Value.ToArgb() & 0xFFFFFF);
            Assert.Equal(15, run.FontSize);

            var doc = LegacyDoc("<font face='fixedsys'><u>“致…右转。”</u></font>");
            run = doc.Sections[0].Runs[0];
            Assert.True(run.Underline);
            Assert.Equal("fixedsys", run.FontFace);
        }

        [Fact]
        public void LegacyFontClosePopsFontFrame_NoLeak()
        {
            // </font> 弹到最近 font 帧（含其上 bold 帧）——size 不泄漏给后续文本
            var doc = LegacyDoc("<font size='15'><b>x</font>y</b>");
            Assert.Equal(2, doc.Sections[0].Runs.Count);
            Assert.Equal(15, doc.Sections[0].Runs[0].FontSize);
            Assert.True(doc.Sections[0].Runs[0].Bold);
            Assert.Null(doc.Sections[0].Runs[1].FontSize);
            Assert.False(doc.Sections[0].Runs[1].Bold);
        }

        [Fact]
        public void LegacyUnderlineSurvivesLineBreak()
        {
            // <br> 只产无样式换行 run，不弹栈——对齐 Web DOM
            var doc = LegacyDoc("<font face='fixedsys'><u>甲<br>乙</u></font>丙");
            var runs = doc.Sections[0].Runs;
            Assert.Equal(4, runs.Count);
            Assert.True(runs[0].Underline);
            Assert.Equal("fixedsys", runs[0].FontFace);
            Assert.Equal("\n", runs[1].Text);
            Assert.False(runs[1].Underline);
            Assert.True(runs[2].Underline);
            Assert.Equal("fixedsys", runs[2].FontFace);
            Assert.Equal("丙", runs[3].Text);
            Assert.False(runs[3].Underline);
            Assert.Null(runs[3].FontFace);
        }

        [Fact]
        public void LegacyNestedFontSizeOverrideAndRestore()
        {
            var doc = LegacyDoc("<font size='10'>a<font size='20'>b</font>c</font>d");
            var runs = doc.Sections[0].Runs;
            Assert.Equal(4, runs.Count);
            Assert.Equal(10, runs[0].FontSize);
            Assert.Equal(20, runs[1].FontSize);
            Assert.Equal(10, runs[2].FontSize);
            Assert.Null(runs[3].FontSize);
        }

        [Theory]
        [InlineData("<font size='15px'>x</font>", 15)]
        [InlineData("<font size='+15'>x</font>", 15)]
        [InlineData("<font size='15.9'>x</font>", 15)]
        [InlineData("<font size='96'>x</font>", 96)]
        public void LegacyFontSizeParseIntRules(string html, int expected)
        {
            Assert.Equal(expected, LegacyDoc(html).Sections[0].Runs[0].FontSize);
        }

        [Theory]
        [InlineData("<font size='0'>x</font>")]
        [InlineData("<font size='97'>x</font>")]
        [InlineData("<font size='-5'>x</font>")]
        [InlineData("<font size='abc'>x</font>")]
        [InlineData("<font size='0x15'>x</font>")]
        public void LegacyFontSizeInvalid_Omitted(string html)
        {
            Assert.Null(LegacyDoc(html).Sections[0].Runs[0].FontSize);
        }

        [Fact]
        public void Legacy3HexColorExpands()
        {
            NativeTooltipRun run = LegacyDoc("<font color='#f60'>x</font>").Sections[0].Runs[0];
            Assert.Equal(0xFF6600, run.Color.Value.ToArgb() & 0xFFFFFF);
        }

        [Fact]
        public void LegacyMalformedTagsDegrade()
        {
            // 未闭合引号 → face 无效省略，文本不受影响
            var doc = LegacyDoc("<font face='broken>t</font>z");
            var runs = doc.Sections[0].Runs;
            Assert.Equal(2, runs.Count);
            Assert.Null(runs[0].FontFace);
            Assert.Equal("z", runs[1].Text);

            // 多余闭合标签容错忽略
            doc = LegacyDoc("a</u>b</i>c</font>d");
            Assert.Equal("abcd", doc.Sections[0].PlainText);
        }

        [Fact]
        public void RunCtorBackCompatAndExtended()
        {
            // 原三参构造不破：新字段全部缺省
            var r = new NativeTooltipRun("t", null, false);
            Assert.False(r.Italic);
            Assert.False(r.Underline);
            Assert.Null(r.FontSize);
            Assert.Null(r.FontFace);

            var r2 = new NativeTooltipRun("t", null, true, italic: true, fontSize: 20);
            Assert.True(r2.Bold);
            Assert.True(r2.Italic);
            Assert.Equal(20, r2.FontSize);
            Assert.Null(r2.FontFace);
        }
    }
}
