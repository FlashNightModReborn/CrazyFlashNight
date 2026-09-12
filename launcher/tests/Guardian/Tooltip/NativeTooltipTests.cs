using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Tooltip;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Tooltip
{
    /// <summary>
    /// NativeTooltip 岗位定向回归：document 纯文本契约 / 受限旧入口 / 评分与布局 /
    /// 定位边缘约束 / widget 生命周期与身份匹配。
    ///
    /// 关键不变量：
    /// 1. 桥 v1 document 的 title / run.text 是纯文本——C# 绝不再做标记展开或实体解码
    ///    （"&lt;b&gt;literal&lt;/b&gt;" 已展开为字面量后不得二次解析）。
    /// 2. 旧 htmlText 仅在 FromLegacyHtmlDocument 旧入口展开（font color/b/br/p）。
    /// 3. Hide(requestId) 只清匹配实例；同 requestId 低 revision 迟到 show 拒绝。
    /// 4. 静止不逐帧：WantsAnimationTick 恒 false。
    /// </summary>
    public class NativeTooltipTests
    {
        // ════════════ 样本 ════════════

        /// <summary>最复杂注释样本：title+icon+中文混排+多色+粗体+显式换行+长正文+pinned。</summary>
        private static JObject ComplexPayload(string requestId = "tt-1", long revision = 7)
        {
            return JObject.Parse(@"{
  'version': 1,
  'kind': 'tooltip',
  'op': 'show',
  'requestId': '" + requestId + @"',
  'sceneId': 'scene-shop-42',
  'owner': 'shopItem',
  'revision': " + revision + @",
  'x': 640.5,
  'y': 300.25,
  'document': {
    'version': 1,
    'title': '龙胆亮银枪·改',
    'icon': { 'kind': 'item', 'name': 'weapon_lance_mk2' },
    'profile': 'pinned',
    'sections': [
      { 'role': 'intro', 'runs': [
          { 'text': '史诗品质 · 双手长枪', 'color': '#FFD700', 'bold': true },
          { 'text': '攻击 288~352\n暴击率 +12%' }
      ]},
      { 'role': 'description', 'runs': [
          { 'text': '赵云佩枪重铸版。枪身镌刻""银龙出海""铭文，', 'color': '#9FB6C0' },
          { 'text': '暴击时触发', 'bold': true },
          { 'text': '【龙吟】', 'color': '#66CCFF', 'bold': true },
          { 'text': '：3 秒内攻速 +25%。' }
      ]},
      { 'role': 'body', 'runs': [
          { 'text': '套装 2/4：龙胆\n需求等级 45\n耐久 120/120\n售价 88,000 金币' }
      ]}
    ]
  }
}");
        }

        private static Control Anchor()
        {
            // 1024x576 → viewport 全幅、scale=1；无需 handle（CalcViewport 只读尺寸）
            return new Control { Size = new Size(1024, 576) };
        }

        // ════════════ document 解析：纯文本契约 ════════════

        [Fact]
        public void Payload_ComplexSample_ParsesAllFields()
        {
            NativeTooltipDocument doc = NativeTooltipDocument.FromPayload(ComplexPayload());
            Assert.NotNull(doc);
            Assert.Equal(1, doc.Version);
            Assert.Equal("tt-1", doc.RequestId);
            Assert.Equal("scene-shop-42", doc.SceneId);
            Assert.Equal("shopItem", doc.Owner);
            Assert.Equal(7, doc.Revision);
            Assert.True(doc.HasAnchor);
            Assert.Equal(640.5f, doc.AnchorX);
            Assert.Equal(300.25f, doc.AnchorY);
            Assert.Equal(NativeTooltipProfile.Pinned, doc.Profile);
            Assert.Equal("龙胆亮银枪·改", doc.Title);
            Assert.NotNull(doc.Icon);
            Assert.True(doc.Icon.IsItem);
            Assert.Equal("weapon_lance_mk2", doc.Icon.Name);
            Assert.Equal(3, doc.Sections.Count);
            Assert.Equal(NativeTooltipSectionRole.Intro, doc.Sections[0].Role);
            Assert.Equal(NativeTooltipSectionRole.Description, doc.Sections[1].Role);
            Assert.Equal(NativeTooltipSectionRole.Body, doc.Sections[2].Role);
            Assert.True(doc.HasContent);
        }

        [Fact]
        public void Payload_RunText_IsVerbatimPlainText_NoDoubleParse()
        {
            // AS2 htmlToRuns 展开一次后的字面量标记——C# 侧绝不再解析。
            JObject p = JObject.Parse(@"{
              'version':1,'requestId':'r1','document':{ 'version':1,
                'sections':[{'role':'body','runs':[
                  {'text':'<b>literal</b> &amp; <font color=""#FF0000"">x</font>'}]}]}}");
            NativeTooltipDocument doc = NativeTooltipDocument.FromPayload(p);
            Assert.NotNull(doc);
            Assert.Single(doc.Sections[0].Runs);
            Assert.Equal("<b>literal</b> &amp; <font color=\"#FF0000\">x</font>",
                doc.Sections[0].Runs[0].Text);
            Assert.False(doc.Sections[0].Runs[0].Bold);
            Assert.Null(doc.Sections[0].Runs[0].Color);
        }

        [Fact]
        public void LegacyEntry_StillExpandsConstrainedMarkup()
        {
            // 旧入口明确存在且与纯文本入口分开：htmlText 仅在这里展开一次。
            JObject d = JObject.Parse(@"{'version':1,
                'sections':[{'role':'body','runs':[
                  {'text':'a<b>粗</b><br><font color=""#FF0000"">红</font>&amp;nbsp;尾<p>二段</p>'}]}]}");
            NativeTooltipDocument doc = NativeTooltipDocument.FromLegacyHtmlDocument(d);
            Assert.NotNull(doc);
            string plain = doc.Sections[0].PlainText;
            Assert.Contains("粗", plain);
            Assert.Contains("红", plain);
            Assert.Contains("\n", plain);
            bool sawBold = false, sawRed = false;
            foreach (NativeTooltipRun r in doc.Sections[0].Runs)
            {
                if (r.Text == "粗" && r.Bold) sawBold = true;
                if (r.Text == "红" && r.Color.HasValue && r.Color.Value.R == 255) sawRed = true;
            }
            Assert.True(sawBold, "legacy <b> 应展开为 bold run");
            Assert.True(sawRed, "legacy <font color> 应展开为 color run");
        }

        [Fact]
        public void Payload_ExplicitNewlines_PreservedInRuns()
        {
            NativeTooltipDocument doc = NativeTooltipDocument.FromPayload(ComplexPayload());
            string intro = doc.Sections[0].PlainText;
            Assert.Contains("\n", intro);
            string body = doc.Sections[2].PlainText;
            Assert.Equal(3, body.Split('\n').Length - 1); // 3 个显式换行
        }

        [Fact]
        public void Payload_ColorBold_TransitionsPreservedPerRun()
        {
            NativeTooltipDocument doc = NativeTooltipDocument.FromPayload(ComplexPayload());
            var desc = doc.Sections[1].Runs;
            Assert.Equal(4, desc.Count);
            Assert.Equal(Color.FromArgb(255, 159, 182, 192), desc[0].Color.Value);
            Assert.False(desc[0].Bold);
            Assert.True(desc[1].Bold);
            Assert.Null(desc[1].Color);
            Assert.Equal(Color.FromArgb(255, 102, 204, 255), desc[2].Color.Value);
            Assert.True(desc[2].Bold);
        }

        [Theory]
        [InlineData("simple", NativeTooltipProfile.Simple)]
        [InlineData("dense", NativeTooltipProfile.Dense)]
        [InlineData("pinned", NativeTooltipProfile.Pinned)]
        [InlineData("weird", NativeTooltipProfile.Simple)]
        [InlineData(null, NativeTooltipProfile.Simple)]
        public void Profile_Normalizes(string profile, NativeTooltipProfile expected)
        {
            string json = @"{'version':1,'requestId':'r','document':{'version':1,"
                + (profile == null ? "" : "'profile':'" + profile + "',")
                + "'sections':[{'role':'body','runs':[{'text':'x'}]}]}}";
            Assert.Equal(expected, NativeTooltipDocument.FromPayload(JObject.Parse(json)).Profile);
        }

        [Fact]
        public void Payload_MissingOptionalFields_Tolerated()
        {
            JObject p = JObject.Parse(@"{'version':1,'requestId':'r2',
                'document':{'version':1,'title':'只有标题'}}");
            NativeTooltipDocument doc = NativeTooltipDocument.FromPayload(p);
            Assert.NotNull(doc);
            Assert.Null(doc.Icon);
            Assert.Empty(doc.Sections);
            Assert.False(doc.HasAnchor);
            Assert.True(doc.HasContent); // title 也算内容
        }

        [Fact]
        public void Payload_UnsupportedVersion_Rejected()
        {
            JObject p = ComplexPayload();
            p["version"] = 2;
            Assert.Null(NativeTooltipDocument.FromPayload(p));
        }

        [Fact]
        public void Payload_DocumentVersion2_Rejected()
        {
            JObject p = ComplexPayload();
            ((JObject)p["document"])["version"] = 2;
            Assert.Null(NativeTooltipDocument.FromPayload(p));
        }

        [Fact]
        public void Payload_EmptyDocument_Rejected()
        {
            JObject p = JObject.Parse(@"{'version':1,'requestId':'r','document':{'version':1}}");
            NativeTooltipDocument doc; string err;
            Assert.False(NativeTooltipDocument.TryFromPayload(p, out doc, out err));
            Assert.NotNull(err);
        }

        [Fact]
        public void Payload_NoMutableJsonLeak()
        {
            JObject p = ComplexPayload();
            NativeTooltipDocument doc = NativeTooltipDocument.FromPayload(p);
            // 改源 JSON 不影响已解析文档
            ((JObject)p["document"])["title"] = "被改写";
            Assert.Equal("龙胆亮银枪·改", doc.Title);
        }

        // ════════════ 评分 ════════════

        [Fact]
        public void Score_MixedWidth_ChineseDoubleAsciiSingle()
        {
            var s = NativeTooltipLayout.ScoreText("ab中文c");
            Assert.Equal(7, s.Total);        // 3*1 + 2*2
            Assert.Equal(1, s.LineCount);
        }

        [Fact]
        public void Score_WhitespaceCollapsed_NewlinesCount()
        {
            var s = NativeTooltipLayout.ScoreText("a   b\n\ncd\r\ne");
            Assert.Equal(4, s.LineCount);    // "a   b" / "" / "cd" / "e"
            Assert.True(s.MaxLine > 0);
        }

        [Fact]
        public void Score_LiteralMarkupText_CountsVerbatim()
        {
            // 纯文本契约：字面标记按字符计宽（不跳过）
            var s = NativeTooltipLayout.ScoreText("<b>x</b>");
            Assert.Equal(8, s.Total);
        }

        [Fact]
        public void Width_Estimate_ClampedToBounds()
        {
            var tiny = new NativeTooltipLayout.TextScore { Total = 2, MaxLine = 2, LineCount = 1 };
            Assert.Equal(150, NativeTooltipLayout.EstimateMainWidth(tiny, 150, 650));
            var huge = new NativeTooltipLayout.TextScore { Total = 100000, MaxLine = 500, LineCount = 200 };
            Assert.Equal(650, NativeTooltipLayout.EstimateMainWidth(huge, 150, 650));
        }

        [Fact]
        public void Split_Threshold_SmallStaysMerged_LargeSplits()
        {
            var small = new NativeTooltipLayout.TextScore { Total = 40, MaxLine = 40, LineCount = 2 };
            var tinyIntro = new NativeTooltipLayout.TextScore { Total = 10, MaxLine = 10, LineCount = 1 };
            Assert.False(NativeTooltipLayout.ShouldSplit(small, tinyIntro));

            var big = new NativeTooltipLayout.TextScore { Total = 200, MaxLine = 60, LineCount = 8 };
            Assert.True(NativeTooltipLayout.ShouldSplit(big, tinyIntro)); // 210>192 且 200>48
        }

        // ════════════ 换行布局 ════════════

        private static int FixedMeasure(string text, bool bold)
        {
            // 确定性测量：宽字符 12px，窄字符 6px，空白 3px
            int w = 0;
            foreach (char c in text)
                w += (c == ' ' || c == '\t') ? 3 : (NativeTooltipLayout.IsWideChar(c) ? 12 : 6);
            return w;
        }

        /// <summary>拼接一行全部 slice 的文本（CJK 逐字断行会产生多 slice）。</summary>
        private static string LineText(NativeTooltipLayout.VisualLine line)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var s in line.Slices) sb.Append(s.Text);
            return sb.ToString();
        }

        [Fact]
        public void Wrap_ExplicitNewlines_ProduceLogicalLines()
        {
            var runs = new List<NativeTooltipRun>
            {
                new NativeTooltipRun("第一行\n\n第三行", null, false)
            };
            var lines = NativeTooltipLayout.WrapRuns(runs, 400, FixedMeasure);
            Assert.Equal(3, lines.Count);
            Assert.True(lines[1].IsBlank);
            Assert.Equal("第三行", LineText(lines[2]));
        }

        [Fact]
        public void Wrap_CjkBreaksPerChar_AsciiWordStays()
        {
            var runs = new List<NativeTooltipRun> { new NativeTooltipRun("你好世界abc", null, false) };
            // 4 个中文字 = 48px，abc=18px，maxW=50 → "你好世界"(48) + "abc"(18) 第二行
            var lines = NativeTooltipLayout.WrapRuns(runs, 50, FixedMeasure);
            Assert.Equal(2, lines.Count);
            Assert.Equal("你好世界", LineText(lines[0]));
            Assert.Equal("abc", LineText(lines[1]));
        }

        [Fact]
        public void Wrap_LongAsciiToken_ForceSplitPerChar()
        {
            var runs = new List<NativeTooltipRun> { new NativeTooltipRun("abcdefghij", null, false) };
            var lines = NativeTooltipLayout.WrapRuns(runs, 30, FixedMeasure); // 30/6 = 5 chars/line
            Assert.Equal(2, lines.Count);
            Assert.Equal("abcde", LineText(lines[0]));
            Assert.Equal("fghij", LineText(lines[1]));
        }

        [Fact]
        public void Wrap_PreservesRunColorAcrossLines()
        {
            var runs = new List<NativeTooltipRun>
            {
                new NativeTooltipRun("红字第一行\n红字第二行", Color.Red, true)
            };
            var lines = NativeTooltipLayout.WrapRuns(runs, 400, FixedMeasure);
            Assert.Equal(2, lines.Count);
            foreach (var l in lines)
            {
                Assert.True(l.Slices[0].Bold);
                Assert.Equal(Color.Red, l.Slices[0].Color.Value);
            }
        }

        // ════════════ 定位 ════════════

        [Fact]
        public void Placement_PointAnchorTie_UsesWebLeftFirstOrder()
        {
            // 无元素的 Web 点锚没有宽度；左右均与 16px 排斥框重叠 6px。
            // 同分按 Web left→right→top→bottom 优先序。旧断言把 1px 元素
            // 锚点的右侧优势误当成零面积鼠标点规则。活体 Web 对照另有独立用例。
            var vp = new Rectangle(0, 0, 1024, 576);
            string side;
            Rectangle r = NativeTooltipLayout.SolvePlacement(
                new Point(600, 300), new Size(200, 100), vp, null, 1f, out side);
            Assert.Equal("left", side);
            Assert.Equal(600 - 10, r.Right);
        }

        [Fact]
        public void Placement_FlipsRight_WhenLeftOverflows()
        {
            var vp = new Rectangle(0, 0, 1024, 576);
            string side;
            Rectangle r = NativeTooltipLayout.SolvePlacement(
                new Point(50, 300), new Size(400, 100), vp, null, 1f, out side);
            // 左侧放不下 → right（或 top/bottom，但绝不越界）
            Assert.True(r.Left >= vp.Left + 4 && r.Right <= vp.Right - 4);
            Assert.True(r.Top >= vp.Top + 4 && r.Bottom <= vp.Bottom - 4);
        }

        [Fact]
        public void Placement_LockedSide_Sticks_WhileFeasible()
        {
            var vp = new Rectangle(0, 0, 1024, 576);
            string side;
            Rectangle r = NativeTooltipLayout.SolvePlacement(
                new Point(700, 100), new Size(200, 80), vp, "bottom", 1f, out side);
            Assert.Equal("bottom", side);
            Assert.True(r.Top > 100);
        }

        [Fact]
        public void Placement_ClampedInsideViewport()
        {
            var vp = new Rectangle(100, 50, 800, 400);
            string side;
            Rectangle r = NativeTooltipLayout.SolvePlacement(
                new Point(110, 60), new Size(500, 300), vp, null, 1f, out side);
            Assert.True(r.Left >= vp.Left);
            Assert.True(r.Top >= vp.Top);
            Assert.True(r.Right <= vp.Right);
            Assert.True(r.Bottom <= vp.Bottom);
        }

        // ════════════ widget 生命周期 ════════════

        [Fact]
        public void Widget_ShowThenHide_MatchingRequestId()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.False(w.Visible);
                Assert.True(w.Show(ComplexPayload()));
                Assert.True(w.Visible);
                Assert.Equal("tt-1", w.CurrentRequestId);
                Assert.Equal("shopItem", w.CurrentOwner);
                Assert.Equal(7, w.CurrentRevision);
                Assert.True(w.ScreenBounds.Width > 0);

                Assert.False(w.Hide("other-id")); // 不匹配：不动显示
                Assert.True(w.Visible);
                Assert.True(w.Hide("tt-1"));
                Assert.False(w.Visible);
            }
        }

        [Fact]
        public void Widget_StaleRevision_Rejected()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(ComplexPayload("tt-1", 7)));
                // 同 requestId 但 revision 更低 = 迟到
                Assert.False(w.Show(ComplexPayload("tt-1", 3)));
                Assert.Equal(7, w.CurrentRevision);
                // 更高 revision 接受
                Assert.True(w.Show(ComplexPayload("tt-1", 9)));
                Assert.Equal(9, w.CurrentRevision);
            }
        }

        [Fact]
        public void Widget_Reset_ClearsAll()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                w.Show(ComplexPayload());
                w.Reset();
                Assert.False(w.Visible);
                Assert.Null(w.CurrentRequestId);
                Assert.Equal(Rectangle.Empty, w.ScreenBounds);
            }
        }

        [Fact]
        public void Widget_NeverWantsAnimationTick()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.False(w.WantsAnimationTick);
                w.Show(ComplexPayload());
                Assert.False(w.WantsAnimationTick);
            }
        }

        [Fact]
        public void Widget_HitTest_OnlyPinned_InsideBounds()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                w.Show(ComplexPayload()); // pinned
                Rectangle b = w.ScreenBounds;
                Point inside = new Point(b.X + b.Width / 2, b.Y + b.Height / 2);
                Assert.True(w.TryHitTest(inside));
                Assert.False(w.TryHitTest(new Point(b.X - 50, b.Y - 50)));

                // dense / simple 不命中
                JObject dense = ComplexPayload("tt-2", 1);
                ((JObject)dense["document"])["profile"] = "dense";
                w.Show(dense);
                inside = new Point(w.ScreenBounds.X + w.ScreenBounds.Width / 2,
                    w.ScreenBounds.Y + w.ScreenBounds.Height / 2);
                Assert.False(w.TryHitTest(inside));
            }
        }

        [Fact]
        public void Widget_PinnedClose_FiresDismissWithRequestId()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                w.Show(ComplexPayload());
                string dismissed = null;
                w.DismissRequested += id => dismissed = id;

                Rectangle close = w.ActivePlan.CloseRect;
                Assert.False(close.IsEmpty);
                Point center = new Point(
                    w.PlacedRect.X + close.X + close.Width / 2,
                    w.PlacedRect.Y + close.Y + close.Height / 2);
                var args = new MouseEventArgs(MouseButtons.Left, 1, center.X, center.Y, 0);
                w.OnMouseEvent(args, MouseEventKind.Down);
                w.OnMouseEvent(args, MouseEventKind.Click);
                Assert.Equal("tt-1", dismissed);
            }
        }

        [Fact]
        public void Widget_LongDense_ScrollsWithinBounds()
        {
            // 长正文 dense：分栏 + 滚动视口
            string longText = "";
            for (int i = 0; i < 80; i++) longText += "第" + i + "行装备属性明细描述说明文字，";
            JObject p = JObject.Parse(@"{
              'version':1,'requestId':'tt-long','x':500,'y':200,
              'document':{'version':1,'title':'密集检视','profile':'dense',
                'sections':[
                  {'role':'intro','runs':[{'text':'测试物品·长文'}]},
                  {'role':'description','runs':[{'text':'" + longText + @"'}]}
                ]}}");
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(p));
                var plan = w.ActivePlan;
                Assert.True(plan.Split, "长 desc 应分栏");
                Assert.True(plan.DescScrollable, "80+ 行应产生滚动");
                Assert.True(plan.TipSize.Height <= 576 - 2 * 8 + 1, "tip 高度受视口约束");

                int maxScroll = w.MaxScrollLine;
                Assert.True(maxScroll > 0);
                // web max-height:min(70vh,520px) 下本例溢出仅 ~2 行——步进按实际余量
                int step = Math.Max(1, maxScroll / 2);
                Assert.True(w.ScrollByLines(step));
                Assert.Equal(step, w.ScrollLineOffset);
                Assert.True(w.ScrollByLines(maxScroll + 100)); // 钳制到 max，仍算实际滚动
                Assert.Equal(maxScroll, w.ScrollLineOffset);
                Assert.False(w.ScrollByLines(1)); // 已在底部：无变化
                Assert.True(w.ScrollByLines(-maxScroll));
                Assert.Equal(0, w.ScrollLineOffset);
            }
        }

        [Fact]
        public void Widget_TryScrollAt_RespectsPinnedHitAndDelta()
        {
            JObject p = ComplexPayload();
            string longText = "";
            for (int i = 0; i < 100; i++) longText += "滚动内容行" + i + "描述，";
            ((JArray)((JObject)p["document"])["sections"]).Add(
                JObject.Parse(@"{'role':'body','runs':[{'text':'" + longText + @"'}]}"));
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(p));
                if (!w.Scrollable) return; // 内容不够长则本测试无可滚对象——样本保证应可滚
                Rectangle b = w.ScreenBounds;
                Point outside = new Point(b.X - 100, b.Y - 100);
                Assert.False(w.TryScrollAt(outside, -120)); // pinned：框外不滚
                Point inside = new Point(b.X + b.Width / 2, b.Y + b.Height / 2);
                bool scrolled = w.TryScrollAt(inside, -120);
                Assert.True(scrolled);
                Assert.True(w.ScrollLineOffset > 0);
            }
        }

        [Fact]
        public void Widget_OnMouseWheel_PinnedConsumesInside_ReleasesOutside()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                w.Show(ComplexPayload());
                Rectangle b = w.ScreenBounds;
                Point inside = new Point(b.X + b.Width / 2, b.Y + b.Height / 2);
                Assert.True(w.OnMouseWheel(inside, -120), "pinned 框内恒消费（含未滚动）");
                Point outside = new Point(b.X - 100, b.Y - 100);
                Assert.False(w.OnMouseWheel(outside, -120));

                JObject dense = ComplexPayload("tt-d", 1);
                ((JObject)dense["document"])["profile"] = "dense";
                w.Show(dense);
                inside = new Point(w.ScreenBounds.X + w.ScreenBounds.Width / 2,
                    w.ScreenBounds.Y + w.ScreenBounds.Height / 2);
                Assert.False(w.OnMouseWheel(inside, -120), "dense 不消费滚轮");
            }
        }

        [Fact]
        public void Widget_OnHostSuppressed_EndsSession_PinnedReportsDismiss()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                w.Show(ComplexPayload());
                string dismissed = null;
                w.DismissRequested += id => dismissed = id;
                w.OnHostSuppressed("panel_suspend");
                Assert.Equal("tt-1", dismissed);
                Assert.False(w.Visible);

                // dense 压隐直接清、不报 dismiss
                JObject dense = ComplexPayload("tt-d", 1);
                ((JObject)dense["document"])["profile"] = "dense";
                w.Show(dense);
                dismissed = null;
                w.OnHostSuppressed("owner_hidden");
                Assert.Null(dismissed);
                Assert.False(w.Visible);
            }
        }

        [Fact]
        public void Widget_Paint_DoesNotThrow_AndHonorsHudOrigin()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            using (var bmp = new Bitmap(1024, 576))
            using (Graphics g = Graphics.FromImage(bmp))
            {
                w.Show(ComplexPayload());
                // hudOrigin 平移后 paint 不应越界或抛异常
                w.Paint(g, 1.0f, Point.Empty);
                w.Paint(g, 1.0f, new Point(w.PlacedRect.X, w.PlacedRect.Y));
            }
        }

        // ════════════ document 自身 version 边界 ════════════

        [Fact]
        public void Document_Version_Mismatch_RejectedThroughAllEntries()
        {
            JObject p = ComplexPayload();
            ((JObject)p["document"])["version"] = 2;
            // payload.v1 不得掩盖 document.v2
            NativeTooltipDocument doc; string err;
            Assert.False(NativeTooltipDocument.TryFromPayload(p, out doc, out err));
            Assert.Null(doc);
            Assert.Contains("version", err);
            // FromDocument 入口同样拒绝
            Assert.Null(NativeTooltipDocument.FromDocument((JObject)p["document"]));
            // 字符串形态 "2" 同样拒绝（非缺省回退）
            ((JObject)p["document"])["version"] = "2";
            Assert.Null(NativeTooltipDocument.FromPayload(p));
            // version 缺省按 1 处理（向后兼容旧聚合）
            ((JObject)p["document"]).Remove("version");
            Assert.NotNull(NativeTooltipDocument.FromPayload(p));
        }

        // ════════════ 段落 / 视口真实行为 ════════════

        private static JObject LongDensePayload()
        {
            string longText = "";
            for (int i = 0; i < 80; i++) longText += "第" + i + "行装备属性明细描述说明文字，";
            return JObject.Parse(@"{
              'version':1,'requestId':'tt-long','x':500,'y':200,
              'document':{'version':1,'title':'密集检视','profile':'dense',
                'sections':[
                  {'role':'intro','runs':[{'text':'测试物品·长文'}]},
                  {'role':'description','runs':[{'text':'" + longText + @"'}]}
                ]}}");
        }

        [Fact]
        public void Plan_SectionBoundary_ForcesLineBreak()
        {
            NativeTooltipDocument doc = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'双段',
                'sections':[
                  {'role':'description','runs':[{'text':'甲段尾部'}]},
                  {'role':'body','runs':[{'text':'乙段头部'}]}
                ]}"));
            var plan = NativeTooltipLayout.ComputePlan(doc, FixedMeasure, 15, 1f, 1024, 576);
            Assert.NotNull(plan);
            var lines = plan.Split ? plan.DescLines : plan.IntroLines;
            int idx = -1;
            for (int i = 0; i < lines.Count; i++)
                if (LineText(lines[i]).Contains("乙段头部")) { idx = i; break; }
            Assert.True(idx > 0, "第二段应落在独立视觉行");
            Assert.True(LineText(lines[idx]).StartsWith("乙段头部"),
                "section 边界必须是硬换行，实际行=" + LineText(lines[idx]));
            Assert.DoesNotContain("乙段", LineText(lines[idx - 1]));
        }

        [Fact]
        public void Plan_GiantIntro_StillBoundedByViewport()
        {
            var intro = new System.Text.StringBuilder();
            for (int i = 0; i < 120; i++) intro.Append("第").Append(i).Append("行简介说明文字，");
            var desc = new System.Text.StringBuilder();
            for (int i = 0; i < 200; i++) desc.Append("第").Append(i).Append("行描述说明文字，");
            NativeTooltipDocument doc = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'超长','profile':'dense',
                'sections':[
                  {'role':'intro','runs':[{'text':'" + intro + @"'}]},
                  {'role':'description','runs':[{'text':'" + desc + @"'}]}
                ]}"));
            var plan = NativeTooltipLayout.ComputePlan(doc, FixedMeasure, 15, 1f, 1024, 576);
            Assert.NotNull(plan);
            Assert.True(plan.Split, "双长文应分栏");
            int maxTipH = 576 - 2 * NativeTooltipLayout.Px(NativeTooltipLayout.ViewportInsetBase, 1f);
            Assert.True(plan.TipSize.Height <= maxTipH,
                "tip 高度必须受视口约束（intro 也要夹取），实际="
                    + plan.TipSize.Height + " > " + maxTipH);
            Assert.True(plan.TipSize.Width <= 1024 - 2 * NativeTooltipLayout.Px(
                NativeTooltipLayout.ViewportInsetBase, 1f));
        }

        // ════════════ 滚轮分派（host 实际入口 = OnMouseWheel）════════════

        [Fact]
        public void Wheel_DenseScrollable_ConsumesWhileShown()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(LongDensePayload()));
                Assert.True(w.Scrollable);
                // dense+Scrollable 显示期间滚轮归本注释滚动——不要求先移入浮层
                Assert.True(w.OnMouseWheel(new Point(20, 20), -120));
                Assert.True(w.ScrollLineOffset > 0);
                Assert.True(w.OnMouseWheel(new Point(900, 500), 120));
            }
        }

        [Fact]
        public void Wheel_DenseScrollable_OwnerBounds_GatesConsumption()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(LongDensePayload()));
                w.OwnerScreenBounds = new Rectangle(100, 100, 60, 40);
                Assert.False(w.OnMouseWheel(new Point(20, 20), -120), "owner bounds 外放行");
                Assert.True(w.OnMouseWheel(new Point(120, 120), -120), "owner bounds 内消费");
                Assert.True(w.ScrollLineOffset > 0);
                Assert.False(w.TryScrollAt(new Point(20, 20), -120), "TryScrollAt 同受 owner 约束");
                w.Hide("tt-long");
                Assert.False(w.OwnerScreenBounds.HasValue, "会话清除时 owner bounds 一并清");
            }
        }

        [Fact]
        public void Wheel_DenseNotScrollable_And_Simple_PassThrough()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                JObject dense = ComplexPayload("tt-d", 1);
                ((JObject)dense["document"])["profile"] = "dense";
                w.Show(dense);
                Assert.False(w.Scrollable, "短 dense 无溢出");
                Assert.False(w.OnMouseWheel(new Point(20, 20), -120));

                JObject simple = ComplexPayload("tt-s", 1);
                ((JObject)simple["document"])["profile"] = "simple";
                w.Show(simple);
                Assert.False(w.OnMouseWheel(new Point(20, 20), -120));
            }
        }

        // ════════════ paint 真实像素 / icon 真实目录 ════════════

        [Fact]
        public void Paint_Split_DescPanel_WebGradient_NoFrame()
        {
            // 权威 = 迁移前 Web：面板 = rgba(153,153,153,.8)→rgba(51,51,51,.8)
            // 垂直渐变、无边框无阴影；不得出现 NativeHud 填充/亮框线。
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(LongDensePayload()));
                var plan = w.ActivePlan;
                Assert.True(plan.Split);
                Assert.False(plan.DescPanel.IsEmpty);
                Rectangle placed = w.PlacedRect;
                // 无 handle → 客户区坐标域；hudOrigin=Empty 时画布=客户区
                using (var bmp = new Bitmap(1024, 576))
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.FromArgb(255, 24, 26, 28));
                    w.Paint(g, 1.0f, Point.Empty);
                    Rectangle dp = new Rectangle(placed.X + plan.DescPanel.X,
                        placed.Y + plan.DescPanel.Y, plan.DescPanel.Width, plan.DescPanel.Height);
                    // 顶区合成色 ≈ gradTop(204,153) over bg(24,26,28) ≈ (127,128,128)
                    int etr = (204 * 153 + 51 * 24) / 255;
                    int etg = (204 * 153 + 51 * 26) / 255;
                    int etb = (204 * 153 + 51 * 28) / 255;
                    // 底区合成色 ≈ gradBot(204,51) over bg ≈ (46,46,46)
                    int ebr = (204 * 51 + 51 * 24) / 255;
                    int ebg = (204 * 51 + 51 * 26) / 255;
                    int ebb = (204 * 51 + 51 * 28) / 255;
                    int topHit = 0, botHit = 0, total = 0;
                    // 采样面板 1px 内缘（文本从 pad=3 起，不踩字形像素）
                    int topBand = dp.Y + 1;
                    int botBand = dp.Bottom - 2;
                    for (int x = dp.X + 8; x < dp.Right - 8; x += 7)
                    {
                        total++;
                        Color pt = bmp.GetPixel(x, topBand);
                        if (Math.Abs(pt.R - etr) <= 4 && Math.Abs(pt.G - etg) <= 4
                            && Math.Abs(pt.B - etb) <= 4) topHit++;
                        Color pb = bmp.GetPixel(x, botBand);
                        if (Math.Abs(pb.R - ebr) <= 4 && Math.Abs(pb.G - ebg) <= 4
                            && Math.Abs(pb.B - ebb) <= 4) botHit++;
                    }
                    Assert.True(topHit * 2 >= total,
                        "desc 面板顶区应为 Web 灰渐变顶色，命中=" + topHit + "/" + total);
                    Assert.True(botHit * 2 >= total,
                        "desc 面板底区应为 Web 灰渐变底色，命中=" + botHit + "/" + total);
                    // 顶边中点 = 渐变顶色而非亮框线（Web 无边框；旧实现亮框 R>90 差异显著
                    // ——但渐变顶色本身≈127，须逐通道区分：亮框线是近纯白>200）
                    Color edge = bmp.GetPixel(dp.X + dp.Width / 2, dp.Y);
                    Assert.True(edge.R < 200 && edge.G < 200,
                        "desc 面板顶边不得有 NativeHud 亮框线，实际=" + edge);
                }
            }
        }

        [Fact]
        public void Paint_PlainSimple_WebPaddingAndGradient()
        {
            // plain 短提示：#panel-tooltip 原生框 pad 10/14、maxw 480、lh 1.5、无边框。
            JObject p = JObject.Parse(@"{
              'version':1,'requestId':'tt-plain','x':500,'y':200,
              'document':{'version':1,'profile':'simple',
                'sections':[{'role':'intro','runs':[{'text':'恢复 30% HP'}]}]}}");
            var doc = NativeTooltipDocument.FromPayload(p);
            var plan = NativeTooltipLayout.ComputePlan(doc, FixedMeasure, 15, 1f, 1024, 576);
            Assert.True(plan.Plain);
            Assert.Equal(NativeTooltipLayout.Px(
                NativeTooltipLayout.PlainPadXBase, 1f), plan.IntroContentLeftPx);
            Assert.Equal(NativeTooltipLayout.Px(
                NativeTooltipLayout.PlainPadYBase, 1f), plan.IntroContentTopPx);
            Assert.True(plan.TipSize.Width <= NativeTooltipLayout.Px(
                NativeTooltipLayout.PlainMaxWBase, 1f));
            Assert.False(plan.IntroPanel.IsEmpty);
        }

        // ════════════ layoutType（root 契约：doc.LayoutType，不由 icon 推断）════════════

        private static NativeTooltipDocument IconDoc(string layoutType)
        {
            string lt = layoutType == null ? ""
                : ",'layoutType':'" + layoutType + "'";
            return NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'布局','profile':'dense'" + lt + @",
                'icon':{'kind':'item','name':'x'},
                'sections':[{'role':'intro','runs':[{'text':'简介'}]}]}"));
        }

        [Fact]
        public void Plan_LayoutType_Narrow_UsesNarrowDims_EvenWithIcon()
        {
            var plan = NativeTooltipLayout.ComputePlan(
                IconDoc("narrow"), FixedMeasure, 15, 1f, 1024, 576);
            Assert.False(plan.LayoutWide);
            // narrow: intro 宽 120、icon 111、icon-text 间距 11、min-h 140
            Assert.Equal(120, plan.IntroPanel.Width);
            Assert.Equal(111, plan.IconRect.Width);
            Assert.True(plan.IntroPanel.Height >= 140);
        }

        [Fact]
        public void Plan_LayoutType_DefaultsWide_And_WideDims()
        {
            // 缺省 / 显式 wide / 非法值 → wide（文档侧已归一，plan 层再兜底）
            foreach (string lt in new string[] { null, "wide", "bogus" })
            {
                var plan = NativeTooltipLayout.ComputePlan(
                    IconDoc(lt), FixedMeasure, 15, 1f, 1024, 576);
                Assert.True(plan.LayoutWide, "layoutType=" + (lt ?? "null"));
                Assert.Equal(200, plan.IntroPanel.Width);
                Assert.Equal(192, plan.IconRect.Width);
            }
        }

        // ════════════ dense 检视状态条（input 侧投影 → widget）════════════

        [Fact]
        public void Inspection_Pending_AddsStrip_AbovePanels_GrowsTip()
        {
            var doc = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'检视','profile':'dense',
                'sections':[{'role':'intro','runs':[{'text':'简介'}]}]}"));
            var idle = NativeTooltipLayout.ComputePlan(
                doc, FixedMeasure, 15, 1f, 1024, 576);
            Assert.True(idle.InspStrip.IsEmpty, "无投影 → 无状态条");

            var pend = NativeTooltipLayout.ComputePlan(
                doc, FixedMeasure, 15, 1f, 1024, 576, "pending");
            Assert.False(pend.InspStrip.IsEmpty);
            Assert.Equal(NativeTooltipLayout.Px(
                NativeTooltipLayout.InspMinHBase, 1f), pend.InspStrip.Height);
            Assert.Equal(0, pend.InspStrip.Y);
            Assert.True(pend.InspStrip.Width <= pend.TipSize.Width);
            Assert.True(pend.InspMeterW > 0, "pending 须有进度槽");
            int off = pend.InspStrip.Height
                + NativeTooltipLayout.Px(NativeTooltipLayout.InspMarginBase, 1f);
            Assert.Equal(idle.IntroPanel.Y + off, pend.IntroPanel.Y);
            Assert.Equal(idle.TipSize.Height + off, pend.TipSize.Height);
        }

        [Fact]
        public void Inspection_Inspect_CollapsesToThinBar_ScanIdle_None()
        {
            var doc = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'检视','profile':'dense',
                'sections':[{'role':'intro','runs':[{'text':'简介'}]}]}"));
            var ins = NativeTooltipLayout.ComputePlan(
                doc, FixedMeasure, 15, 1f, 1024, 576, "inspect");
            Assert.False(ins.InspStrip.IsEmpty);
            Assert.Equal(NativeTooltipLayout.Px(
                NativeTooltipLayout.InspCollapsedHBase, 1f), ins.InspStrip.Height);
            Assert.True(ins.InspMeterW == 0, "inspect 无进度槽（meter display:none）");

            foreach (string st in new string[] { "scan", "idle", null, "bogus" })
            {
                var p = NativeTooltipLayout.ComputePlan(
                    doc, FixedMeasure, 15, 1f, 1024, 576, st);
                Assert.True(p.InspStrip.IsEmpty, "state=" + (st ?? "null"));
            }
        }

        [Fact]
        public void Inspection_NonDense_NoStrip()
        {
            // 状态条是 dense 专属（web ensureInspectionStatus 仅 dense 创建）
            var simple = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'简','profile':'simple',
                'icon':{'kind':'item','name':'x'},
                'sections':[{'role':'intro','runs':[{'text':'x'}]}]}"));
            var p1 = NativeTooltipLayout.ComputePlan(
                simple, FixedMeasure, 15, 1f, 1024, 576, "pending");
            Assert.True(p1.InspStrip.IsEmpty);

            var pinned = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'钉','profile':'pinned',
                'sections':[{'role':'intro','runs':[{'text':'x'}]}]}"));
            var p2 = NativeTooltipLayout.ComputePlan(
                pinned, FixedMeasure, 15, 1f, 1024, 576, "inspect");
            Assert.True(p2.InspStrip.IsEmpty);
        }

        [Fact]
        public void Widget_SetInspectionState_ProjectsIntoPlan_AndClearsOnHide()
        {
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(LongDensePayload()));
                Assert.True(w.ActivePlan.InspStrip.IsEmpty);

                w.SetInspectionState("pending", 800);
                Assert.Equal("pending", w.CurrentInspectionState);
                Assert.False(w.ActivePlan.InspStrip.IsEmpty,
                    "pending 投影应出现在排版计划");
                Assert.True(w.ActivePlan.InspStrip.Height >= 10, "pending 为全高条");

                w.SetInspectionState("inspect", 0);
                Assert.True(w.ActivePlan.InspStrip.Height <= 4,
                    "inspect 稳态折叠为细条");

                w.SetInspectionState("idle", 0);
                Assert.True(w.ActivePlan.InspStrip.IsEmpty);

                w.SetInspectionState("pending", 500);
                Assert.True(w.Hide("tt-long"));
                Assert.True("idle" == w.CurrentInspectionState, "hide 应清投影态");
            }
        }

        [Fact]
        public void Wheel_DenseScrollable_NoOwner_LimitedToClientRect()
        {
            // root 约定：ownerRect 缺失时至少限定 Flash 客户区，不全屏吞轮。
            using (Control a = Anchor())   // 无 handle → client 域 = (0,0,1024,576)
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(LongDensePayload()));
                Assert.True(w.Scrollable);
                Assert.False(w.OnMouseWheel(new Point(-50, 20), -120),
                    "客户区外不消费");
                Assert.False(w.OnMouseWheel(new Point(2000, 20), -120),
                    "客户区外不消费");
                Assert.True(w.OnMouseWheel(new Point(20, 20), -120),
                    "客户区内消费");
            }
        }

        [Fact]
        public void Icon_SkillKind_ResolvesViaSharedManifest()
        {
            // 技能图标与物品共用 icons/manifest.json（烘焙剥「图标-」前缀，裸技能名为键）：
            // 无需第二目录——catalog.TryGet(技能名) 直接命中 manifest 条目。
            string dir = Path.Combine(Path.GetTempPath(),
                "tt-icons-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            try
            {
                using (var b = new Bitmap(4, 4))
                    b.Save(Path.Combine(dir, "s.png"), System.Drawing.Imaging.ImageFormat.Png);
                File.WriteAllText(Path.Combine(dir, "manifest.json"),
                    "{ \"斩铁\": { \"f1\": \"s.png\" } }");
                using (var cat = new CF7Launcher.Guardian.Hud.Loot.LootIconCatalog(
                    dir, null, 4L * 1024 * 1024, null))
                {
                    CF7Launcher.Guardian.Hud.Loot.LootIconCatalog.LootIconFrames frames;
                    Assert.True(cat.TryGet("斩铁", out frames),
                        "技能名应命中共享 manifest（kind:skill 无独立目录）");
                    Assert.NotNull(frames.First);
                }
                // kind:"skill" 文档照常保留 icon 槽，由 name 直接解析
                NativeTooltipDocument doc = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                    'version':1,'title':'技能注释','profile':'dense',
                    'icon':{'kind':'skill','name':'斩铁'},
                    'sections':[{'role':'intro','runs':[{'text':'技能说明'}]}]}"));
                Assert.NotNull(doc.Icon);
                Assert.False(doc.Icon.IsItem);
                var plan = NativeTooltipLayout.ComputePlan(doc, FixedMeasure, 15, 1f, 1024, 576);
                Assert.Equal("斩铁", plan.IconName);
                Assert.False(plan.IconRect.IsEmpty);
            }
            finally { try { Directory.Delete(dir, true); } catch { } }
        }

        // ════════════ 行高 = 行内最大 run 字号 × em（root-font-probe Edge DOM 实证）════════════

        [Fact]
        public void Wrap_RunFontSize_RaisesThatLineHeight_LineBox()
        {
            // Edge DOM 实证（root-font-probe ryu-ichimonji web.json fontProbe）：
            // 12px 正文 → computed line-height 15px（1.25）；20px run → 25px。
            var runs = new List<NativeTooltipRun>
            {
                new NativeTooltipRun("普通行\n", null, false),
                new NativeTooltipRun("大字行", null, false, false, false, 20, null)
            };
            var lines = NativeTooltipLayout.WrapRuns(runs, 400, FixedMeasure, 15f);
            Assert.Equal(2, lines.Count);
            Assert.Equal(15f, lines[0].LineHeightF);
            Assert.Equal(25f, lines[1].LineHeightF);
            Assert.Equal(25, lines[1].LineHeightPx);
        }

        [Fact]
        public void Wrap_BigFontSoftWrap_RecalcsHeadAndCarryHeights()
        {
            // 软折进位：大字 run 断行后，头行/余行各按行内最大字号重算——
            // 高度不能由构造期常量或上一行残留带出。
            var runs = new List<NativeTooltipRun>
            {
                new NativeTooltipRun("小字\n", null, false),
                new NativeTooltipRun("大字大字大字", null, false, false, false, 20, null)
            };
            // maxW=50：宽字 12px/字，一行至多 4 字 → 大字段折成 2 行
            var lines = NativeTooltipLayout.WrapRuns(runs, 50, FixedMeasure, 15f);
            Assert.Equal(3, lines.Count);
            Assert.Equal(15f, lines[0].LineHeightF);
            Assert.Equal(25f, lines[1].LineHeightF);
            Assert.Equal(25f, lines[2].LineHeightF);
        }

        [Fact]
        public void Wrap_LateBigFontRun_RaisesWholeLine_NotNext()
        {
            // 行内后段才出现大字号 run → 本行整体抬高（line box = max(inline)），
            // 不回填前行、不遗留到下一行。
            var runs = new List<NativeTooltipRun>
            {
                new NativeTooltipRun("前段小字", null, false),
                new NativeTooltipRun("后段大", null, false, false, false, 20, null),
                new NativeTooltipRun("\n收尾", null, false)
            };
            var lines = NativeTooltipLayout.WrapRuns(runs, 400, FixedMeasure, 15f);
            Assert.Equal(2, lines.Count);
            Assert.Equal(25f, lines[0].LineHeightF);
            Assert.Equal(15f, lines[1].LineHeightF);
        }

        [Fact]
        public void Wrap_FontFace_PreservesSemanticField_OnSlices()
        {
            // fontFace 语义字段随 run→slice 保留（parity 核对用）；渲染端有效
            // 基线 = 正文体（legacy FONT FACE 畸形 style 实证），此处不断言字体名。
            var runs = new List<NativeTooltipRun>
            {
                new NativeTooltipRun("明朝体\n", null, false, false, false, null, "MS Mincho"),
                new NativeTooltipRun("宋体尾", null, false)
            };
            var lines = NativeTooltipLayout.WrapRuns(runs, 400, FixedMeasure, 15f);
            Assert.Equal(2, lines.Count);
            Assert.Equal("MS Mincho", lines[0].Slices[0].FontFace);
            Assert.Null(lines[1].Slices[0].FontFace);
            Assert.Equal(15f, lines[0].LineHeightF);
        }

        [Fact]
        public void Plan_PlainBigFont_PanelGrowsByActualHeights()
        {
            // plain 路径（lh 1.5）：20px run → 行高 30；面板高按逐行真实高
            // 浮点累加，不再按常量压算。
            var doc = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'profile':'simple',
                'sections':[{'role':'intro','runs':[
                    {'text':'小行'}, {'text':'\n'},
                    {'text':'大行','fontSize':20}]}]}"));
            var plan = NativeTooltipLayout.ComputePlan(doc, FixedMeasure, 18f, 1f, 1024, 576);
            Assert.True(plan.Plain);
            Assert.Equal(2, plan.IntroLines.Count);
            Assert.Equal(18f, plan.IntroLines[0].LineHeightF);
            Assert.Equal(30f, plan.IntroLines[1].LineHeightF);
            // padY=10×2 + 18+30 = 68
            Assert.Equal(68, plan.IntroPanel.Height);
        }

        [Fact]
        public void Plan_SplitScroll_VariableHeights_BackAccumulatesMaxScroll()
        {
            // 变行高滚动几何：vpH=183 → maxH=round(min(520,128.1))=128 →
            // descPanelH=128、viewH=120。11 行×15 自尾累加 8 行=120 顶格 →
            // MaxScrollLine=3；末行换 20px run（行高 25）→ 尾部只能装 7 行 →
            // MaxScrollLine=4。旧实现按常量行高 Count-Visible 算，两种情形同值。
            const string lineText = "第N行描述说明文字啊"; // 9 字 ≈102px < descTextW 146
            var parts = new List<string>();
            for (int i = 0; i < 11; i++)
            {
                if (i > 0) parts.Add("{'text':'\\n'}");
                parts.Add("{'text':'" + lineText + "'"
                    + (i == 10 ? ",'fontSize':20" : "") + "}");
            }
            string runsJson = string.Join(",", parts.ToArray());
            var docBig = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'滚动','profile':'dense',
                'sections':[{'role':'description','runs':[" + runsJson + "]}]}"));
            var planBig = NativeTooltipLayout.ComputePlan(
                docBig, FixedMeasure, 15f, 1f, 1024, 183);
            Assert.True(planBig.Split);
            Assert.Equal(11, planBig.DescTotalLines);
            Assert.Equal(8, planBig.DescVisibleLines);
            Assert.Equal(4, planBig.MaxScrollLine);
            Assert.True(planBig.DescScrollable);

            string runsPlain = runsJson.Replace(",'fontSize':20", "");
            var docNorm = NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'滚动','profile':'dense',
                'sections':[{'role':'description','runs':[" + runsPlain + "]}]}"));
            var planNorm = NativeTooltipLayout.ComputePlan(
                docNorm, FixedMeasure, 15f, 1f, 1024, 183);
            Assert.Equal(3, planNorm.MaxScrollLine);
        }

        [Fact]
        public void Plan_FractionalContentHeight_DoesNotInventScrolling()
        {
            // 1600×900 的20行正文总高312.5px。容器向下取整会伪造溢出，
            // 导致无需滚动的P90注释也进入等待检视状态。
            var runs = new JArray();
            for (int i = 0; i < 20; i++)
                runs.Add(new JObject { ["text"] = "描述说明文字一行" + (i < 19 ? "\n" : "") });
            var doc = NativeTooltipDocument.FromDocument(new JObject {
                ["version"] = 1, ["title"] = "完整正文", ["profile"] = "dense",
                ["sections"] = new JArray(new JObject {
                    ["role"] = "description", ["runs"] = runs }) });
            var plan = NativeTooltipLayout.ComputePlan(
                doc, FixedMeasure, 15.625f, 900f / 864f, 1600, 900);
            Assert.True(plan.Split);
            Assert.Equal(20, plan.DescTotalLines);
            Assert.False(plan.DescScrollable);
            Assert.Equal(0, plan.MaxScrollLine);
            Assert.True(plan.ScrollViewportRect.Height >= 312.5f);
        }

        [Fact]
        public void Widget_BigFontRun_LineHeightScales_NotConstant()
        {
            // 复刻 ryu-ichimonji 重叠事故：anchor 576 → scale=2/3，
            // 20px run 行物理高 = 25×2/3 ≈ 16.67（旧实现被常量 10 压叠）。
            JObject p = JObject.Parse(@"{
              'version':1,'requestId':'tt-big','x':500,'y':200,
              'document':{'version':1,'profile':'dense',
                'icon':{'kind':'item','name':'x'},
                'sections':[{'role':'intro','runs':[
                  {'text':'普通行'}, {'text':'\n'},
                  {'text':'大字行','fontSize':20}]}]}}");
            using (Control a = Anchor())
            using (var w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(p));
                var lines = w.ActivePlan.IntroLines;
                Assert.Equal(2, lines.Count);
                Assert.Equal(10f, lines[0].LineHeightF, 2);
                Assert.Equal(16.667f, lines[1].LineHeightF, 2);
            }
        }

        // ════════════ DPI：vh/vw 与定位常量在 CSS px 视口域求值 ════════════

        /// <summary>
        /// dominator 回归样本：30 行短句 desc + 短 intro。
        /// 物理行高 15.625（scale=900/864≈1.04167，物理/本地CSS 因子与 dpi 无关），
        /// 内容高 = ceil(30×15.625)+8 ≈ 477 物理 px —— 落在两档 70vh cap 之间：
        ///   dpi=1.5 → cssH=600 → maxH=min(420,520)=420css ≈ 438 物理 → 滚动
        ///   dpi=1.25 → cssH=720 → maxH=min(504,520)=504css ≈ 525 物理 → 不滚
        ///   dpi=1.0 → cssH=900 → maxH=min(630,520)=520css ≈ 542 物理 → 不滚
        /// （root dpi-web 实证：dominator/MACSIII/bloodsword 在 150% DPI 全部
        /// scrollMismatch；旧实现把物理 900 当 CSS 用 → cap≈542 恒不滚。）
        /// </summary>
        private static NativeTooltipDocument DpiParityDoc()
        {
            var parts = new List<string>();
            for (int i = 0; i < 30; i++)
            {
                if (i > 0) parts.Add("{'text':'\\n'}");
                parts.Add("{'text':'第" + i + "行描述说明文字啊'}");
            }
            string runsJson = string.Join(",", parts.ToArray());
            return NativeTooltipDocument.FromDocument(JObject.Parse(@"{
                'version':1,'title':'DPI 视口','profile':'dense',
                'sections':[
                  {'role':'intro','runs':[{'text':'简介'}]},
                  {'role':'description','runs':[" + runsJson + @"]}
                ]}"));
        }

        [Theory]
        [InlineData(1.5f, true)]
        [InlineData(1.25f, false)]
        [InlineData(1.0f, false)]
        public void Plan_DescMaxHeight_70vh_UsesCssViewport_NotPhysical(
            float dpiScale, bool expectScrollable)
        {
            // 同一物理视口 1500×900、同一 scale：仅 CSS 视口随 dpi 变化。
            var plan = NativeTooltipLayout.ComputePlan(
                DpiParityDoc(), FixedMeasure, 15.625f, 900f / 864f, 1500, 900,
                null, dpiScale);
            Assert.True(plan.Split, "desc 足够长应分栏");
            Assert.Equal(expectScrollable, plan.DescScrollable);
        }

        [Fact]
        public void Widget_DpiProvider_SamePhysicalViewport_FlipsScrollAt150()
        {
            // 注入式 provider：同一物理 client 1500×900，dpi 1.5/1.0 决定滚与不滚。
            var parts = new List<string>();
            for (int i = 0; i < 30; i++)
            {
                if (i > 0) parts.Add("{'text':'\\n'}");
                parts.Add("{'text':'第" + i + "行描述说明文字啊'}");
            }
            string runsJson = string.Join(",", parts.ToArray());
            JObject p = JObject.Parse(@"{
              'version':1,'requestId':'tt-dpi','x':500,'y':200,
              'document':{'version':1,'title':'DPI 视口','profile':'dense',
                'sections':[
                  {'role':'intro','runs':[{'text':'简介'}]},
                  {'role':'description','runs':[" + runsJson + @"]}
                ]}}");
            using (Control a = new Control { Size = new Size(1500, 900) })
            {
                using (var w150 = new NativeTooltipWidget(a, null, () => 1.5f))
                {
                    Assert.True(w150.Show(p));
                    Assert.True(w150.ActivePlan.DescScrollable,
                        "150% DPI：cssH=600 → 70vh=420 < 正文物理高 → 应滚动");
                    Assert.True(w150.Scrollable);
                }
                using (var w100 = new NativeTooltipWidget(a, null, () => 1.0f))
                {
                    Assert.True(w100.Show(p));
                    Assert.False(w100.ActivePlan.DescScrollable,
                        "100% DPI：cssH=900 → 70vh=630 顶 520px cap → 不滚动");
                }
            }
        }
    }
}
