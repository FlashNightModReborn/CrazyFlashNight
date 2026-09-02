using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelHostHudCompanionTests
    {
        private sealed class RecordingCompanion : IPanelHudCompanion
        {
            public readonly List<string> Calls = new List<string>();
            public Action OnSuspend;
            public Action OnResume;
            public bool ThrowOnSuspend;
            public bool ThrowOnResume;

            public void Suspend()
            {
                Calls.Add("suspend");
                if (OnSuspend != null) OnSuspend();
                if (ThrowOnSuspend)
                    throw new InvalidOperationException("suspend fixture failure");
            }

            public void Resume()
            {
                Calls.Add("resume");
                if (OnResume != null) OnResume();
                if (ThrowOnResume)
                    throw new InvalidOperationException("resume fixture failure");
            }
        }

        private sealed class HostHarness : IDisposable
        {
            public readonly Queue<Action> Pumps = new Queue<Action>();
            public readonly PanelHostController Host;

            public HostHarness(IPanelHudCompanion companion)
            {
                Host = new PanelHostController(
                    delegate(Action pump) { Pumps.Enqueue(pump); },
                    delegate(Action fire) { fire(); },
                    companion);
            }

            public void Pump()
            {
                Action pump = Assert.Single(Pumps);
                Pumps.Clear();
                pump();
            }

            public void Dispose()
            {
                Host.Dispose();
            }
        }

        [Fact]
        public void NormalOpenClose_SuspendsBeforeActivationAndResumesBeforeCloseCompletes()
        {
            var companion = new RecordingCompanion();
            using (var harness = new HostHarness(companion))
            {
                companion.OnSuspend =
                    delegate { Assert.False(harness.Host.IsPanelOpen); };
                companion.OnResume =
                    delegate { Assert.True(harness.Host.IsPanelOpen); };

                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map", "{}", null, null));
                harness.Pump();

                Assert.True(harness.Host.IsPanelOpen);
                Assert.Equal(
                    new[] { "suspend" },
                    companion.Calls);

                harness.Host.ClosePanel();
                harness.Pump();

                Assert.False(harness.Host.IsPanelOpen);
                Assert.Equal(
                    new[] { "suspend", "resume" },
                    companion.Calls);

                // An already-idle close is a no-op and must not manufacture
                // another companion transition.
                harness.Host.ClosePanel();
                harness.Pump();
                Assert.Equal(
                    new[] { "suspend", "resume" },
                    companion.Calls);
            }
        }

        [Fact]
        public void CompanionSuspendFailure_IsolatedWithoutUnpairedResume()
        {
            var companion = new RecordingCompanion
            {
                ThrowOnSuspend = true
            };
            using (var harness = new HostHarness(companion))
            {
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map", "{}", null, null));
                harness.Pump();
                Assert.True(harness.Host.IsPanelOpen);

                harness.Host.ClosePanel();
                harness.Pump();
                Assert.False(harness.Host.IsPanelOpen);
                Assert.Equal(
                    new[] { "suspend" },
                    companion.Calls);
            }
        }

        [Fact]
        public void CompanionResumeFailure_RemainsSuspendedAndIsRetried()
        {
            var companion = new RecordingCompanion
            {
                ThrowOnResume = true
            };
            using (var harness = new HostHarness(companion))
            {
                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map", "{}", null, null));
                harness.Pump();
                harness.Host.ClosePanel();
                harness.Pump();
                Assert.False(harness.Host.IsPanelOpen);
                Assert.Equal(
                    new[] { "suspend", "resume" },
                    companion.Calls);

                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map", "{}", null, null));
                harness.Pump();
                harness.Host.ClosePanel();
                harness.Pump();
                Assert.False(harness.Host.IsPanelOpen);
                Assert.Equal(
                    new[] { "suspend", "resume", "resume" },
                    companion.Calls);
            }
        }

        [Fact]
        public void ExceptionReset_DoesNotManufactureUnpairedCompanionResume()
        {
            var companion = new RecordingCompanion
            {
                ThrowOnResume = true
            };
            using (var harness = new HostHarness(companion))
            {
                harness.Host.SetOpenGate(
                    delegate
                    {
                        throw new InvalidOperationException(
                            "open gate fixture failure");
                    });

                Assert.True(
                    harness.Host.TryOpenPanel(
                        "map", "{}", null, null));
                harness.Pump();

                Assert.False(harness.Host.IsPanelOpen);
                Assert.Empty(companion.Calls);
            }
        }

        [Fact]
        public void ProductionOpen_SuspendsCompanionBeforeBackdropAndWeb()
        {
            string source = File.ReadAllText(
                FindRepositoryFile(
                    "launcher",
                    "src",
                    "Guardian",
                    "PanelHostController.cs"));
            string open = Slice(
                source,
                "private bool DoOpen(string name, string initDataJson, string reservedPanelInstanceId,",
                "private void DoRebind(string name, string initDataJson)");

            int captureBackdrop = open.IndexOf(
                "Bitmap composed = CaptureBackdrop(",
                StringComparison.Ordinal);
            Assert.True(captureBackdrop >= 0);
            int validAdmissionComment = open.IndexOf(
                "// valid admission 后才能暂停独立 surface/HUD",
                StringComparison.Ordinal);
            Assert.True(validAdmissionComment >= 0);
            int suspendCompanion = open.IndexOf(
                "SuspendHudCompanion();",
                validAdmissionComment,
                StringComparison.Ordinal);
            int resumeWeb = open.IndexOf(
                "if (!_web.ResumeForPanel(panelRect))",
                captureBackdrop,
                StringComparison.Ordinal);

            Assert.True(suspendCompanion >= 0);
            Assert.True(suspendCompanion > validAdmissionComment);
            Assert.True(suspendCompanion < captureBackdrop);
            Assert.True(resumeWeb > captureBackdrop);
        }

        private static string Slice(
            string source,
            string startMarker,
            string endMarker)
        {
            int start = source.IndexOf(
                startMarker,
                StringComparison.Ordinal);
            Assert.True(start >= 0);
            int end = source.IndexOf(
                endMarker,
                start,
                StringComparison.Ordinal);
            Assert.True(end > start);
            return source.Substring(start, end - start);
        }

        private static string FindRepositoryFile(
            params string[] relativeParts)
        {
            DirectoryInfo current =
                new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string path = current.FullName;
                foreach (string part in relativeParts)
                    path = Path.Combine(path, part);
                if (File.Exists(path)) return path;
                current = current.Parent;
            }
            throw new FileNotFoundException(
                string.Join(
                    Path.DirectorySeparatorChar.ToString(),
                    relativeParts));
        }
    }
}
