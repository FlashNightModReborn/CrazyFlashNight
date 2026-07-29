#nullable enable

using System;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoSplitSurfaceTests
{
    private const int GwlExStyle = -20;
    private const long WsExTransparent = 0x00000020L;
    private const long WsExLayered = 0x00080000L;
    private const long WsExNoActivate = 0x08000000L;
    private const int WmNcHitTest = 0x0084;
    private const long HtTransparent = -1;

    [Fact]
    public void FixtureEnvironmentResolution_IsExactAllowlistedAndFailClosed()
    {
        string[] expected =
        [
            "empty",
            "min_step",
            "p25",
            "p50",
            "p75",
            "p99",
            "full",
            "mp_vf34",
            "mp_vf35",
            "mp_vf70",
            "mp_vf91"
        ];

        Assert.Equal(
            "CF7_PLAYER_INFO_FIXTURE_CASE",
            PlayerInfoSplitSurface.FixtureCaseEnvironment);
        Assert.Equal(expected, PlayerInfoFixtureInput.AllowedCaseIds);
        foreach (string caseId in expected)
        {
            Assert.True(
                PlayerInfoSplitSurface.TryResolveFixtureCase(
                    caseId,
                    out string resolved));
            Assert.Equal(caseId, resolved);
        }

        string?[] rejected =
        [
            null,
            string.Empty,
            " ",
            "\tfull",
            "full ",
            "FULL",
            "p100",
            "custom",
            "0",
            "true"
        ];
        foreach (string? rawValue in rejected)
        {
            Assert.False(
                PlayerInfoSplitSurface.TryResolveFixtureCase(
                    rawValue,
                    out string resolved));
            Assert.Equal(string.Empty, resolved);
        }
    }

    [Fact]
    public void TypeBoundary_IsACompanionSurfaceAndCannotEnterNativeHudUnion()
    {
        Assert.True(
            typeof(OverlayBase).IsAssignableFrom(
                typeof(PlayerInfoSplitSurface)));
        Assert.True(
            typeof(IPanelHudCompanion).IsAssignableFrom(
                typeof(PlayerInfoSplitSurface)));
        Assert.False(
            typeof(NativeHudOverlay).IsAssignableFrom(
                typeof(PlayerInfoSplitSurface)));
        Assert.False(
            typeof(INativeHudWidget).IsAssignableFrom(
                typeof(PlayerInfoSplitSurface)));
        Assert.False(
            typeof(IUiDataConsumer).IsAssignableFrom(
                typeof(PlayerInfoSplitSurface)));
    }

    [Fact]
    public void SurfaceOwnsOneAnimationAuthorityAndInjectsItIntoWidget()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(out Panel anchor);
            using PlayerInfoSplitSurface surface =
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "full");

            FieldInfo animationField = typeof(PlayerInfoSplitSurface).GetField(
                "_animation",
                BindingFlags.Instance | BindingFlags.NonPublic) ??
                throw new MissingFieldException(
                    typeof(PlayerInfoSplitSurface).FullName,
                    "_animation");
            FieldInfo widgetField = typeof(PlayerInfoSplitSurface).GetField(
                "_widget",
                BindingFlags.Instance | BindingFlags.NonPublic) ??
                throw new MissingFieldException(
                    typeof(PlayerInfoSplitSurface).FullName,
                    "_widget");
            FieldInfo sourceField = typeof(PlayerInfoWidget).GetField(
                "_visualStateSource",
                BindingFlags.Instance | BindingFlags.NonPublic) ??
                throw new MissingFieldException(
                    typeof(PlayerInfoWidget).FullName,
                    "_visualStateSource");

            object animation = animationField.GetValue(surface) ??
                throw new InvalidOperationException(
                    "Surface did not retain its animation authority.");
            object widget = widgetField.GetValue(surface) ??
                throw new InvalidOperationException(
                    "Surface did not retain its rendering widget.");

            Assert.Same(animation, sourceField.GetValue(widget));
            Assert.Single(
                typeof(PlayerInfoSplitSurface)
                    .GetFields(BindingFlags.Instance | BindingFlags.NonPublic),
                field => field.FieldType == typeof(PlayerInfoAnimationModel));
        });
    }

    [Fact]
    public void RealStaHwnd_IsLayeredClickThroughAndNoActivate()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(out Panel anchor);
            using PlayerInfoSplitSurface surface =
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "full");

            Assert.True(surface.IsHandleCreated);
            IntPtr handle = surface.Handle;
            long exStyle = GetWindowLongPtr(handle, GwlExStyle).ToInt64();

            Assert.Equal(
                WsExLayered,
                exStyle & WsExLayered);
            Assert.Equal(
                WsExTransparent,
                exStyle & WsExTransparent);
            Assert.Equal(
                WsExNoActivate,
                exStyle & WsExNoActivate);
            Assert.Equal(
                HtTransparent,
                SendMessage(
                    handle,
                    WmNcHitTest,
                    IntPtr.Zero,
                    IntPtr.Zero).ToInt64());
        });
    }

    [Fact]
    public void FactoryFailures_ReleaseOwnerRootAndPartialHwnd()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(out Panel anchor);
            int ownedBaseline = owner.OwnedForms.Length;

            Assert.Throws<ArgumentException>(() =>
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "FULL"));
            Assert.Equal(ownedBaseline, owner.OwnedForms.Length);

            Assert.Throws<InvalidOperationException>(() =>
                PlayerInfoSplitSurface.CreateFixtureForTest(
                    owner,
                    anchor,
                    "full",
                    () => throw new InvalidOperationException(
                        "injected asset-load failure")));
            Application.DoEvents();
            Assert.Equal(ownedBaseline, owner.OwnedForms.Length);
        });
    }

    [Fact]
    public void OwnerHidden_BlocksInflightPublishAndQueuedAnimationCommit()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(out Panel anchor);
            owner.Show();
            Application.DoEvents();
            var observer = new RecordingCommitObserver();
            using PlayerInfoSplitSurface surface =
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "full",
                    observer);

            surface.SetReady();
            InvokeOverlayOwnerTransition(surface, "OnOwnerDeactivated");
            WaitWithoutMessagePump(
                () => surface.Counters.Pipeline.PublishCount > 0,
                TimeSpan.FromSeconds(10),
                "Background raster publish did not complete while hidden.");
            PumpFor(TimeSpan.FromMilliseconds(250));
            Assert.Equal(0, surface.Counters.CommitCount);
            Assert.Equal(0, observer.Count);

            InvokeOverlayOwnerTransition(surface, "OnOwnerActivated");
            PumpUntil(
                () => surface.Counters.CommitCount > 0,
                TimeSpan.FromSeconds(10),
                "Owner activation did not consume the current batch.");
            Assert.True(IsWindowVisible(surface.Handle));

            Assert.True(surface.SetFixtureCase("empty"));
            InvokeOverlayOwnerTransition(surface, "OnOwnerDeactivated");
            long hiddenCommitCount = surface.Counters.CommitCount;
            PumpFor(TimeSpan.FromMilliseconds(350));
            Assert.Equal(hiddenCommitCount, surface.Counters.CommitCount);
            Assert.Equal(hiddenCommitCount, observer.Count);

            InvokeOverlayOwnerTransition(surface, "OnOwnerActivated");
            Assert.False(
                IsWindowVisible(surface.Handle),
                "Activation must not briefly restore the stale pre-hidden bitmap.");
            PumpUntil(
                () => surface.Counters.CommitCount > hiddenCommitCount,
                TimeSpan.FromSeconds(10),
                "Owner reactivation did not resume the queued visual state.");
            Assert.True(IsWindowVisible(surface.Handle));
        }, TimeSpan.FromSeconds(30));
    }

    [Fact]
    public void OwnerVisibilityHook_RequestsRasterOnlyForARealTransition()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(out Panel anchor);
            using PlayerInfoSplitSurface surface =
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "full");

            surface.SetReady();
            WaitWithoutMessagePump(
                () => surface.Counters.Pipeline.PublishCount > 0,
                TimeSpan.FromSeconds(10),
                "Visibility transition test did not publish its raster batch.");
            PumpUntil(
                () => surface.Counters.CommitCount > 0,
                TimeSpan.FromSeconds(10),
                "Visibility transition test did not commit its initial frame.");

            long visibleBaseline =
                surface.Counters.Pipeline.RequestCount;
            InvokeOverlayOwnerTransition(surface, "OnOwnerActivated");
            Assert.Equal(
                visibleBaseline,
                surface.Counters.Pipeline.RequestCount);

            InvokeOverlayOwnerTransition(surface, "OnOwnerDeactivated");
            InvokeOverlayOwnerTransition(surface, "OnOwnerActivated");
            Assert.Equal(
                visibleBaseline + 1,
                surface.Counters.Pipeline.RequestCount);

            long transitioned =
                surface.Counters.Pipeline.RequestCount;
            InvokeOverlayOwnerTransition(surface, "OnOwnerActivated");
            Assert.Equal(
                transitioned,
                surface.Counters.Pipeline.RequestCount);
        }, TimeSpan.FromSeconds(30));
    }

    [Fact]
    public void CounterSnapshot_DoesNotMaterializeTimingHistory()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(out Panel anchor);
            using PlayerInfoSplitSurface surface =
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "full");

            surface.SetReady();
            WaitWithoutMessagePump(
                () => surface.Counters.Pipeline.PublishCount > 0,
                TimeSpan.FromSeconds(10),
                "Counter allocation test did not publish its raster batch.");
            PumpUntil(
                () => surface.Counters.CommitCount > 0,
                TimeSpan.FromSeconds(10),
                "Counter allocation test did not create non-empty timing history.");
            Assert.NotEmpty(surface.Snapshot.SurfaceMilliseconds);
            Assert.NotEmpty(surface.Snapshot.PaintMilliseconds);
            Assert.NotEmpty(surface.Snapshot.CommitMilliseconds);

            _ = surface.Counters;
            long baselineCommitCount = surface.Counters.CommitCount;
            long allocatedBefore = GC.GetAllocatedBytesForCurrentThread();
            long observed = 0;
            for (var index = 0; index < 10_000; index++)
            {
                observed += surface.Counters.CommitCount;
            }
            long allocated =
                GC.GetAllocatedBytesForCurrentThread() - allocatedBefore;

            Assert.Equal(10_000L * baselineCommitCount, observed);
            Assert.InRange(allocated, 0, 1_024);
        });
    }

    [Fact]
    public void CompanionTransitions_AreIdempotentAndNeverThrowAfterPartialWorkFailure()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(out Panel anchor);
            using PlayerInfoSplitSurface surface =
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "full");

            surface.SetReady();
            WaitWithoutMessagePump(
                () => surface.Counters.Pipeline.PublishCount > 0,
                TimeSpan.FromSeconds(10),
                "Companion test did not publish its raster batch.");
            PumpUntil(
                () => surface.Counters.CommitCount > 0,
                TimeSpan.FromSeconds(10),
                "Companion test did not create its first committed frame.");

            surface.Suspend();
            surface.Suspend();
            Assert.True(surface.Counters.Suspended);

            FieldInfo pipelineField = typeof(PlayerInfoSplitSurface).GetField(
                "_pipeline",
                BindingFlags.Instance | BindingFlags.NonPublic) ??
                throw new MissingFieldException(
                    typeof(PlayerInfoSplitSurface).FullName,
                    "_pipeline");
            object pipeline = pipelineField.GetValue(surface) ??
                throw new InvalidOperationException(
                    "Companion test could not capture the live pipeline.");
            pipelineField.SetValue(surface, null);
            try
            {
                Assert.Null(Record.Exception(surface.Resume));
            }
            finally
            {
                pipelineField.SetValue(surface, pipeline);
            }

            Assert.False(surface.Counters.Suspended);
            Assert.True(surface.ResumePending);
            anchor.Width++;
            Assert.False(surface.ResumePending);
            surface.Resume();
            Assert.False(surface.Counters.Suspended);
            surface.Suspend();
            surface.Resume();
            Assert.False(surface.Counters.Suspended);
        });
    }

    [Fact]
    public void ResumeWaitsForNextValidLayoutBeforeClearingPending()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(out Panel anchor);
            using PlayerInfoSplitSurface surface =
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "full");

            surface.SetReady();
            WaitWithoutMessagePump(
                () => surface.Counters.Pipeline.PublishCount > 0,
                TimeSpan.FromSeconds(10),
                "Resume-pending test did not publish its initial raster.");
            PumpUntil(
                () => surface.Counters.CommitCount > 0,
                TimeSpan.FromSeconds(10),
                "Resume-pending test did not commit its initial frame.");

            surface.Suspend();
            anchor.Size = Size.Empty;
            long requestBaseline = surface.Counters.Pipeline.RequestCount;
            long commitBaseline = surface.Counters.CommitCount;

            Assert.Null(Record.Exception(surface.Resume));
            Assert.False(surface.Counters.Suspended);
            Assert.True(surface.ResumePending);
            Assert.Equal(
                requestBaseline,
                surface.Counters.Pipeline.RequestCount);
            Assert.Equal(commitBaseline, surface.Counters.CommitCount);

            anchor.Size = new Size(1024, 576);
            Assert.False(surface.ResumePending);
            Assert.Equal(
                requestBaseline + 1,
                surface.Counters.Pipeline.RequestCount);
            PumpUntil(
                () => surface.Counters.CommitCount > commitBaseline,
                TimeSpan.FromSeconds(10),
                "Next valid layout did not complete the pending resume.");
            Assert.True(surface.Counters.Shown);
        }, TimeSpan.FromSeconds(30));
    }

    [Fact]
    public void PendingResumeIsCancelledBySuspendAndShutdownWithoutLateWork()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(out Panel anchor);
            using PlayerInfoSplitSurface surface =
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "full");

            surface.SetReady();
            WaitWithoutMessagePump(
                () => surface.Counters.Pipeline.PublishCount > 0,
                TimeSpan.FromSeconds(10),
                "Late-work test did not publish its initial raster.");
            PumpUntil(
                () => surface.Counters.CommitCount > 0,
                TimeSpan.FromSeconds(10),
                "Late-work test did not commit its initial frame.");

            surface.Suspend();
            anchor.Size = Size.Empty;
            surface.Resume();
            Assert.True(surface.ResumePending);

            surface.Suspend();
            Assert.False(surface.ResumePending);
            long suspendedRequests =
                surface.Counters.Pipeline.RequestCount;
            long suspendedCommits = surface.Counters.CommitCount;
            anchor.Size = new Size(1280, 720);
            PumpFor(TimeSpan.FromMilliseconds(150));
            Assert.Equal(
                suspendedRequests,
                surface.Counters.Pipeline.RequestCount);
            Assert.Equal(suspendedCommits, surface.Counters.CommitCount);

            anchor.Size = Size.Empty;
            surface.Resume();
            Assert.True(surface.ResumePending);
            Task shutdown = surface.BeginShutdown();
            Assert.False(surface.ResumePending);
            long shutdownRequests =
                surface.Counters.Pipeline.RequestCount;
            long shutdownCommits = surface.Counters.CommitCount;
            anchor.Size = new Size(1024, 576);
            PumpFor(TimeSpan.FromMilliseconds(150));
            shutdown.GetAwaiter().GetResult();
            Assert.Equal(
                shutdownRequests,
                surface.Counters.Pipeline.RequestCount);
            Assert.Equal(shutdownCommits, surface.Counters.CommitCount);
        }, TimeSpan.FromSeconds(30));
    }

    [Fact]
    public void DirectDispose_DrainsActiveRasterAndDestroysOwnedHwnd()
    {
        RunOnSta(() =>
        {
            using Form owner = CreateHost(
                out Panel anchor,
                new Size(1920, 1080));
            int ownedBaseline = owner.OwnedForms.Length;
            var surface = PlayerInfoSplitSurface.CreateFixture(
                owner,
                anchor,
                "full");
            using var rasterizer = new CancellationBlockingRasterizer();
            FieldInfo pipelineField = typeof(PlayerInfoSplitSurface).GetField(
                "_pipeline",
                BindingFlags.Instance | BindingFlags.NonPublic) ??
                throw new MissingFieldException(
                    typeof(PlayerInfoSplitSurface).FullName,
                    "_pipeline");
            var originalPipeline =
                (PlayerInfoRasterPipeline)(pipelineField.GetValue(surface) ??
                    throw new InvalidOperationException(
                        "Direct-dispose test could not capture the live pipeline."));
            var blockingPipeline =
                new PlayerInfoRasterPipeline(rasterizer);
            pipelineField.SetValue(surface, blockingPipeline);
            originalPipeline.Dispose();
            IntPtr handle = surface.Handle;
            Assert.True(IsWindow(handle));
            surface.SetReady();
            Assert.True(
                rasterizer.Started.Wait(TimeSpan.FromSeconds(5)),
                "The direct-dispose raster worker did not start.");
            Assert.Equal(1, surface.Counters.Pipeline.ActiveWorkers);

            try
            {
                surface.Dispose();
                Assert.True(
                    rasterizer.CancellationObserved.Wait(
                        TimeSpan.FromSeconds(5)),
                    "Direct dispose did not cancel the active raster worker.");
                surface.WaitForDrainAsync(TimeSpan.FromSeconds(5))
                    .GetAwaiter()
                    .GetResult();
                PlayerInfoRasterPipelineSnapshot drained =
                    blockingPipeline.Snapshot;
                Assert.Equal(1, drained.CancelCount);
                Assert.Equal(0, drained.FaultCount);
                Assert.Null(drained.LastFault);
                Application.DoEvents();

                Assert.False(IsWindow(handle));
                Assert.False(surface.IsHandleCreated);
                Assert.Equal(ownedBaseline, owner.OwnedForms.Length);
            }
            finally
            {
                // A broken cancellation path must fail the assertions above,
                // but the test release prevents that failure from leaking a
                // permanently blocked worker into the process.
                rasterizer.TestRelease.Set();
                surface.Dispose();
                blockingPipeline.Dispose();
            }
        }, TimeSpan.FromSeconds(20));
    }

    [Fact]
    public void BackgroundPublish_LifecycleAndIdle_AreUiThreadBounded()
    {
        RunOnSta(() =>
        {
            int uiThreadId = Environment.CurrentManagedThreadId;
            using Form owner = CreateHost(out Panel anchor);
            var observer = new RecordingCommitObserver();
            using PlayerInfoSplitSurface surface =
                PlayerInfoSplitSurface.CreateFixture(
                    owner,
                    anchor,
                    "full",
                    observer);

            surface.SetReady();

            WaitWithoutMessagePump(
                () => surface.Counters.Pipeline.PublishCount > 0,
                TimeSpan.FromSeconds(10),
                "Background raster publish did not complete.");
            PlayerInfoSplitSurfaceSnapshot published = surface.Snapshot;
            Assert.Equal(0, published.PaintCount);
            Assert.Equal(0, published.CommitCount);
            Assert.Equal(0, observer.Count);

            PumpUntil(
                () => surface.Counters.CommitCount > 0,
                TimeSpan.FromSeconds(10),
                "The posted UI-thread paint/commit did not run.");
            PlayerInfoSplitSurfaceSnapshot firstCommit = surface.Snapshot;
            Assert.Equal(firstCommit.CommitCount, observer.Count);
            Assert.Equal(uiThreadId, observer.LastThreadId);
            Assert.NotNull(observer.LastResult);
            Assert.True(
                observer.LastResult!.Succeeded,
                "Real UpdateLayeredWindow failed: " +
                observer.LastResult.ErrorValue +
                " nativeError=" +
                observer.LastResult.NativeErrorCode);
            Assert.Equal(
                firstCommit.TightPhysicalBounds.Left,
                observer.LastResult.ScreenX);
            Assert.Equal(
                firstCommit.TightPhysicalBounds.Top,
                observer.LastResult.ScreenY);
            Assert.Equal(
                firstCommit.TightPhysicalBounds.Width,
                observer.LastResult.Width);
            Assert.Equal(
                firstCommit.TightPhysicalBounds.Height,
                observer.LastResult.Height);
            Point viewportOrigin = anchor.PointToScreen(Point.Empty);
            Assert.Equal(
                new Rectangle(
                    viewportOrigin.X,
                    viewportOrigin.Y + 474,
                    282,
                    81),
                firstCommit.TightPhysicalBounds);
            Assert.Equal(0, firstCommit.CommitFailureCount);
            Assert.True(firstCommit.Shown);

            long beforeZOrderReassert = surface.Counters.CommitCount;
            surface.SetZOrderInsertAfter(IntPtr.Zero);
            PumpUntil(
                () => surface.Counters.CommitCount > beforeZOrderReassert,
                TimeSpan.FromSeconds(10),
                "Repeating the same z-order anchor did not reassert the real HWND placement.");
            Assert.True(surface.Snapshot.Shown);

            surface.Suspend();
            PlayerInfoSplitSurfaceSnapshot suspended = surface.Snapshot;
            Assert.True(suspended.Suspended);
            Assert.False(suspended.Shown);
            Assert.True(surface.SetFixtureCase("empty"));
            long suspendedCommitCount = surface.Counters.CommitCount;
            PumpFor(TimeSpan.FromMilliseconds(200));
            Assert.Equal(
                suspendedCommitCount,
                surface.Counters.CommitCount);

            surface.Resume();
            Assert.False(surface.Counters.Suspended);
            PumpUntil(
                () => surface.Counters.CommitCount > suspendedCommitCount,
                TimeSpan.FromSeconds(10),
                "Resume did not repaint the suspended fixture change.");

            long settledCommitCount = PumpUntilCommitQuiescent(
                surface,
                quietPeriod: TimeSpan.FromMilliseconds(250),
                timeout: TimeSpan.FromSeconds(8));
            PumpFor(TimeSpan.FromMilliseconds(350));
            Assert.Equal(
                settledCommitCount,
                surface.Counters.CommitCount);

            anchor.Size = new Size(1280, 720);
            long preShutdownCommitCount = surface.Counters.CommitCount;
            Task beginShutdown = surface.BeginShutdown();
            surface.WaitForDrainAsync(TimeSpan.FromSeconds(10))
                .GetAwaiter()
                .GetResult();
            beginShutdown.GetAwaiter().GetResult();

            PlayerInfoSplitSurfaceSnapshot shutdown = surface.Snapshot;
            Assert.True(shutdown.Shutdown);
            Assert.False(shutdown.Ready);
            Assert.False(shutdown.Shown);
            Assert.Equal(0, shutdown.Pipeline.ActiveWorkers);
            Assert.False(surface.SetFixtureCase("full"));

            PumpFor(TimeSpan.FromMilliseconds(350));
            Assert.Equal(
                preShutdownCommitCount,
                surface.Counters.CommitCount);
            Assert.Equal(
                preShutdownCommitCount,
                observer.Count);
        }, TimeSpan.FromSeconds(35));
    }

    private static Form CreateHost(
        out Panel anchor,
        Size? clientSize = null)
    {
        Size size = clientSize ?? new Size(1024, 576);
        var owner = new Form
        {
            AutoScaleMode = AutoScaleMode.None,
            ClientSize = size,
            FormBorderStyle = FormBorderStyle.None,
            Location = new Point(-20_000, -20_000),
            ShowInTaskbar = false,
            StartPosition = FormStartPosition.Manual
        };
        anchor = new Panel
        {
            Bounds = new Rectangle(Point.Empty, size)
        };
        owner.Controls.Add(anchor);
        _ = owner.Handle;
        _ = anchor.Handle;
        return owner;
    }

    private static void WaitWithoutMessagePump(
        Func<bool> condition,
        TimeSpan timeout,
        string failureMessage)
    {
        var timer = Stopwatch.StartNew();
        while (!condition() && timer.Elapsed < timeout)
        {
            Thread.Sleep(5);
        }
        Assert.True(condition(), failureMessage);
    }

    private static void PumpUntil(
        Func<bool> condition,
        TimeSpan timeout,
        string failureMessage)
    {
        var timer = Stopwatch.StartNew();
        while (!condition() && timer.Elapsed < timeout)
        {
            Application.DoEvents();
            Thread.Sleep(5);
        }
        Application.DoEvents();
        Assert.True(condition(), failureMessage);
    }

    private static long PumpUntilCommitQuiescent(
        PlayerInfoSplitSurface surface,
        TimeSpan quietPeriod,
        TimeSpan timeout)
    {
        var total = Stopwatch.StartNew();
        var quiet = Stopwatch.StartNew();
        long lastCommitCount = surface.Counters.CommitCount;
        while (total.Elapsed < timeout)
        {
            Application.DoEvents();
            Thread.Sleep(5);

            PlayerInfoSplitSurfaceCounterSnapshot snapshot = surface.Counters;
            if (snapshot.CommitCount != lastCommitCount)
            {
                lastCommitCount = snapshot.CommitCount;
                quiet.Restart();
            }
            if (snapshot.Pipeline.ActiveWorkers == 0 &&
                string.Equals(
                    snapshot.Pipeline.DesiredBatchKey,
                    snapshot.Pipeline.CurrentBatchKey,
                    StringComparison.Ordinal) &&
                quiet.Elapsed >= quietPeriod)
            {
                return lastCommitCount;
            }
        }

        Assert.Fail(
            "PlayerInfo surface did not reach a commit-quiescent state " +
            $"within {timeout.TotalSeconds:0.###} seconds.");
        return 0;
    }

    private static void PumpFor(TimeSpan duration)
    {
        var timer = Stopwatch.StartNew();
        while (timer.Elapsed < duration)
        {
            Application.DoEvents();
            Thread.Sleep(5);
        }
        Application.DoEvents();
    }

    private static void InvokeOverlayOwnerTransition(
        PlayerInfoSplitSurface surface,
        string methodName)
    {
        MethodInfo method = typeof(OverlayBase).GetMethod(
            methodName,
            BindingFlags.Instance | BindingFlags.NonPublic) ??
            throw new MissingMethodException(
                typeof(OverlayBase).FullName,
                methodName);
        method.Invoke(surface, null);
    }

    private sealed class CancellationBlockingRasterizer :
        IPlayerInfoRasterizer,
        IDisposable
    {
        internal ManualResetEventSlim Started { get; } = new(false);
        internal ManualResetEventSlim CancellationObserved { get; } =
            new(false);
        internal ManualResetEventSlim TestRelease { get; } = new(false);

        public PlayerInfoRasterBatch Bake(
            PlayerInfoRasterPlan plan,
            CancellationToken cancellationToken,
            PlayerInfoRasterProgress progress)
        {
            Started.Set();
            int signaled = WaitHandle.WaitAny(
            [
                cancellationToken.WaitHandle,
                TestRelease.WaitHandle
            ]);
            if (signaled == 0)
            {
                CancellationObserved.Set();
                cancellationToken.ThrowIfCancellationRequested();
            }
            throw new InvalidOperationException(
                "The test released the raster worker before cancellation.");
        }

        public void Dispose()
        {
            Started.Dispose();
            CancellationObserved.Dispose();
            TestRelease.Dispose();
        }
    }

    private static void RunOnSta(
        Action action,
        TimeSpan? timeout = null)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                action();
            }
            catch (Exception ex)
            {
                failure = ex;
            }
        })
        {
            IsBackground = true,
            Name = "PlayerInfoSplitSurfaceTests.STA"
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();

        TimeSpan joinTimeout = timeout ?? TimeSpan.FromSeconds(20);
        Assert.True(
            thread.Join(joinTimeout),
            "STA test thread exceeded its fail-closed timeout of " +
            $"{joinTimeout.TotalSeconds:0.###} seconds.");
        if (failure is not null)
        {
            ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }

    private sealed class RecordingCommitObserver :
        ILayeredWindowCommitObserver
    {
        private int _count;
        private int _lastThreadId;
        private LayeredWindowCommitResult? _lastResult;

        internal int Count => Volatile.Read(ref _count);
        internal int LastThreadId => Volatile.Read(ref _lastThreadId);
        internal LayeredWindowCommitResult? LastResult =>
            Volatile.Read(ref _lastResult);

        public void OnCommit(LayeredWindowCommitResult result)
        {
            Volatile.Write(
                ref _lastThreadId,
                Environment.CurrentManagedThreadId);
            Volatile.Write(ref _lastResult, result);
            Interlocked.Increment(ref _count);
        }
    }

    [DllImport(
        "user32.dll",
        EntryPoint = "GetWindowLongPtrW",
        SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr(
        IntPtr windowHandle,
        int index);

    [DllImport(
        "user32.dll",
        EntryPoint = "SendMessageW",
        SetLastError = true)]
    private static extern IntPtr SendMessage(
        IntPtr windowHandle,
        int message,
        IntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr windowHandle);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr windowHandle);
}
