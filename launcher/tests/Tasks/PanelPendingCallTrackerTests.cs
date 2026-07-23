using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Tasks;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class PanelPendingCallTrackerTests
    {
        [Fact]
        public void ReadinessAndRejectedCallIds_AreExplicitAndDeduplicated()
        {
            int sends = 0;
            int ended = 0;
            using (var tracker = new PanelPendingCallTracker<string>(
                () => false,
                _ => { sends++; return true; },
                1000,
                (_, __) => ended++))
            {
                int backendCallId;
                Assert.False(tracker.IsReady());
                Assert.True(tracker.TryRememberRejected("web.not-ready.1"));
                Assert.False(tracker.TryRememberRejected("web.not-ready.1"));
                Assert.Equal(0, sends);
                Assert.Equal(0, ended);
                Assert.True(tracker.IsKnownWebCallId("web.not-ready.1"));
                Assert.False(tracker.TryBegin("web.not-ready.1", "other", out backendCallId));
                Assert.Equal(0, backendCallId);
            }
        }

        [Fact]
        public void TryBegin_DoesNotRecheckTheCallersReadinessSnapshot()
        {
            int readinessChecks = 0;
            PanelPendingCallEndReason? ended = null;
            using (var tracker = new PanelPendingCallTracker<string>(
                () => Interlocked.Increment(ref readinessChecks) == 1,
                _ => false,
                1000,
                (_, reason) => ended = reason))
            {
                Assert.True(tracker.IsReady());
                int backendCallId;
                Assert.True(tracker.TryBegin("web.ready-snapshot.1", "context", out backendCallId));

                tracker.Send(backendCallId, "payload");

                Assert.Equal(1, readinessChecks);
                Assert.Equal(PanelPendingCallEndReason.DeliveryUnknown, ended);
            }
        }

        [Fact]
        public void ActiveAndRecentWebCallIds_AreSuppressed()
        {
            using (var tracker = NewTracker(1000, delegate { }))
            {
                int backendCallId;
                Assert.True(tracker.TryBegin("web.duplicate.1", "first", out backendCallId));

                int duplicateBackendCallId;
                Assert.False(tracker.TryBegin(
                    "web.duplicate.1",
                    "active-duplicate",
                    out duplicateBackendCallId));
                Assert.Equal(0, duplicateBackendCallId);

                PanelPendingCall<string> completed;
                Assert.True(tracker.TryComplete(backendCallId, out completed));
                Assert.Equal("first", completed.Context);
                Assert.False(tracker.TryComplete(backendCallId, out completed));

                Assert.False(tracker.TryBegin(
                    "web.duplicate.1",
                    "recent-duplicate",
                    out duplicateBackendCallId));
            }
        }

        [Fact]
        public void TimeoutThenLateResponse_ProducesOneTerminal()
        {
            var ended = new List<PanelPendingCallEndReason>();
            using (var seen = new ManualResetEventSlim(false))
            using (var tracker = NewTracker(
                20,
                reason =>
                {
                    lock (ended) { ended.Add(reason); }
                    seen.Set();
                }))
            {
                int backendCallId;
                Assert.True(tracker.TryBegin("web.timeout.1", "context", out backendCallId));
                tracker.Send(backendCallId, "payload");
                Assert.True(seen.Wait(TimeSpan.FromSeconds(2)));

                PanelPendingCall<string> completed;
                Assert.False(tracker.TryComplete(backendCallId, out completed));
                lock (ended)
                {
                    Assert.Single(ended);
                    Assert.Equal(PanelPendingCallEndReason.Timeout, ended[0]);
                }
            }
        }

        [Fact]
        public async Task ResponseAndTimeoutRace_HasExactlyOneWinner()
        {
            int terminalCount = 0;
            using (var releaseResponse = new ManualResetEventSlim(false))
            using (var tracker = new PanelPendingCallTracker<string>(
                () => true,
                _ => true,
                30,
                (_, __) => Interlocked.Increment(ref terminalCount)))
            {
                int backendCallId;
                Assert.True(tracker.TryBegin("web.race.1", "context", out backendCallId));
                tracker.Send(backendCallId, "payload");

                Task response = Task.Run(delegate
                {
                    releaseResponse.Wait();
                    PanelPendingCall<string> completed;
                    if (tracker.TryComplete(backendCallId, out completed))
                        Interlocked.Increment(ref terminalCount);
                });

                await Task.Delay(30);
                releaseResponse.Set();
                await response.WaitAsync(TimeSpan.FromSeconds(2));
                for (int i = 0; i < 200 && Volatile.Read(ref terminalCount) != 1; i++)
                    await Task.Delay(10);
                Assert.Equal(1, Volatile.Read(ref terminalCount));
                await Task.Delay(60);
                Assert.Equal(1, Volatile.Read(ref terminalCount));
            }
        }

        [Fact]
        public void SendFalse_EndsAsDeliveryUnknownOnce()
        {
            var ended = new List<Tuple<PanelPendingCall<string>, PanelPendingCallEndReason>>();
            using (var tracker = new PanelPendingCallTracker<string>(
                () => true,
                _ => false,
                1000,
                (call, reason) => ended.Add(Tuple.Create(call, reason))))
            {
                int backendCallId;
                Assert.True(tracker.TryBegin("web.send-false.1", "opaque", out backendCallId));

                tracker.Send(backendCallId, "payload");
                Assert.Single(ended);
                Assert.Equal("web.send-false.1", ended[0].Item1.WebCallId);
                Assert.Equal("opaque", ended[0].Item1.Context);
                Assert.Equal(PanelPendingCallEndReason.DeliveryUnknown, ended[0].Item2);

                PanelPendingCall<string> completed;
                Assert.False(tracker.TryComplete(backendCallId, out completed));
                tracker.Send(backendCallId, "payload-again");
                Assert.Single(ended);
            }
        }

        [Fact]
        public void ClearAndDispose_DrainOnceAndSuppressLateResponses()
        {
            var ended = new List<string>();
            var tracker = new PanelPendingCallTracker<string>(
                () => true,
                _ => true,
                1000,
                (call, reason) => ended.Add(call.WebCallId + ":" + reason));
            try
            {
                int clearedBackendCallId;
                Assert.True(tracker.TryBegin(
                    "web.clear.1",
                    "clear",
                    out clearedBackendCallId));
                tracker.Clear();

                PanelPendingCall<string> completed;
                Assert.False(tracker.TryComplete(clearedBackendCallId, out completed));
                Assert.Equal(
                    new[] { "web.clear.1:Cleared" },
                    ended.ToArray());

                int disposedBackendCallId;
                Assert.True(tracker.TryBegin(
                    "web.dispose.1",
                    "dispose",
                    out disposedBackendCallId));
                tracker.Dispose();
                tracker.Dispose();

                Assert.False(tracker.TryComplete(disposedBackendCallId, out completed));
                Assert.Equal(
                    new[] { "web.clear.1:Cleared", "web.dispose.1:Cleared" },
                    ended.ToArray());

                int afterDisposeCallId;
                Assert.False(tracker.TryBegin(
                    "web.after-dispose.1",
                    "late",
                    out afterDisposeCallId));
                Assert.Equal(0, afterDisposeCallId);
            }
            finally
            {
                tracker.Dispose();
            }
        }

        private static PanelPendingCallTracker<string> NewTracker(
            int timeoutMs,
            Action<PanelPendingCallEndReason> onEnded)
        {
            return new PanelPendingCallTracker<string>(
                () => true,
                _ => true,
                timeoutMs,
                (_, reason) => onEnded(reason));
        }
    }
}
