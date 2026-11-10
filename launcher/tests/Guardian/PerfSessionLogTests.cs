using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PerfSessionLogTests
    {
        private static string CreateRoot()
        {
            string root=Path.Combine(Directory.GetCurrentDirectory(),"tmp",
                "perf-session-log-tests",Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            return root;
        }

        private static PerfTelemetrySnapshot Sample()
        {
            return new PerfTelemetrySnapshot
            {
                ConnectionGeneration=1,HostFrameOrdinal=10,SourceScene=2,
                SourceSampleSequence=3,SampleFrame=9,StalenessFrames=1,
                SampleAgeMs=20,AcceptedSampleFrame=8,AcceptedStalenessFrames=2,
                AcceptedSampleAgeMs=40,FrameIngressAgeMs=5,TransportAgeMs=6,
                InboundCount=20,SourceFps=30,AcceptedFps=29,
                Paused=false,Foreground=true,SurfaceGate=true,Connected=true
            };
        }

        private static string[] ReadLinesShared(string path)
        {
            using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,
                FileShare.ReadWrite|FileShare.Delete))
            using(var reader=new StreamReader(stream)) {
                var lines=new List<string>();
                while(!reader.EndOfStream) lines.Add(reader.ReadLine());
                return lines.ToArray();
            }
        }

        private static List<JObject> ReadEvents(string path)
        {
            return ReadLinesShared(path).Where(line=>line.Length>0)
                .Select(line=>JObject.Parse(line)).ToList();
        }

        [Fact]
        public void SlowPerfWriteCannotHoldOrdinaryGameLog()
        {
            string root=CreateRoot();
            using var entered=new ManualResetEventSlim();
            using var release=new ManualResetEventSlim();
            Task writer=null,ordinary=null;
            bool completed=false;
            try {
                LogManager.InitFileLog(root);
                LogManager.PerfSessionWriteFailureForTests=()=> {
                    entered.Set();
                    if(!release.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException("slow write fixture");
                };
                writer=Task.Run(()=>LogManager.WritePerfSessionSample(Sample()));
                Assert.True(entered.Wait(TimeSpan.FromSeconds(3)));
                ordinary=Task.Run(()=>LogManager.Log("ordinary game log during diagnostic write"));
                completed=ordinary.Wait(TimeSpan.FromSeconds(1));
            } finally {
                release.Set();
                writer?.GetAwaiter().GetResult();
                ordinary?.GetAwaiter().GetResult();
                LogManager.Shutdown();
                Directory.Delete(root,true);
            }
            Assert.True(completed,"Game log waited for the diagnostic disk writer");
        }

        [Fact]
        public void HostMinimizeUpdatesContextWhenSourceFramesStop()
        {
            string root=CreateRoot();
            var task=new FrameTask(null,null);
            try {
                var activation=new AppActivationState();
                var engine=new PerfDecisionEngine(task.FpsBuffer,null);
                engine.SetActivationState(activation);task.SetDecisionEngine(engine);
                LogManager.InitFileLog(root);
                string path=LogManager.PerfSessionLogPath;
                task.HandleRaw("","","30|6|0|1|v2|15|500|0|34|MEDIUM|MEDIUM|0|0|1|0",null,null,1);
                task.SamplePerfTelemetryForTests();
                activation.OnMinimizeChanged(true);
                task.SamplePerfTelemetryForTests();
                var samples=ReadEvents(path).Where(x=>x.Value<string>("event")=="perf_sample").ToArray();
                Assert.Equal(2,samples.Length);
                Assert.True(samples[0].Value<bool>("foreground"));
                Assert.False(samples[1].Value<bool>("foreground"));
                Assert.Equal(samples[0]["hostFrameOrdinal"],samples[1]["hostFrameOrdinal"]);
                Assert.Equal(samples[0]["sourceSampleSequence"],samples[1]["sourceSampleSequence"]);
            } finally {
                task.Stop();LogManager.Shutdown();Directory.Delete(root,true);
            }
        }

        [Fact]
        public void StopPreventsFurtherTelemetryWrites()
        {
            string root=CreateRoot();
            var task=new FrameTask(null,null);
            try
            {
                double now=0;
                DateTime utc=DateTime.UtcNow;
                LogManager.InitFileLog(root,()=>utc,()=>now);
                string path=LogManager.PerfSessionLogPath;
                task.SamplePerfTelemetryForTests();
                Assert.Equal(1,ReadEvents(path).Count(e=>e.Value<string>("event")=="perf_sample"));
                task.Stop();
                int lines=ReadLinesShared(path).Count();
                now=10000;
                task.SamplePerfTelemetryForTests();
                task.SamplePerfTelemetryForTests();
                Assert.Equal(lines,ReadLinesShared(path).Count());
            }
            finally
            {
                task.Stop();
                LogManager.Shutdown();
                Directory.Delete(root,true);
            }
        }

        [Fact]
        public void WriteFailureDisablesOnlyDiagnosticsAndReportsOnce()
        {
            string root=CreateRoot();
            var logs=new List<string>();
            LogManager.SetSink(logs.Add);
            try
            {
                double now=0;
                DateTime utc=DateTime.UtcNow;
                LogManager.InitFileLog(root,()=>utc,()=>now);
                string path=LogManager.PerfSessionLogPath;
                LogManager.PerfSessionWriteFailureForTests=()=>throw new IOException("fixture");
                LogManager.WritePerfSessionSample(Sample());
                LogManager.WritePerfSessionSample(Sample());
                LogManager.InitFileLog(root,()=>utc,()=>now);
                Assert.Equal(1,logs.Count(line=>line.Contains("event=perf_session_disabled")));
                Assert.Single(Directory.GetFiles(Path.Combine(root,"logs","perf-sessions"),"*.jsonl"));
                Assert.Equal(1,ReadEvents(path).Count(e=>e.Value<string>("event")=="session_start"));
                Assert.Equal(0,ReadEvents(path).Count(e=>e.Value<string>("event")=="perf_sample"));
            }
            finally
            {
                LogManager.Shutdown();
                LogManager.ResetSink();
                Directory.Delete(root,true);
            }
        }

        [Fact]
        public void QueuedRenderEventFlushFailureReportsOnceBeforeShutdown()
        {
            string root=CreateRoot();
            var logs=new List<string>();
            LogManager.SetSink(logs.Add);
            try
            {
                double now=0;
                DateTime utc=DateTime.UtcNow;
                LogManager.InitFileLog(root,()=>utc,()=>now);
                string path=LogManager.PerfSessionLogPath;
                var target=new RenderSelection(2,540,"LOW",2);
                LogManager.EnqueueRenderScheduleRequest(7,3,target,"sustained_low_fps");
                LogManager.PerfSessionWriteFailureForTests=()=>throw new IOException("queued_flush_failure");
                LogManager.WritePerfSessionSample(Sample());
                Assert.Equal(1,logs.Count(line=>line.Contains("event=perf_session_disabled")));
                LogManager.WritePerfSessionSample(Sample());
                LogManager.EnqueueRenderSchedulePresented(7,target,
                    new System.Drawing.Size(960,540),"sustained_low_fps");
                Assert.Equal(1,logs.Count(line=>line.Contains("event=perf_session_disabled")));
                LogManager.Shutdown();
                Assert.Equal(1,logs.Count(line=>line.Contains("event=perf_session_disabled")));
                Assert.Equal(1,ReadEvents(path).Count(e=>e.Value<string>("event")=="session_start"));
                Assert.Equal(0,ReadEvents(path).Count(e=>e.Value<string>("event")=="render_schedule_request"));
                Assert.Equal(0,ReadEvents(path).Count(e=>e.Value<string>("event")=="perf_sample"));
            }
            finally
            {
                LogManager.Shutdown();
                LogManager.ResetSink();
                Directory.Delete(root,true);
            }
        }

        [Fact]
        public void FourHoursOfFakeOneHertzSamplesKeepMonotonicElapsedTime()
        {
            string root=CreateRoot();
            DateTime start=new DateTime(2026,11,9,0,0,0,DateTimeKind.Utc);
            DateTime utc=start;
            double now=0;
            try
            {
                LogManager.InitFileLog(root,()=>utc,()=>now);
                string path=LogManager.PerfSessionLogPath;
                var sample=Sample();
                const int seconds=4*60*60;
                for(int i=0;i<=seconds;i++) {
                    utc=start.AddSeconds(i);
                    now=i*1000d;
                    LogManager.WritePerfSessionSample(sample);
                }
                LogManager.Shutdown();
                long samples=0;
                JObject first=null,last=null,end=null;
                foreach(var item in ReadEvents(path)) {
                    if(item.Value<string>("event")=="perf_sample") {
                        if(first==null) first=item;
                        last=item;
                        samples++;
                    } else if(item.Value<string>("event")=="session_end") end=item;
                }
                Assert.Equal(seconds+1,samples);
                Assert.Equal(1,first.Value<long>("sessionSampleSequence"));
                Assert.Equal(0d,first.Value<double>("elapsedMs"));
                Assert.Equal(seconds+1,last.Value<long>("sessionSampleSequence"));
                Assert.Equal(seconds*1000d,last.Value<double>("elapsedMs"));
                Assert.Equal(start.AddSeconds(seconds),last.Value<DateTime>("utc").ToUniversalTime());
                Assert.NotNull(end);
                Assert.Equal(seconds*1000d,end.Value<double>("elapsedMs"));
            }
            finally
            {
                LogManager.Shutdown();
                Directory.Delete(root,true);
            }
        }

        [Fact]
        public void RestartWithSameUtcCreatesANewFileWithoutOverwritingTheOldSession()
        {
            string root=CreateRoot();
            DateTime utc=new DateTime(2026,11,9,1,2,3,DateTimeKind.Utc);
            double now=0;
            try
            {
                LogManager.InitFileLog(root,()=>utc,()=>now);
                string first=LogManager.PerfSessionLogPath;
                LogManager.Shutdown();
                string original=File.ReadAllText(first);
                LogManager.InitFileLog(root,()=>utc,()=>now);
                string second=LogManager.PerfSessionLogPath;
                LogManager.Shutdown();
                Assert.NotEqual(first,second);
                Assert.Equal(original,File.ReadAllText(first));
                Assert.Equal(2,Directory.GetFiles(Path.Combine(root,"logs","perf-sessions"),"*.jsonl").Length);
                var start=ReadEvents(second)[0];
                Assert.Equal(typeof(LogManager).Assembly.ManifestModule.ModuleVersionId.ToString("D"),
                    start.Value<string>("coreMvid"));
                Assert.Equal(JTokenType.Null,start["taskProgress"].Type);
                Assert.Equal("not_exported",start.Value<string>("taskProgressReason"));
                Assert.True(start["buildIdentity"].Type!=JTokenType.Null
                    || start.Value<string>("buildIdentityReason")!=null);
            }
            finally
            {
                LogManager.Shutdown();
                Directory.Delete(root,true);
            }
        }

        [Fact]
        public void RenderRequestAndPresentationAreQueuedSeparatelyFromFrameThreads()
        {
            string root=CreateRoot();
            DateTime utc=DateTime.UtcNow;
            double now=100;
            try
            {
                LogManager.InitFileLog(root,()=>utc,()=>now);
                string path=LogManager.PerfSessionLogPath;
                var target=new RenderSelection(2,540,"LOW",2);
                LogManager.EnqueueRenderScheduleRequest(7,3,target,"sustained_low_fps");
                LogManager.EnqueueRenderSchedulePresented(7,target,
                    new System.Drawing.Size(960,540),"sustained_low_fps");
                Assert.Equal(1,ReadLinesShared(path).Count());
                now=125;
                LogManager.WritePerfSessionSample(Sample());
                LogManager.Shutdown();
                var events=ReadEvents(path);
                Assert.Equal(new[]{"session_start","render_schedule_request",
                    "render_schedule_presented","perf_sample","session_end"},
                    events.Select(e=>e.Value<string>("event")).ToArray());
                var request=events[1];
                var presented=events[2];
                Assert.Equal(0d,request.Value<double>("elapsedMs"));
                Assert.Equal(2,request.Value<int>("targetStage"));
                Assert.Equal(540,request.Value<int>("targetHeight"));
                Assert.Equal("LOW",request.Value<string>("targetQuality"));
                Assert.Equal(0d,presented.Value<double>("elapsedMs"));
                Assert.Equal(2,presented.Value<int>("actualStage"));
                Assert.Equal(960,presented.Value<int>("sourceWidth"));
                Assert.Equal("sustained_low_fps",presented.Value<string>("reason"));
            }
            finally
            {
                LogManager.Shutdown();
                Directory.Delete(root,true);
            }
        }
    }
}
