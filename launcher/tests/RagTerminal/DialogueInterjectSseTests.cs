using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.RagTerminal;
using Xunit;

namespace CF7Launcher.Tests.RagTerminal
{
    /// <summary>
    /// G0-3：逐句 SSE 客户端（fixture 驱动，不依赖真后端、不调真模型）。
    ///
    /// 覆盖《交接与契约 fixture》F-01 / F-02 / F-09 / F-10 / F-11 的 Host 侧断言：
    /// - 首句/首段早于 done 交付；
    /// - seq 单调、split 标记、mute 先于 line、error 之后不再产生台词；
    /// - 取消真断流（Dispose 在途响应流），取消后不播未到的行；
    /// - 玩家 $PC 播放期间到达的首句排队，$PC 播完再播。
    /// </summary>
    public sealed class DialogueInterjectSseTests
    {
        private const string FixedOpen =
            "event: status\ndata: {\"stage\":\"thinking\"}\n\n";

        /// <summary>内存假流：可整包也可按块吐出，模拟网络分段到达。</summary>
        private sealed class MemorySseTransport : IDialogueInterjectTransport
        {
            private readonly string _payload;
            internal int OpenCount;
            internal bool Disposed;

            internal MemorySseTransport(string payload) { _payload = payload; }

            public Task<Stream> OpenAsync(string requestJson, CancellationToken cancellationToken)
            {
                OpenCount++;
                var bytes = Encoding.UTF8.GetBytes(_payload);
                var stream = new TrackedStream(bytes);
                stream.OnDispose = delegate { Disposed = true; };
                return Task.FromResult<Stream>(stream);
            }

            public Task<Newtonsoft.Json.Linq.JObject> PostFinalizeAsync(
                string requestJson, CancellationToken cancellationToken)
            {
                return Task.FromResult(new Newtonsoft.Json.Linq.JObject { ["ok"] = true });
            }

            public Task<Newtonsoft.Json.Linq.JObject> PostActionResultAsync(
                string requestJson, CancellationToken cancellationToken)
            {
                return Task.FromResult(new Newtonsoft.Json.Linq.JObject { ["ok"] = true });
            }
        }

        /// <summary>可观测 Dispose 的只读流（证明取消会真正断流）。</summary>
        private sealed class TrackedStream : Stream
        {
            private readonly byte[] _data;
            private int _pos;
            internal Action OnDispose;

            internal TrackedStream(byte[] data) { _data = data; }

            public override bool CanRead { get { return true; } }
            public override bool CanSeek { get { return false; } }
            public override bool CanWrite { get { return false; } }
            public override long Length { get { return _data.Length; } }
            public override long Position
            {
                get { return _pos; }
                set { throw new NotSupportedException(); }
            }
            public override void Flush() { }
            public override int Read(byte[] buffer, int offset, int count)
            {
                int remain = _data.Length - _pos;
                if (remain <= 0) return 0;
                int take = Math.Min(count, remain);
                Array.Copy(_data, _pos, buffer, offset, take);
                _pos += take;
                return take;
            }
            public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
            public override void SetLength(long value) { throw new NotSupportedException(); }
            public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
            protected override void Dispose(bool disposing)
            {
                if (disposing && OnDispose != null) OnDispose();
                base.Dispose(disposing);
            }
        }

        /// <summary>首行之后永久阻塞的流：用于验证取消能真断流而不是干等。</summary>
        private sealed class BlockingStream : Stream
        {
            private readonly byte[] _head;
            private int _pos;
            private readonly ManualResetEventSlim _gate = new ManualResetEventSlim(false);
            internal int DisposeCount;
            internal Action OnDisposeHook;

            internal BlockingStream(string head) { _head = Encoding.UTF8.GetBytes(head); }

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
                throw new ObjectDisposedException("BlockingStream");
            }
            public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
            public override void SetLength(long value) { throw new NotSupportedException(); }
            public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
            protected override void Dispose(bool disposing)
            {
                if (disposing)
                {
                    Interlocked.Increment(ref DisposeCount);
                    if (OnDisposeHook != null) OnDisposeHook();
                    _gate.Set();
                }
                base.Dispose(disposing);
            }
        }

        private static DialogueInterjectStream Build(
            IDialogueInterjectTransport transport, List<DialogueInterjectEvent> seen)
        {
            return new DialogueInterjectStream(transport, seen.Add, null);
        }

        private static int IndexOf(List<DialogueInterjectEvent> seen, string textOrKind)
        {
            for (int i = 0; i < seen.Count; i++)
            {
                DialogueInterjectEvent evt = seen[i];
                if (evt.Kind == DialogueInterjectEventKind.Line && evt.Text("text") == textOrKind) return i;
                if (evt.EventName == textOrKind) return i;
            }
            return -1;
        }

        // ── F-01 日常普通：首句早于 done，seq 0/1/2，closing 无 split ──────────

        [Fact]
        public async Task F01_FirstLineArrivesBeforeDoneAndSeqIsMonotonic()
        {
            const string payload = FixedOpen
                + "event: line\ndata: {\"kind\":\"add\",\"text\":\"还能怎么样，老样子。\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":0}\n\n"
                + "event: line\ndata: {\"kind\":\"add\",\"text\":\"你倒是难得过来一趟。\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":1}\n\n"
                + "event: line\ndata: {\"kind\":\"closing\",\"text\":\"说吧，想聊什么？\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":2}\n\n"
                + "event: done\ndata: {\"dialogue_instance_id\":\"11111111-1111-4111-8111-111111111111\",\"session_id\":\"s1\",\"usage\":{}}\n\n";
            var seen = new List<DialogueInterjectEvent>();
            var transport = new MemorySseTransport(payload);
            var stream = Build(transport, seen);
            await stream.RunAsync("{}", CancellationToken.None);

            Assert.True(stream.SawTerminal);
            Assert.Equal(5, seen.Count);
            Assert.Equal(DialogueInterjectEventKind.Status, seen[0].Kind);

            var lines = new List<DialogueInterjectLine>();
            foreach (DialogueInterjectEvent evt in seen)
                if (evt.Kind == DialogueInterjectEventKind.Line) lines.Add(DialogueInterjectLine.FromEvent(evt));

            Assert.Equal(3, lines.Count);
            Assert.Equal(0, lines[0].Seq);
            Assert.Equal(1, lines[1].Seq);
            Assert.Equal(2, lines[2].Seq);
            Assert.Equal("closing", lines[2].Kind);
            Assert.False(lines[0].IsSplitHead);           // 自然单条不锁输入
            Assert.Equal(1, lines[0].SplitCount);

            // 首句严格早于 done 交付（不是"整轮结束才上屏"）
            int firstLine = -1, done = -1;
            for (int i = 0; i < seen.Count; i++)
            {
                if (firstLine < 0 && seen[i].Kind == DialogueInterjectEventKind.Line) firstLine = i;
                if (seen[i].Kind == DialogueInterjectEventKind.Done) done = i;
            }
            Assert.True(firstLine >= 0 && done > firstLine);
        }

        // ── F-02 日常拆分：split 标记 + 前置段暂锁 ───────────────────────────

        [Fact]
        public async Task F02_SplitSegmentsCarryIndexCountAndHeadIsLocked()
        {
            string payload =
                "event: line\ndata: {\"kind\":\"add\",\"text\":\"<段0>\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":0,\"split\":{\"index\":0,\"count\":2}}\n\n"
                + "event: line\ndata: {\"kind\":\"add\",\"text\":\"<段1>\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":1,\"split\":{\"index\":1,\"count\":2}}\n\n"
                + "event: line\ndata: {\"kind\":\"closing\",\"text\":\"记住了就早点回来。\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":2}\n\n"
                + "event: done\ndata: {\"dialogue_instance_id\":\"11111111-1111-4111-8111-111111111111\",\"session_id\":\"s1\"}\n\n";
            var seen = new List<DialogueInterjectEvent>();
            var stream = Build(new MemorySseTransport(payload), seen);
            await stream.RunAsync("{}", CancellationToken.None);

            var lines = new List<DialogueInterjectLine>();
            foreach (DialogueInterjectEvent evt in seen)
                if (evt.Kind == DialogueInterjectEventKind.Line) lines.Add(DialogueInterjectLine.FromEvent(evt));

            Assert.Equal(3, lines.Count);
            Assert.Equal(0, lines[0].SplitIndex);
            Assert.Equal(2, lines[0].SplitCount);
            Assert.True(lines[0].IsSplitHead);             // 前置段：输入暂锁
            Assert.False(lines[1].IsSplitHead);            // 末段：开始显示即解锁
            Assert.Equal(1, lines[1].SplitIndex);
            Assert.False(lines[2].IsSplitHead);            // closing 不带 split
            Assert.Equal(1, lines[2].SplitCount);
        }

        // ── F-09 任务 mute：mute 先于 line ───────────────────────────────────

        [Fact]
        public async Task F09_MuteEventPrecedesLine()
        {
            string payload =
                "event: mute\ndata: {\"mute\":true}\n\n"
                + "event: line\ndata: {\"kind\":\"add\",\"text\":\"行了，这事不用你操心。\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":0}\n\n"
                + "event: plan\ndata: {\"mute\":true,\"end\":1,\"edits\":[]}\n\n"
                + "event: done\ndata: {\"dialogue_instance_id\":\"22222222-2222-4222-8222-222222222222\",\"session_id\":\"s2\"}\n\n";
            var seen = new List<DialogueInterjectEvent>();
            var stream = Build(new MemorySseTransport(payload), seen);
            await stream.RunAsync("{}", CancellationToken.None);

            int mute = IndexOf(seen, "mute"), line = IndexOf(seen, "line");
            Assert.True(mute >= 0 && line > mute);
            Assert.True(seen[mute].Data.Value<bool>("mute"));

            // plan 里的 mute 也要能被上层读到（双通道）
            int plan = IndexOf(seen, "plan");
            Assert.True(plan > line);
            Assert.True(seen[plan].Data.Value<bool>("mute"));
            Assert.Equal(1, seen[plan].Int("end", -1));
        }

        // ── F-10 零有效：只有 error，不产生任何台词 ──────────────────────────

        [Fact]
        public async Task F10_ZeroValidLinesProducesOnlyErrorAndNoLines()
        {
            const string payload =
                "event: error\ndata: {\"code\":\"no_valid_lines\",\"message\":\"零条有效输出\",\"valid_lines\":0}\n\n";
            var seen = new List<DialogueInterjectEvent>();
            var stream = Build(new MemorySseTransport(payload), seen);
            await stream.RunAsync("{}", CancellationToken.None);

            Assert.Single(seen);
            Assert.Equal(DialogueInterjectEventKind.Error, seen[0].Kind);
            Assert.Equal("no_valid_lines", seen[0].Text("code"));
            Assert.Equal(0, seen[0].Int("valid_lines", -1));
            Assert.True(stream.SawTerminal);
        }

        // ── F-11 部分有效后流断：已收 line 保留，error 之后不再产生台词 ──────

        [Fact]
        public async Task F11_PartialLinesSurviveAndNothingFollowsError()
        {
            string payload =
                "event: line\ndata: {\"kind\":\"add\",\"text\":\"你先听我说。\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":0}\n\n"
                + "event: error\ndata: {\"code\":\"stream_failed\",\"message\":\"连接中断\",\"valid_lines\":1}\n\n"
                + "event: line\ndata: {\"kind\":\"add\",\"text\":\"不该出现。\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":1}\n\n";
            var seen = new List<DialogueInterjectEvent>();
            var stream = Build(new MemorySseTransport(payload), seen);
            await stream.RunAsync("{}", CancellationToken.None);

            var lines = new List<string>();
            foreach (DialogueInterjectEvent evt in seen)
                if (evt.Kind == DialogueInterjectEventKind.Line) lines.Add(evt.Text("text"));

            Assert.Single(lines);
            Assert.Equal("你先听我说。", lines[0]);
            Assert.Equal(1, seen[seen.Count - 1].Int("valid_lines", -1));
            Assert.Equal(DialogueInterjectEventKind.Error, seen[seen.Count - 1].Kind);
        }

        // ── F-12 取消：真断流，未到行不播 ───────────────────────────────────

        [Fact]
        public async Task CancelDisposesInFlightStreamAndDeliversNothingMore()
        {
            var transport = new BlockingTransport();
            var seen = new List<DialogueInterjectEvent>();
            var stream = new DialogueInterjectStream(transport, seen.Add, null);

            Task run = Task.Run(() => stream.RunAsync("{}", CancellationToken.None));
            Assert.True(SpinWait.SpinUntil(() => seen.Count == 1, 5000), "首句应先到达");
            stream.Cancel();
            Task finished = await Task.WhenAny(run, Task.Delay(5000));
            Assert.Same(run, finished);   // 取消后读取必须结束

            Assert.True(stream.Cancelled);
            Assert.Equal(1, seen.Count);                   // 取消后不再交付
            Assert.True(transport.Disposed, "取消必须 Dispose 在途响应流（真断流）");
        }

        private sealed class BlockingTransport : IDialogueInterjectTransport
        {
            internal bool Disposed;
            private readonly BlockingStream _stream = new BlockingStream(
                "event: line\ndata: {\"kind\":\"add\",\"text\":\"第一句\",\"emotion\":\"普通\",\"speaker\":\"Andy Law\",\"seq\":0}\n\n");

            public Task<Stream> OpenAsync(string requestJson, CancellationToken cancellationToken)
            {
                _stream.OnDisposeHook = delegate { Disposed = true; };
                return Task.FromResult<Stream>(_stream);
            }

            public Task<Newtonsoft.Json.Linq.JObject> PostFinalizeAsync(
                string requestJson, CancellationToken cancellationToken)
            {
                return Task.FromResult(new Newtonsoft.Json.Linq.JObject { ["ok"] = true });
            }

            public Task<Newtonsoft.Json.Linq.JObject> PostActionResultAsync(
                string requestJson, CancellationToken cancellationToken)
            {
                return Task.FromResult(new Newtonsoft.Json.Linq.JObject { ["ok"] = true });
            }
        }

        // ── 玩家 $PC 播放期间的首句排队 ─────────────────────────────────────

        [Fact]
        public void FirstLineQueuesWhilePlayerLinePlays()
        {
            var playback = new DialogueInterjectPlayback();
            var played = new List<string>();
            playback.LineReady += line => played.Add(line.Text);

            playback.BeginPlayerLine();
            Assert.True(playback.Enqueue(LineOf("还能怎么样，老样子。", 0)));
            playback.Enqueue(LineOf("你倒是难得过来一趟。", 1));
            Assert.Empty(played);                          // $PC 播放期间不上屏
            Assert.Equal(2, playback.PendingCount);

            playback.EndPlayerLine();
            Assert.Single(played);                         // 只放出第一条
            Assert.Equal("还能怎么样，老样子。", played[0]);

            playback.NotifyLineFinished();
            Assert.Equal(2, played.Count);
            Assert.Equal("你倒是难得过来一趟。", played[1]);
        }

        [Fact]
        public void CancelDropsQueuedLinesAndStopsPlayback()
        {
            var playback = new DialogueInterjectPlayback();
            var played = new List<string>();
            playback.LineReady += line => played.Add(line.Text);

            playback.BeginPlayerLine();
            playback.Enqueue(LineOf("排队1", 0));
            playback.Enqueue(LineOf("排队2", 1));
            playback.Cancel();
            playback.EndPlayerLine();
            playback.NotifyLineFinished();
            playback.Enqueue(LineOf("撤销后新到", 2));

            Assert.Empty(played);
            Assert.True(playback.PendingCount == 0);
            Assert.True(playback.Cancelled);
        }

        [Fact]
        public void MuteOnlyDisablesInputNotQueuedLines()
        {
            var playback = new DialogueInterjectPlayback();
            var played = new List<string>();
            playback.LineReady += line => played.Add(line.Text);

            playback.MarkMuted();
            playback.Enqueue(LineOf("化解台词", 0));
            Assert.True(playback.Muted);
            Assert.Single(played);                         // 禁言不吞已到台词
        }

        private static DialogueInterjectLine LineOf(string text, int seq)
        {
            return new DialogueInterjectLine
            {
                Kind = "add", Text = text, Emotion = "普通", Speaker = "Andy Law", Seq = seq
            };
        }
    }
}
