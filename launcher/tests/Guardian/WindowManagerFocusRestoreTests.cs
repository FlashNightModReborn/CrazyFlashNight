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
        public void PublicRestoreReportsFailureWhenRootMatchesButInnerFocusIsWrong()
        {
            // A0.2 反例：前台根已匹配（fg=FlashRoot）但 Flash 线程的 hwndFocus
            // 落在非 Flash 子窗口——旧谓词（普通路径不查内部焦点）会误报成功。
            var api = new FakeFocusApi
            {
                Foreground = GuardianIndicator,
                Root = FlashRoot,
                Focused = GuardianIndicator,
                SetForegroundResult = true,
                ForegroundAfterSet = FlashRoot
            };
            var manager = new WindowManager(api, Flash);

            bool restored = manager.RestoreFlashInputFocus(
                "test_public_root_ok_inner_wrong");

            Assert.False(restored);
            Assert.Equal(2, api.SetForegroundCallCount);
        }

        [Fact]
        public void PublicRestoreReportsFailureWhenInnerFocusIsNone()
        {
            var api = new FakeFocusApi
            {
                Foreground = GuardianIndicator,
                Root = FlashRoot,
                Focused = IntPtr.Zero,
                SetForegroundResult = true,
                ForegroundAfterSet = FlashRoot
            };
            var manager = new WindowManager(api, Flash);

            Assert.False(manager.RestoreFlashInputFocus("test_public_inner_none"));
        }

        [Fact]
        public void PublicRestoreSucceedsWhenRootAndInnerFocusBothHeld()
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

            Assert.True(manager.RestoreFlashInputFocus("test_public_inner_ok"));
            Assert.Equal(1, api.SetForegroundCallCount);
        }

        [Fact]
        public void InnerFocusOnFlashChildCountsAsHeld()
        {
            var flashChild = new IntPtr(0x1002);
            var api = new FakeFocusApi
            {
                Foreground = GuardianIndicator,
                Root = FlashRoot,
                Focused = flashChild,
                SetForegroundResult = true,
                ForegroundAfterSet = FlashRoot
            };
            var manager = new WindowManager(api, Flash);

            Assert.True(manager.RestoreFlashInputFocus("test_inner_flash_child"));
        }

        [Fact]
        public void PublicRestoreToleratesSpuriousSetForegroundReturnFalse()
        {
            // 既有语义防回归：SFW 返回 false 但根匹配与内部焦点均成立时仍算成功。
            var api = new FakeFocusApi
            {
                Foreground = GuardianIndicator,
                Root = FlashRoot,
                Focused = Flash,
                SetForegroundResult = false,
                ForegroundAfterSet = FlashRoot
            };
            var manager = new WindowManager(api, Flash);

            Assert.True(manager.RestoreFlashInputFocus("test_sfw_false_but_held"));
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

        [Fact]
        public void BeforeHideHandoffActivatesExactRootAndKeepsFocusInFlash()
        {
            var panel = new IntPtr(0x3000);
            var api = new FakeFocusApi { Foreground = panel, Root = FlashRoot, Focused = Flash,
                SetForegroundResult = true, ForegroundAfterSet = FlashRoot };
            var manager = new WindowManager(api, Flash);
            Assert.True(manager.HandoffFlashFocusBeforePanelHide("panel_close:before_hide:stage-select", panel));
            Assert.Equal(FlashRoot, api.LastForegroundTarget);
            Assert.Equal(Flash, api.LastFocusTarget);
            Assert.Equal(1, api.SetForegroundCallCount);
            Assert.Equal(0, api.AttachCallCount);
            Assert.Equal(FlashRoot, api.Foreground);
        }

        [Fact]
        public void BeforeHideHandoffDoesNotReportSuccessWhenKeyboardFocusRemainsElsewhere()
        {
            var panel = new IntPtr(0x3000);
            var api = new FakeFocusApi { Foreground = panel, Root = FlashRoot, Focused = GuardianIndicator,
                SetForegroundResult = true, ForegroundAfterSet = FlashRoot };
            var manager = new WindowManager(api, Flash);
            Assert.False(manager.HandoffFlashFocusBeforePanelHide("handoff_wrong_focus", panel));
            Assert.Equal(FlashRoot, api.Foreground);
            Assert.Equal(Flash, api.LastFocusTarget);
            Assert.Equal(1, api.SetForegroundCallCount);
            Assert.Equal(0, api.AttachCallCount);
        }

        [Fact]
        public void BeforeHideHandoffDoesNothingIfForegroundChangedSinceCapture()
        {
            var api = new FakeFocusApi { Foreground = GuardianIndicator, Root = FlashRoot };
            var manager = new WindowManager(api, Flash);
            Assert.False(manager.HandoffFlashFocusBeforePanelHide("external_switch", new IntPtr(0x3000)));
            Assert.Equal(0, api.SetForegroundCallCount);
            Assert.Equal(IntPtr.Zero, api.LastFocusTarget);
            Assert.Equal(0, api.AttachCallCount);
        }

        [Theory]
        [InlineData(false, false)]
        [InlineData(true, false)]
        [InlineData(true, true)]
        public void BeforeHideHandoffNeverRetriesOrSetsFocusAfterLostActivation(bool activated, bool replaceFlash)
        {
            var panel = new IntPtr(0x3000);
            var api = new FakeFocusApi { Foreground = panel, Root = FlashRoot,
                SetForegroundResult = activated,
                ForegroundAfterSet = replaceFlash ? FlashRoot : GuardianIndicator };
            var manager = new WindowManager(api, Flash);
            if (replaceFlash) api.AfterSetForeground = manager.ResetEmbedState;
            Assert.False(manager.HandoffFlashFocusBeforePanelHide("handoff_race", panel));
            Assert.Equal(1, api.SetForegroundCallCount);
            Assert.Equal(IntPtr.Zero, api.LastFocusTarget);
            Assert.Equal(0, api.AttachCallCount);
        }

        [Fact] public void ExecutionClaimRevokedDuringFirstAttemptPreventsFocusAndFallback()
        {
            bool eligible=true;
            var api=new FakeFocusApi { Root=FlashRoot,ForegroundAfterSet=GuardianIndicator,AfterSetForeground=()=>eligible=false };
            var manager=new WindowManager(api,Flash);
            Assert.False(manager.RestoreFlashInputFocus("late_claim",()=>eligible));
            Assert.Equal(1,api.SetForegroundCallCount);
            Assert.Equal(IntPtr.Zero,api.LastFocusTarget);Assert.Equal(0,api.AttachCallCount);
        }
        [Fact] public void MissingExecutionClaimMakesNoFocusCalls()
        {
            var api=new FakeFocusApi { Root=FlashRoot };var manager=new WindowManager(api,Flash);
            Assert.False(manager.RestoreFlashInputFocus("no_claim",()=>false));
            Assert.Equal(0,api.SetForegroundCallCount);Assert.Equal(IntPtr.Zero,api.LastFocusTarget);
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
            internal IntPtr LastForegroundTarget { get; private set; }
            internal IntPtr LastFocusTarget { get; private set; }
            internal int AttachCallCount { get; private set; }

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
                LastForegroundTarget = windowHandle;
                Foreground = ForegroundAfterSet;
                AfterSetForeground?.Invoke();
                return SetForegroundResult;
            }

            public bool AttachThreadInput(
                uint attachThreadId,
                uint attachToThreadId,
                bool attach)
            {
                AttachCallCount++;
                return true;
            }

            public IntPtr SetFocus(IntPtr windowHandle)
            {
                LastFocusTarget = windowHandle;
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
