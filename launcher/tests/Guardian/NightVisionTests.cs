using System;
using System.IO;
using System.Xml.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian {
    public class NightVisionTests {
        private static string Xml => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..","..","data","environment","color_engine_preset.xml"));
        [Fact] public void AuthoredRolesKeepTargetsAndEnvironmentAsIndependentAssists() {
            var p=NightVisionProfile.Load(Xml);
            Assert.Equal(7,p.Count);
            Assert.True(p["夜视仪"].Native[1]>0);Assert.Equal(0,p["夜视仪"].UnitStrength);
            Assert.Equal(0,p["浅红夜视仪"].Native[1]);Assert.True(p["浅红夜视仪"].UnitStrength>.4);
            Assert.True(p["浅绿夜视仪"].Native[1]>0);Assert.Equal(0,p["浅绿夜视仪"].UnitStrength);
            Assert.Equal(0,p["浅蓝夜视仪"].Native[1]);Assert.True(p["浅蓝夜视仪"].UnitStrength>.4);
            Assert.Equal(0,p["高级夜视仪"].Native[1]);Assert.Equal(0,p["高级夜视仪"].UnitStrength);
            Assert.True(p["高级夜视仪"].ShadowLift>0);Assert.Equal(0,p["剑圣视觉四阶"].ShadowLift);
            Assert.Equal(0,p["剑圣视觉四阶"].Native[1]);Assert.Equal(0,p["剑圣视觉四阶"].UnitStrength);
            Assert.Equal(1,p["剑圣视觉四阶"].Native[6]);
            Assert.True(p["剑圣视觉四阶"].Native[11]>p["夜视仪"].Native[11]);
            Assert.True(p["剑圣视觉四阶"].Native[13]<p["夜视仪"].Native[13]);
        }
        [Theory] [InlineData("浅红夜视仪")] [InlineData("浅蓝夜视仪")]
        public void WhiteHotPresetsHaveNeutralPaletteAndSemanticUnitStyle(string mode) {
            var doc=XDocument.Load(Xml);
            foreach(var set in doc.Root.Elements("PresetSet")) if((string)set.Element("name")==mode)
                Assert.Equal("whitehot",(string)set.Element("VisionEffects").Element("UnitStyle"));
            string resolved;
            var lut=WorldLutBaker.BakeFromXml(Xml,mode,0,1,out resolved);
            Assert.Equal(mode,resolved);
            for(int i=0;i<lut.Length;i+=4){Assert.Equal(lut[i],lut[i+1]);Assert.Equal(lut[i+1],lut[i+2]);}
        }
        [Fact] public void NaturalAdvancedVisionRestoresColorAndDarkDetailWithoutEnvironmentEdges() {
            var doc=XDocument.Load(Xml);XElement selected=null;
            foreach(var set in doc.Root.Elements("PresetSet"))if((string)set.Element("name")=="高级夜视仪")selected=set;
            var effects=selected.Element("VisionEffects");
            Assert.Equal("natural",(string)effects.Element("UnitStyle"));
            Assert.Equal(0,(float)effects.Element("UnitStrength"));
            Assert.InRange((float)effects.Element("UnitOutlineStrength"),.1f,.25f);
            var profile=NightVisionProfile.Load(Xml)["高级夜视仪"];
            Assert.Equal(0,profile.Native[1]);Assert.InRange(profile.Native[3],0,.25f);
            Assert.InRange(profile.Native[15],.02f,.08f);
            foreach(var p in NightVisionProfile.Load(Xml).Values)if(p.Name!="高级夜视仪")Assert.Equal(0,p.Native[15]);
            string resolved;var lut=WorldLutBaker.BakeFromXml(Xml,"高级夜视仪",0,1,out resolved);
            int gray=((4*32+4)*32+4)*4;
            Assert.True(lut[gray+1]>4/31.0*255*1.5,"dark clothing receives useful exposure lift");
            int colored=((5*32+9)*32+15)*4;
            Assert.True(lut[colored]>lut[colored+1]+20 && lut[colored+1]>lut[colored+2]+20,"original material hue stays distinct");
            Assert.Equal(0,lut[0]);Assert.Equal(0,lut[1]);Assert.Equal(0,lut[2]);
            var identity=WorldLutBaker.BakeMatrix(WorldColorMatrix.Identity(),1);
            Assert.Equal(identity,WorldLutBaker.BakeFromXml(Xml,"高级夜视仪",7,1,out resolved));
            Assert.Equal(identity,WorldLutBaker.BakeFromXml(Xml,"剑圣视觉四阶",0,1,out resolved));
        }
        [Fact] public void NaturalCurveChangesInvalidateCameraLutEvenWithTheSameMatrix() {
            var m=WorldColorMatrix.Identity();
            Assert.True(WorldCompositorController.NightLutChanged(m,.85,m,0));
            Assert.True(WorldCompositorController.NightLutChanged(m,0,m,.85));
            Assert.False(WorldCompositorController.NightLutChanged(m,.85,(double[])m.Clone(),.85));
            Assert.True(WorldCompositorController.NightLutChanged(m,0,null,double.NaN));
        }
        [Theory] [InlineData("夜视仪")] [InlineData("浅绿夜视仪")]
        public void OutlinePresetsKeepDarkMaterialVisibleWithoutRestoringGrainOrAddingHeat(string mode) {
            var document=XDocument.Load(Xml);
            XElement selected=null;
            foreach(var set in document.Root.Elements("PresetSet"))if((string)set.Element("name")==mode)selected=set;
            var node=selected.Element("VisionEffects");
            var profile=NightVisionProfile.Load(Xml)[mode];
            Assert.Equal(0,profile.UnitStrength);
            Assert.InRange(profile.Native[1],0,.23f);
            Assert.InRange(profile.Native[3],.9f,1);
            Assert.True((float)node.Element("UnitOutlineWidth")>profile.Native[2]);
            Assert.True((float)node.Element("UnitOutlineStrength")>profile.Native[1]);
            string resolved;
            var lut=WorldLutBaker.BakeFromXml(Xml,mode,0,1,out resolved);
            int darkGray=((2*32+2)*32+2)*4;
            // Green output of dark neutral clothing must survive the underlay
            // multiplier. Pixel zero is no longer crushed into near black.
            Assert.True(lut[darkGray+1]*profile.Native[6]>=22);
            Assert.True(lut[1]*profile.Native[6]>=8);
        }
        [Theory] [InlineData("EdgeStrength","NaN")] [InlineData("GlareThreshold","0")]
        [InlineData("GainFloor","2")] [InlineData("UnitRed","-1")] [InlineData("Version","2")]
        [InlineData("ShadowLift","NaN")] [InlineData("ShadowLift","-0.1")] [InlineData("ShadowLift","2.1")]
        [InlineData("ScanStrength","NaN")] [InlineData("ScanStrength","-0.001")] [InlineData("ScanStrength","0.081")]
        public void ProfileRejectsMalformedVisualData(string field,string value) {
            var doc=XDocument.Load(Xml);
            foreach(var set in doc.Root.Elements("PresetSet")) if((string)set.Element("name")=="夜视仪")set.Element("VisionEffects").SetElementValue(field,value);
            string path=Path.GetTempFileName();
            try {doc.Save(path);Assert.Throws<FormatException>(()=>NightVisionProfile.Load(path));}
            finally {File.Delete(path);}
        }
        [Fact] public void ModeNamesAloneCannotEnableNightVisionOnLegacyOrUnreadyScenes() {
            var p=NightVisionProfile.Load(Xml);
            Assert.Same(NightVisionProfile.None,WorldCompositorController.ResolveNightVision(p,"夜视仪",false,true));
            Assert.Same(NightVisionProfile.None,WorldCompositorController.ResolveNightVision(p,"夜视仪",true,false));
            Assert.Same(NightVisionProfile.None,WorldCompositorController.ResolveNightVision(p,"光照",true,true));
            Assert.Same(NightVisionProfile.None,WorldCompositorController.ResolveNightVision(p,"unknown",true,true));
            Assert.Same(p["浅红夜视仪"],WorldCompositorController.ResolveNightVision(p,"浅红夜视仪",true,true));
        }
        private static JObject Wire() => JObject.Parse("{version:1,sequence:1,scene:1,ready:true,paused:false,immediate:true,sourceNeutral:true,mode:'夜视仪',light:0,parameters:[.15,1,.15,1,0,50,0,0]}");
        [Fact] public void LightingWireRequiresPairedBooleanActivationButAcceptsOldSources() {
            var w=Wire();Assert.True(WorldLightingFrame.TryParse(w,out var old));Assert.False(old.NightVisionRequested);
            w["visionVersion"]=1;Assert.False(WorldLightingFrame.TryParse(w,out _));
            w["visionActive"]=true;Assert.True(WorldLightingFrame.TryParse(w,out var current));Assert.True(current.NightVisionRequested);
            w["visionActive"]=1;Assert.False(WorldLightingFrame.TryParse(w,out _));
            w["visionActive"]=false;w["visionVersion"]=2;Assert.False(WorldLightingFrame.TryParse(w,out _));
        }
        [Fact] public void NewSceneActivationWaitsForItsOwnCaptureAndStalePacketsCannotReenableIt() {
            var t=new WorldLightingTransition();var w=Wire();w["visionVersion"]=1;w["visionActive"]=true;
            Assert.True(WorldLightingFrame.TryParse(w,out var f));Assert.True(t.Adopt(f,0));Assert.True(t.NightVisionRequested);
            w["sequence"]=2;w["scene"]=2;w["ready"]=false;w["visionActive"]=false;
            WorldLightingFrame.TryParse(w,out f);t.Adopt(f,100);
            w["sequence"]=3;w["ready"]=true;WorldLightingFrame.TryParse(w,out f);t.Adopt(f,200);
            Assert.True(t.WaitingForCapture);Assert.True(t.NightVisionRequested);
            Assert.False(t.ConfirmCapturedFrame(199,210));Assert.True(t.ConfirmCapturedFrame(200,210));Assert.False(t.NightVisionRequested);
            w["sequence"]=1;w["scene"]=1;w["visionActive"]=true;WorldLightingFrame.TryParse(w,out f);
            Assert.False(t.Adopt(f,300));Assert.False(t.NightVisionRequested);
        }
        [Fact] public void TransitionMatrixBakesExactlyLikeXmlAndTrueVisionStaysIdentity() {
            var tables=WorldLutBaker.LoadPresetTables(Xml);
            var a=WorldLutBaker.Interpolate(tables["夜视仪"],2.5);
            Assert.Equal(WorldLutBaker.Bake(a,1),WorldLutBaker.BakeMatrix(WorldColorMatrix.Generate(a),1));
            var top=WorldLutBaker.Interpolate(tables["剑圣视觉四阶"],0);
            Assert.Equal(WorldColorMatrix.Identity(),WorldColorMatrix.Generate(top));
            Assert.Throws<ArgumentException>(()=>WorldLutBaker.BakeMatrix(new double[8],1));
        }
    }
}
