using System;
using System.IO;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.Tests.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Gateway
{
    public sealed class MinimalSessionReferenceProviderTests
    {
        [Fact]
        public void LifecycleRefBootstrapsOnlyTheCurrentExactSession()
        {
            string launcherPath = Path.GetFullPath(
                Path.Combine(
                    Path.GetTempPath(),
                    "cf7-agent-tests",
                    "Launcher.Core.exe"));
            var launcher = new SessionProcessIdentity(
                101,
                new DateTimeOffset(
                    2026,
                    7,
                    30,
                    1,
                    2,
                    3,
                    TimeSpan.Zero),
                launcherPath);
            var owner = new SessionRegistryHostOwner(launcher);
            var registry = new SessionSurfaceRegistry(
                owner,
                new RecordingSessionSurfaceHostValidator());
            string firstSessionId =
                "session_bootstrap_first_01";
            registry.RegisterSession(
                owner,
                Registration(
                    launcher,
                    firstSessionId,
                    1));
            var provider =
                new RegistryMinimalSessionReferenceProvider(
                    registry,
                    "lifecycle_salt_bootstrap_01");

            MinimalSessionReference minimal =
                provider.GetMinimalReference();
            Assert.True(
                provider.TryResolveLifecycleReference(
                    minimal.LifecycleRef,
                    out string resolvedSessionId,
                    out ulong resolvedGeneration));
            Assert.Equal(firstSessionId, resolvedSessionId);
            Assert.Equal(1UL, resolvedGeneration);
            Assert.False(
                provider.TryResolveLifecycleReference(
                    "lifecycle_ref_not_current_01",
                    out _,
                    out _));

            string replacementSessionId =
                "session_bootstrap_second_1";
            registry.ReplaceLifecycle(
                owner,
                new SessionMutationExpectation
                {
                    SessionId = firstSessionId,
                    LifecycleGeneration = 1
                },
                Registration(
                    launcher,
                    replacementSessionId,
                    2));

            Assert.False(
                provider.TryResolveLifecycleReference(
                    minimal.LifecycleRef,
                    out _,
                    out _));
            MinimalSessionReference replacement =
                provider.GetMinimalReference();
            Assert.True(
                provider.TryResolveLifecycleReference(
                    replacement.LifecycleRef,
                    out resolvedSessionId,
                    out resolvedGeneration));
            Assert.Equal(
                replacementSessionId,
                resolvedSessionId);
            Assert.Equal(2UL, resolvedGeneration);
        }

        [Fact]
        public void MultipleRegisteredSessionsFailClosedWithoutChoosingOne()
        {
            string launcherPath = Path.GetFullPath(
                Path.Combine(
                    Path.GetTempPath(),
                    "cf7-agent-tests",
                    "Launcher.Core.exe"));
            var launcher = new SessionProcessIdentity(
                101,
                new DateTimeOffset(
                    2026,
                    7,
                    30,
                    1,
                    2,
                    3,
                    TimeSpan.Zero),
                launcherPath);
            var owner = new SessionRegistryHostOwner(launcher);
            var registry = new SessionSurfaceRegistry(
                owner,
                new RecordingSessionSurfaceHostValidator());
            registry.RegisterSession(
                owner,
                Registration(
                    launcher,
                    "session_bootstrap_first_01",
                    1));
            registry.RegisterSession(
                owner,
                Registration(
                    launcher,
                    "session_bootstrap_second_1",
                    1));
            var provider =
                new RegistryMinimalSessionReferenceProvider(
                    registry,
                    "lifecycle_salt_bootstrap_01");

            MinimalSessionReference minimal =
                provider.GetMinimalReference();

            Assert.False(minimal.ProjectRunning);
            Assert.Null(minimal.LifecycleRef);
            Assert.False(
                provider.TryResolveLifecycleReference(
                    "lifecycle_ref_not_current_01",
                    out _,
                    out _));
        }

        private static SessionHostRegistration Registration(
            SessionProcessIdentity launcher,
            string sessionId,
            ulong lifecycleGeneration)
        {
            return new SessionHostRegistration
            {
                SessionId = sessionId,
                LifecycleGeneration = lifecycleGeneration,
                SessionMode =
                    SessionMode.DeveloperInteractive,
                Slot = "launcher_idle",
                LauncherProcess = launcher,
                CoreSha256 = new string('a', 64),
                RuntimeQualification =
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode =
                            RuntimeMode.FormalRuntime,
                        BuildIdentity =
                            new string('b', 64),
                        PayloadClosure =
                            new string('c', 64),
                        ActualProcessPath =
                            launcher.ExecutablePath
                    },
                Capabilities =
                    new[] { AgentCapabilitiesV1.SessionStatus }
            };
        }
    }
}
