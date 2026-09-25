using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;
namespace CF7Launcher.Tests.Guardian {
    public class WorldCompositorTests {
        [Fact] public void CaptureFrameRejectsUnknownExtentRatherThanGuessingAnOrigin()
        {
            var visible=new Rectangle(0,0,1920,1020);
            var outer=new Rectangle(-9,-9,1938,1038);
            Assert.False(WorldCompositorController.TryResolveCaptureFrame(visible,outer,new Size(1922,1030),out _));
            Assert.False(WorldCompositorController.TryResolveCaptureFrame(visible,outer,new Size(1602,939),out _));
            Assert.False(WorldCompositorController.TryResolveCaptureFrame(visible,outer,Size.Empty,out _));
        }
        [Fact] public void NormalAndBorderlessCaptureFramesRetainTheirMeasuredOrigin()
        {
            var frame=new Rectangle(139,86,1602,939);var window=new Rectangle(131,86,1618,947);
            Assert.True(WorldCompositorController.TryResolveCaptureFrame(frame,window,frame.Size,out var resolved));
            Assert.Equal(frame,resolved);
            Assert.True(WorldCompositorController.TryResolveCaptureFrame(frame,window,window.Size,out resolved));
            Assert.Equal(window,resolved);
        }
        [Fact] public void CropRejectsOutsideAndSupportsNegativeMonitorOrigin() {
            var root=new Rectangle(-1500,100,1100,750);
            Assert.Equal(new Rectangle(8,40,1084,610),WorldCompositorController.CalculateCrop(new Rectangle(-1492,140,1084,610),root));
            Assert.Throws<ArgumentException>(()=>WorldCompositorController.CalculateCrop(new Rectangle(-1510,140,1084,610),root));
        }
        // 缺陷 X（2026-09-24）：合成器未呈现或裁剪未建立时整窗回读会含标题栏——抓帧准入必须拒绝。
        [Fact] public void GrabAdmissionRequiresActiveCaptureAndEstablishedWorldViewport() {
            Assert.False(WorldCompositorController.CanGrabWorldViewport(false,new Rectangle(0,0,2560,1440)));
            Assert.False(WorldCompositorController.CanGrabWorldViewport(true,Rectangle.Empty));
            Assert.False(WorldCompositorController.CanGrabWorldViewport(true,new Rectangle(8,40,0,610)));
            Assert.True(WorldCompositorController.CanGrabWorldViewport(true,new Rectangle(8,40,1084,610)));
        }
        [Fact] public void WindowMoveOnePixelCaptureDriftDoesNotFreezeTheScene() {
            // Exact measured geometry from the 2026-09-25 weather candidate run.
            var captured=new Rectangle(138,23,1602,939);
            var flash=new Rectangle(139,63,1600,900);
            Assert.True(WorldCompositorController.TryCalculateCrop(flash,captured,out var crop));
            Assert.Equal(new Rectangle(1,40,1600,899),crop);
            Assert.False(WorldCompositorController.TryCalculateCrop(
                new Rectangle(139,66,1600,900),captured,out _));
        }
        [Fact] public void LegacyNeutralMatrixIsIdentity() {
            Assert.Equal(WorldColorMatrix.Identity(),WorldColorMatrix.Generate(new double[]{1,1,1,1,0,0,0,0}));
        }
        [Fact] public void FullDesaturationUsesCrossChannelLuminance() {
            var m=WorldColorMatrix.Generate(new double[]{1,1,1,1,0,0,-100,0});
            for(int row=0;row<3;row++) { Assert.Equal(.2126,m[row*5],5); Assert.Equal(.7152,m[row*5+1],5); Assert.Equal(.0722,m[row*5+2],5); }
        }
        [Fact] public void LegacyCompositionOrderAndByteOffsetsArePreserved() {
            var m=WorldColorMatrix.Generate(new double[]{.5,1,1,1,20,50,0,0});
            Assert.Equal(.75,m[0],5); Assert.Equal(-22,m[4],5); Assert.Equal(-44,m[9],5);
            var shader=new WorldColorMatrix().ShaderSettings(m);
            Assert.Equal(-22/255f,shader[12],5); Assert.Equal(1,shader[15]);
        }
        private static WorldLightingFrame Frame(long sequence, long scene, bool ready, double brightness=0) =>
            new WorldLightingFrame { Sequence=sequence, Scene=scene, Ready=ready, Mode="光照", Light=brightness<0 ? 2 : 7,
                Parameters=new double[]{1,1,1,1,brightness,0,0,0} };
        [Fact] public void LoadingSceneKeepsLastGradeDespiteNeutralProvisionalPayload() {
            var transition=new WorldLightingTransition();
            transition.Adopt(Frame(1,1,true,-40),0);
            var old=transition.Sample(1);
            transition.Adopt(Frame(2,2,false),100);
            transition.Adopt(Frame(3,2,false),500);
            Assert.True(transition.Pending);
            Assert.True(transition.ShouldPresent(true));
            Assert.False(transition.ShouldPresent(false));
            Assert.Equal(old,transition.Sample(600));
            Assert.Equal(2,transition.LastReadyLight);
            Assert.False(transition.Adopt(Frame(4,1,true),650));
            Assert.Equal(old,transition.Sample(700));
        }
        [Fact] public void NewReadySceneAdaptsFromHeldGradeWithoutANeutralFrame() {
            var transition=new WorldLightingTransition();
            transition.Adopt(Frame(1,1,true,-40),0);
            transition.Adopt(Frame(2,2,false),100);
            var next=Frame(3,2,true,-20); next.Immediate=true; next.Paused=true;
            transition.Adopt(next,500);
            Assert.True(transition.WaitingForCapture);
            Assert.False(transition.ConfirmCapturedFrame(499,700));
            Assert.Equal(-40,transition.Sample(700)[4],5);
            Assert.True(transition.ConfirmCapturedFrame(500,900));
            Assert.InRange(transition.BlendDurationMs,80,180);
            Assert.Equal(-40,transition.Sample(900)[4],5);
            Assert.Equal(-30,transition.Sample(900+transition.BlendDurationMs/2)[4],5);
            Assert.Equal(-20,transition.Sample(900+transition.BlendDurationMs)[4],5);
            Assert.False(transition.Pending);
        }
        [Fact] public void OrdinaryImmediateModeChangesStillApplyWithoutSceneBuffer() {
            var transition=new WorldLightingTransition();
            transition.Adopt(Frame(1,1,true,-40),0);
            var next=Frame(2,1,true,20); next.Mode="夜视仪"; next.Immediate=true;
            transition.Adopt(next,100);
            Assert.Equal(0,transition.BlendDurationMs);
            Assert.Equal(20,transition.Sample(100)[4],5);
        }
        [Fact] public void LongSceneWaitIsDetectableAndHeartbeatsDoNotResetAge() {
            var transition=new WorldLightingTransition();
            transition.Adopt(Frame(1,1,true,-40),0);
            transition.Adopt(Frame(2,2,false),100);
            transition.Adopt(Frame(3,2,false),9000);
            Assert.False(transition.IsOverdue(10100));
            Assert.True(transition.IsOverdue(10101));
            transition.Adopt(Frame(4,2,true,-20),10200);
            Assert.True(transition.ConfirmCapturedFrame(10200,10250));
            Assert.False(transition.IsOverdue(10300));
            Assert.InRange(transition.BlendDurationMs,80,180);
        }
        [Fact] public void InitialUnreadyStateIsNotTreatedAsAUsableGrade() {
            var transition=new WorldLightingTransition();
            transition.Adopt(Frame(1,1,false),0);
            Assert.False(transition.HasValidState);
            transition.Adopt(Frame(2,1,true,-30),500);
            Assert.True(transition.HasValidState);
            Assert.Equal(0,transition.BlendDurationMs);
            Assert.Equal(-30,transition.Sample(500)[4],5);
        }
        [Fact] public void ReadyHeartbeatsDoNotStarveCaptureFenceAndUseLatestTarget() {
            var transition=new WorldLightingTransition();
            transition.Adopt(Frame(1,1,true,-40),0);
            transition.Adopt(Frame(2,2,true,-20),500);
            transition.Adopt(Frame(3,2,true,-25),950);
            Assert.True(transition.Pending);
            Assert.False(transition.ConfirmCapturedFrame(double.NaN,999));
            Assert.True(transition.ConfirmCapturedFrame(600,1000));
            Assert.Equal(-25,transition.Sample(1000+transition.BlendDurationMs)[4],5);
        }
        [Fact] public void NewerSceneInvalidatesQueuedReadyTargetDuringCaptureStall() {
            var transition=new WorldLightingTransition();
            transition.Adopt(Frame(1,1,true,-40),0);
            transition.Adopt(Frame(2,2,true,-20),500);
            transition.Adopt(Frame(3,3,false),700);
            Assert.False(transition.ConfirmCapturedFrame(800,800));
            Assert.Equal(-40,transition.Sample(800)[4],5);
            Assert.False(transition.Adopt(Frame(4,2,true),850));
            transition.Adopt(Frame(5,3,true,-10),900);
            Assert.False(transition.ConfirmCapturedFrame(899,1000));
            Assert.True(transition.ConfirmCapturedFrame(901,1100));
            Assert.Equal(3,transition.ReadyScene);
            Assert.Equal(-10,transition.Sample(1100+transition.BlendDurationMs)[4],5);
        }
        private static JObject Payload() => JObject.Parse("{\"version\":1,\"sequence\":1,\"scene\":1,\"ready\":true,\"paused\":false,\"immediate\":true,\"sourceNeutral\":true,\"mode\":\"光照\",\"light\":3.2,\"parameters\":[1,1,1,1,0,0,0,0]}");
        [Fact] public void SnapshotRequiresNeutralSourceAndFiniteNumericParameters() {
            var p=Payload(); Assert.True(WorldLightingFrame.TryParse(p,out _));
            p["sourceNeutral"]=false; Assert.False(WorldLightingFrame.TryParse(p,out _));
            p=Payload(); p["parameters"][0]=double.NaN; Assert.False(WorldLightingFrame.TryParse(p,out _));
            p=Payload(); p["parameters"][0]="1"; Assert.False(WorldLightingFrame.TryParse(p,out _));
        }
        [Fact] public void WeatherRequiresExplicitNativeOwnershipAndBoundedVisualState() {
            var p=Payload();
            Assert.True(WorldLightingFrame.TryParse(p,out var legacy));
            Assert.False(legacy.WeatherNative);
            p["weatherNative"]=true; p["weatherType"]="snow";
            p["weatherIntensity"]=0.7; p["weatherQuality"]=1;
            Assert.True(WorldLightingFrame.TryParse(p,out var weather));
            Assert.True(weather.WeatherNative); Assert.Equal(2,weather.WeatherType);
            Assert.Equal(0.7f,weather.WeatherIntensity); Assert.Equal(1,weather.WeatherQuality);
            p["weatherGroundMin"]=220; p["weatherGroundMax"]=500;
            Assert.True(WorldLightingFrame.TryParse(p,out var grounded));
            Assert.Equal(220f,grounded.WeatherGroundMin); Assert.Equal(500f,grounded.WeatherGroundMax);
            p["weatherGroundMax"]=210; Assert.False(WorldLightingFrame.TryParse(p,out _));
            p["weatherGroundMax"]=500;
            p["weatherQuality"]=1.0;
            Assert.True(WorldLightingFrame.TryParse(p,out var numericFloat));
            Assert.Equal(1,numericFloat.WeatherQuality);
            p["weatherIntensity"]=-0.1; Assert.False(WorldLightingFrame.TryParse(p,out _));
            p["weatherIntensity"]=0.7; p["weatherType"]="unknown";
            Assert.False(WorldLightingFrame.TryParse(p,out _));
            p["weatherType"]="snow"; p["weatherQuality"]=1.5;
            Assert.False(WorldLightingFrame.TryParse(p,out _));
            p["weatherQuality"]="high"; Assert.False(WorldLightingFrame.TryParse(p,out _));
            p["weatherQuality"]=1; p["weatherNative"]="true";
            Assert.False(WorldLightingFrame.TryParse(p,out _));
        }
        [Theory]
        [InlineData("警报",1)] [InlineData("医疗警报",2)] [InlineData("工业警报",3)]
        [InlineData("毒气",4)] [InlineData("腐蚀",5)] [InlineData("寒铁",6)]
        [InlineData("伏击",7)] [InlineData("鸿门宴",8)] [InlineData("血月",9)]
        [InlineData("檀烟",10)] [InlineData("custom",11)]
        public void EveryAtmospherePresetHasANativeLook(string name,int expected) {
            var p=Payload();
            p["atmosphere"]=new JObject {
                ["preset"]=name,["r"]=218,["g"]=38,["b"]=57,["alpha"]=18,
                ["mode"]="radial",["pulse"]=true,["pulseSpeed"]=0.12,
                ["pulseMin"]=5,["pulseMax"]=20
            };
            Assert.True(WorldLightingFrame.TryParse(p,out var frame));
            Assert.Equal(name,frame.Atmosphere.Name);
            Assert.Equal(18f/100f,frame.Atmosphere.NativeParameters[3],5);
            if(name!="custom") Assert.Equal(expected,WorldPresentationCatalog.Load(CatalogPath()).Atmosphere(name).Family);
        }
        [Fact] public void AtmosphereIsClosedAndMissingLegacyFieldMeansNoNativeOverlay() {
            var p=Payload();
            Assert.True(WorldLightingFrame.TryParse(p,out var old));
            Assert.Equal("none",old.Atmosphere.Name);
            p["atmosphere"]=new JObject {
                ["preset"]="custom",["r"]=20,["g"]=40,["b"]=60,["alpha"]=12,
                ["mode"]="flat",["pulse"]=false,["pulseSpeed"]=0.08,
                ["pulseMin"]=5,["pulseMax"]=20
            };
            Assert.True(WorldLightingFrame.TryParse(p,out var custom));
            Assert.Equal("custom",custom.Atmosphere.Name);
            ((JObject)p["atmosphere"])["alpha"]=101;
            Assert.False(WorldLightingFrame.TryParse(p,out _));
            ((JObject)p["atmosphere"])["alpha"]=12;
            ((JObject)p["atmosphere"])["preset"]="unregistered";
            Assert.True(WorldLightingFrame.TryParse(p,out var unknown));
            Assert.Equal("unregistered",unknown.Atmosphere.Name);
            Assert.Throws<InvalidDataException>(()=>WorldPresentationCatalog.Load(CatalogPath()).Atmosphere(unknown.Atmosphere.Name));
        }
        [Fact] public void DataOnlyVisualTuningChangesNativeParametersWithoutChangingFamily() {
            string source=CatalogPath(), copy=Path.GetTempFileName();
            try {
                var baseline=WorldPresentationCatalog.Load(source);
                var json=JObject.Parse(File.ReadAllText(source));
                var looks=(JArray)json["atmosphere"];
                foreach(JObject look in looks) if((string)look["name"]=="医疗警报") look["base"]=0.20;
                var added=(JObject)looks[0].DeepClone(); added["name"]="新预设"; looks.Add(added);
                ((JObject)json["weather"])["rain"]["count"]=220;
                File.WriteAllText(copy,json.ToString());
                var changed=WorldPresentationCatalog.Load(copy);
                Assert.Equal(baseline.Atmosphere("医疗警报").Family,changed.Atmosphere("医疗警报").Family);
                Assert.NotEqual(baseline.Atmosphere("医疗警报").Tuning[3],changed.Atmosphere("医疗警报").Tuning[3]);
                Assert.Equal(baseline.Atmosphere("警报").Family,changed.Atmosphere("新预设").Family);
                Assert.Equal(220,changed.Weather(1).Count);
                Assert.NotEqual(baseline.Sha256,changed.Sha256);
                ((JObject)json["weather"])["rain"]["count"]=513;
                File.WriteAllText(copy,json.ToString());
                Assert.Throws<InvalidDataException>(()=>WorldPresentationCatalog.Load(copy));
            } finally { File.Delete(copy); }
        }
        private static string CatalogPath() {
            var directory=new DirectoryInfo(AppContext.BaseDirectory);
            while(directory!=null) {
                string path=Path.Combine(directory.FullName,WorldPresentationCatalog.RelativePath);
                if(File.Exists(path)) return path;
                directory=directory.Parent;
            }
            throw new FileNotFoundException(WorldPresentationCatalog.RelativePath);
        }
        [Fact] public void DisconnectInvalidatesAlreadyQueuedSnapshot() {
            var queue=new Queue<Action>(); int adopted=0,resets=0;
            var task=new WorldLightingTask(a=>queue.Enqueue(a),f=>adopted++,()=>resets++);
            task.Handle(new JObject { ["payload"]=Payload() }); task.Disconnected();
            while(queue.Count>0) queue.Dequeue()();
            Assert.Equal(0,adopted); Assert.Equal(1,resets);
        }
    }
}
