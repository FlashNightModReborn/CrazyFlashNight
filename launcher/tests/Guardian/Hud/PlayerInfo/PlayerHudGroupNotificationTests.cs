using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudGroupNotificationTests
{
    private static JArray Focus(int hp) => new(new JObject {
        ["id"]=5,["role"]="boss",["name"]="焦点",["hp"]=new JArray(hp,1000),["icon"]="",["doll"]=null });

    private static JObject Delta(int seq,string group,JToken value) => new() {
        ["v"]=1,["epoch"]=1,["seq"]=seq,["full"]=false,["visible"]=true,
        ["groups"]=new JObject { [group]=value } };

    [Fact]
    public void FocusDoesNotWakeBottomOrBuffButRealBuffPauseVisibilityAndEpochChangesStillApply()
    {
        using var anchor=new Panel { Size=new Size(1024,576) };
        using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
        var root=new DirectoryInfo(AppContext.BaseDirectory);
        while (root!=null && !File.Exists(Path.Combine(root.FullName,"launcher","web","icons","manifest.json")))
            root=root.Parent;
        Assert.NotNull(root);
        using var bottom=new PlayerHudBottomWidget(anchor,controller,Path.Combine(root.FullName,"launcher","web","icons"));
        using var buff=new PlayerHudBuffWidget(anchor,controller);
        void Send(JObject packet) => Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),1));
        var full=PlayerHudStateTests.Full();
        full["groups"]["focusTarget"]=Focus(900);
        Send(full);
        var cards=controller.State.Snapshot.BuffCards;
        int bottomPaint=0,buffPaint=0;
        bottom.RepaintRequested+=(_,_)=>bottomPaint++;
        buff.RepaintRequested+=(_,_)=>buffPaint++;
        Send(Delta(2,"focusTarget",Focus(470)));
        Assert.Equal((0,0),(bottomPaint,buffPaint));
        Assert.Same(cards,controller.State.Snapshot.BuffCards);
        full["seq"]=3; full["groups"]["focusTarget"]=Focus(900);
        Send(full);
        Assert.Equal((0,0),(bottomPaint,buffPaint));
        Assert.Same(cards,controller.State.Snapshot.BuffCards);

        var status=(JArray)full["groups"]["buffs"].DeepClone();
        status[0]["remaining"]=999;
        Send(Delta(4,"buffs",status));
        Assert.Equal((0,1),(bottomPaint,buffPaint));
        Assert.NotSame(cards,controller.State.Snapshot.BuffCards);
        Assert.Equal(999,controller.State.Snapshot.BuffCards[0].DisplayRemaining);
        var vitals=(JObject)full["groups"]["vitals"].DeepClone();
        vitals["paused"]=true;
        Send(Delta(5,"vitals",vitals));
        vitals["paused"]=false;
        Send(Delta(6,"vitals",vitals));
        Assert.Equal((2,1),(bottomPaint,buffPaint));
        bottom.SetHostSuppressed(true); buff.SetHostSuppressed(true);
        Assert.False(bottom.Visible); Assert.False(buff.Visible);
        bottom.SetHostSuppressed(false); buff.SetHostSuppressed(false);
        Assert.True(bottom.Visible); Assert.True(buff.Visible);
        Assert.True(bottomPaint>=4 && buffPaint>=3);
        bottomPaint=buffPaint=0;
        Send(PlayerHudStateTests.Full(2));
        Assert.True(bottomPaint>=1 && buffPaint>=1);
        controller.State.Disconnect();
        Assert.False(bottom.Visible); Assert.False(buff.Visible);
    }

    [Fact]
    public void IdenticalFullAndInvalidPacketAreSilentButRemovalOfOptionalGroupNotifies()
    {
        var state=new PlayerHudState();
        PlayerHudGroups changes=PlayerHudGroups.None;
        state.Changed+=()=>changes|=state.NotifyingGroups;
        var full=PlayerHudStateTests.Full(); full["groups"]["focusTarget"]=Focus(300);
        Assert.True(state.Receive(PlayerHudStateTests.Encode(full),1));
        Assert.Equal(PlayerHudGroups.All,changes);
        var cards=state.Snapshot.BuffCards;
        changes=PlayerHudGroups.None;
        full["seq"]=2;
        Assert.True(state.Receive(PlayerHudStateTests.Encode(full),2));
        Assert.Same(cards,state.Snapshot.BuffCards);
        Assert.False(state.Receive(PlayerHudStateTests.Encode(Delta(3,"focusTarget",new JArray(1))),3));
        Assert.Equal(PlayerHudGroups.None,changes);
        Assert.True(state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full(1,3)),4));
        Assert.Equal(PlayerHudGroups.Focus,changes);
        Assert.Empty(state.Snapshot.TargetList);
        Assert.Same(cards,state.Snapshot.BuffCards);
    }

    [Fact]
    public void ExplicitBuffTimersAreAlwaysValidatedAndSmallLegalChangesAreRetained()
    {
        var state=new PlayerHudState();
        var full=PlayerHudStateTests.Full();
        var rows=(JArray)full["groups"]["buffs"];
        rows[0]["remaining"]=0.0;
        Assert.True(state.Receive(PlayerHudStateTests.Encode(full),1));
        var accepted=state.Snapshot;
        var cards=accepted.BuffCards;
        var changes=PlayerHudGroups.None;
        state.Changed+=()=>changes|=state.NotifyingGroups;
        // JObject's property setter can discard almost-equal doubles before they reach the wire.
        ((JValue)rows[0]["remaining"]).Value=-1e-17;
        Assert.False(state.Receive(PlayerHudStateTests.Encode(Delta(2,"buffs",rows)),2));
        Assert.Same(accepted,state.Snapshot);
        Assert.Equal(PlayerHudGroups.None,changes);
        ((JValue)rows[0]["remaining"]).Value=1e-17;
        Assert.True(state.Receive(PlayerHudStateTests.Encode(Delta(2,"buffs",rows)),3));
        Assert.Equal(PlayerHudGroups.Buffs,changes);
        Assert.Equal(1e-17,state.Snapshot.Buffs[0].Remaining);
        Assert.Equal(1e-17,state.Snapshot.BuffCards[0].DisplayRemaining);
        Assert.NotSame(cards,state.Snapshot.BuffCards);
    }
}
