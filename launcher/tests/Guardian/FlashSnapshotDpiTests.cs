using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// 输出保持 GetClientRect 的物理尺寸；只有 DPI Unaware 的 GDI 源缓冲按
    /// windowDpi/monitorDpi 还原后再拉伸，避免右侧/底部黑区。
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
        public void Unaware_OutputRemainsPhysical()
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

        [Fact]
        public void Unaware_150Percent_UsesVirtualizedLogicalSource()
        {
            int sourceW, sourceH;
            FlashSnapshot.ComputeCaptureSourceSize(
                1600,
                900,
                EffectiveDpiAwareness.Unaware,
                96u,
                144u,
                144u,
                out sourceW,
                out sourceH);

            Assert.Equal(1067, sourceW);
            Assert.Equal(600, sourceH);
        }

        [Fact]
        public void Unaware_125Percent_UsesVirtualizedLogicalSource()
        {
            int sourceW, sourceH;
            FlashSnapshot.ComputeCaptureSourceSize(
                1280,
                720,
                EffectiveDpiAwareness.Unaware,
                96u,
                120u,
                120u,
                out sourceW,
                out sourceH);

            Assert.Equal(1024, sourceW);
            Assert.Equal(576, sourceH);
        }

        [Theory]
        [InlineData(EffectiveDpiAwareness.PerMonitorV2, 144u, 144u)]
        [InlineData(EffectiveDpiAwareness.PerMonitor, 144u, 144u)]
        [InlineData(EffectiveDpiAwareness.SystemAware, 144u, 144u)]
        [InlineData(EffectiveDpiAwareness.Unknown, 144u, 144u)]
        [InlineData(EffectiveDpiAwareness.Unaware, 96u, 96u)]
        public void NonVirtualizedSource_RemainsOneToOne(
            EffectiveDpiAwareness awareness,
            uint monitorDpiX,
            uint monitorDpiY)
        {
            int sourceW, sourceH;
            FlashSnapshot.ComputeCaptureSourceSize(
                1600,
                900,
                awareness,
                96u,
                monitorDpiX,
                monitorDpiY,
                out sourceW,
                out sourceH);

            Assert.Equal(1600, sourceW);
            Assert.Equal(900, sourceH);
        }

        [Fact]
        public void Unaware_AnisotropicMonitorDpi_ScalesOnlyAffectedAxis()
        {
            int sourceW, sourceH;
            FlashSnapshot.ComputeCaptureSourceSize(
                1600,
                900,
                EffectiveDpiAwareness.Unaware,
                96u,
                144u,
                96u,
                out sourceW,
                out sourceH);

            Assert.Equal(1067, sourceW);
            Assert.Equal(900, sourceH);
        }
    }
}
