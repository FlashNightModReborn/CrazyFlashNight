using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Integration;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class TrustedUnattendedGameEntryGateTests
    {
        private const string A5 =
            TrustedUnattendedGameEntryGate.ExactA5Slot;

        [Fact]
        public void ForeignSlotAlwaysPassesWithoutTouchingEntryDependencies()
        {
            var gate = new TrustedUnattendedGameEntryGate(
                delegate
                {
                    throw new InvalidOperationException(
                        "snapshot must remain untouched");
                },
                delegate
                {
                    throw new InvalidOperationException(
                        "readiness must remain untouched");
                },
                delegate(string attemptId)
                {
                    throw new InvalidOperationException(
                        "sender must remain untouched");
                });

            Assert.True(gate.TryAllowCredential(
                "cf7_agent_other_workflow",
                null));
            Assert.True(gate.TryAllowCredential(null, null));
        }

        [Theory]
        [InlineData("WaitingGameReady", A5, "attempt-a", "attempt-a")]
        [InlineData("Ready", "cf7_agent_a5_material_shop_run_near", "attempt-a", "attempt-a")]
        [InlineData("Ready", A5, "attempt-stale", "attempt-stale")]
        [InlineData("Ready", A5, "attempt-a", null)]
        [InlineData("Ready", A5, "attempt-a", "attempt-stale")]
        public void A5RequiresOneExactReadyTrueTitleSnapshot(
            string state,
            string snapshotSlot,
            string snapshotAttempt,
            string titleAttempt)
        {
            int sendCount = 0;
            var snapshot = new TrustedUnattendedGameEntrySnapshot(
                state,
                snapshotSlot,
                snapshotAttempt,
                titleAttempt);
            var gate = Gate(
                () => snapshot,
                delegate { return false; },
                delegate(string attemptId)
                {
                    sendCount++;
                    return true;
                });

            Assert.False(gate.TryAllowCredential(A5, "attempt-a"));
            Assert.Equal(0, sendCount);
        }

        [Fact]
        public void SuccessfulSendIsOneShotUntilExactAgentControlReady()
        {
            const string attempt = "attempt-a";
            bool ready = false;
            int sendCount = 0;
            var readinessCalls = new List<(string Slot, string Attempt)>();
            var gate = Gate(
                () => Ready(attempt),
                delegate(string slot, string currentAttempt)
                {
                    readinessCalls.Add((slot, currentAttempt));
                    return ready
                        && slot == A5
                        && currentAttempt == attempt;
                },
                delegate(string sentAttempt)
                {
                    Assert.Equal(attempt, sentAttempt);
                    sendCount++;
                    return true;
                });

            Assert.False(gate.TryAllowCredential(A5, attempt));
            Assert.False(gate.TryAllowCredential(A5, attempt));
            Assert.Equal(1, sendCount);

            ready = true;
            Assert.True(gate.TryAllowCredential(A5, attempt));
            Assert.Equal(1, sendCount);
            Assert.All(
                readinessCalls,
                call =>
                {
                    Assert.Equal(A5, call.Slot);
                    Assert.Equal(attempt, call.Attempt);
                });
        }

        [Fact]
        public void FalseOrThrowingSenderDoesNotConsumeAttempt()
        {
            int sendCount = 0;
            bool ready = false;
            var gate = Gate(
                () => Ready("attempt-retry"),
                delegate { return ready; },
                delegate(string sentAttempt)
                {
                    Assert.Equal("attempt-retry", sentAttempt);
                    sendCount++;
                    if (sendCount == 1) return false;
                    if (sendCount == 2)
                        throw new InvalidOperationException("fixture");
                    return true;
                });

            Assert.False(gate.TryAllowCredential(
                A5,
                "attempt-retry"));
            Assert.False(gate.TryAllowCredential(
                A5,
                "attempt-retry"));
            Assert.False(gate.TryAllowCredential(
                A5,
                "attempt-retry"));
            Assert.False(gate.TryAllowCredential(
                A5,
                "attempt-retry"));
            Assert.Equal(3, sendCount);

            ready = true;
            Assert.True(gate.TryAllowCredential(
                A5,
                "attempt-retry"));
            Assert.Equal(3, sendCount);
        }

        [Fact]
        public void NewExactAttemptMaySendAgainButStaleReadinessCannotPass()
        {
            string attempt = "attempt-one";
            string readyAttempt = null;
            int sendCount = 0;
            var gate = Gate(
                () => Ready(attempt),
                delegate(string slot, string candidate)
                {
                    return slot == A5
                        && candidate == readyAttempt;
                },
                delegate(string sentAttempt)
                {
                    Assert.Equal(attempt, sentAttempt);
                    sendCount++;
                    return true;
                });

            Assert.False(gate.TryAllowCredential(A5, attempt));
            Assert.Equal(1, sendCount);

            readyAttempt = "attempt-one";
            attempt = "attempt-two";
            Assert.False(gate.TryAllowCredential(A5, attempt));
            Assert.Equal(2, sendCount);

            readyAttempt = "attempt-two";
            Assert.True(gate.TryAllowCredential(A5, attempt));
            Assert.Equal(2, sendCount);
        }

        [Fact]
        public async Task ConcurrentA5ChecksCanInvokeOnlyOneFixedSender()
        {
            const string attempt = "attempt-concurrent";
            int sendCount = 0;
            using var senderEntered = new ManualResetEventSlim(false);
            using var releaseSender = new ManualResetEventSlim(false);
            var gate = Gate(
                () => Ready(attempt),
                delegate { return false; },
                delegate(string sentAttempt)
                {
                    Assert.Equal(attempt, sentAttempt);
                    Interlocked.Increment(ref sendCount);
                    senderEntered.Set();
                    releaseSender.Wait(TimeSpan.FromSeconds(5));
                    return true;
                });

            Task<bool> first = Task.Run(
                () => gate.TryAllowCredential(A5, attempt));
            Assert.True(senderEntered.Wait(TimeSpan.FromSeconds(5)));

            Task<bool>[] concurrent = Enumerable.Range(0, 16)
                .Select(_ => Task.Run(
                    () => gate.TryAllowCredential(A5, attempt)))
                .ToArray();
            bool[] concurrentResults = await Task.WhenAll(concurrent);

            Assert.All(
                concurrentResults,
                value => Assert.False(value));
            Assert.Equal(1, Volatile.Read(ref sendCount));

            releaseSender.Set();
            Assert.False(await first);
            Assert.Equal(1, Volatile.Read(ref sendCount));
            Assert.False(gate.TryAllowCredential(A5, attempt));
            Assert.Equal(1, Volatile.Read(ref sendCount));
        }

        private static TrustedUnattendedGameEntryGate Gate(
            Func<TrustedUnattendedGameEntrySnapshot> snapshot,
            Func<string, string, bool> ready,
            Func<string, bool> sender)
        {
            return new TrustedUnattendedGameEntryGate(
                snapshot,
                ready,
                sender);
        }

        private static TrustedUnattendedGameEntrySnapshot Ready(
            string attempt)
        {
            return new TrustedUnattendedGameEntrySnapshot(
                "Ready",
                A5,
                attempt,
                attempt);
        }
    }
}
