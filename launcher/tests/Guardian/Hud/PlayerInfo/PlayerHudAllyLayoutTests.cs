using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public class PlayerHudAllyLayoutTests
{
    [Theory]
    [InlineData(1, 0, false, 28, 151.5f)]
    [InlineData(2, 1, false, 28, 294f)]
    [InlineData(2, 4, false, 28, 61f)]
    [InlineData(4, 1, false, 28, 114f)]
    [InlineData(10, 1, false, 28, 273f)]
    [InlineData(11, 0, false, 58, 273f)]
    [InlineData(20, 0, false, 58, 273f)]
    [InlineData(20, 0, true, 58, 294f)]
    [InlineData(21, 1, false, 88, 273f)]
    public void TrayEndsAfterLastOccupiedRowAndShrinksWithoutOverflow(int occupiedSlots, int focus, bool hasOverflow, int height, float expectedWidth)
    {
        var tray = PlayerHudAllyLayout.Tray(occupiedSlots, focus, 63, hasOverflow);
        Assert.Equal(height, tray.Height);
        Assert.Equal(expectedWidth, tray.Width, 2);
        Assert.True(tray.Contains(PlayerHudAllyLayout.Cell(occupiedSlots - 1, occupiedSlots, focus, tray.Top)));
        if (occupiedSlots >= 4)
            Assert.Equal(PlayerHudAllyLayout.Cell(0, 4, focus, tray.Top), PlayerHudAllyLayout.Cell(0, occupiedSlots, focus, tray.Top));
    }

    [Fact]
    public void RowTrayShrinksPartiallyFilledRowsAndLeavesUnusedRightAreaTransparent()
    {
        var row0 = PlayerHudAllyLayout.RowTray(0, 11, 0, 0, hasOverflow: false);
        var row1 = PlayerHudAllyLayout.RowTray(1, 11, 0, 0, hasOverflow: false);
        Assert.Equal(new RectangleF(6f, 0f, 273f, 28f), row0);
        Assert.Equal(new RectangleF(6f, 30f, 34.5f, 28f), row1);

        var row0Overflow = PlayerHudAllyLayout.RowTray(0, 20, 0, 0, hasOverflow: true);
        var row1Overflow = PlayerHudAllyLayout.RowTray(1, 20, 0, 0, hasOverflow: true);
        Assert.Equal(294f, row0Overflow.Width, 2);
        Assert.Equal(273f, row1Overflow.Width, 2);
        Assert.True(row0Overflow.Contains(PlayerHudAllyLayout.Toggle(0)));

        var root = FindRoot();
        RuntimeFontCatalog.Configure(root);
        Exception? failure = null;
        var thread = new System.Threading.Thread(() =>
        {
            try
            {
                using var owner = new Form { ClientSize = new Size(1024, 576) };
                using var anchor = new Panel { Dock = DockStyle.Fill };
                owner.Controls.Add(anchor);
                owner.CreateControl();
                anchor.CreateControl();
                using var controller = new PlayerHudController(_ => true, () => true, action => action());
                using var allies = new PlayerHudAllyWidget(anchor, controller, null);

                var packet = PlayerHudStateTests.Full();
                packet["groups"]["focusTarget"] = new JArray();
                packet["groups"]["allies"] = new JObject
                {
                    ["rows"] = new JArray(Enumerable.Range(0, 11).Select(i => new JObject
                    {
                        ["id"] = 100 + i,
                        ["generation"] = 1,
                        ["slot"] = i,
                        ["role"] = i == 0 ? "pet" : "map",
                        ["name"] = i == 10 ? "Itinerant" : $"友军{i}",
                        ["icon"] = "",
                        ["hp"] = new JArray(i == 3 ? 220 : 1000, 1000),
                        ["shield"] = new JArray(0, 0),
                        ["down"] = false,
                        ["protected"] = false
                    })),
                    ["overflow"] = new JArray()
                };
                Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet), 1));
                using var canvas = new Bitmap(320, 96, PixelFormat.Format32bppPArgb);
                using (var g = Graphics.FromImage(canvas))
                    allies.Paint(g, 1f, anchor.PointToScreen(Point.Empty));

                // Occupied row 0 & row 1 plates are opaque; unused right tail of row 0 and empty slots 11..19 of row 1 stay fully transparent.
                Assert.True(canvas.GetPixel(24, 14).A > 200);
                Assert.True(canvas.GetPixel(24, 44).A > 200);
                Assert.Equal(0, canvas.GetPixel(288, 14).A);
                Assert.Equal(0, canvas.GetPixel(60, 44).A);
                Assert.Equal(0, canvas.GetPixel(200, 44).A);
                // 2px transparent seam between row 0 (0..28) and row 1 (30..58).
                Assert.Equal(0, canvas.GetPixel(24, 29).A);

                var evidence = Environment.GetEnvironmentVariable("CF7_ALLY_HUD_EVIDENCE_DIR");
                if (!string.IsNullOrEmpty(evidence))
                {
                    Directory.CreateDirectory(evidence);
                    canvas.Save(Path.Combine(evidence, "ally-11-no-focus.png"), ImageFormat.Png);
                }
            }
            catch (Exception ex) { failure = ex; }
        });
        thread.SetApartmentState(System.Threading.ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }

    private static string FindRoot()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
            if (Directory.Exists(Path.Combine(dir.FullName, "launcher")) && Directory.Exists(Path.Combine(dir.FullName, "scripts")))
                return dir.FullName;
        throw new DirectoryNotFoundException("Could not locate project root.");
    }
}
