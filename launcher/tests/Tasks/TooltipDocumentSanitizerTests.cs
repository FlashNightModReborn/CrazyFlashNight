using System;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// TooltipDocumentSanitizer 单元测试：COMMON 桥协议 v1 可选 document 的
    /// 宿主边界净化语义——白名单重建、纯文本逐字、字段降级、结构上限、剥离契约。
    /// </summary>
    public class TooltipDocumentSanitizerTests
    {
        private static JObject ValidDocument()
        {
            return new JObject
            {
                ["version"] = 1,
                ["title"] = "M4A1-消音",
                ["icon"] = new JObject { ["kind"] = "item", ["name"] = "M4A1" },
                ["profile"] = "dense",
                ["sections"] = new JArray
                {
                    new JObject
                    {
                        ["role"] = "intro",
                        ["runs"] = new JArray
                        {
                            new JObject { ["text"] = "M4A1-消音", ["bold"] = true },
                            new JObject { ["text"] = "\n武器    步枪\n$20000\n" },
                            new JObject { ["text"] = "+15%", ["color"] = "#ffcc00" }
                        }
                    }
                }
            };
        }

        [Fact]
        public void TrySanitize_ValidDocument_RoundTripsCanonicalShape()
        {
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(ValidDocument(), out output));

            Assert.Equal(1, (int)output["version"]);
            Assert.Equal("M4A1-消音", (string)output["title"]);
            Assert.Equal("item", (string)output["icon"]["kind"]);
            Assert.Equal("M4A1", (string)output["icon"]["name"]);
            Assert.Equal("dense", (string)output["profile"]);

            JObject section = (JObject)output["sections"][0];
            Assert.Equal("intro", (string)section["role"]);
            JArray runs = (JArray)section["runs"];
            Assert.Equal(3, runs.Count);
            Assert.Equal("M4A1-消音", (string)runs[0]["text"]);
            Assert.True((bool)runs[0]["bold"]);
            Assert.Equal("\n武器    步枪\n$20000\n", (string)runs[1]["text"]);
            Assert.Equal("#FFCC00", (string)runs[2]["color"]);
        }

        [Fact]
        public void TrySanitize_PlainTextIsVerbatim_NoHtmlOrEntityReprocessing()
        {
            // 纯文本契约：聚合端已展开过的字面量 <b>/&amp;/&lt; 必须逐字透传，
            // 不得再做标记展开或实体解码。
            var doc = new JObject
            {
                ["title"] = "<b>标题</b> &amp; 结尾",
                ["sections"] = new JArray
                {
                    new JObject
                    {
                        ["role"] = "body",
                        ["runs"] = new JArray
                        {
                            new JObject { ["text"] = "字面 <b>粗体</b> 与 &lt;tag&gt; &amp;#65;" },
                            "裸字符串 run 也逐字 <i>保留</i>"
                        }
                    }
                }
            };

            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Equal("<b>标题</b> &amp; 结尾", (string)output["title"]);
            JArray runs = (JArray)output["sections"][0]["runs"];
            Assert.Equal("字面 <b>粗体</b> 与 &lt;tag&gt; &amp;#65;", (string)runs[0]["text"]);
            Assert.Equal("裸字符串 run 也逐字 <i>保留</i>", (string)runs[1]["text"]);
        }

        [Fact]
        public void TrySanitize_StripsUnknownKeysAtEveryLevel()
        {
            JObject doc = ValidDocument();
            doc["owner"] = "forged.owner";
            doc["onclick"] = "alert(1)";
            doc["icon"]["extra"] = true;
            ((JObject)doc["sections"][0])["injected"] = "x";
            ((JObject)doc["sections"][0]["runs"][0])["href"] = "javascript:0";

            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Null(output["owner"]);
            Assert.Null(output["onclick"]);
            Assert.Null(output["icon"]["extra"]);
            Assert.Null(output["sections"][0]["injected"]);
            Assert.Null(output["sections"][0]["runs"][0]["href"]);
        }

        [Theory]
        [InlineData(2)]
        [InlineData("2")]
        [InlineData(1.5)]
        public void TrySanitize_RejectsUnsupportedVersion(object version)
        {
            JObject doc = ValidDocument();
            doc["version"] = version is double ? (double)version
                : version is int ? (int)version
                : version.ToString();

            JObject output;
            Assert.False(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Null(output);
        }

        [Fact]
        public void TrySanitize_MissingOrLenientVersion_DefaultsToOne()
        {
            JObject doc = ValidDocument();
            doc.Remove("version");
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Equal(1, (int)output["version"]);

            doc["version"] = 1.0;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));

            doc["version"] = "1";
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));

            // 无法解析的 version 与 NativeTooltipDocument.ReadInt 一致按缺省 1。
            doc["version"] = new JObject();
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
        }

        [Theory]
        [InlineData("string")]
        [InlineData(42)]
        [InlineData(true)]
        public void TrySanitize_RejectsNonObjectDocument(object token)
        {
            JToken value = token is string ? (JToken)new JValue((string)token)
                : token is int ? new JValue((int)token)
                : new JValue((bool)token);
            JObject output;
            Assert.False(TooltipDocumentSanitizer.TrySanitize(value, out output));
            Assert.False(TooltipDocumentSanitizer.TrySanitize(new JArray(1, 2), out output));
            Assert.False(TooltipDocumentSanitizer.TrySanitize(null, out output));
            Assert.False(TooltipDocumentSanitizer.TrySanitize(JValue.CreateNull(), out output));
        }

        [Fact]
        public void TrySanitize_RejectsDocumentWithoutRenderableContent()
        {
            JObject output;
            Assert.False(TooltipDocumentSanitizer.TrySanitize(new JObject(), out output));
            Assert.False(TooltipDocumentSanitizer.TrySanitize(
                new JObject { ["version"] = 1, ["sections"] = new JArray() }, out output));
            Assert.False(TooltipDocumentSanitizer.TrySanitize(
                new JObject
                {
                    ["title"] = "",
                    ["sections"] = new JArray
                    {
                        new JObject
                        {
                            ["role"] = "body",
                            ["runs"] = new JArray(new JObject { ["text"] = "" })
                        }
                    }
                }, out output));
        }

        [Fact]
        public void TrySanitize_FieldLevelDegradation_DropsNotFails()
        {
            var doc = new JObject
            {
                ["version"] = 1,
                ["title"] = 42,                       // 非字符串 → 剔除 title 字段
                ["icon"] = new JObject { ["kind"] = "item" },  // 缺 name → 整个 icon 省略
                ["profile"] = "DENSE",                // 大小写归一
                ["sections"] = new JArray
                {
                    "literal section is skipped",     // 非对象 → 跳过
                    new JObject
                    {
                        ["role"] = "meta",            // 未知 role → body
                        ["runs"] = new JArray
                        {
                            new JObject { ["text"] = "保留正文" },
                            new JObject { ["text"] = 42 },       // 非字符串 → 跳过该 run
                            new JObject { ["text"] = "带色", ["color"] = "red", ["bold"] = "yes" },
                            new JObject { ["text"] = "非法控制符\0丢弃" }
                        }
                    },
                    new JObject { ["runs"] = new JArray("缺 role 按 body") }
                }
            };

            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Null(output["title"]);
            Assert.Null(output["icon"]);
            Assert.Equal("dense", (string)output["profile"]);

            JArray sections = (JArray)output["sections"];
            Assert.Equal(2, sections.Count);
            Assert.Equal("body", (string)sections[0]["role"]);
            Assert.Equal("body", (string)sections[1]["role"]);

            JArray runs = (JArray)sections[0]["runs"];
            Assert.Equal(2, runs.Count);   // text=42 与含 \0 的 run 均被剔除
            Assert.Equal("保留正文", (string)runs[0]["text"]);
            Assert.Equal("带色", (string)runs[1]["text"]);
            Assert.Null(runs[1]["color"]); // 非法 color → 省略
            Assert.Null(runs[1]["bold"]);  // 非 bool bold → 省略
            Assert.Equal("缺 role 按 body", (string)sections[1]["runs"][0]["text"]);
        }

        [Fact]
        public void TrySanitize_RunStyleKeys_PassThroughWhitelist()
        {
            // document v1 可选 run 样式：italic/underline 仅真 bool 透传（显式 false 保留），
            // fontSize 限 1..96，fontFace 过滤为受限字体名。
            var doc = new JObject
            {
                ["version"] = 1,
                ["sections"] = new JArray
                {
                    new JObject
                    {
                        ["role"] = "body",
                        ["runs"] = new JArray
                        {
                            new JObject
                            {
                                ["text"] = "样式",
                                ["italic"] = true,
                                ["underline"] = true,
                                ["fontSize"] = 15,
                                ["fontFace"] = "ms mincho"
                            },
                            new JObject
                            {
                                ["text"] = "显式false保留",
                                ["italic"] = false,
                                ["underline"] = false
                            },
                            "裸字符串 run 不带样式"
                        }
                    }
                }
            };

            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JArray runs = (JArray)output["sections"][0]["runs"];
            Assert.Equal(3, runs.Count);
            Assert.True((bool)runs[0]["italic"]);
            Assert.True((bool)runs[0]["underline"]);
            Assert.Equal(15, (int)runs[0]["fontSize"]);
            Assert.Equal("ms mincho", (string)runs[0]["fontFace"]);
            Assert.False((bool)runs[1]["italic"]);
            Assert.False((bool)runs[1]["underline"]);
            Assert.Null(runs[2]["italic"]);
            Assert.Null(runs[2]["fontSize"]);
            Assert.Null(runs[2]["fontFace"]);
        }

        [Theory]
        [InlineData(15, 15)]
        [InlineData(96, 96)]
        [InlineData(15.9, 15)]        // Float 向零截断（对齐 parseInt）
        [InlineData("15px", 15)]
        [InlineData("+15", 15)]
        [InlineData(" 20 ", 20)]
        [InlineData("15.9", 15)]
        public void TrySanitize_FontSize_ParseIntSemantics(object raw, int expected)
        {
            var doc = new JObject
            {
                ["sections"] = new JArray(new JObject
                {
                    ["role"] = "body",
                    ["runs"] = new JArray(new JObject
                    {
                        ["text"] = "x",
                        ["fontSize"] = raw is double ? JToken.FromObject((double)raw)
                            : raw is string ? JToken.FromObject((string)raw)
                            : JToken.FromObject((int)raw)
                    })
                })
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Equal(expected, (int)output["sections"][0]["runs"][0]["fontSize"]);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(97)]
        [InlineData(-5)]
        [InlineData("abc")]
        [InlineData("0x15")]          // parseInt("0x15",10)=0 → 丢弃
        [InlineData("999999999999")]  // 溢出早退
        public void TrySanitize_FontSize_OutOfRangeOrInvalid_OmitsKey(object raw)
        {
            var doc = new JObject
            {
                ["sections"] = new JArray(new JObject
                {
                    ["role"] = "body",
                    ["runs"] = new JArray(new JObject
                    {
                        ["text"] = "x",
                        ["fontSize"] = raw is string
                            ? JToken.FromObject((string)raw) : JToken.FromObject((int)raw)
                    })
                })
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Null(output["sections"][0]["runs"][0]["fontSize"]);
        }

        [Theory]
        [InlineData("ms mincho", "ms mincho")]
        [InlineData("fixedsys", "fixedsys")]
        [InlineData("MS  MINCHO", "MS MINCHO")]        // 空格折叠、大小写保留
        [InlineData("楷体-字", "楷体-字")]              // CJK + 连字符
        [InlineData("\tms\tmincho\n", "msmincho")]     // \t\n 非允许字符直接剥除（legacy 同款）
        public void TrySanitize_FontFace_RestrictedName(string raw, string expected)
        {
            var doc = new JObject
            {
                ["sections"] = new JArray(new JObject
                {
                    ["role"] = "body",
                    ["runs"] = new JArray(new JObject
                    {
                        ["text"] = "x",
                        ["fontFace"] = raw
                    })
                })
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Equal(expected, (string)output["sections"][0]["runs"][0]["fontFace"]);
        }

        [Fact]
        public void TrySanitize_FontFace_MaliciousFilteredToSafeChars()
        {
            // 事件属性/CSS 元字符不得进入 fontFace
            var doc = new JObject
            {
                ["sections"] = new JArray(new JObject
                {
                    ["role"] = "body",
                    ["runs"] = new JArray(
                        new JObject { ["text"] = "a", ["fontFace"] = "x' onmouseover='alert(1)'" },
                        new JObject { ["text"] = "b", ["fontFace"] = "!!!;;;" },   // 全过滤为空 → 省略
                        new JObject { ["text"] = "c", ["fontFace"] = 42 },          // 非字符串 → 省略
                        new JObject { ["text"] = "d",
                            ["fontFace"] = new string('f', TooltipDocumentSanitizer.MaxFontFaceChars + 10) })
                })
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JArray runs = (JArray)output["sections"][0]["runs"];
            string face = (string)runs[0]["fontFace"];
            Assert.NotNull(face);
            Assert.DoesNotContain("'", face);
            Assert.DoesNotContain("(", face);
            Assert.DoesNotContain(")", face);
            Assert.DoesNotContain(";", face);
            Assert.DoesNotContain("=", face);
            Assert.Null(runs[1]["fontFace"]);
            Assert.Null(runs[2]["fontFace"]);
            Assert.Equal(
                TooltipDocumentSanitizer.MaxFontFaceChars,
                ((string)runs[3]["fontFace"]).Length);
        }

        [Fact]
        public void TrySanitize_NormalizesColorAndKeepsExplicitBoldFalse()
        {
            var doc = new JObject
            {
                ["sections"] = new JArray
                {
                    new JObject
                    {
                        ["role"] = "DESCRIPTION",
                        ["runs"] = new JArray
                        {
                            new JObject { ["text"] = "a", ["color"] = "0xa1b2c3" },
                            new JObject { ["text"] = "b", ["color"] = "A1B2C3", ["bold"] = false },
                            new JObject { ["text"] = "c", ["color"] = "#12345" }
                        }
                    }
                }
            };

            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Equal("description", (string)output["sections"][0]["role"]);
            JArray runs = (JArray)output["sections"][0]["runs"];
            Assert.Equal("#A1B2C3", (string)runs[0]["color"]);
            Assert.Equal("#A1B2C3", (string)runs[1]["color"]);
            Assert.False((bool)runs[1]["bold"]);
            Assert.Null(runs[2]["color"]);
        }

        private static JArray ManySections(int sectionCount, int runsPerSection)
        {
            var sections = new JArray();
            for (int i = 0; i < sectionCount; i++)
            {
                var runs = new JArray();
                for (int j = 0; j < runsPerSection; j++)
                    runs.Add(new JObject { ["text"] = "r" + j });
                sections.Add(new JObject { ["role"] = "body", ["runs"] = runs });
            }
            return sections;
        }

        private static int TotalRuns(JArray sections)
        {
            int total = 0;
            foreach (JToken section in sections)
                total += ((JArray)section["runs"]).Count;
            return total;
        }

        [Fact]
        public void TrySanitize_EnforcesSectionCap()
        {
            // 每段 10 run、总 run 远低于上限 → 仅 MaxSections 截断生效。
            var doc = new JObject
            {
                ["version"] = 1,
                ["sections"] = ManySections(
                    TooltipDocumentSanitizer.MaxSections + 4, 10)
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JArray emitted = (JArray)output["sections"];
            Assert.Equal(TooltipDocumentSanitizer.MaxSections, emitted.Count);
            foreach (JToken section in emitted)
                Assert.Equal(10, ((JArray)section["runs"]).Count);
        }

        [Fact]
        public void TrySanitize_EnforcesRunsPerSectionCap()
        {
            var doc = new JObject
            {
                ["version"] = 1,
                ["sections"] = ManySections(
                    1, TooltipDocumentSanitizer.MaxRunsPerSection + 4)
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Single((JArray)output["sections"]);
            Assert.Equal(
                TooltipDocumentSanitizer.MaxRunsPerSection,
                ((JArray)output["sections"][0]["runs"]).Count);
        }

        [Fact]
        public void TrySanitize_EnforcesTotalRunsCap()
        {
            // 8×40=320 > MaxTotalRuns：输出总 run 数封顶，且每段仍受段内上限约束。
            var doc = new JObject
            {
                ["version"] = 1,
                ["sections"] = ManySections(8, 40)
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JArray emitted = (JArray)output["sections"];
            Assert.Equal(
                TooltipDocumentSanitizer.MaxTotalRuns, TotalRuns(emitted));
            foreach (JToken section in emitted)
                Assert.True(
                    ((JArray)section["runs"]).Count
                        <= TooltipDocumentSanitizer.MaxRunsPerSection);
        }

        [Fact]
        public void TrySanitize_DropsOverBoundScalarsWithoutFailingDocument()
        {
            var doc = new JObject
            {
                ["title"] = new string('t', TooltipDocumentSanitizer.MaxTitleChars + 1),
                ["icon"] = new JObject
                {
                    ["kind"] = "item",
                    ["name"] = new string('n', TooltipDocumentSanitizer.MaxIconNameChars + 1)
                },
                ["sections"] = new JArray
                {
                    new JObject
                    {
                        ["role"] = "body",
                        ["runs"] = new JArray
                        {
                            new JObject
                            {
                                ["text"] = new string('x',
                                    TooltipDocumentSanitizer.MaxRunTextChars + 1)
                            },
                            new JObject { ["text"] = "仍有内容" }
                        }
                    }
                }
            };

            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Null(output["title"]);
            Assert.Null(output["icon"]);
            JArray runs = (JArray)output["sections"][0]["runs"];
            Assert.Single(runs);
            Assert.Equal("仍有内容", (string)runs[0]["text"]);
        }

        [Fact]
        public void ApplyTo_AttachesSanitizedDocumentOrStripsKey()
        {
            var target = new JObject();
            TooltipDocumentSanitizer.ApplyTo(ValidDocument(), target);
            Assert.Equal("M4A1-消音", (string)target["document"]["title"]);

            // 克隆路径残留的未净化 document：非法输入必须移除旧键。
            TooltipDocumentSanitizer.ApplyTo(new JObject { ["version"] = 2 }, target);
            Assert.Null(target["document"]);

            TooltipDocumentSanitizer.ApplyTo(null, target);
            Assert.Null(target["document"]);
        }

        [Fact]
        public void HasExactKeysAllowingOptionalDocument_PinsWhitelistSemantics()
        {
            Func<JObject> baseMessage = () => new JObject
            {
                ["task"] = "x", ["callId"] = 1, ["success"] = true, ["v"] = 1
            };
            string[] expected = { "task", "callId", "success", "v" };

            Assert.True(TooltipDocumentSanitizer
                .HasExactKeysAllowingOptionalDocument(baseMessage(), expected));

            JObject withDocument = baseMessage();
            withDocument["document"] = new JObject();
            Assert.True(TooltipDocumentSanitizer
                .HasExactKeysAllowingOptionalDocument(withDocument, expected));

            JObject withExtra = baseMessage();
            withExtra["injected"] = true;
            Assert.False(TooltipDocumentSanitizer
                .HasExactKeysAllowingOptionalDocument(withExtra, expected));

            JObject documentAndExtra = baseMessage();
            documentAndExtra["document"] = new JObject();
            documentAndExtra["injected"] = true;
            Assert.False(TooltipDocumentSanitizer
                .HasExactKeysAllowingOptionalDocument(documentAndExtra, expected));

            JObject missing = baseMessage();
            missing.Remove("v");
            Assert.False(TooltipDocumentSanitizer
                .HasExactKeysAllowingOptionalDocument(missing, expected));

            Assert.False(TooltipDocumentSanitizer
                .HasExactKeysAllowingOptionalDocument(null, expected));
            Assert.False(TooltipDocumentSanitizer
                .HasExactKeysAllowingOptionalDocument(new JObject(), expected));
        }
    }
}
