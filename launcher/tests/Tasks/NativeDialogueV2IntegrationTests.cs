using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Bus;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>wire v2 真实传输集成测试（M2 接线层）：真实 XmlSocketServer（ephemeral
    /// 端口）+ 脚本化 FakeAs2Peer（raw TcpClient，JSON+\0 帧）。对端复刻 AS2 侧规则：
    /// 发送 append 前推进 session epoch；finish.epoch &lt; session.epoch 按 stale 拒绝
    /// （沉默，不 hide 不 publish）；合法 finish 经 pending 门禁后提交一次终态并回
    /// v2 hide；已提交会话的重复 finish 只重发匹配 hide、绝不重复发布事件。
    /// 采用队列与 closing 重试节拍全部手动泵（无真实 sleep 推进逻辑时序）；每条断言
    /// 失败信息自含旅程号 + 阶段。本类内旅程串行（xunit 同类不并行）。</summary>
    public sealed class NativeDialogueV2IntegrationTests
    {
        // ════════════════ 手动泵（采用队列 / 重试节拍共用） ════════════════

        /// <summary>线程安全手动队列：socket 读线程 enqueue，测试线程 pump 执行。</summary>
        private sealed class ManualPump
        {
            private readonly object _gate = new object();
            private readonly Queue<Action> _queue = new Queue<Action>();

            internal void Enqueue(Action action) { lock (_gate) _queue.Enqueue(action); }

            internal int Pending { get { lock (_gate) return _queue.Count; } }

            internal int PumpAll()
            {
                int ran = 0;
                while (true)
                {
                    Action action;
                    lock (_gate)
                    {
                        if (_queue.Count == 0) return ran;
                        action = _queue.Dequeue();
                    }
                    action();
                    ran++;
                }
            }

            /// <summary>只执行一条已排回调。重试队列必须用本方法：成功的 RetryTick
            /// 会原地 ArmRetry 再排一条，PumpAll 在 closing 中会永不返回。</summary>
            internal bool PumpOne()
            {
                Action action;
                lock (_gate)
                {
                    if (_queue.Count == 0) return false;
                    action = _queue.Dequeue();
                }
                action();
                return true;
            }
        }

        // ════════════════ 脚本化 AS2 对端 ════════════════

        /// <summary>真实 socket 对端：后台读线程按 \0 切帧、逐帧记录入站原文；
        /// task=="cmd" 帧由 EvaluateCmd 按 AS2 规则剧本裁决（可回 hide）。
        /// 所有 AS2 会话态（PeerEpoch/CommittedRids/计数器）只在本类 _gate 下读写。</summary>
        private sealed class FakeAs2Peer : IDisposable
        {
            internal sealed class Inbound
            {
                internal string Raw;      // \0 边界内的原始帧（policy XML 也逐字记录）
                internal JObject Json;    // 非 JSON 帧为 null
            }

            private readonly object _gate = new object();
            private readonly List<Inbound> _frames = new List<Inbound>();
            private readonly List<string> _finishRaws = new List<string>();
            private readonly List<JObject> _otherCmds = new List<JObject>();
            private readonly HashSet<string> _committedRids = new HashSet<string>(StringComparer.Ordinal);
            private readonly object _writeGate = new object();
            private TcpClient _client;
            private NetworkStream _stream;
            private Thread _reader;
            private volatile bool _eof;
            internal string ReaderError;

            // ── AS2 会话侧状态（脚本复刻 §4.5/§4.6）──
            internal volatile string ActiveRequestId;
            internal volatile string ActiveSceneId;
            internal int PeerEpoch;                    // book=1；SendAppend 发送前 ++
            internal volatile bool RewardPending;      // pending 门禁：吞 cmd 不进裁决
            private int _eventsPublished;              // followingEvent 发布计数（不变量：每 rid ≤1）
            private int _staleFinishRejected;
            private int _futureFinishRejected;
            private int _swallowedFinishCount;
            private int _hideSentCount;
            private int _unexpectedCmdCount;

            internal static FakeAs2Peer Connect(int port)
            {
                var peer = new FakeAs2Peer();
                peer._client = new TcpClient();
                peer._client.Connect(IPAddress.Loopback, port);
                peer._client.NoDelay = true;
                peer._stream = peer._client.GetStream();
                peer._reader = new Thread(peer.ReaderLoop)
                {
                    IsBackground = true,
                    Name = "FakeAs2Peer.Reader"
                };
                peer._reader.Start();
                return peer;
            }

            /// <summary>Flash XMLSocket 最小接入握手：policy-file-request →
            /// cross-domain-policy。policy 帧不触发业务 ready。</summary>
            internal void PolicyHandshake(string journey)
            {
                SendRaw("<policy-file-request/>");
                WaitFor(f => f.Raw != null
                        && f.Raw.IndexOf("cross-domain-policy", StringComparison.Ordinal) >= 0,
                    journey, "policy-response");
            }

            // ── 出站（peer → host）──

            internal void SendRaw(string frame)
            {
                byte[] bytes = Encoding.UTF8.GetBytes(frame + "\0");
                lock (_writeGate)
                {
                    _stream.Write(bytes, 0, bytes.Length);
                    _stream.Flush();
                }
            }

            internal void SendJson(JObject message)
            {
                SendRaw(message.ToString(Formatting.None));
            }

            internal void SendV2(JObject payload, string callId)
            {
                var msg = new JObject { ["task"] = "native_dialogue", ["payload"] = payload };
                if (callId != null) msg["callId"] = callId;
                SendJson(msg);
            }

            internal void SendPing(string callId)
            {
                SendJson(new JObject { ["task"] = "v2itest_ping", ["callId"] = callId });
            }

            internal void SendBook(int sequence, int lineCount, string callId, int startIndex = 0)
            {
                var lines = new JArray();
                for (int i = 0; i < lineCount; i++) lines.Add(Line("第" + i + "行"));
                lock (_gate)
                {
                    ActiveRequestId = "nd:" + sequence;
                    ActiveSceneId = "scene.1";
                    PeerEpoch = 1;                       // book = 行集代际 1
                }
                SendV2(new JObject
                {
                    ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                    ["requestId"] = "nd:" + sequence, ["sceneId"] = "scene.1",
                    ["mode"] = "ordinary", ["epoch"] = 1, ["startIndex"] = startIndex,
                    ["advanceKey"] = 13, ["lines"] = lines
                }, callId);
            }

            /// <summary>AS2 规则：接受 append 时发送前推进 session epoch（不等 C# ack）。</summary>
            internal void SendAppend(int lineCount, int restartIndex, string callId)
            {
                var lines = new JArray();
                for (int i = 0; i < lineCount; i++) lines.Add(Line("追加" + i));
                int epoch;
                lock (_gate)
                {
                    PeerEpoch++;
                    epoch = PeerEpoch;
                }
                SendV2(new JObject
                {
                    ["version"] = 2, ["op"] = "append",
                    ["requestId"] = ActiveRequestId, ["sceneId"] = ActiveSceneId,
                    ["baseEpoch"] = epoch - 1, ["epoch"] = epoch,
                    ["restartIndex"] = restartIndex, ["lines"] = lines
                }, callId);
            }

            internal void SendSet(int advanceKey, string callId)
            {
                SendV2(new JObject
                {
                    ["version"] = 2, ["op"] = "set",
                    ["requestId"] = ActiveRequestId, ["sceneId"] = ActiveSceneId,
                    ["advanceKey"] = advanceKey
                }, callId);
            }

            internal void SendStatus(string callId)
            {
                SendStatus(ActiveRequestId, ActiveSceneId, callId);
            }

            internal void SendStatus(string requestId, string sceneId, string callId)
            {
                SendV2(new JObject
                {
                    ["version"] = 2, ["op"] = "status",
                    ["requestId"] = requestId, ["sceneId"] = sceneId
                }, callId);
            }

            internal void SendV1Show(int sequence, int revision)
            {
                SendJson(new JObject
                {
                    ["task"] = "native_dialogue",
                    ["payload"] = new JObject
                    {
                        ["version"] = 1, ["op"] = "show",
                        ["requestId"] = "nd:" + sequence, ["sceneId"] = "scene.1",
                        ["revision"] = revision, ["lineIndex"] = revision - 1,
                        ["lineCount"] = 3, ["name"] = "Andy Law", ["title"] = "雇佣兵",
                        ["text"] = "v1行" + revision,
                        ["portrait"] = new JObject
                        {
                            ["kind"] = "static", ["key"] = "Andy Law", ["expression"] = "普通"
                        },
                        ["imageAction"] = "keep"
                    }
                });
            }

            // ── 入站（host → peer）观测 ──

            internal Inbound WaitFor(Predicate<Inbound> pred, string journey, string step,
                int timeoutMs = 5000)
            {
                long deadline = Environment.TickCount64 + timeoutMs;
                lock (_gate)
                {
                    while (true)
                    {
                        var hit = _frames.FirstOrDefault(f => pred(f));
                        if (hit != null) return hit;
                        long remain = deadline - Environment.TickCount64;
                        if (remain <= 0 || _eof)
                            Fail(journey, step, "wait timeout (eof=" + _eof
                                + ", readerErr=" + (ReaderError ?? "-") + "); frames:\n"
                                + DumpLocked());
                        Monitor.Wait(_gate, (int)Math.Min(remain, 200));
                    }
                }
            }

            /// <summary>等到第 count 条匹配帧（帧顺序即 wire 到达顺序）。</summary>
            internal Inbound WaitForCount(Predicate<Inbound> pred, int count,
                string journey, string step, int timeoutMs = 5000)
            {
                long deadline = Environment.TickCount64 + timeoutMs;
                lock (_gate)
                {
                    while (true)
                    {
                        var matches = _frames.Where(f => pred(f)).ToList();
                        if (matches.Count >= count) return matches[count - 1];
                        long remain = deadline - Environment.TickCount64;
                        if (remain <= 0 || _eof)
                            Fail(journey, step, "want frame #" + count + " got "
                                + matches.Count + " (eof=" + _eof + "); frames:\n"
                                + DumpLocked());
                        Monitor.Wait(_gate, (int)Math.Min(remain, 200));
                    }
                }
            }

            internal List<Inbound> Snapshot()
            {
                lock (_gate) return new List<Inbound>(_frames);
            }

            internal int CountWhere(Predicate<Inbound> pred)
            {
                lock (_gate) return _frames.Count(f => pred(f));
            }

            /// <summary>入站 finish 的原始帧（含注入自检帧；wire 计数请用 CountWhere）。</summary>
            internal List<string> FinishRaws()
            {
                lock (_gate) return new List<string>(_finishRaws);
            }

            internal List<JObject> OtherCmds()
            {
                lock (_gate) return new List<JObject>(_otherCmds);
            }

            internal (int Events, int Stale, int Future, int Swallowed, int Hides,
                int Unexpected) Stats()
            {
                lock (_gate)
                    return (_eventsPublished, _staleFinishRejected, _futureFinishRejected,
                        _swallowedFinishCount, _hideSentCount, _unexpectedCmdCount);
            }

            /// <summary>不经 socket 直接喂一条 cmd 给对端剧本——用于验证 stale 规则本身
            /// （正确宿主本就不该重发旧 epoch finish，此入口证明对端拒绝路径不是空转）。</summary>
            internal string InjectCmdForTest(JObject cmd)
            {
                return EvaluateCmd(cmd, cmd.ToString(Formatting.None));
            }

            // ── AS2 规则剧本：handleAction(v2) + pending 门禁 ──

            private string EvaluateCmd(JObject cmd, string raw)
            {
                if (cmd.Value<string>("action") != "nativeDialogueAction")
                {
                    lock (_gate) _unexpectedCmdCount++;
                    return null;
                }
                if (cmd.Value<string>("verb") != "finish")
                {
                    lock (_gate) _otherCmds.Add((JObject)cmd.DeepClone());
                    return null;
                }
                string rid = cmd.Value<string>("requestId");
                string sid = cmd.Value<string>("sceneId");
                var epochToken = cmd["epoch"];
                long epoch = epochToken != null && epochToken.Type == JTokenType.Integer
                    ? epochToken.Value<long>() : -1;
                lock (_gate)
                {
                    _finishRaws.Add(raw);
                    // pending 门禁先于一切裁决：吞整包 cmd（v3 §4.6 等待业务提交）。
                    if (RewardPending) { _swallowedFinishCount++; return null; }
                    if (rid != ActiveRequestId || sid != ActiveSceneId)
                    {
                        _unexpectedCmdCount++;
                        return null;
                    }
                    // 未来/缺失/非整数 epoch：拒绝并诊断（沉默）。
                    if (epoch < 0 || epoch > PeerEpoch) { _futureFinishRejected++; return null; }
                    // stale finish：不放 claim、不 publish、不补播尾部。
                    if (epoch < PeerEpoch) { _staleFinishRejected++; return null; }
                    // 已提交会话的重复 finish：允许重发匹配 hide，绝不重复发布。
                    if (_committedRids.Contains(rid))
                    {
                        _hideSentCount++;
                        return HideWire(rid, sid);
                    }
                    _committedRids.Add(rid);
                    _eventsPublished++;
                    _hideSentCount++;
                    return HideWire(rid, sid);
                }
            }

            private static string HideWire(string rid, string sid)
            {
                return new JObject
                {
                    ["task"] = "native_dialogue",
                    ["payload"] = new JObject
                    {
                        ["version"] = 2, ["op"] = "hide",
                        ["requestId"] = rid, ["sceneId"] = sid
                    }
                }.ToString(Formatting.None);
            }

            private string DumpLocked()
            {
                return string.Join("\n", _frames.Select((f, i) =>
                {
                    string raw = f.Raw ?? "";
                    if (raw.Length > 160) raw = raw.Substring(0, 160) + "…";
                    return "  #" + i + " " + raw;
                }));
            }

            private void ReaderLoop()
            {
                var buffer = new byte[8192];
                var pending = new MemoryStream();
                try
                {
                    while (true)
                    {
                        int n = _stream.Read(buffer, 0, buffer.Length);
                        if (n <= 0) break;
                        int start = 0;
                        for (int i = 0; i < n; i++)
                        {
                            if (buffer[i] != 0) continue;
                            if (i > start) pending.Write(buffer, start, i - start);
                            string raw = Encoding.UTF8.GetString(
                                pending.GetBuffer(), 0, (int)pending.Length);
                            pending.SetLength(0);
                            if (raw.Length > 0) OnFrame(raw);
                            start = i + 1;
                        }
                        if (start < n) pending.Write(buffer, start, n - start);
                    }
                }
                catch (Exception ex)
                {
                    ReaderError = ex.GetType().Name + ": " + ex.Message;
                }
                finally
                {
                    _eof = true;
                    lock (_gate) Monitor.PulseAll(_gate);
                }
            }

            private void OnFrame(string raw)
            {
                JObject json = null;
                try { json = JObject.Parse(raw); } catch { }
                string reply = null;
                if (json != null && json.Value<string>("task") == "cmd")
                    reply = EvaluateCmd(json, raw);
                lock (_gate)
                {
                    _frames.Add(new Inbound { Raw = raw, Json = json });
                    Monitor.PulseAll(_gate);
                }
                if (reply != null)
                {
                    try { SendRaw(reply); } catch { }
                }
            }

            public void Dispose()
            {
                try { _stream?.Close(); } catch { }
                try { _client?.Close(); } catch { }
            }
        }

        // ════════════════ 接线夹具：真 server + 真 task + 手动泵 ════════════════

        /// <summary>生产同款接线：router.RegisterAsync(native_dialogue → task.HandleAsync)、
        /// OnClientReadyForGeneration → PushCapsForGeneration、OnClientDisconnected →
        /// HandleTransportDisconnected；dispatch 与 BookRetryScheduler/Clock 全手动。</summary>
        private sealed class WireFixture : IDisposable
        {
            internal readonly MessageRouter Router = new MessageRouter();
            internal readonly XmlSocketServer Server;
            internal readonly Control Anchor;
            internal readonly NativeDialogueWidget Widget;
            internal readonly NativeDialogueTask Task;
            internal readonly ManualPump Dispatch = new ManualPump();
            internal readonly ManualPump Retry = new ManualPump();
            internal readonly List<long> RetryDelays = new List<long>();
            internal readonly List<FakeAs2Peer> Peers = new List<FakeAs2Peer>();
            internal int Port;
            internal long FakeNow;
            internal int DisconnectEvents;

            internal WireFixture()
            {
                Router.RegisterSync("v2itest_ping", _ => "{\"ok\":true}");
                Server = new XmlSocketServer(Router, AllowLoopbackXmlSocketPeerAuthority.Instance);
                Anchor = new Control { Size = new Size(1024, 576) };
                Widget = new NativeDialogueWidget(Anchor);
                Task = new NativeDialogueTask(Server, Widget, Dispatch.Enqueue, () => true);
                Task.BookRetryScheduler = (ms, cb) =>
                {
                    lock (RetryDelays) RetryDelays.Add(ms);
                    Retry.Enqueue(cb);
                };
                Task.BookRetryClock = () => FakeNow;
                Router.RegisterAsync("native_dialogue", Task.HandleAsync);
                Server.OnClientReadyForGeneration += Task.PushCapsForGeneration;
                Server.OnClientDisconnected += Task.HandleTransportDisconnected;
                Server.OnClientDisconnected +=
                    () => Interlocked.Increment(ref DisconnectEvents);
                Port = ProbeFreePort();
                Assert.True(Server.Start(Port), "fixture: XmlSocketServer.Start failed");
            }

            /// <summary>新对端全接入：TCP → policy 握手 → 首条业务 ping → 等本代 caps
            /// （逐字断言）→ 等 ping 应答（ready 后首帧顺序 = caps 先于业务应答）。</summary>
            internal FakeAs2Peer NewPeer(string journey)
            {
                var peer = FakeAs2Peer.Connect(Port);
                Peers.Add(peer);
                peer.PolicyHandshake(journey);
                Assert.True(
                    SpinWait.SpinUntil(() => Server.HasClient, TimeSpan.FromSeconds(5)),
                    "[" + journey + "/accept] server 未见客户端");
                string hb = "hb-" + Peers.Count;
                peer.SendPing(hb);
                var caps = peer.WaitFor(IsCaps, journey, "caps");
                Assert.Equal(
                    "{\"task\":\"dialogue_caps\",\"modes\":[\"snapshot\",\"book\"]}",
                    caps.Raw);
                Assert.Equal(NativeDialogueTask.CapsWire, caps.Raw);
                peer.WaitFor(HasCallId(hb), journey, "ready-pong");
                Assert.True(Server.IsClientReady,
                    "[" + journey + "/ready] IsClientReady 应为 true");
                return peer;
            }

            internal void Pump() { Dispatch.PumpAll(); }

            /// <summary>推进一次 closing 重试节拍（手动时钟步进，无真实 sleep）。</summary>
            internal void PumpRetry()
            {
                FakeNow += 800;
                Retry.PumpOne();
            }

            internal void Advance()
            {
                var frame = Widget.CurrentFrame;
                Assert.NotNull(frame);
                Widget.InputRequested(frame, "advance");
            }

            internal void CloseInput()
            {
                var frame = Widget.CurrentFrame;
                Assert.NotNull(frame);
                Widget.InputRequested(frame, "close");
            }

            /// <summary>等对端回包被排入采用队列后泵之（hide 等无应答报文的收口步）。</summary>
            internal void PumpNextInbound(string journey, string step)
            {
                Assert.True(
                    SpinWait.SpinUntil(() => Dispatch.Pending > 0, TimeSpan.FromSeconds(5)),
                    "[" + journey + "/" + step + "] 采用队列未见新报文");
                Pump();
            }

            public void Dispose()
            {
                foreach (var peer in Peers) { try { peer.Dispose(); } catch { } }
                try { Server.Dispose(); } catch { }
                try { Widget.Dispose(); } catch { }
                try { Anchor.Dispose(); } catch { }
            }

            private static int ProbeFreePort()
            {
                var listener = new TcpListener(IPAddress.Loopback, 0);
                listener.Start();
                int port = ((IPEndPoint)listener.LocalEndpoint).Port;
                listener.Stop();
                return port;
            }
        }

        // ════════════════ 共享断言/谓词 ════════════════

        private static JObject Line(string text)
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

        private static bool IsCaps(FakeAs2Peer.Inbound f)
        {
            return f.Json != null && f.Json.Value<string>("task") == "dialogue_caps";
        }

        private static bool IsCmd(FakeAs2Peer.Inbound f)
        {
            return f.Json != null && f.Json.Value<string>("task") == "cmd";
        }

        private static bool IsFinish(FakeAs2Peer.Inbound f)
        {
            return IsCmd(f) && f.Json.Value<string>("verb") == "finish";
        }

        private static Predicate<FakeAs2Peer.Inbound> HasCallId(string callId)
        {
            return f => f.Json != null && f.Json.Value<string>("callId") == callId;
        }

        private static void Fail(string journey, string step, string detail)
        {
            Assert.Fail("[" + journey + "/" + step + "] " + detail);
        }

        /// <summary>发 book → 等采用动作入队并泵之 → 等 applied ack；返回 ack JSON。
        /// （send 与 socket 读线程异线程：必须先等 enqueue 再 pump，否则泵空队列。）</summary>
        private static JObject AdoptBook(WireFixture fx, FakeAs2Peer peer,
            int sequence, int lineCount, string journey)
        {
            string callId = "cb-book-" + sequence;
            peer.SendBook(sequence, lineCount, callId);
            fx.PumpNextInbound(journey, "book-enqueue");
            var ack = peer.WaitFor(HasCallId(callId), journey, "book-ack").Json;
            if (ack == null || ack.Value<string>("status") != "applied")
                Fail(journey, "book-ack", "expect applied, got "
                    + (ack != null ? ack.ToString(Formatting.None) : "null"));
            if (fx.Widget.CurrentFrame == null)
                Fail(journey, "book-adopt", "widget 无呈现帧");
            return ack;
        }

        /// <summary>发 status 查询 → 泵 → 等应答（FIFO：应答到达即此前全部
        /// host→peer 帧均已到达，可作静默断言的排序锚点）。</summary>
        private static JObject QueryStatus(WireFixture fx, FakeAs2Peer peer,
            string callId, string journey)
        {
            peer.SendStatus(callId);
            fx.PumpNextInbound(journey, "status-enqueue");
            return peer.WaitFor(HasCallId(callId), journey, "status-reply").Json;
        }

        // ════════════════ 旅程 ════════════════

        [Fact]
        public void J01_HandshakePushesCapsVerbatimPerGeneration()
        {
            const string J = "J01-handshake-caps";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);
            var frames = peer.Snapshot();
            int capsIdx = frames.FindIndex(f => IsCaps(f));
            int pongIdx = frames.FindIndex(HasCallId("hb-1"));
            Assert.True(capsIdx >= 0 && pongIdx > capsIdx,
                "[" + J + "/order] caps 必须先于业务应答 capsIdx=" + capsIdx
                + " pongIdx=" + pongIdx);

            // 换代重连：每一代 ready 都重发一次 caps（gen≥2 不缺口）。
            peer.Dispose();
            Assert.True(
                SpinWait.SpinUntil(
                    () => Volatile.Read(ref fx.DisconnectEvents) >= 1,
                    TimeSpan.FromSeconds(5)),
                "[" + J + "/disconnect] server 未感知断线");
            fx.Pump();
            var peer2 = fx.NewPeer(J + "-gen2");
            Assert.Equal(1, peer2.CountWhere(f => IsCaps(f)));
        }

        [Fact]
        public void J02_BookAckSentOnlyAfterUiAdoption()
        {
            const string J = "J02-book-ack-after-adopt";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);

            peer.SendBook(7, 2, "cb-book");
            peer.SendPing("cb-ping");
            // pong 到达 ⇒ 读线程已越过 book 报文且采用动作已入队；
            // 采用点未跑，ack 绝不得先出（ack=已采用，非已投递）。
            peer.WaitFor(HasCallId("cb-ping"), J, "pong-after-book");
            Assert.True(fx.Dispatch.Pending >= 1,
                "[" + J + "/queued] 采用动作应已在队列");
            Assert.Equal(0, peer.CountWhere(HasCallId("cb-book")));
            Assert.Null(fx.Widget.CurrentFrame);

            fx.Pump();                                   // 采用点：校验 + ShowFrame + 应答
            Assert.NotNull(fx.Widget.CurrentFrame);
            Assert.Equal("第0行", fx.Widget.CurrentFrame.Text);
            var ack = peer.WaitFor(HasCallId("cb-book"), J, "ack").Json;
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal("book", ack.Value<string>("op"));
            Assert.Equal("nd:7", ack.Value<string>("requestId"));
            Assert.Equal("scene.1", ack.Value<string>("sceneId"));
            Assert.Equal(1, ack.Value<int>("requestedEpoch"));
            Assert.Equal(1, ack.Value<int>("appliedEpoch"));

            var frames = peer.Snapshot();
            Assert.True(
                frames.FindIndex(HasCallId("cb-book"))
                    > frames.FindIndex(HasCallId("cb-ping")),
                "[" + J + "/order] ack 必须晚于采用点（pong 之后）");
        }

        [Fact]
        public void J03_LocalAdvanceIsZeroWireAndRevisionMonotonic()
        {
            const string J = "J03-local-advance-zero-wire";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);
            AdoptBook(fx, peer, 7, 3, J);
            int rev0 = fx.Widget.CurrentFrame.Revision;

            fx.Advance();                                // OnInput → AdvanceLocal（本地换句）
            Assert.Equal("第1行", fx.Widget.CurrentFrame.Text);
            Assert.True(fx.Widget.CurrentFrame.Revision > rev0,
                "[" + J + "/revision] 本地 revision 必须单调");
            int rev1 = fx.Widget.CurrentFrame.Revision;
            fx.Advance();
            Assert.Equal("第2行", fx.Widget.CurrentFrame.Text);
            Assert.True(fx.Widget.CurrentFrame.Revision > rev1);

            // FIFO 静默证法：status 应答到达 ⇒ 此前全部 host→peer 帧已到达。
            var status = QueryStatus(fx, peer, "cb-st", J);
            Assert.Equal("active", status.Value<string>("state"));
            Assert.Equal(1, status.Value<int>("appliedEpoch"));
            Assert.Equal(3, status.Value<int>("rowCount"));
            Assert.Equal(0, peer.CountWhere(IsCmd));     // 本地换句全程零 wire
        }

        [Fact]
        public void J04_FrozenFinishRetriesByteIdenticalUntilHideCloses()
        {
            const string J = "J04-frozen-finish-retry-hide";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);
            AdoptBook(fx, peer, 7, 2, J);
            peer.RewardPending = true;                   // pending 门禁：吞 cmd

            fx.Advance();                                // → 末行
            fx.Advance();                                // 越末行 → closing，首发冻结 finish
            var f1 = peer.WaitForCount(IsFinish, 1, J, "finish#1");
            Assert.Equal("cmd", f1.Json.Value<string>("task"));
            Assert.Equal("nativeDialogueAction", f1.Json.Value<string>("action"));
            Assert.Equal("nd:7", f1.Json.Value<string>("requestId"));
            Assert.Equal("scene.1", f1.Json.Value<string>("sceneId"));
            Assert.Equal("finish", f1.Json.Value<string>("verb"));
            Assert.Equal(1, f1.Json.Value<int>("epoch"));
            Assert.Equal(1, f1.Json.Value<int>("finalIndex"));   // 规范化行数-1
            Assert.Equal("advance_past_end", f1.Json.Value<string>("reason"));
            Assert.Null(f1.Json["revision"]);            // v2 终态不带 revision

            fx.PumpRetry();                              // 被吞 → 重试，逐字节相同
            var f2 = peer.WaitForCount(IsFinish, 2, J, "finish#2");
            Assert.Equal(f1.Raw, f2.Raw);
            fx.PumpRetry();
            var f3 = peer.WaitForCount(IsFinish, 3, J, "finish#3");
            Assert.Equal(f1.Raw, f3.Raw);
            Assert.Single(peer.FinishRaws().Distinct()); // 冻结性：同 payload 无第二变体
            Assert.Equal(3, peer.Stats().Swallowed);     // 门禁实吞 3 次
            lock (fx.RetryDelays)
                Assert.All(fx.RetryDelays, d => Assert.InRange(d, 500, 1000));

            peer.RewardPending = false;                  // pending 解除
            fx.PumpRetry();                              // 重试到达 → 合法 finish → 提交 + hide
            peer.WaitForCount(IsFinish, 4, J, "finish#4");
            fx.PumpNextInbound(J, "hide-adopt");         // hide 上泵采用 → 墓碑
            Assert.Null(fx.Widget.CurrentFrame);
            var stats = peer.Stats();
            Assert.Equal(1, stats.Events);               // 终态事件恰好一次
            Assert.Equal(1, stats.Hides);

            fx.PumpRetry();                              // 在途重试回调已失效
            var none = QueryStatus(fx, peer, "cb-st", J);
            Assert.Equal("none", none.Value<string>("state"));
            Assert.Equal(4, peer.CountWhere(IsFinish));  // hide 之后零新增 finish
        }

        [Fact]
        public void J05_AppendRevivesClosingAndStaleFinishStaysSilent()
        {
            const string J = "J05-append-revives-closing";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);
            AdoptBook(fx, peer, 7, 1, J);
            peer.RewardPending = true;
            fx.Advance();                                // 单行 book 越末 → closing
            peer.WaitForCount(IsFinish, 1, J, "finish#1");
            fx.PumpRetry();
            peer.WaitForCount(IsFinish, 2, J, "finish#2");

            // AS2 发送前推进 epoch（SendAppend 内 ++）：baseEpoch=1 / epoch=2。
            peer.SendAppend(1, 1, "cb-ap");
            fx.PumpNextInbound(J, "append-enqueue");
            var ack = peer.WaitFor(HasCallId("cb-ap"), J, "append-ack").Json;
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal(2, ack.Value<int>("appliedEpoch"));
            // 复活证据：取消重试、回 active、按 restartIndex 重播合并后行集。
            Assert.Equal("追加0", fx.Widget.CurrentFrame.Text);
            Assert.Equal(1, fx.Widget.CurrentFrame.LineIndex);
            Assert.Equal(2, fx.Widget.CurrentFrame.LineCount);
            Assert.Equal(2, fx.Widget.CurrentFrame.Revision);   // 本地 revision 续单调
            var active = QueryStatus(fx, peer, "cb-st1", J);
            Assert.Equal("active", active.Value<string>("state"));
            Assert.Equal(2, active.Value<int>("appliedEpoch"));
            Assert.Equal(2, active.Value<int>("rowCount"));

            fx.PumpRetry();                              // 复活已撤旧终态重试
            QueryStatus(fx, peer, "cb-st2", J);          // FIFO 锚点
            Assert.Equal(2, peer.CountWhere(IsFinish));  // 旧 epoch finish 绝不再发
            var mid = peer.Stats();
            Assert.Equal(0, mid.Events);                 // 被吞旧 finish 零发布
            Assert.Equal(0, mid.Hides);

            // 对端剧本 stale 裁决自检：旧 epoch finish 若迟到到达 → 沉默
            // （不 hide、不 publish、不补播；正确宿主本就不会重发，此步证明对端非空转）。
            // 注意必须先解除 pending 门禁，否则该包按剧本被门禁吞掉而非进 stale 分支。
            peer.RewardPending = false;
            var staleReply = peer.InjectCmdForTest(new JObject
            {
                ["task"] = "cmd", ["action"] = "nativeDialogueAction",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1",
                ["verb"] = "finish", ["epoch"] = 1,
                ["finalIndex"] = 0, ["reason"] = "advance_past_end"
            });
            Assert.Null(staleReply);
            Assert.Equal(1, peer.Stats().Stale);
            Assert.Equal(0, peer.Stats().Events);        // 旧 epoch 不结束新行集

            // 新行集继续到末 → 新冻结 finish 用新代际 epoch=2。
            fx.Advance();                                // index1 已是合并后末行 → closing
            var f3 = peer.WaitForCount(IsFinish, 3, J, "finish#3");
            Assert.Equal(2, f3.Json.Value<int>("epoch"));
            Assert.Equal(1, f3.Json.Value<int>("finalIndex"));
            fx.PumpNextInbound(J, "hide-adopt");
            Assert.Null(fx.Widget.CurrentFrame);
            var done = peer.Stats();
            Assert.Equal(1, done.Events);                // 恰好一次终态发布
            Assert.Equal(1, done.Hides);
            Assert.Equal(0, done.Unexpected);
        }

        [Fact]
        public void J06_SetDuringClosingKeepsRetryingFrozenFinish()
        {
            const string J = "J06-set-keeps-retry";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);
            AdoptBook(fx, peer, 7, 1, J);
            peer.RewardPending = true;
            fx.CloseInput();                             // verb=close → closing(close)
            var f1 = peer.WaitForCount(IsFinish, 1, J, "finish#1");
            Assert.Equal("close", f1.Json.Value<string>("reason"));
            Assert.Equal(0, f1.Json.Value<int>("finalIndex"));

            peer.SendSet(32, "cb-set");
            fx.PumpNextInbound(J, "set-enqueue");
            var ack = peer.WaitFor(HasCallId("cb-set"), J, "set-ack").Json;
            Assert.Equal("applied", ack.Value<string>("status"));
            Assert.Equal("set", ack.Value<string>("op"));
            Assert.Equal(1, ack.Value<int>("appliedEpoch"));   // set 不 bump epoch
            Assert.NotNull(fx.Task.CaptureKeyboardAction(32)); // advanceKey 已生效

            fx.PumpRetry();                              // set 不终止 closing：续试原冻结请求
            var f2 = peer.WaitForCount(IsFinish, 2, J, "finish#2");
            Assert.Equal(f1.Raw, f2.Raw);
            Assert.Single(peer.FinishRaws().Distinct());
        }

        [Fact]
        public void J07_StatusQueryReportsActiveClosingNoneOverWire()
        {
            const string J = "J07-status-three-states";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);
            AdoptBook(fx, peer, 7, 3, J);

            var active = QueryStatus(fx, peer, "cb-a", J);
            Assert.Equal("active", active.Value<string>("state"));
            Assert.Equal(1, active.Value<int>("appliedEpoch"));
            Assert.Equal(3, active.Value<int>("rowCount"));
            Assert.Equal("nd:7", active.Value<string>("requestId"));

            peer.RewardPending = true;
            fx.Advance(); fx.Advance(); fx.Advance();    // 越末 → closing
            peer.WaitForCount(IsFinish, 1, J, "finish");
            var closing = QueryStatus(fx, peer, "cb-c", J);
            Assert.Equal("closing", closing.Value<string>("state"));
            Assert.Equal(1, closing.Value<int>("appliedEpoch"));
            Assert.Equal(3, closing.Value<int>("rowCount"));

            peer.SendStatus("nd:99", "scene.1", "cb-n");
            fx.PumpNextInbound(J, "status-none-enqueue");
            var none = peer.WaitFor(HasCallId("cb-n"), J, "status-none").Json;
            Assert.Equal("none", none.Value<string>("state"));
            Assert.Equal(0, none.Value<int>("appliedEpoch"));
            Assert.Equal(0, none.Value<int>("rowCount"));
        }

        [Fact]
        public void J08_DisconnectStopsRetryAndNeverCrossesGeneration()
        {
            const string J = "J08-disconnect-stops-retry";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);
            AdoptBook(fx, peer, 7, 1, J);
            peer.RewardPending = true;
            fx.Advance();                                // closing + finish#1
            peer.WaitForCount(IsFinish, 1, J, "finish#1");

            peer.Dispose();                              // 真断线（FIN）
            Assert.True(
                SpinWait.SpinUntil(
                    () => Volatile.Read(ref fx.DisconnectEvents) >= 1,
                    TimeSpan.FromSeconds(5)),
                "[" + J + "/disconnect] server 未感知断线");
            fx.Pump();                                   // 断线收口：TerminateBookSession
            Assert.Null(fx.Widget.CurrentFrame);
            fx.PumpRetry();                              // 在途重试回调 token 失效
            fx.PumpRetry();

            var peer2 = fx.NewPeer(J + "-gen2");         // 新代：caps 重发（内部已逐字验）
            AdoptBook(fx, peer2, 8, 1, J);
            Assert.Equal(0, peer2.CountWhere(IsCmd));    // 跨 generation 零 finish/cmd
            fx.PumpRetry();
            QueryStatus(fx, peer2, "cb-st", J);          // FIFO 锚点
            Assert.Equal(0, peer2.CountWhere(IsCmd));
        }

        [Fact]
        public void J09_V1AndV2CoexistOnSameConnection()
        {
            const string J = "J09-v1-v2-coexist";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);

            peer.SendV1Show(1, 1);
            peer.SendPing("cb-p");
            peer.WaitFor(HasCallId("cb-p"), J, "pong");  // v1 show 已被读线程接过
            fx.Pump();                                   // v1 采用（fire-and-forget，无 ack）
            Assert.Equal("nd:1", fx.Widget.CurrentFrame.RequestId);
            Assert.Equal("v1行1", fx.Widget.CurrentFrame.Text);

            fx.Advance();                                // v1 会话：OnInput → v1 cmd
            var cmd = peer.WaitForCount(IsCmd, 1, J, "v1-cmd");
            Assert.Equal("advance", cmd.Json.Value<string>("verb"));
            Assert.Equal(1, cmd.Json.Value<int>("revision"));
            Assert.Null(cmd.Json["epoch"]);              // v1 cmd 无 epoch

            // 同连接切 v2 book（更高 rid）：ack + book 会话，与 v1 互不串。
            AdoptBook(fx, peer, 7, 2, J);
            Assert.Equal("nd:7", fx.Widget.CurrentFrame.RequestId);
            Assert.Equal("第0行", fx.Widget.CurrentFrame.Text);
            fx.Advance();                                // v2 本地换句零 wire
            Assert.Equal("第1行", fx.Widget.CurrentFrame.Text);

            var status = QueryStatus(fx, peer, "cb-s", J);
            Assert.Equal("active", status.Value<string>("state"));
            Assert.Equal(2, status.Value<int>("rowCount"));
            Assert.Equal(1, peer.CountWhere(IsCmd));     // 全程仅 v1 那一条 cmd
            var other = Assert.Single(peer.OtherCmds());
            Assert.Equal("advance", other.Value<string>("verb"));
            Assert.Equal(0, peer.Stats().Unexpected);
        }

        [Fact]
        public void J10_RejectedOpsDoNotTerminateClosingOverWire()
        {
            const string J = "J10-rejected-ops-keep-closing";
            using var fx = new WireFixture();
            var peer = fx.NewPeer(J);
            AdoptBook(fx, peer, 7, 1, J);
            peer.RewardPending = true;
            fx.Advance();                                // closing + finish#1
            var f1 = peer.WaitForCount(IsFinish, 1, J, "finish#1");

            // 被拒的高 sequence 报文（畸形 book nd:9 缺 lines）不终止 closing、不推进前沿。
            peer.SendV2(new JObject
            {
                ["version"] = 2, ["op"] = "book", ["kind"] = "inline",
                ["requestId"] = "nd:9", ["sceneId"] = "scene.1",
                ["mode"] = "ordinary", ["epoch"] = 1
            }, "cb-bad");
            fx.PumpNextInbound(J, "badbook-enqueue");
            var rej = peer.WaitFor(HasCallId("cb-bad"), J, "rej-ack").Json;
            Assert.Equal("rejected", rej.Value<string>("status"));
            Assert.Equal("malformed", rej.Value<string>("reason"));
            Assert.Equal(1, rej.Value<int>("appliedEpoch"));

            // 代际不连续 append 同形：被拒亦不终止 closing。
            peer.SendV2(new JObject
            {
                ["version"] = 2, ["op"] = "append",
                ["requestId"] = "nd:7", ["sceneId"] = "scene.1",
                ["baseEpoch"] = 5, ["epoch"] = 6,
                ["lines"] = new JArray(Line("x"))
            }, "cb-gap");
            fx.PumpNextInbound(J, "gap-enqueue");
            var gap = peer.WaitFor(HasCallId("cb-gap"), J, "gap-ack").Json;
            Assert.Equal("rejected", gap.Value<string>("status"));
            Assert.Equal("epoch_gap", gap.Value<string>("reason"));

            fx.PumpRetry();                              // closing 存活：冻结请求续试
            var f2 = peer.WaitForCount(IsFinish, 2, J, "finish#2");
            Assert.Equal(f1.Raw, f2.Raw);

            peer.RewardPending = false;                  // 收口仍正常：重试 → hide → closed
            fx.PumpRetry();
            peer.WaitForCount(IsFinish, 3, J, "finish#3");
            fx.PumpNextInbound(J, "hide-adopt");
            Assert.Null(fx.Widget.CurrentFrame);
            var none = QueryStatus(fx, peer, "cb-st", J);
            Assert.Equal("none", none.Value<string>("state"));
            Assert.Single(peer.FinishRaws().Distinct()); // 全程同一份冻结请求
            Assert.Equal(1, peer.Stats().Events);
        }
    }
}
