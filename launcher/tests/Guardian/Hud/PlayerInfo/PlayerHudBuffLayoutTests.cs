using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudBuffLayoutTests
{
    private static JObject Packet(int count, long epoch = 1, long seq = 1)
    {
        var packet = PlayerHudStateTests.Full(epoch, seq);
        packet["groups"]["buffs"] = new JArray(Enumerable.Range(0, count).Select(i => new JObject
        {
            ["id"] = "buff" + i.ToString("000"), ["timed"] = false, ["total"] = 0, ["remaining"] = 0,
            ["info"] = new JObject { ["name"] = i == 0 ? "全装助力" : i == 1 ? "缓冲护盾" : "药剂" + i,
                ["description"] = "只读状态说明", ["polarity"] = "benefit", ["stacks"] = 0 }
        }));
        return packet;
    }

    [Theory]
    [InlineData(1)] [InlineData(10)] [InlineData(11)] [InlineData(13)]
    [InlineData(32)] [InlineData(80)] [InlineData(81)] [InlineData(256)]
    public void EveryVisibleCardAndTargetStripStayInTheSharedLeftColumn(int count)
    {
        Assert.Equal(10, PlayerHudBuffLayout.Columns);
        var bounds = PlayerHudBuffLayout.Bounds(count);
        var notchLeft = (1024 - RightHudLayout.PreferredNotchMaxWidthBase) / 2f;
        Assert.True(bounds.Right + RightHudLayout.NotchRightGapBase <= notchLeft);
        for (int i = 0; i < Math.Min(count, PlayerHudBuffLayout.PageSize); i++)
            Assert.True(bounds.Contains(PlayerHudBuffWidget.SlotRect(i)));
        var targets = PlayerHudFocusTargetWidget.BoundsForBuffCount(count, 4);
        Assert.True(targets.Top >= bounds.Bottom + 4);
        Assert.True(targets.Bottom < 460); // Preserve room above the bottom player HUD, including at the 256-row wire limit.
        if (count > PlayerHudBuffLayout.PageSize)
        {
            Assert.True(bounds.Contains(PlayerHudBuffLayout.PreviousPageRect(count)));
            Assert.True(bounds.Contains(PlayerHudBuffLayout.NextPageRect(count)));
        }
    }

    [Theory]
    [InlineData(1024, 576, 13)] [InlineData(1600, 900, 13)]
    [InlineData(1920, 1080, 32)] [InlineData(1024, 768, 256)]
    public void ProductionCardsAvoidAnExpandedNotchAtEachViewport(int width, int height, int count) => Sta(() =>
    {
        RuntimeFontCatalog.Configure(Root());
        using var form = new Form { ClientSize = new Size(width, height), AutoScaleMode = AutoScaleMode.None };
        using var anchor = new Panel { Dock = DockStyle.Fill }; form.Controls.Add(anchor); form.CreateControl(); anchor.CreateControl();
        using var controller = new PlayerHudController(_ => true, () => true, action => action());
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Packet(count)));
        using var widget = new PlayerHudBuffWidget(anchor, controller);
        var fps = new FpsRingBuffer(600); fps.Push(30);
        using var notch = new NotchWidget(anchor, fps, Root(), () => { }, () => { }, () => { }, _ => { });
        notch.ForceGameReadyForTest(true); notch.ForceCurrenciesForTest(13023413, 13046452);
        notch.BeginExpandForTest(); notch.Tick(10000);
        notch.SetStatusItem("wave", "波次 1/1", "残敌 1", NativeHudTheme.Cyan); notch.Tick(500);
        Assert.False(widget.ScreenBounds.IntersectsWith(notch.ScreenBounds));
        var origin = anchor.PointToScreen(Point.Empty);
        var relative = widget.ScreenBounds; relative.Offset(-origin.X, -origin.Y);
        var viewport = RightHudLayout.ViewportFromPanelSize(width, height);
        Assert.True(viewport.Contains(relative));
        using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(bitmap)) { graphics.Clear(Color.Transparent); widget.Paint(graphics, 1, origin); notch.Paint(graphics, 1, origin); }
        float scale = viewport.Height / 576f;
        var eleventh = PlayerHudBuffWidget.SlotRect(10);
        Assert.Equal(35, eleventh.Top); // The reported thirteenth card must have wrapped before reaching the notch.
        Assert.True(bitmap.GetPixel(viewport.Left + (int)((eleventh.Left + 2) * scale), viewport.Top + (int)((eleventh.Top + 2) * scale)).A > 0);
        var output = Environment.GetEnvironmentVariable("CF7_UNIFIED61_HUD_REVIEW_DIR");
        if (!string.IsNullOrEmpty(output))
        {
            Directory.CreateDirectory(output);
            bitmap.Save(Path.Combine(output, $"buff-safe-column-{width}x{height}-{count}.png"), ImageFormat.Png);
        }
    });

    [Fact]
    public void LargeListsRemainAccessibleAndPageNavigationCannotSendGameCommandsOrReplayOldEpochs() => Sta(() =>
    {
        using var form = new Form { ClientSize = new Size(1024, 576), AutoScaleMode = AutoScaleMode.None };
        using var anchor = new Panel { Dock = DockStyle.Fill }; form.Controls.Add(anchor); form.CreateControl(); anchor.CreateControl();
        var sent = new List<string>();
        using var controller = new PlayerHudController(s => { sent.Add(s); return true; }, () => true, action => action());
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Packet(256))); sent.Clear();
        using var widget = new PlayerHudBuffWidget(anchor, controller);
        Point At(RectangleF r) => anchor.PointToScreen(new Point((int)r.X + 5, (int)r.Y + 5));
        void Edge(Point p, MouseEventKind kind) => widget.OnMouseEvent(new MouseEventArgs(MouseButtons.Left, 1, p.X, p.Y, 0), kind);
        void Click(Point p) { Edge(p, MouseEventKind.Down); Edge(p, MouseEventKind.Up); Edge(p, MouseEventKind.Click); }
        var next = At(PlayerHudBuffLayout.NextPageRect(256));
        Assert.True(widget.NeedsPointerClick);
        var initialNext = widget.CapturePointerTarget(next);
        Click(next);
        Assert.Equal(1, widget.CurrentPage);
        Assert.NotEqual(initialNext, widget.CapturePointerTarget(next));
        Assert.Equal("buff080", Assert.IsType<PlayerHudTarget>(widget.CapturePointerTarget(At(PlayerHudBuffWidget.SlotRect(0)))).Key);
        Click(next); Click(next);
        Assert.Equal(3, widget.CurrentPage);
        Assert.Equal("buff255", Assert.IsType<PlayerHudTarget>(widget.CapturePointerTarget(At(PlayerHudBuffWidget.SlotRect(15)))).Key);
        Assert.False(widget.TryHitTest(At(PlayerHudBuffWidget.SlotRect(16))));
        Edge(next, MouseEventKind.Down);
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Packet(256, 2)));
        Edge(next, MouseEventKind.Up); Edge(next, MouseEventKind.Click);
        Assert.Equal(0, widget.CurrentPage);
        Click(next); widget.SetHostSuppressed(true);
        Edge(next, MouseEventKind.Down); widget.SetHostSuppressed(false); Edge(next, MouseEventKind.Up); Edge(next, MouseEventKind.Click);
        Assert.Equal(1, widget.CurrentPage);
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Packet(2, 2, 2)));
        Assert.Equal(0, widget.CurrentPage); Assert.False(widget.NeedsPointerClick);
        Assert.Empty(sent);
    });

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
