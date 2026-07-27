using System.Collections.Generic;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// SafeExitPanelWidget 状态机回归。
    ///
    /// 关键不变量（防 d6ef 引入的 sv-only 误显示回归）：
    /// 1. sv:1/2/3 不带 Arm() → Visible=false（普通自动存盘 / 商店关闭 / 升级路径不能弹面板）
    /// 2. SAFEEXIT click → Arm() → Visible=true，sv:1 显示 Saving，sv:2 切 Done
    /// 3. 取消按钮：本地 disarm + dismissed → 再次 Arm() 可正常重开
    /// 4. EXIT_CONFIRM click：由 widget 的 armed+Done capability exact-once 消费后退出
    /// 5. button-level Down/Up 匹配：down idx=0 + up idx=1 → 不触发任何分发
    /// 6. s:0 → Disarm 完整复位
    /// 7. sv:3 只暴露取消/重试，第二按钮绝不派发 EXIT_CONFIRM
    /// </summary>
    public class SafeExitPanelWidgetTests
    {
        private class Capture
        {
            public List<Keys> SentKeys = new List<Keys>();
            public List<string> Posts = new List<string>();
            public int Exit;
        }

        private static LauncherCommandRouter MakeRouter(Capture c)
        {
            return new LauncherCommandRouter(
                socketServer: null,
                onSendKey: k => c.SentKeys.Add(k),
                onToggleFullscreen: () => { },
                onToggleLog: () => { },
                onForceExit: () => c.Exit++,
                postToWeb: s => c.Posts.Add(s),
                onPanelStateChanged: b => { },
                setActivePanel: name => { });
        }

        private static SafeExitPanelWidget MakeWidget(out LauncherCommandRouter router, out Capture cap)
        {
            cap = new Capture();
            router = MakeRouter(cap);
            // Control 实例无需 handle；ScreenBounds 不参与本测试断言（用 Visible 间接判定）
            Control anchor = new Control();
            SafeExitPanelWidget w = new SafeExitPanelWidget(anchor, router);
            w.ForceGameReady(true);
            router.OnSafeExitArm = w.Arm;
            router.OnSafeExitSendFailed = w.FailAttempt;
            router.TryConsumeSafeExitConfirm =
                w.TryAuthorizeExitConfirm;
            return w;
        }

        private static IReadOnlyDictionary<string, string> Snapshot(params string[] kvPieces)
        {
            // pieces 形如 "sv:1" / "s:1"。key = ":" 前段；value = 整段（与 UiData 现有契约一致）。
            Dictionary<string, string> dict = new Dictionary<string, string>();
            foreach (string p in kvPieces)
            {
                int colon = p.IndexOf(':');
                string k = colon > 0 ? p.Substring(0, colon) : p;
                dict[k] = p;
            }
            return dict;
        }

        // ── HIGH 回归：sv-only 不能显示面板 ──
        [Fact]
        public void Sv1_WithoutArm_DoesNotShowPanel()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            // 模拟普通自动存盘：sv:1 直接来，没有 SAFEEXIT click 的 Arm
            w.OnUiDataChanged(Snapshot("sv:1"), new HashSet<string> { "sv" });
            Assert.False(w.Visible);
            Assert.False(w.IsArmed);
            Assert.True(w.IsSavingState); // 内部状态推进，但 visible 受 _armed 门控
        }

        [Fact]
        public void Sv2_WithoutArm_DoesNotShowPanel()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.OnUiDataChanged(Snapshot("sv:1"), new HashSet<string> { "sv" });
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });
            Assert.False(w.Visible);
            Assert.True(w.IsDoneState);
        }

        [Fact]
        public void PriorUnarmedSv2_ThenArm_StartsFreshSaving()
        {
            // 高优先级回归：普通存盘（自动存盘/商店关闭/升级）先把 unarmed widget 推到 Done。
            // 玩家随后点 SAFEEXIT，Arm() 必须强制复位到 Saving，
            // 否则 Visible 立刻显示「取消/退出」按钮，早于本次 safeExit 真正的 sv:1/2，存在数据丢失风险。
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            // 模拟普通商店关闭存盘：unarmed 状态下 sv:1 → sv:2 推达
            w.OnUiDataChanged(Snapshot("sv:1"), new HashSet<string> { "sv" });
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });
            Assert.False(w.Visible);
            Assert.True(w.IsDoneState); // 内部状态污染到 Done

            // 玩家点 SAFEEXIT
            w.Arm();
            Assert.True(w.Visible);
            Assert.True(w.IsArmed);
            Assert.True(w.IsSavingState); // 必须强制复位到 Saving
            Assert.False(w.IsDoneState);  // 不能保留旧 Done
        }

        // ── Arm 路径正常显示 ──
        [Fact]
        public void Arm_ThenSv1_ShowsSavingPanel()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            Assert.True(w.Visible);
            Assert.True(w.IsArmed);
            Assert.True(w.IsSavingState); // Arm() 立刻进 Saving 防 sv:1 race
            w.OnUiDataChanged(Snapshot("sv:1"), new HashSet<string> { "sv" });
            Assert.True(w.Visible);
            Assert.True(w.IsSavingState);
        }

        [Fact]
        public void Arm_ThenSv1Sv2_TransitionsToDone()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:1"), new HashSet<string> { "sv" });
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });
            Assert.True(w.Visible);
            Assert.True(w.IsDoneState);
        }

        [Fact]
        public void FailedRetry_CanRepeatSv1ToSv3WithoutExiting()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            int sends = 0;
            router.SetGameCommandSenderForTests(
                delegate
                {
                    sends++;
                    return true;
                });
            router.Dispatch("SAFEEXIT");
            w.OnUiDataChanged(Snapshot("sv:1"), new HashSet<string> { "sv" });
            w.OnUiDataChanged(Snapshot("sv:3"), new HashSet<string> { "sv" });

            Assert.True(w.Visible);
            Assert.True(w.IsFailedState);
            Assert.False(w.IsDoneState);
            Assert.False(w.WantsAnimationTick);

            w.InternalDownIndex = 1;
            SafeExitPanelWidget.ClickOutcome outcome = w.TryFireButtonClick(1);
            Assert.Equal(SafeExitPanelWidget.ClickOutcome.Retried, outcome);
            Assert.Equal(0, cap.Exit);
            Assert.True(w.IsArmed);
            Assert.True(w.IsSavingState);

            w.OnUiDataChanged(Snapshot("sv:1"), new HashSet<string> { "sv" });
            w.OnUiDataChanged(Snapshot("sv:3"), new HashSet<string> { "sv" });
            Assert.True(w.IsFailedState);

            w.InternalDownIndex = 1;
            outcome = w.TryFireButtonClick(1);
            Assert.Equal(SafeExitPanelWidget.ClickOutcome.Retried, outcome);
            Assert.True(w.IsSavingState);
            w.OnUiDataChanged(Snapshot("sv:1"), new HashSet<string> { "sv" });
            w.OnUiDataChanged(Snapshot("sv:3"), new HashSet<string> { "sv" });

            Assert.True(w.IsFailedState);
            Assert.Equal(3, sends);
            Assert.Equal(0, cap.Exit);
            Assert.Empty(cap.Posts);
        }

        [Fact]
        public void SafeExitSendFalseImmediatelyFailsNativeAndWebWithoutExiting()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w =
                MakeWidget(out router, out cap);
            int sends = 0;
            router.SetGameCommandSenderForTests(
                delegate
                {
                    sends++;
                    return false;
                });

            router.Dispatch("SAFEEXIT");

            Assert.Equal(1, sends);
            Assert.True(w.Visible);
            Assert.True(w.IsArmed);
            Assert.True(w.IsFailedState);
            Assert.False(w.IsSavingState);
            Assert.Equal(0, cap.Exit);
            Assert.Equal(
                "{\"type\":\"safe_exit_failed\"}",
                Assert.Single(cap.Posts));
        }

        [Fact]
        public void SafeExitSendThrowImmediatelyFailsNativeAndWebWithoutExiting()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w =
                MakeWidget(out router, out cap);
            int sends = 0;
            router.SetGameCommandSenderForTests(
                delegate
                {
                    sends++;
                    throw new System.InvalidOperationException(
                        "safe exit transport down");
                });

            router.Dispatch("SAFEEXIT");

            Assert.Equal(1, sends);
            Assert.True(w.Visible);
            Assert.True(w.IsArmed);
            Assert.True(w.IsFailedState);
            Assert.Equal(0, cap.Exit);
            Assert.Equal(
                "{\"type\":\"safe_exit_failed\"}",
                Assert.Single(cap.Posts));
        }

        [Fact]
        public void DoneRow_RightmostPixelStillHitsExitButton()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });

            Assert.Equal(1, w.HitButtonForTest(203, 16, new System.Drawing.Rectangle(0, 0, 204, 32)));
        }

        [Fact]
        public void DoneRow_AutoDismissesAfterFiveSecondsWithoutExiting()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });

            Assert.Equal(5000, SafeExitPanelWidget.DoneAutoDismissMsForTest);
            Assert.Equal(5000, w.DoneAutoDismissRemainingMsForTest);
            Assert.True(w.WantsAnimationTick);

            w.Tick(4999);
            Assert.True(w.Visible);
            Assert.Equal(0, cap.Exit);

            w.Tick(1);
            Assert.False(w.Visible);
            Assert.False(w.IsArmed);
            Assert.True(w.IsDismissed);
            Assert.False(w.IsDoneState);
            Assert.Equal(0, cap.Exit);
        }

        [Fact]
        public void DoneRow_ButtonHoverPausesAutoDismissUntilPointerLeaves()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });

            w.SetHoverForTest(1);
            Assert.False(w.WantsAnimationTick);
            w.Tick(5000);
            Assert.True(w.Visible);
            Assert.Equal(5000, w.DoneAutoDismissRemainingMsForTest);

            w.SetHoverForTest(-1);
            Assert.True(w.WantsAnimationTick);
            w.Tick(5000);
            Assert.False(w.Visible);
            Assert.Equal(0, cap.Exit);
        }

        // ── 取消 → 重开 ──
        [Fact]
        public void Cancel_DisarmsAndDismisses_ThenRearmRestores()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });
            // 模拟：down + up 都命中 EXIT_CANCEL (idx 0)
            w.InternalDownIndex = 0;
            SafeExitPanelWidget.ClickOutcome outcome = w.TryFireButtonClick(0);
            Assert.Equal(SafeExitPanelWidget.ClickOutcome.Cancelled, outcome);
            Assert.False(w.Visible);
            Assert.False(w.IsArmed);
            Assert.True(w.IsDismissed);
            Assert.Equal(0, cap.Exit); // 取消不应调 ForceExit

            // 重新 Arm 应该恢复显示
            w.Arm();
            Assert.True(w.Visible);
            Assert.False(w.IsDismissed);
        }

        // ── EXIT_CONFIRM dispatch ──
        [Fact]
        public void ExitConfirm_DispatchesAndDisarms()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });
            w.InternalDownIndex = 1; // EXIT_CONFIRM
            SafeExitPanelWidget.ClickOutcome outcome = w.TryFireButtonClick(1);
            Assert.Equal(SafeExitPanelWidget.ClickOutcome.Confirmed, outcome);
            Assert.False(w.IsArmed);
            Assert.Equal(1, cap.Exit);

            router.Dispatch("EXIT_CONFIRM");
            Assert.Equal(1, cap.Exit);
        }

        [Fact]
        public void RawExitConfirm_IsRejectedWhenUnarmedSavingOrFailed()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w =
                MakeWidget(out router, out cap);

            router.Dispatch("EXIT_CONFIRM");
            Assert.Equal(0, cap.Exit);

            w.Arm();
            router.Dispatch("EXIT_CONFIRM");
            Assert.Equal(0, cap.Exit);
            Assert.True(w.IsArmed);
            Assert.True(w.IsSavingState);

            w.FailAttempt();
            router.Dispatch("EXIT_CONFIRM");
            Assert.Equal(0, cap.Exit);
            Assert.True(w.IsArmed);
            Assert.True(w.IsFailedState);
        }

        [Fact]
        public void FallbackPacketAuthority_AllowsDoneConfirmExactlyOnce()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w =
                MakeWidget(out router, out cap);
            router.SetGameCommandSenderForTests(
                delegate { return true; });

            router.Dispatch("SAFEEXIT");
            w.HandleUiData(
                new UiDataPacket("s:1|sv:1"));
            Assert.True(w.IsSavingState);
            w.HandleUiData(
                new UiDataPacket("s:1|sv:2"));
            Assert.True(w.IsDoneState);

            router.Dispatch("EXIT_CONFIRM");
            router.Dispatch("EXIT_CONFIRM");

            Assert.Equal(1, cap.Exit);
            Assert.False(w.IsArmed);
        }

        // ── MED 回归：button-level Down/Up 必须匹配 ──
        [Fact]
        public void DownCancelUpExit_DoesNotTrigger()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });
            // 玩家按住 EXIT_CANCEL（idx 0）拖到 EXIT_CONFIRM（idx 1）松开
            w.InternalDownIndex = 0;
            SafeExitPanelWidget.ClickOutcome outcome = w.TryFireButtonClick(1);
            Assert.Equal(SafeExitPanelWidget.ClickOutcome.MismatchedDownUp, outcome);
            Assert.True(w.IsArmed); // 状态不变
            Assert.Equal(0, cap.Exit); // 不可触发退出
        }

        [Fact]
        public void DownExitUpCancel_DoesNotTrigger()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });
            w.InternalDownIndex = 1; // EXIT_CONFIRM
            SafeExitPanelWidget.ClickOutcome outcome = w.TryFireButtonClick(0); // 松开在 EXIT_CANCEL
            Assert.Equal(SafeExitPanelWidget.ClickOutcome.MismatchedDownUp, outcome);
            Assert.False(w.IsDismissed);
            Assert.True(w.IsArmed);
        }

        [Fact]
        public void NoDown_UpClick_DoesNotTrigger()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });
            // 按下不在 widget 内（_downIndex 默认 -1），松开命中 EXIT_CONFIRM
            SafeExitPanelWidget.ClickOutcome outcome = w.TryFireButtonClick(1);
            Assert.Equal(SafeExitPanelWidget.ClickOutcome.MismatchedDownUp, outcome);
            Assert.Equal(0, cap.Exit);
        }

        // ── s:0 完整复位 ──
        [Fact]
        public void GameNotReady_DisarmsAndResets()
        {
            LauncherCommandRouter router; Capture cap;
            SafeExitPanelWidget w = MakeWidget(out router, out cap);
            w.Arm();
            w.OnUiDataChanged(Snapshot("sv:2"), new HashSet<string> { "sv" });
            Assert.True(w.Visible);
            // 游戏切到未就绪
            w.OnUiDataChanged(Snapshot("s:0"), new HashSet<string> { "s" });
            Assert.False(w.Visible);
            Assert.False(w.IsArmed);
            Assert.False(w.IsDoneState);
            Assert.False(w.IsSavingState);
        }

        // ── 解析 helper（保留旧覆盖） ──
        [Theory]
        [InlineData("sv:1", 1)]
        [InlineData("sv:2", 2)]
        [InlineData("sv:3", 3)]
        [InlineData("sv:0", 0)]
        [InlineData("1", 1)]
        [InlineData("", 0)]
        [InlineData(null, 0)]
        public void ParseSv_PrefixedAndBare(string input, int expected)
        {
            Assert.Equal(expected, UiValueParser.ParseUiIntValue(input, 0));
        }
    }
}
