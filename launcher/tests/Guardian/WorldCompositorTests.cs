using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;
namespace CF7Launcher.Tests.Guardian {
    public class WorldCompositorTests {
        private static object TransitionPaint(WorldCompositorController controller) =>
            typeof(WorldCompositorController).GetField("_transitionPaintRequest",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(controller);
        private static double TransitionPaintAfter(object request) =>
            (double)request.GetType().GetField("After",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(request);
        private static bool RecordTransitionPaint(WorldCompositorController controller,object request,double painted) =>
            (bool)typeof(WorldCompositorController).GetMethod("RecordTransitionPaint",BindingFlags.NonPublic|BindingFlags.Instance).Invoke(controller,new[]{request,(object)painted});
        private static void SetTransitionScene(WorldCompositorController controller,long scene,bool ready=true) {
            var payload=Payload(); payload["scene"]=scene; payload["ready"]=ready;
            Assert.True(WorldLightingFrame.TryParse(payload,out var frame)); SetRenderField(controller,"_frame",frame);
        }
        private static void RecordTransitionGrade(WorldCompositorController controller,long scene,double now) =>
            typeof(WorldCompositorController).GetMethod("RecordTransitionGrade",BindingFlags.NonPublic|BindingFlags.Instance).Invoke(controller,new object[]{scene,now});
        [Fact] public void InitialGradeDoesNotIssueAnUnrequestedStartupRepaint() {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetTransitionScene(controller,2); RecordTransitionGrade(controller,2,100);
            Assert.Null(TransitionPaint(controller));
        }
        [Fact] public void ExplicitRevealStillRequiresASecondPaintAfterItsGradeSubmission() {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetTransitionScene(controller,3); controller.RequireFreshTransitionFrame(3);
            var first=TransitionPaint(controller); double now=TransitionPaintAfter(first)+10;
            Assert.True(RecordTransitionPaint(controller,first,now));
            RecordTransitionGrade(controller,3,now+1);
            var second=TransitionPaint(controller); Assert.NotNull(second); Assert.NotSame(first,second);
            Assert.Equal(now+1,TransitionPaintAfter(second));
        }
        [Fact] public void ResetDoesNotCarryRevealPaintAuthorityIntoANewSource() {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetTransitionScene(controller,3); controller.RequireFreshTransitionFrame(3); controller.ResetSource();
            SetTransitionScene(controller,3); RecordTransitionGrade(controller,3,100);
            Assert.Null(TransitionPaint(controller));
        }
        [Fact] public void StaticRevealRequestsPaintWithoutGrantingPresentationFromItsAcknowledgment() {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetTransitionScene(controller,3); controller.RequireFreshTransitionFrame(3);
            var request=TransitionPaint(controller); Assert.NotNull(request);
            double painted=TransitionPaintAfter(request)+10;
            Assert.True(RecordTransitionPaint(controller,request,painted));
            Assert.Null(TransitionPaint(controller));
            Assert.Equal(painted,(double)typeof(WorldCompositorController).GetField("_requiredFrameMs",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(controller));
            Assert.Equal(0L,(long)typeof(WorldCompositorController).GetField("_transitionPresentedScene",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(controller));
        }
        [Fact] public void LatePaintCannotAcknowledgeANewerRevealForTheSameScene() {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetTransitionScene(controller,3); controller.RequireFreshTransitionFrame(3); var old=TransitionPaint(controller);
            controller.RequireFreshTransitionFrame(3); var current=TransitionPaint(controller);
            Assert.NotSame(old,current);
            Assert.False(RecordTransitionPaint(controller,old,TransitionPaintAfter(current)+10));
            Assert.Same(current,TransitionPaint(controller));
            Assert.True(RecordTransitionPaint(controller,current,TransitionPaintAfter(current)+20));
        }
        [Theory] [InlineData(4,true)] [InlineData(3,false)]
        public void PaintForAReplacedOrUnreadySceneCannotAdvanceTheFence(long scene,bool ready) {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetTransitionScene(controller,3); controller.RequireFreshTransitionFrame(3); var old=TransitionPaint(controller);
            SetTransitionScene(controller,scene,ready);
            Assert.False(RecordTransitionPaint(controller,old,TransitionPaintAfter(old)+10));
            Assert.Same(old,TransitionPaint(controller));
        }
        [Fact] public void SourceResetCancelsAQueuedTransitionRepaint() {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetTransitionScene(controller,3); controller.RequireFreshTransitionFrame(3); var old=TransitionPaint(controller);
            controller.ResetSource(); SetTransitionScene(controller,3);
            Assert.Null(TransitionPaint(controller));
            Assert.False(RecordTransitionPaint(controller,old,TransitionPaintAfter(old)+10));
        }
        [Theory] [InlineData(double.NaN)] [InlineData(double.PositiveInfinity)] [InlineData(double.NegativeInfinity)] [InlineData(-1)]
        public void InvalidRepaintAcknowledgmentFailsInsteadOfAdvancingTheFence(double invalid) {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetTransitionScene(controller,3); controller.RequireFreshTransitionFrame(3); var request=TransitionPaint(controller);
            var error=Assert.Throws<TargetInvocationException>(()=>RecordTransitionPaint(controller,request,invalid));
            Assert.IsType<InvalidOperationException>(error.InnerException);
            Assert.Same(request,TransitionPaint(controller));
        }

        private static void GeometryWait(WorldCompositorController controller,double now) =>
            typeof(WorldCompositorController).GetMethod("CheckGeometryRecoveryTimeout",BindingFlags.NonPublic|BindingFlags.Instance)
                .Invoke(controller,new object[]{now});
        [Fact] public void UnknownGeometryStartsItsBudgetAtFirstFailureAfterAHealthySession() {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetRenderField(controller,"_startedMs",1d); SetRenderField(controller,"_requiredFrameMs",2d);
            GeometryWait(controller,100000);
            GeometryWait(controller,110000); // preserve existing strictly-greater 10s limit
            var error=Assert.Throws<TargetInvocationException>(()=>GeometryWait(controller,110001));
            Assert.IsType<TimeoutException>(error.InnerException);
        }
        [Fact] public void RepeatedGeometryFailureDoesNotSlideRecoveryDeadline() {
            using var owner=new Form(); using var controller=RenderController(owner);
            GeometryWait(controller,1000);
            for(int now=2000;now<=11000;now+=1000) GeometryWait(controller,now);
            var error=Assert.Throws<TargetInvocationException>(()=>GeometryWait(controller,11001));
            Assert.IsType<TimeoutException>(error.InnerException);
        }
        [Fact] public void OnGeometryChangedHandlerRestartsGeometryWaitBudget() {
            using var owner=new Form(); using var controller=RenderController(owner);
            GeometryWait(controller,1000);
            typeof(WorldCompositorController).GetMethod("OnGeometryChanged",BindingFlags.NonPublic|BindingFlags.Instance)
                .Invoke(controller,new object[]{owner,EventArgs.Empty});
            GeometryWait(controller,500000);
            GeometryWait(controller,510000);
            var error=Assert.Throws<TargetInvocationException>(()=>GeometryWait(controller,510001));
            Assert.IsType<TimeoutException>(error.InnerException);
        }
        [Fact] public void SourceResetDoesNotInheritGeometryWaitDeadline() {
            using var owner=new Form(); using var controller=RenderController(owner);
            GeometryWait(controller,1000); controller.ResetSource();
            GeometryWait(controller,500000);
            GeometryWait(controller,510000);
            var error=Assert.Throws<TargetInvocationException>(()=>GeometryWait(controller,510001));
            Assert.IsType<TimeoutException>(error.InnerException);
        }

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
        [Theory]
        [InlineData("LOW",2)]
        [InlineData("MEDIUM",0)]
        public void SameHeightQualityOrEffectsChangeNeedsItsOwnFreshCapture(string quality,int effects) {
            using var owner=new Form();
            using var controller=RenderController(owner);
            SetRenderField(controller,"_appliedHeight",720);
            int first=0,second=0;
            controller.ApplyRenderSelection(new RenderSelection(2,720,"MEDIUM",1),.15f,_=>first++);
            object initial=PendingRender(controller);
            Assert.True(RecordPaint(controller,initial,100));
            Assert.True(CompleteRender(controller,initial,100));
            Assert.Equal(1,first);

            controller.ApplyRenderSelection(new RenderSelection(3,720,quality,effects),.15f,_=>second++);
            object changed=PendingRender(controller);
            // A native animation may have presented repeatedly using the old capture.
            Assert.False(CompleteRender(controller,changed,150));
            Assert.Equal(0,second);
            Assert.True(RecordPaint(controller,changed,200));
            Assert.False(CompleteRender(controller,changed,199));
            Assert.True(CompleteRender(controller,changed,200));
            Assert.Equal(1,second);
        }
        [Fact] public void RepaintReturningAfterAnotherSelectionCannotCompleteTheNewTarget() {
            using var owner=new Form();
            using var controller=RenderController(owner);
            SetRenderField(controller,"_appliedHeight",720);
            int oldCalls=0,newCalls=0;
            controller.ApplyRenderSelection(new RenderSelection(2,720,"MEDIUM",1),.15f,_=>oldCalls++);
            object old=PendingRender(controller);
            // ApplyRenderSelection runs on the UI while the first RepaintAsync awaits.
            controller.ApplyRenderSelection(new RenderSelection(3,720,"LOW",2),.15f,_=>newCalls++);
            object current=PendingRender(controller);
            Assert.False(RecordPaint(controller,old,200));
            Assert.False(CompleteRender(controller,old,250));
            Assert.False(CompleteRender(controller,current,250));
            Assert.Same(current,PendingRender(controller));
            Assert.True(RecordPaint(controller,current,300));
            Assert.True(CompleteRender(controller,current,300));
            Assert.Equal(0,oldCalls);Assert.Equal(1,newCalls);
        }
        [Fact] public void SourceResetCancelsAPaintAlreadyInFlight() {
            using var owner=new Form();
            using var controller=RenderController(owner);
            SetRenderField(controller,"_appliedHeight",720);
            int calls=0;
            controller.ApplyRenderSelection(new RenderSelection(2,720,"MEDIUM",1),.15f,_=>calls++);
            object old=PendingRender(controller);
            controller.ResetSource();
            Assert.False(RecordPaint(controller,old,200));
            Assert.False(CompleteRender(controller,old,250));
            Assert.Null(PendingRender(controller));
            Assert.Equal(0,calls);
        }
        [Fact] public void CompletionCallbackCanReenterWithoutLosingTheNextFence() {
            using var owner=new Form();
            using var controller=RenderController(owner);
            SetRenderField(controller,"_appliedHeight",720);
            int firstCalls=0,nextCalls=0;
            controller.ApplyRenderSelection(new RenderSelection(2,720,"MEDIUM",1),.15f,_=> {
                firstCalls++;
                controller.ApplyRenderSelection(new RenderSelection(3,720,"LOW",2),.15f,_=>nextCalls++);
            });
            object first=PendingRender(controller);
            Assert.True(RecordPaint(controller,first,100));
            Assert.True(CompleteRender(controller,first,100));
            object next=PendingRender(controller);
            Assert.NotNull(next);Assert.NotSame(first,next);
            Assert.False(CompleteRender(controller,first,200));
            Assert.False(CompleteRender(controller,next,200));
            Assert.True(RecordPaint(controller,next,250));
            Assert.True(CompleteRender(controller,next,250));
            Assert.Equal(1,firstCalls);Assert.Equal(1,nextCalls);
        }
        [Fact] public void FreshCaptureWithAnotherAppliedHeightCannotCompleteTheTarget() {
            using var owner=new Form();
            using var controller=RenderController(owner);
            int calls=0;
            controller.ApplyRenderSelection(new RenderSelection(4,540,"LOW",2),.15f,_=>calls++);
            object request=PendingRender(controller);
            Assert.True(RecordPaint(controller,request,100));
            SetRenderField(controller,"_appliedHeight",720);
            Assert.False(CompleteRender(controller,request,150));
            Assert.Same(request,PendingRender(controller));
            SetRenderField(controller,"_appliedHeight",540);
            Assert.True(CompleteRender(controller,request,150));
            Assert.Equal(1,calls);
        }
        private static WorldCompositorController RenderController(Form owner) {
            string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
            return new WorldCompositorController(owner,owner,()=>IntPtr.Zero,()=>false,_=>{},root,()=>false,_=>{},()=>{});
        }
        private static object PendingRender(WorldCompositorController controller)=>
            typeof(WorldCompositorController).GetField("_renderCompletion",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(controller);
        private static void SetRenderField(WorldCompositorController controller,string name,object value)=>
            typeof(WorldCompositorController).GetField(name,BindingFlags.NonPublic|BindingFlags.Instance).SetValue(controller,value);
        private static bool RecordPaint(WorldCompositorController controller,object request,double painted)=>
            (bool)typeof(WorldCompositorController).GetMethod("RecordRenderPaint",BindingFlags.NonPublic|BindingFlags.Instance)
                .Invoke(controller,new object[]{request,painted});
        private static bool CompleteRender(WorldCompositorController controller,object request,double captured)=>
            (bool)typeof(WorldCompositorController).GetMethod("CompleteRenderSelection",BindingFlags.NonPublic|BindingFlags.Instance)
                .Invoke(controller,new object[]{request,captured,new Size(960,540)});
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
        [Fact] public void ClippedClientGeometryPreservesFullStageAlignmentAcrossTopLeftAndBottomRight() {
            var capture=new Rectangle(100,50,1024,576);
            var topLeftClippedSource=new Rectangle(98,48,1024,576);
            Assert.True(WorldCompositorController.TryResolveGeometrySnapshot(
                new Rectangle(100,50,1022,574),topLeftClippedSource,capture,capture,capture.Size,
                out var topLeft,out var reason));
            Assert.Null(reason);
            Assert.True(topLeft.IsClientClipped);
            Assert.Equal(new Point(2,2),topLeft.ClientOffset);
            Assert.Equal(new Rectangle(0,0,1022,574),topLeft.Crop);
            Assert.Equal(new RectangleF(-2f,-2f,1024f,576f),topLeft.ComputeSourceStageRect());
            Assert.Equal(new RectangleF(0f,0f,1024f,576f),topLeft.ComputeContentViewport(new Size(1024,576)));
            Assert.Equal(new RectangleF(2f,2f,1022f,574f),topLeft.ComputeOutputViewport(new Size(1024,576)));

            var bottomRightClippedSource=new Rectangle(102,52,1024,576);
            Assert.True(WorldCompositorController.TryResolveGeometrySnapshot(
                new Rectangle(102,52,1022,574),bottomRightClippedSource,capture,capture,capture.Size,
                out var bottomRight,out reason));
            Assert.Null(reason);
            Assert.True(bottomRight.IsClientClipped);
            Assert.Equal(new Point(0,0),bottomRight.ClientOffset);
            Assert.Equal(new Rectangle(2,2,1022,574),bottomRight.Crop);
            Assert.Equal(new RectangleF(0f,0f,1024f,576f),bottomRight.ComputeSourceStageRect());
            Assert.Equal(new RectangleF(0f,0f,1024f,576f),bottomRight.ComputeContentViewport(new Size(1024,576)));
            Assert.Equal(new RectangleF(0f,0f,1022f,574f),bottomRight.ComputeOutputViewport(new Size(1024,576)));
        }
        [Fact] public void GeometryCropFencePreservesStaticSceneAcrossInitialCropAndWindowMoveWhileFencingResizes() {
            var initialCrop=new Rectangle(8,40,1280,720);
            Assert.Equal(100d,WorldCompositorController.SelectGeometryCropFenceMs(
                Rectangle.Empty,initialCrop,viewportHeld:false,paintFenceMs:0d,geometryChangedAtMs:double.NaN,requiredFrameMs:100d,nowMs:250d));
            var movedSameSizeCrop=new Rectangle(9,40,1280,720);
            Assert.Equal(100d,WorldCompositorController.SelectGeometryCropFenceMs(
                initialCrop,movedSameSizeCrop,viewportHeld:false,paintFenceMs:0d,geometryChangedAtMs:double.NaN,requiredFrameMs:100d,nowMs:300d));
            var resizedCrop=new Rectangle(8,40,1600,900);
            Assert.Equal(420d,WorldCompositorController.SelectGeometryCropFenceMs(
                initialCrop,resizedCrop,viewportHeld:true,paintFenceMs:420d,geometryChangedAtMs:400d,requiredFrameMs:100d,nowMs:450d));
            Assert.Equal(410d,WorldCompositorController.SelectGeometryCropFenceMs(
                initialCrop,resizedCrop,viewportHeld:false,paintFenceMs:0d,geometryChangedAtMs:410d,requiredFrameMs:100d,nowMs:450d));
        }
        [Fact] public void CommitGeometrySnapshotSubmitsAtomicResizeAndClippedClientTransitions() {
            using var owner=new Form(); using var controller=RenderController(owner);
            SetRenderField(controller,"_requiredFrameMs",100d);
            var submissions=new List<(WorldGeometrySnapshot Geometry,double FenceMs)>();

            // 1. Initial 1280x720 windowed admission
            var cap1280=new Rectangle(100,50,1296,759);
            var src1280=new Rectangle(108,81,1280,720);
            Assert.True(WorldCompositorController.TryResolveGeometrySnapshot(
                src1280,src1280,cap1280,cap1280,cap1280.Size,out var snap1280,out var reason));
            Assert.Null(reason);
            Assert.True(controller.CommitGeometrySnapshot(snap1280,200d,(g,f)=>submissions.Add((g,f))));
            Assert.Single(submissions);
            Assert.Equal(new Rectangle(8,31,1280,720),submissions[0].Geometry.Crop);
            Assert.Equal(new Size(1280,720),submissions[0].Geometry.FullClientSize);
            Assert.Equal(100d,submissions[0].FenceMs);
            Assert.False(controller.CommitGeometrySnapshot(snap1280,210d,(g,f)=>submissions.Add((g,f))));

            // 2. Held resize enlarge 1280x720 -> 1600x900 (R01 regression check)
            SetRenderField(controller,"_viewportHeld",true);
            SetRenderField(controller,"_paintFenceMs",420d);
            SetRenderField(controller,"_geometryChangedAtMs",400d);
            var cap1600=new Rectangle(100,50,1616,939);
            var src1600=new Rectangle(108,81,1600,900);
            Assert.True(WorldCompositorController.TryResolveGeometrySnapshot(
                src1600,src1600,cap1600,cap1600,cap1600.Size,out var snap1600,out reason));
            Assert.True(controller.CommitGeometrySnapshot(snap1600,450d,(g,f)=>submissions.Add((g,f))));
            Assert.Equal(2,submissions.Count);
            Assert.Equal(new Rectangle(8,31,1600,900),submissions[1].Geometry.Crop);
            Assert.Equal(new Size(1600,900),submissions[1].Geometry.FullClientSize);
            Assert.Equal(420d,submissions[1].FenceMs);
            Assert.False((bool)typeof(WorldCompositorController).GetField("_viewportHeld",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(controller));

            // 3. Unheld resize shrink 1600x900 -> 1024x576 (R01 regression check)
            SetRenderField(controller,"_geometryChangedAtMs",510d);
            var cap1024=new Rectangle(100,50,1040,615);
            var src1024=new Rectangle(108,81,1024,576);
            Assert.True(WorldCompositorController.TryResolveGeometrySnapshot(
                src1024,src1024,cap1024,cap1024,cap1024.Size,out var snap1024,out reason));
            Assert.True(controller.CommitGeometrySnapshot(snap1024,520d,(g,f)=>submissions.Add((g,f))));
            Assert.Equal(3,submissions.Count);
            Assert.Equal(new Rectangle(8,31,1024,576),submissions[2].Geometry.Crop);
            Assert.Equal(new Size(1024,576),submissions[2].Geometry.FullClientSize);
            Assert.Equal(510d,submissions[2].FenceMs);

            // 4. Clipped client transition (1px top-left clip on 1024x576) preserves fence when only clientOffset changes
            var capBorderless=new Rectangle(100,50,1024,576);
            var srcClipped=new Rectangle(99,49,1024,576);
            Assert.True(WorldCompositorController.TryResolveGeometrySnapshot(
                new Rectangle(100,50,1023,575),srcClipped,capBorderless,capBorderless,capBorderless.Size,out var snapClipped,out reason));
            Assert.True(controller.CommitGeometrySnapshot(snapClipped,550d,(g,f)=>submissions.Add((g,f))));
            Assert.Equal(4,submissions.Count);
            Assert.Equal(new Point(1,1),submissions[3].Geometry.ClientOffset);
            Assert.Equal(new Rectangle(0,0,1023,575),submissions[3].Geometry.Crop);
            Assert.Equal(new Size(1024,576),submissions[3].Geometry.FullClientSize);
            Assert.Equal(550d,submissions[3].FenceMs);
        }
        internal static string ResolveNativeCompositorModuleForTest(string root,string candidateEnv) {
            if(!string.IsNullOrWhiteSpace(candidateEnv)) {
                string candidate=Path.GetFullPath(candidateEnv);
                if(!Directory.Exists(candidate))
                    throw new InvalidOperationException($"Explicit candidate directory does not exist: {candidate}");
                string module=Path.Combine(candidate,"runtime",NativeCompositorSession.ModuleName);
                if(!File.Exists(module))
                    throw new InvalidOperationException($"Explicit candidate native module is missing: {module}");
                string manifestPath=Path.Combine(candidate,"runtime","cf7-runtime-manifest.tsv");
                if(!File.Exists(manifestPath))
                    throw new InvalidOperationException($"Explicit candidate manifest is missing: {manifestPath}");
                string metadataPath=Path.Combine(candidate,"runtime-build-metadata.v2.json");
                if(!File.Exists(metadataPath))
                    throw new InvalidOperationException($"Explicit candidate metadata is missing: {metadataPath}");
                JObject metadata=JObject.Parse(File.ReadAllText(metadataPath));
                string identity=metadata.Value<string>("buildIdentityHash");
                string closure=metadata.Value<string>("payloadClosureHash");
                if(string.IsNullOrWhiteSpace(identity) || identity.Length!=64 || string.IsNullOrWhiteSpace(closure) || closure.Length!=64)
                    throw new InvalidOperationException($"Explicit candidate metadata hashes are invalid: {metadataPath}");
                string expectedRel="runtime/"+NativeCompositorSession.ModuleName;
                string[] matchedRow=null;
                foreach(string line in File.ReadLines(manifestPath)) {
                    string[] parts=line.Split('\t');
                    if(parts.Length==4 && parts[0]=="file" && string.Equals(parts[1],expectedRel,StringComparison.Ordinal)) {
                        matchedRow=parts; break;
                    }
                }
                if(matchedRow==null || !long.TryParse(matchedRow[2],out long expectedLength))
                    throw new InvalidOperationException($"Explicit candidate manifest is missing entry for {expectedRel}");
                long actualLength=new FileInfo(module).Length;
                if(actualLength!=expectedLength)
                    throw new InvalidOperationException($"Explicit candidate module length mismatch: expected={expectedLength} actual={actualLength}");
                string actualSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(module)));
                if(!string.Equals(actualSha,matchedRow[3],StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException($"Explicit candidate module SHA256 mismatch: expected={matchedRow[3]} actual={actualSha}");
                IntPtr loaded=System.Runtime.InteropServices.NativeLibrary.Load(module);
                try {
                    if(!System.Runtime.InteropServices.NativeLibrary.TryGetExport(loaded,"ProbeSetViewportGeometry",out _))
                        throw new InvalidOperationException($"Explicit candidate module is missing required export ProbeSetViewportGeometry: {module}");
                } finally {
                    System.Runtime.InteropServices.NativeLibrary.Free(loaded);
                }
                Console.WriteLine($"[WorldCompositorTests] Verified explicit candidate module: path={module} sha256={actualSha} buildIdentity={identity}");
                return module;
            }
            string latestCandidate=null;
            string candidatesDir=Path.Combine(root,"tmp","runtime-candidates","v2");
            if(Directory.Exists(candidatesDir)) {
                foreach(string dir in Directory.GetDirectories(candidatesDir,"c-*")) {
                    string dll=Path.Combine(dir,"runtime",NativeCompositorSession.ModuleName);
                    if(File.Exists(dll) && (latestCandidate==null || File.GetLastWriteTimeUtc(dll)>File.GetLastWriteTimeUtc(latestCandidate)))
                        latestCandidate=dll;
                }
            }
            string[] fallbackCandidates={
                Path.Combine(root,"tmp","night-vision-native-tests",NativeCompositorSession.ModuleName),
                latestCandidate,
                Path.Combine(root,"launcher","build","native",NativeCompositorSession.ModuleName),
                Path.Combine(root,"runtime",NativeCompositorSession.ModuleName)
            };
            foreach(string c in fallbackCandidates) {
                if(string.IsNullOrWhiteSpace(c) || !File.Exists(c)) continue;
                IntPtr mod=System.Runtime.InteropServices.NativeLibrary.Load(c);
                try {
                    if(System.Runtime.InteropServices.NativeLibrary.TryGetExport(mod,"ProbeSetViewportGeometry",out _))
                        return Path.GetFullPath(c);
                } finally { System.Runtime.InteropServices.NativeLibrary.Free(mod); }
            }
            return null;
        }
        [Fact] public void ExplicitCandidateResolutionRejectsMissingDirectoryMissingExportAndHashMismatch() {
            string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
            string missingDir=Path.Combine(root,"tmp","candidate-does-not-exist-"+Guid.NewGuid().ToString("N"));
            var missingEx=Assert.Throws<InvalidOperationException>(()=>ResolveNativeCompositorModuleForTest(root,missingDir));
            Assert.Contains("Explicit candidate directory does not exist",missingEx.Message);

            string tempRoot=Path.Combine(Path.GetTempPath(),"cf7-explicit-candidate-test-"+Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path.Combine(tempRoot,"runtime"));
            try {
                string modulePath=Path.Combine(tempRoot,"runtime",NativeCompositorSession.ModuleName);
                string systemDll=Path.Combine(Environment.SystemDirectory,"version.dll");
                File.Copy(systemDll,modulePath,overwrite:true);
                byte[] moduleBytes=File.ReadAllBytes(modulePath);
                string actualSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(moduleBytes));
                string wrongSha=new string('0',64);
                File.WriteAllText(Path.Combine(tempRoot,"runtime-build-metadata.v2.json"),
                    "{\"buildIdentityHash\":\""+new string('A',64)+"\",\"payloadClosureHash\":\""+new string('B',64)+"\"}");

                // 2. Hash mismatch against manifest is immediately rejected without falling back
                File.WriteAllText(Path.Combine(tempRoot,"runtime","cf7-runtime-manifest.tsv"),
                    $"file\truntime/{NativeCompositorSession.ModuleName}\t{moduleBytes.Length}\t{wrongSha}\n");
                var hashEx=Assert.Throws<InvalidOperationException>(()=>ResolveNativeCompositorModuleForTest(root,tempRoot));
                Assert.Contains("SHA256 mismatch",hashEx.Message);

                // 3. Matching manifest + hash but missing ProbeSetViewportGeometry export is immediately rejected
                File.WriteAllText(Path.Combine(tempRoot,"runtime","cf7-runtime-manifest.tsv"),
                    $"file\truntime/{NativeCompositorSession.ModuleName}\t{moduleBytes.Length}\t{actualSha}\n");
                var exportEx=Assert.Throws<InvalidOperationException>(()=>ResolveNativeCompositorModuleForTest(root,tempRoot));
                Assert.Contains("ProbeSetViewportGeometry",exportEx.Message);
            } finally {
                if(Directory.Exists(tempRoot)) Directory.Delete(tempRoot,recursive:true);
            }
        }
        [Fact] public void NativeSessionAcceptsResizeAndClippedClientHandoffsWhileRejectingInvalidGeometry() {
            string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
            string candidateEnv=Environment.GetEnvironmentVariable("CF7_TEST_SHARED_WORLD_CANDIDATE");
            string modulePath=ResolveNativeCompositorModuleForTest(root,candidateEnv);
            if(!string.IsNullOrWhiteSpace(candidateEnv)) {
                string expectedModule=Path.Combine(Path.GetFullPath(candidateEnv),"runtime",NativeCompositorSession.ModuleName);
                Assert.Equal(expectedModule,modulePath,ignoreCase:true);
            }
            if(modulePath==null) return;

            using var source=new Form { FormBorderStyle=FormBorderStyle.None,ShowInTaskbar=false,ClientSize=new Size(1280,720) };
            using var output=new Form { FormBorderStyle=FormBorderStyle.None,ShowInTaskbar=false,ClientSize=new Size(1280,720) };
            _=source.Handle; _=output.Handle;
            using var controller=RenderController(source);
            using var session=new NativeCompositorSession(modulePath,source.Handle,(uint)Environment.ProcessId,output.Handle,borderless:true);

            // 1. Initial 1280x720 -> Enlarge 1600x900 -> Shrink 1024x576 -> Clipped 1022x574 via production CommitGeometrySnapshot + session.Viewport
            var snap1280=new WorldGeometrySnapshot(new Rectangle(0,0,1280,720),new Rectangle(8,31,1280,720),new Rectangle(0,0,1296,759),new Rectangle(8,31,1280,720),Point.Empty);
            Assert.True(controller.CommitGeometrySnapshot(snap1280,100d,session.Viewport));

            session.HoldViewport();
            SetRenderField(controller,"_viewportHeld",true);
            SetRenderField(controller,"_paintFenceMs",200d);
            var snap1600=new WorldGeometrySnapshot(new Rectangle(0,0,1600,900),new Rectangle(8,31,1600,900),new Rectangle(0,0,1616,939),new Rectangle(8,31,1600,900),Point.Empty);
            Assert.True(controller.CommitGeometrySnapshot(snap1600,210d,session.Viewport));

            session.HoldViewport();
            SetRenderField(controller,"_viewportHeld",true);
            SetRenderField(controller,"_paintFenceMs",300d);
            var snap1024=new WorldGeometrySnapshot(new Rectangle(0,0,1024,576),new Rectangle(8,31,1024,576),new Rectangle(0,0,1040,615),new Rectangle(8,31,1024,576),Point.Empty);
            Assert.True(controller.CommitGeometrySnapshot(snap1024,310d,session.Viewport));

            var snapClipTl=new WorldGeometrySnapshot(new Rectangle(0,0,1022,574),new Rectangle(-2,-2,1024,576),new Rectangle(0,0,1024,576),new Rectangle(0,0,1022,574),new Point(2,2));
            Assert.True(controller.CommitGeometrySnapshot(snapClipTl,400d,session.Viewport));

            var snapClipBr=new WorldGeometrySnapshot(new Rectangle(0,0,1022,574),new Rectangle(2,2,1024,576),new Rectangle(0,0,1024,576),new Rectangle(2,2,1022,574),Point.Empty);
            Assert.True(controller.CommitGeometrySnapshot(snapClipBr,500d,session.Viewport));

            // 2. Standalone Viewport + ClientGeometry across resizes
            session.Viewport(new Rectangle(0,0,1280,720),600d);
            session.ClientGeometry(Point.Empty,new Size(1280,720));
            session.Viewport(new Rectangle(0,0,1023,575),700d);
            session.ClientGeometry(new Point(1,1),new Size(1024,576));

            // 3. Invalid client geometry and out-of-capture crop are rejected without crashing
            Assert.Throws<InvalidOperationException>(()=>session.ClientGeometry(new Point(3,0),new Size(1026,576)));
            Assert.Throws<InvalidOperationException>(()=>session.ClientGeometry(Point.Empty,new Size(1600,900)));
            var badCaptureSnap=new WorldGeometrySnapshot(new Rectangle(0,0,1024,576),new Rectangle(0,0,1024,576),new Rectangle(0,0,1000,576),new Rectangle(0,0,1024,576),Point.Empty);
            Assert.Throws<InvalidOperationException>(()=>session.Viewport(badCaptureSnap,800d));
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
