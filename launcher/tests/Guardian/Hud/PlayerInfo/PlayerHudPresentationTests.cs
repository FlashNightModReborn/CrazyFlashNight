using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.Hud.Tooltip;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudPresentationTests
{
    private static string Root()
    {
        var d=new DirectoryInfo(AppContext.BaseDirectory);
        while(d!=null&&!File.Exists(Path.Combine(d.FullName,"fonts","fonts.xml")))d=d.Parent;
        Assert.NotNull(d);return d.FullName;
    }
    private static void Sta(Action action)
    {
        Exception error=null;
        var thread=new Thread(()=>{try{action();}catch(Exception e){error=e;}});
        thread.SetApartmentState(ApartmentState.STA);thread.Start();Assert.True(thread.Join(45000));
        if(error!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(error).Throw();
    }
    private static PlayerHudSnapshot Snapshot(JObject packet)
    {
        var state=new PlayerHudState();Assert.True(state.Receive(PlayerHudStateTests.Encode(packet),1));return state.Snapshot;
    }
    private static PlayerHudTarget Target(PlayerHudSnapshot snapshot)=>new("resources",0,"",snapshot.Epoch,0,0,PlayerHudBottomWidget.DetailsRect);
    private static string Details(PlayerHudSnapshot snapshot)
    {
        var document=NativeTooltipDocument.FromPayload(PlayerHudResourceTooltip.Build(snapshot,Target(snapshot),"fixture-resource"));
        Assert.NotNull(document);return string.Concat(document.Sections.Select(s=>s.PlainText));
    }

    [Fact]
    public void CountdownStepUnitMatchesItsExistingAs2Authority()
    {
        var source=File.ReadAllText(Path.Combine(Root(),"scripts","类定义","org","flashNight","arki","unit","Action","Skill","ManualCooldownService.as"));
        var match=Regex.Match(source,@"public static var FRAME_MS:Number\s*=\s*([0-9.]+)");
        Assert.True(match.Success);
        Assert.Equal(double.Parse(match.Groups[1].Value,CultureInfo.InvariantCulture),PlayerHudCooldownText.StepMilliseconds);
    }
    [Theory]
    [InlineData(false,0,360,"12s")]
    [InlineData(false,60,360,"10s")]
    [InlineData(false,0,126,"4.2s")]
    [InlineData(false,125,126,"0.1s")]
    [InlineData(false,126,126,"0.1s")]
    [InlineData(false,0,1800,"1:00")]
    [InlineData(false,0,1900,"1:04")]
    [InlineData(true,0,360,"")]
    public void CountdownFormattingDoesNotDeclareReadiness(bool ready,double step,double total,string expected)
        =>Assert.Equal(expected,PlayerHudCooldownText.Format(new PlayerHudCooldown(ready,step,total)));

    [Fact]
    public void DetailsShowOverflowAuthoritativePoiseAndLevelRelativeExperience()
    {
        var packet=PlayerHudStateTests.Full();var v=packet["groups"]["vitals"];
        v["mp"]=new JArray(750,600);v["shield"]=new JArray(500,400);
        v["poise"]=0.25;v["poiseDetail"]=new JObject{["threshold"]=0.2928932188,["hasStaggerBand"]=true,["phase"]="stagger"};
        v["experience"]=new JArray(1200000,1000000,1400000);
        var text=Details(Snapshot(packet));
        Assert.Contains("生命：1400 / 1000（140%）\n超额：+400",text);
        Assert.Contains("魔力：750 / 600（125%）\n超额：+150",text);
        Assert.Contains("护盾：500 / 400（125%）\n超额：+100",text);
        Assert.Contains("25% · 踉跄风险",text);Assert.Contains("踉跄分界：约 29.3%",text);
        Assert.Contains("本级经验：200000 / 400000（50%）",text);Assert.Contains("距升级：200000",text);
        Assert.DoesNotContain("1200000 / 1400000",text);
        v["hp"]=new JArray(500,1000);v["experience"]=new JArray(1600000,1000000,1400000);
        text=Details(Snapshot(packet));Assert.Contains("超额：+0",text);Assert.Contains("距升级：0",text);
    }
    [Fact]
    public void MissingShieldAndInactivePoiseAreNotShownAsActiveOrSafe()
    {
        var packet=PlayerHudStateTests.Full();var v=packet["groups"]["vitals"];
        v["shieldReady"]=false;v["experience"]=new JArray(1200,1400,1400);
        var text=Details(Snapshot(packet));Assert.Contains("护盾：未就绪",text);
        Assert.Contains("踉跄分界：未就绪",text);Assert.Contains("区间未就绪",text);Assert.Contains("距升级：--",text);
        v["shieldReady"]=true;v["shieldPresent"]=false;
        v["poiseDetail"]=new JObject{["threshold"]=.5,["hasStaggerBand"]=true,["phase"]="rigid"};
        text=Details(Snapshot(packet));Assert.Contains("护盾：无护盾",text);Assert.Contains("刚体",text);Assert.Contains("当前不适用",text);
        v["poiseDetail"]["hasStaggerBand"]=false;v["poiseDetail"]["threshold"]=0;v["poiseDetail"]["phase"]="buffer";
        Assert.Contains("无踉跄区间",Details(Snapshot(packet)));
    }
    [Fact]
    public void DetailsRefreshInPlaceAndDoNotReturnAfterSuppressionOrEpochChange()
    {
        Sta(()=>
        {
            RuntimeFontCatalog.Configure(Root());
            using var form=new Form{ClientSize=new Size(1024,576)};using var anchor=new Panel{Dock=DockStyle.Fill};
            form.Controls.Add(anchor);form.CreateControl();anchor.CreateControl();
            using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
            var data=PlayerHudStateTests.Full();controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(data));
            using var detail=new PlayerHudResourceTooltip(anchor,controller);
            controller.ShowTooltip(Target(controller.State.Snapshot));var first=detail.Widget.ActiveDocument;
            Assert.NotNull(first);data["seq"]=2;data["groups"]["cooldowns"][0]=new JArray(0,1,30);
            controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(data));Assert.Same(first,detail.Widget.ActiveDocument);
            data["seq"]=3;data["groups"]["vitals"]["hp"][0]=777;
            controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(data));
            Assert.Equal(first.RequestId,detail.Widget.CurrentRequestId);Assert.Equal(3,detail.Widget.CurrentRevision);
            Assert.Contains("生命：777",string.Concat(detail.Widget.ActiveDocument.Sections.Select(s=>s.PlainText)));
            detail.Widget.OnHostSuppressed("owner_hidden");data["seq"]=4;data["groups"]["vitals"]["hp"][0]=778;
            controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(data));Assert.Null(detail.Widget.ActiveDocument);
            controller.ShowTooltip(Target(controller.State.Snapshot));Assert.NotNull(detail.Widget.ActiveDocument);
            data["epoch"]=2;data["seq"]=5;controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(data));Assert.Null(detail.Widget.ActiveDocument);
            controller.ShowTooltip(Target(controller.State.Snapshot));Assert.NotNull(detail.Widget.ActiveDocument);
            controller.Disconnected();Assert.Null(detail.Widget.ActiveDocument);
        });
    }
    [Fact]
    public void PausedCountdownOnlyChangesWhenTheAuthorityAdvancesAndRestoresTheKey()
    {
        Sta(()=>
        {
            var root=Root();RuntimeFontCatalog.Configure(root);
            using var form=new Form{ClientSize=new Size(1024,576)};using var anchor=new Panel{Dock=DockStyle.Fill};
            form.Controls.Add(anchor);form.CreateControl();anchor.CreateControl();
            using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
            using var bottom=new PlayerHudBottomWidget(anchor,controller,Path.Combine(root,"launcher","web","icons"));
            var data=PlayerHudStateTests.Full();data["groups"]["vitals"]["paused"]=true;
            data["groups"]["cooldowns"][1]=new JArray(0,0,126);
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(data),1));
            var origin=anchor.PointToScreen(Point.Empty);var rect=Rectangle.Ceiling(PlayerHudBottomWidget.HotkeyRect(PlayerHudBottomWidget.SkillRect(0)));
            Bitmap Paint(){var bitmap=new Bitmap(1024,576,PixelFormat.Format32bppPArgb);using(var g=Graphics.FromImage(bitmap))bottom.Paint(g,1,origin);return bitmap;}
            int Differences(Bitmap a,Bitmap b){var count=0;for(var y=rect.Top;y<rect.Bottom;y++)for(var x=rect.Left;x<rect.Right;x++)if(a.GetPixel(x,y)!=b.GetPixel(x,y))count++;return count;}
            using var start=Paint();bottom.Tick(5000);using var still=Paint();Assert.Equal(0,Differences(start,still));
            data["seq"]=2;data["groups"]["cooldowns"][1]=new JArray(0,30,126);
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(data),2));using var advanced=Paint();Assert.True(Differences(start,advanced)>0);
            data["seq"]=3;data["groups"]["cooldowns"][1]=new JArray(1,0,126);
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(data),3));bottom.Tick(300);using var ready=Paint();Assert.True(Differences(ready,advanced)>0);
        });
    }
    [Fact]
    public void BuffStyleSharesTopBarHeightAndClearsItsEmptyFrame()
    {
        Sta(()=>
        {
            using var form=new Form{ClientSize=new Size(1920,1080)};using var anchor=new Panel{Dock=DockStyle.Fill};
            form.Controls.Add(anchor);form.CreateControl();anchor.CreateControl();
            using var controller=new PlayerHudController(_=>true,()=>true,a=>a());
            using var buffs=new PlayerHudBuffWidget(anchor,controller);var packet=PlayerHudStateTests.Full();
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),1));
            Assert.Equal(anchor.PointToScreen(Point.Empty).Y,buffs.ScreenBounds.Top);
            Assert.Equal((int)Math.Ceiling(NativeHudTheme.TopBarHeightBase*1080d/576),buffs.ScreenBounds.Height);
            Assert.False(buffs.TryHitTest(buffs.ScreenBounds.Location));
            packet["seq"]=2;packet["groups"]["buffs"]=new JArray();Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),2));
            Assert.False(buffs.Visible);Assert.Equal(Rectangle.Empty,buffs.ScreenBounds);
        });
    }
}
