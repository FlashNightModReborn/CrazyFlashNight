using CF7Launcher.Tests.Guardian;
using System;
using System.Collections.Generic;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    [ResourceCaseGuard]
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
            Assert.Equal(IntPtr.Zero, api.LastFocusTarget);
            Assert.Equal(1, api.SetForegroundCallCount);
            Assert.Equal(0, api.AttachCallCount);
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
        [Fact] public void EligibilityCallbackCannotRetireTargetAndStillPermitFocus()
        {
            var api = new FakeFocusApi { Root = FlashRoot };
            var manager = new WindowManager(api, Flash);
            Assert.False(manager.RestoreFlashInputFocus("claim_reentry", () => {
                manager.ResetEmbedState(); return true;
            }));
            Assert.Equal(0, api.SetForegroundCallCount);
            Assert.Equal(0, api.SetFocusCallCount);
            Assert.Equal(0, api.AttachCallCount);
        }

        [Fact] public void FallbackThreadQueryRetiringTargetCannotAttach()
        {
            var api = new FakeFocusApi { Root = FlashRoot, ForegroundAfterSet = GuardianIndicator };
            var manager = new WindowManager(api, Flash);
            api.AfterGetThread = manager.ResetEmbedState;
            Assert.False(manager.RestoreFlashInputFocus("thread_query_retirement", Flash));
            Assert.Equal(1, api.SetFocusCallCount);
            Assert.Equal(0, api.AttachCallCount);
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void RetirementDuringAttachStillAttemptsDetachWithoutLaterFocus(bool detachResult)
        {
            var api = new FakeFocusApi { Root = FlashRoot, ForegroundAfterSet = GuardianIndicator,
                DetachResult = detachResult };
            var manager = new WindowManager(api, Flash);
            api.AfterAttach = manager.ResetEmbedState;
            Assert.False(manager.RestoreFlashInputFocus("attach_retirement", Flash));
            Assert.Equal(1, api.SetForegroundCallCount);
            Assert.Equal(1, api.SetFocusCallCount);
            Assert.Equal(2, api.AttachCallCount);
            Assert.Equal(new[] { (42u, 43u, true), (42u, 43u, false) }, api.AttachArguments);
        }

        [Fact] public void SuccessfulAttachFollowedByEligibilityRevocationDetachesExactPair()
        {
            bool eligible=true;
            var api=new FakeFocusApi {Root=FlashRoot,ForegroundAfterSet=GuardianIndicator};
            var manager=new WindowManager(api,Flash);api.AfterAttach=()=>eligible=false;
            Assert.False(manager.RestoreFlashInputFocus("recheck_revoke",()=>eligible));
            Assert.Equal(new[]{(42u,43u,true),(42u,43u,false)},api.AttachArguments);
            Assert.Equal(1,api.SetForegroundCallCount);Assert.Equal(1,api.SetFocusCallCount);
            Console.WriteLine("F01 revoke exact ordered calls: "+string.Join(";",api.AttachArguments));
        }
        [Fact] public void EligibilityCallbackThrowAfterSuccessfulAttachStillDetachesExactPair()
        {
            var api=new FakeFocusApi {Root=FlashRoot,ForegroundAfterSet=GuardianIndicator};
            var manager=new WindowManager(api,Flash);
            Assert.Throws<InvalidOperationException>(()=>manager.RestoreFlashInputFocus("recheck_callback_throw",()=>{
                if(api.AttachArguments.Count>0)throw new InvalidOperationException("owned eligibility callback");return true;}));
            Assert.Equal(new[]{(42u,43u,true),(42u,43u,false)},api.AttachArguments);
            Assert.Equal(1,api.SetForegroundCallCount);Assert.Equal(1,api.SetFocusCallCount);
            Console.WriteLine("F01 callback exception cleanup: "+string.Join(";",api.AttachArguments));
        }
        [Theory][InlineData(false)][InlineData(true)]
        public void DetachFailureRetainsSpecificDiagnosticAndExactPair(bool throws)
        {
            var logs=new List<string>();LogManager.SetSink(logs.Add);
            try{
                var api=new FakeFocusApi {Root=FlashRoot,ForegroundAfterSet=GuardianIndicator,DetachResult=false,ThrowOnDetach=throws};
                var manager=new WindowManager(api,Flash);api.AfterAttach=manager.ResetEmbedState;
                manager.RestoreFlashInputFocus("recheck_detach_failed",Flash);
                Assert.Equal(new[]{(42u,43u,true),(42u,43u,false)},api.AttachArguments);
                foreach(string line in logs)Console.WriteLine(line);
                Assert.Contains(logs,x=>throws?x.Contains("DETACH FAILED"):x.Contains("detach returned false"));
            }finally{LogManager.ResetSink();}
        }
        private static WindowManager CloseManager(FakeFocusApi api)
        {
            api.ProcessId=(uint)System.Diagnostics.Process.GetCurrentProcess().Id;
            var manager=new WindowManager(api,Flash);
            typeof(WindowManager).GetField("_registeredFocusProcess",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)
                .SetValue(manager,System.Diagnostics.Process.GetCurrentProcess());
            return manager;
        }
        [Fact] public void ClosePermitHasOneRootAttemptAndTailUsesOnlyInnerFocusAfterSourceRetires()
        {
            var api=new FakeFocusApi { Foreground=GuardianIndicator,Root=FlashRoot,Focused=GuardianIndicator,
                SetForegroundResult=true,ForegroundAfterSet=FlashRoot };
            api.AfterSetFocus=()=>api.Focused=Flash;
            var manager=CloseManager(api); var target=manager.CaptureFlashFocusTarget();
            bool sourceAlive=true, successor=false;
            var context=new HostCloseContext(new EndpointLease(null,null,null,"help","A","host",1,1,1,IntPtr.Zero),
                NativeCloseCause.PageClose,new Newtonsoft.Json.Linq.JObject(),IntPtr.Zero);
            var permit=new FocusPermit(context,()=>!successor && (context.SourceRetired || sourceAlive),target);
            Assert.True(permit.EnterLive());
            permit.RootVerified=manager.HandoffFlashFocusOnce("close",GuardianIndicator,target,permit.Eligible);
            Assert.True(permit.RootVerified); context.SourceRetired=true; sourceAlive=false; api.Focused=GuardianIndicator;
            Assert.True(permit.EnterTail()); Assert.True(manager.RestoreFlashInnerFocusOnce("tail",target,permit.Eligible));
            Assert.False(permit.EnterTail()); Assert.Equal(1,api.SetForegroundCallCount); Assert.Equal(2,api.SetFocusCallCount);
            Assert.Equal(new[] {(42u,43u,true),(42u,43u,false),(42u,43u,true),(42u,43u,false)},api.AttachArguments);
            permit.Complete(); Assert.False(permit.Eligible());
        }
        [Fact] public void TailLosesPermissionWhenAnotherOwnerOrForeignForegroundArrives()
        {
            var api=new FakeFocusApi { Foreground=GuardianIndicator,Root=FlashRoot,Focused=Flash,
                SetForegroundResult=true,ForegroundAfterSet=FlashRoot };
            var manager=CloseManager(api); var target=manager.CaptureFlashFocusTarget(); bool owner=true;
            var context=new HostCloseContext(new EndpointLease(null,null,null,"help","A","host",1,1,1,IntPtr.Zero),
                NativeCloseCause.PageClose,new Newtonsoft.Json.Linq.JObject(),IntPtr.Zero);
            var permit=new FocusPermit(context,()=>owner,target); Assert.True(permit.EnterLive());
            permit.RootVerified=manager.HandoffFlashFocusOnce("close",GuardianIndicator,target,permit.Eligible);
            context.SourceRetired=true; owner=false; Assert.False(permit.EnterTail()); owner=true; Assert.False(permit.Eligible());
            api.Foreground=new IntPtr(0x9999);
            Assert.False(manager.RestoreFlashInnerFocusOnce("tail",target,()=>true));
            Assert.Equal(1,api.SetForegroundCallCount); Assert.Equal(0,api.SetFocusCallCount);
        }
        [Fact] public void CloseAttachRevocationStillDetachesExactPair()
        {
            var api=new FakeFocusApi { Foreground=FlashRoot,Root=FlashRoot,Focused=GuardianIndicator };
            var manager=CloseManager(api); var target=manager.CaptureFlashFocusTarget(); bool eligible=true;
            api.AfterAttach=()=>eligible=false;
            Assert.False(manager.RestoreFlashInnerFocusOnce("tail",target,()=>eligible));
            Assert.Equal(0,api.SetFocusCallCount); Assert.Equal(new[] {(42u,43u,true),(42u,43u,false)},api.AttachArguments);
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
            internal Action AfterGetThread { get; set; }
            internal Action AfterAttach { get; set; }
            internal Action AfterSetFocus { get; set; }
            internal uint ProcessId=200;
            internal bool ThrowOnDetach;
            internal bool DetachResult { get; set; } = true;
            internal int SetFocusCallCount { get; private set; }
            internal int SetForegroundCallCount { get; private set; }
            internal IntPtr LastForegroundTarget { get; private set; }
            internal IntPtr LastFocusTarget { get; private set; }
            internal int AttachCallCount { get; private set; }
            internal List<(uint from, uint to, bool attach)> AttachArguments = new List<(uint,uint,bool)>();

            public IntPtr GetForegroundWindow()
            {
                return Foreground;
            }

            public uint GetWindowThreadProcessId(
                IntPtr windowHandle,
                out uint processId)
            {
                processId = ProcessId;
                AfterGetThread?.Invoke();
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
                AttachArguments.Add((attachThreadId, attachToThreadId, attach));
                AttachCallCount++;
                if (attach) AfterAttach?.Invoke();
                if (!attach && ThrowOnDetach) throw new InvalidOperationException("owned detach failure");
                return attach || DetachResult;
            }

            public IntPtr SetFocus(IntPtr windowHandle)
            {
                SetFocusCallCount++;
                LastFocusTarget = windowHandle;
                AfterSetFocus?.Invoke();
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
