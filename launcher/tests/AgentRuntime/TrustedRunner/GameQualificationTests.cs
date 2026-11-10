using System;
using System.IO;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.TrustedRunner;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.TrustedRunner
{
    public sealed class GameQualificationTests
    {
        [Theory]
        [InlineData("cf7_agent_review1110", 10)]
        [InlineData("cf7_agent_i2051110", 80)]
        public void QualificationIsCandidateOnlyAndLifetimeIsSlotBound(string slot, int minutes)
        {
            Assert.True(TrustedRegressionSlots.IsQualification(slot));
            Assert.Equal(TimeSpan.FromMinutes(minutes), TrustedRegressionSlots.MaximumLifetime(slot));
            Assert.Equal(slot, TrustedUnattendedRunnerOptions.Parse(new[] {
                "--agent-unattended-runner", "--adapter", "jsonl", "--slot", slot }).Slot);
            TrustedUnattendedRunnerOptions.ValidateRuntimeBinding(slot, "isolated_candidate",
                @"C:\repo\tmp\runtime-candidates\v2\c-0123456789ab-0123456789-i205");
            Assert.Throws<InvalidDataException>(() =>
                TrustedUnattendedRunnerOptions.ValidateRuntimeBinding(slot, "formal_runtime", @"C:\repo"));
        }

        [Theory]
        [InlineData("cf7_agent_152_a28")]
        [InlineData("cf7_agent_a5_material_shop_run")]
        [InlineData("cf7_agent_i2051110_near")]
        public void OrdinaryAndNearMatchSlotsNeverReceiveLongWindow(string slot)
        {
            Assert.False(TrustedRegressionSlots.IsQualification(slot));
            Assert.Equal(TimeSpan.FromMinutes(10), TrustedRegressionSlots.MaximumLifetime(slot));
        }

        [Theory]
        [InlineData("q205:shift+d+j", true)]
        [InlineData("q205:d+r", true)]
        [InlineData("q205:alt+f4", false)]
        [InlineData("q205:ctrl+a", false)]
        [InlineData("q205:shift+d+j+k", false)]
        [InlineData("q205:j+shift+d", false)]
        [InlineData("q205:escape", false)]
        [InlineData("j", false)]
        public void GesturesAreClosedAndCannotBecomeGeneralKeyboard(string token, bool allowed)
        {
            Assert.Equal(allowed, GameQualificationInput.TryResolve(token, out _));
        }
    }
}
