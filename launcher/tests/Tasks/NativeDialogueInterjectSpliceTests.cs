using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// G0-2：Host 本地增强行（插话新增/改写/拆分）不得改变 AS2 的 wire 行数口径。
    ///
    /// 契约来源：
    /// - 《协议》D-20 / 9：结束用 AS2 原始 rowCount-1 发 advance_past_end；提前关闭用 close，
    ///   finalIndex 在原始范围内；
    /// - NativeDialogueService.handleV2Action：advance_past_end 要求 finalIndex == rowCount-1，
    ///   close 要求 finalIndex ∈ [0, rowCount-1]。
    ///
    /// 驱动面与 NativeDialogueBookSessionTests 一致：AdoptV2 直跑（dispatch = 同步），
    /// widget.InputRequested 触发 advance/close。
    /// </summary>
    public sealed class NativeDialogueInterjectSpliceTests
    {
        private sealed class Harness : IDisposable
        {
            internal readonly Control Anchor;
            internal readonly NativeDialogueWidget Widget;
            internal readonly NativeDialogueTask Task;
            internal readonly List<string> Sent = new List<string>();

            internal Harness()
            {
                Anchor = new Control { Size = new Size(1024, 576) };
                Widget = new NativeDialogueWidget(Anchor);
                Task = new NativeDialogueTask(Widget, a => a(),
                    wire => { Sent.Add(wire); return true; },
                    () => true);
                Task.BookRetryScheduler = (ms, cb) => { };
            }

            internal NativeDialogueBookSession Session
            {
                get { return Task.BookSessionForTest; }
            }

            internal void Advance() { Widget.InputRequested(Widget.CurrentFrame, "advance"); }
            internal void Close() { Widget.InputRequested(Widget.CurrentFrame, "close"); }

            internal JObject LastSent()
            {
                Assert.NotEmpty(Sent);
                return JObject.Parse(Sent[Sent.Count - 1].TrimEnd('\0'));
            }

            public void Dispose()
            {
                try { Widget.Dispose(); } catch { }
                try { Anchor.Dispose(); } catch { }
            }
        }

        private static JObject WireLine(string text)
        {
            return new JObject
            {
                ["name"] = "Andy Law", ["title"] = "雇佣兵", ["text"] = text,
                ["portrait"] = new JObject
                {
                    ["kind"] = "static", ["key"] = "Andy Law", ["expression"] = "普通"
                },
                ["imageAction"] = "keep"
            };
        }

        private static JObject Book(int sequence, params string[] texts)
        {
            var lines = new JArray();
            for (int i = 0; i < texts.Length; i++) lines.Add(WireLine(texts[i]));
            return new JObject
            {
                ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                ["requestId"] = "nd:" + sequence, ["sceneId"] = "scene.1",
                ["mode"] = "ordinary", ["epoch"] = 1, ["startIndex"] = 0,
                ["advanceKey"] = 13, ["lines"] = lines
            };
        }

        private static JObject Append(string requestId, int baseEpoch, int epoch, params string[] texts)
        {
            var lines = new JArray();
            for (int i = 0; i < texts.Length; i++) lines.Add(WireLine(texts[i]));
            return new JObject
            {
                ["version"] = 2, ["op"] = "append", ["requestId"] = requestId,
                ["sceneId"] = "scene.1", ["baseEpoch"] = baseEpoch, ["epoch"] = epoch,
                ["restartIndex"] = 0, ["lines"] = lines
            };
        }

        /// <summary>本地增强行：WireIndex = -1（纯 Host 新增，不占 AS2 行号）。</summary>
        private static NativeDialogueBookSession.Line Local(string text)
        {
            return new NativeDialogueBookSession.Line
            {
                Name = "Andy Law", Title = "雇佣兵", Text = text,
                PortraitKey = "Andy Law", Expression = "普通",
                ImageAction = "keep", ImagePath = ""
            };
        }

        /// <summary>改写行：占用原第 wireIndex 条（播放后该原始行算已越过）。</summary>
        private static NativeDialogueBookSession.Line Edited(int wireIndex, string text)
        {
            NativeDialogueBookSession.Line line = Local(text);
            line.WireIndex = wireIndex;
            return line;
        }

        [Fact]
        public void LocalAdditionsDoNotChangeWireRowCountAndFinishUsesOriginalLastIndex()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, "第0行", "第1行", "第2行"));
            Assert.Equal(3, h.Session.RowCount);          // AS2 口径
            Assert.Equal(3, h.Session.PlaybackCount);

            // 播到原末行（index 2），再在尾部接两条本地新增（不接回原文）
            h.Advance(); h.Advance();
            Assert.Equal("第2行", h.Widget.CurrentFrame.Text);
            Assert.True(h.Session.ReplaceFrom(3,
                new[] { Local("本地新增0"), Local("本地新增1") }, null));

            Assert.Equal(3, h.Session.RowCount);          // wire 行数不变
            Assert.Equal(5, h.Session.PlaybackCount);     // 播放序列 +2
            Assert.Equal("本地新增0", h.Widget.CurrentFrame.Text);
            Assert.Equal(5, h.Widget.CurrentFrame.LineCount);   // 播放序列长度，widget 只用于显示

            h.Advance();
            Assert.Equal("本地新增1", h.Widget.CurrentFrame.Text);
            h.Advance();                                  // 越末行 → closing
            JObject finish = h.LastSent();
            Assert.Equal("finish", finish.Value<string>("verb"));
            Assert.Equal("advance_past_end", finish.Value<string>("reason"));
            // 关键断言：AS2 原始最后一行的 finalIndex = 2，而不是增强行数 4
            Assert.Equal(2, finish.Value<int>("finalIndex"));
            Assert.Equal(1, finish.Value<int>("epoch"));
        }

        [Fact]
        public void EarlyCloseUsesOriginalIndexInsideWireRange()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, "第0行", "第1行", "第2行"));

            // 在第 1 条前插入一条本地 AI 台词并接回原第 1 条
            Assert.True(h.Session.ReplaceFrom(1, new[] { Local("AI 插话") }, 1));
            Assert.Equal("AI 插话", h.Widget.CurrentFrame.Text);
            Assert.Equal(0, h.Session.CurrentWireIndex);   // 增强行不推进原始行号

            h.Close();
            JObject finish = h.LastSent();
            Assert.Equal("close", finish.Value<string>("reason"));
            int finalIndex = finish.Value<int>("finalIndex");
            Assert.InRange(finalIndex, 0, 2);              // AS2 只校验范围
            Assert.Equal(0, finalIndex);                   // 当前值 = 已走过的最后一条原始行
        }

        [Fact]
        public void ReplaceInPlaceSwapsOriginalRowAndKeepsResumePoint()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, "第0行", "第1行", "第2行"));
            h.Advance();                                   // index=1（原第 1 行）

            Assert.True(h.Session.ReplaceFrom(1, new[] { Edited(1, "改写后的第1行") }, 2));
            Assert.Equal("改写后的第1行", h.Widget.CurrentFrame.Text);
            Assert.Equal(3, h.Session.RowCount);
            Assert.Equal(3, h.Session.PlaybackCount);
            Assert.Equal(1, h.Session.CurrentWireIndex);

            h.Advance();                                   // 接回原第 2 行
            Assert.Equal("第2行", h.Widget.CurrentFrame.Text);
            Assert.Equal(2, h.Session.CurrentWireIndex);
            h.Advance();
            Assert.Equal(2, h.LastSent().Value<int>("finalIndex"));
            Assert.Equal("advance_past_end", h.LastSent().Value<string>("reason"));
        }

        [Fact]
        public void SplitReplacementPlaysSegmentsInOrderAndMapsBothToSameWireRow()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, "第0行", "第1行", "第2行"));
            h.Advance();

            // 一条原台词被拆成两段：两段都占用原第 1 条
            Assert.True(h.Session.ReplaceFrom(1,
                new[] { Edited(1, "段0"), Edited(1, "段1") }, 2));
            Assert.Equal("段0", h.Widget.CurrentFrame.Text);
            Assert.Equal(4, h.Session.PlaybackCount);
            Assert.Equal(3, h.Session.RowCount);

            h.Advance();
            Assert.Equal("段1", h.Widget.CurrentFrame.Text);
            Assert.Equal(1, h.Session.CurrentWireIndex);   // 两段都算原第 1 条
            h.Advance();
            Assert.Equal("第2行", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal(2, h.LastSent().Value<int>("finalIndex"));
        }

        [Fact]
        public void WireAppendAfterLocalEnhancementStillFinishesAtWireLastIndex()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, "第0行", "第1行", "第2行"));
            Assert.True(h.Session.ReplaceFrom(3, new[] { Local("本地新增") }, null));
            Assert.Equal("本地新增", h.Widget.CurrentFrame.Text);

            // AS2 追加两条原始行：wire 行数变成 5，播放序列 = 4 + 2
            JObject ack = JObject.Parse(h.Task.AdoptV2(Append("nd:7", 1, 2, "追加0", "追加1")));
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal(2, ack.Value<int>("appliedEpoch"));
            Assert.Equal(5, h.Session.RowCount);
            Assert.Equal(6, h.Session.PlaybackCount);

            // 追加后从 restartIndex 0 重播：走完 6 条
            for (int i = 0; i < 5; i++) h.Advance();
            Assert.Equal("追加1", h.Widget.CurrentFrame.Text);
            h.Advance();
            JObject finish = h.LastSent();
            Assert.Equal("advance_past_end", finish.Value<string>("reason"));
            Assert.Equal(4, finish.Value<int>("finalIndex"));   // wire 5 行 → 4
        }

        [Fact]
        public void ReplaceFromRejectsInvalidArgumentsWithoutTouchingPlayback()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, "第0行", "第1行"));

            Assert.False(h.Session.ReplaceFrom(-1, new[] { Local("x") }, null));
            Assert.False(h.Session.ReplaceFrom(3, new[] { Local("x") }, null));   // > PlaybackCount
            Assert.False(h.Session.ReplaceFrom(0, null, 5));                      // resume 越界
            Assert.False(h.Session.ReplaceFrom(0, new NativeDialogueBookSession.Line[] { null }, null));   // 空行
            var tooHigh = Local("y");
            tooHigh.WireIndex = 9;
            Assert.False(h.Session.ReplaceFrom(0, new[] { tooHigh }, null));
            Assert.Equal("第0行", h.Widget.CurrentFrame.Text);
            Assert.Equal(2, h.Session.PlaybackCount);

            // closing 之后不再接受本地增强
            h.Advance(); h.Advance();
            Assert.Equal(NativeDialogueBookSession.HostState.Closing, h.Session.State);
            Assert.False(h.Session.ReplaceFrom(0, new[] { Local("z") }, null));
        }

        [Fact]
        public void SkipToResumeDropsRemovedOriginalRowsFromPlayback()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, "第0行", "第1行", "第2行", "第3行"));
            h.Advance();                                   // 到原第 1 行

            // 跳到原第 3 行：原第 1、2 行不再播放（任务模式 remove 的等价形态）
            Assert.True(h.Session.ReplaceFrom(1, new NativeDialogueBookSession.Line[0], 3));
            Assert.Equal("第3行", h.Widget.CurrentFrame.Text);
            Assert.Equal(3, h.Session.CurrentWireIndex);
            Assert.Equal(4, h.Session.RowCount);           // AS2 仍认为有 4 行
            Assert.Equal(2, h.Session.PlaybackCount);      // 本地只剩 [第0行, 第3行]

            h.Advance();
            Assert.Equal(3, h.LastSent().Value<int>("finalIndex"));
            Assert.Equal("advance_past_end", h.LastSent().Value<string>("reason"));
        }
    }
}
