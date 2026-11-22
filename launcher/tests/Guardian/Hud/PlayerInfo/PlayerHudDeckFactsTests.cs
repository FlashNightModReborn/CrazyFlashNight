using System.Linq;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudDeckFactsTests
{
    private static JObject Effect(string id,string kind,string key,int? slot=null)
    {
        var source=new JObject { ["kind"]=kind,["key"]=key };
        if (slot.HasValue) source["slot"]=slot.Value;
        return new() { ["id"]=id,["timed"]=true,["total"]=150,["remaining"]=73,["source"]=source };
    }

    [Fact]
    public void PhysicalBankAndExactEquippedSkillAreAdoptedFromEffectSource()
    {
        var packet=PlayerHudStateTests.Full();
        var groups=packet["groups"];
        var rows=new JArray(Effect("99:potionB","drug","药剂1",5),Effect("99:inventory","inventory","药剂0"),
            Effect("99:skill","skill","技能4"));
        ((JObject)rows[2])["role"]="eres";
        groups["buffs"]=rows;
        var state=new PlayerHudState();
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet),1));
        Assert.Equal((1<<5,0,1<<3),PlayerHudBottomWidget.SourceLights(state.Snapshot));
        Assert.Equal("99:skill",state.Snapshot.BuffCards.First().Id);
        packet["seq"]=2;groups["loadout"]["bank"]=1;
        for (int lane=0;lane<4;lane++)groups["loadout"]["drugs"][lane]["slot"]=4+lane;
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet),2));
        Assert.Equal((1<<5,2,1<<3),PlayerHudBottomWidget.SourceLights(state.Snapshot));
        packet["seq"]=3;groups["loadout"]["drugs"][1]["name"]="另一种药";
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet),3));
        Assert.Equal((1<<5,0,1<<3),PlayerHudBottomWidget.SourceLights(state.Snapshot));
        packet["seq"]=4;rows[0]["remaining"]=0; rows[2]["remaining"]=0;
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet),4));
        Assert.Equal((0,0,0),PlayerHudBottomWidget.SourceLights(state.Snapshot));
    }

    [Fact]
    public void MissingCoatingDenominatorStaysUnknownAndLegacyPacketClearsAddedFacts()
    {
        var packet=PlayerHudStateTests.Full();
        packet["groups"]["combat"]["deck"]=new JObject { ["points"]=15,["initial"]=0,["equipment"]="钢手套",["power"]=16 };
        var state=new PlayerHudState();
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet),1));
        Assert.Equal(new PlayerHudDeckFacts(15,0,"钢手套",16),state.Snapshot.Combat.Deck);
        packet["seq"]=2;packet["groups"]["combat"]["deck"]["initial"]=14;
        Assert.False(state.Receive(PlayerHudStateTests.Encode(packet),2));
        Assert.Equal(0,state.Snapshot.Combat.Deck.Initial);
        Assert.True(state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full(1,3)),3));
        Assert.Null(state.Snapshot.Combat.Deck); Assert.Null(state.Snapshot.BuffCards.Single().Source);
    }

    [Theory]
    [InlineData(151,"6s")]
    [InlineData(150,"5s")]
    [InlineData(91,"4s")]
    [InlineData(90,"3.0s")]
    [InlineData(87,"2.9s")]
    [InlineData(1,"0.0s")]
    public void CountdownUsesTheSameDisplayCadenceAsEnergyEffect(int frames,string expected) =>
        Assert.Equal(expected,PlayerHudBuffWidget.Countdown(frames));
}
