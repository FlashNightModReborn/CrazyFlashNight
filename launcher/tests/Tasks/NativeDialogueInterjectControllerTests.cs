using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.RagTerminal;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// P2 / G2：日常核心（成功轮不接回原文、失败轮接回、逐句输入、拆分暂锁、中途插入参考续写、
    /// closing 收尾、重复触发）＋ dialogueKind 组类型门控。
    ///
    /// 驱动面：NativeDialogueTask.AdoptV2（dispatch 同步）+ 假传输（脚本化 SSE）+
    /// 注入 ID/时钟；不调真模型、不起 HTTP、不构造窗口。
    /// </summary>
    public sealed class NativeDialogueInterjectControllerTests
    {
        private sealed class ScriptedTransport : IDialogueInterjectTransport
        {
            private readonly Queue<string> _scripts = new Queue<string>();
            internal string LastRequest;
            internal readonly List<string> Requests = new List<string>();
            internal readonly List<string> Finalizes = new List<string>();
            internal int OpenCount;
            internal Func<string, Task<Stream>> OpenAsyncOverride;

            internal void Script(string sse) { _scripts.Enqueue(sse); }

            internal string LastFinalize
            {
                get { return Finalizes.Count > 0 ? Finalizes[Finalizes.Count - 1] : null; }
            }

            public Task<Stream> OpenAsync(string requestJson, CancellationToken cancellationToken)
            {
                LastRequest = requestJson;
                Requests.Add(requestJson);
                OpenCount++;
                if (OpenAsyncOverride != null) return OpenAsyncOverride(requestJson);
                string payload = _scripts.Count > 0 ? _scripts.Dequeue() : "";
                return Task.FromResult<Stream>(new MemoryStream(Encoding.UTF8.GetBytes(payload)));
            }

            public Task<JObject> PostFinalizeAsync(string requestJson, CancellationToken cancellationToken)
            {
                Finalizes.Add(requestJson);
                return Task.FromResult(new JObject
                {
                    ["ok"] = true,
                    ["dialogue_instance_id"] = "inst",
                    ["session_id"] = "s1",
                    ["appended"] = 0,
                    ["total"] = 0
                });
            }
        }

        /// <summary>先吐若干字节再永久阻塞的流（模拟"流没结束、玩家关闭/再插话"）。</summary>
        private sealed class HangingStream : Stream
        {
            private readonly byte[] _head;
            private int _pos;
            private readonly ManualResetEventSlim _gate = new ManualResetEventSlim(false);
            internal volatile bool Disposed;

            internal HangingStream(string head) { _head = Encoding.UTF8.GetBytes(head); }

            public override bool CanRead { get { return true; } }
            public override bool CanSeek { get { return false; } }
            public override bool CanWrite { get { return false; } }
            public override long Length { get { return _head.Length; } }
            public override long Position
            {
                get { return _pos; }
                set { throw new NotSupportedException(); }
            }
            public override void Flush() { }
            public override int Read(byte[] buffer, int offset, int count)
            {
                if (_pos < _head.Length)
                {
                    int take = Math.Min(count, _head.Length - _pos);
                    Array.Copy(_head, _pos, buffer, offset, take);
                    _pos += take;
                    return take;
                }
                _gate.Wait(TimeSpan.FromSeconds(10));
                throw new ObjectDisposedException("HangingStream");
            }
            public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
            public override void SetLength(long value) { throw new NotSupportedException(); }
            public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
            protected override void Dispose(bool disposing)
            {
                if (disposing) { Disposed = true; _gate.Set(); }
                base.Dispose(disposing);
            }
        }

        private sealed class Harness : IDisposable
        {
            internal readonly Control Anchor;
            internal readonly NativeDialogueWidget Widget;
            internal readonly NativeDialogueTask Task;
            internal readonly ScriptedTransport Transport = new ScriptedTransport();
            internal readonly NativeDialogueInterjectController Controller;
            internal readonly List<DialogueInterjectInputState> States = new List<DialogueInterjectInputState>();
            internal readonly List<string> Sent = new List<string>();
            private int _ids;

            internal Harness(bool inline = true)
            {
                Anchor = new Control { Size = new Size(1024, 576) };
                Widget = new NativeDialogueWidget(Anchor);
                Task = new NativeDialogueTask(Widget, a => a(),
                    wire => { Sent.Add(wire); return true; }, () => true);
                Task.BookRetryScheduler = (ms, cb) => { };
                Controller = new NativeDialogueInterjectController(
                    Task, Widget, a => a(), null, () => Transport,
                    () => "id-" + (++_ids), () => new DateTime(2026, 10, 18, 22, 30, 0));
                if (inline)
                    Controller.TaskRunner = f =>
                    {
                        f().GetAwaiter().GetResult();
                        return System.Threading.Tasks.Task.CompletedTask;
                    };
                Controller.InputStateChanged += s => States.Add(s);
                Controller.Attach();
            }

            internal void AdoptBook(params string[] texts)
            {
                AdoptBookInMode(7, "ordinary", null, texts);
            }

            internal void AdoptBookInMode(int sequence, string mode, string dialogueKind,
                params string[] texts)
            {
                var lines = new JArray();
                for (int i = 0; i < texts.Length; i++)
                {
                    lines.Add(new JObject
                    {
                        ["name"] = "Andy Law", ["title"] = "雇佣兵", ["text"] = texts[i],
                        ["portrait"] = new JObject
                        {
                            ["kind"] = "static", ["key"] = "Andy Law", ["expression"] = "普通"
                        },
                        ["imageAction"] = "keep"
                    });
                }
                var book = new JObject
                {
                    ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                    ["requestId"] = "nd:" + sequence, ["sceneId"] = "scene.1",
                    ["mode"] = mode, ["epoch"] = 1, ["startIndex"] = 0,
                    ["advanceKey"] = 13, ["lines"] = lines
                };
                if (dialogueKind != null) book["dialogueKind"] = dialogueKind;
                Task.AdoptV2(book);
            }

            internal void Append(int sequence, int baseEpoch, string text)
            {
                Task.AdoptV2(new JObject
                {
                    ["version"] = 2, ["op"] = "append", ["requestId"] = "nd:" + sequence,
                    ["sceneId"] = "scene.1", ["baseEpoch"] = baseEpoch, ["epoch"] = baseEpoch + 1,
                    ["restartIndex"] = 0,
                    ["lines"] = new JArray(new JObject
                    {
                        ["name"] = "Andy Law", ["title"] = "雇佣兵", ["text"] = text,
                        ["portrait"] = new JObject
                        {
                            ["kind"] = "static", ["key"] = "Andy Law", ["expression"] = "普通"
                        },
                        ["imageAction"] = "keep"
                    })
                });
            }

            internal void Advance() { Widget.InputRequested(Widget.CurrentFrame, "advance"); }
            internal void Close() { Widget.InputRequested(Widget.CurrentFrame, "close"); }

            internal JObject LastFinish()
            {
                for (int i = Sent.Count - 1; i >= 0; i--)
                {
                    JObject command = JObject.Parse(Sent[i].TrimEnd('\0'));
                    if (command.Value<string>("verb") == "finish") return command;
                }
                return null;
            }

            public void Dispose()
            {
                try { Controller.Dispose(); } catch { }
                try { Widget.Dispose(); } catch { }
                try { Anchor.Dispose(); } catch { }
            }
        }

        private static string AddLine(string text, int seq, string kind = "add")
        {
            return "event: line\ndata: {\"kind\":\"" + kind + "\",\"text\":\"" + text
                + "\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":" + seq + "}\n\n";
        }

        private static string Done()
        {
            return "event: done\ndata: {\"dialogue_instance_id\":\"inst\",\"session_id\":\"s1\",\"usage\":{}}\n\n";
        }

        // ── 组类型门控 ─────────────────────────────────────────────────────

        [Theory]
        [InlineData(null, "Ready")]
        [InlineData("daily", "Ready")]
        [InlineData("task_pre", "Hidden")]
        [InlineData("task_post", "Hidden")]
        [InlineData("stage", "Hidden")]
        public void DialogueKindGatesInterject(string kind, string expectedState)
        {
            using var h = new Harness();
            h.AdoptBookInMode(7, "ordinary", kind, "又是你。", "有事说事。");
            Assert.Equal(expectedState, h.Controller.InputState.ToString());
            if (expectedState == "Ready")
                Assert.True(h.Controller.Submit("插一句"));
            else
                Assert.False(h.Controller.Submit("插一句"));
        }

        [Fact]
        public void StageModeNeverEnablesInterjectEvenWithoutKind()
        {
            using var h = new Harness();
            h.AdoptBookInMode(7, "stage", null, "场景一", "场景二");
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);
            Assert.False(h.Controller.Submit("插一句"));
            Assert.Equal(0, h.Transport.OpenCount);
        }

        [Fact]
        public void InvalidDialogueKindIsRejectedWhole()
        {
            using var h = new Harness();
            var book = new JObject
            {
                ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1",
                ["mode"] = "ordinary", ["epoch"] = 1, ["startIndex"] = 0,
                ["advanceKey"] = 13, ["dialogueKind"] = "gossip",
                ["lines"] = new JArray(new JObject
                {
                    ["name"] = "Andy Law", ["title"] = "雇佣兵", ["text"] = "又是你。",
                    ["portrait"] = new JObject
                    {
                        ["kind"] = "static", ["key"] = "Andy Law", ["expression"] = "普通"
                    },
                    ["imageAction"] = "keep"
                })
            };
            JObject ack = JObject.Parse(h.Task.AdoptV2(book));
            Assert.Equal("malformed", ack.Value<string>("reason"));
            Assert.Null(h.Widget.CurrentFrame);
        }

        [Fact]
        public void AppendKeepsGroupKindAndSession()
        {
            using var h = new Harness();
            h.AdoptBookInMode(7, "ordinary", "daily", "又是你。");
            var session = h.Task.BookSessionForTest;
            h.Append(7, 1, "追加一句");
            Assert.Same(session, h.Task.BookSessionForTest);
            Assert.Equal("daily", h.Task.BookSessionForTest.DialogueKind);
        }

        // ── 发送 / 请求形状 ────────────────────────────────────────────────

        [Fact]
        public void SubmitPlaysPcLineAndBuildsProtocolRequest()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。", "没事就别挡道。");
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);

            h.Transport.Script(AddLine("还能怎么样，老样子。", 0) + Done());
            Assert.True(h.Controller.Submit("  最近怎么样？  "));

            Assert.Equal("$PC", h.Widget.CurrentFrame.Name);
            Assert.Equal("最近怎么样？", h.Widget.CurrentFrame.Text);
            Assert.Equal(3, h.Task.BookSessionForTest.RowCount);       // wire 行数不变
            Assert.Equal(2, h.Task.BookSessionForTest.PlaybackCount);  // 成功轮：原作剩余不进播放序列
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            JObject request = JObject.Parse(h.Transport.LastRequest);
            Assert.Equal("daily", request.Value<string>("mode"));
            Assert.Equal("Andy Law", request.Value<string>("npc"));
            Assert.Equal("最近怎么样？", request.Value<string>("player_input"));
            Assert.False(string.IsNullOrEmpty(request.Value<string>("dialogue_instance_id")));
            Assert.False(string.IsNullOrEmpty(request.Value<string>("turn_id")));
            Assert.Equal("日常插话 · Andy Law · 2026-10-18 22:30", request.Value<string>("session_title"));
            Assert.Equal(JTokenType.Null, request["task_context"].Type);
            Assert.Equal(165, request["limits"].Value<int>("line_hard_max"));
            Assert.Equal(135, request["limits"].Value<int>("line_prompt_max"));

            JObject dialogue = (JObject)request["dialogue"];
            Assert.Equal("daily", dialogue.Value<string>("kind"));
            Assert.Equal("nd:7", dialogue.Value<string>("group_id"));
            var played = (JArray)dialogue["played"];
            Assert.Single(played);
            Assert.Equal("npc", played[0].Value<string>("role"));
            Assert.Equal("又是你。", played[0].Value<string>("text"));
            var remaining = (JArray)dialogue["remaining"];
            Assert.Equal(2, remaining.Count);
            Assert.Equal(1, remaining[0].Value<int>("index"));
            Assert.Equal("有事说事。", remaining[0].Value<string>("text"));
            Assert.Empty((JArray)dialogue["reference_continuation"]);
        }

        // ── 首句 / 成功轮 ─────────────────────────────────────────────────

        [Fact]
        public void FirstLineQueuesWhilePcPlaysThenStartsOnTypingFinished()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。");
            h.Transport.Script(AddLine("第一句", 0) + AddLine("第二句", 1) + Done());

            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.Equal(2, h.Controller.PendingLineCount);
            Assert.Equal("$PC", h.Widget.CurrentFrame.Name);
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);
            Assert.Equal(new[]
            {
                DialogueInterjectInputState.Ready,
                DialogueInterjectInputState.Hidden
            }, h.States);

            Assert.True(h.Widget.CompleteCurrentLineTyping());
            Assert.Equal("第一句", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
            Assert.Equal(0, h.Controller.PendingLineCount);

            h.Advance();
            Assert.Equal("第二句", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void SuccessTurnEndsAtLastAiLineWithoutResumingOriginal()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。", "没事就别挡道。");
            h.Transport.Script(AddLine("AI 第一句", 0) + AddLine("AI 第二句", 1) + Done());

            Assert.True(h.Controller.Submit("最近怎么样？"));
            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal("AI 第一句", h.Widget.CurrentFrame.Text);

            h.Advance();
            Assert.Equal("AI 第二句", h.Widget.CurrentFrame.Text);

            h.Advance();                                        // 末行之后 → closing
            Assert.True(h.Controller.ClosingForTest);
            JObject finish = h.LastFinish();
            Assert.NotNull(finish);
            Assert.Equal("advance_past_end", finish.Value<string>("reason"));
            Assert.Equal(2, finish.Value<int>("finalIndex"));    // AS2 原始末行
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);
            Assert.False(h.Controller.Submit("再来一句"));
        }

        [Fact]
        public void LastAddWithoutClosingStaysOnScreenAndDoesNotAutoClose()
        {
            // 结束语为空：最后一条 add 就是结束语，不自动关闭（D-16）。
            using var h = new Harness();
            h.AdoptBook("又是你。");
            h.Transport.Script(AddLine("只有一句", 0) + Done());
            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal("只有一句", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.ClosingForTest);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        // ── 拆分暂锁 ──────────────────────────────────────────────────────

        [Fact]
        public void SplitIntermediateLocksInputUntilLastSegment()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。");
            const string split0 =
                "event: line\ndata: {\"kind\":\"add\",\"text\":\"段0\",\"emotion\":\"普通\","
                + "\"speaker\":\"Andy Law\",\"seq\":0,\"split\":{\"index\":0,\"count\":2}}\n\n";
            const string split1 =
                "event: line\ndata: {\"kind\":\"add\",\"text\":\"段1\",\"emotion\":\"普通\","
                + "\"speaker\":\"Andy Law\",\"seq\":1,\"split\":{\"index\":1,\"count\":2}}\n\n";
            h.Transport.Script(split0 + split1 + Done());

            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal("段0", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Locked, h.Controller.InputState);
            Assert.False(h.Controller.Submit("插不了"));

            h.Advance();
            Assert.Equal("段1", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        // ── 失败回退 ──────────────────────────────────────────────────────

        [Fact]
        public void ZeroLineFailureRestoresOriginalTail()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。", "没事就别挡道。");
            h.Transport.Script(
                "event: error\ndata: {\"code\":\"no_valid_lines\",\"message\":\"零条\",\"valid_lines\":0}\n\n");

            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.Equal("$PC", h.Widget.CurrentFrame.Name);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
            Assert.Equal("no_valid_lines", h.Controller.LastFailure);

            h.Advance();
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);   // 接回原作
            Assert.True(h.Transport.Finalizes.Count > 0);
        }

        [Fact]
        public void PartialFailureResumesOriginalAfterPlayedAiLines()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。", "没事就别挡道。");
            h.Transport.Script(
                AddLine("先听我说。", 0)
                + "event: error\ndata: {\"code\":\"stream_failed\",\"message\":\"断流\",\"valid_lines\":1}\n\n");

            Assert.True(h.Controller.Submit("最近怎么样？"));
            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal("先听我说。", h.Widget.CurrentFrame.Text);
            Assert.Equal("stream_failed", h.Controller.LastFailure);

            h.Advance();                                            // 已播 AI 行之后接回原作
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);
            Assert.Contains("先听我说。", h.Transport.LastFinalize);
        }

        // ── 中途插入 / 参考续写 ───────────────────────────────────────────

        [Fact]
        public void MidTurnInsertCarriesUnplayedLinesAsReference()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。");
            h.Transport.Script(
                AddLine("第一句", 0) + AddLine("第二句", 1) + AddLine("第三句", 2) + Done());
            h.Transport.Script(AddLine("新回答", 0) + Done());

            Assert.True(h.Controller.Submit("第一次"));
            h.Widget.CompleteCurrentLineTyping();                    // 第一句上屏
            Assert.Equal("第一句", h.Widget.CurrentFrame.Text);
            string instanceId = h.Controller.DialogueInstanceId;
            string turnA = h.Controller.CurrentTurnId;

            // 在“第一句”上再次插话：第二句/第三句未播 → 参考续写
            Assert.True(h.Controller.Submit("第二次"));
            Assert.Equal(instanceId, h.Controller.DialogueInstanceId);   // 同 session
            Assert.NotEqual(turnA, h.Controller.CurrentTurnId);          // 新 turn
            Assert.Equal(2, h.Controller.LastReferenceCount);

            JObject request = JObject.Parse(h.Transport.LastRequest);
            var reference = (JArray)((JObject)request["dialogue"])["reference_continuation"];
            Assert.Equal(2, reference.Count);
            Assert.Equal("add", reference[0].Value<string>("kind"));
            Assert.Equal("第二句", reference[0].Value<string>("text"));
            Assert.Equal("第三句", reference[1].Value<string>("text"));
            // played 只到“第一句”为止，含玩家上一条
            var played = (JArray)((JObject)request["dialogue"])["played"];
            Assert.Equal(3, played.Count);
            Assert.Equal("player", played[1].Value<string>("role"));
            Assert.Equal("ai", played[2].Value<string>("role"));
            Assert.Equal("第一句", played[2].Value<string>("text"));
        }

        [Fact]
        public void MidTurnInsertKeepsClosingLineAsReference()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。");
            h.Transport.Script(
                AddLine("正文", 0) + AddLine("收尾语", 1, "closing") + Done());
            h.Transport.Script(AddLine("新回答", 0) + Done());

            Assert.True(h.Controller.Submit("第一次"));
            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal("正文", h.Widget.CurrentFrame.Text);

            Assert.True(h.Controller.Submit("第二次"));
            JObject request = JObject.Parse(h.Transport.LastRequest);
            var reference = (JArray)((JObject)request["dialogue"])["reference_continuation"];
            Assert.Single(reference);
            Assert.Equal("closing", reference[0].Value<string>("kind"));
            Assert.Equal("收尾语", reference[0].Value<string>("text"));
        }

        // ── closing 收尾 ──────────────────────────────────────────────────

        [Fact]
        public void ClosingOnCloseCancelsInFlightAndFinalizesImmediately()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。", "有事说事。");
            var hanging = new HangingStream(AddLine("在途句", 0));
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.True(SpinWait.SpinUntil(() => h.Controller.PendingLineCount == 1, 5000));

            h.Close();
            Assert.True(SpinWait.SpinUntil(() => h.Controller.ClosingForTest, 5000));
            Assert.True(SpinWait.SpinUntil(() => hanging.Disposed, 5000));
            Assert.True(SpinWait.SpinUntil(() => h.Transport.Finalizes.Count > 0, 5000));
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);
            Assert.False(h.Controller.Submit("关掉后插话"));

            JObject finish = h.LastFinish();
            Assert.NotNull(finish);
            Assert.Equal("close", finish.Value<string>("reason"));
            Assert.InRange(finish.Value<int>("finalIndex"), 0, 1);
        }

        [Fact]
        public void ClosingOnAdvancePastEndFinalizesAndRejectsSubmit()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。");
            h.Transport.Script(AddLine("回答", 0) + Done());
            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();

            h.Advance();                                        // 末行后 → advance_past_end
            Assert.True(h.Controller.ClosingForTest);
            Assert.False(h.Controller.Submit("末句后插话"));
            Assert.True(h.Transport.Finalizes.Count > 0);
            JObject finish = h.LastFinish();
            Assert.Equal("advance_past_end", finish.Value<string>("reason"));
            Assert.Equal(0, finish.Value<int>("finalIndex"));
        }

        // ── 重复触发 / 组结束 ─────────────────────────────────────────────

        [Fact]
        public void NewBookStartsNewSessionAndClearsHistory()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。");
            h.Transport.Script(AddLine("回答", 0) + Done());
            Assert.True(h.Controller.Submit("第一次"));
            h.Widget.CompleteCurrentLineTyping();
            string firstInstance = h.Controller.DialogueInstanceId;
            Assert.NotNull(firstInstance);
            Assert.True(h.Controller.PlayedCount > 0);

            h.AdoptBookInMode(8, "ordinary", null, "换一场戏。");
            Assert.Null(h.Controller.DialogueInstanceId);        // 新组必须新建 session
            Assert.Equal(1, h.Controller.PlayedCount);           // 只剩新组第一句

            h.Transport.Script(AddLine("新回答", 0) + Done());
            Assert.True(h.Controller.Submit("第二次"));
            Assert.NotEqual(firstInstance, h.Controller.DialogueInstanceId);
        }

        [Fact]
        public void CancelDisposesInFlightStreamAndStopsUnplayedLines()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。", "有事说事。");
            var hanging = new HangingStream(AddLine("排队句", 0));
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.True(SpinWait.SpinUntil(() => h.Controller.PendingLineCount == 1, 5000));

            h.Controller.CancelTurn("test");
            Assert.True(SpinWait.SpinUntil(() => hanging.Disposed, 5000));
            Assert.Equal(0, h.Controller.PendingLineCount);
            Assert.Equal("$PC", h.Widget.CurrentFrame.Name);
            Assert.True(SpinWait.SpinUntil(() => h.Transport.Finalizes.Count > 0, 5000));

            h.Advance();
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void SubmitRejectedWhenNotReadyOrTooLong()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。");
            Assert.False(h.Controller.Submit("   "));
            Assert.False(h.Controller.Submit(new string('字', 151)));
            Assert.True(h.Controller.Submit(new string('字', 150)));
        }
    }
}
