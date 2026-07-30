using System;
using System.IO;
using System.Linq;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.Tests.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Integration
{
    public sealed class
        LauncherAgentDeveloperEnrollmentPresenterTests
    {
        [Fact]
        public void SelectionFreezesExactBoundedScope()
        {
            var selection =
                new LauncherAgentDeveloperEnrollmentSelection(
                    Id("client"),
                    new[]
                    {
                        AgentCapabilitiesV1.SessionStatus,
                        AgentCapabilitiesV1.SessionStatus,
                        "observe:"
                            + ObservationDataScopesV1
                                .WindowMetadata
                    },
                    new[]
                    {
                        Id("web"),
                        Id("web")
                    },
                    TimeSpan.FromHours(1));

            Assert.Equal(Id("client"), selection.ClientInstanceId);
            Assert.Equal(2, selection.AllowedCapabilities.Count);
            Assert.Single(selection.AllowedTargets);
            Assert.Equal(TimeSpan.FromHours(1), selection.Lifetime);
        }

        [Fact]
        public void SelectionRejectsInvalidClientAndOverlongLifetime()
        {
            Assert.Throws<ArgumentException>(
                () =>
                    new LauncherAgentDeveloperEnrollmentSelection(
                        "not opaque",
                        new[]
                        {
                            AgentCapabilitiesV1.SessionStatus
                        },
                        new[] { Id("web") },
                        TimeSpan.FromHours(1)));
            Assert.Throws<ArgumentOutOfRangeException>(
                () =>
                    new LauncherAgentDeveloperEnrollmentSelection(
                        Id("client"),
                        new[]
                        {
                            AgentCapabilitiesV1.SessionStatus
                        },
                        new[] { Id("web") },
                        TimeSpan.FromHours(8)
                            + TimeSpan.FromTicks(1)));
        }

        [Fact]
        public void SelectionRejectsMoreThanGlobalTargetCap()
        {
            string[] targets = Enumerable.Range(
                    0,
                    AgentProtocolV1.MaximumTargetScopeItems
                        + 1)
                .Select(index => Id("target" + index))
                .ToArray();

            Assert.Throws<ArgumentException>(
                () =>
                    new LauncherAgentDeveloperEnrollmentSelection(
                        Id("client"),
                        new[]
                        {
                            AgentCapabilitiesV1.SessionStatus
                        },
                        targets,
                        TimeSpan.FromHours(1)));
        }

        [Fact]
        public void PresentationRequestRequiresCurrentExactTargets()
        {
            Assert.Throws<ArgumentException>(
                () =>
                    new LauncherAgentDeveloperEnrollmentPresentationRequest(
                        new[]
                        {
                            AgentCapabilitiesV1.SessionStatus
                        },
                        Array.Empty<
                            LauncherAgentEnrollmentTargetOption>()));

            var request =
                new LauncherAgentDeveloperEnrollmentPresentationRequest(
                    new[]
                    {
                        AgentCapabilitiesV1.SessionStatus
                    },
                    new[]
                    {
                        new LauncherAgentEnrollmentTargetOption(
                            Id("web"),
                            SurfaceKind.WebOverlay,
                            "Web 面板"),
                        new LauncherAgentEnrollmentTargetOption(
                            Id("web"),
                            SurfaceKind.WebOverlay,
                            "重复项")
                    });

            Assert.Single(request.Targets);
        }

        [Fact]
        public void HumanCloseRemovesSecuritySurfaceAndAcknowledgesExactSession()
        {
            RunSta(() =>
            {
                using var ownerForm = new Form
                {
                    ShowInTaskbar = false
                };
                ownerForm.Show();
                _ = ownerForm.Handle;
                var launcher = new SessionProcessIdentity(
                    Environment.ProcessId,
                    DateTimeOffset.UtcNow,
                    Path.GetFullPath(
                        Environment.ProcessPath
                        ?? "Launcher.Tests.exe"));
                var registryOwner =
                    new SessionRegistryHostOwner(launcher);
                var registry = new SessionSurfaceRegistry(
                    registryOwner,
                    new RecordingSessionSurfaceHostValidator());
                var controller =
                    new SessionSurfaceHostController(
                        registry,
                        registryOwner,
                        new RuntimeQualificationRegistration
                        {
                            RuntimeMode =
                                RuntimeMode.FormalRuntime,
                            BuildIdentity = new string('a', 64),
                            PayloadClosure = new string('b', 64),
                            ActualProcessPath =
                                launcher.ExecutablePath
                        },
                        new string('c', 64),
                        new[]
                        {
                            AgentCapabilitiesV1.SessionStatus
                        });
                var presenter =
                    new LauncherAgentDeveloperEnrollmentPresenter(
                        ownerForm,
                        controller,
                        registryOwner,
                        (dialog, dialogOwner) =>
                        {
                            Assert.True(
                                controller.Snapshot
                                    .HumanReauthorizationRequired);
                            Assert.Equal(
                                BlockingModalKind
                                    .HumanOnlySecurity,
                                controller.Snapshot
                                    .BlockingModalKind);
                            return DialogResult.Cancel;
                        });
                var request =
                    new LauncherAgentDeveloperEnrollmentPresentationRequest(
                        new[]
                        {
                            AgentCapabilitiesV1.SessionStatus
                        },
                        new[]
                        {
                            new LauncherAgentEnrollmentTargetOption(
                                Id("web"),
                                SurfaceKind.WebOverlay,
                                "Web 面板")
                        });

                Assert.Null(presenter.Present(request));
                Assert.Equal(
                    BlockingModalKind.None,
                    controller.Snapshot.BlockingModalKind);
                Assert.False(
                    controller.Snapshot
                        .HumanReauthorizationRequired);
                Assert.DoesNotContain(
                    controller.Snapshot.Surfaces,
                    surface => surface.SafetyKind
                        == AgentTargetSafetyKind
                            .HumanOnlySecuritySurface);
                ownerForm.Close();
                Application.DoEvents();
            });
        }

        private static void RunSta(Action action)
        {
            Exception failure = null;
            var thread = new Thread(() =>
            {
                try
                {
                    action();
                }
                catch (Exception exception)
                {
                    failure = exception;
                }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            if (!thread.Join(TimeSpan.FromSeconds(20)))
            {
                throw new TimeoutException(
                    "Developer enrollment STA test timed out.");
            }
            if (failure != null)
                ExceptionDispatchInfo.Capture(failure).Throw();
        }

        private static string Id(string prefix)
        {
            return (prefix
                + "_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
                .Substring(0, 32);
        }
    }
}
