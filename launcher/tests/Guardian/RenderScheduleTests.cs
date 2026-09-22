using System;
using System.Drawing;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class RenderScheduleTests
    {
        private static RenderSample S(int frames=15,int ms=500,string preset="MEDIUM") =>
            new RenderSample { Frames=frames,DurationMs=ms,Preset=preset,Quality=preset };
        private static void Feed(RenderSchedule p,int count,int frames,ref double now,bool admitted=true)
        { for(int i=0;i<count;i++) { now+=500; p.Observe(S(frames),now,admitted); } }
        [Fact] public void DowngradeRequiresSustainedPressureAndDoesNotRaiseResolutionAtLowBoundary()
        {
            var p=new RenderSchedule(new RenderScheduleSettings()); double now=0;
            Feed(p,3,10,ref now); Assert.Equal(0,p.Current.Stage);
            Feed(p,1,10,ref now); Assert.Equal(1,p.Current.Stage); Assert.Equal(.85,p.Current.Scale);
            Feed(p,7,10,ref now); Assert.Equal(.75,p.Current.Scale);
            for(int i=0;i<20 && p.Current.Quality!="LOW";i++) Feed(p,1,10,ref now);
            Assert.Equal("LOW",p.Current.Quality); Assert.Equal(.75,p.Current.Scale);
        }
        [Fact] public void PanicSkipsToLowThenStopsAtFloor()
        {
            var p=new RenderSchedule(new RenderScheduleSettings()); double now=0;
            Feed(p,3,4,ref now); Assert.Equal("LOW",p.Current.Quality); Assert.Equal(.75,p.Current.Scale);
            Feed(p,40,4,ref now); Assert.Equal(.67,p.Current.Scale);
        }
        [Fact] public void InactiveAndPausedSamplesDoNotAccumulatePressure()
        {
            var p=new RenderSchedule(new RenderScheduleSettings()); double now=0;
            Feed(p,30,2,ref now,false); Assert.Equal(0,p.Current.Stage);
            var paused=S(2); paused.Paused=true;
            for(int i=0;i<20;i++) p.Observe(paused,now+=500,true);
            Assert.Equal(0,p.Current.Stage);
            Feed(p,3,10,ref now); Assert.Equal(0,p.Current.Stage);
        }
        [Fact] public void LongGapAndSceneResetRetainTierButDiscardConfirmation()
        {
            var p=new RenderSchedule(new RenderScheduleSettings()); double now=0;
            Feed(p,4,10,ref now); Assert.Equal(1,p.Current.Stage);
            p.ResetObservations(); Assert.Equal(1,p.Current.Stage);
            p.Observe(S(1,8000),now+=8000,true); Assert.Equal(1,p.Current.Stage);
            Feed(p,3,10,ref now); Assert.Equal(1,p.Current.Stage);
        }
        [Fact] public void RecoveryNeedsHeadroomAndBacksOffAfterFailedUpgrade()
        {
            var p=new RenderSchedule(new RenderScheduleSettings()); double now=0;
            Feed(p,4,10,ref now); Assert.Equal(1,p.Current.Stage);
            Feed(p,8,15,ref now); Assert.Equal(1,p.Current.Stage);
            Feed(p,8,15,ref now); Assert.Equal(0,p.Current.Stage);
            Feed(p,6,10,ref now); Assert.Equal(1,p.Current.Stage);
            Feed(p,20,15,ref now); Assert.Equal(1,p.Current.Stage);
            Feed(p,40,15,ref now); Assert.Equal(0,p.Current.Stage);
        }
        [Fact] public void LongFramesBlockRecoveryEvenWithGoodAverage()
        {
            var p=new RenderSchedule(new RenderScheduleSettings()); double now=0;
            Feed(p,4,10,ref now);
            var s=S(); s.LongFrames=1;
            for(int i=0;i<40;i++) p.Observe(s,now+=500,true);
            Assert.Equal(1,p.Current.Stage);
        }
        [Fact] public void HealthyThirtyFpsJitterStillRecoversWithinTenSeconds()
        {
            var p=new RenderSchedule(new RenderScheduleSettings()); double now=0;
            Feed(p,4,10,ref now); Assert.Equal(1,p.Current.Stage);
            // Real capped-frame windows alternate over/under 30 as their boundaries move.
            int[] frames={15,16,15,16,15,16,15,16,15,16,15,16,15,16,15,16,15,16,15,16};
            int[] durations={506,509,512,507,510,514,517,511,520,506,518,509,515,512,519,510,503,518,509,517};
            for(int i=0;i<frames.Length;i++) p.Observe(S(frames[i],durations[i]),now+=durations[i],true);
            Assert.Equal(0,p.Current.Stage);
        }
        [Fact] public void BriefNearThresholdDipSpendsCreditInsteadOfErasingIt()
        {
            var p=new RenderSchedule(new RenderScheduleSettings()); double now=0;
            Feed(p,4,10,ref now);
            Feed(p,8,15,ref now);
            int before=p.RecoveryMs; Assert.True(before>0);
            p.Observe(S(14,520),now+=520,true);
            p.Observe(S(14,520),now+=520,true);
            Assert.True(p.RecoveryMs>0);
            Feed(p,10,15,ref now); Assert.Equal(0,p.Current.Stage);
        }
        [Fact] public void UserQualityCeilingAndFixedBenchmarkStageAreRespected()
        {
            var p=new RenderSchedule(new RenderScheduleSettings { FixedStage=3 });
            for(int i=0;i<30;i++) p.Observe(S(1),i*500,true);
            Assert.Equal(new RenderSelection(3,.75,"LOW"),p.Current);
            Assert.All(RenderSchedule.Stages("LOW"),s=>Assert.Equal("LOW",s.Quality));
            Assert.Equal(new RenderSelection(0,1,"HIGH"),RenderSchedule.Stages("HIGH")[0]);
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
        [InlineData(1600,900,1200,675,800,450,600,337)]
        [InlineData(1920,1080,1286,724,960,540,643,362)]
        [InlineData(1000,800,750,450,0,0,0,-75)]
        [InlineData(1600,900,1200,675,-40,940,-30,705)]
        public void PointerMappingMatchesAspectFitAndAllowsOutsideDrag(int ow,int oh,int sw,int sh,int x,int y,int ex,int ey)
        {
            var point=WorldPointerMapper.Map(new Point(x,y),new Size(ow,oh),new Size(sw,sh));
            Assert.Equal(new Point(ex,ey),point);
            Assert.Equal(point,WorldPointerMapper.Unpack(WorldPointerMapper.Pack(point)));
        }
    }
}
