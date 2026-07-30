using System;
using System.IO;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.Tests.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class AgentHairDomainTargetAuthorityTests
    {
        [Theory]
        [InlineData(SurfaceKind.Launcher)]
        [InlineData(SurfaceKind.Flash)]
        [InlineData(SurfaceKind.NativeHud)]
        [InlineData(SurfaceKind.WingsShell)]
        public void NonWebTargetsAreNeverHairDomainTargets(
            SurfaceKind kind)
        {
            using var setup = new Setup();
            string targetId = Id(kind.ToString());
            setup.Add(
                targetId,
                kind,
                InputMode.DomainTransaction);

            Assert.False(
                setup.Authority.TryAuthorize(
                    setup.Controller.SessionId,
                    targetId,
                    out string reasonCode));
            Assert.Equal("unsupported_for_surface", reasonCode);
        }

        [Fact]
        public void OnlyUniqueDomainTransactionWebOverlayIsAccepted()
        {
            using var setup = new Setup();
            string targetId = Id("web");
            setup.Add(
                targetId,
                SurfaceKind.WebOverlay,
                InputMode.DomainTransaction);

            Assert.True(
                setup.Authority.TryAuthorize(
                    setup.Controller.SessionId,
                    targetId,
                    out string reasonCode));
            Assert.Null(reasonCode);

            string second = Id("web_second");
            setup.Add(
                second,
                SurfaceKind.WebOverlay,
                InputMode.DomainTransaction);
            Assert.False(
                setup.Authority.TryAuthorize(
                    setup.Controller.SessionId,
                    targetId,
                    out reasonCode));
            Assert.Equal("unsupported_for_surface", reasonCode);
        }

        [Fact]
        public void WebOverlayWithoutDomainTransactionModeIsRejected()
        {
            using var setup = new Setup();
            string targetId = Id("web");
            setup.Add(
                targetId,
                SurfaceKind.WebOverlay,
                InputMode.Cdp);

            Assert.False(
                setup.Authority.TryAuthorize(
                    setup.Controller.SessionId,
                    targetId,
                    out string reasonCode));
            Assert.Equal("unsupported_for_surface", reasonCode);
        }

        private static string Id(string prefix)
        {
            return prefix + "_0123456789abcdefghijklmnop";
        }

        private sealed class Setup : IDisposable
        {
            private readonly SessionRegistryHostOwner _owner;
            private readonly SessionProcessIdentity _launcher;
            private readonly SessionProcessIdentity _flash;
            private long _nextWindowHandle = 2000;

            internal Setup()
            {
                _launcher = new SessionProcessIdentity(
                    Environment.ProcessId,
                    DateTimeOffset.UtcNow,
                    Path.GetFullPath("Launcher.Tests.exe"));
                _owner = new SessionRegistryHostOwner(_launcher);
                _flash = new SessionProcessIdentity(
                    Environment.ProcessId + 1,
                    DateTimeOffset.UtcNow,
                    Path.GetFullPath("FlashPlayer.exe"));
                Registry = new SessionSurfaceRegistry(
                    _owner,
                    new RecordingSessionSurfaceHostValidator());
                Controller = new SessionSurfaceHostController(
                    Registry,
                    _owner,
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode = RuntimeMode.FormalRuntime,
                        BuildIdentity = new string('a', 64),
                        PayloadClosure = new string('b', 64),
                        ActualProcessPath =
                            _launcher.ExecutablePath
                    },
                    new string('c', 64),
                    new[]
                    {
                        AgentCapabilitiesV1.AppearanceHairChange
                    });
                Authority =
                    new RegistryAgentHairDomainTargetAuthority(
                        Registry);
                Controller.SetAttempt(
                    Id("attempt"),
                    _flash,
                    "agent_test_slot",
                    1);
            }

            internal SessionSurfaceRegistry Registry { get; }
            internal SessionSurfaceHostController Controller
            {
                get;
            }
            internal RegistryAgentHairDomainTargetAuthority Authority
            {
                get;
            }

            internal void Add(
                string targetId,
                SurfaceKind kind,
                InputMode inputMode)
            {
                long handle = ++_nextWindowHandle;
                bool flash = kind == SurfaceKind.Flash;
                Controller.SynchronizeSurface(
                    new SessionSurfaceHostRegistration
                    {
                        TargetId = targetId,
                        Kind = kind,
                        SafetyKind =
                            AgentTargetSafetyKind.RuntimeOwned,
                        OwnerRelation =
                            flash
                                ? SessionSurfaceOwnerRelation
                                    .FlashTopLevel
                                : SessionSurfaceOwnerRelation
                                    .RuntimeOverlay,
                        OwnerProcess =
                            flash ? _flash : _launcher,
                        WindowHandle = handle,
                        BoundsPhysical = Rect(),
                        ClientRectPhysical = Rect(),
                        ContentRectPhysical = Rect(),
                        Dpi = 96,
                        Visible = true,
                        ObservationModes = new[]
                        {
                            ObservationMode
                                .WindowGraphicsCapture
                        },
                        InputModes = new[] { inputMode }
                    });
            }

            public void Dispose()
            {
            }

            private static SessionPhysicalRect Rect()
            {
                return new SessionPhysicalRect(
                    0,
                    0,
                    800,
                    600);
            }
        }
    }
}
