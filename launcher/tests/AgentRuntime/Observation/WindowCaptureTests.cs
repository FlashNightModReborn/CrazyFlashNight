using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Observation;
using Xunit;

namespace CF7Launcher.Tests.AgentRuntime.Observation
{
    public sealed class WindowCaptureTests
    {
        [Fact]
        public async Task ProductionFacadePassesExactHwndToNativePixelBoundary()
        {
            var items = new RecordingCaptureItemFactory();
            var pixels = new RecordingPixelProducer();
            var factory = new WindowsGraphicsCaptureSourceFactory(
                items,
                new AcceptingPreflight(),
                pixels,
                TimeSpan.FromSeconds(1));
            ObservationSurfacePlan surface = Surface();
            using IWindowFrameSource source = factory.Create(surface);

            using WindowFrameCaptureResult result =
                await source.CaptureLatestAsync(
                    CancellationToken.None);

            Assert.True(result.Success);
            Assert.Equal(
                new IntPtr(surface.WindowHandle),
                items.LastWindow);
            Assert.Equal(1, items.Calls);
            Assert.Equal(1, pixels.Calls);
            Assert.Equal(
                items.Handle.AbiPointer,
                pixels.LastItem);
            Assert.True(items.Handle.Disposed);
        }

        [Fact]
        public async Task RejectedPreflightNeverCreatesItemOrCallsNativePixels()
        {
            var items = new RecordingCaptureItemFactory();
            var pixels = new RecordingPixelProducer();
            var factory = new WindowsGraphicsCaptureSourceFactory(
                items,
                new RejectingPreflight(),
                pixels,
                TimeSpan.FromSeconds(1));
            using IWindowFrameSource source =
                factory.Create(Surface());

            using WindowFrameCaptureResult result =
                await source.CaptureLatestAsync(
                    CancellationToken.None);

            Assert.False(result.Success);
            Assert.Equal(
                "target_not_authoritative",
                result.ReasonCode);
            Assert.Equal(0, items.Calls);
            Assert.Equal(0, pixels.Calls);
        }

        [Fact]
        public async Task HardDeadlineDisposesLateNativePixels()
        {
            var items = new RecordingCaptureItemFactory();
            using var release = new ManualResetEventSlim(false);
            using var entered = new ManualResetEventSlim(false);
            var pixels = new BlockingPixelProducer(
                entered,
                release);
            var factory = new WindowsGraphicsCaptureSourceFactory(
                items,
                new AcceptingPreflight(),
                pixels,
                TimeSpan.FromMilliseconds(40));
            using IWindowFrameSource source =
                factory.Create(Surface());

            Stopwatch stopwatch = Stopwatch.StartNew();
            using WindowFrameCaptureResult result =
                await source.CaptureLatestAsync(
                    CancellationToken.None);
            stopwatch.Stop();

            Assert.True(entered.IsSet);
            Assert.False(result.Success);
            Assert.Equal(
                "capture_unavailable",
                result.ReasonCode);
            Assert.True(
                stopwatch.Elapsed < TimeSpan.FromSeconds(1));

            release.Set();
            Assert.True(SpinWait.SpinUntil(
                () => items.Handle.Disposed
                    && pixels.ReturnedPixels != null
                    && pixels.ReturnedPixels.All(
                        value => value == 0),
                TimeSpan.FromSeconds(2)));
        }

        [Fact]
        public void NativeProducerRejectsMissingCaptureItem()
        {
            var producer =
                new WindowsGraphicsCapturePixelProducer();

            Assert.Throws<ArgumentNullException>(
                () => producer.CaptureLatest(
                    null,
                    CancellationToken.None));
        }

        [Fact]
        public async Task RealWgcCapturesOnlyExplicitOwnedWindowWhenOptedIn()
        {
            if (!string.Equals(
                    Environment.GetEnvironmentVariable(
                        "CF7_RUN_REAL_WGC_TEST"),
                    "1",
                    StringComparison.Ordinal))
            {
                return;
            }
            Assert.True(Environment.UserInteractive);

            using var ready = new ManualResetEventSlim(false);
            Form form = null;
            Exception uiFailure = null;
            var uiThread = new Thread(
                () =>
                {
                    try
                    {
                        form = new Form
                        {
                            BackColor = Color.Magenta,
                            ClientSize = new Size(320, 180),
                            FormBorderStyle =
                                FormBorderStyle.FixedToolWindow,
                            ShowInTaskbar = false,
                            StartPosition =
                                FormStartPosition.Manual,
                            Location = new Point(40, 40)
                        };
                        form.Shown += (_, _) => ready.Set();
                        Application.Run(form);
                    }
                    catch (Exception exception)
                    {
                        uiFailure = exception;
                        ready.Set();
                    }
                });
            uiThread.IsBackground = true;
            uiThread.SetApartmentState(ApartmentState.STA);
            uiThread.Start();

            try
            {
                Assert.True(
                    ready.Wait(TimeSpan.FromSeconds(5)));
                Assert.Null(uiFailure);
                Assert.NotNull(form);
                IntPtr window = form.Handle;
                Assert.NotEqual(IntPtr.Zero, window);

                using Process process =
                    Process.GetCurrentProcess();
                ObservationSurfacePlan surface =
                    SurfaceForCurrentProcess(
                        window,
                        process);
                var factory =
                    new WindowsGraphicsCaptureSourceFactory();
                using IWindowFrameSource source =
                    factory.Create(surface);

                using WindowFrameCaptureResult result =
                    await source.CaptureLatestAsync(
                        CancellationToken.None);

                Assert.True(
                    result.Success,
                    result.ReasonCode);
                Assert.Equal(
                    ObservationMode.WindowGraphicsCapture,
                    result.SourceMode);
                Assert.True(result.Width >= 320);
                Assert.True(result.Height >= 180);
                Assert.True(CapturedFrameSafety.IsAcceptableBgra(
                    result,
                    out string reasonCode),
                    reasonCode);
            }
            finally
            {
                if (form != null
                    && !form.IsDisposed
                    && form.IsHandleCreated)
                {
                    form.BeginInvoke(
                        new Action(form.Close));
                }
                Assert.True(
                    uiThread.Join(TimeSpan.FromSeconds(5)));
            }
        }

        [Fact]
        public async Task FlashSnapshotNeverRunsWithoutHostQualification()
        {
            var qualification = new DeniedQualification();
            var fallback =
                new VerifiedFlashSnapshotKeyframeFallback(
                    qualification);
            ObservationSurfacePlan surface = Surface();
            var plan = new ObservationCapturePlan(
                "session_capture_AAAAAAAAAAAAAAAA",
                1,
                null,
                null,
                null,
                1,
                1,
                BlockingModalKind.None,
                surface,
                new[] { surface });

            using WindowFrameCaptureResult result =
                await fallback.CaptureAsync(
                    plan,
                    surface,
                    CancellationToken.None);

            Assert.False(result.Success);
            Assert.Equal(
                "capture_unavailable",
                result.ReasonCode);
            Assert.Equal(1, qualification.Calls);
        }

        [Fact]
        public void BlackAndOversizeFramesAreNeverAccepted()
        {
            using WindowFrameCaptureResult black =
                RecordingFrameSourceFactory.BlackFrame();
            Assert.False(CapturedFrameSafety.IsAcceptableBgra(
                black,
                out string blackReason));
            Assert.Equal("capture_unavailable", blackReason);

            int width = 2049;
            int height = 2048;
            using WindowFrameCaptureResult oversized =
                WindowFrameCaptureResult.Captured(
                    new byte[checked(width * height * 4)],
                    width,
                    height,
                    ObservationMode.WindowGraphicsCapture);
            Assert.False(CapturedFrameSafety.IsAcceptableBgra(
                oversized,
                out string sizeReason));
            Assert.Equal(
                "capture_object_too_large",
                sizeReason);
        }

        private static ObservationSurfacePlan Surface()
        {
            return new ObservationSurfacePlan(
                "target_capture_AAAAAAAAAAAAAAAAA",
                SurfaceKind.Flash,
                0x1234,
                101,
                new DateTimeOffset(
                    2026, 7, 30, 8, 0, 0, TimeSpan.Zero),
                Path.GetFullPath(
                    Path.Combine(
                        Path.GetTempPath(),
                        "cf7-observation-tests",
                        "capture-owner.exe")),
                0,
                1,
                1,
                1,
                1,
                null,
                null,
                Rect(10, 20, 400, 300),
                Rect(14, 50, 392, 266),
                Rect(20, 56, 380, 250),
                144,
                10,
                visible: true,
                minimized: false,
                active: true,
                observationModes: new[]
                {
                    ObservationMode.WindowGraphicsCapture,
                    ObservationMode.FlashSnapshotKeyframe
                });
        }

        private static PhysicalRect Rect(
            int x,
            int y,
            int width,
            int height)
        {
            return new PhysicalRect
            {
                X = x,
                Y = y,
                Width = width,
                Height = height
            };
        }

        private static ObservationSurfacePlan
            SurfaceForCurrentProcess(
                IntPtr window,
                Process process)
        {
            string executablePath = Path.GetFullPath(
                process.MainModule.FileName);
            return new ObservationSurfacePlan(
                "target_capture_real_AAAAAAAAAAAA",
                SurfaceKind.Flash,
                window.ToInt64(),
                process.Id,
                new DateTimeOffset(
                    process.StartTime.ToUniversalTime()),
                executablePath,
                0,
                1,
                1,
                1,
                1,
                null,
                null,
                Rect(40, 40, 330, 210),
                Rect(45, 65, 320, 180),
                Rect(45, 65, 320, 180),
                96,
                10,
                visible: true,
                minimized: false,
                active: true,
                observationModes: new[]
                {
                    ObservationMode.WindowGraphicsCapture
                });
        }

        private sealed class RecordingCaptureItemFactory
            : IGraphicsCaptureItemFactory
        {
            public int Calls { get; private set; }
            public IntPtr LastWindow { get; private set; }
            public RecordingCaptureItemHandle Handle { get; } =
                new RecordingCaptureItemHandle();

            public bool TryCreateForWindow(
                IntPtr windowHandle,
                out IGraphicsCaptureItemHandle captureItem,
                out string reasonCode)
            {
                Calls++;
                LastWindow = windowHandle;
                captureItem = Handle;
                reasonCode = null;
                return true;
            }
        }

        private sealed class AcceptingPreflight
            : IWindowCapturePreflight
        {
            public bool TryValidate(
                ObservationSurfacePlan surface,
                out string reasonCode)
            {
                reasonCode = null;
                return true;
            }
        }

        private sealed class RejectingPreflight
            : IWindowCapturePreflight
        {
            public bool TryValidate(
                ObservationSurfacePlan surface,
                out string reasonCode)
            {
                reasonCode = "target_not_authoritative";
                return false;
            }
        }

        private sealed class RecordingPixelProducer
            : IWgcPixelProducer
        {
            public int Calls { get; private set; }
            public IntPtr LastItem { get; private set; }

            public WindowFrameCaptureResult CaptureLatest(
                IGraphicsCaptureItemHandle captureItem,
                CancellationToken cancellationToken)
            {
                Calls++;
                LastItem = captureItem.AbiPointer;
                return WindowFrameCaptureResult.Captured(
                    new byte[]
                    {
                        20, 40, 200, 255,
                        20, 40, 200, 255,
                        20, 40, 200, 255,
                        20, 40, 200, 255
                    },
                    2,
                    2,
                    ObservationMode.WindowGraphicsCapture);
            }
        }

        private sealed class BlockingPixelProducer
            : IWgcPixelProducer
        {
            private readonly ManualResetEventSlim _entered;
            private readonly ManualResetEventSlim _release;

            public BlockingPixelProducer(
                ManualResetEventSlim entered,
                ManualResetEventSlim release)
            {
                _entered = entered;
                _release = release;
            }

            public byte[] ReturnedPixels { get; private set; }

            public WindowFrameCaptureResult CaptureLatest(
                IGraphicsCaptureItemHandle captureItem,
                CancellationToken cancellationToken)
            {
                _entered.Set();
                _release.Wait();
                ReturnedPixels = new byte[]
                {
                    20, 40, 200, 255
                };
                return WindowFrameCaptureResult.Captured(
                    ReturnedPixels,
                    1,
                    1,
                    ObservationMode.WindowGraphicsCapture);
            }
        }

        private sealed class RecordingCaptureItemHandle
            : IGraphicsCaptureItemHandle
        {
            public IntPtr AbiPointer
            {
                get { return new IntPtr(99); }
            }

            public bool Disposed { get; private set; }

            public void Dispose()
            {
                Disposed = true;
            }
        }

        private sealed class DeniedQualification
            : IFlashSnapshotQualification
        {
            public int Calls { get; private set; }

            public bool IsValidatedLocalKeyframeSource(
                ObservationCapturePlan plan,
                ObservationSurfacePlan surface,
                out string reasonCode)
            {
                Calls++;
                reasonCode =
                    "flash_snapshot_not_qualified";
                return false;
            }
        }
    }
}
