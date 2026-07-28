using System;
using System.Collections.Generic;
using System.Drawing;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class LayeredWindowCommitTests
    {
        [Fact]
        public void SuccessfulCommit_ReturnsMetrics_AndReleasesInNestedOrder()
        {
            FakeNativeApi native = new FakeNativeApi();
            using (Bitmap bitmap = new Bitmap(12, 7))
            {
                LayeredWindowCommitResult result = LayeredWindowCommitExecutor.Execute(
                    new IntPtr(1),
                    bitmap,
                    20,
                    30,
                    255,
                    native);

                Assert.True(result.Succeeded);
                Assert.Equal(LayeredWindowCommitError.None, result.Error);
                Assert.Equal("none", result.ErrorValue);
                Assert.Equal(12, result.Width);
                Assert.Equal(7, result.Height);
                Assert.Equal(84, result.PixelCount);
                Assert.Equal(336, result.ByteCount);
                Assert.Equal(20, result.ScreenX);
                Assert.Equal(30, result.ScreenY);
                Assert.True(result.ElapsedTicks >= 0);
                Assert.True(result.UpdateLayeredWindowTicks >= 0);
                Assert.Null(result.CleanupError);
            }

            Assert.Equal(
                new[]
                {
                    "acquire-screen",
                    "create-memory",
                    "create-bitmap",
                    "select-bitmap",
                    "update",
                    "restore-old",
                    "delete-bitmap",
                    "delete-memory",
                    "release-screen"
                },
                native.Calls);
        }

        [Fact]
        public void UpdateLayeredWindowFalse_IsStructuredFailure_AndStillCleansEverything()
        {
            FakeNativeApi native = new FakeNativeApi
            {
                UpdateSucceeds = false,
                LastError = 1400
            };
            using (Bitmap bitmap = new Bitmap(3, 5))
            {
                LayeredWindowCommitResult result = LayeredWindowCommitExecutor.Execute(
                    new IntPtr(1),
                    bitmap,
                    0,
                    0,
                    200,
                    native);

                Assert.False(result.Succeeded);
                Assert.Equal(
                    LayeredWindowCommitError.UpdateLayeredWindowFailed,
                    result.Error);
                Assert.Equal("update_layered_window_failed", result.ErrorValue);
                Assert.Equal(1400, result.NativeErrorCode);
                Assert.Equal("UpdateLayeredWindow returned false.", result.ErrorMessage);
            }

            Assert.Contains("restore-old", native.Calls);
            Assert.Contains("delete-bitmap", native.Calls);
            Assert.Contains("delete-memory", native.Calls);
            Assert.Contains("release-screen", native.Calls);
        }

        [Fact]
        public void BitmapHandleFault_ReleasesPreviouslyAcquiredDcs()
        {
            FakeNativeApi native = new FakeNativeApi
            {
                ThrowWhenCreatingBitmap = true
            };
            using (Bitmap bitmap = new Bitmap(2, 2))
            {
                LayeredWindowCommitResult result = LayeredWindowCommitExecutor.Execute(
                    new IntPtr(1),
                    bitmap,
                    0,
                    0,
                    255,
                    native);

                Assert.False(result.Succeeded);
                Assert.Equal(
                    LayeredWindowCommitError.BitmapHandleCreateFailed,
                    result.Error);
            }

            Assert.DoesNotContain("delete-bitmap", native.Calls);
            Assert.Contains("delete-memory", native.Calls);
            Assert.Contains("release-screen", native.Calls);
        }

        [Fact]
        public void CleanupFailure_IsNotReportedAsSuccess()
        {
            FakeNativeApi native = new FakeNativeApi
            {
                DeleteBitmapSucceeds = false,
                LastError = 6
            };
            using (Bitmap bitmap = new Bitmap(2, 2))
            {
                LayeredWindowCommitResult result = LayeredWindowCommitExecutor.Execute(
                    new IntPtr(1),
                    bitmap,
                    0,
                    0,
                    255,
                    native);

                Assert.False(result.Succeeded);
                Assert.Equal(LayeredWindowCommitError.CleanupFailed, result.Error);
                Assert.Equal(6, result.NativeErrorCode);
                Assert.Contains("DeleteObject", result.CleanupError);
            }
        }

        [Fact]
        public void RestoreFailure_DestroysMemoryDcBeforeDeletingBitmap()
        {
            FakeNativeApi native = new FakeNativeApi
            {
                RestoreSucceeds = false,
                LastError = 6
            };
            using (Bitmap bitmap = new Bitmap(2, 2))
            {
                LayeredWindowCommitResult result = LayeredWindowCommitExecutor.Execute(
                    new IntPtr(1),
                    bitmap,
                    0,
                    0,
                    255,
                    native);

                Assert.False(result.Succeeded);
                Assert.Equal(LayeredWindowCommitError.CleanupFailed, result.Error);
                Assert.Contains("SelectObject(restore)", result.CleanupError);
            }

            Assert.Equal(
                new[]
                {
                    "acquire-screen",
                    "create-memory",
                    "create-bitmap",
                    "select-bitmap",
                    "update",
                    "restore-old",
                    "delete-memory",
                    "delete-bitmap",
                    "release-screen"
                },
                native.Calls);
            Assert.False(native.BitmapHandleIsLive);
            Assert.False(native.MemoryDcIsLive);
        }

        [Fact]
        public void OperationalFailure_RemainsPrimary_WhenCleanupAlsoFails()
        {
            FakeNativeApi native = new FakeNativeApi
            {
                UpdateSucceeds = false,
                RestoreSucceeds = false,
                LastError = 1400
            };
            using (Bitmap bitmap = new Bitmap(2, 2))
            {
                LayeredWindowCommitResult result = LayeredWindowCommitExecutor.Execute(
                    new IntPtr(1),
                    bitmap,
                    0,
                    0,
                    255,
                    native);

                Assert.False(result.Succeeded);
                Assert.Equal(
                    LayeredWindowCommitError.UpdateLayeredWindowFailed,
                    result.Error);
                Assert.Equal(1400, result.NativeErrorCode);
                Assert.Contains("SelectObject(restore)", result.CleanupError);
            }
            Assert.False(native.BitmapHandleIsLive);
            Assert.False(native.MemoryDcIsLive);
        }

        [Fact]
        public void MissingWindowHandle_DoesNotAcquireNativeResources()
        {
            FakeNativeApi native = new FakeNativeApi();
            using (Bitmap bitmap = new Bitmap(2, 2))
            {
                LayeredWindowCommitResult result = LayeredWindowCommitExecutor.Execute(
                    IntPtr.Zero,
                    bitmap,
                    0,
                    0,
                    255,
                    native);

                Assert.False(result.Succeeded);
                Assert.Equal(
                    LayeredWindowCommitError.WindowHandleUnavailable,
                    result.Error);
            }
            Assert.Empty(native.Calls);
        }

        [Fact]
        public void ObserverSlot_IsDisabledByDefault_AndCanBeInstalledThenRemoved()
        {
            LayeredWindowCommitObserverSlot slot = new LayeredWindowCommitObserverSlot();
            RecordingObserver observer = new RecordingObserver();
            LayeredWindowCommitResult result = CreateResult();

            Assert.False(slot.IsEnabled);
            slot.Publish(result);
            Assert.Equal(0, observer.CallCount);

            slot.Set(observer);
            Assert.True(slot.IsEnabled);
            slot.Publish(result);
            Assert.Equal(1, observer.CallCount);
            Assert.Same(result, observer.LastResult);

            slot.Set(null);
            Assert.False(slot.IsEnabled);
            slot.Publish(result);
            Assert.Equal(1, observer.CallCount);
        }

        [Fact]
        public void ObserverSlot_ContainsObserverExceptions()
        {
            LayeredWindowCommitObserverSlot slot = new LayeredWindowCommitObserverSlot();
            slot.Set(new ThrowingObserver());

            Exception exception = Record.Exception(delegate
            {
                slot.Publish(CreateResult());
            });

            Assert.Null(exception);
        }

        private static LayeredWindowCommitResult CreateResult()
        {
            return new LayeredWindowCommitResult(
                true,
                1,
                2,
                3,
                4,
                255,
                1,
                1,
                LayeredWindowCommitError.None,
                0,
                null,
                null);
        }

        private sealed class RecordingObserver : ILayeredWindowCommitObserver
        {
            public int CallCount;
            public LayeredWindowCommitResult LastResult;

            public void OnCommit(LayeredWindowCommitResult result)
            {
                CallCount++;
                LastResult = result;
            }
        }

        private sealed class ThrowingObserver : ILayeredWindowCommitObserver
        {
            public void OnCommit(LayeredWindowCommitResult result)
            {
                throw new InvalidOperationException("synthetic observer failure");
            }
        }

        private sealed class FakeNativeApi : ILayeredWindowCommitNativeApi
        {
            private static readonly IntPtr ScreenDc = new IntPtr(11);
            private static readonly IntPtr MemoryDc = new IntPtr(22);
            private static readonly IntPtr BitmapHandle = new IntPtr(33);
            private static readonly IntPtr PreviousObject = new IntPtr(44);
            private int _selectCalls;

            public readonly List<string> Calls = new List<string>();
            public bool UpdateSucceeds = true;
            public bool DeleteBitmapSucceeds = true;
            public bool DeleteMemorySucceeds = true;
            public bool RestoreSucceeds = true;
            public bool ThrowWhenCreatingBitmap;
            public int LastError;
            public bool BitmapHandleIsLive;
            public bool MemoryDcIsLive;
            private bool _bitmapIsSelected;

            public IntPtr AcquireScreenDc()
            {
                Calls.Add("acquire-screen");
                return ScreenDc;
            }

            public int ReleaseScreenDc(IntPtr screenDc)
            {
                Assert.Equal(ScreenDc, screenDc);
                Calls.Add("release-screen");
                return 1;
            }

            public IntPtr CreateCompatibleDc(IntPtr screenDc)
            {
                Assert.Equal(ScreenDc, screenDc);
                Calls.Add("create-memory");
                MemoryDcIsLive = true;
                return MemoryDc;
            }

            public bool DeleteDc(IntPtr memoryDc)
            {
                Assert.Equal(MemoryDc, memoryDc);
                Calls.Add("delete-memory");
                if (!DeleteMemorySucceeds) return false;
                MemoryDcIsLive = false;
                _bitmapIsSelected = false;
                return true;
            }

            public IntPtr CreateBitmapHandle(Bitmap bitmap)
            {
                Calls.Add("create-bitmap");
                if (ThrowWhenCreatingBitmap)
                    throw new InvalidOperationException("synthetic bitmap failure");
                BitmapHandleIsLive = true;
                return BitmapHandle;
            }

            public bool DeleteObject(IntPtr handle)
            {
                Assert.Equal(BitmapHandle, handle);
                Calls.Add("delete-bitmap");
                Assert.False(
                    _bitmapIsSelected && MemoryDcIsLive,
                    "DeleteObject must not run while the bitmap is selected into a live DC.");
                if (!DeleteBitmapSucceeds) return false;
                BitmapHandleIsLive = false;
                return true;
            }

            public IntPtr SelectObject(IntPtr memoryDc, IntPtr handle)
            {
                Assert.Equal(MemoryDc, memoryDc);
                _selectCalls++;
                if (_selectCalls == 1)
                {
                    Assert.Equal(BitmapHandle, handle);
                    Calls.Add("select-bitmap");
                    _bitmapIsSelected = true;
                    return PreviousObject;
                }
                Assert.Equal(PreviousObject, handle);
                Calls.Add("restore-old");
                if (!RestoreSucceeds) return IntPtr.Zero;
                _bitmapIsSelected = false;
                return BitmapHandle;
            }

            public bool UpdateLayeredWindow(
                IntPtr windowHandle,
                IntPtr screenDc,
                IntPtr memoryDc,
                int screenX,
                int screenY,
                int width,
                int height,
                byte globalAlpha)
            {
                Assert.Equal(new IntPtr(1), windowHandle);
                Assert.Equal(ScreenDc, screenDc);
                Assert.Equal(MemoryDc, memoryDc);
                Calls.Add("update");
                return UpdateSucceeds;
            }

            public int GetLastError()
            {
                return LastError;
            }
        }
    }
}
