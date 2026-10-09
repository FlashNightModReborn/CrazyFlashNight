using System;
using System.Drawing;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class RenderScheduleTests
    {
        private static RenderSample S(int frames=15,int ms=500,string preset="MEDIUM") =>
            new RenderSample {Frames=frames,DurationMs=ms,Preset=preset,Quality=preset};
        private static RenderSchedule Ready(PerformancePolicy policy=null,int sourceHeight=2160)
        {
            var p=new RenderSchedule(new RenderScheduleSettings(),policy,sourceHeight);
            Assert.True(p.ConfirmApplied(p.Current,0)); return p;
        }
        private static void Feed(RenderSchedule p,int count,int frames,ref double now,bool admitted=true,bool complete=true)
        {
            for(int i=0;i<count;i++) {
                p.Observe(S(frames),now+=500,admitted);
                if(complete && p.Pending) p.ConfirmApplied(p.Current,now);
            }
        }
        [Fact] public void NoDecisionBeforeInitialTargetActuallyApplies()
        {
            var p=new RenderSchedule(new RenderScheduleSettings()); double now=0;
            Feed(p,30,2,ref now,complete:false); Assert.Equal(0,p.Current.Stage);
            Assert.True(p.Pending);
        }
        [Fact] public void SustainedPressureStepsDownAndNeverExceedsAbsoluteBudget()
        {
            var p=Ready(new PerformancePolicy("balanced","auto",540)); double now=0;
            Feed(p,4,10,ref now); Assert.Equal(0,p.Current.Stage);
            Feed(p,1,10,ref now); Assert.NotEqual(0,p.Current.Stage);
            Feed(p,50,10,ref now); Assert.Equal("LOW",p.Current.Quality);
            Assert.Equal(362,p.Current.Height); Assert.Equal(2,p.Current.EffectLevel);
        }
        [Fact] public void PanicUsesTheAllowedFloorWithoutMagicScaleLookup()
        {
            var p=Ready(new PerformancePolicy("performance","auto",540)); double now=0;
            Feed(p,4,4,ref now); Assert.Equal(270,p.Current.Height); Assert.Equal("LOW",p.Current.Quality);
            Feed(p,30,4,ref now); Assert.Equal(270,p.Current.Height);
        }
        [Fact] public void PausedInactiveLongGapAndLoadingDoNotAccumulatePressure()
        {
            var p=Ready(); double now=0;
            Feed(p,30,2,ref now,false); Assert.Equal(0,p.Current.Stage);
            var paused=S(2); paused.Paused=true;
            for(int i=0;i<20;i++) p.Observe(paused,now+=500,true);
            p.Observe(S(1,8000),now+=8000,true);
            Assert.Equal(0,p.Current.Stage);
            Feed(p,3,10,ref now); Assert.Equal(0,p.Current.Stage);
        }
        [Fact] public void LongFrameRecoveryNeedsCleanSampleTime()
        {
            var p=Ready(); double now=0;
            Feed(p,5,10,ref now); int lowered=p.Current.Stage; Assert.True(lowered>0);
            var s=S(); s.LongFrames=1;
            for(int i=0;i<50;i++) p.Observe(s,now+=500,true);
            Assert.Equal(lowered,p.Current.Stage); Assert.Equal(0,p.RecoveryMs);
            Feed(p,20,15,ref now); Assert.Equal(0,p.Current.Stage);
        }
        [Fact] public void DelayedUpgradeStillStartsFailureWindowWhenApplied()
        {
            var p=Ready(); double now=0;
            Feed(p,5,10,ref now); Assert.Equal(1,p.Current.Stage);
            while(p.Current.Stage!=0) {
                p.Observe(S(),now+=500,true);
                Assert.True(now<20000);
            }
            Assert.True(p.Pending);
            Feed(p,30,15,ref now,false,false);
            Assert.True(p.ConfirmApplied(p.Current,now));
            Feed(p,5,10,ref now); Assert.Equal(1,p.Current.Stage);
            Feed(p,18,15,ref now); Assert.Equal(1,p.Current.Stage); Assert.Equal(0,p.RecoveryMs);
            Feed(p,50,15,ref now); Assert.Equal(0,p.Current.Stage);
        }
        [Fact] public void FixedMeansWholeTargetIndependentOfOldAs2Preset()
        {
            var p=Ready(new PerformancePolicy("quality","fixed",540)); double now=0;
            var target=p.Current;
            Feed(p,80,1,ref now);
            p.Observe(S(15,preset:"LOW"),now+500,true);
            Assert.Equal(target,p.Current);
            Assert.Equal(new RenderSelection(0,540,"HIGH",0),target);
        }
        [Fact] public void ResolutionClampSkipsNoOpTargetsButRetainsLogicalPressure()
        {
            var stages=RenderSchedule.Stages(new PerformancePolicy("balanced","auto",540),2160);
            Assert.All(stages,s=>Assert.InRange(s.Height,1,540));
            Assert.Equal(0,stages[0].EffectLevel); Assert.Equal(1,stages[1].EffectLevel);
            var p=Ready(new PerformancePolicy("balanced","auto",540),1); double now=0;
            Feed(p,5,10,ref now); Assert.Equal(1,p.Current.Stage);
            Feed(p,5,10,ref now); Assert.Equal(3,p.Current.Stage);
            Feed(p,30,10,ref now); Assert.Equal(3,p.Current.Stage);
        }
        [Fact] public void ShrinkingThenRestoringWindowCannotSilentlyUpgradeThePressureLevel()
        {
            var p=Ready(); double now=0; Feed(p,40,10,ref now);
            Assert.Equal(4,p.Current.Stage);
            p.Configure(PerformancePolicy.Default,400); p.ConfirmApplied(p.Current,now);
            Assert.Equal(268,p.Current.Height);
            p.Configure(PerformancePolicy.Default,1080); p.ConfirmApplied(p.Current,now);
            Assert.Equal(4,p.Current.Stage); Assert.Equal(724,p.Current.Height);
        }
        [Fact] public void SmallWindowStillHasResolutionHeadroomInsideAnAbsoluteCeiling()
        {
            var p=Ready(new PerformancePolicy("balanced","auto",540),480); double now=0;
            Assert.Equal(480,p.Current.Height);
            Feed(p,40,10,ref now); Assert.Equal(322,p.Current.Height);
            p.Configure(new PerformancePolicy("performance","fixed",540),2160);
            Assert.Equal(540,p.Current.Height); Assert.Equal("LOW",p.Current.Quality);
        }
        [Fact] public void OldCompletionCannotAdoptNewPolicy()
        {
            var p=Ready(); var old=p.Current;
            p.Configure(new PerformancePolicy("quality","fixed",720),1080);
            Assert.False(p.ConfirmApplied(old,100));
            Assert.True(p.Pending); Assert.Equal("HIGH",p.Current.Quality);
        }
        [Fact] public void ParserRejectsMissingNonfiniteAndInconsistentTelemetry()
        {
            string wire="30|6|0|1|v2|15|500|0|34|MEDIUM|MEDIUM|0|0|1|2";
            Assert.True(RenderSample.TryParse(wire.Split('|'),out var s)); Assert.Equal(30,s.Fps);
            Assert.False(RenderSample.TryParse("30|6|0|1".Split('|'),out _));
            Assert.False(RenderSample.TryParse(wire.Replace("|500|","|NaN|").Split('|'),out _));
            Assert.False(RenderSample.TryParse(wire.Replace("|0|34|","|16|34|").Split('|'),out _));
            Assert.False(RenderSample.TryParse(wire.Replace("|34|","|501|").Split('|'),out _));
        }
        [Theory]
        [InlineData(3840,2160,2160,540,960,540)]
        [InlineData(3840,2160,1440,540,1440,810)]
        [InlineData(3840,2160,1080,540,1920,1080)]
        [InlineData(640,360,360,540,640,360)]
        [InlineData(1920,1080,1080,0,1920,1080)]
        public void AbsoluteBudgetUsesSourceRasterAndNeverUpsamples(int w,int h,int sourceHeight,int cap,int ew,int eh)
            => Assert.Equal(new Size(ew,eh),FlashRenderBudget.Fit(new Size(w,h),sourceHeight,cap));
        [Theory]
        [InlineData(1600,900,1200,675,800,450,600,337)]
        [InlineData(1920,1080,1286,724,960,540,643,362)]
        [InlineData(1000,800,750,450,0,0,0,-75)]
        [InlineData(1600,900,1200,675,-40,940,-30,705)]
        [InlineData(3840,2160,960,540,1920,1080,480,270)]
        public void PointerMappingMatchesAspectFitAndAllowsOutsideDrag(int ow,int oh,int sw,int sh,int x,int y,int ex,int ey)
        {
            var point=WorldPointerMapper.Map(new Point(x,y),new Size(ow,oh),new Size(sw,sh));
            Assert.Equal(new Point(ex,ey),point);
            Assert.Equal(point,WorldPointerMapper.Unpack(WorldPointerMapper.Pack(point)));
        }
    }
}
