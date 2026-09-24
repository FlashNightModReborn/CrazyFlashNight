using System;
using System.Collections.Generic;
using System.Drawing;
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
        [Fact] public void DisconnectInvalidatesAlreadyQueuedSnapshot() {
            var queue=new Queue<Action>(); int adopted=0,resets=0;
            var task=new WorldLightingTask(a=>queue.Enqueue(a),f=>adopted++,()=>resets++);
            task.Handle(new JObject { ["payload"]=Payload() }); task.Disconnected();
            while(queue.Count>0) queue.Dequeue()();
            Assert.Equal(0,adopted); Assert.Equal(1,resets);
        }
    }
}
