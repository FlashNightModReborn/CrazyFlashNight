using System.Drawing;
using System.Drawing.Drawing2D;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NativeHudThemeTests
    {
        [Fact]
        public void TopBarHeight_IsSharedByNotchRightActionsAndComboAnchor()
        {
            Assert.Equal(32, NativeHudTheme.TopBarHeightBase);
            Assert.Equal(NativeHudTheme.TopBarHeightBase, RightHudLayout.ToolBarHeightBase);
            Assert.Equal(NativeHudTheme.TopBarHeightBase, NotchWidget.CollapsedHeightBaseForTest);
            Assert.Equal(NativeHudTheme.TopBarHeightBase, ComboWidget.NotchPillHeightBaseForTest);
            Assert.Equal(0, NativeHudTheme.CornerCutPx(1.875f));
        }

        [Fact]
        public void CutCornerPath_ClipsCornersButKeepsPanelInterior()
        {
            using (GraphicsPath path = NativeHudTheme.CreateCutCornerPath(new Rectangle(0, 0, 100, 32), 4))
            {
                Assert.True(path.PointCount >= 8);
                Assert.False(path.IsVisible(1, 1));
                Assert.True(path.IsVisible(50, 16));
                Assert.True(path.IsVisible(2, 16));
            }
        }

        [Theory]
        [InlineData(1.0f, 1)]
        [InlineData(1.5f, 1)]
        [InlineData(1.875f, 1)]
        [InlineData(2.5f, 2)]
        public void FrameStroke_StaysHairlineAtCommonViewportScales(float scale, int expected)
        {
            Assert.Equal(expected, NativeHudTheme.StrokePx(scale));
        }

        [Fact]
        public void ThemeMaintainsHighContrastFlashFrameHierarchy()
        {
            Assert.True(NativeHudTheme.FrameStrong.GetBrightness() > NativeHudTheme.PanelFill.GetBrightness());
            Assert.True(NativeHudTheme.TextPrimary.GetBrightness() > NativeHudTheme.TextSecondary.GetBrightness());
            Assert.True(NativeHudTheme.FrameStrong.A > NativeHudTheme.FrameMuted.A);
            Assert.True(NativeHudTheme.PanelFillDense.A > NativeHudTheme.PanelFillSoft.A);

            using (Bitmap bitmap = new Bitmap(100, 32))
            using (Graphics g = Graphics.FromImage(bitmap))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                NativeHudTheme.DrawButton(g, new Rectangle(0, 0, 100, 32), 1.5f,
                    false, false, false, false);

                // 结构线内部临时关闭抗锯齿，但必须恢复调用方的文字/曲线渲染状态。
                Assert.Equal(SmoothingMode.AntiAlias, g.SmoothingMode);
                // 左上角标要比槽位中心底色更亮，确保细节不是只有代码没有像素结果。
                Assert.True(bitmap.GetPixel(3, 3).GetBrightness()
                    > bitmap.GetPixel(50, 16).GetBrightness());
            }
        }
    }
}
