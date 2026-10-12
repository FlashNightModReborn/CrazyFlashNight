using System;
using System.Diagnostics;
using System.Linq;
using System.Text;
using CF7Launcher.Bus;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Tests.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;
using Xunit.Abstractions;

namespace CF7Launcher.Tests.Bus;

// CPU/allocation microbenchmarks. These do not measure gameplay throughput or GPU work.
public class StreamCostBenchmarksTests
{
    private readonly ITestOutputHelper _output;
    public StreamCostBenchmarksTests(ITestOutputHelper output) => _output = output;
    private static string Encode(JObject packet) => Convert.ToBase64String(Encoding.UTF8.GetBytes(packet.ToString(Formatting.None)));
    [Fact]
    public void HudCooldownAndFullPacketCostAgainstTheFrozenProductionConsumer()
    {
        const int count = 1024;
        string full = Encode(PlayerHudStateTests.Full());
        var deltas = Enumerable.Range(0, count).Select(i => Encode(new JObject { ["v"] = 1, ["epoch"] = 1,
            ["seq"] = i + 2, ["full"] = false, ["visible"] = true,
            ["groups"] = new JObject { ["cooldowns"] = new JArray(Enumerable.Range(0, 18).Select(_ => new JArray(0, i % 20, 30))) } })).ToArray();
        var fulls = Enumerable.Range(0, count).Select(i => Encode(PlayerHudStateTests.Full(seq: i + 2))).ToArray();
        foreach (bool delta in new[] { true, false })
        {
            long oldBytes = 0, newBytes = 0, oldTicks = 0, newTicks = 0;
            for (int pass = -1; pass < 6; pass++)
            {
                for (int turn = 0; turn < 2; turn++)
                {
                    bool baseline = (turn == 0) == (pass % 2 == 0);
                    var old = new PlayerHudStateLegacyFixture(); var next = new PlayerHudState();
                    Assert.True(baseline ? old.Receive(full, 1) : next.Receive(full, 1));
                    long allocated = GC.GetAllocatedBytesForCurrentThread(); long started = Stopwatch.GetTimestamp();
                    foreach (string packet in delta ? deltas : fulls)
                        if (!(baseline ? old.Receive(packet, 2) : next.Receive(packet, 2))) throw new InvalidOperationException("benchmark packet rejected");
                    long elapsed = Stopwatch.GetTimestamp() - started; long bytes = GC.GetAllocatedBytesForCurrentThread() - allocated;
                    Assert.Equal(count + 1, baseline ? old.AcceptedPackets : next.AcceptedPackets);
                    if (pass < 0) continue;
                    if (baseline) { oldBytes += bytes; oldTicks += elapsed; } else { newBytes += bytes; newTicks += elapsed; }
                }
            }
            _output.WriteLine("[STREAM_HUD_COST] workload={0} packets={1} order=AB-BA passes=6 baselineBytes={2} candidateBytes={3} baselineMs={4:F3} candidateMs={5:F3}",
                delta ? "cooldowns-only" : "full", count * 6, oldBytes, newBytes,
                oldTicks * 1000d / Stopwatch.Frequency, newTicks * 1000d / Stopwatch.Frequency);
        }
    }
    [Fact]
    public void FrameParserAllocationOnDenseOrderedWireAgainstTheRetainedLegacyPath()
    {
        string wire = "F12|34|1\x01" + new string('n', 2400) + "\x02" + "30|30|0" + "\x03" + "s:1|ga:slot"
            + "\x04" + "1|1|1|0" + "\x05" + new string('b', 64000) + "\x06" + new string('c', 4000)
            + "\x07" + new string('r', 16000) + "\x08" + new string('a', 16000) + "\x09" + new string('l', 4000);
        Assert.Equal(FrameSections.Legacy(wire), FrameSections.Parse(wire));
        long oldBytes = 0, newBytes = 0, oldTicks = 0, newTicks = 0, observed = 0;
        const int count = 256;
        for (int pass = -1; pass < 6; pass++)
            for (int turn = 0; turn < 2; turn++)
            {
                bool baseline = (turn == 0) == (pass % 2 == 0);
                long allocated = GC.GetAllocatedBytesForCurrentThread(); long started = Stopwatch.GetTimestamp();
                for (int i = 0; i < count; i++)
                {
                    var parsed = baseline ? FrameSections.Legacy(wire) : FrameSections.Parse(wire);
                    observed += parsed.Rays.Length + parsed.Camera.Length;
                }
                long elapsed = Stopwatch.GetTimestamp() - started, bytes = GC.GetAllocatedBytesForCurrentThread() - allocated;
                if (pass < 0) continue;
                if (baseline) { oldBytes += bytes; oldTicks += elapsed; } else { newBytes += bytes; newTicks += elapsed; }
            }
        Assert.True(observed > 0);
        _output.WriteLine("[STREAM_FRAME_COST] packets={0} order=AB-BA passes=6 baselineBytes={1} candidateBytes={2} baselineMs={3:F3} candidateMs={4:F3}",
            count * 6, oldBytes, newBytes, oldTicks * 1000d / Stopwatch.Frequency, newTicks * 1000d / Stopwatch.Frequency);
    }
}
