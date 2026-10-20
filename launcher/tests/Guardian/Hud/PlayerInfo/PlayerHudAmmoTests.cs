using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudAmmoTests
{
    internal static JObject Detail() => new()
    {
        ["capacity"]=8,["loaded"]=11,["normal"]=8,["chamber"]=1,["ghost"]=2,
        ["reward"]=0,["reserve"]=5,["spread"]=1.5,["overflow"]=3
    };
    private static JObject Packet(JObject detail)
    {
        var packet=PlayerHudStateTests.Full();
        var combat=(JObject)packet["groups"]["combat"];
        combat["mode"]="长枪";
        combat["ammo"]=new JArray("11","9","","");
        combat["ammoDetails"]=new JArray(detail,JValue.CreateNull());
        return packet;
    }
    [Fact]
    public void TypedSourcesAndPaidBalanceArriveWithoutReplacingLegacyTotals()
    {
        var state=new PlayerHudState();
        var path=System.IO.Path.Combine(AppContext.BaseDirectory,"Fixtures","PlayerHud","as2-ammo-combat.json");
        var packet=PlayerHudStateTests.Full();
        packet["groups"]["combat"]=JObject.Parse(System.IO.File.ReadAllText(path));
        Assert.True(state.Receive(PlayerHudStateTests.Encode(packet),1));
        var detail=state.Snapshot.Combat.AmmoDetails[0];
        Assert.Equal(10,detail.Loaded);Assert.Equal(7,detail.Normal);
        Assert.Equal(1,detail.Chamber);Assert.Equal(2,detail.Ghost);Assert.Equal(0,detail.Reward);
        Assert.Equal(4,detail.Reserve);Assert.InRange(Math.Abs(detail.Spread-(1+4.0/7)),0,0.000000001);Assert.Equal(3,detail.Overflow);
        Assert.Equal("10",state.Snapshot.Combat.Ammo[0]);Assert.Null(state.Snapshot.Combat.AmmoDetails[1]);
    }
    [Theory]
    [InlineData("loaded",12)]
    [InlineData("normal",9)]
    [InlineData("chamber",3)]
    [InlineData("ghost",3)]
    [InlineData("reward",9)]
    [InlineData("reserve",-1)]
    [InlineData("reserve",1.5)]
    [InlineData("spread",4)]
    [InlineData("overflow",1)]
    [InlineData("unexpected",1)]
    public void InvalidAmmoDetailRejectsThePacketAtomically(string field,double number)
    {
        var state=new PlayerHudState();
        Assert.True(state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full()),1));
        var before=state.Snapshot;
        var detail=Detail();detail[field]=number;
        var packet=Packet(detail);packet["seq"]=2;
        Assert.False(state.Receive(PlayerHudStateTests.Encode(packet),1));
        Assert.Same(before,state.Snapshot);
    }
    [Fact]
    public void AmmoHoverExplainsSourcesAndRiskWithoutAddingAnotherPermanentMeter()
    {
        var state=new PlayerHudState();
        Assert.True(state.Receive(PlayerHudStateTests.Encode(Packet(Detail())),1));
        var target=new PlayerHudTarget("ammo",0,"",state.Snapshot.Epoch,0,0,new RectangleF(488,518,68,46),1,false);
        var document=PlayerHudResourceTooltip.Build(state.Snapshot,target,"ammo-test");
        var text=string.Concat(document["document"]["sections"][0]["runs"].Select(r=>(string)r["text"]));
        Assert.Contains("普通：8 / 8",text);Assert.Contains("留膛：1",text);
        Assert.Contains("幽灵：2",text);Assert.Contains("奖励：0",text);
        Assert.Contains("超额装填：+3",text);
        Assert.Contains("已拆包余量：5",text);Assert.Contains("散射倍率：1.5",text);
        Assert.DoesNotContain("生命：",text);
    }
    [Fact]
    public void LegacySnapshotStillWorksWhenAmmoDetailsWereNotNegotiated()
    {
        var state=new PlayerHudState();
        Assert.True(state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full()),1));
        Assert.Null(state.Snapshot.Combat.AmmoDetails);
    }

    [Fact]
    public void TypedAmmoColorsTheExistingLayoutAndOffersOnlyLocalHover()
    {
        Exception failure=null;
        var thread=new Thread(() =>
        {
            try
            {
                var directory=new DirectoryInfo(AppContext.BaseDirectory);
                while(directory!=null&&!File.Exists(Path.Combine(directory.FullName,"AGENTS.md")))directory=directory.Parent;
                Assert.NotNull(directory);var root=directory.FullName;RuntimeFontCatalog.Configure(root);
                using var owner=new Form {ClientSize=new Size(1024,576)};
                using var anchor=new Panel {Dock=DockStyle.Fill};
                owner.Controls.Add(anchor);owner.CreateControl();anchor.CreateControl();
                var sends=0;
                using var controller=new PlayerHudController(_=>{sends++;return true;},()=>true,action=>action());
                using var bottom=new PlayerHudBottomWidget(anchor,controller,Path.Combine(root,"launcher","web","icons"));
                var origin=anchor.PointToScreen(Point.Empty);
                using var baseline=new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
                var packet=Packet(Detail());
                ((JObject)packet["groups"]["combat"]).Remove("ammoDetails");
                Assert.Equal("",controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet)));
                Assert.True(controller.CanInteract);
                // The initial packet negotiates HUD capabilities before local hover becomes active.
                sends=0;
                using(var graphics=Graphics.FromImage(baseline)){graphics.Clear(Color.FromArgb(35,39,44));bottom.Paint(graphics,1,origin);}
                var captures=new[]{"overload","ghost-without-overflow","dual"};
                for(var index=0;index<captures.Length;index++)
                {
                    var detail=Detail();
                    packet=Packet(detail);packet["seq"]=index+2;
                    if(index==1){detail["loaded"]=8;detail["normal"]=5;detail["overflow"]=0;packet["groups"]["combat"]["ammo"][0]="8";}
                    if(index==2)packet["groups"]["combat"]["mode"]="双枪";
                    Assert.Equal("",controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet)));
                    using var bitmap=new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
                    using(var graphics=Graphics.FromImage(bitmap)){graphics.Clear(Color.FromArgb(35,39,44));bottom.Paint(graphics,1,origin);}
                    var changed=0;
                    for(var y=515;y<564;y++)for(var x=488;x<575;x++)
                        if(bitmap.GetPixel(x,y)!=baseline.GetPixel(x,y))changed++;
                    Assert.True(changed>20,"Source tint must visibly alter the existing ammunition text.");
                    var target=bottom.CapturePointerTarget(new Point(origin.X+522,origin.Y+532));
                    Assert.NotNull(target);Assert.Equal("ammo",target.Kind);
                    var evidence=Environment.GetEnvironmentVariable("CF7_EVIDENCE_ROOT");
                    if(!string.IsNullOrWhiteSpace(evidence))
                    {
                        var folder=Path.Combine(evidence,"ammo-hud");Directory.CreateDirectory(folder);
                        bitmap.Save(Path.Combine(folder,captures[index]+".png"),ImageFormat.Png);
                    }
                }
                Assert.Equal(0,sends);
            }
            catch(Exception error){failure=error;}
        });
        thread.SetApartmentState(ApartmentState.STA);thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(30)),"Ammo rendering must finish.");
        if(failure!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
