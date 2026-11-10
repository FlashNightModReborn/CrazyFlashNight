using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PerfTelemetryFreshnessTests
    {
        private sealed class Fixture
        {
            internal double Now;
            internal int Generation=1;
            internal long Ordinal;
            internal readonly FpsRingBuffer Buffer;
            internal readonly PerfDecisionEngine Engine;
            internal readonly List<string> Wire=new List<string>();

            internal Fixture()
            {
                Buffer=new FpsRingBuffer(32,()=>Now);
                Buffer.NotifyConnectionReady(Generation);
                Engine=new PerfDecisionEngine(Buffer,null) {IsActive=true};
                Engine.ConfigureRenderSchedule(new RenderScheduleSettings(),(_,__)=>{},
                    ()=>true,()=>2160,PerformancePolicy.Default,Wire.Add,()=>Now);
            }

            internal static string[] Sample(long sequence,int frames=15,int scene=1)
            {
                return ("30|6|0|"+scene+"|v2|"+frames+"|500|0|34|MEDIUM|MEDIUM|0|0|"
                    +sequence+"|0").Split('|');
            }

            internal void Frame(long sequence,int frames=15,int scene=1)
            {
                Raw(Sample(sequence,frames,scene));
            }

            internal void Raw(string[] parts)
            {
                Now+=500;
                Ordinal=Buffer.ObserveFrameIngress(Generation,out double receivedMs);
                Engine.EvaluateRenderSample(parts,Generation,Ordinal,receivedMs);
            }

            internal PerfTelemetrySnapshot Snapshot()
            {
                return Buffer.CapturePerfTelemetry(new CF7Launcher.Bus.PerfTransportSnapshot(
                    Generation,100,25,true));
            }
        }

        [Fact]
        public void StructuralParsingRetainsHighRateSourceButLegacyParserStillRejectsIt()
        {
            string[] parts=Fixture.Sample(1,61);
            Assert.True(RenderSample.TryParseTelemetry(parts,out var sample,out string reason));
            Assert.Null(reason);
            Assert.Equal(122d,sample.Fps);
            Assert.False(RenderSample.IsEligibleForExistingRenderPolicy(sample,out reason));
            Assert.Equal("rate_out_of_policy",reason);
            Assert.False(RenderSample.TryParse(parts,out sample));
            Assert.Null(sample);
        }

        [Fact]
        public void HighRateSourceAdvancesWithoutAdvancingAcceptedPolicyFreshness()
        {
            var f=new Fixture();
            f.Frame(1);
            f.Frame(2,61);
            var s=f.Snapshot();
            Assert.Equal(2,s.SourceSampleSequence.Value);
            Assert.Equal(2,s.SampleFrame.Value);
            Assert.Equal(122d,s.SourceFps.Value);
            Assert.Equal(0d,s.SampleAgeMs.Value);
            Assert.Equal(1,s.AcceptedSampleFrame.Value);
            Assert.Equal(30d,s.AcceptedFps.Value);
            Assert.Equal(500d,s.AcceptedSampleAgeMs.Value);
            Assert.Equal(1,s.AcceptedStalenessFrames.Value);
            Assert.Equal("rate_out_of_policy",s.SampleRejectReason);
            Assert.Equal(1,f.Buffer.Count);
            Assert.Single(f.Wire);
        }

        [Fact]
        public void DuplicateAndRegressedSequencesNeverRefreshSourceOrAcceptedAges()
        {
            var f=new Fixture();
            f.Frame(7);
            f.Frame(7);
            var duplicate=f.Snapshot();
            Assert.Equal("duplicate",duplicate.SampleRejectReason);
            Assert.Equal(7,duplicate.SourceSampleSequence.Value);
            Assert.Equal(1,duplicate.SampleFrame.Value);
            Assert.Equal(1,duplicate.StalenessFrames.Value);
            Assert.Equal(500d,duplicate.SampleAgeMs.Value);
            Assert.Equal(500d,duplicate.AcceptedSampleAgeMs.Value);
            f.Frame(6);
            var regressed=f.Snapshot();
            Assert.Equal("regressed",regressed.SampleRejectReason);
            Assert.Equal(1,regressed.SampleFrame.Value);
            Assert.Equal(2,regressed.StalenessFrames.Value);
            Assert.Equal(1000d,regressed.SampleAgeMs.Value);
            Assert.Equal(1,f.Buffer.Count);
        }

        [Fact]
        public void InvalidOldSceneAndOldConnectionCannotRewriteCurrentFacts()
        {
            var f=new Fixture();
            f.Frame(10,scene:2);
            f.Raw(Fixture.Sample(99,scene:1));
            var oldScene=f.Snapshot();
            Assert.Equal(2,oldScene.SourceScene.Value);
            Assert.Equal(10,oldScene.SourceSampleSequence.Value);
            Assert.Equal(1,oldScene.SampleFrame.Value);
            f.Generation=0;
            f.Raw(Fixture.Sample(88,scene:2));
            var oldConnection=f.Snapshot();
            Assert.Equal(10,oldConnection.SourceSampleSequence.Value);
            Assert.Equal(1,oldConnection.SampleFrame.Value);
            Assert.Equal(2,oldConnection.HostFrameOrdinal.Value);
            f.Generation=1;
            f.Raw(new[]{"bad"});
            var invalid=f.Snapshot();
            Assert.Equal("invalid_shape",invalid.SampleRejectReason);
            Assert.Equal(10,invalid.SourceSampleSequence.Value);
            Assert.Equal(1,invalid.SampleFrame.Value);
        }

        [Fact]
        public void SceneResetClearsFreshnessButRetainsTheOldSceneBarrier()
        {
            var f=new Fixture();
            f.Frame(10,scene:2);
            f.Buffer.NotifySceneReset();
            var reset=f.Snapshot();
            Assert.Null(reset.SourceSampleSequence);
            Assert.Null(reset.AcceptedSampleFrame);
            f.Frame(99,scene:1);
            var late=f.Snapshot();
            Assert.Null(late.SourceSampleSequence);
            Assert.Equal(2,late.HostFrameOrdinal.Value);
            Assert.Equal(1,f.Buffer.Count);
            f.Frame(9,scene:2);
            f.Frame(11,scene:2);
            var retiredSameScene=f.Snapshot();
            Assert.Null(retiredSameScene.SourceScene);
            Assert.Null(retiredSameScene.SourceSampleSequence);
            Assert.Null(retiredSameScene.SampleFrame);
            Assert.Null(retiredSameScene.AcceptedSampleFrame);
            Assert.False(f.Buffer.HasFreshSample);
            Assert.Equal(4,retiredSameScene.HostFrameOrdinal.Value);
            Assert.Equal(1,f.Buffer.Count);
            f.Frame(1,scene:3);
            var current=f.Snapshot();
            Assert.Equal(3,current.SourceScene.Value);
            Assert.Equal(1,current.SourceSampleSequence.Value);
            Assert.Equal(5,current.SampleFrame.Value);
            Assert.Equal(5,current.AcceptedSampleFrame.Value);
            Assert.True(f.Buffer.HasFreshSample);
            Assert.Equal(2,f.Buffer.Count);
        }

        [Fact]
        public void NewConnectionStartsANewOrdinalDomainWithoutCrossGenerationDeltas()
        {
            var f=new Fixture();
            f.Frame(10);
            f.Generation=2;
            f.Buffer.NotifyConnectionReady(2);
            f.Engine.ResetRenderSource();
            f.Frame(1);
            var s=f.Snapshot();
            Assert.Equal(2,s.ConnectionGeneration.Value);
            Assert.Equal(1,s.HostFrameOrdinal.Value);
            Assert.Equal(1,s.SourceSampleSequence.Value);
            Assert.Equal(1,s.SampleFrame.Value);
            Assert.Equal(0,s.StalenessFrames.Value);
            Assert.Equal(1,s.AcceptedSampleFrame.Value);
            Assert.Equal(0,s.AcceptedStalenessFrames.Value);
        }

        [Fact]
        public void AcceptedFpsAndIdentityRemainAtomicDuringConcurrentSnapshots()
        {
            double now=0;
            var buffer=new FpsRingBuffer(16,()=>now);
            buffer.NotifyConnectionReady(1);
            var writer=Task.Run(()=>{
                for(int i=1;i<=2000;i++) {
                    long ordinal=buffer.ObserveFrameIngress(1,out double received);
                    var sample=new RenderSample {Frames=i,DurationMs=1000,Tier=0};
                    buffer.PushAcceptedSample(sample,1,ordinal,received,null,true);
                }
            });
            while(!writer.IsCompleted) {
                var s=buffer.CapturePerfTelemetry(new CF7Launcher.Bus.PerfTransportSnapshot(1,1,0,true));
                if(!s.AcceptedSampleFrame.HasValue) continue;
                Assert.Equal(s.AcceptedSampleFrame.Value,s.AcceptedFps.Value);
                Assert.True(s.AcceptedStalenessFrames.Value>=0);
            }
            writer.GetAwaiter().GetResult();
        }

        [Fact]
        public void FrameOrdinalAdvancesBeforeVisualConsumptionEvenWithoutAnFpsSection()
        {
            var task=new FrameTask(null,null);
            try
            {
                task.HandleRaw("","",null,null,null,4);
                task.HandleRaw("","",null,null,null,4);
                var s=task.FpsBuffer.CapturePerfTelemetry(
                    new CF7Launcher.Bus.PerfTransportSnapshot(4,2,0,true));
                Assert.Equal(2,s.HostFrameOrdinal.Value);
                Assert.Null(s.SourceSampleSequence);
                Assert.InRange(s.FrameIngressAgeMs.Value,0,1000);
            }
            finally { task.Stop(); }
        }
    }
}
