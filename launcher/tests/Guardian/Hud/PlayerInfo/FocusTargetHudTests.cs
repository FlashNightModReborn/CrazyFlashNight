using System;
using System.Collections.Generic;
using System.Diagnostics;
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
using CF7Launcher.Guardian.Hud.UnitLife;
using Newtonsoft.Json.Linq;
using Xunit;
using Xunit.Abstractions;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class FocusTargetHudTests(ITestOutputHelper output)
{
    private readonly ITestOutputHelper _output = output;
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
        Assert.Contains(sent, value => value.Contains("\"focusTarget\":true") && value.Contains("\"focusUnitInfo\":true"));
        Assert.NotNull(controller.State.Snapshot.FocusTarget);
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Full(1, 2)));
        controller.Disconnected();
        while (dispatch.Count > 0) dispatch.Dequeue()();
        Assert.Null(controller.State.Snapshot);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(10)]
    [InlineData(84)]
    [InlineData(256)]
    public void FirstRowKeepsTheAuthoredAnchorWhenBuffCountChanges(int buffs)
    {
        var bounds = PlayerHudFocusTargetWidget.BoundsForBuffCount(buffs);
        Assert.Equal(new RectangleF(6,0,294,36),bounds);
        // Second focus target stays full-width even when allies > 3
        Assert.Equal(new RectangleF(6,38,294,34),PlayerHudFocusTargetWidget.RowBounds(buffs,1,2,3));
        Assert.Equal(new RectangleF(6,38,294,34),PlayerHudFocusTargetWidget.RowBounds(buffs,1,2,4));
        Assert.Equal(new RectangleF(8,74,290,23),PlayerHudFocusTargetWidget.RowBounds(buffs,2,3,4));
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
            int barY = (int)(viewport.Top + (logical.Top + 25) * scale);
            var filled = bitmap.GetPixel((int)(viewport.Left + (logical.Left + 52) * scale), barY);
            var empty = bitmap.GetPixel((int)(viewport.Left + (logical.Right - 12) * scale), barY);
            Assert.True(filled.A > 0 && empty.A > 0);
            // D2 Muted Tactical AS2 palette: healthy HP is muted olive-green across roles (critical red only on protect <30%).
            Assert.True(filled.G > filled.R && filled.G > filled.B, $"Expected D2 olive-green HP pixel, got {filled}");
            Assert.True(empty.R < 60 && empty.G < 60 && empty.B < 60);
            Assert.Equal(0, bitmap.GetPixel(viewport.Left + 2, viewport.Top + 2).A);
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
    public void FocusTargetSupportsDamageTrailWarningBandsOverflowAndUnifiedTooltip()
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
            Assert.True(widget.IsCritical); // The protection row remains red below 30%.
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

    [Fact]
    public void EqualTargetFactsInNewEpochReinitializeWithoutLosingCriticalStateOrInheritingDamage()
    {
        Sta(() =>
        {
            PlayerHudMotionSettings.Configure("full");
            using var form = new Form { ClientSize = new Size(1024, 576) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            form.Controls.Add(anchor);
            form.CreateControl();
            anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);

            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Full()));
            var low = Full(1, 2);
            low["groups"]["focusTarget"]["hp"] = new JArray(25, 100);
            low["groups"]["focusTarget"]["role"] = "protect";
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(low));
            Assert.True(widget.IsCritical);
            Assert.Equal(.7, widget.TrailRatio, 8);
            low["epoch"] = 2;
            low["seq"] = 1;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(low));
            Assert.True(widget.IsCritical);
            Assert.Equal(.25, widget.TrailRatio, 8);
            Assert.Equal(0f, widget.GetHealAlpha(1));
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
            Assert.False(widget.IsTargetCritical(30));
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

            // Hover row 2 (combat target in full-width compact strip y=74..97)
            var combatRowPt = new Point(widget.ScreenBounds.Left + 150, widget.ScreenBounds.Top + 84);
            widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, combatRowPt.X, combatRowPt.Y, 0), MouseEventKind.Move);
            Assert.True(tooltip.Widget.Visible);
            var combatText = string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(s => s.Runs).Select(r => r.Text));
            Assert.Contains("重盾骑士", combatText);
            Assert.Contains("当前交战目标", combatText);
            Assert.DoesNotContain("危急", combatText);

            // Duplicate IDs or >8 targets must be rejected fail-closed
            var dupPacket = PlayerHudStateTests.Full(1, 2);
            dupPacket["groups"]["focusTarget"] = new JArray(Target(1), Target(1));
            Assert.False(Receive(controller.State, dupPacket));
            var overCapPacket = PlayerHudStateTests.Full(1, 3);
            overCapPacket["groups"]["focusTarget"] = new JArray(Enumerable.Range(1, 9).Select(id => Target(id)));
            Assert.False(Receive(controller.State, overCapPacket));
        });
    }

    [Fact]
    public void EightDistinctTargetsShareSevenSecondaryCellsEvenWithLegacyCompactHints()
    {
        var state = new PlayerHudState();
        var packet = Full();
        var targets = new JArray(Enumerable.Range(1, 8).Select(id => { var t = Target(id); t["compact"] = true; return t; }));
        packet["groups"]["focusTarget"] = targets;
        Assert.True(Receive(state, packet));
        Assert.Equal(8, state.Snapshot.TargetList.Length);
        Assert.All(state.Snapshot.TargetList, row => Assert.True(row.Compact));
        Assert.Equal(new RectangleF(8 + 5 * (290f / 6),74,290f / 6,23), PlayerHudFocusTargetWidget.RowBounds(0, 7, 8));
        Assert.Equal(new RectangleF(6,0,294,97), PlayerHudFocusTargetWidget.BoundsForBuffCount(0, 8));
        var fewer = new JArray(targets.Take(3).Select(t => t.DeepClone()));
        Assert.True(Receive(state, Delta(2, new JObject { ["focusTarget"] = fewer })));
        Assert.Equal(3, state.Snapshot.TargetList.Length);
        Assert.True(state.Snapshot.TargetList[0].Compact);
        Assert.Equal(new RectangleF(8,74,290,23), PlayerHudFocusTargetWidget.RowBounds(0, 2, 3));
        Assert.Equal("9999", PlayerHudFocusTargetWidget.DenseValue(9999));
        Assert.Equal("1万", PlayerHudFocusTargetWidget.DenseValue(10000));
        Assert.Equal("1.9万", PlayerHudFocusTargetWidget.DenseValue(19999));
        Assert.Equal("9999万", PlayerHudFocusTargetWidget.DenseValue(99999999));
        Assert.Equal("1亿", PlayerHudFocusTargetWidget.DenseValue(100_000_000));
        Assert.Equal("1.5万亿", PlayerHudFocusTargetWidget.DenseValue(1_599_999_999_999));
        Assert.Equal("-2亿", PlayerHudFocusTargetWidget.DenseValue(-200_000_000));
        Assert.Equal("1E16", PlayerHudFocusTargetWidget.DenseValue(1e16));
        Assert.Equal("<1%", PlayerHudFocusTargetWidget.DensePercent(1, 1000));
        Assert.Equal("0%", PlayerHudFocusTargetWidget.DensePercent(0, 1000));
    }

    [Theory]
    [InlineData(1, 1)]
    [InlineData(2, 2)]
    [InlineData(3, 2)]
    [InlineData(4, 2)]
    [InlineData(5, 2)]
    [InlineData(6, 2)]
    [InlineData(7, 2)]
    [InlineData(8, 2)]
    public void SecondaryTargetsShareOneRowAndEveryCellHoversItsOwnTarget(int count, int wide)
    {
        Sta(() =>
        {
            RuntimeFontCatalog.Configure(Root());
            PlayerHudMotionSettings.Configure("full");
            using var form = new Form { ClientSize = new Size(1024, 576), AutoScaleMode = AutoScaleMode.None };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            form.Controls.Add(anchor);
            form.CreateControl();
            anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var tooltip = new PlayerHudResourceTooltip(anchor, controller, true);
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);
            var packet = Full();
            packet["groups"]["buffs"] = new JArray();
            string[] protects = count == 5
                ? ["浮士德兄弟", "翅虎", "火凤", "黑龙"]
                : ["Tomboy", "主唱", "键盘", "吉他", "保护仪器", "守卫甲", "守卫乙"];
            packet["groups"]["focusTarget"] = new JArray(Enumerable.Range(1, count).Select(id =>
            {
                var row = Target(id);
                row["name"] = id == count ? "克隆兽" : protects[id - 1];
                row["role"] = id == count ? "combat" : "protect";
                row["hp"] = new JArray(15743, 21800);
                if (id == count) row["hits"] = 6;
                return row;
            }));
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.Equal(count, controller.State.Snapshot!.TargetList.Length);
            var displayed = PlayerHudFocusTargetWidget.OrderForDisplay(controller.State.Snapshot!.TargetList);
            if (count >= 2)
                Assert.Equal("克隆兽", displayed[1].Name); // active combat enemy always promoted to wide row 1
            using var bitmap = new Bitmap(1024, 576, PixelFormat.Format32bppPArgb);
            var origin = anchor.PointToScreen(Point.Empty);
            using (var graphics = Graphics.FromImage(bitmap))
                widget.Paint(graphics, 1, origin);
            var evidence = Environment.GetEnvironmentVariable("CF7_FOCUS_HUD_EVIDENCE_DIR");
            if (!string.IsNullOrEmpty(evidence))
            {
                Directory.CreateDirectory(evidence);
                using var strip = bitmap.Clone(new Rectangle(0, 0, 308, 140), bitmap.PixelFormat);
                strip.Save(Path.Combine(evidence, $"focus-queue-{count}.png"), ImageFormat.Png);
            }
            for (int i = 0; i < count; i++)
            {
                var item = PlayerHudFocusTargetWidget.RowBounds(0, i, count);
                Assert.Equal(i < wide, item.Width == 294);
                var cell = new Point((int)(item.Left + item.Width / 2), (int)(item.Top + item.Height / 2));
                Assert.NotEqual(0, bitmap.GetPixel(cell.X, cell.Y).A);
                var screen = anchor.PointToScreen(cell);
                widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, screen.X, screen.Y, 0), MouseEventKind.Move);
                Assert.True(tooltip.Widget.Visible);
                var text = string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(section => section.Runs).Select(run => run.Text));
                Assert.Contains(displayed[i].Name, text);
                Assert.Contains("15743 / 21800", text);
                Assert.Equal(i < wide && displayed[i].Hits > 0 ? 1f : 0f, widget.GetComboPulse(displayed[i].Id));
            }
            var bounds = PlayerHudFocusTargetWidget.BoundsForBuffCount(0, count);
            Assert.Equal(count == 1 ? 36f : count == 2 ? 72f : 97f, bounds.Bottom);
            Assert.Equal(bounds.Bottom, PlayerHudFocusTargetWidget.TopLeftBottomFor(0, count, false));

            if (count == 5)
            {
                // Row 1 is wide combat enemy (克隆兽); row 2 compact strip has 3 protects: 翅虎, 火凤, 黑龙.
                var queue = (JArray)packet["groups"]["focusTarget"]!;
                var wideRow1 = anchor.PointToScreen(new Point(150, 52));
                widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, wideRow1.X, wideRow1.Y, 0), MouseEventKind.Move);
                Assert.Contains("克隆兽", string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(s => s.Runs).Select(run => run.Text)));
                // Drop 克隆兽 -> remaining 4 protects: 浮士德兄弟 (row 0), 翅虎 (row 1), 火凤 & 黑龙 (row 2 strip)
                var four = new JArray(queue.Take(4).Select(item => item.DeepClone()));
                Assert.True(Receive(controller.State, Delta(2, new JObject { ["focusTarget"] = four })));
                widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, wideRow1.X, wideRow1.Y, 0), MouseEventKind.Move);
                Assert.Contains("翅虎", string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(s => s.Runs).Select(run => run.Text)));
                var rightStripCell = anchor.PointToScreen(new Point(250, 84));
                widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, rightStripCell.X, rightStripCell.Y, 0), MouseEventKind.Move);
                Assert.Contains("黑龙", string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(s => s.Runs).Select(run => run.Text)));
                Assert.True(Receive(controller.State, Delta(3, new JObject { ["focusTarget"] = queue.DeepClone() })));
                widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, wideRow1.X, wideRow1.Y, 0), MouseEventKind.Move);
                Assert.Contains("克隆兽", string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(s => s.Runs).Select(run => run.Text)));
            }
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

    [Fact]
    public void HealthRequestsTrackAndNumeralsWhileOnlyTrailTicksRequestJustTheTrack()
    {
        Sta(() =>
        {
            RuntimeFontCatalog.Configure(Root());
            PlayerHudMotionSettings.Configure("full");
            using var form = new Form();
            using var anchor = new Panel { Size = new Size(1600, 900) };
            form.Controls.Add(anchor);
            form.CreateControl();
            anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);
            EventArgs? damage = null;
            widget.RepaintRequested += (_, e) => damage = e;
            var target = Target();
            void SetHp(int seq, int hp)
            {
                target["hp"] = new JArray(hp, 100);
                var packet = Full(1, seq);
                packet["groups"]["buffs"] = new JArray();
                packet["groups"]["focusTarget"] = target.DeepClone();
                controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            }

            target["role"] = "protect";
            SetHp(1, 58);
            SetHp(2, 45);
            var update = Assert.IsType<HudRepaintRegions>(damage).Bounds;
            Assert.Equal(2, update.Length);
            Assert.True(update[1].Top < update[0].Top);
            damage = null;
            widget.Tick(150);
            var track = Assert.Single(Assert.IsType<HudRepaintRegions>(damage).Bounds);
            Assert.True(widget.ScreenBounds.Contains(track));
            Assert.True(track.Height < widget.ScreenBounds.Height / 2);
            SetHp(3, 15);
            var wholeRow = Rectangle.Inflate(widget.ScreenBounds, 2, 2); // 1600×900 centered stroke and AA fringe
            Assert.Equal(wholeRow, Assert.Single(Assert.IsType<HudRepaintRegions>(damage).Bounds));
            damage = null;
            widget.Tick(33);
            Assert.True(Assert.Single(Assert.IsType<HudRepaintRegions>(damage).Bounds).Height < wholeRow.Height / 2);
        });
    }

    [Fact]
    public void D2UnitInfoBarRendersShieldPoiseRigidCriticalAndTooltipDetails()
    {
        Sta(() =>
        {
            RuntimeFontCatalog.Configure(Root());
            PlayerHudMotionSettings.Configure("full");
            using var form = new Form { ClientSize = new Size(1920, 1080), AutoScaleMode = AutoScaleMode.None };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            form.Controls.Add(anchor);
            form.CreateControl();
            anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var tooltip = new PlayerHudResourceTooltip(anchor, controller, true);
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);

            var packet = Full();
            var target = Target();
            target["hp"] = new JArray(7800, 10000);
            target["shield"] = new JArray(420, 600);
            target["poise"] = 204; // 80%
            target["flags"] = 4;   // rigid
            target["hitSeq"] = 1;
            packet["groups"]["focusTarget"] = new JArray(target);
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));

            var origin = anchor.PointToScreen(Point.Empty);
            using var bmp = new Bitmap(1920, 1080, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(bmp)) { g.Clear(Color.Transparent); widget.Paint(g, 1, origin); }
            var viewport = RightHudLayout.ViewportFromPanelSize(1920, 1080);
            float scale = viewport.Height / 576f;

            // Sample upper shield cap (~y=23.2), upper HP body (~y=26.6), lower rigid track (~y=31.2) at x=90
            int sampleX = (int)(viewport.Left + 90 * scale);
            var shieldPx = bmp.GetPixel(sampleX, (int)(viewport.Top + 23.2f * scale));
            var hpPx = bmp.GetPixel(sampleX, (int)(viewport.Top + 26.6f * scale));
            var rigidPx = bmp.GetPixel(sampleX, (int)(viewport.Top + 31.2f * scale));
            Assert.True(shieldPx.B > shieldPx.R && shieldPx.G > shieldPx.R, $"Expected ice-cyan shield cap, got {shieldPx}");
            Assert.True(hpPx.G > hpPx.R && hpPx.G > hpPx.B, $"Expected D2 olive-green HP fill, got {hpPx}");
            Assert.True(rigidPx.R > rigidPx.B + 40 && rigidPx.R > 120, $"Expected molten-orange rigid track, got {rigidPx}");

            // Hover tooltip shows shield, poise and rigid status
            var hoverPt = new Point(widget.ScreenBounds.Left + 60, widget.ScreenBounds.Top + 18);
            widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, hoverPt.X, hoverPt.Y, 0), MouseEventKind.Move);
            Assert.True(tooltip.Widget.Visible);
            var tipText = string.Concat(tooltip.Widget.ActiveDocument!.Sections.SelectMany(s => s.Runs).Select(r => r.Text));
            Assert.Contains("护盾：420 / 600（70%）", tipText);
            Assert.Contains("韧性：80% · 刚体霸体", tipText);

            // Protect critical (<30%) flips upper HP bar to crimson red
            var crit = (JObject)target.DeepClone();
            crit["role"] = "protect";
            crit["hp"] = new JArray(2000, 10000);
            crit["shield"] = new JArray(0, 0);
            crit["flags"] = 0;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Delta(2, new JObject { ["focusTarget"] = new JArray(crit) })));
            using var critBmp = new Bitmap(1920, 1080, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(critBmp)) { g.Clear(Color.Transparent); widget.Paint(g, 1, origin); }
            var critPx = critBmp.GetPixel((int)(viewport.Left + 55 * scale), (int)(viewport.Top + 25.5f * scale));
            Assert.True(critPx.R > critPx.G + 40 && critPx.R > critPx.B + 40, $"Expected critical red HP fill, got {critPx}");
        });
    }

    [Fact]
    public void ShieldPoiseAndHitSeqOnlyRepaintLifeTrackWithoutTouchingReadout()
    {
        Sta(() =>
        {
            RuntimeFontCatalog.Configure(Root());
            PlayerHudMotionSettings.Configure("full");
            using var form = new Form();
            using var anchor = new Panel { Size = new Size(1600, 900) };
            form.Controls.Add(anchor);
            form.CreateControl();
            anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);

            var row = Target();
            row["shield"] = new JArray(200, 500);
            row["poise"] = 180;
            row["flags"] = 0;
            row["hitSeq"] = 1;
            var p1 = Full(1, 1);
            p1["groups"]["focusTarget"] = new JArray(row.DeepClone());
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(p1));
            Assert.False(widget.WantsAnimationTick); // initial hitSeq does not spuriously flash

            EventArgs? damage = null;
            widget.RepaintRequested += (_, e) => damage = e;

            // Only shield, poise, rigid, hitSeq change while HP stays constant -> single track-only dirty rect
            row["shield"] = new JArray(120, 500);
            row["poise"] = 128;
            row["flags"] = 4;
            row["hitSeq"] = 2;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Delta(2, new JObject { ["focusTarget"] = new JArray(row.DeepClone()) })));
            var area = Assert.Single(Assert.IsType<HudRepaintRegions>(damage).Bounds);
            Assert.True(widget.ScreenBounds.Contains(area));
            Assert.True(area.Height < widget.ScreenBounds.Height / 2);
            Assert.True(widget.WantsAnimationTick); // hitSeq bump triggered 115ms hit flash

            widget.Tick(130);
            Assert.False(widget.WantsAnimationTick);
        });
    }

    [Fact]
    public void ComboHitIncrementAndPulseEmitNarrowHitChipDamagePixelIdenticalToFullRepaint()
    {
        Sta(() =>
        {
            RuntimeFontCatalog.Configure(Root());
            using var form = new Form { AutoScaleMode = AutoScaleMode.None, ClientSize = new Size(1920, 1080) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            form.Controls.Add(anchor); form.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var widget = new PlayerHudFocusTargetWidget(anchor, controller);

            var packet = PlayerHudStateTests.Full();
            packet["groups"]["focusTarget"] = new JArray(
                new JObject { ["id"] = 1, ["role"] = "protect", ["name"] = "Tomboy", ["hp"] = new JArray(15000, 20000) },
                new JObject { ["id"] = 2, ["role"] = "combat", ["name"] = "克隆兽", ["hp"] = new JArray(15000, 20000), ["hits"] = 12, ["shield"] = new JArray(200, 500), ["poise"] = 160, ["flags"] = 1, ["hitSeq"] = 1 });
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet), 1));

            var origin = anchor.PointToScreen(Point.Empty);
            using var partial = new Bitmap(600, 160, PixelFormat.Format32bppPArgb);
            using var full = new Bitmap(600, 160, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(partial)) widget.Paint(g, 1f, origin);

            Rectangle[]? damaged = null;
            widget.RepaintRequested += (_, e) => damaged = (e as HudRepaintRegions)?.Bounds;

            // Same-digit combo increment (12 -> 13) + HP drop must NOT trigger whole-row repaint
            Assert.True(controller.State.Receive("~1,1,2;f,1,2,14500,20000,13,200,500,160,1,2", 2));
            Assert.NotNull(damaged);
            Assert.Equal(3, damaged!.Length);
            long area = damaged!.Sum(r => (long)r.Width * r.Height);
            long wholeRowArea = (long)Math.Ceiling(294 * 1.875) * (long)Math.Ceiling(34 * 1.875);
            Assert.True(area < wholeRowArea * 0.75, $"Expected narrow track+readout+hitChip dirty area (<75% of row), got {area} vs row {wholeRowArea}");

            void ApplyPartial(Rectangle[] rects)
            {
                using var g = Graphics.FromImage(partial);
                using var reg = new Region();
                reg.MakeEmpty();
                foreach (var r in rects) reg.Union(new Rectangle(r.X - origin.X, r.Y - origin.Y, r.Width, r.Height));
                g.SetClip(reg, System.Drawing.Drawing2D.CombineMode.Replace);
                g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                g.FillRectangle(Brushes.Transparent, 0, 0, partial.Width, partial.Height);
                g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceOver;
                widget.Paint(g, 1f, origin);
            }

            ApplyPartial(damaged!);
            using (var g = Graphics.FromImage(full)) { g.Clear(Color.Transparent); widget.Paint(g, 1f, origin); }
            AssertBitmapsEqual(full, partial);

            // ComboPulse tick must also stay narrow and pixel-identical
            damaged = null;
            widget.Tick(33);
            Assert.NotNull(damaged);
            long tickArea = damaged!.Sum(r => (long)r.Width * r.Height);
            Assert.True(tickArea < wholeRowArea * 0.55, $"Expected narrow combo+track tick area (<55% of row), got {tickArea} vs row {wholeRowArea}");
            ApplyPartial(damaged!);
            using (var g = Graphics.FromImage(full)) { g.Clear(Color.Transparent); widget.Paint(g, 1f, origin); }
            AssertBitmapsEqual(full, partial);
        });
    }

    private static void AssertBitmapsEqual(Bitmap expected, Bitmap actual)
    {
        Assert.Equal(expected.Size, actual.Size);
        for (int y = 0; y < expected.Height; y++)
            for (int x = 0; x < expected.Width; x++)
                Assert.True(expected.GetPixel(x, y) == actual.GetPixel(x, y), $"Pixel mismatch at ({x},{y}): expected {expected.GetPixel(x, y)} actual {actual.GetPixel(x, y)}");
    }

    [Fact]
    public void WorldScaleUnitLifeBarPainter100BarsOffscreenBenchmark()
    {
        // Offscreen benchmark for future #38 world-space unit info migration:
        // 100 heterogeneous 45×6.8 logical bars at 1080p (1.875x -> ~84×13 px) painted per frame.
        UnitLifeBarPainter.ClearCache();
        using var bmp = new Bitmap(1920, 1080, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(bmp);
        g.ScaleTransform(1.875f, 1.875f);

        var rects = new RectangleF[100];
        var visuals = new UnitLifeBarVisual[100];
        for (int i = 0; i < 100; i++)
        {
            int col = i % 10, row = i / 10;
            rects[i] = new RectangleF(12f + col * 98f, 12f + row * 52f, 45f, 6.8f);
            double hp = 15 + (i * 19 % 86);
            double trail = Math.Min(1.0, hp / 100.0 + (i % 3 == 0 ? 0.18 : 0.0));
            visuals[i] = new UnitLifeBarVisual(
                new UnitHealth(hp, 100),
                trail,
                LossAlpha: 1f,
                LossActive: trail > hp / 100.0,
                HealStartRatio: hp / 100.0,
                GainAlpha: 0f,
                Critical: false,
                ShieldRatio: i % 4 == 0 ? 0.6 : 0.0,
                PoiseRatio: (i % 10) / 10.0,
                HasPoise: true,
                Rigid: i % 7 == 0,
                Airborne: i % 11 == 0,
                Down: false,
                Darkened: i % 5 == 0,
                HitFlash: i % 9 == 0 ? 0.8f : 0f,
                Alpha: i % 13 == 0 ? 0.65f : 1f);
        }

        // Cold bake + warmup
        for (int w = 0; w < 5; w++)
            for (int i = 0; i < 100; i++)
                UnitLifeBarPainter.Paint(g, rects[i], visuals[i], UnitLifeBarStyle.Hostile, 1f,
                    UnitInfoBarTheme.As2ClassicWorld, slanted: false);

        const int frames = 40;
        var timesMs = new double[frames];
        var sw = new Stopwatch();
        for (int f = 0; f < frames; f++)
        {
            sw.Restart();
            for (int i = 0; i < 100; i++)
                UnitLifeBarPainter.Paint(g, rects[i], visuals[i], UnitLifeBarStyle.Hostile, 1f,
                    UnitInfoBarTheme.As2ClassicWorld, slanted: false);
            sw.Stop();
            timesMs[f] = sw.Elapsed.TotalMilliseconds;
        }
        Array.Sort(timesMs);
        double p50 = timesMs[frames / 2];
        double p95 = timesMs[(int)(frames * 0.95)];
        _output.WriteLine($"[UnitLifeBarPainter 100x world bars @1080p] p50={p50:F2}ms p95={p95:F2}ms min={timesMs[0]:F2}ms max={timesMs[^1]:F2}ms");
        // Verify reasonable CPU headroom on offscreen GDI+ surface (wide CI-safe bound; real measurement printed above)
        Assert.True(p95 < 100.0, $"100-bar offscreen p95 unexpectedly high: {p95:F2}ms");
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
