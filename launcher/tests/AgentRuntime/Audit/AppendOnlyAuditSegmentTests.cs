using System;
using System.Linq;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.Tests.AgentRuntime.Security;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Audit
{
    public sealed class AppendOnlyAuditSegmentTests
    {
        [Fact]
        public void Segment_ProducesVerifiableSequenceAndAnchoredReceipt()
        {
            var clock = new ManualAgentRuntimeClock();
            var segment = new AppendOnlyAuditSegment(
                clock,
                "auditseg-test");
            AuditEntry first = segment.Append(
                "credential_issued",
                "{\"principal\":\"opaque\"}");
            clock.Advance(TimeSpan.FromMilliseconds(7));
            AuditEntry second = segment.Append(
                "lease_acquired",
                "{\"lease\":\"opaque\"}");
            AuditSegmentReceipt receipt = segment.SealCompleted(
                "{\"reasonCode\":\"normal_shutdown\"}");

            AuditVerificationResult verified =
                AppendOnlyAuditSegment.Verify(
                    segment.Snapshot(),
                    segment.SegmentId,
                    receipt);

            Assert.True(verified.Valid);
            Assert.Equal(3, verified.VerifiedEntries);
            Assert.Equal(first.EntryHash, second.PreviousHash);
            Assert.Equal(
                AuditSegmentTerminalKind.Completed,
                verified.TerminalKind);
            Assert.Equal(receipt.FinalHash, verified.FinalHash);
        }

        [Fact]
        public void PayloadMutation_IsDetected()
        {
            var segment = new AppendOnlyAuditSegment(
                new ManualAgentRuntimeClock(),
                "auditseg-test");
            segment.Append("action", "{\"outcome\":\"rejected\"}");
            AuditSegmentReceipt receipt =
                segment.SealCompleted("{}");
            AuditEntry[] tampered = segment.Snapshot().ToArray();
            tampered[0] = tampered[0] with
            {
                CanonicalPayload = "{\"outcome\":\"committed\"}"
            };

            AuditVerificationResult result =
                AppendOnlyAuditSegment.Verify(
                    tampered,
                    segment.SegmentId,
                    receipt);

            Assert.False(result.Valid);
            Assert.Equal("payload_hash_mismatch", result.ReasonCode);
        }

        [Fact]
        public void AbnormalClosure_HasExplicitTruncatedTerminalReceipt()
        {
            var segment = new AppendOnlyAuditSegment(
                new ManualAgentRuntimeClock(),
                "auditseg-test");
            segment.Append(
                "input_dispatch_started",
                "{\"actionId\":\"opaque\"}");

            AuditSegmentReceipt receipt = segment.SealTruncated(
                "launcher_crash_recovery");

            Assert.Equal(
                AuditSegmentTerminalKind.Truncated,
                receipt.TerminalKind);
            Assert.Equal(
                AuditSegmentTerminalKind.Truncated,
                segment.Snapshot().Last().TerminalKind);
            Assert.True(AppendOnlyAuditSegment.Verify(
                segment.Snapshot(),
                segment.SegmentId,
                receipt).Valid);
            Assert.Throws<InvalidOperationException>(
                () => segment.Append("late_event", "{}"));
        }

        [Fact]
        public void ReceiptMismatch_CannotPretendTruncatedChainWasContinuous()
        {
            var segment = new AppendOnlyAuditSegment(
                new ManualAgentRuntimeClock(),
                "auditseg-test");
            segment.Append("action", "{}");
            AuditSegmentReceipt actual = segment.SealTruncated(
                "process_terminated");
            var forged = actual with
            {
                TerminalKind = AuditSegmentTerminalKind.Completed
            };

            AuditVerificationResult result =
                AppendOnlyAuditSegment.Verify(
                    segment.Snapshot(),
                    segment.SegmentId,
                    forged);

            Assert.False(result.Valid);
            Assert.Equal("receipt_mismatch", result.ReasonCode);
        }

        [Fact]
        public void ReceiptSealTime_IsBoundToTerminalEntry()
        {
            var segment = new AppendOnlyAuditSegment(
                new ManualAgentRuntimeClock(),
                "auditseg-test");
            AuditSegmentReceipt actual =
                segment.SealCompleted("{}");
            var forged = actual with
            {
                SealedUtc = actual.SealedUtc.AddMilliseconds(1)
            };

            AuditVerificationResult result =
                AppendOnlyAuditSegment.Verify(
                    segment.Snapshot(),
                    segment.SegmentId,
                    forged);

            Assert.False(result.Valid);
            Assert.Equal("receipt_mismatch", result.ReasonCode);
        }

        [Fact]
        public void EventCapacity_AlwaysReservesTerminalReceiptSlot()
        {
            var segment = new AppendOnlyAuditSegment(
                new ManualAgentRuntimeClock(),
                "auditseg-test");
            for (int index = 0;
                index < AppendOnlyAuditSegment.MaximumEntries - 1;
                index++)
            {
                segment.Append("event", "{}");
            }

            InvalidOperationException error =
                Assert.Throws<InvalidOperationException>(
                    () => segment.Append("overflow", "{}"));
            Assert.Equal("audit_segment_needs_seal", error.Message);

            AuditSegmentReceipt receipt =
                segment.SealCompleted("{}");
            Assert.Equal(
                AppendOnlyAuditSegment.MaximumEntries,
                receipt.FinalServerSequence);
        }
    }
}
