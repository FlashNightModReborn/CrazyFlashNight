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
                    for(var y=515;y<564;y++)for(var x=484;x<588;x++)
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
                var evidenceDir=Environment.GetEnvironmentVariable("CF7_EVIDENCE_ROOT");
                if(!string.IsNullOrWhiteSpace(evidenceDir))
                {
                    using var hdOwner=new Form {ClientSize=new Size(1920,1080)};
                    using var hdAnchor=new Panel {Dock=DockStyle.Fill};
                    hdOwner.Controls.Add(hdAnchor);hdOwner.CreateControl();hdAnchor.CreateControl();
                    using var hdBottom=new PlayerHudBottomWidget(hdAnchor,controller,Path.Combine(root,"launcher","web","icons"));
                    var folder=Path.Combine(evidenceDir,"ammo-hud");Directory.CreateDirectory(folder);

                    void SaveCrop(JObject pkt, string fileName)
                    {
                        Assert.Equal("",controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(pkt)));
                        using var hd=new Bitmap(1920,1080,PixelFormat.Format32bppPArgb);
                        using(var g=Graphics.FromImage(hd)){g.Clear(Color.FromArgb(35,39,44));hdBottom.Paint(g,1.875f,hdAnchor.PointToScreen(Point.Empty));}
                        using var crop=hd.Clone(new Rectangle(895,955,225,120),PixelFormat.Format32bppPArgb);
                        crop.Save(Path.Combine(folder,fileName),ImageFormat.Png);
                    }

                    // 1. Subweapon mode (50/0 cap 50, 13/0 cap 17)
                    var subPacket=PlayerHudStateTests.Full();
                    subPacket["seq"]=10;
                    var subCombat=(JObject)subPacket["groups"]["combat"];
                    subCombat["mode"]="长枪副武器";
                    subCombat["ammo"]=new JArray("45","0","13","0");
                    subCombat["ammoDetails"]=new JArray(
                        new JObject{["capacity"]=50,["loaded"]=45,["normal"]=45,["chamber"]=0,["ghost"]=0,["reward"]=0,["reserve"]=0,["spread"]=1.0,["overflow"]=0},
                        new JObject{["capacity"]=17,["loaded"]=13,["normal"]=13,["chamber"]=0,["ghost"]=0,["reward"]=0,["reserve"]=0,["spread"]=1.0,["overflow"]=0});
                    SaveCrop(subPacket, "subweapon-hollow-aligned-1080p.png");

                    // 2. Single-gun mode WITHOUT active weapon skill (9000/0 cap 9000) -> hides 战技, expands to full width
                    var singleNoSkill=PlayerHudStateTests.Full();
                    singleNoSkill["seq"]=11;
                    var snsCombat=(JObject)singleNoSkill["groups"]["combat"];
                    snsCombat["mode"]="长枪";
                    snsCombat["weapon"]["visible"]=false;
                    snsCombat["ammo"]=new JArray("9000","0","","");
                    snsCombat["ammoDetails"]=new JArray(
                        new JObject{["capacity"]=9000,["loaded"]=9000,["normal"]=9000,["chamber"]=0,["ghost"]=0,["reward"]=0,["reserve"]=0,["spread"]=1.0,["overflow"]=0},
                        JValue.CreateNull());
                    SaveCrop(singleNoSkill, "single-no-skill-1080p.png");

                    // 3. Single-gun mode WITH active weapon skill (45/2 cap 50) -> shows 战技 on right, compact cards on left
                    var singleWithSkill=PlayerHudStateTests.Full();
                    singleWithSkill["seq"]=12;
                    var swsCombat=(JObject)singleWithSkill["groups"]["combat"];
                    swsCombat["mode"]="长枪";
                    swsCombat["weapon"]["visible"]=true;
                    swsCombat["ammo"]=new JArray("45","2","","");
                    swsCombat["ammoDetails"]=new JArray(
                        new JObject{["capacity"]=50,["loaded"]=45,["normal"]=45,["chamber"]=0,["ghost"]=0,["reward"]=0,["reserve"]=100,["spread"]=1.0,["overflow"]=0},
                        JValue.CreateNull());
                    SaveCrop(singleWithSkill, "single-with-skill-1080p.png");

                    // 4. Subweapon mode matching low/empty screenshot (0/0 cap 50, 6/0 cap 36) -> co-tinted icons & breathable layout
                    var subLowEmpty=PlayerHudStateTests.Full();
                    subLowEmpty["seq"]=13;
                    var sleCombat=(JObject)subLowEmpty["groups"]["combat"];
                    sleCombat["mode"]="长枪副武器";
                    sleCombat["ammo"]=new JArray("0","0","6","0");
                    sleCombat["ammoDetails"]=new JArray(
                        new JObject{["capacity"]=50,["loaded"]=0,["normal"]=0,["chamber"]=0,["ghost"]=0,["reward"]=0,["reserve"]=0,["spread"]=1.0,["overflow"]=0},
                        new JObject{["capacity"]=36,["loaded"]=6,["normal"]=6,["chamber"]=0,["ghost"]=0,["reward"]=0,["reserve"]=0,["spread"]=1.0,["overflow"]=0});
                    SaveCrop(subLowEmpty, "subweapon-low-empty-1080p.png");
                }
                Assert.Equal(0,sends);
            }
            catch(Exception error){failure=error;}
        });
        thread.SetApartmentState(ApartmentState.STA);thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(30)),"Ammo rendering must finish.");
        if(failure!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }

    [Fact]
    public void ReserveColorAndYieldingPreservePrimaryBudgetAcrossExtremeCapacities()
    {
        Assert.Equal(PlayerHudAmmoPainter.ReserveNormalText, PlayerHudBottomWidget.ReserveAmmoColor("15"));
        Assert.Equal(PlayerHudAmmoPainter.ReserveNormalText, PlayerHudBottomWidget.ReserveAmmoColor("无限"));
        Assert.Equal(PlayerHudAmmoPainter.ReserveLowText, PlayerHudBottomWidget.ReserveAmmoColor("2"));
        Assert.Equal(PlayerHudAmmoPainter.ReserveLowText, PlayerHudBottomWidget.ReserveAmmoColor("1"));
        Assert.Equal(PlayerHudAmmoPainter.ReserveEmptyText, PlayerHudBottomWidget.ReserveAmmoColor("0"));

        float MonospaceMeasure(string s) => s.Length * 7f;
        var full9999 = PlayerHudAmmoPainter.FormatPrimaryLoaded("9999", MonospaceMeasure, 38f, 9999);
        var low5Of9999 = PlayerHudAmmoPainter.FormatPrimaryLoaded("5", MonospaceMeasure, 38f, 9999);
        Assert.Equal("9999", full9999.Text);
        Assert.Equal("5", low5Of9999.Text);
        Assert.Equal(full9999.ReservedWidth, low5Of9999.ReservedWidth);

        Assert.Equal("350", PlayerHudAmmoPainter.FormatReserveWithYield("350", MonospaceMeasure, 24f));
        Assert.Equal("1234", PlayerHudAmmoPainter.FormatReserveWithYield("1234", MonospaceMeasure, 30f));
        Assert.Equal("999+", PlayerHudAmmoPainter.FormatReserveWithYield("1234", MonospaceMeasure, 25f));
        Assert.Equal("1.23万", PlayerHudAmmoPainter.FormatReserveWithYield("12345", MonospaceMeasure, 40f));
        Assert.Equal("1.2万", PlayerHudAmmoPainter.FormatReserveWithYield("12345", MonospaceMeasure, 32f));
        Assert.Equal("1万+", PlayerHudAmmoPainter.FormatReserveWithYield("12345", MonospaceMeasure, 24f));

        Assert.Equal(544.5f, PlayerHudAmmoPainter.ResolveDualMagazineIconX(500.5f, 583.0f, 21f, 18f, 544.5f));
        Assert.Equal(544.5f, PlayerHudAmmoPainter.ResolveDualMagazineIconX(500.5f, 583.0f, 28f, 18f, 544.5f));
        var fiveDigitSplit = PlayerHudAmmoPainter.ResolveDualMagazineIconX(500.5f, 583.0f, 42f, 24f, 544.5f);
        Assert.True(fiveDigitSplit > 544.5f && fiveDigitSplit <= 583.0f - 24f);
    }

    [Fact]
    public void MagazineBarRendersDiscreteAndContinuousTiersAcrossSingleAndDualModes()
    {
        using var surface = new Bitmap(240, 60, PixelFormat.Format32bppPArgb);
        using var g = Graphics.FromImage(surface);
        g.Clear(Color.Black);

        // Tier 1: 8-round discrete 1:1 cells
        PlayerHudAmmoPainter.PaintMagazineBar(g, new RectangleF(10, 5, 80, 3), 1f,
            new PlayerHudAmmoDetail(8, 6, 6, 0, 0, 0, 0, 1.0, 0), "6", 8);
        var gapPixels = 0;
        var filledPixels = 0;
        for (var x = 10; x < 90; x++)
        {
            var c = surface.GetPixel(x, 6);
            if (c.R > 180 && c.G > 180) filledPixels++;
            else if (c.R < 30 && c.G < 30 && x < 65) gapPixels++;
        }
        Assert.True(filledPixels > 35);
        Assert.True(gapPixels >= 5, "Discrete 8-round bar must keep 1px physical cell gaps");

        var spentTopBorder = surface.GetPixel(84, 5);
        var spentInterior = surface.GetPixel(84, 6);
        var spentBottomBorder = surface.GetPixel(84, 7);
        Assert.True(spentTopBorder.R >= 50 && spentBottomBorder.R >= 50 && spentInterior.R < 25,
            $"Spent discrete cell must render as hollow slot (top={spentTopBorder}, mid={spentInterior}, bot={spentBottomBorder})");

        // Tier 3: 9999-round continuous bar with 20% quintile notches and leading cursor edge
        PlayerHudAmmoPainter.PaintMagazineBar(g, new RectangleF(10, 20, 100, 3), 1f,
            new PlayerHudAmmoDetail(9999, 5000, 5000, 0, 0, 0, 0, 1.0, 0), "5000", 9999);
        var notchAt20Pct = surface.GetPixel(10 + 20, 21);
        var fillBetweenNotches = surface.GetPixel(10 + 10, 21);
        Assert.True(fillBetweenNotches.R > 180 && notchAt20Pct.R < 40, "Quintile notch at 20% must be carved on continuous bar");

        var contSpentTop = surface.GetPixel(10 + 75, 20);
        var contSpentMid = surface.GetPixel(10 + 75, 21);
        var contSpentBot = surface.GetPixel(10 + 75, 22);
        Assert.True(contSpentTop.R >= 50 && contSpentBot.R >= 50 && contSpentMid.R < 25,
            $"Spent right portion of continuous bar must render as hollow trough (top={contSpentTop}, mid={contSpentMid}, bot={contSpentBot})");
    }
}
