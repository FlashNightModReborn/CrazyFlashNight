using CF7Launcher.Guardian.Hud.PlayerInfo;
using System.Linq;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudResourceFactsTests
{
    [Fact]
    public void FreshAvm1ResourceFixturePreservesStrengthResistanceAndCoexistingFlags()
    {
        // Actual CS6 run 3907f4b50d524e22b0656c6b3488ba45, PlayerHudServiceTest 82/82.
        var path = System.IO.Path.Combine(System.AppContext.BaseDirectory,
            "Fixtures", "PlayerHud", "as2-resource-wire.json");
        var raw = System.IO.File.ReadAllText(path, System.Text.Encoding.UTF8);
        var state = new PlayerHudState();
        Assert.True(state.Receive(System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(raw)), 1));
        var vitals = state.Snapshot.Vitals;
        Assert.Equal(130, vitals.Hp);
        Assert.Equal(150, vitals.Mp);
        Assert.True(vitals.PoiseVisual.Airborne);
        Assert.True(vitals.PoiseVisual.Rigid);
        Assert.Equal("air", vitals.PoiseDetail.Phase);
        Assert.Equal("finite", vitals.ShieldDetail.StrengthKind);
        Assert.Equal(99999999, vitals.ShieldDetail.Strength);
        Assert.True(vitals.ShieldDetail.ResistsBypass);
        Assert.Equal("full", vitals.ShieldDetail.Recovery.State);
        Assert.Equal(0, vitals.ShieldDetail.Recovery.TotalMs);
    }

    [Fact]
    public void DetailsKeepExactNumbersRecoveryReasonCoexistingFlagsAndReserveAmmo()
    {
        var packet=PlayerHudStateTests.Full();
        packet["groups"]["vitals"]["shieldDetail"]=Shield("mp");
        packet["groups"]["vitals"]["poiseVisual"]=new JObject{["airborne"]=true,["rigid"]=true,["down"]=false};
        packet["groups"]["combat"]["mode"]="双枪";
        packet["groups"]["combat"]["ammo"]=new JArray("7","123456789","1","987654321");
        var state=new PlayerHudState();Assert.True(state.Receive(PlayerHudStateTests.Encode(packet),1));
        var snapshot=state.Snapshot;
        var target=new PlayerHudTarget("resources",0,"",snapshot.Epoch,0,0,PlayerHudBottomWidget.DetailsRect);
        var payload=PlayerHudResourceTooltip.Build(snapshot,target,"resource-facts");
        var text=string.Concat(payload["document"]["sections"][0]["runs"].Select(r=>r["text"].Value<string>()));
        Assert.Contains("99999999",text);Assert.Contains("MP不足",text);Assert.Contains("浮空与刚体同时存在",text);
        Assert.Contains("123456789",text);Assert.Contains("987654321",text);
    }

    internal static JObject Shield(string state = "waiting") => new()
    {
        ["strengthKind"] = "finite", ["strength"] = 99999999, ["resistsBypass"] = true,
        ["recovery"] = new JObject
        {
            ["state"] = state, ["progress"] = state == "waiting" ? 0.6 : state == "charging" ? 1 : 0,
            ["remainingMs"] = state == "waiting" ? 1600 : 0, ["totalMs"] = state == "waiting" ? 4000 : 0
        }
    };

    [Fact]
    public void OptionalFactsPreserveCoexistingAirAndRigidAndLargeFiniteStrength()
    {
        var packet = PlayerHudStateTests.Full();
        packet["groups"]["vitals"]["poiseVisual"] = new JObject { ["airborne"] = true, ["rigid"] = true, ["down"] = false };
        packet["groups"]["vitals"]["shieldDetail"] = Shield();
        var state = new PlayerHudState();
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet), 1));
        Assert.True(state.Snapshot.Vitals.PoiseVisual.Airborne);
        Assert.True(state.Snapshot.Vitals.PoiseVisual.Rigid);
        Assert.Equal(99999999, state.Snapshot.Vitals.ShieldDetail.Strength);
        Assert.Equal(1600, state.Snapshot.Vitals.ShieldDetail.Recovery.RemainingMs);
    }

    [Theory]
    [InlineData("none")]
    [InlineData("full")]
    [InlineData("charging")]
    [InlineData("health")]
    [InlineData("mp")]
    [InlineData("conditions")]
    [InlineData("manual")]
    [InlineData("unavailable")]
    public void RecoveryStatesDoNotInventAClock(string phase)
    {
        var packet = PlayerHudStateTests.Full(); packet["groups"]["vitals"]["shieldDetail"] = Shield(phase);
        var state = new PlayerHudState(); Assert.True(state.Receive(PlayerHudStateTests.Encode(packet), 1));
        Assert.Equal(0, state.Snapshot.Vitals.ShieldDetail.Recovery.TotalMs);
    }

    [Fact]
    public void BadDetailsRejectAtomicallyAndAReplacementVitalsCannotKeepOldFacts()
    {
        var packet = PlayerHudStateTests.Full(); packet["groups"]["vitals"]["shieldDetail"] = Shield();
        var state = new PlayerHudState(); Assert.True(state.Receive(PlayerHudStateTests.Encode(packet), 1));
        var before = state.Snapshot;
        packet["seq"] = 2;
        packet["groups"]["vitals"]["shieldDetail"]["recovery"]["progress"] = 1.1;
        Assert.False(state.Receive(PlayerHudStateTests.Encode(packet), 2)); Assert.Same(before, state.Snapshot);
        packet["groups"]["vitals"]["shieldDetail"] = Shield("mp");
        packet["groups"]["vitals"]["shieldDetail"]["recovery"]["totalMs"] = 4000;
        Assert.False(state.Receive(PlayerHudStateTests.Encode(packet), 3)); Assert.Same(before, state.Snapshot);
        ((JObject)packet["groups"]["vitals"]).Remove("shieldDetail");
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet), 4)); Assert.Null(state.Snapshot.Vitals.ShieldDetail);
    }

    [Fact]
    public void UnlimitedStrengthHasAnExplicitKindInsteadOfInvalidJsonInfinity()
    {
        var packet = PlayerHudStateTests.Full(); var detail = Shield();
        detail["strengthKind"] = "unlimited"; detail["strength"] = 0;
        packet["groups"]["vitals"]["shieldDetail"] = detail;
        var state = new PlayerHudState(); Assert.True(state.Receive(PlayerHudStateTests.Encode(packet), 1));
        Assert.Equal("unlimited", state.Snapshot.Vitals.ShieldDetail.StrengthKind);
        packet["seq"] = 2; detail["strength"] = 99999999;
        Assert.False(state.Receive(PlayerHudStateTests.Encode(packet), 2));
    }
}
