using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian.Hud.Guidance;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class NativeGuidanceVisualTests
    {
        private static readonly string[] SceneIds = { "combat", "run", "pickup", "crate", "crate-safe" };
        private static Dictionary<string,string> Keys(string interact="E") => new() {
            ["left"]="A",["right"]="D",["up"]="W",["down"]="S",["attack"]="J",["jump"]="K",["interact"]=interact };
        private static string ProjectRoot()
        {
            for(var directory=new DirectoryInfo(AppContext.BaseDirectory);directory!=null;directory=directory.Parent)
                if(File.Exists(Path.Combine(directory.FullName,"launcher","data","guidance-catalog.json")))return directory.FullName;
            throw new DirectoryNotFoundException("Guidance author source missing");
        }
        private static GuidanceCatalog Catalog() => GuidanceCatalog.FromJson(File.ReadAllText(Path.Combine(ProjectRoot(),"launcher","data","guidance-catalog.json")));
        private static byte[] Pixels(Bitmap image)
        {
            var data=image.LockBits(new Rectangle(Point.Empty,image.Size),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
            try {var bytes=new byte[data.Stride*image.Height];Marshal.Copy(data.Scan0,bytes,0,bytes.Length);return bytes;}
            finally {image.UnlockBits(data);}
        }
        [Theory][InlineData(1024,576)][InlineData(1600,900)][InlineData(2560,1440)]
        public void SceneDiagramsKeepTransparentTopAndOriginalScenePlacement(int width,int height)
        {
            RuntimeFontCatalog.ResetForTest();RuntimeFontCatalog.ConfigureForTest(ProjectRoot());
            try
            {
                using var anchor=new Panel {Size=new Size(width,height)};
                using var widget=new NativeGuidanceWidget(anchor,Catalog());
                foreach(string id in SceneIds)
                {
                    widget.Show("ng:1","scene",1,id,.75f,Keys());
                    using var image=new Bitmap(width,height,PixelFormat.Format32bppArgb);
                    using var g=Graphics.FromImage(image);widget.Paint(g,1,anchor.PointToScreen(Point.Empty));
                    byte[] bytes=Pixels(image);int pixels=0,topPixels=0;
                    for(int y=0;y<height;y++)for(int x=0;x<width;x++)
                    {
                        int alpha=bytes[(y*width+x)*4+3];
                        if(alpha!=0){pixels++;if(y<height*340/576)topPixels++;}
                    }
                    Assert.Equal(0,topPixels);
                    Assert.InRange(pixels,100,width*height/12);
                    Assert.False(widget.TryHitTest(widget.ScreenBounds.Location));
                    string output=Environment.GetEnvironmentVariable("CF7_GUIDANCE_VISUAL_OUTPUT");
                    if(width==1024&&!string.IsNullOrEmpty(output))
                    {
                        Directory.CreateDirectory(output);
                        using var preview=new Bitmap(width,height);using var canvas=Graphics.FromImage(preview);
                        canvas.Clear(Color.FromArgb(45,48,51));widget.Paint(canvas,1,anchor.PointToScreen(Point.Empty));
                        preview.Save(Path.Combine(output,id+".png"),ImageFormat.Png);
                    }
                }
            }
            finally {RuntimeFontCatalog.ResetForTest();}
        }
        [Fact] public void NativeRenderedKeyLabelChangesAfterRemapping()
        {
            using var anchor=new Panel {Size=new Size(1024,576)};using var widget=new NativeGuidanceWidget(anchor,Catalog());
            using var before=new Bitmap(1024,576);using var after=new Bitmap(1024,576);
            widget.Show("ng:1","scene",1,"pickup",1,Keys());using(var g=Graphics.FromImage(before))widget.Paint(g,1,anchor.PointToScreen(Point.Empty));
            widget.Show("ng:1","scene",2,"pickup",1,Keys("T"));using(var g=Graphics.FromImage(after))widget.Paint(g,1,anchor.PointToScreen(Point.Empty));
            Assert.False(Pixels(before).SequenceEqual(Pixels(after)));
        }
        [Theory]
        [InlineData("x","-1")][InlineData("x","\"300\"")][InlineData("width","0")]
        [InlineData("height","999999999999999999999")][InlineData("fontSize","9")]
        [InlineData("type","\"script\"")][InlineData("extra","true")]
        public void VisualCatalogRejectsUnsafeOrUnreadableElements(string field,string value)
        {
            var content=JObject.Parse(File.ReadAllText(Path.Combine(ProjectRoot(),"launcher","data","guidance-catalog.json")));
            var node=content["guides"].First(g=>g.Value<string>("id")=="combat")["pages"][0]["visual"][0];node[field]=JToken.Parse(value);
            Assert.Throws<FormatException>(()=>GuidanceCatalog.FromJson(content.ToString()));
        }
        [Fact] public void HelpCatalogHasTwoAutomaticTutorialsAndFiveAuthoredSceneDiagrams()
        {
            var catalog=Catalog();foreach(string id in new[]{"start","map"}){Assert.True(catalog.TryGet(id,out var guide));Assert.True(guide.WebHelp);}
            foreach(string id in SceneIds){Assert.True(catalog.TryGet(id,out var guide));Assert.False(guide.WebHelp);Assert.NotEmpty(guide.Pages[0].Visual);}
        }
        [Fact] public void AuthoredLongKeyNamesFitAtReadableSizeAndRenderArrowBindings()
        {
            RuntimeFontCatalog.ResetForTest();RuntimeFontCatalog.ConfigureForTest(ProjectRoot());
            try
            {
                var catalog=Catalog();using var image=new Bitmap(1024,576);using var g=Graphics.FromImage(image);
                using var bold=CF7Launcher.Guardian.Hud.NativeHudFonts.CreateRoleFont("native.combat.label",10,FontStyle.Bold,GraphicsUnit.Pixel);
                using var regular=CF7Launcher.Guardian.Hud.NativeHudFonts.CreateRoleFont("native.combat.label",10,FontStyle.Regular,GraphicsUnit.Pixel);
                string producer=File.ReadAllText(Path.Combine(ProjectRoot(),"scripts","类定义","org","flashNight","arki","key","KeyManager.as"));
                var names=Regex.Matches(producer,"keyMap\\[\\d+\\] = \"([^\"]+)\"").Select(m=>m.Groups[1].Value).Distinct().ToArray();
                Assert.NotEmpty(names);
                foreach(string name in names)
                {
                    string label=catalog.KeyLabels.TryGetValue(name,out string mapped)?mapped:name;
                    Assert.True(Math.Min(g.MeasureString(label,bold).Width,g.MeasureString(label,regular).Width)<=31,"Key label too wide: "+name);
                }
                Assert.Equal("↑",catalog.KeyLabels["上方向键"]);Assert.Equal("↓",catalog.KeyLabels["下方向键"]);
                using var anchor=new Panel {Size=new Size(1024,576)};using var widget=new NativeGuidanceWidget(anchor,catalog);
                var keys=Keys();keys["left"]="左方向键";keys["right"]="右方向键";keys["up"]="上方向键";keys["down"]="下方向键";
                widget.Show("ng:1","scene",1,"combat",.75f,keys);widget.Paint(g,1,anchor.PointToScreen(Point.Empty));
                Assert.True(Pixels(image).Any(b=>b!=0));
                string output=Environment.GetEnvironmentVariable("CF7_GUIDANCE_VISUAL_OUTPUT");
                if(!string.IsNullOrEmpty(output))
                {
                    Directory.CreateDirectory(output);using var preview=new Bitmap(1024,576);using var canvas=Graphics.FromImage(preview);
                    canvas.Clear(Color.FromArgb(45,48,51));widget.Paint(canvas,1,anchor.PointToScreen(Point.Empty));
                    preview.Save(Path.Combine(output,"combat-arrow-keys.png"),ImageFormat.Png);
                }
            }
            finally {RuntimeFontCatalog.ResetForTest();}
        }
    }
}
