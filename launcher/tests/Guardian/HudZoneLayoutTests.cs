using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// 上层 HUD 分区仲裁与 v2 视觉原语（docs/上层HUD风格锚定与分区仲裁-ADR-2026-11-05.md D3–D6）。
    /// </summary>
    public sealed class HudZoneLayoutTests : IDisposable
    {
        public HudZoneLayoutTests() { HudZoneLayout.ResetForTests(); }
        public void Dispose() { HudZoneLayout.ResetForTests(); }

        [Fact]
        public void TopLeftWorstCaseNeverEntersTheEventCardReserve()
        {
            Assert.Equal(PlayerHudBuffLayout.SafeRight, HudZoneLayout.LeftColumnRight);
            Assert.Equal(LootFeedModel.MaxVisibleCards, HudZoneLayout.EventMaxCards);
            var worst = PlayerHudFocusTargetWidget.BoundsForBuffCount(256, 4);
            Assert.True(worst.Bottom <= HudZoneLayout.TopLeftMaxBottom, "TL bottom=" + worst.Bottom);
            Assert.True(HudZoneLayout.TopLeftMaxBottom + HudZoneLayout.ZoneGap
                <= HudZoneLayout.EventBottomY - HudZoneLayout.EventCardsReserveHeight + 0.01f);
            Assert.Equal(worst.Bottom, PlayerHudFocusTargetWidget.TopLeftBottomFor(256, 4, false));
            Assert.Equal(0f, PlayerHudFocusTargetWidget.TopLeftBottomFor(256, 4, true));
            Assert.Equal(PlayerHudBuffLayout.ContentHeight(3), PlayerHudFocusTargetWidget.TopLeftBottomFor(3, 0, false));
        }

        [Theory]
        [InlineData(0f, 460f, 6f, 460f)]
        [InlineData(281f, 460f, 287f, 460f)]
        [InlineData(100f, 402f, 106f, 396f)]
        public void FallbackRegionYieldsToStatusColumnAndSitsOnEventCards(float tl, float cards, float top, float bottom)
        {
            HudZoneLayout.FallbackRegion(tl, cards, out float t, out float b);
            Assert.Equal(top, t);
            Assert.Equal(bottom, b);
        }

        [Fact]
        public void EventCardsTopMatchesLootGeometry()
        {
            Assert.Equal(460f, HudZoneLayout.EventCardsTopFor(0, false));
            Assert.Equal(460f - 2 * 29f, HudZoneLayout.EventCardsTopFor(2, false));
            Assert.Equal(460f - HudZoneLayout.EventCardsReserveHeight, HudZoneLayout.EventCardsTopFor(5, true));
        }

        [Fact]
        public void ComboFollowsNotchStableBottomAndStaysInsideTheNotchSafeWidth()
        {
            Assert.Equal(32f, NotchWidget.StableBottomBase(0));
            Assert.Equal(54f, NotchWidget.StableBottomBase(1));
            Assert.Equal(56f, HudZoneLayout.ComboTop(NotchWidget.StableBottomBase(1)));
            int rightRowLeft = 1024 - RightHudLayout.RightOffsetBase - RightHudLayout.RightActionRowWidthBase;
            Assert.True(HudZoneLayout.ComboMaxWidth <= 2 * (rightRowLeft - RightHudLayout.NotchRightGapBase - 512));
            Assert.True(512 - HudZoneLayout.ComboMaxWidth / 2 >= HudZoneLayout.LeftColumnRight);
        }

        [Fact]
        public void ReportsRaiseChangedOnlyForRealChanges()
        {
            int changes = 0;
            HudZoneLayout.Changed += (_, _) => changes++;
            HudZoneLayout.ReportTopLeftBottom(120f);
            HudZoneLayout.ReportTopLeftBottom(120.1f);
            HudZoneLayout.ReportEventCardsTop(402f);
            HudZoneLayout.ReportNotchStableBottom(10f); // clamped to collapsed height: no change
            Assert.Equal(2, changes);
            Assert.Equal(HudZoneLayout.ComboTop(32f), HudZoneLayout.CurrentComboTop());
        }

        [Fact]
        public void FallbackMessagesStackAboveEventCardsAndNeverCoverTheStatusColumn() => Sta(() =>
        {
            RuntimeFontCatalog.Configure(Root());
            using var form = new Form { ClientSize = new Size(1024, 576), AutoScaleMode = AutoScaleMode.None };
            using var anchor = new Panel { Dock = DockStyle.Fill }; form.Controls.Add(anchor); form.CreateControl(); anchor.CreateControl();
            using var toast = new ToastWidget(anchor);
            toast.SetReady();
            for (int i = 0; i < 8; i++) toast.AddMessage("<font color='#FFCC00'>消息</font> 第" + i + "条");
            var origin = anchor.PointToScreen(Point.Empty);

            var free = toast.ScreenBounds; free.Offset(-origin.X, -origin.Y);
            Assert.Equal(460, free.Bottom);
            Assert.Equal(8, toast.VisibleLineCount);

            HudZoneLayout.ReportEventCardsTop(402f);
            HudZoneLayout.ReportTopLeftBottom(281f);
            var squeezed = toast.ScreenBounds; squeezed.Offset(-origin.X, -origin.Y);
            Assert.True(squeezed.Bottom <= 397, "bottom=" + squeezed.Bottom);
            Assert.True(squeezed.Top >= 286, "top=" + squeezed.Top);
            Assert.InRange(toast.VisibleLineCount, 1, 7);
            Assert.True(squeezed.Right <= HudZoneLayout.LeftColumnRight + 1);

            HudZoneLayout.ReportTopLeftBottom(400f);
            Assert.Equal(Rectangle.Empty, toast.ScreenBounds);
            using var bitmap = new Bitmap(1024, 576);
            using (var g = Graphics.FromImage(bitmap)) toast.Paint(g, 1, origin); // no space: paints nothing, no throw
        });

        [Fact]
        public void PanelToastBecomesPlainNotchNoticeWithFirstSemanticColor()
        {
            WebOverlayForm.DescribePanelToast("<font color='#FF6666'>失败</font>：材料不足", out string plain, out Color accent);
            Assert.Equal("失败：材料不足", plain);
            Assert.Equal(Color.FromArgb(255, 0xFF, 0x66, 0x66), accent);
            WebOverlayForm.DescribePanelToast("已保存", out plain, out accent);
            Assert.Equal("已保存", plain);
            Assert.True(accent.R > 200 && accent.G > 200 && accent.B > 200);
        }

        [Fact]
        public void PlatePrimitiveChamfersOnlyRequestedCornersAndKeepsGraphicsState()
        {
            using (GraphicsPath path = NativeHudTheme.CreatePlatePath(new RectangleF(0, 0, 100, 32), 7,
                NativeHudTheme.PlateCorners.TopRight))
            {
                Assert.False(path.IsVisible(99, 1));
                Assert.True(path.IsVisible(1, 1));
                Assert.True(path.IsVisible(1, 31));
                Assert.True(path.IsVisible(50, 16));
            }
            using (GraphicsPath notch = NativeHudTheme.CreatePlatePath(new RectangleF(0, 0, 100, 32), 10,
                NativeHudTheme.PlateCorners.BottomLeft | NativeHudTheme.PlateCorners.BottomRight))
            {
                Assert.False(notch.IsVisible(1, 31));
                Assert.False(notch.IsVisible(99, 31));
                Assert.True(notch.IsVisible(1, 1));
            }
            using (Bitmap bitmap = new Bitmap(120, 40))
            using (Graphics g = Graphics.FromImage(bitmap))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                NativeHudTheme.DrawPlate(g, new Rectangle(0, 0, 120, 40), 1f, NativeHudTheme.PanelFillDense,
                    NativeHudTheme.AnchorRim, NativeHudTheme.PlateCorners.TopRight, NativeHudTheme.PlateChamferBase);
                RectangleF content = NativeHudTheme.DrawSlantTag(g, new RectangleF(10, 10, 40, 16),
                    NativeHudTheme.AnchorTagFill, NativeHudTheme.AnchorRim);
                Assert.Equal(SmoothingMode.AntiAlias, g.SmoothingMode); // 原语内部切换平滑模式后必须恢复调用方状态
                Assert.True(content.Width < 40 && content.Left > 10);
                Assert.Equal(0, bitmap.GetPixel(119, 0).A);             // chamfered corner stays transparent
                Assert.True(bitmap.GetPixel(60, 20).A > 200);            // dense metal plate body
                Assert.True(bitmap.GetPixel(60, 0).GetBrightness() > bitmap.GetPixel(60, 20).GetBrightness()); // silver rim
            }
        }

        private static string Root()
        {
            var current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null && !Directory.Exists(Path.Combine(current.FullName, "data", "items"))) current = current.Parent;
            return current?.FullName ?? throw new DirectoryNotFoundException("Repository root");
        }

        private static void Sta(Action body)
        {
            Exception error = null;
            var thread = new Thread(() => { try { body(); } catch (Exception e) { error = e; } });
            thread.SetApartmentState(ApartmentState.STA); thread.Start(); Assert.True(thread.Join(15000));
            if (error != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(error).Throw();
        }
    }
}
