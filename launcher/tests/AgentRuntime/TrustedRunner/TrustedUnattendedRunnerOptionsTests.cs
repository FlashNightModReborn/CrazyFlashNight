using System;
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

        [Fact]
        public void AcceptsExactA5MaterialShopSlot()
        {
            TrustedUnattendedRunnerOptions options =
                TrustedUnattendedRunnerOptions.Parse(
                    new[]
                    {
                        "--agent-unattended-runner",
                        "--adapter",
                        "mcp",
                        "--slot",
                        "cf7_agent_a5_material_shop_run"
                    });

            Assert.Equal(
                TrustedUnattendedAdapter.Mcp,
                options.Adapter);
            Assert.Equal(
                "cf7_agent_a5_material_shop_run",
                options.Slot);
        }

        [Theory]
        [InlineData("cf7_agent_equipment_tuning", 30)]
        [InlineData("cf7_agent_arena_calibration", 30)]
        [InlineData("cf7_agent_character_build", 30)]
        [InlineData("cf7_agent_loot_target_full_v1", 30)]
        [InlineData("cf7_agent_a5_material_shop_run", 60)]
        [InlineData("CF7_AGENT_A5_MATERIAL_SHOP_RUN", 30)]
        public void CredentialAcquisitionBudgetIsExactPerSlot(
            string slot,
            int expectedSeconds)
        {
            Assert.Equal(
                TimeSpan.FromSeconds(expectedSeconds),
                TrustedUnattendedBootstrapLease
                    .CredentialAcquisitionPolicyMaximumForSlot(slot));
        }

        [Theory]
        [InlineData(
            "cf7_agent_a5_material_shop_run",
            "isolated_candidate",
            @"C:\repo\tmp\runtime-candidates\v2\a5",
            true)]
        [InlineData(
            "cf7_agent_a5_material_shop_run",
            "formal_runtime",
            @"C:\repo",
            true)]
        [InlineData(
            "cf7_agent_a5_material_shop_run",
            "unqualified_dev",
            @"C:\repo",
            false)]
        [InlineData(
            "cf7_agent_a5_material_shop_run",
            "isolated_candidate",
            @"C:\repo\tmp\runtime-candidates\v2\c-ordinary",
            false)]
        [InlineData(
            "cf7_agent_a5_material_shop_run",
            "isolated_candidate",
            @"C:\repo\tmp\runtime-candidates\v2\a4",
            false)]
        [InlineData(
            "cf7_agent_a5_material_shop_run",
            "isolated_candidate",
            @"C:\repo\tmp\runtime-candidates\v2\A5",
            false)]
        [InlineData(
            "cf7_agent_equipment_tuning",
            "isolated_candidate",
            @"C:\repo\tmp\runtime-candidates\v2\a5",
            false)]
        [InlineData(
            "cf7_agent_equipment_tuning",
            "isolated_candidate",
            @"C:\repo\tmp\runtime-candidates\v2\A5",
            false)]
        [InlineData(
            "cf7_agent_equipment_tuning",
            "isolated_candidate",
            @"C:\repo\tmp\runtime-candidates\v2\a5-near",
            false)]
        [InlineData(
            "cf7_agent_equipment_tuning",
            "isolated_candidate",
            @"C:\repo\tmp\runtime-candidates\v2\c-ordinary",
            false)]
        [InlineData(
            "cf7_agent_equipment_tuning",
            "isolated_candidate",
            @"C:\repo\tmp\runtime-candidates\v2\c-32ed30866355-5d18a14d6c-20260730t154609961z-39b299d9",
            true)]
        [InlineData(
            "cf7_agent_equipment_tuning",
            "formal_runtime",
            @"C:\repo",
            true)]
        public void EnforcesExactA5SlotRuntimeBinding(
            string slot,
            string runtimeMode,
            string deploymentRoot,
            bool accepted)
        {
            if (accepted)
            {
                TrustedUnattendedRunnerOptions
                    .ValidateRuntimeBinding(
                        slot,
                        runtimeMode,
                        deploymentRoot);
                return;
            }

            Assert.Throws<InvalidDataException>(
                () => TrustedUnattendedRunnerOptions
                    .ValidateRuntimeBinding(
                        slot,
                        runtimeMode,
                        deploymentRoot));
        }

        [Theory]
        [InlineData("evil")]
        [InlineData("cf7_agent_arbitrary")]
        [InlineData("cf7_agent_equipment_tuning.json")]
        [InlineData("cf7_agent_a5_material_shop_seed")]
        [InlineData("cf7_agent_a5_material_shop_recovery")]
        [InlineData("CF7_AGENT_A5_MATERIAL_SHOP_RUN")]
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
