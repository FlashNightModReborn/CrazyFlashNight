using System;
using System.Collections.Generic;
using System.Linq;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Diagnostic
{
    public class InputLatencyProbeTests
    {
        private sealed class Clock
        {
            internal double Now;
            internal readonly Queue<Action> Posted = new();
            internal readonly List<(string Name, JObject Data)> Events = new();
            internal InputLatencyProbe Create() => new(Posted.Enqueue,
                (name, data) => Events.Add((name, JObject.FromObject(data))), "test", () => Now);
            internal JObject Last(string name) => Events.Last(e => e.Name == name).Data;
        }
        [Theory]
        [InlineData(null, true, false)]
        [InlineData("true", true, false)]
        [InlineData("1", false, false)]
        [InlineData("1", true, true)]
        public void RequiresExactOptInAndExistingRecording(string value, bool recording, bool expected)
            => Assert.Equal(expected, InputLatencyProbe.IsRequested(value, recording));

        [Fact]
        public void BlockedUiQueuesOnePingAndMeasuresDelayOnRecovery()
        {
            var clock = new Clock(); using var probe = clock.Create();
            probe.BeginTransition("tr:1", 1, "loading");
            clock.Now = 20; probe.Pulse();
            clock.Now = 40; probe.Pulse(); clock.Now = 60; probe.Pulse();
            Assert.Single(clock.Posted);
            clock.Now = 110; clock.Posted.Dequeue()();
            Assert.Equal("ui_dispatch", clock.Last("input_latency.slow").Value<string>("metric"));
            Assert.Equal(90, clock.Last("input_latency.slow").Value<double>("ms"));
        }
        [Fact]
        public void TimerSchedulingGapIsNotUiQueueDelay()
        {
            var clock = new Clock(); using var probe = clock.Create();
            probe.BeginTransition("tr:1", 1, "loading");
            clock.Now = 120; probe.Pulse(); clock.Posted.Dequeue()();
            Assert.Single(clock.Events, e => e.Name == "input_latency.slow");
            Assert.Equal("sampler_gap", clock.Last("input_latency.slow").Value<string>("metric"));
        }
        [Fact]
        public void DelayedCallbacksCannotWriteIntoNextTransition()
        {
            var clock = new Clock(); using var probe = clock.Create();
            probe.BeginTransition("tr:1", 1, "loading"); clock.Now = 20; probe.Pulse();
            var oldSample = probe.BeginSample("cursor_queue");
            clock.Now = 80; probe.BeginTransition("tr:2", 1, "cover"); probe.Pulse();
            Assert.Single(clock.Posted);
            clock.Posted.Dequeue()(); oldSample.Dispose();
            Assert.Empty(clock.Events.Where(e => e.Name == "input_latency.slow"));
            clock.Now = 100; probe.Pulse(); clock.Now = 150; clock.Posted.Dequeue()();
            Assert.Equal("tr:2", clock.Last("input_latency.slow").Value<string>("id"));
            Assert.Equal(50, clock.Last("input_latency.slow").Value<double>("ms"));
        }
        [Fact]
        public void SamplesRetainStartingPhaseAndStopAfterBoundedTail()
        {
            var clock = new Clock(); using var probe = clock.Create();
            probe.BeginTransition("tr:1", 1, "loading");
            var sample = probe.BeginSample("surface_present");
            probe.SetPhase("base_ready", finished: true);
            clock.Now = 50; sample.Dispose();
            Assert.Equal("loading", clock.Last("input_latency.slow").Value<string>("phase"));
            clock.Now = 2000; probe.Pulse();
            Assert.Empty(clock.Posted);
            int count = clock.Events.Count;
            clock.Now = 4000; probe.Observe("hook_delivery", 500); probe.Pulse();
            Assert.Equal(count, clock.Events.Count);
        }
        [Fact]
        public void SlowEventBudgetKeepsPeaksAndReportsOmissions()
        {
            var clock = new Clock(); using var probe = clock.Create();
            probe.BeginTransition("tr:1", 1, "loading");
            for (int i = 0; i < 100; i++) probe.Observe("hook_delivery", 40 + i);
            clock.Now = 30000; probe.Pulse();
            Assert.Equal(InputLatencyProbe.SlowEventLimit, clock.Events.Count(e => e.Name == "input_latency.slow"));
            var summary = clock.Last("input_latency.summary");
            Assert.Equal(36, summary.Value<int>("omittedSlowEvents"));
            var hook = summary["metrics"].Single(m => m.Value<string>("name") == "hook_delivery");
            Assert.Equal(139, hook.Value<double>("maxMs"));
            Assert.Equal(100, hook.Value<int>("slow"));
        }

        [Fact]
        public void HookWorkAndDownstreamChainAreSeparateFromDeliveryDelay()
        {
            var clock = new Clock(); using var probe = clock.Create();
            probe.BeginTransition("startup:1", 0, "startup");
            probe.Observe("hook_delivery", 90);
            var own = probe.BeginSample("hook_callback");
            clock.Now = 10; own.Dispose();
            var chain = probe.BeginSample("hook_chain");
            clock.Now = 110; chain.Dispose();
            probe.Dispose();
            var metrics = clock.Last("input_latency.summary")["metrics"];
            Assert.Equal(10, metrics.Single(m => m.Value<string>("name") == "hook_callback").Value<double>("maxMs"));
            Assert.Equal(100, metrics.Single(m => m.Value<string>("name") == "hook_chain").Value<double>("maxMs"));
            Assert.Equal(90, metrics.Single(m => m.Value<string>("name") == "hook_delivery").Value<double>("maxMs"));
        }
        [Fact]
        public void DisposeAndDispatcherFailureNeverRetryOrReviveObservation()
        {
            var clock = new Clock(); var probe = clock.Create();
            probe.BeginTransition("tr:1", 1, "loading"); clock.Now = 20; probe.Pulse();
            probe.Dispose(); int count = clock.Events.Count;
            clock.Now = 500; clock.Posted.Dequeue()(); probe.Pulse();
            Assert.Equal(count, clock.Events.Count);
            int attempts = 0;
            using var broken = new InputLatencyProbe(_ => { attempts++; throw new InvalidOperationException(); },
                (_, _) => throw new Exception("sink failure"), "test", () => clock.Now);
            broken.BeginTransition("tr:2", 1, "cover"); broken.Pulse(); broken.Pulse();
            Assert.Equal(1, attempts);
        }
    }
}
