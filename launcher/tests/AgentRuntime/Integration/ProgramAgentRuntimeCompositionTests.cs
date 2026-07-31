using System;
using System.IO;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class ProgramAgentRuntimeCompositionTests
    {
        [Fact]
        public void ProductionSurfaceCompositionKeepsOnlyFlashMetadataOnly()
        {
            var launcher = new SessionProcessIdentity(
                101,
                new DateTimeOffset(
                    2026,
                    7,
                    31,
                    0,
                    0,
                    0,
                    TimeSpan.Zero),
                Path.GetFullPath("Launcher.Core.exe"));
            var flash = new SessionProcessIdentity(
                202,
                launcher.StartTimeUtc.AddSeconds(1),
                Path.GetFullPath("Flash.exe"));
            var cache =
                new global::Program.AgentRuntimeSurfaceCache(
                    launcher);
            cache.Update(
                1001,
                2001,
                flash,
                3001,
                4001);
            LauncherAgentRuntimeTargetIds targets =
                LauncherAgentRuntimeTargetIds.Create();

            WindowsSessionSurfaceSpec[] specs =
                cache.CreateSpecs(targets).ToArray();

            Assert.Equal(4, specs.Length);
            WindowsSessionSurfaceSpec flashSpec =
                Assert.Single(
                    specs,
                    value =>
                        value.Kind
                            == SurfaceKind.Flash);
            Assert.Empty(flashSpec.ObservationModes);
            Assert.Empty(flashSpec.InputModes);

            foreach (SurfaceKind kind in new[]
                     {
                         SurfaceKind.Launcher,
                         SurfaceKind.WebOverlay,
                         SurfaceKind.NativeHud
                     })
            {
                WindowsSessionSurfaceSpec spec =
                    Assert.Single(
                        specs,
                        value => value.Kind == kind);
                Assert.Contains(
                    ObservationMode.WindowGraphicsCapture,
                    spec.ObservationModes);
            }
        }

        [Fact]
        public void ProductionCompositionDoesNotAdvertiseWindowActivation()
        {
            LauncherAgentRuntimeTargetIds targets =
                LauncherAgentRuntimeTargetIds.Create();
            var activators =
                global::Program
                    .CreateProductionAgentRuntimeTargetActivators(
                        targets);

            Assert.Empty(activators);
            Assert.False(
                LauncherAgentRuntimeHost
                    .HasProductionActivationProvider(
                        activators,
                        targets));
            Assert.DoesNotContain(
                AgentCapabilitiesV1.ActivateWindow,
                LauncherAgentRuntimeHost
                    .BuildSessionCapabilities(
                        qualified: true,
                        hairEnabled: true,
                        structuredEnabled: true,
                        activationEnabled:
                            LauncherAgentRuntimeHost
                                .HasProductionActivationProvider(
                                    activators,
                                    targets)));
        }
    }
}
