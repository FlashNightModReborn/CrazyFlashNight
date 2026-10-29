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
using CF7Launcher.Guardian.Hud.Loot;
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
    [InlineData(0, 4)]
    [InlineData(1, 36)]
    [InlineData(10, 36)]
    [InlineData(11, 68)]
    [InlineData(32, 132)]
    [InlineData(33, 132)]
    [InlineData(80, 260)]
    [InlineData(81, 280)]
    [InlineData(256, 280)]
    public void FollowsBuffRowsAndCompactsToTopWhenNoBuffsExist(int buffs, float top)
    {
        var bounds = PlayerHudFocusTargetWidget.BoundsForBuffCount(buffs);
        Assert.Equal(top, bounds.Top);
        Assert.True(bounds.Left >= 0 && bounds.Right <= 1024 && bounds.Bottom < 576);
        var notchLeft = (1024 - RightHudLayout.PreferredNotchMaxWidthBase) / 2f;
        Assert.True(bounds.Right + RightHudLayout.NotchRightGapBase <= notchLeft);
    }

    [Theory]
    [InlineData(1024, 576, 0, "boss")]
    [InlineData(1600, 900, 1, "boss")]
    [InlineData(1920, 1080, 33, "protect")]
    [InlineData(1024, 768, 256, "protect")]
    public void ProductionWidgetRendersInsideViewportAndSupportsReadOnlyHoverAcrossSuppression(int width, int height, int buffs, string role)
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
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.NotNull(controller.State.Snapshot);
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);
            int paints = 0; widget.RepaintRequested += (_, _) => paints++;
            var changed = Target(); changed["hp"][0] = 75; changed["role"] = role;
            changed["name"] = packet["groups"]["focusTarget"]["name"].DeepClone();
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Delta(2, new JObject { ["focusTarget"] = changed })));
            Assert.Equal(1, paints);
            var vitals = (JObject)packet["groups"]["vitals"].DeepClone(); vitals["hp"][0] = 555;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Delta(3, new JObject { ["vitals"] = vitals })));
            Assert.Equal(1, paints); // unrelated player changes do not repaint the target strip
            var origin = anchor.PointToScreen(Point.Empty);
            var bounds = widget.ScreenBounds; bounds.Offset(-origin.X, -origin.Y);
            var viewport = RightHudLayout.ViewportFromPanelSize(width, height);
            Assert.True(viewport.Contains(bounds));
            Assert.True(widget.TryHitTest(new Point(widget.ScreenBounds.Left + 2, widget.ScreenBounds.Top + 2)));
            Assert.False(widget.NeedsPointerClick);
            Assert.False(widget.WantsAnimationTick);
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
            Assert.Equal(0, bitmap.GetPixel(viewport.Left + 10, viewport.Top + 2).A);
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

    [Fact]
    public void FocusTargetSupportsDamageTrailCriticalHysteresisOverflowAndUnifiedTooltip()
    {
        Sta(() =>
        {
            RuntimeFontCatalog.Configure(Root());
            PlayerHudMotionSettings.Configure("full");
            using var form = new Form { ClientSize = new Size(1024, 576), AutoScaleMode = AutoScaleMode.None };
            using var anchor = new Panel { Dock = DockStyle.Fill }; form.Controls.Add(anchor); form.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var tooltip = new PlayerHudResourceTooltip(anchor, controller, true);
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);

            var packet = Full();
            packet["groups"]["focusTarget"]["role"] = "protect";
            packet["groups"]["focusTarget"]["name"] = "需要护送的重要幸存者车队";
            packet["groups"]["focusTarget"]["hp"] = new JArray(140, 100);
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.Equal(1.0, widget.TrailRatio, 3);
            Assert.False(widget.IsCritical);

            var hit = Target();
            hit["role"] = "protect";
            hit["name"] = "需要护送的重要幸存者车队";
            hit["hp"] = new JArray(22, 100);
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Delta(2, new JObject { ["focusTarget"] = hit })));
            Assert.Equal(1.0, widget.TrailRatio, 3);
            Assert.True(widget.IsCritical);
            Assert.True(widget.WantsAnimationTick);

            // Advance clock: damage trail holds for 90ms then contracts smoothly over 230ms
            widget.Tick(200);
            Assert.True(widget.TrailRatio < 1.0 && widget.TrailRatio > 0.22);
            widget.Tick(200);
            Assert.Equal(0.22, widget.TrailRatio, 3);

            var slightHeal = (JObject)hit.DeepClone();
            slightHeal["hp"] = new JArray(28, 100);
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Delta(3, new JObject { ["focusTarget"] = slightHeal })));
            Assert.True(widget.IsCritical); // 25% enter, >30% exit hysteresis
            Assert.True(widget.GetHealAlpha(1) > 0f);

            var hoverPt = new Point(widget.ScreenBounds.Left + 20, widget.ScreenBounds.Top + 10);
            widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, hoverPt.X, hoverPt.Y, 0), MouseEventKind.Move);
            Assert.True(tooltip.Widget.Visible);
            var text = string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(s => s.Runs).Select(r => r.Text));
            Assert.Contains("需要护送的重要幸存者车队", text);
            Assert.Contains("保护目标（需存活）", text);
            Assert.Contains("28 / 100（28%）", text);

            var safeHeal = (JObject)hit.DeepClone();
            safeHeal["hp"] = new JArray(35, 100);
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Delta(4, new JObject { ["focusTarget"] = safeHeal })));
            Assert.False(widget.IsCritical);
            Assert.True(widget.WantsAnimationTick);
            widget.Tick(400);
            Assert.Equal(0f, widget.GetHealAlpha(1), 3);
            Assert.False(widget.WantsAnimationTick); // returns to idle once heal preview & critical state end

            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Delta(5, new JObject { ["focusTarget"] = JValue.CreateNull() })));
            tooltip.Widget.Tick(2000); // 淡出窗口走完，会话才结束
            Assert.False(tooltip.Widget.Visible);
        });
    }

    private sealed class RecordingDollBakeSink : IDollBakeSink
    {
        internal readonly List<string> Keys = new();
        public void EnsurePortrait(IReadOnlyDictionary<string, string> tuple, string key) => Keys.Add(key);
    }

    [Fact]
    public void MultiTargetListPortraitsAndCombatRoleRenderAndHoverIndependently()
    {
        Sta(() =>
        {
            var root = Root();
            RuntimeFontCatalog.Configure(root);
            PlayerHudMotionSettings.Configure("full");
            using var form = new Form { ClientSize = new Size(1024, 576), AutoScaleMode = AutoScaleMode.None };
            using var anchor = new Panel { Dock = DockStyle.Fill }; form.Controls.Add(anchor); form.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var tooltip = new PlayerHudResourceTooltip(anchor, controller, true);
            using var icons = new LootIconCatalog(
                Path.Combine(root, "launcher", "web", "icons"),
                Path.Combine(root, "launcher", "web", "assets", "enemy-portraits"));
            var dollBake = new RecordingDollBakeSink();
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller, icons, dollBake);

            var packet = PlayerHudStateTests.Full();
            packet["groups"]["focusTarget"] = new JArray(
                new JObject
                {
                    ["id"] = 10, ["role"] = "protect", ["name"] = "护送目标", ["hp"] = new JArray(280, 400),
                    ["doll"] = new JObject { ["face"] = "男脸", ["hair"] = "短发", ["gender"] = "男" }
                },
                new JObject
                {
                    ["id"] = 20, ["role"] = "boss", ["name"] = "忍者BOSS", ["hp"] = new JArray(900, 1000),
                    ["icon"] = "敌人-忍者BOSS"
                },
                new JObject
                {
                    ["id"] = 30, ["role"] = "combat", ["name"] = "重盾骑士", ["hp"] = new JArray(180, 1000),
                    ["icon"] = "重盾骑士"
                });
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            var list = controller.State.Snapshot!.TargetList;
            Assert.Equal(3, list.Length);
            Assert.Single(dollBake.Keys);
            Assert.StartsWith("纸娃娃-", list[0].PortraitKey, StringComparison.Ordinal);
            Assert.Equal(dollBake.Keys[0], list[0].PortraitKey);
            Assert.True(widget.IsTargetCritical(30));
            Assert.False(widget.IsTargetCritical(20));

            using var bitmap = new Bitmap(1024, 576, PixelFormat.Format32bppPArgb);
            var origin = anchor.PointToScreen(Point.Empty);
            using (var g = Graphics.FromImage(bitmap)) { g.Clear(Color.Transparent); widget.Paint(g, 1, origin); }
            // Row 1 (boss) portrait box at (6+3, 4+33+3, 22, 24) should contain non-transparent rasterized SVG portrait pixels
            bool hasBossPortraitPixel = false;
            for (int y = 42; y < 60 && !hasBossPortraitPixel; y++)
                for (int x = 11; x < 26 && !hasBossPortraitPixel; x++)
                    if (bitmap.GetPixel(x, y).A > 0) hasBossPortraitPixel = true;
            Assert.True(hasBossPortraitPixel);

            // Hover row 2 (combat target)
            var combatRowPt = new Point(widget.ScreenBounds.Left + 40, widget.ScreenBounds.Top + (int)(2 * 33) + 12);
            widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, combatRowPt.X, combatRowPt.Y, 0), MouseEventKind.Move);
            Assert.True(tooltip.Widget.Visible);
            var combatText = string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(s => s.Runs).Select(r => r.Text));
            Assert.Contains("重盾骑士", combatText);
            Assert.Contains("当前交战目标", combatText);
            Assert.Contains("状态：目标生命危急", combatText);

            // Duplicate IDs or >4 targets must be rejected fail-closed
            var dupPacket = PlayerHudStateTests.Full(1, 2);
            dupPacket["groups"]["focusTarget"] = new JArray(Target(1), Target(1));
            Assert.False(Receive(controller.State, dupPacket));
            var overCapPacket = PlayerHudStateTests.Full(1, 3);
            overCapPacket["groups"]["focusTarget"] = new JArray(Target(1), Target(2), Target(3), Target(4), Target(5));
            Assert.False(Receive(controller.State, overCapPacket));
        });
    }

    [Fact]
    public void SixDigitExactHpAndEmbeddedComboHitBadgeRenderAndPulseCleanly()
    {
        Sta(() =>
        {
            var root = Root();
            RuntimeFontCatalog.Configure(root);
            PlayerHudMotionSettings.Configure("full");

            // 1. 6-digit Boss HP (< 1,000,000) stays exact integer; >= 1,000,000 compacts to 万
            using var glyphs = new PlayerHudNumberGlyphs();
            Func<string, float> measure = s => glyphs.Measure(PlayerInfoPathGlyphAtlas.Aero, s, 11.2f);
            var sixDigitTarget = new PlayerHudFocusTarget(1, "boss", "机械巨龙", 158420, 200000);
            var sixDigitLayout = PlayerHudNumberFormat.FormatText(
                PlayerHudFocusTargetWidget.CompactHealthText(sixDigitTarget),
                measure, PlayerHudFocusTargetWidget.HpReadoutMaxWidth, PlayerHudFocusTargetWidget.ExactHpCompactThreshold);
            Assert.Equal("158420/200000", sixDigitLayout.Text);

            var sevenDigitTarget = new PlayerHudFocusTarget(1, "boss", "终焉巨兽", 1250000, 2000000);
            var sevenDigitLayout = PlayerHudNumberFormat.FormatText(
                PlayerHudFocusTargetWidget.CompactHealthText(sevenDigitTarget),
                measure, PlayerHudFocusTargetWidget.HpReadoutMaxWidth, PlayerHudFocusTargetWidget.ExactHpCompactThreshold);
            Assert.Contains("万", sevenDigitLayout.Text);

            // 2. Wire protocol accepts positive hits, rejects invalid hits, and triggers 150ms combo badge pulse
            using var form = new Form { ClientSize = new Size(1024, 576), AutoScaleMode = AutoScaleMode.None };
            using var anchor = new Panel { Dock = DockStyle.Fill }; form.Controls.Add(anchor); form.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var tooltip = new PlayerHudResourceTooltip(anchor, controller, true);
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);

            var packet = Full();
            packet["groups"]["focusTarget"]["hp"] = new JArray(158420, 200000);
            packet["groups"]["focusTarget"]["hits"] = 18;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.Equal(18, controller.State.Snapshot!.FocusTarget!.Hits);
            Assert.Equal(1f, widget.GetComboPulse(1), 3);
            Assert.True(widget.WantsAnimationTick);

            using var bitmap = new Bitmap(1024, 576, PixelFormat.Format32bppPArgb);
            var origin = anchor.PointToScreen(Point.Empty);
            using (var g = Graphics.FromImage(bitmap)) { g.Clear(Color.Transparent); widget.Paint(g, 1, origin); }

            // Hover tooltip includes combo count and exact 6-digit HP
            var hoverPt = new Point(widget.ScreenBounds.Left + 50, widget.ScreenBounds.Top + 10);
            widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, hoverPt.X, hoverPt.Y, 0), MouseEventKind.Move);
            Assert.True(tooltip.Widget.Visible);
            var text = string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(s => s.Runs).Select(r => r.Text));
            Assert.Contains("158420 / 200000（79%）", text);
            Assert.Contains("当前连击：18 Hit", text);

            // Tick 160ms: combo pulse finishes and widget returns to idle
            widget.Tick(160);
            Assert.Equal(0f, widget.GetComboPulse(1), 3);
            Assert.False(widget.WantsAnimationTick);

            // Invalid hits <= 0 is rejected fail-closed
            var badHits = Full(1, 2);
            badHits["groups"]["focusTarget"]["hits"] = 0;
            Assert.False(Receive(controller.State, badHits));
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
