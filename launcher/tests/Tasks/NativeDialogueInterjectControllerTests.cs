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
    /// G1：日常插话「玩家说一句 → $PC → 首句播放 → 可取消 / 失败回退 / finalize」。
    ///
    /// 驱动面：NativeDialogueTask.AdoptV2（dispatch 同步）+ 假传输（脚本化 SSE）+
    /// 注入的 ID 生成器/时钟；不调真模型、不起 HTTP、不构造窗口。
    /// 请求/事件形状对齐《协议》5.1/5.2 与 fixture F-01/F-10/F-11/F-12。
    /// </summary>
    public sealed class NativeDialogueInterjectControllerTests
    {
        private sealed class ScriptedTransport : IDialogueInterjectTransport
        {
            private readonly Queue<string> _scripts = new Queue<string>();
            internal string LastRequest;
            internal string LastFinalize;
            internal int OpenCount;
            internal bool Finalized;
            /// <summary>非空时接管流的开法（取消测试用阻塞流）。</summary>
            internal Func<string, Task<Stream>> OpenAsyncOverride;

            internal void Script(string sse) { _scripts.Enqueue(sse); }

            public Task<Stream> OpenAsync(string requestJson, CancellationToken cancellationToken)
            {
                LastRequest = requestJson;
                OpenCount++;
                if (OpenAsyncOverride != null) return OpenAsyncOverride(requestJson);
                string payload = _scripts.Count > 0 ? _scripts.Dequeue() : "";
                return Task.FromResult<Stream>(new MemoryStream(Encoding.UTF8.GetBytes(payload)));
            }

            public Task<JObject> PostFinalizeAsync(string requestJson, CancellationToken cancellationToken)
            {
                LastFinalize = requestJson;
                Finalized = true;
                return Task.FromResult(new JObject
                {
                    ["ok"] = true,
                    ["dialogue_instance_id"] = "inst",
                    ["session_id"] = "s1",
                    ["appended"] = 1,
                    ["total"] = 2
                });
            }
        }

        /// <summary>先吐一条 line 再永久阻塞的流（模拟"流没结束、玩家关闭"）。</summary>
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
            private int _ids;

            internal Harness(bool inline = true)
            {
                Anchor = new Control { Size = new Size(1024, 576) };
                Widget = new NativeDialogueWidget(Anchor);
                Task = new NativeDialogueTask(Widget, a => a(), wire => true, () => true);
                Task.BookRetryScheduler = (ms, cb) => { };
                Controller = new NativeDialogueInterjectController(
                    Task, Widget, a => a(), null, () => Transport,
                    () => "id-" + (++_ids), () => new DateTime(2026, 10, 18, 21, 30, 0));
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
                AdoptBook(7, texts);
            }

            internal void AdoptBook(int sequence, params string[] texts)
            {
                AdoptBookInMode(sequence, "ordinary", texts);
            }

            internal void AdoptBookInMode(int sequence, string mode, params string[] texts)
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
                Task.AdoptV2(new JObject
                {
                    ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                    ["requestId"] = "nd:" + sequence, ["sceneId"] = "scene.1",
                    ["mode"] = mode, ["epoch"] = 1, ["startIndex"] = 0,
                    ["advanceKey"] = 13, ["lines"] = lines
                });
            }

            internal void Advance() { Widget.InputRequested(Widget.CurrentFrame, "advance"); }

            public void Dispose()
            {
                try { Controller.Dispose(); } catch { }
                try { Widget.Dispose(); } catch { }
                try { Anchor.Dispose(); } catch { }
            }
        }

        private const string F01 =
            "event: line\ndata: {\"kind\":\"add\",\"text\":\"还能怎么样，老样子。\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":0}\n\n"
            + "event: line\ndata: {\"kind\":\"add\",\"text\":\"你倒是难得过来一趟。\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":1}\n\n"
            + "event: done\ndata: {\"dialogue_instance_id\":\"inst\",\"session_id\":\"s1\",\"usage\":{}}\n\n";

        // ── 发送：$PC 上屏 + 请求形状 ───────────────────────────────────────

        [Fact]
        public void SubmitPlaysPcLineAndBuildsProtocolRequest()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。", "没事就别挡道。");
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);

            h.Transport.Script(F01);
            Assert.True(h.Controller.Submit("  最近怎么样？  "));

            // 本地立即播 $PC，wire 行数不变（G0-2 契约）
            Assert.Equal("$PC", h.Widget.CurrentFrame.Name);
            Assert.Equal("最近怎么样？", h.Widget.CurrentFrame.Text);
            Assert.Equal(3, h.Task.BookSessionForTest.RowCount);
            Assert.Equal(4, h.Task.BookSessionForTest.PlaybackCount);
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            JObject request = JObject.Parse(h.Transport.LastRequest);
            Assert.Equal("daily", request.Value<string>("mode"));
            Assert.Equal("Andy Law", request.Value<string>("npc"));
            Assert.Equal("最近怎么样？", request.Value<string>("player_input"));
            Assert.False(string.IsNullOrEmpty(request.Value<string>("dialogue_instance_id")));
            Assert.False(string.IsNullOrEmpty(request.Value<string>("turn_id")));
            Assert.Equal("日常插话 · Andy Law · 2026-10-18 21:30", request.Value<string>("session_title"));
            Assert.Equal(JTokenType.Null, request["task_context"].Type);
            Assert.Equal(165, request["limits"].Value<int>("line_hard_max"));
            Assert.Equal(135, request["limits"].Value<int>("line_prompt_max"));

            JObject dialogue = (JObject)request["dialogue"];
            Assert.Equal("daily", dialogue.Value<string>("kind"));
            Assert.Equal("nd:7", dialogue.Value<string>("group_id"));
            // played 只含本轮发送前：原作第一句（npc）
            var played = (JArray)dialogue["played"];
            Assert.Single(played);
            Assert.Equal("npc", played[0].Value<string>("role"));
            Assert.Equal("又是你。", played[0].Value<string>("text"));
            Assert.Equal(0, played[0].Value<int>("seq"));
            // remaining 从当前播放点之后编号 1..N
            var remaining = (JArray)dialogue["remaining"];
            Assert.Equal(2, remaining.Count);
            Assert.Equal(1, remaining[0].Value<int>("index"));
            Assert.Equal("有事说事。", remaining[0].Value<string>("text"));
            Assert.Equal(2, remaining[1].Value<int>("index"));
            Assert.Empty((JArray)dialogue["reference_continuation"]);
        }

        // ── 首句：$PC 期间排队，播完再上屏 ─────────────────────────────────

        [Fact]
        public void FirstLineQueuesWhilePcPlaysThenStartsOnTypingFinished()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。");
            h.Transport.Script(F01);

            Assert.True(h.Controller.Submit("最近怎么样？"));
            // 流已跑完（inline）：两条 line 都在排队，$PC 还在播
            Assert.Equal(2, h.Controller.PendingLineCount);
            Assert.Equal("$PC", h.Widget.CurrentFrame.Name);
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);
            Assert.Equal(new[]
            {
                DialogueInterjectInputState.Ready,
                DialogueInterjectInputState.Hidden
            }, h.States);

            // $PC 打字完成 → 首句立即上屏，输入恢复可用
            Assert.True(h.Widget.CompleteCurrentLineTyping());
            Assert.Equal("还能怎么样，老样子。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
            Assert.Equal(0, h.Controller.PendingLineCount);   // 其余已收台词已排进播放序列

            // 第二句已接在首句之后，玩家点“下一条”逐句走（P2 再补结束语/参考续写）
            h.Advance();
            Assert.Equal("你倒是难得过来一趟。", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);
        }

        // ── finalize：只写已播内容 ─────────────────────────────────────────

        [Fact]
        public void FinalizeTranscriptContainsOnlyPlayedRows()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。");
            h.Transport.Script(F01);
            Assert.True(h.Controller.Submit("最近怎么样？"));
            h.Widget.CompleteCurrentLineTyping();          // 首句上屏

            Assert.True(h.Transport.Finalized);
            JObject payload = JObject.Parse(h.Transport.LastFinalize);
            Assert.Equal(h.Controller.DialogueInstanceId, payload.Value<string>("dialogue_instance_id"));
            Assert.Equal(h.Controller.CurrentTurnId, payload.Value<string>("turn_id"));

            var transcript = (JArray)payload["transcript"];
            Assert.Equal(3, transcript.Count);
            Assert.Equal("npc", transcript[0].Value<string>("role"));
            Assert.Equal("又是你。", transcript[0].Value<string>("text"));
            Assert.Equal("player", transcript[1].Value<string>("role"));
            Assert.Equal("$PC", transcript[1].Value<string>("name"));
            Assert.Equal("ai", transcript[2].Value<string>("role"));
            Assert.Equal("还能怎么样，老样子。", transcript[2].Value<string>("text"));
            // 未播的第二句不得落库
            Assert.DoesNotContain("你倒是难得过来一趟。", h.Transport.LastFinalize);
        }

        // ── 失败：不播额外台词，回到原对话当前点 ───────────────────────────

        [Fact]
        public void ErrorBeforeFirstLineRestoresOriginalTail()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。", "没事就别挡道。");
            h.Transport.Script(
                "event: error\ndata: {\"code\":\"no_valid_lines\",\"message\":\"零条\",\"valid_lines\":0}\n\n");

            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.Equal("$PC", h.Widget.CurrentFrame.Name);      // $PC 已播保留
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
            Assert.Equal(0, h.Controller.PendingLineCount);
            Assert.Equal("no_valid_lines", h.Controller.LastFailure);

            // 播放序列已还原：下一条是原第 2 句（当前 $PC 之后接回原文）
            h.Advance();
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);
            Assert.True(h.Transport.Finalized);                  // 失败也按已播收尾
        }

        [Fact]
        public void PartialStreamThenCloseKeepsPlayedLine()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。");
            h.Transport.Script(
                "event: line\ndata: {\"kind\":\"add\",\"text\":\"你先听我说。\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":0}\n\n"
                + "event: error\ndata: {\"code\":\"stream_failed\",\"message\":\"断流\",\"valid_lines\":1}\n\n");

            Assert.True(h.Controller.Submit("最近怎么样？"));
            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal("你先听我说。", h.Widget.CurrentFrame.Text);
            Assert.Equal("stream_failed", h.Controller.LastFailure);
            Assert.True(h.Transport.Finalized);
            // 已播的 AI 行保留在 transcript
            Assert.Contains("你先听我说。", h.Transport.LastFinalize);
        }

        // ── 取消：真断流 + 未到行不播 ───────────────────────────────────────

        [Fact]
        public void CancelDisposesInFlightStreamAndStopsUnplayedLines()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。", "有事说事。");
            var hanging = new HangingStream(
                "event: line\ndata: {\"kind\":\"add\",\"text\":\"排队句\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":0}\n\n");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.True(SpinWait.SpinUntil(() => h.Controller.PendingLineCount == 1, 5000),
                "首句应先排队到达");

            h.Controller.CancelTurn("close");
            Assert.True(SpinWait.SpinUntil(() => hanging.Disposed, 5000), "取消必须 Dispose 在途响应流");
            Assert.Equal(0, h.Controller.PendingLineCount);
            Assert.Equal("$PC", h.Widget.CurrentFrame.Name);          // 未播的 AI 行不上屏
            Assert.True(SpinWait.SpinUntil(() => h.Transport.Finalized, 5000));

            // 取消后仍然回到原对话
            h.Advance();
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);
        }

        // ── 组结束：取消在途、复位 session id ──────────────────────────────

        [Fact]
        public void GroupEndCancelsTurnAndResetsInstanceId()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。", "有事说事。");
            var hanging = new HangingStream(
                "event: line\ndata: {\"kind\":\"add\",\"text\":\"排队句\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":0}\n\n");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.True(SpinWait.SpinUntil(() => h.Controller.PendingLineCount == 1, 5000));
            Assert.NotNull(h.Controller.DialogueInstanceId);

            // 新一组 book 顶掉旧会话 → BookSessionEnded
            h.AdoptBook(8, "换一场戏。");
            Assert.True(SpinWait.SpinUntil(() => h.Controller.DialogueInstanceId == null, 5000));
            Assert.Null(h.Controller.DialogueInstanceId);          // 新组要重新建 session
            Assert.True(hanging.Disposed);
        }

        [Fact]
        public void StageDialogueNeverEnablesInterject()
        {
            using var h = new Harness();
            h.AdoptBookInMode(9, "stage", "场景台词一", "场景台词二");
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);
            Assert.False(h.Controller.Submit("插一句"));
            Assert.Equal(0, h.Transport.OpenCount);       // 不发请求
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
