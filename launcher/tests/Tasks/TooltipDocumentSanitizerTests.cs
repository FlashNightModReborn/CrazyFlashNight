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

        // ════════════ 2026-10 二轮改版：sub 段 / 插条 / 弹夹行转发 ════════════

        [Fact]
        public void SubRole_IsPreservedAsStructuralSubBoxRole()
        {
            JObject doc = ValidDocument();
            doc["sections"] = new JArray
            {
                new JObject { ["role"] = "intro",
                    ["runs"] = new JArray { new JObject { ["text"] = "正文" } } },
                new JObject { ["role"] = "SUB",
                    ["runs"] = new JArray { new JObject { ["text"] = "已装插件：扩容弹匣" } } },
                new JObject { ["role"] = "sub",
                    ["runs"] = new JArray { new JObject { ["text"] = "夜视" } } }
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            // 归一化为小写并保留出现序（每个 sub 段 = 一个独立子注释框）
            Assert.Equal("sub", (string)output["sections"][1]["role"]);
            Assert.Equal("sub", (string)output["sections"][2]["role"]);
        }

        [Fact]
        public void Rail_IsDedupedCappedAndWhitelisted()
        {
            JObject doc = ValidDocument();
            doc["rail"] = new JArray
            {
                "长枪", "长枪",                        // 重复项丢弃
                1234,                                 // 非字符串丢弃
                new string('长', 25),                  // 超 24 字符：整项丢弃
                "突击步枪", "第三项丢弃"
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JArray rail = (JArray)output["rail"];
            Assert.NotNull(rail);
            Assert.Equal(2, rail.Count);
            Assert.Equal("长枪", (string)rail[0]);
            Assert.Equal("突击步枪", (string)rail[1]);
        }

        [Fact]
        public void Rail_WithoutAnyUsableText_IsOmitted()
        {
            JObject doc = ValidDocument();
            doc["rail"] = new JArray { "", "   ", 7 };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Null(output["rail"]);
        }

        [Fact]
        public void Magazine_RequiresNameAndKeepsOptionalIcon()
        {
            JObject doc = ValidDocument();
            doc["magazine"] = new JObject
            {
                ["name"] = "11 号 4.7mm 弹夹",
                ["icon"] = "ammo_ghren_47"
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Equal("11 号 4.7mm 弹夹", (string)output["magazine"]["name"]);
            Assert.Equal("ammo_ghren_47", (string)output["magazine"]["icon"]);

            JObject noIcon = ValidDocument();
            noIcon["magazine"] = new JObject { ["name"] = "9mm 弹夹" };
            Assert.True(TooltipDocumentSanitizer.TrySanitize(noIcon, out output));
            Assert.Equal("9mm 弹夹", (string)output["magazine"]["name"]);
            Assert.Null(output["magazine"]["icon"]);

            // 无 name / 空白 name = 整键丢弃：弹夹名是这一行的存在条件
            JObject nameless = ValidDocument();
            nameless["magazine"] = new JObject { ["icon"] = "ammo_ghren_47" };
            Assert.True(TooltipDocumentSanitizer.TrySanitize(nameless, out output));
            Assert.Null(output["magazine"]);

            JObject blank = ValidDocument();
            blank["magazine"] = new JObject { ["name"] = "   ", ["icon"] = "a" };
            Assert.True(TooltipDocumentSanitizer.TrySanitize(blank, out output));
            Assert.Null(output["magazine"]);
        }

        [Fact]
        public void Magazine_AmmoLineIsForwardedAndBounded()
        {
            JObject doc = ValidDocument();
            doc["magazine"] = new JObject
            {
                ["name"] = "11 号 4.7mm 弹夹",
                ["ammo"] = "4.7mm 穿甲弹"
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            Assert.Equal("4.7mm 穿甲弹", (string)output["magazine"]["ammo"]);

            JObject capped = ValidDocument();
            capped["magazine"] = new JObject
            {
                ["name"] = "弹夹",
                ["ammo"] = new string('弹', TooltipDocumentSanitizer.MaxMagazineAmmoChars + 1)
            };
            Assert.True(TooltipDocumentSanitizer.TrySanitize(capped, out output));
            Assert.Null(output["magazine"]["ammo"]);

            JObject blank = ValidDocument();
            blank["magazine"] = new JObject { ["name"] = "弹夹", ["ammo"] = "   " };
            Assert.True(TooltipDocumentSanitizer.TrySanitize(blank, out output));
            Assert.Null(output["magazine"]["ammo"]);
        }

        [Fact]
        public void AttachmentsRows_AreWhitelistedRebuilt()
        {
            JObject doc = ValidDocument();
            doc["sections"] = new JArray
            {
                new JObject
                {
                    ["role"] = "sub",
                    ["kind"] = "attachments",
                    ["title"] = "已安装2个配件",
                    ["runs"] = new JArray { new JObject { ["text"] = "回退全文" } },
                    ["rows"] = new JArray
                    {
                        new JObject
                        {
                            ["name"] = "扩容弹匣",
                            ["icon"] = "mod_mag",
                            ["runs"] = new JArray
                            {
                                new JObject { ["text"] = " (+30%)",
                                    ["color"] = "#ff0" }
                            },
                            ["evil"] = "drop"
                        },
                        new JObject { ["name"] = "消音器" },   // 无图标/无效果行仍保留
                        new JObject { ["name"] = "   " },      // 空白名整行丢弃
                        "not-an-object"                        // 类型异常整行丢弃
                    }
                }
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JObject section = (JObject)output["sections"][0];
            Assert.Equal("sub", (string)section["role"]);
            Assert.Equal("attachments", (string)section["kind"]);
            Assert.Equal("已安装2个配件", (string)section["title"]);
            // 回退 runs 仍保留，旧消费端不丢内容
            Assert.Equal("回退全文", (string)section["runs"][0]["text"]);
            JArray rows = (JArray)section["rows"];
            Assert.Equal(2, rows.Count);
            Assert.Equal("扩容弹匣", (string)rows[0]["name"]);
            Assert.Equal("mod_mag", (string)rows[0]["icon"]);
            Assert.Equal("#FFFF00", (string)rows[0]["runs"][0]["color"]);
            Assert.Null(rows[0]["evil"]);
            Assert.Equal("消音器", (string)rows[1]["name"]);
            Assert.Null(rows[1]["icon"]);
            Assert.Equal(0, ((JArray)rows[1]["runs"]).Count);
        }

        [Fact]
        public void AcquisitionRows_AreWhitelistedRebuilt()
        {
            // 获取方式子框：kind 透传、商店行 NPC 头像键（icon）保留、
            // 类别行内容 runs 保留；非法行与未列举键照 attachments 同一套规则。
            JObject doc = ValidDocument();
            doc["sections"] = new JArray
            {
                new JObject
                {
                    ["role"] = "sub",
                    ["kind"] = "acquisition",
                    ["title"] = "获取方式",
                    ["runs"] = new JArray { new JObject { ["text"] = "回退全文" } },
                    ["rows"] = new JArray
                    {
                        new JObject
                        {
                            ["name"] = "安迪",
                            ["icon"] = "安迪",   // NPC 头像键：Web 端映射 portraits/icons/<NPC名>.webp
                            ["depth"] = 1
                        },
                        new JObject
                        {
                            ["name"] = "合成",
                            ["depth"] = 2,
                            ["runs"] = new JArray
                            {
                                new JObject { ["text"] = "武器工坊 ($5000)",
                                    ["color"] = "#0f0" }
                            },
                            ["evil"] = "drop"
                        },
                        new JObject { ["name"] = "   " }   // 空白名整行丢弃
                    }
                }
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JObject section = (JObject)output["sections"][0];
            Assert.Equal("sub", (string)section["role"]);
            Assert.Equal("acquisition", (string)section["kind"]);
            Assert.Equal("获取方式", (string)section["title"]);
            Assert.Equal("回退全文", (string)section["runs"][0]["text"]);
            JArray rows = (JArray)section["rows"];
            Assert.Equal(2, rows.Count);
            Assert.Equal("安迪", (string)rows[0]["name"]);
            Assert.Equal("安迪", (string)rows[0]["icon"]);
            Assert.Equal(1, (int)rows[0]["depth"]);
            Assert.Equal("合成", (string)rows[1]["name"]);
            Assert.Null(rows[1]["depth"]);
            Assert.Equal("#00FF00", (string)rows[1]["runs"][0]["color"]);
            Assert.Null(rows[1]["evil"]);
        }

        [Fact]
        public void ModInfoRows_AllowEffectOnlyChildrenAndKeepFallback()
        {
            JObject doc = ValidDocument();
            doc["sections"] = new JArray
            {
                new JObject
                {
                    ["role"] = "sub",
                    ["kind"] = "modinfo",
                    ["title"] = "配件信息",
                    ["runs"] = new JArray { new JObject { ["text"] = "回退全文" } },
                    ["rows"] = new JArray
                    {
                        new JObject { ["name"] = "装配要求" },
                        new JObject
                        {
                            ["depth"] = 1,
                            ["runs"] = new JArray
                            {
                                new JObject { ["text"] = "插件位置：", ["color"] = "#0f0" },
                                new JObject { ["text"] = "手环" }
                            }
                        },
                        new JObject()
                    }
                }
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JObject section = (JObject)output["sections"][0];
            Assert.Equal("modinfo", (string)section["kind"]);
            Assert.Equal("回退全文", (string)section["runs"][0]["text"]);
            JArray rows = (JArray)section["rows"];
            Assert.Equal(2, rows.Count);
            Assert.Equal("装配要求", (string)rows[0]["name"]);
            Assert.Equal("", (string)rows[1]["name"]);
            Assert.Equal(1, (int)rows[1]["depth"]);
            Assert.Equal(2, ((JArray)rows[1]["runs"]).Count);
            Assert.Equal("#00FF00", (string)rows[1]["runs"][0]["color"]);
        }

        [Fact]
        public void UpgradeRows_AreWhitelistedWithIconsAndDepth()
        {
            JObject doc = ValidDocument();
            doc["sections"] = new JArray
            {
                new JObject
                {
                    ["role"] = "description", ["kind"] = "upgrades", ["title"] = "升阶路线",
                    ["rows"] = new JArray
                    {
                        new JObject { ["name"] = "升自", ["runs"] = new JArray
                            { new JObject { ["text"] = "升自", ["color"] = "#99CCFF" } } },
                        new JObject { ["name"] = "G11", ["icon"] = "weapon_g11", ["depth"] = 1,
                            ["runs"] = new JArray { new JObject { ["text"] = " x1" } } }
                    }
                }
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JObject section = (JObject)output["sections"][0];
            Assert.Equal("upgrades", (string)section["kind"]);
            Assert.Equal("description", (string)section["role"]);
            JArray rows = (JArray)section["rows"];
            Assert.Equal(2, rows.Count);
            Assert.Equal("weapon_g11", (string)rows[1]["icon"]);
            Assert.Equal(1, (int)rows[1]["depth"]);
            Assert.Equal("#99CCFF", (string)rows[0]["runs"][0]["color"]);
        }

        [Fact]
        public void AttachmentsRows_AreCappedAndRequireValidRows()
        {
            var rows = new JArray();
            for (int i = 0; i < TooltipDocumentSanitizer.MaxAttachmentRows + 3; i++)
                rows.Add(new JObject { ["name"] = "插件" + i });

            JObject doc = ValidDocument();
            doc["sections"] = new JArray
            {
                new JObject
                {
                    ["role"] = "sub",
                    ["kind"] = "attachments",
                    ["rows"] = rows,
                    ["runs"] = new JArray { new JObject { ["text"] = "回退" } }
                }
            };
            JObject output;
            Assert.True(TooltipDocumentSanitizer.TrySanitize(doc, out output));
            JObject section = (JObject)output["sections"][0];
            Assert.Equal(
                TooltipDocumentSanitizer.MaxAttachmentRows,
                ((JArray)section["rows"]).Count);

            // 只有非法行 → 不写 kind/title/rows，退回普通 sub（runs 保留）
            JObject invalid = ValidDocument();
            invalid["sections"] = new JArray
            {
                new JObject
                {
                    ["role"] = "sub",
                    ["kind"] = "attachments",
                    ["title"] = "已安装",
                    ["rows"] = new JArray { new JObject { ["icon"] = "x" } },
                    ["runs"] = new JArray { new JObject { ["text"] = "回退" } }
                }
            };
            Assert.True(TooltipDocumentSanitizer.TrySanitize(invalid, out output));
            JObject plain = (JObject)output["sections"][0];
            Assert.Null(plain["kind"]);
            Assert.Null(plain["rows"]);
            Assert.Equal("回退", (string)plain["runs"][0]["text"]);
        }

        [Fact]
        public void RailAndMagazineAlone_AreNotRenderableContent()
        {
            // 只有插条与弹夹行、没有任何正文/标题的文档不成立（否则会画出空壳）
            var doc = new JObject
            {
                ["version"] = 1,
                ["sections"] = new JArray
                {
                    new JObject { ["role"] = "intro",
                        ["runs"] = new JArray { new JObject { ["text"] = "" } } }
                },
                ["rail"] = new JArray { "长枪" },
                ["magazine"] = new JObject { ["name"] = "11 号弹夹" }
            };
            JObject output;
            Assert.False(TooltipDocumentSanitizer.TrySanitize(doc, out output));
        }
    }
}
