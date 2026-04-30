// CF7:ME — CursorOverlayForm.ComputeEffectiveScale 单测（C# 5）
// 覆盖 viewport-first / DPI-fallback 策略。
// 修复诊断：DPI 125%/150% 玩家窗口模式 cursor 偏大的 bug，根因是 max(viewport, dpi)
// 让 DPI 在窗口化（viewport=1.0）时主导。Per-Monitor V2 下物理 viewport 已经反映 OS DPI 缩放，
// 不应再叠加 DPI scale。

using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class CursorScaleTests
    {
        // 全屏 1920×1080：viewport=1.875 → 直接用 viewport（DPI 不再叠加）
        [Fact]
        public void Fullscreen_1080p_DPI100_UsesViewport()
        {
            double s = CursorOverlayForm.ComputeEffectiveScaleForTest(1.875, 1.0);
            Assert.Equal(1.875, s, 3);
        }

        // 窗口化 1024×576 / DPI 100%：viewport=1.0
        [Fact]
        public void Windowed_DesignSize_DPI100_UsesViewport()
        {
            double s = CursorOverlayForm.ComputeEffectiveScaleForTest(1.0, 1.0);
            Assert.Equal(1.0, s, 3);
        }

        // 关键回归：DPI 150% 玩家窗口化时 cursor 应只跟 viewport，不双重放大
        // 之前 bug：max(1.0, 1.5)=1.5 让 DPI 主导，cursor 比设计像素大 50%
        [Fact]
        public void Windowed_HighDpi_StillUsesViewport_NotDpi()
        {
            double s = CursorOverlayForm.ComputeEffectiveScaleForTest(1.0, 1.5);
            Assert.Equal(1.0, s, 3);
        }

        // 4K + DPI 200% + 全屏：Per-Monitor V2 下 viewport 已经是物理像素 → 单独用 viewport
        [Fact]
        public void FourK_DPI200_Fullscreen_UsesViewport()
        {
            double s = CursorOverlayForm.ComputeEffectiveScaleForTest(1.875, 2.0);
            Assert.Equal(1.875, s, 3);
        }

        // 启动早期 viewport 数据未就绪 → 用 DPI 兜底，避免 cursor 渲染成 1.0× 异常小
        [Theory]
        [InlineData(0.0, 1.0, 1.0)]
        [InlineData(0.0, 1.5, 1.5)]
        [InlineData(0.0, 2.0, 2.0)]
        [InlineData(-1.0, 1.5, 1.5)]
        [InlineData(double.NaN, 1.5, 1.5)]
        public void Invalid_Viewport_FallsBackToDpi(double vp, double dpi, double expected)
        {
            double s = CursorOverlayForm.ComputeEffectiveScaleForTest(vp, dpi);
            Assert.Equal(expected, s, 3);
        }

        // 两者都失效 → 1.0
        [Fact]
        public void Both_Invalid_FallsBackToOne()
        {
            double s = CursorOverlayForm.ComputeEffectiveScaleForTest(double.NaN, -1.0);
            Assert.Equal(1.0, s, 3);
        }

        // viewport 有效但 DPI 无效 → 仍用 viewport
        [Fact]
        public void Valid_Viewport_Invalid_Dpi_UsesViewport()
        {
            double s = CursorOverlayForm.ComputeEffectiveScaleForTest(1.875, 0.0);
            Assert.Equal(1.875, s, 3);
        }
    }
}
