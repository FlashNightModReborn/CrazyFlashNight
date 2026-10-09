using System;
using System.Collections.Generic;
using System.Drawing;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class RenderApplicationTests
    {
        private sealed class Fixture
        {
            internal double Now;
            internal readonly FpsRingBuffer Buffer;
            internal readonly PerfDecisionEngine Engine;
            internal readonly List<string> Wire=new();
            internal readonly List<(long Command,RenderSelection Selection)> Applications=new();
            internal long Sequence;
            internal int SourceHeight=2160;
            internal bool SurfaceReady=true;
            internal Fixture()
            {
                Buffer=new FpsRingBuffer(100,()=>Now);
                Engine=new PerfDecisionEngine(Buffer,null) {IsActive=true};
                Engine.ConfigureRenderSchedule(new RenderScheduleSettings(),(id,s)=>Applications.Add((id,s)),
                    ()=>SurfaceReady,()=>SourceHeight,PerformancePolicy.Default,Wire.Add,()=>Now);
            }
            internal void Sample(long applied=0,string quality="MEDIUM",int frames=15,int scene=1,bool paused=false)
            {
                Now+=500;
                Engine.EvaluateRenderSample(($"30|6|{(quality=="LOW"?1:0)}|{scene}|v2|{frames}|500|0|34|MEDIUM|{quality}|0|{(paused?1:0)}|{++Sequence}|{applied}").Split('|'));
            }
            internal void Complete(int index=0)
            {
                var a=Applications[index];
                Engine.ConfirmRenderApplied(a.Command,a.Selection,new Size(a.Selection.Height*16/9,a.Selection.Height));
            }
        }
        [Fact] public void As2AcknowledgementIsNotResizeCompletionAndCannotRunAhead()
        {
            var f=new Fixture(); f.Sample(); Assert.Single(f.Wire);
            f.Sample(1); Assert.Single(f.Applications);
            for(int i=0;i<40;i++) f.Sample(1,frames:2);
            Assert.Single(f.Wire); Assert.Equal("switching",f.Buffer.Performance.Status);
            Assert.Equal(0,f.Buffer.Performance.Height);
            f.Complete(); Assert.Equal(1080,f.Buffer.Performance.Height); Assert.Equal("ready",f.Buffer.Performance.Status);
        }
        [Fact] public void ChangingPolicyDiscardsOldQueuedCompletionAndRequiresExactQuality()
        {
            var f=new Fixture(); f.Sample(); f.Sample(1);
            f.Engine.ConfigurePerformancePolicy(new PerformancePolicy("quality","fixed",540));
            f.Complete(); Assert.Equal(0,f.Buffer.Performance.Height);
            f.Sample(1); Assert.Equal(2,f.Wire.Count);
            f.Sample(2); Assert.Single(f.Applications);
            f.Sample(2,"HIGH"); Assert.Equal(2,f.Applications.Count);
            f.Complete(1); Assert.Equal(540,f.Buffer.Performance.Height); Assert.Equal("HIGH",f.Buffer.Performance.Quality);
            for(int i=0;i<40;i++) f.Sample(2,"HIGH",2);
            Assert.Equal(2,f.Wire.Count); Assert.Equal("fixed",f.Buffer.Performance.Mode);
        }
        [Fact] public void ReconnectKeepsDisplayButRequiresNewEpochCommandAndAdoption()
        {
            var f=new Fixture(); f.Sample(); f.Sample(1); f.Complete();
            f.Engine.ResetRenderSource(); Assert.Equal("disconnected",f.Buffer.Performance.Status);
            Assert.Equal(1080,f.Buffer.Performance.Height);
            f.Sample(scene:2); Assert.Equal(2,f.Wire.Count);
            f.Engine.ConfirmRenderApplied(1,f.Applications[0].Selection,new Size(1920,1080));
            Assert.Equal("switching",f.Buffer.Performance.Status);
            f.Sample(2,scene:2); f.Complete(1); Assert.Equal("ready",f.Buffer.Performance.Status);
        }
        [Fact] public void LegacySyntheticAndOutOfOrderSamplesNeverEnterHudHistory()
        {
            var f=new Fixture();
            f.Engine.EvaluateRenderSample("28|6|1|1".Split('|')); Assert.False(f.Buffer.HasData);
            f.Sample(); Assert.Equal(1,f.Buffer.Count);
            f.Sequence=0; f.Sample(); Assert.Equal(1,f.Buffer.Count);
            f.Now+=2100; Assert.Equal("stale",f.Buffer.Performance.Status);
        }
        [Fact] public void OversizedSourceIsNotReportedAsAnAppliedBudget()
        {
            var f=new Fixture(); f.Sample(); f.Sample(1);
            Assert.Throws<InvalidOperationException>(()=>f.Engine.ConfirmRenderApplied(1,f.Applications[0].Selection,new Size(3840,2160)));
            Assert.Equal(0,f.Buffer.Performance.Height); Assert.Equal("unavailable",f.Buffer.Performance.Status);
            f.Sample(1); Assert.Equal("unavailable",f.Buffer.Performance.Status); Assert.Single(f.Wire);
        }
        [Fact] public void ActualQualityDriftRequestsACompleteNewTargetWithoutChangingPolicy()
        {
            var f=new Fixture(); f.Sample(); f.Sample(1); f.Complete();
            f.Sample(1,"HIGH"); Assert.Equal(2,f.Wire.Count);
            Assert.Contains("|MEDIUM|2|",f.Wire[1]); Assert.Equal("switching",f.Buffer.Performance.Status);
        }
    }
}
