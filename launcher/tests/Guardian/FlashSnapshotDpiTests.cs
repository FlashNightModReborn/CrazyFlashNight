using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// 默认假设：所有 DPI-aware 模式下 GetClientRect 返回物理像素，不缩放。
    /// 与 MS 文档对齐；硬编码"V1=逻辑像素"假设会在 PMv1/SystemAware 下错误放大 1.25-1.5x。
    /// 若 Phase 2 启动期探针发现某模式实际偏差 → 修 ComputePhysicalSize 加分支 + 在此测试加 case 固化。
    /// </summary>
    public class FlashSnapshotDpiTests
    {
        [Fact]
        public void PerMonitorV2_NoScaling()
        {
            int pw, ph;
            FlashSnapshot.ComputePhysicalSize(1024, 576, EffectiveDpiAwareness.PerMonitorV2, 96u, out pw, out ph);
            Assert.Equal(1024, pw);
            Assert.Equal(576, ph);
        }

        [Fact]
        public void PerMonitor_NoScaling()
        {
            int pw, ph;
            FlashSnapshot.ComputePhysicalSize(1024, 576, EffectiveDpiAwareness.PerMonitor, 120u, out pw, out ph);
            Assert.Equal(1024, pw);
            Assert.Equal(576, ph);
        }

        [Fact]
        public void SystemAware_NoScaling()
        {
            int pw, ph;
            FlashSnapshot.ComputePhysicalSize(1024, 576, EffectiveDpiAwareness.SystemAware, 144u, out pw, out ph);
            Assert.Equal(1024, pw);
            Assert.Equal(576, ph);
        }

        [Fact]
        public void Unaware_NoScaling()
        {
            int pw, ph;
            FlashSnapshot.ComputePhysicalSize(1024, 576, EffectiveDpiAwareness.Unaware, 96u, out pw, out ph);
            Assert.Equal(1024, pw);
            Assert.Equal(576, ph);
        }

        [Fact]
        public void Unknown_NoScaling()
        {
            int pw, ph;
            FlashSnapshot.ComputePhysicalSize(1280, 720, EffectiveDpiAwareness.Unknown, 96u, out pw, out ph);
            Assert.Equal(1280, pw);
            Assert.Equal(720, ph);
        }
    }
}
