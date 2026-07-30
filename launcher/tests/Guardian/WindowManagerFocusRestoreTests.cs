using System;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class WindowManagerFocusRestoreTests
    {
        private static readonly IntPtr Flash =
            new IntPtr(0x1001);
        private static readonly IntPtr FlashRoot =
            new IntPtr(0x1000);
        private static readonly IntPtr GuardianIndicator =
            new IntPtr(0x2001);

        [Fact]
        public void ExactFlashRootCanSatisfyPinnedRestore()
        {
            var api = new FakeFocusApi
            {
                Foreground = GuardianIndicator,
                Root = FlashRoot,
                Focused = Flash,
                SetForegroundResult = true,
                ForegroundAfterSet = FlashRoot
            };
            var manager = new WindowManager(api, Flash);

            bool restored = manager.RestoreFlashInputFocus(
                "test_exact_root",
                Flash);

            Assert.True(restored);
        }

        [Fact]
        public void SetForegroundFailureNeverReportsSuccess()
        {
            var api = new FakeFocusApi
            {
                Foreground = FlashRoot,
                Root = FlashRoot,
                SetForegroundResult = false,
                ForegroundAfterSet = FlashRoot
            };
            var manager = new WindowManager(api, Flash);

            bool restored = manager.RestoreFlashInputFocus(
                "test_set_foreground_failure",
                Flash);

            Assert.False(restored);
            Assert.Equal(2, api.SetForegroundCallCount);
        }

        [Fact]
        public void GuardianIndicatorForegroundIsNotAccepted()
        {
            var api = new FakeFocusApi
            {
                Foreground = GuardianIndicator,
                Root = FlashRoot,
                SetForegroundResult = true,
                ForegroundAfterSet = GuardianIndicator
            };
            var manager = new WindowManager(api, Flash);

            bool restored = manager.RestoreFlashInputFocus(
                "test_indicator_foreground",
                Flash);

            Assert.False(restored);
        }

        [Fact]
        public void OtherGuardianChildInSharedRootIsNotAccepted()
        {
            var otherGuardianChild = new IntPtr(0x2002);
            var api = new FakeFocusApi
            {
                Foreground = GuardianIndicator,
                Root = FlashRoot,
                Focused = otherGuardianChild,
                SetForegroundResult = true,
                ForegroundAfterSet = FlashRoot
            };
            var manager = new WindowManager(api, Flash);

            bool restored = manager.RestoreFlashInputFocus(
                "test_other_guardian_child",
                Flash);

            Assert.False(restored);
        }

        [Fact]
        public void TrackedHwndChangeDuringRestoreCannotSucceed()
        {
            WindowManager manager = null;
            var api = new FakeFocusApi
            {
                Foreground = GuardianIndicator,
                Root = FlashRoot,
                SetForegroundResult = true,
                ForegroundAfterSet = Flash
            };
            api.AfterSetForeground =
                delegate { manager.ResetEmbedState(); };
            manager = new WindowManager(api, Flash);

            bool restored = manager.RestoreFlashInputFocus(
                "test_hwnd_reuse",
                Flash);

            Assert.False(restored);
        }

        private sealed class FakeFocusApi
            : IFlashFocusWindowApi
        {
            internal IntPtr Foreground { get; set; }
            internal IntPtr ForegroundAfterSet { get; set; }
            internal IntPtr Root { get; set; }
            internal IntPtr Focused { get; set; }
            internal bool SetForegroundResult { get; set; }
            internal Action AfterSetForeground { get; set; }
            internal int SetForegroundCallCount { get; private set; }

            public IntPtr GetForegroundWindow()
            {
                return Foreground;
            }

            public uint GetWindowThreadProcessId(
                IntPtr windowHandle,
                out uint processId)
            {
                processId = 200;
                return 43;
            }

            public bool SetForegroundWindow(
                IntPtr windowHandle)
            {
                SetForegroundCallCount++;
                Foreground = ForegroundAfterSet;
                AfterSetForeground?.Invoke();
                return SetForegroundResult;
            }

            public bool AttachThreadInput(
                uint attachThreadId,
                uint attachToThreadId,
                bool attach)
            {
                return true;
            }

            public IntPtr SetFocus(IntPtr windowHandle)
            {
                return windowHandle;
            }

            public uint GetCurrentThreadId()
            {
                return 42;
            }

            public bool IsWindow(IntPtr windowHandle)
            {
                return windowHandle != IntPtr.Zero;
            }

            public IntPtr GetRootWindow(IntPtr windowHandle)
            {
                return Root;
            }

            public IntPtr GetFocusedWindow(
                IntPtr windowHandle)
            {
                return Focused;
            }

            public bool IsChild(
                IntPtr parentWindow,
                IntPtr candidateChild)
            {
                return parentWindow == Flash
                    && candidateChild == Focused
                    && candidateChild != GuardianIndicator
                    && candidateChild != new IntPtr(0x2002);
            }
        }
    }
}
