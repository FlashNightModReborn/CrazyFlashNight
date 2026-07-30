using System.IO;
using CF7Launcher.AgentRuntime.TrustedRunner;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.TrustedRunner
{
    public sealed class TrustedUnattendedRunnerOptionsTests
    {
        [Theory]
        [InlineData(
            "jsonl",
            "Jsonl")]
        [InlineData(
            "mcp",
            "Mcp")]
        public void AcceptsOnlyFrozenAdapterAndSlot(
            string adapter,
            string expected)
        {
            TrustedUnattendedRunnerOptions options =
                TrustedUnattendedRunnerOptions.Parse(
                    new[]
                    {
                        "--agent-unattended-runner",
                        "--adapter",
                        adapter,
                        "--slot",
                        "cf7_agent_equipment_tuning"
                    });

            Assert.Equal(
                expected,
                options.Adapter.ToString());
            Assert.Equal(
                "cf7_agent_equipment_tuning",
                options.Slot);
        }

        [Theory]
        [InlineData("evil")]
        [InlineData("cf7_agent_arbitrary")]
        [InlineData("cf7_agent_equipment_tuning.json")]
        public void RejectsUnfrozenSlot(string slot)
        {
            Assert.Throws<InvalidDataException>(
                () => TrustedUnattendedRunnerOptions
                    .Parse(
                        new[]
                        {
                            "--agent-unattended-runner",
                            "--adapter",
                            "jsonl",
                            "--slot",
                            slot
                        }));
        }

        [Fact]
        public void RejectsAdditionalArguments()
        {
            Assert.Throws<InvalidDataException>(
                () => TrustedUnattendedRunnerOptions
                    .Parse(
                        new[]
                        {
                            "--agent-unattended-runner",
                            "--adapter",
                            "jsonl",
                            "--slot",
                            "cf7_agent_equipment_tuning",
                            "--project-root",
                            @"C:\attacker"
                        }));
        }
    }
}
