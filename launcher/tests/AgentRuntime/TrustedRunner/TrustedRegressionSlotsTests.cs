using System;
using System.IO;
using CF7Launcher.AgentRuntime.TrustedRunner;
using CF7Launcher.AgentRuntime.Integration;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.TrustedRunner
{
    public sealed class TrustedRegressionSlotsTests
    {
        [Theory]
        [InlineData("cf7_agent_152_a28")]
        [InlineData("cf7_agent_152_b29")]
        [InlineData("cf7_agent_152_c68")]
        [InlineData("cf7_agent_152_d69")]
        [InlineData("cf7_agent_152_e69")]
        public void RegressionEntryIsCandidateOnlyAndWaitsForRealRuntime(string slot)
        {
            Assert.Equal(slot, TrustedUnattendedRunnerOptions.Parse(new[] {
                "--agent-unattended-runner", "--adapter", "jsonl", "--slot", slot }).Slot);
            TrustedUnattendedRunnerOptions.ValidateRuntimeBinding(slot, "isolated_candidate",
                @"C:\repo\tmp\runtime-candidates\v2\c-0123456789ab-0123456789-i152");
            foreach (var mode in new[] { "formal_runtime", "unqualified_dev" })
                Assert.Throws<InvalidDataException>(() => TrustedUnattendedRunnerOptions.ValidateRuntimeBinding(slot, mode, @"C:\repo"));
            Assert.Throws<InvalidDataException>(() => TrustedUnattendedRunnerOptions.ValidateRuntimeBinding(slot, "isolated_candidate", @"C:\repo\tmp\runtime-candidates\v2\a5"));
            Assert.Equal(TimeSpan.FromSeconds(60), TrustedUnattendedBootstrapLease.CredentialAcquisitionPolicyMaximumForSlot(slot));
            bool ready = false; int sends = 0;
            var gate = new TrustedUnattendedGameEntryGate(
                () => new TrustedUnattendedGameEntrySnapshot("Ready", slot, "attempt", "attempt"),
                (observedSlot, attempt) => ready && observedSlot == slot && attempt == "attempt",
                attempt => { sends++; return true; });
            Assert.False(gate.TryAllowCredential(slot, "attempt"));
            Assert.False(gate.TryAllowCredential(slot, "attempt"));
            Assert.Equal(1, sends);
            ready = true;
            Assert.True(gate.TryAllowCredential(slot, "attempt"));
            Assert.False(gate.TryAllowCredential(slot, "stale"));
        }

        [Theory]
        [InlineData("crazyflasher7_saves")]
        [InlineData("cf7_agent_152_a28_near")]
        [InlineData("CF7_AGENT_152_A28")]
        [InlineData("cf7_agent_other")]
        public void ProfileDoesNotAuthorizeOtherSlots(string slot)
        {
            Assert.False(TrustedRegressionSlots.Contains(slot));
            Assert.Throws<InvalidDataException>(() => TrustedUnattendedRunnerOptions.Parse(new[] {
                "--agent-unattended-runner", "--adapter", "jsonl", "--slot", slot }));
        }
    }
}
