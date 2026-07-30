using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Sessions
{
    public sealed class SessionSurfaceHostValidatorTests
    {
        [Fact]
        public void SessionValidationRequiresExactProcessAndDirectParent()
        {
            SessionProcessIdentity launcher =
                ProcessIdentity(101, "Launcher.Core.exe");
            SessionProcessIdentity flash =
                ProcessIdentity(202, "Flash.exe");
            var processProbe = new FakeProcessProbe();
            processProbe.Exact.Add(launcher.ProcessId);
            processProbe.Exact.Add(flash.ProcessId);
            processProbe.ParentByChild[flash.ProcessId] =
                launcher.ProcessId;
            var validator = new WindowsSessionSurfaceHostValidator(
                processProbe,
                new FakeWindowProbe());
            var owner = new SessionRegistryHostOwner(launcher);

            Assert.True(validator.ValidateSession(
                owner,
                Registration(launcher, flash),
                out _));

            processProbe.ParentByChild[flash.ProcessId] = 999;
            Assert.False(validator.ValidateSession(
                owner,
                Registration(launcher, flash),
                out string reason));
            Assert.Equal("flash_parent_process_mismatch", reason);
        }

        [Fact]
        public void SurfaceValidationUsesObservedHwndOwnerAndOwnedWindowChain()
        {
            SessionProcessIdentity launcher =
                ProcessIdentity(101, "Launcher.Core.exe");
            var processProbe = new FakeProcessProbe();
            processProbe.Exact.Add(launcher.ProcessId);
            var windowProbe = new FakeWindowProbe();
            windowProbe.ProcessByWindow[1001] = launcher.ProcessId;
            windowProbe.ProcessByWindow[1002] = launcher.ProcessId;
            windowProbe.OwnerByWindow[1002] = 1001;
            var validator = new WindowsSessionSurfaceHostValidator(
                processProbe,
                windowProbe);
            var owner = new SessionRegistryHostOwner(launcher);
            SessionSurfaceSnapshot parent =
                Snapshot(launcher, "target_parent_aaaaaaaaa", 1001);
            var context = new SessionSurfaceValidationContext(
                launcher,
                null,
                target => target == parent.TargetId ? parent : null);
            SessionSurfaceHostRegistration child =
                Surface(
                    launcher,
                    "target_child_aaaaaaaaaa",
                    1002,
                    SessionSurfaceOwnerRelation.LauncherOwned,
                    parent.TargetId,
                    1001);

            Assert.True(validator.ValidateSurface(
                owner,
                context,
                child,
                out _));

            windowProbe.OwnerByWindow[1002] = 7777;
            Assert.False(validator.ValidateSurface(
                owner,
                context,
                child,
                out string ownerReason));
            Assert.Equal(
                "surface_window_owner_relation_mismatch",
                ownerReason);

            windowProbe.OwnerByWindow[1002] = 1001;
            windowProbe.ProcessByWindow[1002] = 303;
            Assert.False(validator.ValidateSurface(
                owner,
                context,
                child,
                out string processReason));
            Assert.Equal(
                "surface_hwnd_owner_mismatch",
                processReason);
        }

        private static SessionHostRegistration Registration(
            SessionProcessIdentity launcher,
            SessionProcessIdentity flash)
        {
            return new SessionHostRegistration
            {
                SessionId = "session_aaaaaaaaaaaaaaaaa",
                LifecycleGeneration = 1,
                SessionMode = SessionMode.DeveloperInteractive,
                Slot = "developer",
                AttemptId = "attempt_aaaaaaaaaaaaaaaaa",
                AttemptGeneration = 1,
                LauncherProcess = launcher,
                FlashProcess = flash,
                CoreSha256 = new string('A', 64),
                RuntimeQualification =
                    new RuntimeQualificationRegistration
                    {
                        RuntimeMode = RuntimeMode.FormalRuntime,
                        BuildIdentity = new string('B', 64),
                        PayloadClosure = new string('C', 64),
                        ActualProcessPath = launcher.ExecutablePath
                    },
                Capabilities = Array.Empty<string>()
            };
        }

        private static SessionSurfaceHostRegistration Surface(
            SessionProcessIdentity process,
            string targetId,
            long windowHandle,
            SessionSurfaceOwnerRelation relation,
            string ownerTargetId,
            long ownerWindowHandle)
        {
            var rect = new SessionPhysicalRect(0, 0, 800, 600);
            return new SessionSurfaceHostRegistration
            {
                TargetId = targetId,
                Kind = SurfaceKind.BusinessModal,
                SafetyKind = AgentTargetSafetyKind.RuntimeOwned,
                OwnerRelation = relation,
                OwnerProcess = process,
                WindowHandle = windowHandle,
                OwnerTargetId = ownerTargetId,
                OwnerWindowHandle = ownerWindowHandle,
                BoundsPhysical = rect,
                ClientRectPhysical = rect,
                ContentRectPhysical = rect,
                Dpi = 96,
                Visible = true,
                ObservationModes = new[]
                {
                    ObservationMode.WindowGraphicsCapture
                },
                InputModes = new[]
                {
                    InputMode.SendInputGuarded
                }
            };
        }

        private static SessionSurfaceSnapshot Snapshot(
            SessionProcessIdentity process,
            string targetId,
            long windowHandle)
        {
            var rect = new SessionPhysicalRect(0, 0, 800, 600);
            return new SessionSurfaceSnapshot(
                targetId,
                SurfaceKind.Launcher,
                AgentTargetSafetyKind.RuntimeOwned,
                SessionSurfaceOwnerRelation.LauncherTopLevel,
                process,
                windowHandle,
                null,
                0,
                1,
                1,
                1,
                1,
                null,
                null,
                rect,
                rect,
                rect,
                96,
                0,
                true,
                false,
                true,
                new[] { ObservationMode.WindowGraphicsCapture },
                new[] { InputMode.SendInputGuarded });
        }

        private static SessionProcessIdentity ProcessIdentity(
            int processId,
            string name)
        {
            return new SessionProcessIdentity(
                processId,
                new DateTimeOffset(
                    2026,
                    7,
                    30,
                    0,
                    0,
                    processId % 60,
                    TimeSpan.Zero),
                Path.GetFullPath(
                    Path.Combine(
                        Path.GetTempPath(),
                        "cf7-agent-runtime-tests",
                        name)));
        }

        private sealed class FakeProcessProbe : ISessionProcessProbe
        {
            public HashSet<int> Exact { get; } = new HashSet<int>();
            public Dictionary<int, int> ParentByChild { get; } =
                new Dictionary<int, int>();

            public bool IsExactProcess(SessionProcessIdentity expected)
            {
                return expected != null
                    && Exact.Contains(expected.ProcessId);
            }

            public bool IsDirectChildProcess(
                SessionProcessIdentity child,
                SessionProcessIdentity parent)
            {
                return child != null
                    && parent != null
                    && ParentByChild.TryGetValue(
                        child.ProcessId,
                        out int parentId)
                    && parentId == parent.ProcessId;
            }
        }

        private sealed class FakeWindowProbe : ISessionWindowProbe
        {
            public Dictionary<long, int> ProcessByWindow { get; } =
                new Dictionary<long, int>();
            public Dictionary<long, long> OwnerByWindow { get; } =
                new Dictionary<long, long>();

            public bool TryGetOwnerProcessId(
                long windowHandle,
                out int processId)
            {
                return ProcessByWindow.TryGetValue(
                    windowHandle,
                    out processId);
            }

            public long GetOwnerWindow(long windowHandle)
            {
                return OwnerByWindow.TryGetValue(
                    windowHandle,
                    out long owner)
                    ? owner
                    : 0;
            }
        }
    }
}
