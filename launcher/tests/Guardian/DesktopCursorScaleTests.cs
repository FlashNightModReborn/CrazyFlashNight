// CF7:ME — DesktopCursorOverlay.ComputeEffectiveScale 单测（C# 5）
// 与 CursorOverlayForm.ComputeEffectiveScale 共享同款公式 → 与 CursorScaleTests 内容对齐。
// Phase 1 (cursor decoupling)：保证新旧路径 scale 行为完全一致，旁证 flag toggle 不带玩家可感知差异。

using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class DesktopCursorScaleTests
    {
        // 全屏 1920×1080：viewport=1.875 → 直接用 viewport
        [Fact]
        public void Fullscreen_1080p_DPI100_UsesViewport()
        {
            double s = DesktopCursorOverlay.ComputeEffectiveScaleForTest(1.875, 1.0);
            Assert.Equal(1.875, s, 3);
        }

        // 窗口化 1024×576 / DPI 100%：viewport=1.0
        [Fact]
        public void Windowed_DesignSize_DPI100_UsesViewport()
        {
            double s = DesktopCursorOverlay.ComputeEffectiveScaleForTest(1.0, 1.0);
            Assert.Equal(1.0, s, 3);
        }

        // 关键回归：DPI 150% 玩家窗口化时 cursor 应只跟 viewport
        [Fact]
        public void Windowed_HighDpi_StillUsesViewport_NotDpi()
        {
            double s = DesktopCursorOverlay.ComputeEffectiveScaleForTest(1.0, 1.5);
            Assert.Equal(1.0, s, 3);
        }

        // 4K + DPI 200% + 全屏：Per-Monitor V2 下 viewport 已经是物理像素
        [Fact]
        public void FourK_DPI200_Fullscreen_UsesViewport()
        {
            double s = DesktopCursorOverlay.ComputeEffectiveScaleForTest(1.875, 2.0);
            Assert.Equal(1.875, s, 3);
        }

        // 启动早期 viewport 数据未就绪 → 用 DPI 兜底
        [Theory]
        [InlineData(0.0, 1.0, 1.0)]
        [InlineData(0.0, 1.5, 1.5)]
        [InlineData(0.0, 2.0, 2.0)]
        [InlineData(-1.0, 1.5, 1.5)]
        [InlineData(double.NaN, 1.5, 1.5)]
        public void Invalid_Viewport_FallsBackToDpi(double vp, double dpi, double expected)
        {
            double s = DesktopCursorOverlay.ComputeEffectiveScaleForTest(vp, dpi);
            Assert.Equal(expected, s, 3);
        }

        // 两者都失效 → 1.0
        [Fact]
        public void Both_Invalid_FallsBackToOne()
        {
            double s = DesktopCursorOverlay.ComputeEffectiveScaleForTest(double.NaN, -1.0);
            Assert.Equal(1.0, s, 3);
        }

        // viewport 有效但 DPI 无效 → 仍用 viewport
        [Fact]
        public void Valid_Viewport_Invalid_Dpi_UsesViewport()
        {
            double s = DesktopCursorOverlay.ComputeEffectiveScaleForTest(1.875, 0.0);
            Assert.Equal(1.875, s, 3);
        }
    }
}
