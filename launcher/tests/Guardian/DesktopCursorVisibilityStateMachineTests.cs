// CF7:ME — DesktopCursorOverlay.ResolveTargetVisibility 单测（C# 5）
// 单一可见性状态机的 entry function；生产代码 SetCursorVisible / SetForceHidden /
// UpdateCursorPosition 都通过此函数推导目标状态，单测覆盖 = 生产路径覆盖。
//
// 优先级（从高到低）：
//   1. GameForced      ← SetForceHidden(true)
//   2. CallerOff       ← SetCursorVisible(false)
//   3. Active          ← wantActiveSignal && hasPosition
//   4. Hidden          ← !hasPosition
//   5. prev (Active/Idle 保持) ← 否则保持
//
// 桥接函数 ResolveTargetVisibilityForTest 用 string 命名 enum，避免 internal 暴露。

using Xunit;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tests.Guardian
{
    public class DesktopCursorVisibilityStateMachineTests
    {
        private static string Resolve(string prev, bool callerOff, bool gameForce, bool hasPos, bool wantActive)
        {
            return DesktopCursorOverlay.ResolveTargetVisibilityForTest(
                prev, callerOff, gameForce, hasPos, wantActive);
        }

        // ── 优先级 1: GameForced 覆盖一切 ────────────────────────────────────
        [Fact]
        public void GameForced_Beats_CallerOff()
        {
            // 即使 caller 也想隐藏，game-forced 仍然胜出（不要进 CallerOff，避免后续 SetForceHidden(false) 误以为 caller off 解开后立即 active）
            Assert.Equal("GameForced", Resolve("Active", true, true, true, true));
        }

        [Fact]
        public void GameForced_Beats_MouseActivity()
        {
            Assert.Equal("GameForced", Resolve("Active", false, true, true, true));
        }

        [Theory]
        [InlineData("Hidden")]
        [InlineData("Active")]
        [InlineData("Idle")]
        [InlineData("CallerOff")]
        [InlineData("GameForced")]
        public void GameForced_FromAnyPrev(string prev)
        {
            Assert.Equal("GameForced", Resolve(prev, false, true, true, false));
        }

        // ── 优先级 2: CallerOff（无 GameForced 时） ──────────────────────────
        [Fact]
        public void CallerOff_When_SetCursorVisibleFalse()
        {
            Assert.Equal("CallerOff", Resolve("Active", true, false, true, false));
        }

        [Fact]
        public void CallerOff_Even_With_MouseActivity()
        {
            // SetCursorVisible(false) 之后即使 mouse 仍在动，仍然 CallerOff（plan section 1.3）
            Assert.Equal("CallerOff", Resolve("Active", true, false, true, true));
        }

        // ── 优先级 3: Active（wantActive + hasPos） ──────────────────────────
        [Fact]
        public void Active_OnMouseActivity_FromHidden()
        {
            Assert.Equal("Active", Resolve("Hidden", false, false, true, true));
        }

        [Fact]
        public void Active_OnMouseActivity_FromIdle()
        {
            // idle-hide 唤醒
            Assert.Equal("Active", Resolve("Idle", false, false, true, true));
        }

        [Fact]
        public void Active_OnSetCursorVisibleTrue_WithPosition()
        {
            // SetCursorVisible(true) 是 wantActive 信号
            Assert.Equal("Active", Resolve("CallerOff", false, false, true, true));
        }

        // ── 优先级 4: Hidden（无 position） ──────────────────────────────────
        [Fact]
        public void Hidden_When_NoPosition()
        {
            Assert.Equal("Hidden", Resolve("Hidden", false, false, false, false));
        }

        [Fact]
        public void Hidden_When_SetCursorVisibleTrue_NoPos()
        {
            // SetCursorVisible(true) 但还没收到位置 → Hidden（等第一次 UpdateCursorPosition）
            Assert.Equal("Hidden", Resolve("Hidden", false, false, false, true));
        }

        // ── 优先级 5: 保持 prev ────────────────────────────────────────────
        [Fact]
        public void Active_Stays_Active_NoSignal()
        {
            // SetForceHidden(false) 解锁后无 mouse activity → 保持 Active
            Assert.Equal("Active", Resolve("Active", false, false, true, false));
        }

        [Fact]
        public void Idle_Stays_Idle_NoSignal()
        {
            // 冗余 SetScale 调用不应把 Idle 错误推到 Active（避免 cursor 莫名其妙跳出）
            Assert.Equal("Idle", Resolve("Idle", false, false, true, false));
        }

        [Fact]
        public void Hidden_Stays_Hidden_NoSignal()
        {
            Assert.Equal("Hidden", Resolve("Hidden", false, false, true, false));
        }

        // ── 关键场景：plan risk #4 GameForced 解锁路径 ────────────────────────
        [Fact]
        public void Unlock_GameForced_BackToActive_OnMouseActivity()
        {
            // SetForceHidden(false) 时 wantActive=false → 保持 Active 假设之前是 Active
            // 但更重要：下一次 mouse 移动一定能进 Active
            Assert.Equal("Active", Resolve("GameForced", false, false, true, true));
        }

        [Fact]
        public void Unlock_GameForced_RespectCaller()
        {
            // SetForceHidden(false) 但 caller 也仍设了 hidden → CallerOff
            Assert.Equal("CallerOff", Resolve("GameForced", true, false, true, false));
        }

        // ── 边界：caller 解锁 ─────────────────────────────────────────────
        [Fact]
        public void CallerSetVisibleTrue_NoPos_StaysHidden()
        {
            // 玩家未移动鼠标过：SetCursorVisible(true) → 没位置 → Hidden
            Assert.Equal("Hidden", Resolve("CallerOff", false, false, false, true));
        }
    }
}
