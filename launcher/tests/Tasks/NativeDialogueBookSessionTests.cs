using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Guardian.Dialogue;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>wire v2 book 会话宿主：本地换句/closing 复活/冻结重试/epoch 门。
    /// 驱动面 = task.AdoptV2（采用队列直跑 dispatch=a=>a()）+ widget.InputRequested；
    /// 重试节拍经 task.BookRetryScheduler 注入手动队列。</summary>
    public sealed class NativeDialogueBookSessionTests
    {
        private sealed class Harness : IDisposable
        {
            internal readonly Control Anchor;
            internal readonly NativeDialogueWidget Widget;
            internal readonly NativeDialogueTask Task;
            internal readonly List<string> Sent = new List<string>();
            internal readonly Queue<Action> RetryQueue = new Queue<Action>();
            internal readonly List<long> RetryDelays = new List<long>();
            internal readonly List<Tuple<string, string, JObject>> Prefetches =
                new List<Tuple<string, string, JObject>>();
            internal readonly List<string> SceneLoads = new List<string>();
            internal bool InputAllowed = true;

            internal Harness()
            {
                Anchor = new Control { Size = new Size(1024, 576) };
                Widget = new NativeDialogueWidget(Anchor);
                Task = new NativeDialogueTask(Widget, a => a(),
                    wire => { Sent.Add(wire); return true; },
                    () => InputAllowed);
                Task.BookRetryScheduler = (ms, cb) => { RetryDelays.Add(ms); RetryQueue.Enqueue(cb); };
                Task.PrefetchPortrait = (k, e, app) => Prefetches.Add(Tuple.Create(k, e, app));
                Task.LoadSceneImage = (p, cb) => SceneLoads.Add(p);
            }

            internal void PumpRetry(int times = 1)
            {
                while (times-- > 0 && RetryQueue.Count > 0) RetryQueue.Dequeue()();
            }

            internal void Advance() { Widget.InputRequested(Widget.CurrentFrame, "advance"); }
            internal void Close() { Widget.InputRequested(Widget.CurrentFrame, "close"); }

            public void Dispose()
            {
                try { Widget.Dispose(); } catch { }
                try { Anchor.Dispose(); } catch { }
            }
        }

        private static JObject Line(string text, string key = "Andy Law",
            string imageAction = "keep")
        {
            return new JObject
            {
                ["name"] = "Andy Law", ["title"] = "雇佣兵", ["text"] = text,
                ["portrait"] = new JObject
                {
                    ["kind"] = "static", ["key"] = key, ["expression"] = "普通"
                },
                ["imageAction"] = imageAction
            };
        }

        private static JObject Book(int sequence, int lineCount, int startIndex = 0)
        {
            var lines = new JArray();
            for (int i = 0; i < lineCount; i++) lines.Add(Line("第" + i + "行"));
            return new JObject
            {
                ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                ["requestId"] = "nd:" + sequence, ["sceneId"] = "scene.1",
                ["mode"] = "ordinary", ["epoch"] = 1, ["startIndex"] = startIndex,
                ["advanceKey"] = 13, ["lines"] = lines
            };
        }

        private static JObject Append(string requestId, int baseEpoch, int epoch,
            int restartIndex = 0, int lineCount = 1)
        {
            var lines = new JArray();
            for (int i = 0; i < lineCount; i++) lines.Add(Line("追加" + i));
            return new JObject
            {
                ["version"] = 2, ["op"] = "append", ["requestId"] = requestId,
                ["sceneId"] = "scene.1", ["baseEpoch"] = baseEpoch,
                ["epoch"] = epoch, ["restartIndex"] = restartIndex, ["lines"] = lines
            };
        }

        private static JObject Ack(string json) { return JObject.Parse(json); }

        [Fact]
        public void BookAdoptsAndLocalAdvanceSendsNothing()
        {
            using var h = new Harness();
            JObject ack = Ack(h.Task.AdoptV2(Book(7, 2)));
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal(1, ack.Value<int>("appliedEpoch"));
            Assert.Equal(1, ack.Value<int>("requestedEpoch"));
            Assert.Equal("第0行", h.Widget.CurrentFrame.Text);
            Assert.Equal(1, h.Widget.CurrentFrame.Revision);

            h.Advance();
            Assert.Equal("第1行", h.Widget.CurrentFrame.Text);
            Assert.Equal(2, h.Widget.CurrentFrame.Revision);
            Assert.Empty(h.Sent);   // 本地换句零回程
        }

        [Fact]
        public void AdvancePastEndSendsFrozenFinishAndRetriesSameBytes()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 2));
            h.Advance();            // 到末行
            h.Advance();            // 越末行 → closing
            var finish = Assert.Single(h.Sent);
            JObject command = JObject.Parse(finish.TrimEnd('\0'));
            Assert.Equal("cmd", command.Value<string>("task"));
            Assert.Equal("nativeDialogueAction", command.Value<string>("action"));
            Assert.Equal("nd:7", command.Value<string>("requestId"));
            Assert.Equal("finish", command.Value<string>("verb"));
            Assert.Equal(1, command.Value<int>("epoch"));
            Assert.Equal(1, command.Value<int>("finalIndex"));   // 规范化行数-1
            Assert.Equal("advance_past_end", command.Value<string>("reason"));
            Assert.Null(command["revision"]);                    // v2 终态不带 revision

            h.PumpRetry(2);         // 两次重试逐字节相同
            Assert.Equal(3, h.Sent.Count);
            Assert.Equal(finish, h.Sent[1]);
            Assert.Equal(finish, h.Sent[2]);
            var delay = Assert.Single(h.RetryDelays.Distinct());
            Assert.InRange(delay, 500, 1000);                    // 节拍 0.5–1s
        }

        [Fact]
        public void CloseSendsFinishWithCloseReason()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(3, 3));
            h.Close();              // 显式关闭：未播完也进 closing
            var finish = Assert.Single(h.Sent);
            JObject command = JObject.Parse(finish.TrimEnd('\0'));
            Assert.Equal("close", command.Value<string>("reason"));
            Assert.Equal(2, command.Value<int>("finalIndex"));
        }

        [Fact]
        public void AppendRevivesClosingSessionAndCancelsRetry()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 1));
            h.Advance();            // 越末行 → closing，冻结 finish 已发
            Assert.Single(h.Sent);

            // restartIndex 是合并后数组下标：1 = 追加行
            JObject ack = Ack(h.Task.AdoptV2(Append("nd:7", 1, 2, restartIndex: 1)));
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal(2, ack.Value<int>("appliedEpoch"));
            Assert.Equal("追加0", h.Widget.CurrentFrame.Text);   // restartIndex 重播
            Assert.Equal(2, h.Widget.CurrentFrame.LineCount);    // 合并行集
            Assert.Equal(2, h.Widget.CurrentFrame.Revision);     // 本地 revision 继续单调

            h.PumpRetry(1);         // 复活已取消旧终态重试
            Assert.Single(h.Sent);  // 无新增发送

            h.Advance();            // 合并后末行（index1 已是末行）
            Assert.Equal(2, h.Sent.Count);
            JObject finish = JObject.Parse(h.Sent[1].TrimEnd('\0'));
            Assert.Equal(2, finish.Value<int>("epoch"));         // 新冻结请求用新代际
            Assert.Equal(1, finish.Value<int>("finalIndex"));
        }

        [Fact]
        public void SetDuringClosingAppliesKeyAndKeepsRetrying()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 1));
            h.Advance();            // closing
            var frozen = Assert.Single(h.Sent);

            JObject ack = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "set", ["requestId"] = "nd:7",
                ["sceneId"] = "scene.1", ["advanceKey"] = 32
            }));
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal(1, ack.Value<int>("appliedEpoch"));      // set 不 bump epoch
            Assert.NotNull(h.Task.CaptureKeyboardAction(32));     // advanceKey 已生效

            h.PumpRetry(1);         // set 不终止 closing：原冻结请求继续重试
            Assert.Equal(2, h.Sent.Count);
            Assert.Equal(frozen, h.Sent[1]);
        }

        [Fact]
        public void RejectedOpsDoNotTerminateClosing()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 1));
            h.Advance();            // closing
            var frozen = Assert.Single(h.Sent);

            // 更高 sequence 但被拒的报文（畸形 book：缺 lines）
            JObject badAck = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                ["requestId"] = "nd:9", ["sceneId"] = "scene.1",
                ["mode"] = "ordinary", ["epoch"] = 1
            }));
            Assert.Equal("rejected", badAck.Value<string>("status"));

            // 代际不连续的 append 同样不终止
            JObject gapAck = Ack(h.Task.AdoptV2(Append("nd:7", 5, 6)));
            Assert.Equal("epoch_gap", gapAck.Value<string>("reason"));
            Assert.Equal(1, gapAck.Value<int>("appliedEpoch"));

            h.PumpRetry(1);         // closing 仍在续试
            Assert.Equal(2, h.Sent.Count);
            Assert.Equal(frozen, h.Sent[1]);
        }

        [Fact]
        public void HideTerminatesClosingSession()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 1));
            h.Advance();            // closing
            h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "hide",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1"
            });
            Assert.Null(h.Widget.CurrentFrame);
            h.PumpRetry(1);
            Assert.Single(h.Sent);  // 重试已终止
        }

        [Fact]
        public void HigherSequenceBookTerminatesClosingSession()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 1));
            h.Advance();            // nd:7 closing
            JObject ack = Ack(h.Task.AdoptV2(Book(9, 2)));
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal("nd:9", h.Widget.CurrentFrame.RequestId);
            h.PumpRetry(1);
            Assert.Single(h.Sent);  // 旧会话冻结请求不再重试
        }

        [Fact]
        public void DisconnectTerminatesClosingSession()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 1));
            h.Advance();            // closing
            h.Task.HandleTransportDisconnected();
            Assert.Null(h.Widget.CurrentFrame);
            h.PumpRetry(1);
            Assert.Single(h.Sent);
        }

        [Fact]
        public void FirstInputGatedByInputAllowedButRetriesBypassIt()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 1));
            h.InputAllowed = false;
            h.Advance();            // 首击被输入门拦下：不进 closing 不发包
            Assert.Empty(h.Sent);
            Assert.Empty(h.RetryQueue);

            h.InputAllowed = true;
            h.Advance();            // 越末行 → closing
            Assert.Single(h.Sent);

            h.InputAllowed = false; // 已形成的终态请求重试不再经输入门
            h.PumpRetry(1);
            Assert.Equal(2, h.Sent.Count);
        }

        [Fact]
        public void NextLinePortraitIsPrefetchedSelfDriven()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 3));
            var first = Assert.Single(h.Prefetches);      // book 后即预取 index+1
            Assert.Equal("Andy Law", first.Item1);
            Assert.Null(first.Item3);                     // static 立绘 appearance=null

            h.Advance();                                  // 到 index1 → 预取 index2
            Assert.Equal(2, h.Prefetches.Count);
            h.Advance();                                  // 末行：无下一句不预取
            Assert.Equal(2, h.Prefetches.Count);
        }

        [Fact]
        public void StatusReportsActiveClosingAndNone()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 2));

            JObject active = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "status",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1"
            }));
            Assert.Equal("active", active.Value<string>("state"));
            Assert.Equal(1, active.Value<int>("appliedEpoch"));
            Assert.Equal(2, active.Value<int>("rowCount"));

            h.Advance(); h.Advance();                     // closing
            JObject closing = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "status",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1"
            }));
            Assert.Equal("closing", closing.Value<string>("state"));

            JObject none = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "status",
                ["requestId"] = "nd:99", ["sceneId"] = "scene.1"
            }));
            Assert.Equal("none", none.Value<string>("state"));
            Assert.Equal(0, none.Value<int>("appliedEpoch"));
        }

        [Fact]
        public void EpochGateRejectsNonInitialBookAndSkippedAppend()
        {
            using var h = new Harness();
            JObject badEpoch = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1",
                ["mode"] = "ordinary", ["epoch"] = 2,
                ["lines"] = new JArray(Line("x"))
            }));
            Assert.Equal("epoch_gap", badEpoch.Value<string>("reason"));

            h.Task.AdoptV2(Book(7, 1));
            JObject wrongBase = Ack(h.Task.AdoptV2(Append("nd:7", 2, 3)));
            Assert.Equal("epoch_gap", wrongBase.Value<string>("reason"));
            JObject skipEpoch = Ack(h.Task.AdoptV2(Append("nd:7", 1, 3)));
            Assert.Equal("epoch_gap", skipEpoch.Value<string>("reason"));
            Assert.Equal("nd:7", h.Widget.CurrentFrame.RequestId); // 会话不受影响
            JObject ok = Ack(h.Task.AdoptV2(Append("nd:7", 1, 2)));
            Assert.Equal("applied", ok.Value<string>("status"));
        }

        [Fact]
        public void DuplicateBookAndWrongSessionAreRejected()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 1));
            JObject dup = Ack(h.Task.AdoptV2(Book(7, 1)));
            Assert.Equal("rejected", dup.Value<string>("status"));
            Assert.Equal("stale_sequence", dup.Value<string>("reason"));

            JObject wrong = Ack(h.Task.AdoptV2(Append("nd:8", 1, 2)));
            Assert.Equal("wrong_session", wrong.Value<string>("reason"));
            JObject wrongScene = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "set", ["requestId"] = "nd:7",
                ["sceneId"] = "scene.other", ["advanceKey"] = 32
            }));
            Assert.Equal("wrong_session", wrongScene.Value<string>("reason"));
        }

        [Fact]
        public void MalformedPacksAreRejectedWhole()
        {
            using var h = new Harness();
            // op 白名单之外
            JObject badOp = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "rewind", ["requestId"] = "nd:7",
                ["sceneId"] = "scene.1"
            }));
            Assert.Equal("malformed", badOp.Value<string>("reason"));

            // epoch 缺失 / 非整数
            JObject noEpoch = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1",
                ["mode"] = "ordinary", ["lines"] = new JArray(Line("x"))
            }));
            Assert.Equal("malformed", noEpoch.Value<string>("reason"));
            Assert.Equal(JTokenType.Null, noEpoch["requestedEpoch"].Type);
            var badEpochType = (JObject)Book(7, 1).DeepClone();
            badEpochType["epoch"] = "1";
            Assert.Equal("malformed",
                Ack(h.Task.AdoptV2(badEpochType))["reason"].Value<string>());

            // append 任一行畸形 → 整包拒（已采用行集不受影响）
            h.Task.AdoptV2(Book(7, 1));
            var pack = Append("nd:7", 1, 2);
            ((JArray)pack["lines"])[0]["portrait"] = new JObject { ["kind"] = "bogus" };
            JObject lineBad = Ack(h.Task.AdoptV2(pack));
            Assert.Equal("malformed", lineBad.Value<string>("reason"));
            Assert.Equal(1, lineBad.Value<int>("appliedEpoch"));
            Assert.Equal("第0行", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void AppendBeyondMergedCapacityIsOversize()
        {
            using var h = new Harness();
            var lines = new JArray();
            for (int i = 0; i < 4096; i++) lines.Add(Line("x" + i));
            var book = (JObject)Book(7, 1).DeepClone();
            book["lines"] = lines;
            h.Task.AdoptV2(book);
            JObject ack = Ack(h.Task.AdoptV2(Append("nd:7", 1, 2)));
            Assert.Equal("oversize", ack.Value<string>("reason"));
        }

        [Fact]
        public void SourceBookWithoutAssemblerIsRejected()
        {
            using var h = new Harness();
            JObject ack = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "book", ["kind"] = "source",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1",
                ["mode"] = "ordinary", ["epoch"] = 1,
                ["sourceRef"] = new JObject
                {
                    ["type"] = "npc_dialogue", ["key"] = "酒保",
                    ["group"] = 0, ["contentVersion"] = "abc"
                },
                ["snapshot"] = new JObject { ["playerName"] = "p" }
            }));
            Assert.Equal("malformed", ack.Value<string>("reason"));
            Assert.Null(h.Widget.CurrentFrame);
        }

        [Fact]
        public void SourceBookAssemblesThroughRegisteredHook()
        {
            using var h = new Harness();
            h.Task.SourceAssembler = new StubAssembler(new List<JObject>
            {
                (JObject)Line("装配行0").DeepClone(), (JObject)Line("装配行1").DeepClone()
            });
            JObject ack = Ack(h.Task.AdoptV2(new JObject
            {
                ["version"] = 2, ["op"] = "book", ["kind"] = "source",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1",
                ["mode"] = "ordinary", ["epoch"] = 1,
                ["sourceRef"] = new JObject
                {
                    ["type"] = "npc_dialogue", ["key"] = "酒保",
                    ["group"] = 0, ["contentVersion"] = "abc"
                },
                ["snapshot"] = new JObject { ["playerName"] = "p" }
            }));
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal(2, ack.Value<int>("rowCount"));   // source 型回传规范化行数
            Assert.Equal("装配行0", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void AppendToActiveSessionMergesAndReplaysFromRestart()
        {
            using var h = new Harness();
            h.Task.AdoptV2(Book(7, 2));
            h.Advance();                                     // index=1
            JObject ack = Ack(h.Task.AdoptV2(Append("nd:7", 1, 2, restartIndex: 1, lineCount: 2)));
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal(2, ack.Value<int>("appliedEpoch"));
            Assert.Equal("第1行", h.Widget.CurrentFrame.Text);
            Assert.Equal(4, h.Widget.CurrentFrame.LineCount);
            Assert.Equal(3, h.Widget.CurrentFrame.Revision);   // 本地 revision 不随 restart 回退
        }

        private sealed class StubAssembler : INativeDialogueSourceAssembler
        {
            private readonly List<JObject> _lines;
            internal StubAssembler(List<JObject> lines) { _lines = lines; }
            public bool TryAssemble(JObject sourceRef, JObject snapshot,
                out List<JObject> lines, out int rowCount, out string rejectReason)
            {
                lines = _lines; rowCount = _lines.Count; rejectReason = null;
                return true;
            }
        }
    }
}
