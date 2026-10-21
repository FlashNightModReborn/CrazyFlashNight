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
            internal readonly List<string> BoundPlayers = new List<string>();
            /// <summary>注入时钟：看门狗测试手动推进，不 sleep。</summary>
            internal DateTime Now = new DateTime(2026, 10, 18, 22, 30, 0);
            /// <summary>每次排定时器记录 delay（断言无事件/总时长上限的取小逻辑）。</summary>
            internal readonly List<TimeSpan> WatchdogDelays = new List<TimeSpan>();
            private Action _watchdogCallback;
            private int _ids;

            private sealed class FakeTimer : IDisposable
            {
                private readonly Action _onDispose;
                private bool _disposed;
                internal FakeTimer(Action onDispose) { _onDispose = onDispose; }
                public void Dispose()
                {
                    if (_disposed) return;
                    _disposed = true;
                    if (_onDispose != null) _onDispose();
                }
            }

            /// <summary>当前终端是否在线（测试可切换，模拟 ensureReady 成功/失败）。</summary>
            internal bool TerminalReady = true;

            internal Harness(bool inline = true, Func<Task<bool>> ensureReady = null,
                Func<Task<bool>> llmConfigured = null, bool terminalReady = true,
                Func<string, Task> ensureBound = null)
            {
                TerminalReady = terminalReady;
                Anchor = new Control { Size = new Size(1024, 576) };
                Widget = new NativeDialogueWidget(Anchor);
                Task = new NativeDialogueTask(Widget, a => a(),
                    wire => { Sent.Add(wire); return true; }, () => true);
                Task.BookRetryScheduler = (ms, cb) => { };
                Controller = new NativeDialogueInterjectController(
                    Task, Widget, a => a(), ensureReady, () => Transport,
                    () => "id-" + (++_ids), () => Now,
                    terminalReady: () => TerminalReady, llmConfigured: llmConfigured,
                    ensureBound: name =>
                    {
                        BoundPlayers.Add(name);
                        return ensureBound != null ? ensureBound(name)
                            : System.Threading.Tasks.Task.CompletedTask;
                    });
                Controller.WatchdogScheduler = (delay, callback) =>
                {
                    WatchdogDelays.Add(delay);
                    _watchdogCallback = callback;
                    return new FakeTimer(() =>
                    {
                        if (object.ReferenceEquals(_watchdogCallback, callback)) _watchdogCallback = null;
                    });
                };
                if (inline)
                    Controller.TaskRunner = f =>
                    {
                        f().GetAwaiter().GetResult();
                        return System.Threading.Tasks.Task.CompletedTask;
                    };
                Controller.InputStateChanged += s => States.Add(s);
                Controller.Attach();
            }

            internal TimeSpan LastWatchdogDelay
            {
                get { return WatchdogDelays[WatchdogDelays.Count - 1]; }
            }

            internal int WatchdogArmedCount { get { return WatchdogDelays.Count; } }

            /// <summary>手动触发当前在看门狗（等价于定时器到点），不 sleep。</summary>
            internal void FireWatchdog()
            {
                Action callback = _watchdogCallback;
                _watchdogCallback = null;
                if (callback != null) callback();
            }

            internal void AdoptBook(params string[] texts)
            {
                AdoptBookInMode(7, "ordinary", null, texts);
            }

            internal void AdoptBookInMode(int sequence, string mode, string dialogueKind,
                params string[] texts)
            {
                Task.AdoptV2(BuildBook(sequence, mode, dialogueKind, null, texts));
            }

            /// <summary>任务组 book：带 dialogueKind + dialogueTaskId（P4）。</summary>
            internal void AdoptTaskBook(int sequence, string dialogueKind, string taskId,
                params string[] texts)
            {
                Task.AdoptV2(BuildBook(sequence, "ordinary", dialogueKind, taskId, texts));
            }

            internal JObject BuildBook(int sequence, string mode, string dialogueKind,
                JToken taskId, params string[] texts)
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
                if (taskId != null) book["dialogueTaskId"] = taskId;
                return book;
            }

            /// <summary>自定义行集 + 玩家快照的 book（转录归属/快照还原用）。</summary>
            internal void AdoptBookWith(JObject snapshot, params JObject[] lines)
            {
                var array = new JArray();
                foreach (JObject line in lines) array.Add(line);
                var book = new JObject
                {
                    ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                    ["requestId"] = "nd:9", ["sceneId"] = "scene.1",
                    ["mode"] = "ordinary", ["epoch"] = 1, ["startIndex"] = 0,
                    ["advanceKey"] = 13, ["lines"] = array
                };
                if (snapshot != null) book["snapshot"] = snapshot;
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

        private static JObject BookLine(string name, string text, string title = "", bool doll = false)
        {
            var portrait = new JObject
            {
                ["kind"] = doll ? "doll" : "static",
                ["key"] = doll ? "doll:" + name : name,
                ["expression"] = "普通"
            };
            if (doll)
                portrait["appearance"] = new JObject { ["gender"] = "男", ["hair"] = "短发" };
            return new JObject
            {
                ["name"] = name, ["title"] = title, ["text"] = text,
                ["portrait"] = portrait, ["imageAction"] = "keep"
            };
        }

        private static JObject PlayerSnapshot(string name, string title, bool doll)
        {
            var portrait = new JObject
            {
                ["kind"] = doll ? "doll" : "static",
                ["key"] = doll ? "doll:$PC_CHAR" : name,
                ["expression"] = "普通"
            };
            if (doll)
                portrait["appearance"] = new JObject { ["gender"] = "女", ["hair"] = "长发" };
            return new JObject
            {
                ["playerName"] = name, ["heroTitle"] = title, ["heroPortrait"] = portrait
            };
        }

        private static string AddLine(string text, int seq, string kind = "add",
            string emotion = "普通")
        {
            string emotionField = string.IsNullOrEmpty(emotion)
                ? "" : ",\"emotion\":\"" + emotion + "\"";
            return "event: line\ndata: {\"kind\":\"" + kind + "\",\"text\":\"" + text
                + "\"" + emotionField + ",\"speaker\":\"Andy Law\",\"seq\":" + seq + "}\n\n";
        }

        private static string Done()
        {
            return "event: done\ndata: {\"dialogue_instance_id\":\"inst\",\"session_id\":\"s1\",\"usage\":{}}\n\n";
        }

        // ── 假事件（绕开流驱动，直接喂控制器；P3 的 status / 中途失败都用它）──────

        private static DialogueInterjectEvent Evt(DialogueInterjectEventKind kind, string dataJson)
        {
            return new DialogueInterjectEvent
            {
                Kind = kind,
                EventName = kind.ToString().ToLowerInvariant(),
                Data = JObject.Parse(dataJson)
            };
        }

        private static DialogueInterjectEvent StatusEvent(string stage, string uiHint = null)
        {
            var data = new JObject { ["stage"] = stage };
            if (uiHint != null) data["ui_hint"] = uiHint;
            return Evt(DialogueInterjectEventKind.Status,
                data.ToString(Newtonsoft.Json.Formatting.None));
        }

        private static DialogueInterjectEvent LineEvent(string text, int seq, bool interim = false)
        {
            return Evt(DialogueInterjectEventKind.Line,
                "{\"kind\":\"add\",\"text\":\"" + text
                + "\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":" + seq
                + (interim ? ",\"interim\":true" : "") + "}");
        }

        private static DialogueInterjectEvent ErrorEvent(string code)
        {
            return Evt(DialogueInterjectEventKind.Error,
                "{\"code\":\"" + code + "\",\"message\":\"失败\"}");
        }

        private static DialogueInterjectEvent PlanEvent(string json)
        {
            return Evt(DialogueInterjectEventKind.Plan, json);
        }

        private static DialogueInterjectEvent MuteEvent()
        {
            return Evt(DialogueInterjectEventKind.Mute, "{\"mute\":true}");
        }

        private static DialogueInterjectEvent DoneEvent()
        {
            return Evt(DialogueInterjectEventKind.Done,
                "{\"dialogue_instance_id\":\"inst\",\"session_id\":\"s1\"}");
        }

        /// <summary>任务上下文桩（F-05 形状）：upcoming=本任务，completed=上一个任务。</summary>
        private static JObject DemoTaskContext()
        {
            return new JObject
            {
                ["completed"] = new JObject
                {
                    ["task_id"] = 200123, ["title"] = "南边哨站补给", ["npc"] = "Andy Law",
                    ["objectives"] = new JArray("送回 3 箱弹药"),
                    ["rewards"] = new JArray("金币 1200"),
                    ["outcome"] = "送回 3 箱弹药"
                },
                ["upcoming"] = new JObject
                {
                    ["task_id"] = 200124, ["title"] = "北边仓库失窃", ["npc"] = "Andy Law",
                    ["objectives"] = new JArray("找回失窃货物", "返回交付"),
                    ["rewards"] = new JArray("金币 2400", "声望 10")
                }
            };
        }

        private static void EnableTaskContext(Harness h)
        {
            h.Task.TaskContextProvider = (id, kind) => DemoTaskContext();
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
        public void FirstLineQueuesWhilePcPlaysThenStartsOnAdvance()
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
            Assert.Equal("最近怎么样？", h.Widget.CurrentFrame.Text);  // 还停在 $PC，等玩家推进
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 玩家行仍在屏：整条隐藏
            Assert.Equal(0, h.Controller.PendingLineCount);

            h.Advance();
            Assert.Equal("第一句", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
            h.Advance();
            Assert.Equal("第二句", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void SubmittedPlayerLineStaysHiddenAfterTypingUntilNextNonPlayerLine()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("我来了。"));
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            Assert.True(h.Widget.CompleteCurrentLineTyping());
            Assert.Equal("我来了。", h.Widget.CurrentFrame.Text);       // 玩家台词仍在上屏等推进
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            h.Advance();                                               // 推进到等待占位（非玩家行）
            Assert.Equal("思索中……", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Locked, h.Controller.InputState);
        }

        [Fact]
        public void OriginalPlayerLineStaysHiddenAfterTyping()
        {
            using var h = new Harness();
            h.AdoptBookWith(PlayerSnapshot("阿夜", "流浪剑士", doll: true),
                BookLine("Andy Law", "又是你。", "雇佣兵"),
                BookLine("阿夜", "我来了。", "$PC_TITLE", doll: true),
                BookLine("Andy Law", "进来吧。", "雇佣兵"));

            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
            h.Advance();
            Assert.Equal("我来了。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            h.Advance();
            Assert.Equal("进来吧。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        [Fact]
        public void AiLineInheritsNpcPortraitAndBindsPlayerSnapshot()
        {
            using var h = new Harness();
            h.AdoptBookWith(new JObject
            {
                ["playerName"] = "测试玩家",
                ["heroTitle"] = "队长",
                ["heroPortrait"] = new JObject
                {
                    ["kind"] = "static", ["key"] = "测试玩家", ["expression"] = "普通"
                }
            }, new JObject
            {
                ["name"] = "Andy Law", ["title"] = "雇佣兵", ["text"] = "又是你。",
                ["portrait"] = new JObject
                {
                    ["kind"] = "static", ["key"] = "Andy Law", ["expression"] = "严肃"
                },
                ["imageAction"] = "keep"
            });
            // 本轮没有自带 emotion：表情应回落到 NPC 模板的「严肃」，立绘随 NPC。
            h.Transport.Script(AddLine("听见了。", 0, emotion: null) + Done());

            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();

            Assert.Equal("听见了。", h.Widget.CurrentFrame.Text);
            Assert.Equal("Andy Law", h.Widget.CurrentFrame.Name);
            Assert.Equal("Andy Law", h.Widget.CurrentFrame.PortraitKey);
            Assert.Equal("严肃", h.Widget.CurrentFrame.Expression);
            Assert.Equal("雇佣兵", h.Widget.CurrentFrame.Title);
            Assert.Contains("测试玩家", h.BoundPlayers);
        }

        [Fact]
        public void SuccessTurnEndsAtLastAiLineWithoutResumingOriginal()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。", "没事就别挡道。");
            h.Transport.Script(AddLine("AI 第一句", 0) + AddLine("AI 第二句", 1) + Done());

            Assert.True(h.Controller.Submit("最近怎么样？"));
            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal("最近怎么样？", h.Widget.CurrentFrame.Text);

            h.Advance();
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
            h.Advance();
            Assert.Equal("只有一句", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.ClosingForTest);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        // ── 等待占位「思索中……」 ─────────────────────────────────────────

        [Fact]
        public void AdvancePastPcWithActiveTurnShowsThinkingPlaceholderThenAutoReplaces()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();

            Assert.Equal("思索中……", h.Widget.CurrentFrame.Text);
            Assert.Equal("Andy Law", h.Widget.CurrentFrame.Name);
            Assert.False(h.Controller.ClosingForTest);
            Assert.Equal(0, h.Transport.Finalizes.Count);

            h.Advance();                                   // 占位上继续点：不结束本组
            Assert.Equal("思索中……", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.ClosingForTest);
            Assert.Equal(0, h.Transport.Finalizes.Count);

            h.Controller.OnEvent(LineEvent("来了。", 0));    // 玩家已在占位条：原位自动替换
            Assert.Equal("来了。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);

            h.Advance();                                   // 末行后 → 正常收尾
            Assert.True(h.Controller.ClosingForTest);
            Assert.True(SpinWait.SpinUntil(() => h.Transport.LastFinalize != null, 5000));
            JObject finish = JObject.Parse(h.Transport.LastFinalize);
            var transcript = (JArray)finish["transcript"];
            Assert.Equal(3, transcript.Count);
            Assert.Equal("npc", transcript[0].Value<string>("role"));
            Assert.Equal("player", transcript[1].Value<string>("role"));
            Assert.Equal("ai", transcript[2].Value<string>("role"));
            Assert.DoesNotContain("思索中", transcript.ToString());
        }

        [Fact]
        public void AiLineArrivingWhileStillOnPcWaitsForAdvanceWithoutPlaceholder()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("你好"));
            h.Controller.OnEvent(LineEvent("第一句", 0));   // $PC 还在播 → 排队
            Assert.Equal("你好", h.Widget.CurrentFrame.Text);

            h.Widget.CompleteCurrentLineTyping();           // 播完 $PC：AI 行只入队不抢屏
            Assert.Equal("你好", h.Widget.CurrentFrame.Text);
            Assert.Equal(0, h.Controller.PendingLineCount);

            h.Advance();
            Assert.Equal("第一句", h.Widget.CurrentFrame.Text);  // 直接看到 AI，不经过占位
            Assert.False(h.Controller.ClosingForTest);
        }

        [Fact]
        public void FailureWhileOnPlaceholderRemovesItAndRestoresOriginalTail()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。", "有事说事。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("思索中……", h.Widget.CurrentFrame.Text);

            h.Controller.OnEvent(ErrorEvent("upstream_error"));

            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);  // 占位原位换回原文
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
            Assert.True(SpinWait.SpinUntil(() => h.Transport.Finalizes.Count > 0, 5000));
        }

        [Fact]
        public void StatusStageReplacesThinkingPlaceholderWhileWaiting()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("思索中……", h.Widget.CurrentFrame.Text);

            h.Controller.OnEvent(StatusEvent("searching"));
            Assert.Equal("查资料中", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Preparing, h.Controller.InputState);

            h.Controller.OnEvent(StatusEvent("drafting"));
            Assert.Equal("拟定委托中", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.ClosingForTest);
            Assert.Equal(0, h.Transport.Finalizes.Count);
        }

        [Fact]
        public void StatusUiHintTakesPriorityAndRefreshesPlaceholderInPlace()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("思索中……", h.Widget.CurrentFrame.Text);

            h.Controller.OnEvent(StatusEvent("drafting", "准备候选中"));
            Assert.Equal("准备候选中", h.Widget.CurrentFrame.Text);

            h.Controller.OnEvent(StatusEvent("drafting", "校验修正中"));
            Assert.Equal("校验修正中", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Preparing, h.Controller.InputState);
        }

        [Fact]
        public void TransitionLineThenUiHintPlaceholderUntilFinalDialogueReplacesIt()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("帮我找个活。"));
            h.Controller.OnEvent(StatusEvent("drafting", "拟定委托中"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("拟定委托中", h.Widget.CurrentFrame.Text);

            // 过渡话先到：原位替换等待占位。
            h.Controller.OnEvent(LineEvent("我这儿正盘算着件事。", 0, interim: true));
            Assert.Equal("我这儿正盘算着件事。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);

            // 玩家越过过渡话、最终确认对话还没到：继续显示 ui_hint 占位。
            h.Advance();
            Assert.Equal("拟定委托中", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.ClosingForTest);

            // 最终确认对话到达：原位替换占位，不追加到占位之后。
            h.Controller.OnEvent(LineEvent("这活你接吗？", 1));
            Assert.Equal("这活你接吗？", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);

            h.Controller.OnEvent(DoneEvent());
            h.Advance();
            Assert.True(h.Controller.ClosingForTest);
        }

        [Fact]
        public void DoneWhileOnPostTransitionPlaceholderStillClosesOnAdvance()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("帮我找个活。"));
            h.Controller.OnEvent(StatusEvent("drafting", "拟定委托中"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            h.Controller.OnEvent(LineEvent("我这儿正盘算着件事。", 0, interim: true));
            h.Advance();
            Assert.Equal("拟定委托中", h.Widget.CurrentFrame.Text);

            h.Controller.OnEvent(DoneEvent());
            h.Advance();
            Assert.True(h.Controller.ClosingForTest);
        }

        [Fact]
        public void StatusBeforeAdvanceIsShownOnNewPlaceholder()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("你好"));
            h.Controller.OnEvent(StatusEvent("thinking"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();

            Assert.Equal("思考中", h.Widget.CurrentFrame.Text);
        }

        // ── 玩家快照与转录归属 ───────────────────────────────────────────

        [Fact]
        public void TranscriptRolesDistinguishPlayerNpcAndOtherNpc()
        {
            using var h = new Harness();
            h.AdoptBookWith(PlayerSnapshot("阿夜", "流浪剑士", doll: true),
                BookLine("阿夜", "我来了。", "$PC_TITLE", doll: true),
                BookLine("Andy Law", "又是你。", "雇佣兵"),
                BookLine("守卫", "站住。"));

            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 玩家行在播
            h.Advance();
            h.Advance();
            Assert.Equal("站住。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);

            h.Transport.Script(AddLine("说吧。", 0) + Done());
            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.Equal("阿夜", h.Widget.CurrentFrame.Name);
            Assert.Equal("流浪剑士", h.Widget.CurrentFrame.Title);
            Assert.True(h.Widget.CurrentFrame.IsDoll);

            JObject request = JObject.Parse(h.Transport.LastRequest);
            Assert.Equal("Andy Law", request.Value<string>("npc"));   // 第三方不改写主 NPC
            var played = (JArray)((JObject)request["dialogue"])["played"];
            Assert.Equal(3, played.Count);
            Assert.Equal("player", played[0].Value<string>("role"));
            Assert.Equal("npc", played[1].Value<string>("role"));
            Assert.Equal("other_npc", played[2].Value<string>("role"));

            h.Widget.CompleteCurrentLineTyping();
            h.Close();
            JObject finish = JObject.Parse(h.Transport.LastFinalize);
            var transcript = (JArray)finish["transcript"];
            Assert.Equal(4, transcript.Count);
            Assert.Equal("player", transcript[0].Value<string>("role"));
            Assert.Equal("npc", transcript[1].Value<string>("role"));
            Assert.Equal("other_npc", transcript[2].Value<string>("role"));
            Assert.Equal("player", transcript[3].Value<string>("role"));
            Assert.Equal("阿夜", transcript[3].Value<string>("name"));
            Assert.Equal("最近怎么样？", transcript[3].Value<string>("text"));
        }

        [Fact]
        public void PlayerSnapshotFillsLocalPcWhenBookHasNoPlayerLine()
        {
            using var h = new Harness();
            h.AdoptBookWith(PlayerSnapshot("阿夜", "流浪剑士", doll: true),
                BookLine("Andy Law", "又是你。", "雇佣兵"));
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);

            h.Transport.Script(AddLine("说吧。", 0) + Done());
            Assert.True(h.Controller.Submit("最近怎么样？"));
            NativeDialogueFrame frame = h.Widget.CurrentFrame;
            Assert.Equal("阿夜", frame.Name);
            Assert.Equal("流浪剑士", frame.Title);
            Assert.Equal("doll:$PC_CHAR", frame.PortraitKey);
            Assert.True(frame.IsDoll);
            Assert.False(string.IsNullOrEmpty(frame.AppearanceIdentity));

            h.Widget.CompleteCurrentLineTyping();
            h.Close();
            JObject finish = JObject.Parse(h.Transport.LastFinalize);
            var transcript = (JArray)finish["transcript"];
            var playerRow = transcript[transcript.Count - 1];
            Assert.Equal("player", playerRow.Value<string>("role"));
            Assert.Equal("阿夜", playerRow.Value<string>("name"));
        }

        [Fact]
        public void LegacyDollarPcOriginalLineIsPlayer()
        {
            using var h = new Harness();
            h.AdoptBookWith(PlayerSnapshot("阿夜", "流浪剑士", doll: true),
                BookLine("$PC", "我来了。", "$PC_TITLE", doll: true),
                BookLine("Andy Law", "又是你。", "雇佣兵"));
            h.Advance();
            h.Transport.Script(AddLine("说吧。", 0) + Done());

            Assert.True(h.Controller.Submit("最近怎么样？"));
            JObject request = JObject.Parse(h.Transport.LastRequest);
            var played = (JArray)((JObject)request["dialogue"])["played"];
            Assert.Equal("player", played[0].Value<string>("role"));
            Assert.Equal("npc", played[1].Value<string>("role"));
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
            h.Advance();
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
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 玩家行在屏：隐藏
            Assert.Equal("no_valid_lines", h.Controller.LastFailure);

            h.Advance();
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);   // 接回原作
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
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
            h.Advance();
            Assert.Equal("先听我说。", h.Widget.CurrentFrame.Text);
            Assert.Equal("stream_failed", h.Controller.LastFailure);

            h.Advance();                                            // 已播 AI 行之后接回原作
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);
            h.Close();
            Assert.Contains("先听我说。", h.Transport.LastFinalize);
        }

        /// <summary>
        /// P2 缺陷：AI 首句已经上屏、队列为空时失败，旧代码只调 RestoreOriginalTail()，
        /// 它因 _aiLineShown 直接返回，原作剩余永远不会接回。P3 改走 ResumeAfterPlayedTurnLines。
        /// </summary>
        [Fact]
        public void FailureAfterAiLineIsOnScreenResumesOriginalTail()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。", "有事说事。", "没事就别挡道。");
            var hanging = new HangingStream(AddLine("先听我说。", 0));
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.True(SpinWait.SpinUntil(() => h.Controller.PendingLineCount == 1, 5000));
            Assert.True(h.Widget.CompleteCurrentLineTyping());
            h.Advance();
            Assert.Equal("先听我说。", h.Widget.CurrentFrame.Text);
            Assert.Equal(0, h.Controller.PendingLineCount);

            h.Controller.OnEvent(ErrorEvent("stream_failed"));       // 首句已上屏后流失败

            Assert.Equal("stream_failed", h.Controller.LastFailure);
            Assert.True(SpinWait.SpinUntil(() => h.Transport.Finalizes.Count > 0, 5000));

            h.Advance();                                             // 回到原作下一行，而不是组末
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);
            Assert.Contains("先听我说。", h.Transport.LastFinalize);
        }

        // ── 单轮看门狗 ────────────────────────────────────────────────────

        [Fact]
        public void WatchdogTimesOutSilentStreamAndRestoresOriginalTail()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。", "有事说事。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("最近怎么样？"));
            Assert.True(h.Controller.IsTurnActive);
            Assert.Equal(TimeSpan.FromSeconds(180), h.LastWatchdogDelay);

            h.Now = h.Now.AddSeconds(180);                           // 注入时钟推进，不 sleep
            h.FireWatchdog();

            Assert.Equal("stream_timeout", h.Controller.LastFailure);
            Assert.False(h.Controller.IsTurnActive);
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 玩家行仍在屏：隐藏
            Assert.True(SpinWait.SpinUntil(() => hanging.Disposed, 5000));
            Assert.True(SpinWait.SpinUntil(() => h.Transport.Finalizes.Count > 0, 5000));

            h.Advance();                                             // 按失败回退接回原作
            Assert.Equal("有事说事。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        [Fact]
        public void WatchdogRearmsOnEventAndStillHonorsTotalDeadline()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);
            Assert.True(h.Controller.Submit("你好"));
            Assert.Equal(TimeSpan.FromSeconds(180), h.LastWatchdogDelay);

            h.FireWatchdog();                                        // 提前触发：续排，不算超时
            Assert.Null(h.Controller.LastFailure);
            Assert.Equal(TimeSpan.FromSeconds(180), h.LastWatchdogDelay);

            h.Now = h.Now.AddSeconds(170);
            h.Controller.OnEvent(StatusEvent("thinking"));           // 事件刷新无事件窗口
            Assert.Null(h.Controller.LastFailure);
            // min(170+180, 300) → 距总时长上限只剩 130 秒
            Assert.Equal(TimeSpan.FromSeconds(130), h.LastWatchdogDelay);

            h.Now = h.Now.AddSeconds(130);                           // 总上限到期（距上个事件仅 130 秒）
            h.FireWatchdog();

            Assert.Equal("stream_timeout", h.Controller.LastFailure);
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 玩家行仍在屏：隐藏
        }

        [Fact]
        public void WatchdogIsInactiveAfterTurnEnds()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。");
            h.Transport.Script(AddLine("回答", 0) + Done());
            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            Assert.False(h.Controller.IsTurnActive);

            int armed = h.WatchdogArmedCount;
            h.FireWatchdog();                                        // 迟到的回调：本轮已结束

            Assert.Null(h.Controller.LastFailure);
            Assert.Equal(armed, h.WatchdogArmedCount);               // 不再续排
        }

        // ── status → Preparing ────────────────────────────────────────────

        [Fact]
        public void StatusDraftingShowsPreparingUntilFirstLineArrives()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);
            Assert.True(h.Controller.Submit("有没有活儿？"));           // $PC 播放中：Hidden

            h.Controller.OnEvent(StatusEvent("drafting"));
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            h.Widget.CompleteCurrentLineTyping();                     // $PC 播完、还没出词
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 玩家行仍在屏
            Assert.False(h.Controller.Submit("插一句"));                // 隐藏期间不接受发送

            h.Controller.OnEvent(LineEvent("行，那我直说了。", 0));      // 首个 add 已就绪
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 仍停在 $PC
            Assert.Equal("有没有活儿？", h.Widget.CurrentFrame.Text);    // 仍停在 $PC
            h.Advance();
            Assert.Equal("行，那我直说了。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        [Fact]
        public void StatusSearchingAlsoShowsPreparing()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);
            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();                     // 等待首句：玩家行仍在屏
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            h.Controller.OnEvent(StatusEvent("searching"));
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 仍停在 $PC

            h.Controller.OnEvent(LineEvent("查到了。", 0));             // 出词后回到既有状态
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 仍停在 $PC
            h.Advance();
            Assert.Equal("查到了。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        [Fact]
        public void StatusWithoutPreparingStageKeepsWaitingLocked()
        {
            using var h = new Harness(inline: false);
            h.AdoptBook("又是你。");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);
            Assert.True(h.Controller.Submit("最近怎么样？"));
            h.Widget.CompleteCurrentLineTyping();                     // 等待首句：玩家行仍在屏
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            h.Controller.OnEvent(StatusEvent("thinking"));
            h.Controller.OnEvent(StatusEvent("waiting"));

            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);

            h.Advance();                                              // 推进到占位行：等待态可见
            Assert.Equal("等待中", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Locked, h.Controller.InputState);
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
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();                                             // 第一句上屏
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
            h.Advance();
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

            h.Advance();                                        // $PC 之后 → AI 回答
            Assert.Equal("回答", h.Widget.CurrentFrame.Text);
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

        // ══════════════════ P4：任务插话 ══════════════════

        private const string TaskPlanEdit =
            "{\"mute\":false,\"end\":3,\"edits\":[{\"n\":2,\"kind\":\"edit\","
            + "\"lines\":[{\"text\":\"北边仓库昨晚丢了一批货。\",\"emotion\":\"普通\"}]}]}";

        // ── 选项态（草案确认轮的最后一条 add）──────────────────────────────

        [Fact]
        public void AskAcceptTurnsOnAtLastAddBeforeClosing()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "先别急着答应。");
            // 草案已拟好：最终确认对话两条 add + 结束语；plan 无 end → 放弃原始剩余。
            h.Transport.Script(
                AddLine("委托是去北边仓库找回清单上的货。", 0)
                + AddLine("接不接，你给个话。", 1)
                + AddLine("不接就算了，这活先搁着。", 2, "closing")
                + "event: plan\ndata: {\"mute\":false}\n\n"
                + Done());

            Assert.True(h.Controller.Submit("你说。"));
            h.Widget.CompleteCurrentLineTyping();          // $PC 打完
            h.Advance();                                    // → 首句 add 上屏
            Assert.Equal("委托是去北边仓库找回清单上的货。", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.AskAccept);          // 后面还有 add，不是最后一条

            h.Advance();                                    // → 第二条 add
            Assert.Equal("接不接，你给个话。", h.Widget.CurrentFrame.Text);
            Assert.True(h.Controller.AskAccept);           // 下一条是结束语 → 弹选项

            h.Advance();                                    // → 结束语
            Assert.Equal("不接就算了，这活先搁着。", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.AskAccept);          // 进结束语即恢复普通输入条
        }

        [Fact]
        public void AskAcceptTurnsOnAtLastAddWhenClosingMissing()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "先别急着答应。");
            // 后端没写结束语：靠 done 收流信号认出最后一条 add。
            h.Transport.Script(
                AddLine("委托是去北边仓库找回清单上的货。", 0)
                + AddLine("接不接，你给个话。", 1)
                + "event: plan\ndata: {\"mute\":false}\n\n"
                + Done());

            Assert.True(h.Controller.Submit("你说。"));
            h.Widget.CompleteCurrentLineTyping();          // $PC 打完
            h.Advance();                                    // → 首句 add 上屏
            Assert.Equal("委托是去北边仓库找回清单上的货。", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.AskAccept);

            h.Advance();
            Assert.Equal("接不接，你给个话。", h.Widget.CurrentFrame.Text);
            Assert.True(h.Controller.AskAccept);           // done 已到且后面没有行
        }

        [Fact]
        public void AskAcceptTurnsOnForDailyGroupAfterDraftingStatus()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。");
            // daily 组派活：后端不推 plan（orchestrator 只在 mode=="task" 推），
            // 只推 status(drafting) + 最终确认对话 + 结束语。
            h.Transport.Script(
                "event: status\ndata: {\"stage\":\"drafting\",\"ui_hint\":\"拟定委托中\"}\n\n"
                + AddLine("委托是去北边仓库找回清单上的货。", 0)
                + AddLine("接不接，你给个话。", 1)
                + AddLine("不接就算了，这活先搁着。", 2, "closing")
                + Done());

            Assert.True(h.Controller.Submit("有什么活吗？"));
            h.Widget.CompleteCurrentLineTyping();          // $PC 打完
            h.Advance();                                    // → 首句 add
            Assert.Equal("委托是去北边仓库找回清单上的货。", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.AskAccept);

            h.Advance();                                    // → 第二条 add（最后一条）
            Assert.Equal("接不接，你给个话。", h.Widget.CurrentFrame.Text);
            Assert.True(h.Controller.AskAccept);           // 靠 status(drafting) 认出派活轮
        }

        [Fact]
        public void AskAcceptStaysOffOutsideTaskDraftTurn()
        {
            using var h = new Harness();
            h.AdoptBook("又是你。", "有事说事。");
            h.Transport.Script(
                AddLine("还能怎么样，老样子。", 0)
                + AddLine("那就这样吧。", 1, "closing")
                + Done());

            Assert.True(h.Controller.Submit("最近怎么样？"));
            h.Widget.CompleteCurrentLineTyping();          // $PC 打完
            h.Advance();                                    // → AI 首句上屏
            Assert.Equal("还能怎么样，老样子。", h.Widget.CurrentFrame.Text);
            Assert.False(h.Controller.AskAccept);          // 日常轮即使紧邻结束语也不弹选项
        }

        [Fact]
        public void AskAcceptTurnsOffWhenNewTurnStarts()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "先别急着答应。");
            h.Transport.Script(
                AddLine("接不接，你给个话。", 0)
                + AddLine("不接就算了。", 1, "closing")
                + "event: plan\ndata: {\"mute\":false}\n\n"
                + Done());
            Assert.True(h.Controller.Submit("你说。"));
            h.Widget.CompleteCurrentLineTyping();          // $PC 打完
            h.Advance();                                    // → 唯一一条 add 上屏
            Assert.True(h.Controller.AskAccept);

            // 玩家直接用选项回答：发送即收掉选项态。
            Assert.True(h.Controller.Submit("我接了"));
            Assert.False(h.Controller.AskAccept);
        }

        [Fact]
        public void TaskBookParsesDialogueTaskIdAndAppendKeepsIt()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "北边仓库出事了。");
            var session = h.Task.BookSessionForTest;
            Assert.Equal("200124", session.DialogueTaskId);
            Assert.Equal("task_pre", session.DialogueKind);

            h.Append(7, 1, "追加一句");
            Assert.Same(session, h.Task.BookSessionForTest);
            Assert.Equal("200124", h.Task.BookSessionForTest.DialogueTaskId);
            Assert.Equal("task_pre", h.Task.BookSessionForTest.DialogueKind);
        }

        [Fact]
        public void DailyBookIgnoresDialogueTaskId()
        {
            using var h = new Harness();
            h.Task.AdoptV2(h.BuildBook(7, "ordinary", "daily", new JValue("200124"), "又是你。"));
            Assert.Null(h.Task.BookSessionForTest.DialogueTaskId);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        [Fact]
        public void InvalidTaskIdRejectsWholeBook()
        {
            using var h = new Harness();
            var oversized = new string('1', 33);
            int sequence = 7;
            foreach (JToken token in new JToken[]
            {
                new JValue(200124), new JValue("   "), new JValue(oversized)
            })
            {
                JObject ack = JObject.Parse(h.Task.AdoptV2(
                    h.BuildBook(sequence++, "ordinary", "task_pre", token, "你来了。")));
                Assert.Equal("malformed", ack.Value<string>("reason"));
                Assert.Null(h.Widget.CurrentFrame);
            }
        }

        [Fact]
        public void TaskGroupWithoutContextOrIdStaysHidden()
        {
            using var h = new Harness();
            // 有任务 id 但没 provider：fail-closed
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。");
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);
            Assert.False(h.Controller.Submit("插一句"));
            Assert.Equal(0, h.Transport.OpenCount);

            // 有 provider 但 book 没带 task id：同样 fail-closed
            using var h2 = new Harness();
            EnableTaskContext(h2);
            h2.AdoptTaskBook(7, "task_pre", null, "你来了。");
            Assert.Equal(DialogueInterjectInputState.Hidden, h2.Controller.InputState);
        }

        [Fact]
        public void TaskPreRequestCarriesModeKindContextAndTitle()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "北边仓库出事了。");
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);

            h.Transport.Script(AddLine("你倒是爽快。", 0) + Done());
            Assert.True(h.Controller.Submit("这活儿我接了。"));

            JObject request = JObject.Parse(h.Transport.LastRequest);
            Assert.Equal("task", request.Value<string>("mode"));
            JObject dialogue = (JObject)request["dialogue"];
            Assert.Equal("task_pre", dialogue.Value<string>("kind"));
            Assert.Equal("任务插话 · 北边仓库失窃 · 任务前 · 2026-10-18 22:30",
                request.Value<string>("session_title"));
            var context = (JObject)request["task_context"];
            Assert.Equal(200124, context["upcoming"].Value<int>("task_id"));
            Assert.Equal(200123, context["completed"].Value<int>("task_id"));
            var remaining = (JArray)dialogue["remaining"];
            Assert.Single(remaining);
            Assert.Equal("北边仓库出事了。", remaining[0].Value<string>("text"));
        }

        [Fact]
        public void TaskPostRequestUsesCompletedSegmentTitle()
        {
            using var h = new Harness();
            h.Task.TaskContextProvider = (id, kind) => new JObject
            {
                ["completed"] = new JObject
                {
                    ["task_id"] = 200124, ["title"] = "北边仓库失窃", ["npc"] = "Andy Law",
                    ["objectives"] = new JArray("找回失窃货物"), ["rewards"] = new JArray("金币 2400")
                }
            };
            h.AdoptTaskBook(7, "task_post", "200124", "干得不错。");
            h.Transport.Script(AddLine("嗯。", 0) + Done());
            Assert.True(h.Controller.Submit("交差了。"));

            JObject request = JObject.Parse(h.Transport.LastRequest);
            Assert.Equal("task", request.Value<string>("mode"));
            Assert.Equal("task_post", ((JObject)request["dialogue"]).Value<string>("kind"));
            Assert.Equal("任务插话 · 北边仓库失窃 · 任务后 · 2026-10-18 22:30",
                request.Value<string>("session_title"));
            Assert.Equal(200124, ((JObject)request["task_context"])["completed"].Value<int>("task_id"));
        }

        [Fact]
        public void PlanEndReplaysOriginalsAndEditThenFinishUsesWireTail()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124",
                "你来了。", "先别急着答应。", "北边仓库昨晚丢了东西。",
                "去把清单上的货找回来。", "回来之前别让我等太久。");
            h.Transport.Script(
                AddLine("你倒是爽快。", 0) + "event: plan\ndata: " + TaskPlanEdit + "\n\n" + Done());

            Assert.True(h.Controller.Submit("这活儿我接了。"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("你倒是爽快。", h.Widget.CurrentFrame.Text);

            h.Advance();
            Assert.Equal("先别急着答应。", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("北边仓库昨晚丢了一批货。", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("去把清单上的货找回来。", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("回来之前别让我等太久。", h.Widget.CurrentFrame.Text);
            h.Advance();

            JObject finish = h.LastFinish();
            Assert.NotNull(finish);
            Assert.Equal("advance_past_end", finish.Value<string>("reason"));
            Assert.Equal(4, finish.Value<int>("finalIndex"));   // AS2 原始末行
            Assert.Contains("北边仓库昨晚丢了一批货。", h.Transport.LastFinalize);
        }

        [Fact]
        public void PlanEndPointingAtRemovedEntrySkipsForward()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B", "C", "D");
            h.Transport.Script(
                AddLine("好。", 0)
                + "event: plan\ndata: {\"end\":2,\"edits\":[{\"n\":2,\"kind\":\"remove\"}]}\n\n"
                + Done());

            Assert.True(h.Controller.Submit("嗯。"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("好。", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("A", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("C", h.Widget.CurrentFrame.Text);       // end=2 被 remove → 跳到 C
            h.Advance();
            Assert.Equal("D", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void PlanWithoutEndReplacesWholeTail()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B", "C", "D");
            h.Transport.Script(
                AddLine("这事我只跟你说一遍。", 0)
                + "event: plan\ndata: {\"mute\":false,\"end\":null,\"edits\":["
                + "{\"n\":1,\"kind\":\"edit\",\"lines\":[{\"text\":\"改写的 A\",\"emotion\":\"普通\"}]},"
                + "{\"n\":2,\"kind\":\"remove\"}]}\n\n"
                + Done());

            Assert.True(h.Controller.Submit("听着。"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("这事我只跟你说一遍。", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("改写的 A", h.Widget.CurrentFrame.Text);
            h.Advance();                                         // 组末（不接回 B/C/D）
            Assert.True(h.Controller.ClosingForTest);
            JObject finish = h.LastFinish();
            Assert.Equal(4, finish.Value<int>("finalIndex"));    // 仍用 AS2 原始末行
        }

        [Fact]
        public void PlanRemoveSkipsLineAndKeepsEnd()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B", "C", "D");
            h.Transport.Script(
                AddLine("这事不好办。", 0)
                + "event: plan\ndata: {\"end\":3,\"edits\":[{\"n\":2,\"kind\":\"remove\"}]}\n\n"
                + Done());

            Assert.True(h.Controller.Submit("怎么说？"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("这事不好办。", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("A", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("C", h.Widget.CurrentFrame.Text);       // B 被跳过
            h.Advance();
            Assert.Equal("D", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void PlanMissingNochangeKeepsOriginal()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B", "C", "D");
            h.Transport.Script(
                AddLine("……", 0)
                + "event: plan\ndata: {\"end\":4,\"edits\":[{\"n\":3,\"kind\":\"edit\","
                + "\"lines\":[{\"text\":\"改写的 C\",\"emotion\":\"普通\"}]}]}\n\n"
                + Done());

            Assert.True(h.Controller.Submit("然后呢？"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("……", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("A", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("B", h.Widget.CurrentFrame.Text);       // 未提及 = nochange
            h.Advance();
            Assert.Equal("改写的 C", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("D", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void PlanSplitEditLocksUntilLastSegment()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B", "C", "D");
            h.Transport.Script(
                AddLine("……", 0)
                + "event: plan\ndata: {\"end\":4,\"edits\":[{\"n\":3,\"kind\":\"edit\",\"lines\":["
                + "{\"text\":\"段0\",\"emotion\":\"普通\",\"split\":{\"index\":0,\"count\":2}},"
                + "{\"text\":\"段1\",\"emotion\":\"普通\",\"split\":{\"index\":1,\"count\":2}}]}]}\n\n"
                + Done());

            Assert.True(h.Controller.Submit("嗯。"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            h.Advance();
            h.Advance();
            h.Advance();
            Assert.Equal("段0", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Locked, h.Controller.InputState);
            Assert.False(h.Controller.Submit("插不了"));
            h.Advance();
            Assert.Equal("段1", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        [Fact]
        public void PlanWaitsForAllAddsBeforeApplying()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B");
            h.Transport.Script(
                AddLine("第一句", 0) + AddLine("第二句", 1)
                + "event: plan\ndata: {\"end\":1}\n\n" + Done());

            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("第一句", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("第二句", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("A", h.Widget.CurrentFrame.Text);       // end=1 接回原文
        }

        [Fact]
        public void PlanWithoutAddAppliesOnDoneAndIsNotAFailure()
        {
            using var h = new Harness(inline: false);
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B");
            var hanging = new HangingStream("");
            h.Transport.OpenAsyncOverride = _ => Task.FromResult<Stream>(hanging);

            Assert.True(h.Controller.Submit("嗯。"));
            h.Controller.OnEvent(PlanEvent("{\"end\":2,\"edits\":[{\"n\":1,\"kind\":\"edit\","
                + "\"lines\":[{\"text\":\"改写的 A\",\"emotion\":\"普通\"}]}]}"));
            h.Controller.OnEvent(DoneEvent());                   // 没有 add，只有 plan
            Assert.Null(h.Controller.LastFailure);

            h.Widget.CompleteCurrentLineTyping();                // $PC 播完 → plan 应用
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 玩家行仍在屏：隐藏

            h.Advance();
            Assert.Equal("改写的 A", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
            h.Advance();
            Assert.Equal("B", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void MuteLocksGroupButKeepsPlayingAndResetsOnNewGroup()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A");
            h.Transport.Script(
                "event: mute\ndata: {\"mute\":true}\n\n"
                + AddLine("行了，这事不用你操心。", 0)
                + "event: plan\ndata: {\"mute\":true,\"end\":1}\n\n" + Done());

            Assert.True(h.Controller.Submit("你到底说不说？"));
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState);
            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal(DialogueInterjectInputState.Hidden, h.Controller.InputState); // 玩家行仍在屏：隐藏
            Assert.False(h.Controller.Submit("再说一句"));
            Assert.Equal("（Andy Law）暂时不打算让你插话",
                h.Controller.PlaceholderFor(DialogueInterjectInputState.Muted));

            h.Advance();
            Assert.Equal("行了，这事不用你操心。", h.Widget.CurrentFrame.Text);
            Assert.Equal(DialogueInterjectInputState.Muted, h.Controller.InputState);
            h.Advance();
            Assert.Equal("A", h.Widget.CurrentFrame.Text);        // 照常播放
            Assert.Equal(DialogueInterjectInputState.Muted, h.Controller.InputState);

            h.Advance();                                          // 组末关闭 → 重置
            h.AdoptTaskBook(8, "task_pre", "200124", "换一场。");
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        [Fact]
        public void TaskMidTurnInsertCarriesUnplayedEditAsReference()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B", "C", "D");
            h.Transport.Script(
                AddLine("你倒是爽快。", 0) + "event: plan\ndata: " + TaskPlanEdit + "\n\n" + Done());
            h.Transport.Script(AddLine("新回答", 0) + Done());

            Assert.True(h.Controller.Submit("第一次"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();                                          // add 上屏
            h.Advance();                                          // 停在原文 A（n1）
            Assert.Equal("A", h.Widget.CurrentFrame.Text);

            Assert.True(h.Controller.Submit("第二次"));
            JObject request = JObject.Parse(h.Transport.LastRequest);
            var reference = (JArray)((JObject)request["dialogue"])["reference_continuation"];
            Assert.Single(reference);
            Assert.Equal("edit", reference[0].Value<string>("kind"));
            Assert.Equal(1, reference[0].Value<int>("index"));    // 改写的是 n2 → 下一轮第 1 条
            Assert.Equal("北边仓库昨晚丢了一批货。", reference[0].Value<string>("text"));
        }

        [Fact]
        public void AbandonedTailKeepsRemainingEmptyAndDropsEditReference()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B");
            h.Transport.Script(
                AddLine("这事我只跟你说一遍。", 0)
                + "event: plan\ndata: {\"end\":null,\"edits\":["
                + "{\"n\":1,\"kind\":\"edit\",\"lines\":[{\"text\":\"改写的 A\",\"emotion\":\"普通\"}]}]}\n\n"
                + Done());
            h.Transport.Script(AddLine("新回答", 0) + Done());

            Assert.True(h.Controller.Submit("第一次"));
            h.Widget.CompleteCurrentLineTyping();                 // add 就绪；plan 已应用（无 end）
            h.Advance();                                          // add 上屏
            Assert.True(h.Controller.Submit("第二次"));

            JObject request = JObject.Parse(h.Transport.LastRequest);
            JObject dialogue = (JObject)request["dialogue"];
            Assert.Empty((JArray)dialogue["remaining"]);          // 原始剩余已放弃
            Assert.Empty((JArray)dialogue["reference_continuation"]); // 原编号不存在 → 丢弃
            Assert.Equal("task", request.Value<string>("mode"));
        }

        [Fact]
        public void TaskFailureAfterAppliedPlanKeepsPlanAndDoesNotResumeOriginal()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B", "C");
            h.Transport.Script(
                AddLine("你倒是爽快。", 0)
                + "event: plan\ndata: {\"end\":3}\n\n"
                + "event: error\ndata: {\"code\":\"stream_failed\",\"message\":\"断流\"}\n\n");

            Assert.True(h.Controller.Submit("嗯。"));
            h.Widget.CompleteCurrentLineTyping();
            Assert.Equal("stream_failed", h.Controller.LastFailure);

            h.Advance();
            Assert.Equal("你倒是爽快。", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("A", h.Widget.CurrentFrame.Text);        // plan 已应用：A（n1）→ 接回 B/C
            h.Advance();
            Assert.Equal("B", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("C", h.Widget.CurrentFrame.Text);
        }

        [Fact]
        public void TaskFailureWithoutPlanRestoresOriginalTail()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。", "A", "B");
            h.Transport.Script(
                AddLine("先说一句。", 0)
                + "event: error\ndata: {\"code\":\"stream_failed\",\"message\":\"断流\"}\n\n");

            Assert.True(h.Controller.Submit("嗯。"));
            h.Widget.CompleteCurrentLineTyping();
            h.Advance();
            Assert.Equal("先说一句。", h.Widget.CurrentFrame.Text);
            h.Advance();
            Assert.Equal("A", h.Widget.CurrentFrame.Text);        // 无 plan：接回原文当前点
        }

        [Fact]
        public void LateErrorAfterDoneIsIgnored()
        {
            using var h = new Harness();
            EnableTaskContext(h);
            h.AdoptTaskBook(7, "task_pre", "200124", "你来了。");
            h.Transport.Script(AddLine("回答", 0) + Done());
            Assert.True(h.Controller.Submit("你好"));
            h.Widget.CompleteCurrentLineTyping();
            int finalizes = h.Transport.Finalizes.Count;

            h.Controller.OnEvent(ErrorEvent("stream_failed"));

            Assert.Null(h.Controller.LastFailure);
            Assert.Equal(finalizes, h.Transport.Finalizes.Count);
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

        // ── 配置门：终端在线但模型 API 未配置 ─────────────────────────────

        [Fact]
        public void TerminalStartWithoutLlmConfigLocksUntilSaved()
        {
            int dialogs = 0;
            using var h = new Harness(
                ensureReady: () => Task.FromResult(true),
                llmConfigured: () => Task.FromResult(false),
                terminalReady: false);
            h.Controller.ConfigRequired += () => dialogs++;
            h.AdoptBook("又是你。", "有事说事。");
            Assert.Equal(DialogueInterjectInputState.Offline, h.Controller.InputState);
            Assert.Equal("请先启动聊天终端",
                h.Controller.PlaceholderFor(h.Controller.InputState));

            h.TerminalReady = true;
            h.Controller.RequestTerminalStart();

            Assert.Equal(DialogueInterjectInputState.NeedsConfig, h.Controller.InputState);
            Assert.Equal(1, dialogs);                       // 从插话处启动 → 自动弹配置小窗
            Assert.Equal("请配置模型API",
                h.Controller.PlaceholderFor(h.Controller.InputState));
            Assert.False(h.Controller.Submit("配置前不能发送"));

            h.Controller.NotifyLlmConfigSaved();
            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
        }

        [Fact]
        public void TerminalStartWithConfiguredLlmUnlocksWithoutDialog()
        {
            int dialogs = 0;
            using var h = new Harness(
                ensureReady: () => Task.FromResult(true),
                llmConfigured: () => Task.FromResult(true),
                terminalReady: false);
            h.Controller.ConfigRequired += () => dialogs++;
            h.AdoptBook("又是你。");
            Assert.Equal(DialogueInterjectInputState.Offline, h.Controller.InputState);

            h.TerminalReady = true;
            h.Controller.RequestTerminalStart();

            Assert.Equal(DialogueInterjectInputState.Ready, h.Controller.InputState);
            Assert.Equal(0, dialogs);
        }

        [Fact]
        public void AlreadyRunningTerminalWithoutConfigLocksWithoutAutoDialog()
        {
            int dialogs = 0;
            using var h = new Harness(
                llmConfigured: () => Task.FromResult(false),
                terminalReady: true);
            h.Controller.ConfigRequired += () => dialogs++;
            h.AdoptBook("又是你。");

            Assert.Equal(DialogueInterjectInputState.NeedsConfig, h.Controller.InputState);
            Assert.Equal(0, dialogs);   // 非“从插话处启动”：只锁输入，不自动弹窗
        }

    }
}
