using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public sealed class ProgramControlPlaneModeTests
    {
        [Fact]
        public void StandardNormalModeSelectsAgentRuntime()
        {
            Assert.False(
                global::Program.IsLegacyHttpAutomationMode(
                    System.Array.Empty<string>()));
        }

        [Fact]
        public void ExplicitLegacyFlagSelectsLegacyHttpAutomation()
        {
            Assert.True(
                global::Program.IsLegacyHttpAutomationMode(
                    new[]
                    {
                        "--legacy-http-automation"
                    }));
        }

        [Fact]
        public void BusOnlySelectsLegacyHttpAutomation()
        {
            Assert.True(
                global::Program.IsLegacyHttpAutomationMode(
                    new[] { "--bus-only" }));
        }

        [Theory]
        [InlineData("--LEGACY-HTTP-AUTOMATION")]
        [InlineData("prefix--legacy-http-automation")]
        [InlineData("--legacy-http-automation=true")]
        public void LegacyFlagRequiresExactToken(string argument)
        {
            Assert.False(
                global::Program.IsLegacyHttpAutomationMode(
                    new[] { argument }));
        }

        [Theory]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State
                .WaitingConnect)]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State
                .WaitingHandshake)]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State
                .PrewarmHandshakeHeld)]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State
                .Embedding)]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State
                .RepairPending)]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State
                .WaitingGameReady)]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State
                .Ready)]
        public void ActiveFlashLifecycleAuthorizesExactXmlSocketPeer(
            CF7Launcher.Guardian.GameLaunchFlow.State state)
        {
            Assert.True(
                global::Program
                    .IsXmlSocketFlashLifecycleAuthorized(
                        state));
        }

        [Theory]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State.Idle)]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State.Spawning)]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State.Error)]
        [InlineData(
            CF7Launcher.Guardian.GameLaunchFlow.State.Resetting)]
        public void InactiveFlashLifecycleRejectsExactXmlSocketPeer(
            CF7Launcher.Guardian.GameLaunchFlow.State state)
        {
            Assert.False(
                global::Program
                    .IsXmlSocketFlashLifecycleAuthorized(
                        state));
        }
    }
}
