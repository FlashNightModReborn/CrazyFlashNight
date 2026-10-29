using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Config;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudUsabilityTests
{
    private static JObject Buff(string id, string name = "护盾强化", bool timed = true) => new()
    {
        ["id"] = id, ["timed"] = timed, ["total"] = timed ? 300 : 0, ["remaining"] = timed ? 60 : 0,
        ["info"] = new JObject { ["name"] = name, ["description"] = "强化当前护盾。",
            ["polarity"] = "benefit", ["stacks"] = 2 }
    };

    [Fact]
    public void BuffMetadataAdoptsAtomicallyAndOlderProducersRemainReadable()
    {
        var state = new PlayerHudState(); var packet = PlayerHudStateTests.Full();
        packet["groups"]["buffs"] = new JArray(Buff("a"));
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet), 1));
        var accepted = state.Snapshot;
        Assert.Equal("护盾强化", accepted.Buffs[0].Name);
        Assert.Equal(2, accepted.Buffs[0].Stacks);
        foreach (var bad in new JToken[] { "evil", 1, null })
        {
            packet["seq"] = 2; packet["groups"]["buffs"][0]["info"]["polarity"] = bad;
            packet["groups"]["vitals"]["hp"][0] = 1;
            Assert.False(state.Receive(PlayerHudStateTests.Encode(packet), 2));
            Assert.Same(accepted, state.Snapshot);
        }
        ((JObject)packet["groups"]["buffs"][0]).Remove("info");
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet), 2));
        Assert.Equal("", state.Snapshot.Buffs[0].Name);
        Assert.Equal("neutral", state.Snapshot.Buffs[0].Polarity);
    }

    [Fact]
    public void BuffReflowsUntimedLeftTimedRightAndCompactsWithoutEmptyGaps()
    {
        Sta(() =>
        {
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            owner.Controls.Add(anchor); _ = owner.Handle; _ = anchor.Handle;
            var sent = new List<string>();
            using var controller = new PlayerHudController(raw => { sent.Add(raw); return true; }, () => true, a => a());
            using var widget = new PlayerHudBuffWidget(anchor, controller);
            using var tooltip = new PlayerHudResourceTooltip(anchor, controller, true);
            Assert.False(tooltip.Widget.UseHudChrome);
            var packet = PlayerHudStateTests.Full();
            // Even when a timed buff appears first in the wire array, untimed/permanent buffs sort to the left.
            packet["groups"]["buffs"] = new JArray(Buff("temp1", "临时护盾", timed: true), Buff("perm", "常驻被动", timed: false), Buff("temp2", "兴奋剂", timed: true));
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet)); sent.Clear();
            Assert.Equal(new[] { "perm", "temp1", "temp2" }, controller.State.Snapshot.BuffCards.Select(c => c.Id));
            Point At(int slot) { var r = PlayerHudBuffWidget.SlotRect(slot); return anchor.PointToScreen(new Point((int)r.X + 10, (int)r.Y + 10)); }
            void Hover(int slot) { var p = At(slot); widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, p.X, p.Y, 0), MouseEventKind.Move); }

            // Hovering the permanent buff on the left keeps its tooltip when a temporary buff on the right expires.
            Hover(0); Assert.NotNull(tooltip.Widget.ActiveDocument);
            packet["seq"] = 2; packet["groups"]["buffs"] = new JArray(Buff("perm", "常驻被动", timed: false), Buff("temp2", "兴奋剂", timed: true));
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.Equal(new[] { "perm", "temp2" }, controller.State.Snapshot.BuffCards.Select(c => c.Id));
            Assert.True(widget.TryHitTest(At(0))); Assert.True(widget.TryHitTest(At(1))); Assert.False(widget.TryHitTest(At(2)));
            Assert.NotNull(tooltip.Widget.ActiveDocument);

            // Adding another temporary buff and then expiring the middle one compacts the survivor left and closes the stale slot hover.
            packet["seq"] = 3; packet["groups"]["buffs"] = new JArray(Buff("perm", "常驻被动", timed: false), Buff("temp2", "兴奋剂", timed: true), Buff("temp3", "强心针", timed: true));
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Hover(2); Assert.NotNull(tooltip.Widget.ActiveDocument);
            packet["seq"] = 4; packet["groups"]["buffs"] = new JArray(Buff("perm", "常驻被动", timed: false), Buff("temp3", "强心针", timed: true));
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.Null(tooltip.Widget.ActiveDocument);
            Assert.True(widget.TryHitTest(At(0))); Assert.True(widget.TryHitTest(At(1))); Assert.False(widget.TryHitTest(At(2)));
            Hover(1); Assert.NotNull(tooltip.Widget.ActiveDocument);
            widget.SetHostSuppressed(true); Assert.Null(tooltip.Widget.ActiveDocument);
            Assert.Empty(sent); // Local inspection never dispatches a Flash write or tooltip request.
        });
    }

    [Theory]
    [InlineData(1f)]
    [InlineData(1.25f)]
    [InlineData(1.5625f)]
    [InlineData(2.5f)]
    public void ItemCountsStayInsideTheirBandAndClearOfTheRemovalCross(float scale)
    {
        Sta(()=> {
            using var owner=new Form{ClientSize=new Size(1024,576)};
            using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
            var root=new DirectoryInfo(AppContext.BaseDirectory);
            while(root!=null&&!Directory.Exists(Path.Combine(root.FullName,"launcher","web","icons")))root=root.Parent;
            Assert.NotNull(root);
            CF7Launcher.Fonts.RuntimeFontCatalog.Configure(root.FullName);
            using var widget=new PlayerHudBottomWidget(owner,controller,Path.Combine(root.FullName,"launcher","web","icons"));
            var slot=PlayerHudBottomWidget.DrugRect(0);var bounds=PlayerHudBottomWidget.CountRect(slot);
            Assert.True(bounds.Right<PlayerHudBottomWidget.DrugUnequipRect(0).Left);
            bounds.Offset(10-slot.X,10-slot.Y);
            foreach(var value in new[]{1d,99d,999d,9999d,41006d,int.MaxValue,9007199254740991d,double.MaxValue})
            {
                using var bitmap=new Bitmap((int)(60*scale),(int)(50*scale));
                using(var g=Graphics.FromImage(bitmap))
                {
                    g.Clear(Color.Transparent);g.ScaleTransform(scale,scale);
                    g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    widget.PaintCount(g,bounds,PlayerHudNumberFormat.Full(value));
                }
                var band=Rectangle.FromLTRB((int)Math.Floor(bounds.Left*scale),(int)Math.Floor(bounds.Top*scale),
                    (int)Math.Ceiling(bounds.Right*scale),(int)Math.Ceiling(bounds.Bottom*scale));
                var ink=0;
                for(var y=0;y<bitmap.Height;y++)for(var x=0;x<bitmap.Width;x++)
                {
                    var pixel=bitmap.GetPixel(x,y);
                    if(!band.Contains(x,y))Assert.Equal(0,pixel.A);
                    else if(pixel.R>150 && pixel.G>150 && pixel.B>150)ink++;
                }
                Assert.True(ink>3,"Count must remain visible: "+value);
            }
        });
    }

    [Fact]
    public void GroupedBuffKeepsOneCardAndTooltipAcrossReplacement()
    {
        Sta(() =>
        {
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            owner.Controls.Add(anchor); _ = owner.Handle; _ = anchor.Handle;
            var sent = new List<JObject>();
            using var controller = new PlayerHudController(raw => { sent.Add(JObject.Parse(raw.TrimEnd('\0'))); return true; }, () => true, action => action());
            using var widget = new PlayerHudBuffWidget(anchor, controller);
            using var tooltip = new PlayerHudResourceTooltip(anchor, controller, true);
            var packet = PlayerHudStateTests.Full();
            packet["groups"]["buffs"] = new JArray(PlayerHudStateTests.DetailedBuff("controller", primary: true),
                PlayerHudStateTests.DetailedBuff("effect"), Buff("other"));
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.Contains(sent, message => message["action"].Value<string>() == "playerHudSync" && message["buffDetails"].Value<bool>());
            sent.Clear();
            Assert.Equal(2, controller.State.Snapshot.BuffCards.Length);
            Point At(int slot) { var r = PlayerHudBuffWidget.SlotRect(slot); return anchor.PointToScreen(new Point((int)r.X + 10, (int)r.Y + 10)); }
            void Hover(int slot) { var p = At(slot); widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, p.X, p.Y, 0), MouseEventKind.Move); }
            string Text() => string.Concat(tooltip.Widget.ActiveDocument.Sections.Select(section => section.PlainText));
            Hover(0); var idle = tooltip.Widget.ActiveDocument;
            Assert.NotNull(idle); Assert.Contains("常态生效", Text()); Assert.Contains("空手攻击力：+30", Text());
            Assert.Contains("触发后持续约 3 秒", Text());

            packet["seq"] = 2;
            packet["groups"]["buffs"] = new JArray(PlayerHudStateTests.DetailedBuff("controller", primary: true, active: true),
                PlayerHudStateTests.DetailedBuff("effect", active: true), Buff("other"));
            packet["groups"]["buffs"][1]["incarnation"] = "effect:v2";
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            var burst = tooltip.Widget.ActiveDocument;
            Assert.NotSame(idle, burst); Assert.Contains("爆发中", Text()); Assert.Contains("空手攻击力：+100", Text());
            Assert.Contains("装备刀锋利度加成：-70", Text()); Assert.Contains("激活剩余约 3 秒", Text());
            Assert.True(widget.TryHitTest(At(0))); Assert.True(widget.TryHitTest(At(1)));

            packet["seq"] = 3; packet["groups"]["buffs"][0]["activation"]["remaining"] = 89;
            packet["groups"]["buffs"][1]["incarnation"] = "effect:v3";
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.Same(burst, tooltip.Widget.ActiveDocument);
            packet["seq"] = 4; packet["groups"]["buffs"][0]["activation"]["remaining"] = 60;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.NotSame(burst, tooltip.Widget.ActiveDocument); Assert.Contains("激活剩余约 2 秒", Text());

            packet["seq"] = 5;
            packet["groups"]["buffs"] = new JArray(packet["groups"]["buffs"][1], Buff("other"));
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.Equal(2, controller.State.Snapshot.BuffCards.Length);
            Assert.Null(tooltip.Widget.ActiveDocument); Assert.True(widget.TryHitTest(At(1)));
            Assert.Empty(sent);
        });
    }

    [Theory]
    [InlineData("full")]
    [InlineData("reduced")]
    [InlineData("static")]
    public void MotionPreferenceSurvivesRestartAndOnlyAcceptedSavesApply(string mode)
    {
        var root = Path.Combine(Path.GetTempPath(), "cf7-hud-motion-" + Guid.NewGuid().ToString("N"));
        try
        {
            var prefs = new UserPrefs(root, root);
            var writes = new List<string>(); var replies = new List<JObject>(); var applied = new List<string>();
            var save = true;
            using var task = new SettingsTask(() => true, raw => { writes.Add(raw); return true; }, prefs, () => save && prefs.Save(), 10000);
            task.SetPostToWeb(raw => replies.Add(JObject.Parse(raw)));
            Assert.True(task.BindPanelInstance("motion.1"));
            task.SetHostPreferenceApplied((key, value) => applied.Add(value.Value<string>()));
            void Set(JToken value) => task.HandleWebRequest("host_set", new JObject
            {
                ["domain"] = "settings", ["cmd"] = "host_set", ["panelInstanceId"] = "motion.1", ["callId"] = "motion." + replies.Count,
                ["payload"] = new JObject { ["v"] = 1, ["key"] = "hudMotionMode", ["value"] = value }
            });
            Set(mode);
            Assert.Equal(mode, prefs.HudMotionMode); Assert.Equal(mode, new UserPrefs(root, root).HudMotionMode);
            Assert.Equal(new[] { mode }, applied);
            Set("invalid"); Assert.Equal("bad_value", replies.Last().Value<string>("error"));
            Set(true); Assert.Equal("bad_value", replies.Last().Value<string>("error"));
            save = false; Set(mode == "static" ? "full" : "static");
            Assert.Equal("save_failed", replies.Last().Value<string>("error"));
            Assert.Equal(mode, prefs.HudMotionMode); Assert.Single(applied); Assert.Empty(writes);
        }
        finally
        {
            Assert.StartsWith(Path.GetFullPath(Path.GetTempPath()), Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase);
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    [Theory]
    [InlineData("full", false, false)]
    [InlineData("reduced", true, false)]
    [InlineData("static", true, true)]
    public void MotionModeChangesPresentationWithoutChangingTruth(string mode, bool reduced, bool stationary)
    {
        var oldMode = PlayerHudMotionSettings.Mode; var oldReduced = PlayerHudMotionSettings.ReducedMotion;
        try
        {
            PlayerHudMotionSettings.ReducedMotion = false; PlayerHudMotionSettings.Configure(mode);
            Assert.Equal(reduced, PlayerHudMotionSettings.ReducedMotion); Assert.Equal(stationary, PlayerHudMotionSettings.StaticFeedback);
            var state = new PlayerHudState(); state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full()), 1);
            var motion = new PlayerHudResourceMotion(); var v = state.Snapshot.Vitals;
            motion.Observe(v); var depleted = v with { Shield = 0 }; motion.Observe(depleted);
            Assert.Same(depleted, motion.ResolveShieldDisplay(depleted));
            if (stationary) Assert.Equal(0, PlayerHudMotionSettings.EventStrength);
        }
        finally { PlayerHudMotionSettings.Configure(oldMode); PlayerHudMotionSettings.ReducedMotion = oldReduced; }
    }

    private static void Sta(Action body)
    {
        Exception error = null;
        var thread = new Thread(() => { try { body(); } catch (Exception e) { error = e; } });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); Assert.True(thread.Join(10000));
        if (error != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(error).Throw();
    }
}
