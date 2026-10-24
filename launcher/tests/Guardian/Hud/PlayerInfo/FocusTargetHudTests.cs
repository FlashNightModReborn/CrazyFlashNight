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

public sealed class FocusTargetHudTests
{
    private static JObject Target(long id = 1) => new()
    {
        ["id"] = id, ["role"] = "boss", ["name"] = "元老 | 引号\"", ["hp"] = new JArray(70, 100)
    };
    private static JObject Full(long epoch = 1, long seq = 1)
    {
        var packet = PlayerHudStateTests.Full(epoch, seq);
        packet["groups"]["focusTarget"] = Target();
        return packet;
    }
    private static JObject Delta(long seq, JObject groups) => new()
    { ["v"] = 1, ["epoch"] = 1, ["seq"] = seq, ["full"] = false, ["visible"] = true, ["groups"] = groups };
    private static bool Receive(PlayerHudState state, JObject packet) => state.Receive(PlayerHudStateTests.Encode(packet), 1);

    [Fact]
    public void OptionalGroupRetainsOnlyWithinEpochAndExplicitNullClears()
    {
        var state = new PlayerHudState();
        Assert.True(Receive(state, PlayerHudStateTests.Full())); Assert.Null(state.Snapshot.FocusTarget);
        Assert.True(Receive(state, Full(1, 2))); var target = state.Snapshot.FocusTarget;
        Assert.Equal("元老 | 引号\"", target.Name);
        Assert.True(Receive(state, Delta(3, new JObject { ["buffs"] = new JArray() })));
        Assert.Same(target, state.Snapshot.FocusTarget);
        Assert.True(Receive(state, Delta(4, new JObject { ["focusTarget"] = JValue.CreateNull() })));
        Assert.Null(state.Snapshot.FocusTarget);
        Assert.False(Receive(state, Full(1, 3))); Assert.Null(state.Snapshot.FocusTarget);
        Assert.True(Receive(state, Full(1, 5)));
        Assert.True(Receive(state, PlayerHudStateTests.Full(2, 1))); Assert.Null(state.Snapshot.FocusTarget);
        Assert.True(Receive(state, Full(2, 2))); state.Disconnect(); Assert.Null(state.Snapshot);
    }

    [Theory]
    [InlineData(-12)]
    [InlineData(0)]
    [InlineData(70)]
    [InlineData(140)]
    public void KeepsRawAuthoritativeHealthRatherThanRewritingGameFacts(double hp)
    {
        var packet = Full(); packet["groups"]["focusTarget"]["hp"][0] = hp;
        var state = new PlayerHudState(); Assert.True(Receive(state, packet));
        Assert.Equal(hp, state.Snapshot.FocusTarget.Hp); Assert.Equal(100, state.Snapshot.FocusTarget.HpMax);
    }

    [Theory]
    [InlineData("id", 0)]
    [InlineData("role", "enemy")]
    [InlineData("name", "")]
    [InlineData("extra", true)]
    public void InvalidTargetRejectsWholePacketWithoutPartialVitalsAdoption(string field, object value)
    {
        var state = new PlayerHudState(); Assert.True(Receive(state, Full())); var before = state.Snapshot;
        var packet = Full(1, 2); packet["groups"]["focusTarget"][field] = JToken.FromObject(value);
        packet["groups"]["vitals"]["hp"][0] = 1;
        Assert.False(Receive(state, packet)); Assert.Same(before, state.Snapshot);
    }

    [Fact]
    public void InvalidNumericAndOversizedTextFactsCannotBecomeAVisibleBar()
    {
        foreach (var hp in new[] { new JArray(1, 0), new JArray(1, -1), new JArray("NaN", 100),
                     new JArray(1, "Infinity"), new JArray(1, 100, 10) })
        {
            var packet = Full(); packet["groups"]["focusTarget"]["hp"] = hp;
            var state = new PlayerHudState(); Assert.False(Receive(state, packet)); Assert.Null(state.Snapshot);
        }
        var longName = Full(); longName["groups"]["focusTarget"]["name"] = new string('名', 193);
        Assert.False(Receive(new PlayerHudState(), longName));
    }

    [Fact]
    public void NegotiationUsesExistingSyncAndDisconnectDiscardsQueuedPriorConnectionTarget()
    {
        var sent = new List<string>(); var dispatch = new Queue<Action>();
        using var controller = new PlayerHudController(value => { sent.Add(value); return true; }, () => true, dispatch.Enqueue);
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Full()));
        dispatch.Dequeue()();
        Assert.Contains(sent, value => value.Contains("\"focusTarget\":true"));
        Assert.NotNull(controller.State.Snapshot.FocusTarget);
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Full(1, 2)));
        controller.Disconnected();
        while (dispatch.Count > 0) dispatch.Dequeue()();
        Assert.Null(controller.State.Snapshot);
    }

    [Theory]
    [InlineData(0, 36)]
    [InlineData(1, 36)]
    [InlineData(32, 36)]
    [InlineData(33, 68)]
    [InlineData(256, 260)]
    public void FollowsBuffRowsAndStaysClearOfTopToolbarAndScreenEdges(int buffs, float top)
    {
        var bounds = PlayerHudFocusTargetWidget.BoundsForBuffCount(buffs);
        Assert.Equal(top, bounds.Top);
        Assert.True(bounds.Left >= 0 && bounds.Right <= 1024 && bounds.Bottom < 576);
        Assert.True(bounds.Top >= Math.Max(32, Math.Ceiling(buffs / 32d) * 32) + 4);
        var notchLeft = (1024 - RightHudLayout.PreferredNotchMaxWidthBase) / 2f;
        Assert.True(bounds.Right + RightHudLayout.NotchRightGapBase <= notchLeft);
    }

    [Theory]
    [InlineData(1024, 576, 0, "boss")]
    [InlineData(1600, 900, 1, "boss")]
    [InlineData(1920, 1080, 33, "protect")]
    [InlineData(1024, 768, 256, "protect")]
    public void ProductionWidgetRendersInsideViewportAndRemainsPassiveAcrossSuppression(int width, int height, int buffs, string role)
    {
        Sta(() =>
        {
            RuntimeFontCatalog.Configure(Root());
            using var form = new Form { ClientSize = new Size(width, height), AutoScaleMode = AutoScaleMode.None };
            using var anchor = new Panel { Dock = DockStyle.Fill }; form.Controls.Add(anchor); form.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            var packet = Full(); packet["groups"]["focusTarget"]["role"] = role;
            packet["groups"]["focusTarget"]["name"] = role == "boss" ? "蛮斧刽子手" : "需要护送的目标与很长的中文称号";
            packet["groups"]["buffs"] = new JArray(Enumerable.Range(0, buffs).Select(i => new JObject
                { ["id"] = "b" + i, ["timed"] = false, ["total"] = 0, ["remaining"] = 0 }));
            Assert.True(Receive(controller.State, packet));
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);
            int paints = 0; widget.RepaintRequested += (_, _) => paints++;
            var changed = Target(); changed["hp"][0] = 75; changed["role"] = role;
            changed["name"] = packet["groups"]["focusTarget"]["name"].DeepClone();
            Assert.True(Receive(controller.State, Delta(2, new JObject { ["focusTarget"] = changed })));
            Assert.Equal(1, paints);
            var vitals = (JObject)packet["groups"]["vitals"].DeepClone(); vitals["hp"][0] = 555;
            Assert.True(Receive(controller.State, Delta(3, new JObject { ["vitals"] = vitals })));
            Assert.Equal(1, paints); // unrelated player changes do not repaint the target strip
            var origin = anchor.PointToScreen(Point.Empty);
            var bounds = widget.ScreenBounds; bounds.Offset(-origin.X, -origin.Y);
            var viewport = RightHudLayout.ViewportFromPanelSize(width, height);
            Assert.True(viewport.Contains(bounds));
            Assert.False(widget.TryHitTest(widget.ScreenBounds.Location)); Assert.False(widget.WantsAnimationTick);
            using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
            using (var graphics = Graphics.FromImage(bitmap)) { graphics.Clear(Color.Transparent); widget.Paint(graphics, 1, origin); }
            float scale = viewport.Height / 576f;
            var logical = PlayerHudFocusTargetWidget.BoundsForBuffCount(buffs);
            int barY = (int)(viewport.Top + (logical.Top + 23) * scale);
            var filled = bitmap.GetPixel((int)(viewport.Left + (logical.Left + 30) * scale), barY);
            var empty = bitmap.GetPixel((int)(viewport.Left + (logical.Right - 12) * scale), barY);
            Assert.True(filled.A > 0 && empty.A > 0);
            Assert.True(role == "boss" ? filled.R > filled.G : filled.B > filled.R);
            Assert.True(empty.R < 60 && empty.G < 60 && empty.B < 60);
            Assert.Equal(0, bitmap.GetPixel(viewport.Left + 10, viewport.Top + 5).A);
            // Exercise the actual widest notch and both persistent rows from the
            // reported paused Boss fight, not just the top toolbar rectangle.
            var fps = new FpsRingBuffer(600); fps.Push(30);
            using var notch = new NotchWidget(anchor, fps, Root(), () => { }, () => { }, () => { }, _ => { });
            notch.ForceGameReadyForTest(true); notch.ForceCurrenciesForTest(253331, 0);
            notch.BeginExpandForTest(); notch.Tick(10000);
            notch.SetStatusItem("wave", "波次 1/1 · 歼灭模式", "残敌 1", NativeHudTheme.Cyan);
            notch.SetStatusItem("pause", "游戏暂停", "", NativeHudTheme.Warning);
            notch.Tick(500);
            Assert.False(notch.ScreenBounds.IntersectsWith(widget.ScreenBounds));
            Assert.True(notch.ScreenBounds.Left - widget.ScreenBounds.Right >= Math.Floor(10 * scale));
            using (var graphics = Graphics.FromImage(bitmap)) notch.Paint(graphics, 1, origin);
            var evidence = Environment.GetEnvironmentVariable("CF7_FOCUS_HUD_EVIDENCE_DIR");
            if (!string.IsNullOrEmpty(evidence))
            {
                Directory.CreateDirectory(evidence);
                bitmap.Save(Path.Combine(evidence, $"target-{width}x{height}-{buffs}-{role}.png"), ImageFormat.Png);
            }
            widget.SetHostSuppressed(true); Assert.False(widget.Visible); Assert.Equal(Rectangle.Empty, widget.ScreenBounds);
            widget.SetHostSuppressed(false); Assert.True(widget.Visible); Assert.False(widget.WantsAnimationTick);
            Assert.True(Receive(controller.State, Delta(4, new JObject { ["focusTarget"] = JValue.CreateNull() })));
            Assert.False(widget.Visible); Assert.Equal(Rectangle.Empty, widget.ScreenBounds);
        });
    }

    private static string Root()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory != null && !File.Exists(Path.Combine(directory.FullName, "fonts", "fonts.xml"))) directory = directory.Parent;
        Assert.NotNull(directory); return directory.FullName;
    }
    private static void Sta(Action action)
    {
        Exception error = null;
        var thread = new Thread(() => { try { action(); } catch (Exception exception) { error = exception; } });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); Assert.True(thread.Join(45000));
        if (error != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(error).Throw();
    }
}
