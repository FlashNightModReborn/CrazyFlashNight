using System;
using System.Drawing;
using System.IO;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelGeometryLifecycleTests
    {
        [Fact]
        public void ViewportMeasurementRejectsNonFiniteNonPositiveAndSentinel()
        {
            Assert.Equal(
                PanelGeometryMeasurementKind.ExplicitInvalid,
                PanelGeometryMeasurement.FromViewport(
                    double.NaN, 0, 1600, 900, Point.Empty,
                    "mapper", "test").Kind);
            Assert.Equal(
                PanelGeometryMeasurementKind.ExplicitInvalid,
                PanelGeometryMeasurement.FromViewport(
                    0, 0, 0, 900, Point.Empty,
                    "mapper", "test").Kind);
            PanelGeometryMeasurement sentinel =
                PanelGeometryMeasurement.FromViewport(
                    0, 0, 1, 1, Point.Empty,
                    "mapper", "test");
            Assert.Equal(
                PanelGeometryMeasurementKind.ExplicitInvalid,
                sentinel.Kind);
            Assert.Equal("transient_sentinel", sentinel.Reason);

            PanelGeometryMeasurement valid =
                PanelGeometryMeasurement.FromViewport(
                    12.5, 8.25, 1600, 900,
                    new Point(100, 200),
                    "mapper", "test");
            Assert.Equal(PanelGeometryMeasurementKind.Valid, valid.Kind);
            Assert.Equal(new Rectangle(112, 208, 1600, 900), valid.Rect);
        }

        [Fact]
        public void ExplicitInvalidStopsFallbackWithoutReadingLaterSource()
        {
            int fallbackReads = 0;
            PanelGeometryMeasurement result =
                PanelHostController.ResolveAnchorMeasurements(
                    delegate
                    {
                        return PanelGeometryMeasurement.ExplicitInvalid(
                            "mapper", "minimized");
                    },
                    delegate
                    {
                        fallbackReads++;
                        return PanelGeometryMeasurement.FromRectangle(
                            new Rectangle(0, 0, 1024, 576),
                            "owner", "fallback");
                    });

            Assert.Equal(
                PanelGeometryMeasurementKind.ExplicitInvalid,
                result.Kind);
            Assert.Equal(0, fallbackReads);
            Assert.Equal("mapper", result.Source);
        }

        [Fact]
        public void UnavailableMayUseNextIndependentlyValidSource()
        {
            int fallbackReads = 0;
            PanelGeometryMeasurement result =
                PanelHostController.ResolveAnchorMeasurements(
                    delegate
                    {
                        return PanelGeometryMeasurement.Unavailable(
                            "mapper", "handle_unavailable");
                    },
                    delegate
                    {
                        fallbackReads++;
                        return PanelGeometryMeasurement.FromRectangle(
                            new Rectangle(10, 20, 1024, 576),
                            "flash_panel", "client");
                    });

            Assert.Equal(PanelGeometryMeasurementKind.Valid, result.Kind);
            Assert.Equal(1, fallbackReads);
            Assert.Equal("flash_panel", result.Source);
        }

        [Fact]
        public void RestoreRevalidationIsGenerationBoundAndConsumedExactlyOnce()
        {
            var gate = new PanelRestoreRevalidationGate();
            Assert.False(gate.Mark(7, false));
            Assert.True(gate.Mark(7, true));
            Assert.True(gate.IsPendingFor(7));
            Assert.Equal(
                PanelRestoreRevalidationDisposition.ReplayCommitted,
                gate.Consume(7, true));
            Assert.Equal(
                PanelRestoreRevalidationDisposition.None,
                gate.Consume(7, true));

            Assert.True(gate.Mark(7, true));
            Assert.Equal(
                PanelRestoreRevalidationDisposition.GeometryChanged,
                gate.Consume(7, false));

            Assert.True(gate.Mark(7, true));
            Assert.Equal(
                PanelRestoreRevalidationDisposition.None,
                gate.Consume(8, true));
            Assert.False(gate.IsPendingFor(7));
        }

        [Fact]
        public void ProductionOpenPublishesGeometryBeforeEveryPresentationMutation()
        {
            string source = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Guardian", "PanelHostController.cs"));
            string open = Slice(
                source,
                "private bool DoOpen(string name, string initDataJson, string reservedPanelInstanceId,",
                "private void AbortOpenAttempt(");

            int reserveIdentity = open.IndexOf(
                "string instanceId = string.IsNullOrEmpty(reservedPanelInstanceId)",
                StringComparison.Ordinal);
            int geometry = open.IndexOf(
                "TryCreateProvisionalGeometry(",
                reserveIdentity,
                StringComparison.Ordinal);
            int pause = open.IndexOf(
                "_web.AssertWebPanelPause()",
                geometry,
                StringComparison.Ordinal);
            int companion = open.IndexOf(
                "SuspendHudCompanion();",
                geometry,
                StringComparison.Ordinal);
            int backdrop = open.IndexOf(
                "Bitmap composed = CaptureBackdrop(",
                geometry,
                StringComparison.Ordinal);
            int resume = open.IndexOf(
                "if (!_web.ResumeForPanel(panelRect))",
                geometry,
                StringComparison.Ordinal);
            int commit = open.IndexOf(
                "CommitGeometry(provisional, focusGeneration)",
                geometry,
                StringComparison.Ordinal);

            Assert.True(reserveIdentity >= 0);
            Assert.True(geometry > reserveIdentity);
            Assert.True(pause > geometry);
            Assert.True(companion > pause);
            Assert.True(backdrop > companion);
            Assert.True(resume > backdrop);
            Assert.True(commit > resume);

            string router = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Guardian", "LauncherCommandRouter.cs"));
            Assert.DoesNotContain(
                "TrySendGameCommand(\"webPanelPause\")",
                router);
        }

        [Fact]
        public void ReplayAndRepairAreCommittedOnlyAndFocusFree()
        {
            string source = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Guardian", "WebOverlayForm.cs"));
            string replay = Slice(
                source,
                "internal bool ReplayCommittedPanelPresentation(",
                "internal PanelGeometryMeasurement MeasureCurrentAnchorScreenRect()");
            Assert.Contains("TryGetCommittedPanelGeometry(", replay);
            Assert.Contains("committedRect.Width", replay);
            Assert.DoesNotContain("BeginPanel(", replay);
            Assert.DoesNotContain("QueuePanelFocusRestore", replay);
            Assert.DoesNotContain("SetForegroundWindow", replay);
            Assert.DoesNotContain(".MoveFocus", replay);
            Assert.DoesNotContain("BuildPanelOpenPayload", replay);
            Assert.DoesNotContain("this.ClientSize.Width", replay);

            string repair = Slice(
                source,
                "private void SchedulePanelViewportRepair(string reason)",
                "private CoreWebView2EnvironmentOptions CreateWebView2EnvironmentOptions()");
            Assert.Contains("TryGetCommittedPanelGeometry(", repair);
            Assert.Contains("committedRect.Width", repair);
            Assert.DoesNotContain("this.ClientSize.Width", repair);

            string measurement = Slice(
                source,
                "internal PanelGeometryMeasurement MeasureCurrentAnchorScreenRect()",
                "public void SuspendAfterPanel(");
            Assert.DoesNotContain("Math.Max(1", measurement);
        }

        [Fact]
        public void CommittedLifetimeChecksOwnerHandlePanelAndFocusGeneration()
        {
            string source = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Guardian", "PanelHostController.cs"));
            string lifetime = Slice(
                source,
                "private bool HasCurrentCommittedGeometry(int focusGeneration)",
                "private void MarkRestoreRevalidation(string reason)");

            Assert.Contains("committed.FocusGeneration == focusGeneration", lifetime);
            Assert.Contains("committed.OwnerHandleGeneration == _ownerHandleGeneration", lifetime);
            Assert.Contains("committed.OwnerHwnd == _ownerForm.Handle", lifetime);
            Assert.Contains("committed.PanelName, _activePanel", lifetime);
            Assert.Contains("committed.PanelInstanceId", lifetime);
            Assert.Contains("_activePanelInstanceId", lifetime);
        }

        [Fact]
        public void NativeHideAndShowPairControllerVisibilityWithoutGeometryRevealingIt()
        {
            string source = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Guardian", "WebOverlayForm.cs"));
            string idle = Slice(source, "private void DoFullIdleSuspend(",
                "private void SuspendWebTimers()");
            Assert.True(idle.IndexOf("SetWebViewControllerVisible(false,", StringComparison.Ordinal)
                < idle.IndexOf("ShowWindow(this.Handle, SW_HIDE)", StringComparison.Ordinal));

            string resume = Slice(source, "public bool ResumeForPanel(",
                "private void QueuePanelFocusRestore(");
            Assert.True(resume.IndexOf("SetWebViewControllerVisible(false,", StringComparison.Ordinal)
                < resume.IndexOf("this.TransparencyKey = Color.Empty", StringComparison.Ordinal));
            Assert.True(resume.IndexOf("SetWindowPos(_webView.Handle", StringComparison.Ordinal)
                < resume.IndexOf("SetWebViewControllerVisible(true,", StringComparison.Ordinal));
            Assert.Contains("if (formPresented)", resume);

            string geometry = Slice(source, "private void SyncWebViewViewportBounds(",
                "private void SyncPosition(string reason)");
            Assert.DoesNotContain("controller.IsVisible = true", geometry);

            string replay = Slice(source, "internal bool ReplayCommittedPanelPresentation(",
                "internal PanelGeometryMeasurement MeasureCurrentAnchorScreenRect()");
            Assert.Contains("SetWebViewControllerVisible(false,", replay);
            Assert.Contains("SetWebViewControllerVisible(true,", replay);
        }

        [Fact]
        public void BattleReturnDiagnosticIsBoundedReadOnlyAndExactInstanceScoped()
        {
            string source = File.ReadAllText(FindRepositoryFile(
                "launcher", "src", "Guardian", "WebOverlayForm.cs"));
            string probe = Slice(source, "private bool IsCurrentWarlordPresentation(",
                "private void QueueWarlordStageTerminalClose(");
            Assert.Contains("generation == _panelSessionGeneration", probe);
            Assert.Contains("_panelHost.ActivePanelInstanceId, instanceId", probe);
            Assert.Contains("Task.Delay(1500)", probe);
            Assert.Contains("sample.Length > 8192", probe);
            Assert.Contains("WarlordPanelDiagnostics.read()", probe);
            Assert.DoesNotContain("Capture", probe);
            Assert.DoesNotContain("ResumeForPanel(", probe);
            Assert.DoesNotContain("while (", probe);
            Assert.DoesNotContain("SetForegroundWindow", probe);
        }

        private static string Slice(
            string source,
            string startMarker,
            string endMarker)
        {
            int start = source.IndexOf(startMarker, StringComparison.Ordinal);
            Assert.True(start >= 0, "missing start marker: " + startMarker);
            int end = source.IndexOf(endMarker, start, StringComparison.Ordinal);
            Assert.True(end > start, "missing end marker: " + endMarker);
            return source.Substring(start, end - start);
        }

        private static string FindRepositoryFile(params string[] relativeParts)
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string path = current.FullName;
                foreach (string part in relativeParts)
                    path = Path.Combine(path, part);
                if (File.Exists(path)) return path;
                current = current.Parent;
            }
            throw new FileNotFoundException(
                string.Join(Path.DirectorySeparatorChar.ToString(), relativeParts));
        }
    }
}
