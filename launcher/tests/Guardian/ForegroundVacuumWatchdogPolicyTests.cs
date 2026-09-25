using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// A0.2 — NULL 前台看门狗的资格收窄：真空保留观察，恢复只在资格仍有效时发生。
    /// 核心不变量：NULL 真空持续时间本身不构成资格；无资格时策略永不给出 Restore。
    /// </summary>
    public sealed class ForegroundVacuumWatchdogPolicyTests
    {
        private const SessionForegroundOwnership Null =
            SessionForegroundOwnership.Null;
        private const SessionForegroundOwnership Session =
            SessionForegroundOwnership.Session;
        private const SessionForegroundOwnership External =
            SessionForegroundOwnership.External;

        private static ForegroundVacuumWatchdogPolicy.Decision Tick(
            ForegroundVacuumWatchdogPolicy policy,
            SessionForegroundOwnership foreground,
            int nowTick)
        {
            return policy.OnForegroundTick(foreground, nowTick);
        }

        [Fact]
        public void VacuumWithoutAnyClaimNeverRestores()
        {
            // 从未观察到用户返回/会话前台：NULL 持续多久都不产生资格。
            var policy = new ForegroundVacuumWatchdogPolicy();
            Assert.False(policy.IsRestoreEligible);

            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1000));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Observe,
                Tick(policy, Null, 1400));
            for (int i = 0; i < 20; i++)
            {
                ForegroundVacuumWatchdogPolicy.Decision d =
                    Tick(policy, Null, 1800 + i * 400);
                Assert.NotEqual(ForegroundVacuumWatchdogPolicy.Decision.Restore, d);
            }
        }

        [Fact]
        public void LiveUserReturnClaimAllowsRestoreAfterConfirmedVacuum()
        {
            var policy = new ForegroundVacuumWatchdogPolicy();
            policy.OnSessionActivated();
            Assert.True(policy.IsRestoreEligible);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.ClaimSource.SessionActivation,
                policy.LastClaimSource);

            // 单帧 NULL 只是交接竞态，不动作；第二次连续命中确认真空 → 恢复。
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1000));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, 1400));
        }

        [Fact]
        public void SessionForegroundSampleKeepsInSessionHandoffClaimAlive()
        {
            // 会话内交接途经自己的窗口（overlay/宿主/Flash 根）即维持资格。
            var policy = new ForegroundVacuumWatchdogPolicy();
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Session, 1000));
            Assert.True(policy.IsRestoreEligible);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.ClaimSource.SessionForeground,
                policy.LastClaimSource);

            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1400));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, 1800));
        }

        [Fact]
        public void ExternalForegroundObservationRevokesUntilNextActivation()
        {
            var policy = new ForegroundVacuumWatchdogPolicy();
            policy.OnSessionActivated();

            // 用户切到真实外部程序：资格立刻失效。
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, External, 1000));
            Assert.False(policy.IsRestoreEligible);

            // 外部窗口随后消失 → NULL 真空：仍无资格，仅观察、不恢复。
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1400));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Observe,
                Tick(policy, Null, 1800));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 2200));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Observe,
                Tick(policy, Null, 3800));

            // 下一次合法激活（用户返回）重建资格；节流仍按 2s 输出窗生效。
            policy.OnSessionActivated();
            Assert.True(policy.IsRestoreEligible);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 4200));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 4600));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, 5800));
        }

        [Fact]
        public void NullSamplesAreNeutralNeitherGrantNorRevoke()
        {
            var policy = new ForegroundVacuumWatchdogPolicy();
            policy.OnSessionActivated();
            // 有资格时真空不撤销资格（但有节流的输出节奏）。
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1000));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, 1400));
            Assert.True(policy.IsRestoreEligible);
        }

        [Fact]
        public void SuppressedTicksResetVacuumStreak()
        {
            var policy = new ForegroundVacuumWatchdogPolicy();
            policy.OnSessionActivated();

            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1000));
            // 抑制 tick（锁屏/最小化/面板模式）清零计数并撤销资格——
            // 穿越抑制边界后真空确认与资格都须重建。
            policy.OnSuppressedTick();
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1400));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Observe,
                Tick(policy, Null, 1800));
        }

        [Fact]
        public void SuppressedBoundaryRevokesEligibilityUntilReestablished()
        {
            // 审查反例：激活 → 抑制段 → 连续 NULL 不得恢复（无新的用户返回动作）。
            var policy = new ForegroundVacuumWatchdogPolicy();
            policy.OnSessionActivated();
            policy.OnSuppressedTick();
            Assert.False(policy.IsRestoreEligible);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1000));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Observe,
                Tick(policy, Null, 1400));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1800));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Observe,
                Tick(policy, Null, 3400));

            // 解除抑制后采样到本会话前台（用户确在会话内）→ 资格重建，可恢复。
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Session, 4200));
            Assert.True(policy.IsRestoreEligible);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 4600));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 5000));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, 6600));
        }

        [Fact]
        public void DeactivationRevokesEligibilityUntilNextActivation()
        {
            // 用户切走（WM_ACTIVATEAPP(false)）后外部程序退出留下真空：无新返回，不恢复。
            var policy = new ForegroundVacuumWatchdogPolicy();
            policy.OnSessionActivated();
            Assert.True(policy.IsRestoreEligible);
            policy.OnSessionDeactivated();
            Assert.False(policy.IsRestoreEligible);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.ClaimSource.None,
                policy.LastClaimSource);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1000));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Observe,
                Tick(policy, Null, 1400));
        }

        [Fact]
        public void EmissionsAreThrottledForBothRestoreAndObserve()
        {
            var policy = new ForegroundVacuumWatchdogPolicy();
            policy.OnSessionActivated();
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 0));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, 400));
            // 节流窗内持续真空不再输出。
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 800));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1200));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 2000));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, 2400));

            var ineligible = new ForegroundVacuumWatchdogPolicy();
            Tick(ineligible, External, 0);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(ineligible, Null, 400));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Observe,
                Tick(ineligible, Null, 800));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(ineligible, Null, 1200));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Observe,
                Tick(ineligible, Null, 2800));
        }

        [Fact]
        public void RecheckBeforeExecuteRespectsLateExternalSwitch()
        {
            // R1 RCE-3：有资格且真空确认后策略判 Restore；执行前外部窗口先拿到前台，
            // 执行器必须放弃本次恢复。
            var policy = new ForegroundVacuumWatchdogPolicy();
            policy.OnSessionActivated();
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, 1000));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, 1400));

            // 决策与执行之间：外部切换到达 → 复核失败，不得执行恢复。
            Assert.False(policy.RecheckEligibility(External));
            // NULL 中性不回摆：复核后的撤销保持有效。
            Assert.False(policy.RecheckEligibility(Null));

            // 对照：复核采样仍是本会话前台 → 恢复资格保持。
            var granted = new ForegroundVacuumWatchdogPolicy();
            granted.OnSessionActivated();
            Tick(granted, Null, 1000);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(granted, Null, 1400));
            Assert.True(granted.RecheckEligibility(Session));
        }

        [Fact]
        public void TickCountWraparoundDoesNotDeadlockThrottle()
        {
            var policy = new ForegroundVacuumWatchdogPolicy();
            policy.OnSessionActivated();
            int t0 = int.MaxValue - 100;
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, t0));
            // TickCount 翻转到负值后，节流比较用 unchecked 差值仍正确。
            int t1 = unchecked(t0 + 400);
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, t1));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Skip,
                Tick(policy, Null, unchecked(t1 + 400)));
            Assert.Equal(
                ForegroundVacuumWatchdogPolicy.Decision.Restore,
                Tick(policy, Null, unchecked(t1 + 2000)));
        }
    }
}
