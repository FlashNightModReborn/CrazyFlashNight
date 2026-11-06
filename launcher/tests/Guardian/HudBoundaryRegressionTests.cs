using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class HudBoundaryRegressionTests : IDisposable
    {
        public HudBoundaryRegressionTests() { HudZoneLayout.ResetForTests(); }
        public void Dispose() { HudZoneLayout.ResetForTests(); }

        [Fact]
        public void LatestPanelReceiptGetsItsFullFirstExposureAfterLongSuspend()
        {
            using var anchor = new Control();
            using var notch = new NotchWidget(anchor, new FpsRingBuffer(300), "", null, null, null, null);
            notch.SetStatusItem("wave", "波次", "", Color.Cyan);
            notch.AddNotice("old", "挂起前提示", Color.White);
            notch.AddNotice(NotchWidget.PanelToastNoticeCategory, "旧面板回执", Color.White);
            notch.BeginPanelSuspend();
            notch.AddNotice(NotchWidget.PanelToastNoticeCategory, "材料不足", Color.Red);
            notch.AddNotice(NotchWidget.PanelToastNoticeCategory, "刚刚更新的回执", Color.Green);
            notch.AgeTransientRowsForSuspend(10000);
            Assert.DoesNotContain(notch.InfoRowsForTest, r => r.Category == "old");
            var receipt = Assert.Single(notch.InfoRowsForTest.Where(r => r.Category == NotchWidget.PanelToastNoticeCategory));
            Assert.Equal("刚刚更新的回执", receipt.Text);
            Assert.Equal(4000, receipt.RemainingMs);
            Assert.Equal(0, receipt.AgeMs);
            Assert.Null(receipt.PrevText);
            notch.Tick(3999);
            Assert.Contains(notch.InfoRowsForTest, r => r.Category == NotchWidget.PanelToastNoticeCategory);
            notch.Tick(1);
            Assert.Single(notch.InfoRowsForTest); // wave 仍在，操作回执正常到期
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void ComboUsesStableExpandedReservationIncludingOtherMenu(bool modern) => Sta(() =>
        {
            using var anchor = new Control { Size = new Size(1024, 576) }; anchor.CreateControl();
            using var notch = new NotchWidget(anchor, new FpsRingBuffer(300), "", null, null, null, null, preparationNavigationV1: modern);
            notch.ForceGameReadyForTest(true);
            notch.SetStatusItem("wave", "波次", "", Color.Cyan);
            using var combo = new ComboWidget(anchor);
            combo.ForceGameReady(true);
            combo.OnLegacyUiData("combo", new[] { "", "→↓↘", "波动拳:→↓↘A:1" });
            var collapsed = combo.ScreenBounds;
            notch.BeginExpandForTest();
            int expandedTop = combo.ScreenBounds.Top;
            notch.Tick(75);
            Assert.Equal(expandedTop, combo.ScreenBounds.Top);
            Assert.False(combo.ScreenBounds.IntersectsWith(notch.ScreenBounds));
            notch.Tick(75);
            Assert.False(combo.ScreenBounds.IntersectsWith(notch.ScreenBounds));
            notch.OpenOtherMenuForTest(1);
            Assert.False(combo.ScreenBounds.IntersectsWith(notch.ScreenBounds));
            notch.BeginCollapseForTest(); notch.Tick(200);
            Assert.Equal(collapsed.Top, combo.ScreenBounds.Top);
        });

        [Theory]
        [InlineData(1024, 576)]
        [InlineData(1600, 900)]
        [InlineData(1920, 1080)]
        public void LongRichMessageWrapsAndAllPixelsStayInsideItsReportedBounds(int width, int height) => Sta(() =>
        {
            RuntimeFontCatalog.Configure(Root());
            using var anchor = new Control { Size = new Size(width, height) }; anchor.CreateControl();
            var origin = anchor.PointToScreen(Point.Empty);
            using var toast = new ToastWidget(anchor); toast.SetReady();
            toast.AddMessage("<font color='#FF6666'>注意：</font>" + new string('长', 85) + "<font color='#00FF00'>🙂e\u0301末尾</font>");
            toast.Tick(300);
            var bounds = toast.ScreenBounds; bounds.Offset(-origin.X, -origin.Y);
            using var bitmap = new Bitmap(width, height);
            using (var graphics = Graphics.FromImage(bitmap)) toast.Paint(graphics, 1, origin);
            int ink = 0, bottomInk = 0, outside = 0, red = 0, green = 0;
            for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
            {
                Color pixel = bitmap.GetPixel(x, y);
                if (pixel.A == 0) continue;
                ink++;
                if (!bounds.Contains(x, y)) outside++;
                if (y > bounds.Top + bounds.Height / 2) bottomInk++;
                if (pixel.R > pixel.G * 1.3) red++;
                if (pixel.G > pixel.R * 1.3) green++;
            }
            Assert.True(ink > 0 && bottomInk > 0 && red > 0 && green > 0);
            Assert.Equal(0, outside);
        });

        private static string Root()
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir != null && !Directory.Exists(Path.Combine(dir.FullName, "data", "items"))) dir = dir.Parent;
            return dir?.FullName ?? throw new DirectoryNotFoundException();
        }
        private static void Sta(Action body)
        {
            Exception error = null;
            var thread = new Thread(() => { try { body(); } catch (Exception e) { error = e; } });
            thread.SetApartmentState(ApartmentState.STA); thread.Start(); Assert.True(thread.Join(30000));
            if (error != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(error).Throw();
        }
    }
}
