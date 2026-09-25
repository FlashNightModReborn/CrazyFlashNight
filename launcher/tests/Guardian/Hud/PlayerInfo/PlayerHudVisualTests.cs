using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Threading;
using System.Windows.Forms;
using System.Xml.Linq;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.Hud.Dialogue;
using Newtonsoft.Json.Linq;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerHudVisualTests
{
    public static IEnumerable<object[]> AuthoredAssets => PlayerHudArtData.Ids.Select(id => new object[] { id });
    [Fact]
    public void ResourceColorsMatchTheirNamedAuthoredAssets()
    {
        var root = FindRoot(); XNamespace ns = "http://ns.adobe.com/xfl/2008/";
        Color Source(string symbol) => ColorTranslator.FromHtml((string)XDocument.Load(Path.Combine(root,
            "flashswf", "arts", "新版人物文字信息", "LIBRARY", "素材-新版人物文字信息", symbol + ".xml"))
            .Descendants(ns + "SolidColor").Single().Attribute("color"));
        Assert.Equal(Source("盾槽条").ToArgb(), PlayerHudResourceStyle.Shield.ToArgb());
        Assert.Equal(Source("韧性条").ToArgb(), PlayerHudResourceStyle.Poise.ToArgb());
        var xpColors = XDocument.Load(Path.Combine(root,"flashswf","UI","玩家信息界面","LIBRARY","sprite","Symbol 1859.xml"))
            .Descendants(ns+"DOMLayer").Single(l => (string)l.Attribute("name") == "经验条满")
            .Descendants(ns+"GradientEntry").Select(e => ColorTranslator.FromHtml((string)e.Attribute("color")).ToArgb()).ToArray();
        Assert.Equal(new[] { PlayerHudResourceStyle.ExperienceDark.ToArgb(),PlayerHudResourceStyle.ExperienceLight.ToArgb() },xpColors);
        XNamespace svg="http://www.w3.org/2000/svg";
        using var ornamentBytes=new MemoryStream(PlayerHudArtData.Get("bottom-ornaments"));
        var arcColors=XDocument.Load(ornamentBytes).Descendants(svg+"path")
            .Where(p=>((string)p.Attribute("d")).StartsWith("M38.725 -41.65",StringComparison.Ordinal))
            .Select(p=>(string)p.Attribute("stroke")).ToArray();
        Assert.Equal(new[] { "#333333", "#CCCCCC" },arcColors);
    }

    [Theory]
    [InlineData("rigid")]
    [InlineData("air")]
    [InlineData("down")]
    public void InactivePoiseDoesNotPaintAnOrdinaryRiskMarker(string phase)
    {
        RunOnSta(() =>
        {
            var root = FindRoot(); RuntimeFontCatalog.Configure(root);
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var bottom = new PlayerHudBottomWidget(anchor, controller, Path.Combine(root, "launcher", "web", "icons"));
            var packet = PlayerHudStateTests.Full();
            packet["groups"]["vitals"]["poiseDetail"] = new JObject { ["threshold"] = 0.5, ["hasStaggerBand"] = true, ["phase"] = "buffer" };
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet), 1));
            using var normal = new Bitmap(1024, 576, PixelFormat.Format32bppPArgb);
            using var inactive = new Bitmap(1024, 576, PixelFormat.Format32bppPArgb);
            var origin = anchor.PointToScreen(Point.Empty);
            using (var g = Graphics.FromImage(normal)) bottom.Paint(g, 1, origin);
            packet["seq"] = 2; packet["groups"]["vitals"]["poiseDetail"]["phase"] = phase;
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet), 2));
            using (var g = Graphics.FromImage(inactive)) bottom.Paint(g, 1, origin);
            int MarkerPixels(Bitmap bitmap)
            {
                var count = 0;
                var bar=PlayerHudResourceLayout.PoiseBar;
                var marker=bar.Left+bar.Width/2;
                for (var x = (int)marker-2; x < marker+2; x++) for (var y = (int)bar.Top-2; y < bar.Top+1; y++)
                    if (bitmap.GetPixel(x, y).B > 190) count++;
                return count;
            }
            Assert.True(MarkerPixels(normal) > 0); Assert.Equal(0, MarkerPixels(inactive));
        });
    }
    [Theory]
    [MemberData(nameof(AuthoredAssets))]
    public void AuthoredArtUsesStrictRendererAndProducesVisiblePixels(string id)
    {
        using var cache = new PlayerHudArtCache();
        var image = cache.Get(id, 68, 68);
        var visible = 0;
        for (var y = 0; y < image.Height; y++) for (var x = 0; x < image.Width; x++) if (image.GetPixel(x, y).A > 10) visible++;
        Assert.True(visible > 30, id + " is unexpectedly empty");
        Assert.Same(image, cache.Get(id, 68, 68));
    }

    [Fact]
    public void AuthoredNameClockHoldsLeavesAndReenters()
    {
        Assert.Equal(3.7f, PlayerHudBottomWidget.NameOffset(0));
        Assert.Equal(3.7f, PlayerHudBottomWidget.NameOffset(3200));
        Assert.True(PlayerHudBottomWidget.NameOffset(6600) < -120);
        Assert.True(PlayerHudBottomWidget.NameOffset(6700) > 130);
        Assert.Equal(3.7f, PlayerHudBottomWidget.NameOffset(10000));
    }

    [Fact]
    public void OnlyTheAuthoredUnequipButtonWritesAndAChangedSlotCancelsTheGesture()
    {
        RunOnSta(() =>
        {
            var root = FindRoot(); RuntimeFontCatalog.Configure(root);
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            var sent = new List<JObject>();
            using var controller = new PlayerHudController(raw => { sent.Add(JObject.Parse(raw.TrimEnd('\0'))); return true; }, () => true, action => action());
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(PlayerHudStateTests.Full()));
            Assert.Equal("playerHudSync", (string)Assert.Single(sent)["action"]); sent.Clear();
            using var bottom = new PlayerHudBottomWidget(anchor, controller, Path.Combine(root, "launcher", "web", "icons"));
            var origin = anchor.PointToScreen(Point.Empty);
            MouseEventArgs At(RectangleF r) => new(MouseButtons.Left, 1, origin.X + (int)(r.X + r.Width / 2), origin.Y + (int)(r.Y + r.Height / 2), 0);
            void Click(RectangleF r)
            {
                var at = At(r); bottom.OnMouseEvent(at, MouseEventKind.Down); bottom.OnMouseEvent(at, MouseEventKind.Up); bottom.OnMouseEvent(at, MouseEventKind.Click);
            }
            Click(PlayerHudBottomWidget.SkillRect(0)); Assert.Empty(sent);
            var button = At(PlayerHudBottomWidget.UnequipRect(0));
            bottom.OnMouseEvent(button, MouseEventKind.Down);
            var changed = PlayerHudStateTests.Full(1, 2); changed["groups"]["loadout"]["revision"] = 4;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(changed));
            bottom.OnMouseEvent(button, MouseEventKind.Up); bottom.OnMouseEvent(button, MouseEventKind.Click); Assert.Empty(sent);
            Click(PlayerHudBottomWidget.UnequipRect(0));
            Assert.Single(sent); Assert.Equal("playerHudAction", (string)sent[0]["action"]);
            Assert.Equal(1, (int)sent[0]["slot"]); Assert.Equal(4, (int)sent[0]["revision"]);
        });
    }

    [Fact]
    public void ReadyFlashFinishesDuringPauseAndStopsRedrawingWhenSettled()
    {
        RunOnSta(() =>
        {
            var root = FindRoot(); RuntimeFontCatalog.Configure(root);
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var bottom = new PlayerHudBottomWidget(anchor, controller, Path.Combine(root, "launcher", "web", "icons"));
            var data = PlayerHudStateTests.Full(); data["groups"]["vitals"]["decorations"] = false; data["groups"]["vitals"]["paused"] = true;
            data["groups"]["cooldowns"][17] = new JArray(0, 29, 30);
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(data)); Assert.False(bottom.WantsAnimationTick);
            data["seq"] = 2; data["groups"]["cooldowns"][17] = new JArray(1, 0, 30);
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(data)); Assert.True(bottom.WantsAnimationTick);
            data["seq"] = 3; data["groups"]["vitals"]["paused"] = true;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(data)); bottom.Tick(500); Assert.False(bottom.WantsAnimationTick);
            data["seq"] = 4; data["groups"]["vitals"]["paused"] = false;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(data)); Assert.False(bottom.WantsAnimationTick);
            bottom.Tick(300); Assert.False(bottom.WantsAnimationTick);
            var repaints = 0; bottom.RepaintRequested += (_, _) => repaints++;
            for (var i = 0; i < 100; i++) bottom.Tick(33);
            Assert.Equal(0, repaints);
        });
    }

    [Fact]
    public void NameAnimationContinuesWhenGameplayIsPaused()
    {
        RunOnSta(() =>
        {
            var root = FindRoot(); RuntimeFontCatalog.Configure(root);
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var bottom = new PlayerHudBottomWidget(anchor, controller, Path.Combine(root, "launcher", "web", "icons"));
            var packet = PlayerHudStateTests.Full(); packet["groups"]["vitals"]["paused"] = true;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.True(bottom.WantsAnimationTick);
            var repaints = 0; bottom.RepaintRequested += (_, _) => repaints++;
            bottom.Tick(34); Assert.True(repaints > 0);
            packet["seq"] = 2; packet["groups"]["vitals"]["decorations"] = false;
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(packet));
            Assert.False(bottom.WantsAnimationTick);
        });
    }

    [Fact]
    public void NativeDialogueReappearanceRestoresActualWindowOrderWithNoBuffs()
    {
        RunOnSta(()=>
        {
            RuntimeFontCatalog.Configure(FindRoot());
            using var owner=new Form {ClientSize=new Size(1024,576),Location=new Point(-20000,-20000),StartPosition=FormStartPosition.Manual};
            using var anchor=new Panel {Dock=DockStyle.Fill};owner.Controls.Add(anchor);owner.Show();
            using var main=new NativeHudOverlay(owner,anchor);
            var dialogue=new NativeDialogueWidget(anchor);main.AddWidget(dialogue);
            var controller=new PlayerHudController(_=>true,()=>true,a=>a());
            var packet=PlayerHudStateTests.Full();packet["groups"]["buffs"]=new JArray();
            controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(packet));
            using var resources=PlayerInfoSplitSurface.CreateLive(owner,anchor,controller.State);
            using var runtime=new PlayerHudRuntime(owner,anchor,resources,controller,Path.Combine(FindRoot(),"launcher","web","icons"),main);
            var bottom=(NativeHudOverlay)typeof(PlayerHudRuntime).GetField("_bottom",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(runtime);
            var buffs=(NativeHudOverlay)typeof(PlayerHudRuntime).GetField("_buffs",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(runtime);
            main.SetReady();runtime.SetReady();
            ShowDialogue("nd:stack1");
            PumpUntil(()=>resources.Counters.CommitSuccessCount>0 && IsWindowVisible(main.Handle) && IsWindowVisible(bottom.Handle));
            Assert.False(IsWindowVisible(buffs.Handle));
            AssertAbove(main.Handle,resources.Handle);AssertAbove(resources.Handle,bottom.Handle);
            // Deliberately disturb the relative stack while retaining foreground.
            var foreground=GetForegroundWindow();
            Assert.True(SetWindowPos(resources.Handle,IntPtr.Zero,0,0,0,0,0x0013|0x0200));
            AssertAbove(resources.Handle,main.Handle);
            main.Suspend();main.Resume();
            PumpUntil(()=>IsWindowVisible(main.Handle));
            AssertAbove(main.Handle,resources.Handle);AssertAbove(resources.Handle,bottom.Handle);
            Assert.Equal(foreground,GetForegroundWindow());
            owner.Location=new Point(-19700,-19800);
            Assert.True(resources.Counters.Shown);AssertAbove(main.Handle,resources.Handle);
            runtime.Suspend();Assert.False(resources.Counters.Shown);
            runtime.Resume();PumpUntil(()=>resources.Counters.Shown);
            AssertAbove(main.Handle,resources.Handle);AssertAbove(resources.Handle,bottom.Handle);
            owner.ClientSize=new Size(1280,720);
            Assert.True(resources.Counters.Shown);
            PumpUntil(()=>resources.Size==resources.Counters.TightPhysicalBounds.Size);
            AssertAbove(main.Handle,resources.Handle);AssertAbove(resources.Handle,bottom.Handle);
            owner.WindowState=FormWindowState.Minimized;
            Application.DoEvents();Assert.False(resources.Counters.Shown);
            owner.WindowState=FormWindowState.Normal;owner.Activate();
            PumpUntil(()=>resources.Counters.Shown && IsWindowVisible(main.Handle));
            AssertAbove(main.Handle,resources.Handle);AssertAbove(resources.Handle,bottom.Handle);

            void ShowDialogue(string id)=>dialogue.ShowFrame(new NativeDialogueFrame {RequestId=id,SceneId="stack-scene",Revision=1,LineCount=1,Name="测试",Title="",Text="对话层级测试",PortraitKey="",Expression="",ImageAction="keep",ImagePath=""});
        });
    }
    private static void PumpUntil(Func<bool> done)
    {
        var wait=Stopwatch.StartNew();
        while(!done() && wait.ElapsedMilliseconds<15000){Application.DoEvents();Thread.Sleep(10);}
        Assert.True(done(),"native HUD presentation timed out");
    }
    private static void AssertAbove(IntPtr higher,IntPtr lower)
    {
        for(var h=GetWindow(lower,3);h!=IntPtr.Zero;h=GetWindow(h,3))if(h==higher)return;
        Assert.Fail("Expected HWND "+higher+" above "+lower);
    }
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd,uint cmd);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);

    [Fact]
    public void HiddenBuffAndResourceWindowsNeverBecomeOrderingAnchors()
    {
        foreach(var hidden in new[]{new[]{2},new[]{3},new[]{2,3}})
        {
            var z=new List<int>{4,3,2,1}; // hidden HWNDs start ABOVE the dialogue HUD
            var visible=new HashSet<int>(new[]{1,2,3,4}.Except(hidden));
            PlayerHudRuntime.RestoreStack((IntPtr)1,(IntPtr)2,(IntPtr)3,(IntPtr)4,(window,previous)=>
            {
                int w=window.ToInt32();if(!visible.Contains(w))return false;
                Assert.Contains(previous.ToInt32(),visible);
                z.Remove(w);z.Insert(z.IndexOf(previous.ToInt32())+1,w);return true;
            });
            Assert.Equal(new[]{1,2,3,4}.Where(visible.Contains),z.Where(visible.Contains));
        }
    }

    [Fact]
    public void EveryInitialPresentationOrderRestoresGaugesAboveTheChassis()
    {
        var orders = new[] { new[]{2,3,4}, new[]{2,4,3}, new[]{3,2,4}, new[]{3,4,2}, new[]{4,2,3}, new[]{4,3,2} };
        foreach (var order in orders)
        {
            // Model ShowWindow raising a newly presented owned window, including an
            // asynchronously rasterized resource surface arriving after its siblings.
            var z = new List<int> { 1, 2, 3, 4 }; var visible = new HashSet<int> { 1 };
            foreach (var shown in order)
            {
                visible.Add(shown); z.Remove(shown); z.Insert(0, shown);
                PlayerHudRuntime.RestoreStack((IntPtr)1, (IntPtr)2, (IntPtr)3, (IntPtr)4, (window, previous) =>
                {
                    var w = window.ToInt32(); if (!visible.Contains(w)) return false;
                    z.Remove(w); z.Insert(z.IndexOf(previous.ToInt32()) + 1, w); return true;
                });
                if (visible.Contains(3) && visible.Contains(4)) Assert.True(z.IndexOf(3) < z.IndexOf(4));
            }
            Assert.Equal(new[]{1,2,3,4}, z);
        }
    }

    [Fact]
    public void AuthoredShieldArcTracksShieldIndependentlyOfMp()
    {
        RuntimeFontCatalog.Configure(FindRoot());
        var state = new PlayerHudState(); state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full()), 1);
        var value = state.Snapshot.Vitals with { ShieldPresent = true, ShieldReady = true, Shield = 400, ShieldMax = 400, Mp = 0 };
        var assets = PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster:false);
        var plan = PlayerInfoRasterPlanner.Create(assets, new Rectangle(0,0,1024,576), 1);
        using var batch = new PlayerInfoSvgRasterizer().Bake(plan, CancellationToken.None);
        Bitmap Draw(PlayerHudVitals v)
        {
            var model = new PlayerInfoAnimationModel(); model.ApplyProduction(v);
            using var widget = new PlayerInfoWidget(assets, model) { LiveVitals = v };
            var image = new Bitmap(plan.TightPhysicalBounds.Width, plan.TightPhysicalBounds.Height, PixelFormat.Format32bppPArgb);
            widget.Paint(image, batch, plan); return image;
        }
        using var fullShieldEmptyMp = Draw(value);
        using var fullBoth = Draw(value with { Mp = value.MpMax });
        using var emptyShieldFullMp = Draw(value with { Mp = value.MpMax, Shield = 0 });
        var changed = 0; var cyan = 0;
        for (var y = 508; y < 551; y++) for (var x = 60; x < 89; x++)
        {
            var px = x - plan.TightPhysicalBounds.Left; var py = y - plan.TightPhysicalBounds.Top;
            Assert.Equal(fullShieldEmptyMp.GetPixel(px,py), fullBoth.GetPixel(px,py));
            var pixel = fullBoth.GetPixel(px,py);
            if (pixel != emptyShieldFullMp.GetPixel(px,py))
            {
                changed++;
                // Rim antialiasing and the HP glow also cover edge pixels.
                if (pixel.R < 5 && pixel.G > 80)
                {
                    cyan++;
                    Assert.InRange(Math.Abs(pixel.G - pixel.B), 0, 1);
                }
            }
        }
        Assert.True(changed > 30, "Shield capacity must drive the authored side arc");
        Assert.True(cyan > 30, "The shield fill must keep the approved cyan hue");
    }

    [Fact]
    public void ConstantHealthAnimatesDuringPauseButStopsWhenDecorationsAreDisabled()
    {
        RuntimeFontCatalog.Configure(FindRoot());
        var state = new PlayerHudState(); state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full()), 1);
        var values = state.Snapshot.Vitals with { Hp = 7017, HpMax = 7017, Paused = true, Decorations = true };
        var assets = PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster:false);
        var plan = PlayerInfoRasterPlanner.Create(assets, new Rectangle(0,0,1920,1080), 1);
        using var batch = new PlayerInfoSvgRasterizer().Bake(plan, CancellationToken.None);
        var model = new PlayerInfoAnimationModel(); model.ApplyProduction(values);
        using var widget = new PlayerInfoWidget(assets, model) { LiveVitals = values };
        Bitmap Paint()
        {
            var image = new Bitmap(plan.TightPhysicalBounds.Width,plan.TightPhysicalBounds.Height,PixelFormat.Format32bppPArgb);
            widget.Paint(image,batch,plan); return image;
        }
        using var before = Paint();
        Assert.False(model.WantsAnimationTick);
        Assert.True(widget.AdvanceLiveDecoration(2100));
        using var animated = Paint();
        Assert.True(DifferentPixels(before,animated,new Rectangle(0,0,before.Width,before.Height)) > 100);
        widget.LiveVitals = values with { Decorations = false };
        Assert.False(widget.AdvanceLiveDecoration(10000));
        using var disabled = Paint();
        Assert.Equal(0,DifferentPixels(animated,disabled,new Rectangle(0,0,before.Width,before.Height)));
        widget.LiveVitals = values with { Hp = 0 };
        Assert.False(widget.AdvanceLiveDecoration(1000));
        widget.LiveVitals = values; widget.ResetLiveClock();
        using var reset = Paint();
        Assert.Equal(0,DifferentPixels(before,reset,new Rectangle(0,0,before.Width,before.Height)));
        if (Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_CAPTURE") == "1")
        {
            var output = Path.Combine(FindRoot(),"tmp","player-info-full");
            before.Save(Path.Combine(output,"hud-hp-motion-frame-000.png"));
            animated.Save(Path.Combine(output,"hud-hp-motion-frame-063.png"));
        }
    }

    [Theory]
    [InlineData("motifs", 0, 50, 100)]
    [InlineData("grid", 0, 5, 11)]
    [InlineData("light", 0, 90, 216)]
    public void EachAuthoredHpClipChangesAndRepeatsItsOwnLoop(string clip, int first, int later, int repeat)
    {
        using var motion = new PlayerHudHpMotion();
        SKColor[] Paint(int frame)
        {
            using var bitmap = new SKBitmap(188,188);
            using var canvas = new SKCanvas(bitmap);
            canvas.Clear(new SKColor(180,0,0)); canvas.Translate(94,94); canvas.Scale(2);
            if (clip == "motifs") motion.DrawMotifs(canvas,frame);
            else if (clip == "grid") motion.DrawGrid(canvas,frame);
            else motion.DrawLight(canvas,frame);
            return bitmap.Pixels;
        }
        var start = Paint(first); var next = Paint(later);
        Assert.True(start.Zip(next,(a,b) => a != b).Count(changed => changed) > 20, clip);
        Assert.Equal(start,Paint(repeat));
    }

    [Fact]
    public void ShieldPlaqueDoesNotMoveCombatReadingsOrLevelAndExperience()
    {
        RunOnSta(() =>
        {
            var root = FindRoot(); RuntimeFontCatalog.Configure(root);
            using var owner = new Form { ClientSize = new Size(1024,576) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var bottom = new PlayerHudBottomWidget(anchor,controller,Path.Combine(root,"launcher","web","icons"));
            var packet = PlayerHudStateTests.Full();
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),1));
            using var depleted = new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
            var origin = anchor.PointToScreen(Point.Empty);
            using (var g = Graphics.FromImage(depleted)) bottom.Paint(g,1,origin);
            packet["seq"] = 2; packet["groups"]["vitals"]["shieldPresent"] = false;
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),2));
            using var absent = new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(absent)) bottom.Paint(g,1,origin);
            Assert.Equal(0,DifferentPixels(depleted,absent,new Rectangle(0,504,286,72)));
            var assets=PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster:false);
            var plan=PlayerInfoRasterPlanner.Create(assets,new Rectangle(0,0,1024,576),1);
            using var batch=new PlayerInfoSvgRasterizer().Bake(plan,CancellationToken.None);
            Bitmap Resources(PlayerHudVitals values)
            {
                var model=new PlayerInfoAnimationModel();model.ApplyProduction(values);
                using var widget=new PlayerInfoWidget(assets,model){LiveVitals=values};
                var result=new Bitmap(plan.TightPhysicalBounds.Width,plan.TightPhysicalBounds.Height,PixelFormat.Format32bppPArgb);
                widget.Paint(result,batch,plan);return result;
            }
            var values=controller.State.Snapshot.Vitals;
            using var noShield=Resources(values);
            using var zeroShield=Resources(values with { ShieldPresent=true });
            using var otherMaximum=Resources(values with { ShieldPresent=true,ShieldMax=values.ShieldMax+1 });
            using var unready=Resources(values with { ShieldReady=false });
            var plaque=Rectangle.Round(PlayerHudResourceLayout.ShieldPlaque);
            plaque.Offset(-plan.TightPhysicalBounds.Left,-plan.TightPhysicalBounds.Top);
            Assert.True(DifferentPixels(noShield,zeroShield,plaque)>500);
            Assert.True(DifferentPixels(zeroShield,unready,plaque)>50);
            // Both shields are empty and show 0%; only the displayed upper limit changes.
            Assert.True(DifferentPixels(zeroShield,otherMaximum,plaque)>5);
        });
    }

    [Fact]
    public void LiveHpSeparatorDoesNotRetainTheAuthoredSmallPercentSign()
    {
        using var rule = SKPath.ParseSvgPathData(PlayerHudHpMotionData.SeparatorPath);
        Assert.InRange(rule.Bounds.Height,0.34f,0.36f);
        Assert.InRange(rule.Bounds.Width,45.19f,45.21f);
        Assert.InRange(rule.Bounds.Top,-0.001f,0.001f);
    }

    [Fact]
    public void ExperiencePercentAndNumbersUseTheSameLevelInterval()
    {
        var state = new PlayerHudState(); state.Receive(PlayerHudStateTests.Encode(PlayerHudStateTests.Full()),1);
        var values = state.Snapshot.Vitals with { Experience=1200000, ExperienceStart=1000000, ExperienceEnd=1400000 };
        var (earned,required) = PlayerHudResourceStyle.LevelExperience(values);
        Assert.Equal("50%",PlayerHudResourceStyle.Percent(earned,required));
        Assert.Equal("200000/400000",PlayerHudResourceStyle.ExperienceReadout(values));
        values = values with { ExperienceEnd=1000000 };
        (earned,required) = PlayerHudResourceStyle.LevelExperience(values);
        Assert.Equal("--",PlayerHudResourceStyle.Percent(earned,required));
        Assert.Equal("1200000",PlayerHudResourceStyle.ExperienceReadout(values));
    }

    [Fact]
    public void PoiseRiskNotchesRemainDistinctWithoutChangingTheBufferGrid()
    {
        RunOnSta(() =>
        {
            var root = FindRoot(); RuntimeFontCatalog.Configure(root);
            using var owner = new Form { ClientSize = new Size(1024,576) };
            using var anchor = new Panel { Dock = DockStyle.Fill };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            using var bottom = new PlayerHudBottomWidget(anchor,controller,Path.Combine(root,"launcher","web","icons"));
            var packet = PlayerHudStateTests.Full();
            packet["groups"]["vitals"]["poise"] = 1;
            packet["groups"]["vitals"]["poiseDetail"] = new JObject { ["threshold"]=0.5, ["hasStaggerBand"]=true, ["phase"]="buffer" };
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),1));
            using var bitmap = new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
            using (var g=Graphics.FromImage(bitmap)) bottom.Paint(g,1,anchor.PointToScreen(Point.Empty));
            packet["seq"]=2;packet["groups"]["vitals"]["poiseDetail"]["hasStaggerBand"]=false;
            packet["groups"]["vitals"]["poiseDetail"]["threshold"]=0;
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),2));
            using var noRisk=new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
            using (var g=Graphics.FromImage(noRisk)) bottom.Paint(g,1,anchor.PointToScreen(Point.Empty));
            bool SolidAt(Bitmap image,int x,int y)
            {
                var c=image.GetPixel(x,y); return c.R*0.299+c.G*0.587+c.B*0.114 > 150;
            }
            var bar=PlayerHudResourceLayout.PoiseBar;
            var boundary=bar.Left+bar.Width/2;
            var shapeDifferences = 0;
            for(var y=(int)bar.Bottom-3;y<bar.Bottom;y++) for(var x=(int)bar.Left;x<boundary-2;x++)
                if (SolidAt(bitmap,x,y) != SolidAt(noRisk,x,y)) shapeDifferences++;
            Assert.True(shapeDifferences>15,"Risk notches must survive discarding hue");
            Assert.False(SolidAt(bitmap,(int)boundary,(int)bar.Top+4));
            var buffer=Rectangle.FromLTRB((int)Math.Ceiling(boundary+3),(int)bar.Top,(int)bar.Right,(int)Math.Ceiling(bar.Bottom));
            Assert.Equal(0,DifferentPixels(bitmap,noRisk,buffer));
        });
    }

    [Fact]
    public void DetailsEntryIsSeparateFromSkillActionsAndUsesOnlyLocalSnapshotDetails()
    {
        RunOnSta(() =>
        {
            var root=FindRoot();RuntimeFontCatalog.Configure(root);
            using var owner=new Form { ClientSize=new Size(1024,576) };
            using var anchor=new Panel { Dock=DockStyle.Fill };
            owner.Controls.Add(anchor);owner.CreateControl();anchor.CreateControl();
            var sent=new List<JObject>();
            using var controller=new PlayerHudController(raw=>{sent.Add(JObject.Parse(raw.TrimEnd('\0')));return true;},()=>true,action=>action());
            controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(PlayerHudStateTests.Full()));sent.Clear();
            using var bottom=new PlayerHudBottomWidget(anchor,controller,Path.Combine(root,"launcher","web","icons"));
            using var resourceTooltip=new PlayerHudResourceTooltip(anchor,controller);
            var details=PlayerHudBottomWidget.DetailsRect;
            Assert.True(PlayerHudBottomWidget.DetailsFace.Top>=518.05f);
            Assert.True(PlayerHudBottomWidget.DetailsFace.Bottom<=527.15f);
            Assert.True(details.Contains(PlayerHudBottomWidget.DetailsFace));
            using(var source=new MemoryStream(PlayerHudArtData.Get("skill-panel")))
            {
                XNamespace svg="http://www.w3.org/2000/svg";
                var stripe=XDocument.Load(source).Descendants(svg+"path").Single(p=>(string)p.Attribute("fill")=="url(#g2)");
                var points=System.Text.RegularExpressions.Regex.Matches((string)stripe.Attribute("d"),@"-?\d+(?:\.\d+)?")
                    .Select(m=>float.Parse(m.Value,System.Globalization.CultureInfo.InvariantCulture)).ToArray();
                var outline=PlayerHudBottomWidget.DetailsOutline;
                for(var i=0;i<4;i++)
                {
                    Assert.Equal(points[i*2]+592.9f,outline[i].X,3);
                    Assert.Equal(points[i*2+1]+528.9f,outline[i].Y,3);
                }
            }
            for(var i=0;i<12;i++)
            {
                Assert.False(details.IntersectsWith(PlayerHudBottomWidget.SkillRect(i)));
                Assert.False(details.IntersectsWith(PlayerHudBottomWidget.UnequipRect(i)));
            }
            var origin=anchor.PointToScreen(Point.Empty);
            var at=new MouseEventArgs(MouseButtons.Left,1,origin.X+(int)(details.Left+details.Width/2),origin.Y+(int)(details.Top+details.Height/2),0);
            bottom.OnMouseEvent(at,MouseEventKind.Move);
            bottom.OnMouseEvent(at,MouseEventKind.Down);bottom.OnMouseEvent(at,MouseEventKind.Up);bottom.OnMouseEvent(at,MouseEventKind.Click);
            Assert.Empty(sent);
            Assert.Equal("player-hud-resources",resourceTooltip.Widget.ActiveDocument.Owner);
            Assert.Equal(details.X,resourceTooltip.Widget.ActiveDocument.AnchorRect.Value.X);
            Assert.False(bottom.TryHitTest(new Point(origin.X+266,origin.Y+560)));
            Assert.False(bottom.TryHitTest(new Point(origin.X+910,origin.Y+522)));
        });
    }

    [Fact]
    public void FullMpAndPoiseFollowTheSameTenSlantedColumns()
    {
        RunOnSta(() =>
        {
            var root=FindRoot();RuntimeFontCatalog.Configure(root);
            using var owner=new Form { ClientSize=new Size(1920,1080) };
            using var anchor=new Panel { Dock=DockStyle.Fill };
            owner.Controls.Add(anchor);owner.CreateControl();anchor.CreateControl();
            using var controller=new PlayerHudController(_=>true,()=>true,action=>action());
            var packet=PlayerHudStateTests.Full();packet["groups"]["vitals"]["mp"]=new JArray(600,600);
            packet["groups"]["vitals"]["poise"]=1;
            packet["groups"]["vitals"]["poiseDetail"]=new JObject{["threshold"]=0,["hasStaggerBand"]=false,["phase"]="buffer"};
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),1));
            using var bottom=new PlayerHudBottomWidget(anchor,controller,Path.Combine(root,"launcher","web","icons"));
            using var bitmap=new Bitmap(1920,1080,PixelFormat.Format32bppPArgb);
            var assets=PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster:false);
            var plan=PlayerInfoRasterPlanner.Create(assets,new Rectangle(0,0,1920,1080),1);
            using var batch=new PlayerInfoSvgRasterizer().Bake(plan,CancellationToken.None);
            var model=new PlayerInfoAnimationModel();model.ApplyProduction(controller.State.Snapshot.Vitals);
            using var widget=new PlayerInfoWidget(assets,model){LiveVitals=controller.State.Snapshot.Vitals};
            using var resources=new Bitmap(plan.TightPhysicalBounds.Width,plan.TightPhysicalBounds.Height,PixelFormat.Format32bppPArgb);
            widget.Paint(resources,batch,plan);
            using(var g=Graphics.FromImage(bitmap))
            { bottom.Paint(g,1,anchor.PointToScreen(Point.Empty));g.DrawImageUnscaled(resources,plan.TightPhysicalBounds.Location); }
            List<(int Start,int End)> Runs(RectangleF bar,bool mp)
            {
                var scale=1080f/576;var result=new List<(int,int)>();var start=-1;
                var y=(int)((bar.Top+bar.Height/2)*scale);
                for(var x=(int)(bar.Left*scale)-2;x<(bar.Right*scale)+3;x++)
                {
                    var p=bitmap.GetPixel(x,y);
                    var filled=mp ? p.G>160&&p.B>160&&p.R+p.G+p.B>450 : p.R>180&&p.G>130&&p.B<100;
                    if(filled&&start<0)start=x;
                    if(!filled&&start>=0){result.Add((start,x-1));start=-1;}
                }
                return result;
            }
            var blue=Runs(PlayerHudResourceLayout.MpBar,true);var yellow=Runs(PlayerHudResourceLayout.PoiseBar,false);
            Assert.Equal(10,blue.Count);Assert.Equal(10,yellow.Count);
            var cell=PlayerHudBarArtData.Cells[0];
            var slope=(cell[3].X-cell[0].X)/(cell[3].Y-cell[0].Y);
            var expectedOffset=slope*(PlayerHudResourceLayout.PoiseBar.Top-PlayerHudResourceLayout.MpBar.Top)*1080/576;
            Assert.Equal(PlayerHudResourceLayout.LevelTop,PlayerHudResourceLayout.PoiseBar.Bottom);
            for(var i=0;i<10;i++)
            { Assert.InRange(Math.Abs(yellow[i].Start-blue[i].Start-expectedOffset),0,2);Assert.InRange(Math.Abs(yellow[i].End-blue[i].End-expectedOffset),0,2); }
        });
    }

    private static int DifferentPixels(Bitmap a, Bitmap b, Rectangle area)
    {
        var result = 0;
        for (var y = area.Top; y < area.Bottom; y++) for (var x = area.Left; x < area.Right; x++)
            if (a.GetPixel(x,y) != b.GetPixel(x,y)) result++;
        return result;
    }

    [Fact]
    public void HotkeyCaptionsStayInTheirSlotAndSpaceAliasesDoNotChangeTheBinding()
    {
        RunOnSta(() =>
        {
            var root=FindRoot();RuntimeFontCatalog.Configure(root);
            using var owner=new Form { ClientSize=new Size(1024,576) };
            using var anchor=new Panel { Dock=DockStyle.Fill };
            owner.Controls.Add(anchor);owner.CreateControl();anchor.CreateControl();
            using var controller=new PlayerHudController(_=>true,()=>true,action=>action());
            using var bottom=new PlayerHudBottomWidget(anchor,controller,Path.Combine(root,"launcher","web","icons"));
            var packet=PlayerHudStateTests.Full();
            packet["groups"]["loadout"]["skills"][0]["keyLabel"]="";
            Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),1));
            using var blank=new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
            var origin=anchor.PointToScreen(Point.Empty);
            using(var g=Graphics.FromImage(blank))bottom.Paint(g,1,origin);
            var caption=Rectangle.Ceiling(PlayerHudBottomWidget.HotkeyRect(PlayerHudBottomWidget.SkillRect(0)));
            Bitmap first=null;
            try
            {
                var sequence=2;
                foreach(var raw in new[]{"Spacebar","空格","Ctrl+Shift+F12"})
                {
                    packet["seq"]=sequence;packet["groups"]["loadout"]["skills"][0]["keyLabel"]=raw;
                    Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(packet),sequence++));
                    Assert.Equal(raw,controller.State.Snapshot.Loadout.Skills[0].Hotkey);
                    using var painted=new Bitmap(1024,576,PixelFormat.Format32bppPArgb);
                    using(var g=Graphics.FromImage(painted))bottom.Paint(g,1,origin);
                    var changes=0;
                    for(var y=530;y<576;y++)for(var x=590;x<640;x++)
                        if(painted.GetPixel(x,y)!=blank.GetPixel(x,y))
                        { Assert.True(caption.Contains(x,y),"Hotkey ink escaped its slot caption");changes++; }
                    Assert.True(changes>20);
                    if(raw=="Spacebar") first=(Bitmap)painted.Clone();
                    else if(raw=="空格")Assert.Equal(0,DifferentPixels(first,painted,caption));
                }
            }
            finally { first?.Dispose(); }
        });
    }

    private static string FindRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory != null && !File.Exists(Path.Combine(directory.FullName, "fonts", "fonts.xml"))) directory = directory.Parent;
        Assert.NotNull(directory); return directory.FullName;
    }
    private static void RunOnSta(Action body)
    {
        Exception failure = null;
        var worker = new Thread(() => { try { body(); } catch (Exception ex) { failure = ex; } });
        worker.SetApartmentState(ApartmentState.STA); worker.Start();
        Assert.True(worker.Join(TimeSpan.FromSeconds(45)), "HUD verification did not complete");
        if (failure != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }

    [Theory]
    [InlineData("switch", 1024, 576)]
    [InlineData("weapon", 1024, 576)]
    [InlineData("switch", 1920, 1080)]
    [InlineData("weapon", 1920, 1080)]
    public void CooldownStaysVisibleOverTheSwitchDotsAndWeaponArt(string kind, int width, int height)
    {
        Exception failure = null;
        var worker = new Thread(() =>
        {
            try
            {
                var directory = new DirectoryInfo(AppContext.BaseDirectory);
                while (directory != null && !File.Exists(Path.Combine(directory.FullName, "fonts", "fonts.xml"))) directory = directory.Parent;
                Assert.NotNull(directory);
                RuntimeFontCatalog.Configure(directory.FullName);
                using var owner = new Form { ClientSize = new Size(width, height) };
                using var anchor = new Panel { Dock = DockStyle.Fill };
                owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
                using var controller = new PlayerHudController(_ => true, () => true, action => action());
                var data = PlayerHudStateTests.Full();
                data["groups"]["combat"]["mode"] = "手枪";
                Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(data), 1));
                using var bottom = new PlayerHudBottomWidget(anchor, controller, Path.Combine(directory.FullName, "launcher", "web", "icons"));
                using var ready = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
                using var cooling = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
                var origin = anchor.PointToScreen(Point.Empty);
                using (var g = Graphics.FromImage(ready)) bottom.Paint(g, 1, origin);
                data["seq"] = 2;
                data["groups"]["cooldowns"][kind == "switch" ? 17 : 0] = new JArray(0, 10, 30);
                Assert.True(controller.State.Receive(PlayerHudStateTests.Encode(data), 2));
                using (var g = Graphics.FromImage(cooling)) bottom.Paint(g, 1, origin);
                var rect = kind == "switch" ? PlayerHudBottomWidget.SwitchRect : PlayerHudBottomWidget.WeaponRect;
                var scale = height / 576f;
                long brightBefore = 0, brightAfter = 0;
                for (var y = (int)((rect.Top + 4) * scale); y < (int)((rect.Top + 15) * scale); y++)
                for (var x = (int)((rect.Left + 3) * scale); x < (int)((rect.Right - 3) * scale); x++)
                {
                    var a = ready.GetPixel(x, y); var b = cooling.GetPixel(x, y);
                    if (a.R + a.G + a.B < 400) continue;
                    brightBefore += a.R + a.G + a.B;
                    brightAfter += b.R + b.G + b.B;
                }
                Assert.True(brightBefore > 1000, kind + " must have visible authored foreground");
                Assert.True(brightAfter < brightBefore * 0.65, kind + " foreground hides the cooldown shade");
                var strip=PlayerHudBottomWidget.CooldownTrackRect(rect);
                Assert.False(strip.IntersectsWith(PlayerHudBottomWidget.HotkeyRect(rect)));
                var elapsed = cooling.GetPixel((int)((strip.Left + 2) * scale), (int)((strip.Top + 1) * scale));
                var remaining = cooling.GetPixel((int)((strip.Right - 2) * scale), (int)((strip.Top + 1) * scale));
                Assert.True(elapsed.R + elapsed.G > remaining.R + remaining.G + 150, kind + " needs a readable progress strip");
            }
            catch (Exception ex) { failure = ex; }
        });
        worker.SetApartmentState(ApartmentState.STA); worker.Start();
        Assert.True(worker.Join(TimeSpan.FromSeconds(45)), "Cooldown render did not complete");
        if (failure != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }

    [Theory]
    [InlineData(1024, 576)]
    [InlineData(1920, 1080)]
    [InlineData(2560, 1440)]
    [InlineData(1024, 576, true)]
    [InlineData(1920, 1080, true)]
    [InlineData(1024, 576, false, false)]
    [InlineData(1920, 1080, false, false)]
    [InlineData(1024, 576, false, true, true)]
    [InlineData(1920, 1080, false, true, true)]
    [InlineData(1024, 576, false, true, false, true)]
    [InlineData(1920, 1080, false, true, false, true)]
    public void FullHudPaintsAtActualPhysicalSizeAndLeavesGameplaySpaceTransparent(int width, int height, bool overflow = false, bool shield = true, bool longReadings = false, bool depleted = false)
    {
        Exception failure = null;
        var worker = new Thread(() =>
        {
            try { Render(width, height, overflow, shield, longReadings, depleted); } catch (Exception ex) { failure = ex; }
        });
        worker.SetApartmentState(ApartmentState.STA); worker.Start();
        Assert.True(worker.Join(TimeSpan.FromSeconds(45)), "HUD render did not complete");
        if (failure != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }

    private static void Render(int width, int height, bool overflow, bool shield, bool longReadings, bool depleted)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory != null && !File.Exists(Path.Combine(directory.FullName, "fonts", "fonts.xml"))) directory = directory.Parent;
        Assert.NotNull(directory);
        var root = directory.FullName;
        RuntimeFontCatalog.Configure(root);
        using var owner = new Form { ClientSize = new Size(width, height), StartPosition = FormStartPosition.Manual, Location = new Point(0, 0) };
        using var anchor = new Panel { Dock = DockStyle.Fill };
        owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
        using var controller = new PlayerHudController(_ => true, () => true, action => action());
        var data = PlayerHudStateTests.Full(); var groups = data["groups"];
        groups["vitals"]["name"] = "铁皮突击队长";
        groups["vitals"]["level"] = 42; groups["vitals"]["hp"] = new JArray(8250, 12800);
        groups["vitals"]["mp"] = new JArray(4150, 10000); groups["vitals"]["shield"] = new JArray(1600, 2400);
        groups["vitals"]["shieldPresent"] = shield;
        groups["vitals"]["poiseDetail"] = new JObject { ["threshold"] = 0.2928932188, ["hasStaggerBand"] = true, ["phase"] = "buffer" };
        if (overflow)
        {
            groups["vitals"]["hp"] = new JArray(1400, 1000); groups["vitals"]["mp"] = new JArray(1750, 1000);
            groups["vitals"]["shield"] = new JArray(250, 1000);
            groups["vitals"]["poise"] = 0.35;
            groups["vitals"]["poiseDetail"] = new JObject { ["threshold"] = 0.6464466094, ["hasStaggerBand"] = true, ["phase"] = "stagger" };
            groups["vitals"]["name"] = "溢出恢复与护盾衰减";
        }
        if (longReadings)
        {
            groups["vitals"]["hp"] = new JArray(7017,7017); groups["vitals"]["mp"] = new JArray(1206,4634);
            groups["vitals"]["shield"] = new JArray(8355,8355); groups["vitals"]["poise"] = 1;
            groups["vitals"]["level"] = 99;
            groups["vitals"]["sp"] = 2515;
            groups["vitals"]["experience"] = new JArray(123456789,100000000,150000000);
            groups["vitals"]["poiseDetail"]["threshold"] = 0.5;
        }
        if (depleted)
        {
            groups["vitals"]["hp"]=new JArray(0,7017);groups["vitals"]["mp"]=new JArray(0,4634);
            groups["vitals"]["shield"]=new JArray(0,8355);groups["vitals"]["poise"]=0;
            groups["vitals"]["poiseDetail"]["phase"]="down";
            groups["vitals"]["level"]=99;
        }
        groups["combat"]["mode"] = "长枪副武器"; groups["combat"]["ammo"] = new JArray("75", "4", "1", "6");
        var skills = XDocument.Load(Path.Combine(root, "data", "skills", "skills.xml")).Descendants("Skill")
            .Where(s => !string.IsNullOrWhiteSpace((string)s.Element("Name"))).Take(12).Select(s => (string)s.Element("Name")).ToArray();
        for (var i = 0; i < 12; i++)
        {
            groups["loadout"]["skills"][i]["skillKey"] = skills[i]; groups["loadout"]["skills"][i]["iconKey"] = skills[i];
            groups["loadout"]["skills"][i]["keyLabel"]=new[]{"Spacebar","U","I","O","P","L","H","G","C","B","N","M"}[i];
            groups["cooldowns"][i + 1] = new JArray(i % 3 == 0 ? 0 : 1, 4 + i, 30);
        }
        var drugs = new[] { "普通hp药剂", "普通mp药剂", "普通hp药剂", "普通mp药剂" };
        for (var i = 0; i < 4; i++) { groups["loadout"]["drugs"][i]["name"] = drugs[i]; groups["loadout"]["drugs"][i]["icon"] = drugs[i]; }
        groups["cooldowns"][0] = new JArray(0, 10, 30);
        groups["cooldowns"][17] = new JArray(0, 10, 30);
        groups["cooldowns"][1]=new JArray(0,60,360);
        groups["cooldowns"][13]=new JArray(0,0,240);
        groups["buffs"]=new JArray(
            new JObject{["id"]="1:example-a",["timed"]=true,["total"]=300,["remaining"]=270},
            new JObject{["id"]="1:example-b",["timed"]=true,["total"]=300,["remaining"]=150},
            new JObject{["id"]="1:example-c",["timed"]=true,["total"]=300,["remaining"]=60},
            new JObject{["id"]="1:example-d",["timed"]=false,["total"]=0,["remaining"]=0});
        controller.TakeUiData("pi:"+PlayerHudStateTests.Encode(data));
        Assert.NotNull(controller.State.Snapshot);
        using var bottom = new PlayerHudBottomWidget(anchor, controller, Path.Combine(root, "launcher", "web", "icons"));
        using var buffs = new PlayerHudBuffWidget(anchor, controller); buffs.Tick(400);
        using var canvas = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        var origin = anchor.PointToScreen(Point.Empty);
        using (var graphics = Graphics.FromImage(canvas))
        {
            graphics.Clear(Color.Transparent);
            bottom.Paint(graphics, 1, origin);
            var assets = PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
            var plan = PlayerInfoRasterPlanner.Create(assets, new Rectangle(0, 0, width, height), 1);
            using var batch = new PlayerInfoSvgRasterizer().Bake(plan, CancellationToken.None);
            var animation = new PlayerInfoAnimationModel(); animation.ApplyProduction(controller.State.Snapshot.Vitals);
            using var resourceWidget = new PlayerInfoWidget(assets, animation) { LiveVitals = controller.State.Snapshot.Vitals };
            using var resources = new Bitmap(plan.TightPhysicalBounds.Width, plan.TightPhysicalBounds.Height, PixelFormat.Format32bppPArgb);
            resourceWidget.Paint(resources, batch, plan); graphics.DrawImageUnscaled(resources, plan.TightPhysicalBounds.Location);
            buffs.Paint(graphics, 1, origin);
        }
        Assert.Equal(0, canvas.GetPixel(width / 2, height / 2).A);
        var scale = height / 576f;
        // The old capture on black hid both the missing chassis and rectangle leaks.
        foreach (var x in new[] { 180, 285, 482, 588, 1000 })
            Assert.Equal(255, canvas.GetPixel((int)(x * scale), (int)(566 * scale)).A);
        foreach (var point in new[] { new Point(5, 472), new Point(77, 474), new Point(120, 485), new Point(250, 489) })
            Assert.Equal(0, canvas.GetPixel((int)(point.X * scale), (int)(point.Y * scale)).A);
        if(shield)Assert.True(canvas.GetPixel((int)(250*scale),(int)(500*scale)).A>230);
        else Assert.Equal(0,canvas.GetPixel((int)(250*scale),(int)(500*scale)).A);
        // Maximums and percentages are independently visible without opening details.
        foreach (var region in new[] { new RectangleF(20, 522, 35, 10), new RectangleF(180, 508, 54, 13),
            new RectangleF(18, 496, 40, 16), new RectangleF(90, 524, 29, 11) })
        {
            var ink = 0;
            for (var y = (int)(region.Top * scale); y < (int)(region.Bottom * scale); y++)
            for (var x = (int)(region.Left * scale); x < (int)(region.Right * scale); x++)
            {
                var pixel = canvas.GetPixel(x, y);
                if (pixel.G > 125 && pixel.B > 125) ink++;
            }
            Assert.True(ink > 12 * scale * scale, "Resource reading is missing: " + region);
        }
        Assert.False(bottom.TryHitTest(new Point(origin.X + width / 2, origin.Y + height / 2)));
        Assert.True(bottom.ScreenBounds.Height <= Math.Ceiling(height * 74d / 576d));
        if (longReadings && width==1024)
        {
            var ink=0;
            for(var y=563;y<565;y++) for(var x=90;x<278;x++)
            {
                var p=canvas.GetPixel(x,y);
                if(p.R>150&&p.G>150&&p.B>150)ink++;
            }
            Assert.True(ink>12,"Large XP readings must use the freed row at minimum resolution");
        }
        if (Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_CAPTURE") == "1")
        {
            var output = Path.Combine(root, "tmp", "player-info-full"); Directory.CreateDirectory(output);
            var suffix = (depleted ? "empty-" : longReadings ? "long-" : overflow ? "overflow-" : !shield ? "no-shield-" : "") + width;
            canvas.Save(Path.Combine(output, "hud-preview-" + suffix + ".png"), ImageFormat.Png);
            using var bright = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(bright))
            {
                g.Clear(Color.FromArgb(175, 200, 220));
                using var tile = new SolidBrush(Color.FromArgb(222, 228, 234));
                for (var y = 0; y < height; y += 32) for (var x = 0; x < width; x += 32)
                    if ((x / 32 + y / 32) % 2 == 0) g.FillRectangle(tile, x, y, 32, 32);
                g.DrawImageUnscaled(canvas, 0, 0);
            }
            bright.Save(Path.Combine(output, "hud-bright-" + suffix + ".png"), ImageFormat.Png);
            if(longReadings)
            {
                var buffCrop=Rectangle.FromLTRB(0,0,(int)Math.Ceiling(130*scale),(int)Math.Ceiling(36*scale));
                using var buffPreview=bright.Clone(buffCrop,PixelFormat.Format32bppPArgb);
                buffPreview.Save(Path.Combine(output,"hud-buffs-"+width+".png"),ImageFormat.Png);
                using var tooltip=new PlayerHudResourceTooltip(anchor,controller);
                controller.ShowTooltip(new PlayerHudTarget("resources",0,"",data["epoch"].Value<long>(),0,0,
                    PlayerHudBottomWidget.DetailsRect,controller.Generation));
                using var detailsPreview=(Bitmap)bright.Clone();
                using(var g=Graphics.FromImage(detailsPreview))tooltip.Widget.Paint(g,1,origin);
                var tip=tooltip.Widget.ScreenBounds;tip.Offset(-origin.X,-origin.Y);
                Assert.True(new Rectangle(0,0,width,height).Contains(tip));
                Assert.False(tooltip.Widget.Scrollable);
                using var detailCrop=detailsPreview.Clone(tip,PixelFormat.Format32bppPArgb);
                detailCrop.Save(Path.Combine(output,"hud-resource-details-"+width+".png"),ImageFormat.Png);
                detailsPreview.Save(Path.Combine(output,"hud-with-details-"+width+".png"),ImageFormat.Png);
                controller.HideTooltip();
            }
            // Focused preview uses the same production composition at native output size.
            using var strip = new Bitmap(width, (int)Math.Ceiling(108 * scale), PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(strip)) g.DrawImageUnscaled(bright, 0, strip.Height - height);
            strip.Save(Path.Combine(output, "hud-resource-strip-" + suffix + ".png"), ImageFormat.Png);
            using var resourcePreview = new Bitmap((int)Math.Ceiling(300 * scale), strip.Height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(resourcePreview)) g.DrawImageUnscaled(strip, 0, 0);
            resourcePreview.Save(Path.Combine(output, "hud-resources-" + suffix + ".png"), ImageFormat.Png);
            if (longReadings)
            {
                var crop=Rectangle.FromLTRB((int)(592*scale),(int)(508*scale),width,(int)Math.Ceiling(533*scale));
                using var header=bright.Clone(crop,PixelFormat.Format32bppPArgb);
                header.Save(Path.Combine(output,"hud-skill-header-"+width+".png"),ImageFormat.Png);
                var skillCrop=Rectangle.FromLTRB(crop.Left,crop.Top,width,height);
                using var skillStrip=bright.Clone(skillCrop,PixelFormat.Format32bppPArgb);
                skillStrip.Save(Path.Combine(output,"hud-skill-strip-"+width+".png"),ImageFormat.Png);
            }
        }
    }
}
