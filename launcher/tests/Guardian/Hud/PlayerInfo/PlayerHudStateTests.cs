using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Text;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudStateTests
{
    [Fact]
    public void FreshAvm1FixtureIsAcceptedByTheProductionConsumer()
    {
        // Captured from PlayerHudServiceTest through a fresh CS6 TestLoader run.
        var path = System.IO.Path.Combine(AppContext.BaseDirectory, "Fixtures", "PlayerHud", "as2-wire.json");
        var state = new PlayerHudState();
        var raw = System.IO.File.ReadAllText(path, Encoding.UTF8);
        Assert.True(state.Receive(Convert.ToBase64String(Encoding.UTF8.GetBytes(raw)), 1));
        Assert.Equal(-5, state.Snapshot.Vitals.Hp);
        Assert.Equal(700, state.Snapshot.Vitals.Mp);
        Assert.Equal(0, state.Snapshot.Vitals.Level);
        Assert.Contains("😀", state.Snapshot.Vitals.Name);
        Assert.Equal(12, state.Snapshot.Loadout.Skills.Length);
        Assert.Equal(18, state.Snapshot.Cooldowns.Length);
    }

    internal static JObject Full(long epoch = 1, long seq = 1) => new()
    {
        ["v"] = 1, ["epoch"] = epoch, ["seq"] = seq, ["full"] = true, ["visible"] = true,
        ["groups"] = new JObject
        {
            ["vitals"] = new JObject { ["hp"] = new JArray(1400, 1000), ["mp"] = new JArray(500, 600),
                ["shield"] = new JArray(0, 400), ["shieldPresent"] = true, ["shieldReady"] = true, ["poise"] = 0.45,
                ["experience"] = new JArray(150, 100, 200), ["level"] = 3, ["name"] = "中文|姓名:引号\"\n😀",
                ["sp"] = 5, ["paused"] = false, ["decorations"] = true },
            ["combat"] = new JObject { ["mode"] = "双枪", ["ammo"] = new JArray("6", "12", "8", "3"),
                ["weapon"] = new JObject { ["visible"] = true, ["name"] = "战技", ["mp"] = 12, ["cooldownMs"] = 1000, ["key"] = "Q" } },
            ["loadout"] = new JObject { ["revision"] = 3, ["drugRevision"] = 4, ["bank"] = 0, ["switchKey"] = "6",
                ["skills"] = new JArray(Enumerable.Range(1, 12).Select(i => new JObject { ["slot"] = i,
                    ["equipped"] = true, ["skillKey"] = "技能" + i, ["keyLabel"] = "F" + i,
                    ["stateHealth"] = "ok", ["writeBlocked"] = false, ["level"] = 2, ["iconKey"] = "技能" + i })),
                ["drugs"] = new JArray(Enumerable.Range(0, 4).Select(i => new JObject { ["slot"] = i,
                    ["name"] = "药剂" + i, ["icon"] = "药剂图", ["count"] = 3, ["key"] = (i + 7).ToString() })) },
            ["cooldowns"] = new JArray(Enumerable.Range(0, 18).Select(_ => new JArray(1, 0, 0))),
            ["buffs"] = new JArray(new JObject { ["id"] = "1:buff", ["timed"] = true, ["total"] = 3000, ["remaining"] = 1000 })
        }
    };
    internal static string Encode(JObject value) => Convert.ToBase64String(Encoding.UTF8.GetBytes(value.ToString(Formatting.None)));

    [Fact]
    public void AdoptsRawOverflowAndUnicodeAtomically()
    {
        var state = new PlayerHudState(); Assert.True(state.Receive(Encode(Full()), 1));
        Assert.Equal(1400, state.Snapshot.Vitals.Hp); Assert.Equal(1000, state.Snapshot.Vitals.HpMax);
        Assert.Contains("|姓名:", state.Snapshot.Vitals.Name); Assert.Contains("😀", state.Snapshot.Vitals.Name);
        Assert.True(state.Snapshot.Vitals.ShieldPresent); Assert.Equal(0, state.Snapshot.Vitals.Shield);
        Assert.Equal(18, state.Snapshot.Cooldowns.Length);
    }

    [Fact]
    public void RejectsIncompleteEpochAndMalformedGroupWithoutPartialAdoption()
    {
        var state = new PlayerHudState(); state.Receive(Encode(Full()), 1); var before = state.Snapshot;
        var packet = Full(2, 2); ((JObject)packet["groups"]).Remove("loadout");
        Assert.False(state.Receive(Encode(packet), 2)); Assert.Same(before, state.Snapshot);
        packet = Full(1, 2); packet["groups"]["vitals"]["hp"] = new JArray(99, 100);
        packet["groups"]["loadout"]["drugs"][0]["slot"] = 4;
        Assert.False(state.Receive(Encode(packet), 2)); Assert.Equal(1400, state.Snapshot.Vitals.Hp);
    }

    [Fact]
    public void DeltaStaleClearAndReconnectRespectEpoch()
    {
        var state = new PlayerHudState(); state.Receive(Encode(Full(3, 10)), 1);
        var delta = Full(3, 11); delta["full"] = false;
        var groups = (JObject)delta["groups"]; foreach (var p in groups.Properties().Where(p => p.Name != "vitals").ToArray()) p.Remove();
        groups["vitals"]["hp"][0] = -5;
        Assert.True(state.Receive(Encode(delta), 2)); Assert.Equal(-5, state.Snapshot.Vitals.Hp);
        Assert.False(state.Receive(Encode(Full(3, 10)), 3)); Assert.False(state.Receive(Encode(Full(2, 99)), 3));
        Assert.True(state.Receive(Encode(new JObject { ["v"] = 1, ["epoch"] = 4, ["seq"] = 12, ["full"] = true, ["visible"] = false }), 4));
        Assert.Null(state.Snapshot); Assert.False(state.Receive(Encode(delta), 5));
        delta["epoch"] = 5; delta["seq"] = 13; Assert.False(state.Receive(Encode(delta), 5));
        state.Disconnect(); Assert.True(state.Receive(Encode(Full()), 6));
    }

    [Fact]
    public void ProductionGaugeKeepsOverflowAndNegativeReadoutsWhileGeometryClamps()
    {
        var state = new PlayerHudState(); state.Receive(Encode(Full()), 1);
        var model = new PlayerInfoAnimationModel(); model.ApplyProduction(state.Snapshot.Vitals);
        Assert.Equal("1400", model.VisualState.Hp.CurrentText); Assert.Equal("140", model.VisualState.Hp.PercentText);
        Assert.Equal(1, model.VisualState.Hp.TargetVirtualFrame);
        model.ApplyProduction(state.Snapshot.Vitals with { Hp = -5 });
        Assert.Equal("-5", model.VisualState.Hp.CurrentText); Assert.Equal(129, model.VisualState.Hp.TargetVirtualFrame);
        model.ApplyProduction(state.Snapshot.Vitals with { HpMax = 0 }); Assert.False(model.VisualState.Hp.HasRenderableState);
        model.ResetProduction(); Assert.False(model.VisualState.HasRenderableState);
    }

    [Theory]
    [InlineData(1400, 1000, "140%")]
    [InlineData(1750, 1000, "175%")]
    [InlineData(1150, 1000, "115%")]
    [InlineData(250, 1000, "25%")]
    [InlineData(0, 1000, "0%")]
    [InlineData(-5, 1000, "-1%")]
    [InlineData(100, 0, "--")]
    [InlineData(100, -1, "--")]
    [InlineData(double.PositiveInfinity, 100, "--")]
    public void ResourcePercentageRetainsOverflowAndRejectsUnknownMaximum(double current, double maximum, string expected)
        => Assert.Equal(expected, PlayerHudResourceStyle.Percent(current, maximum));

    [Fact]
    public void ShieldReadoutTracksCapacityDecayAndDistinguishesAbsenceFromZero()
    {
        var state = new PlayerHudState(); state.Receive(Encode(Full()), 1);
        var value = state.Snapshot.Vitals with { ShieldReady = true, ShieldPresent = true, Shield = 250, ShieldMax = 1000 };
        Assert.Equal("盾 250 · 25%", PlayerHudResourceStyle.ShieldReadout(value));
        Assert.Equal("盾 0 · 0%", PlayerHudResourceStyle.ShieldReadout(value with { Shield = 0 }));
        Assert.Equal("", PlayerHudResourceStyle.ShieldReadout(value with { ShieldPresent = false }));
        Assert.Equal("护盾未就绪", PlayerHudResourceStyle.ShieldReadout(value with { ShieldReady = false }));
    }

    [Fact]
    public void PoiseDetailIsAtomicAndMissingDetailCannotKeepAnOldSafeLabel()
    {
        var state = new PlayerHudState(); var packet = Full();
        packet["groups"]["vitals"]["poiseDetail"] = new JObject { ["threshold"] = 0.2928932188, ["hasStaggerBand"] = true, ["phase"] = "stagger" };
        Assert.True(state.Receive(Encode(packet), 1));
        Assert.Equal("踉跄风险", PlayerHudResourceStyle.PoiseCaption(state.Snapshot.Vitals.PoiseDetail));
        var prior = state.Snapshot;
        packet["seq"] = 2; packet["groups"]["vitals"]["hp"][0] = 90;
        packet["groups"]["vitals"]["poiseDetail"]["threshold"] = 1.01;
        Assert.False(state.Receive(Encode(packet), 2)); Assert.Same(prior, state.Snapshot);
        Assert.True(state.Receive(Encode(Full(1, 3)), 3));
        Assert.Null(state.Snapshot.Vitals.PoiseDetail);
        Assert.Equal("分界待就绪", PlayerHudResourceStyle.PoiseCaption(null));
    }

    [Fact]
    public void PoiseCapabilityIsRequestedOncePerAdoptedConnection()
    {
        var sent = new List<JObject>();
        using var controller = new PlayerHudController(raw => { sent.Add(JObject.Parse(raw.TrimEnd('\0'))); return true; }, () => true, action => action());
        controller.TakeUiData("pi:" + Encode(Full())); controller.TakeUiData("pi:" + Encode(Full(1, 2)));
        Assert.Single(sent); Assert.True((bool)sent[0]["poiseDetails"]);
        controller.Disconnected(); controller.TakeUiData("pi:" + Encode(Full()));
        controller.TakeUiData("pi:" + Encode(Full(1, 2)));
        // Reconnection also requests the pre-existing ordinary full-state resync.
        Assert.Equal(2, sent.Count(p => p["poiseDetails"]?.Value<bool>() == true));
    }

    [Fact]
    public void FreshAvm1PoiseFixtureUsesTheAuthoritativeBoundary()
    {
        var raw = System.IO.File.ReadAllText(System.IO.Path.Combine(AppContext.BaseDirectory, "Fixtures", "PlayerHud", "as2-poise-wire.json"), Encoding.UTF8);
        var state = new PlayerHudState();
        Assert.True(state.Receive(Convert.ToBase64String(Encoding.UTF8.GetBytes(raw)), 1));
        Assert.Equal(0.5, state.Snapshot.Vitals.PoiseDetail.Threshold);
        Assert.True(state.Snapshot.Vitals.PoiseDetail.HasStaggerBand);
        Assert.Equal("stagger", state.Snapshot.Vitals.PoiseDetail.Phase);
        Assert.True(state.Snapshot.Vitals.Poise < 0.5);
    }

    [Fact]
    public void DuplicateKeysAndOversizePayloadAreRejected()
    {
        var state = new PlayerHudState();
        Assert.False(state.Receive(Convert.ToBase64String(Encoding.UTF8.GetBytes("{\"v\":1,\"v\":1}")), 1));
        Assert.False(state.Receive(new string('A', PlayerHudState.MaximumEncodedLength + 1), 1));
        Assert.False(state.Receive("not base64!", 1)); Assert.Null(state.Snapshot);
    }

    [Fact]
    public void UnknownWriteOnlyQueriesAndSurvivesDisconnectAndSnapshotReplacement()
    {
        var sent = new List<JObject>();
        using var controller = new PlayerHudController(raw => { sent.Add(JObject.Parse(raw.TrimEnd('\0'))); return true; }, () => true, action => action());
        controller.TakeUiData("pi:" + Encode(Full()));
        var target = new PlayerHudTarget("drug", 0, "药剂0", 1, 4, 0, new RectangleF(343, 536, 26, 26));
        Assert.True(controller.Act(target)); Assert.False(controller.Act(target));
        var id = sent.Single(p => p["action"].Value<string>() == "playerHudAction")["actionId"].Value<string>();
        controller.Disconnected(); controller.TakeUiData("pi:" + Encode(Full(2, 2)));
        Assert.True(controller.WritePending);
        controller.Tick(Environment.TickCount64 + 10000);
        Assert.Single(sent.Where(p => p["action"].Value<string>() == "playerHudAction"));
        Assert.Contains(sent, p => p["action"].Value<string>() == "playerHudQuery");
        var ack = new JObject { ["v"] = 1, ["result"] = new JObject { ["actionId"] = id, ["success"] = false, ["error"] = "unknown", ["changed"] = false } };
        controller.TakeUiData("pi:" + Encode(ack)); Assert.True(controller.WritePending);
        ack["result"]["success"] = true; ack["result"]["error"] = "bad";
        controller.TakeUiData("pi:" + Encode(ack)); Assert.True(controller.WritePending);
        ack["result"]["error"] = ""; controller.TakeUiData("pi:" + Encode(ack)); Assert.False(controller.WritePending);
    }

    [Fact]
    public void HighFrequencyHudDoesNotReachUnrelatedUiConsumers()
    {
        using var controller = new PlayerHudController(_ => true, () => true, action => action());
        Assert.Equal("g:12|mm:2", controller.TakeUiData("g:12|pi:" + Encode(Full()) + "|mm:2"));
        Assert.Equal("", controller.TakeUiData("pi:" + Encode(Full(1, 2))));
        Assert.Equal("task|任务名称", controller.TakeUiData("task|任务名称"));
    }

    [Fact]
    public void AReconnectedActorCannotConsumeAPreviousConnectionsGesture()
    {
        using var controller = new PlayerHudController(_ => true, () => true, action => action());
        controller.TakeUiData("pi:" + Encode(Full()));
        var stale = new PlayerHudTarget("drug", 0, "药剂0", 1, 4, 0, new RectangleF(343, 536, 26, 26));
        controller.Disconnected();
        Assert.False(controller.CanInteract);
        // A new Flash process can reuse numeric epoch/revision values; the transport generation cannot.
        controller.TakeUiData("pi:" + Encode(Full()));
        Assert.True(controller.CanInteract);
        Assert.False(controller.Act(stale));
        Assert.True(controller.Act(stale with { ConnectionGeneration = controller.Generation }));
    }
}
