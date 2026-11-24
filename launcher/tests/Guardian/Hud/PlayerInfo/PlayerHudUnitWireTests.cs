using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public class PlayerHudUnitWireTests
{
    private static JObject Full(long sequence=1)
    {
        var p=PlayerHudStateTests.Full(1,sequence);
        p["groups"]["focusTarget"]=new JArray(new JObject {["id"]=1,["role"]="boss",["name"]="守卫",["hp"]=new JArray(100,100)});
        p["groups"]["allies"]=new JObject {
            ["rows"]=new JArray(new JObject {["slot"]=2,["id"]=2,["generation"]=7,["role"]="merc",["name"]="援军",
                ["icon"]="",["hp"]=new JArray(100,100),["shield"]=new JArray(0,0),["protected"]=false,["down"]=false}),
            ["overflow"]=new JArray()};
        return p;
    }

    [Fact] public void CombinedHotPatchIsAtomicAndPreservesUnrelatedGroups()
    {
        var s=new PlayerHudState();
        Assert.True(s.Receive(PlayerHudStateTests.Encode(Full()),1));
        var old=s.Snapshot;
        var notified=PlayerHudGroups.None;
        s.Changed+=()=>notified=s.NotifyingGroups;
        Assert.True(s.Receive("~1,1,2;f,0,1,75.25,100,3;a,0,2,7,0,100,0,0,1",2));
        Assert.Equal(PlayerHudGroups.Focus|PlayerHudGroups.Allies,notified);
        Assert.Equal(75.25,s.Snapshot.TargetList[0].Hp);
        Assert.True(s.Snapshot.Allies.Rows[0].Down);
        Assert.Same(old.Vitals,s.Snapshot.Vitals);
        Assert.Equal(100,old.TargetList[0].Hp);
        Assert.False(old.Allies.Rows[0].Down);
    }

    [Fact]
    public void MixedFrameDrainsOnceAndRequestsFullAfterMissingTail()
    {
        int dispatches = 0;
        var sent = new System.Collections.Generic.List<JObject>();
        using var controller = new PlayerHudController(
            raw => { sent.Add(JObject.Parse(raw.TrimEnd('\0'))); return true; },
            () => true, drain => { dispatches++; drain(); });
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Full()));
        var head = Full(2);
        head["full"] = false;
        head["groups"] = new JObject { ["vitals"] = head["groups"]["vitals"].DeepClone() };
        head["groups"]["vitals"]["hp"][0] = 345;
        var rest = controller.TakeUiData("left|pi:" + PlayerHudStateTests.Encode(head)
            + "|pi:~1,1,3;a,0,2,7,75,100,0,0,0|right");
        Assert.Equal("left|right", rest);
        Assert.Equal(2, dispatches);
        Assert.Equal(345, controller.State.Snapshot.Vitals.Hp);
        Assert.Equal(75, controller.State.Snapshot.Allies.Rows[0].Hp);
        head["seq"] = 4;
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(head));
        head["seq"] = 6;
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(head) + "|pi:~1,1,7;f,0,1,50,100,0");
        Assert.True(controller.State.NeedsUnitSync);
        Assert.Equal(100, controller.State.Snapshot.TargetList[0].Hp);
        Assert.Equal(2, sent.Count);
        controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Full(8)));
        Assert.False(controller.State.NeedsUnitSync);
    }

    [Theory]
    [InlineData("~1,1,2;f,0,1,70,100,0;a,0,2,8,0,100,0,0,1")]
    [InlineData("~1,1,2;f,0,1,70,100,0;f,0,1,75,100,0")]
    [InlineData("~1,1,2;f,0,1,NaN,100,0")]
    [InlineData("~1,1,3;f,0,1,70,100,0")]
    public void InvalidOrGappedDeltaNeedsFullWithoutPartialAdoption(string value)
    {
        var s=new PlayerHudState();
        Assert.True(s.Receive(PlayerHudStateTests.Encode(Full()),1));
        var prior=s.Snapshot;
        Assert.False(s.Receive(value,2));
        Assert.Same(prior,s.Snapshot);
        Assert.True(s.NeedsUnitSync);
        Assert.True(s.Receive(PlayerHudStateTests.Encode(Full(10)),10));
        Assert.False(s.NeedsUnitSync);
        Assert.False(s.Receive("~1,1,2;f,0,1,70,100,0",11));
        Assert.False(s.NeedsUnitSync);
    }

    [Theory]
    [InlineData(83, true, true)]
    [InlineData(84, true, false)]
    [InlineData(20, false, false)]
    [InlineData(2147483647, true, false)]
    public void VisibleSlotsRespectSeparateProtectionBudget(int slot,bool protect,bool accepted)
    {
        var s=new PlayerHudState();var packet=Full();
        var row=packet["groups"]["allies"]["rows"][0];
        row["slot"]=slot;row["protected"]=protect;
        Assert.Equal(accepted,s.Receive(PlayerHudStateTests.Encode(packet),1));
        Assert.Equal(!accepted,s.NeedsUnitSync);
    }

    [Fact] public void OverlongOverflowIsRejectedBeforeChangingTheRoster()
    {
        var s=new PlayerHudState();Assert.True(s.Receive(PlayerHudStateTests.Encode(Full()),1));
        var prior=s.Snapshot;var replacement=Full(2);
        var ally=replacement["groups"]["allies"];var overflow=(JArray)ally["overflow"];
        for(int i=0;i<=PlayerHudState.MaximumOverflowAllies;i++)
        {
            var row=ally["rows"][0].DeepClone();row["slot"]=-1;row["id"]=50+i;overflow.Add(row);
        }
        Assert.False(s.Receive(PlayerHudStateTests.Encode(replacement),2));
        Assert.Same(prior,s.Snapshot);Assert.True(s.NeedsUnitSync);
    }

    [Fact]
    public void ExtendedFocusHotPacketAdoptsUnitInfoAndRejectsInvalidRanges()
    {
        var basePacket = Full();
        var row = (JObject)basePacket["groups"]["focusTarget"][0];
        row["shield"] = new JArray(200, 300);
        row["poise"] = 180;
        row["flags"] = 0;
        row["hitSeq"] = 1;

        var s = new PlayerHudState();
        Assert.True(s.Receive(PlayerHudStateTests.Encode(basePacket), 1));
        Assert.Equal(200, s.Snapshot.TargetList[0].Shield);
        Assert.Equal(300, s.Snapshot.TargetList[0].ShieldMax);
        Assert.Equal(180, s.Snapshot.TargetList[0].Poise);
        Assert.Equal(1, s.Snapshot.TargetList[0].HitSeq);

        var notified = PlayerHudGroups.None;
        s.Changed += () => notified = s.NotifyingGroups;
        // 11-field extended focus hot record updating shield, poise, rigid+darkened flags, and hitSeq
        Assert.True(s.Receive("~1,1,2;f,0,1,75.25,100,4,150,300,204,12,7", 2));
        Assert.Equal(PlayerHudGroups.Focus, notified);
        var t = s.Snapshot.TargetList[0];
        Assert.Equal(75.25, t.Hp);
        Assert.Equal(4, t.Hits);
        Assert.Equal(150, t.Shield);
        Assert.Equal(300, t.ShieldMax);
        Assert.Equal(204, t.Poise);
        Assert.Equal(12, t.Flags);
        Assert.True(t.Rigid && t.Darkened && !t.Airborne && !t.Down);
        Assert.Equal(7, t.HitSeq);

        // Unavailable poise (-1) and hitSeq 0 are valid
        Assert.True(s.Receive("~1,1,3;f,0,1,75.25,100,0,0,0,-1,3,0", 3));
        var t2 = s.Snapshot.TargetList[0];
        Assert.False(t2.HasPoise);
        Assert.Equal(-1, t2.Poise);
        Assert.True(t2.Airborne && t2.Down);
        Assert.Equal(0, t2.HitSeq);

        // Out-of-range poise/flags/shield/hitSeq reject fail-closed without mutating state
        long seq = 4;
        foreach (var badSuffix in new[] {
            "f,0,1,70,100,0,0,0,256,0,0",
            "f,0,1,70,100,0,0,0,-2,0,0",
            "f,0,1,70,100,0,0,0,0,16,0",
            "f,0,1,70,100,0,-1,100,0,0,0",
            "f,0,1,70,100,0,0,-1,0,0,0"
        })
        {
            var before = s.Snapshot;
            Assert.False(s.Receive($"~1,1,{seq};{badSuffix}", seq));
            Assert.Same(before, s.Snapshot);
            Assert.True(s.NeedsUnitSync);
            seq += 2;
            Assert.True(s.Receive(PlayerHudStateTests.Encode(Full(seq)), seq));
            Assert.False(s.NeedsUnitSync);
            seq++;
        }
    }
}