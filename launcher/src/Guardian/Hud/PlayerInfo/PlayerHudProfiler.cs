#nullable enable
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using Newtonsoft.Json;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Opt-in bounded samples. Flush once per ten seconds; never log every rendered frame.</summary>
internal sealed class PlayerHudProfiler : IDisposable
{
    private readonly Dictionary<string, List<double>> _samples = new(StringComparer.Ordinal);
    private long _lastFlush = Environment.TickCount64;
    internal string Id { get; } = "php:" + Guid.NewGuid().ToString("N");
    internal static PlayerHudProfiler? CreateFromEnvironment() =>
        Environment.GetEnvironmentVariable("CF7_PLAYER_HUD_PROFILE") == "1" ? new() : null;
    internal void Record(string metric, double value)
    {
        if (!double.IsFinite(value) || value < 0) return;
        if (!_samples.TryGetValue(metric, out var rows)) _samples.Add(metric, rows = new List<double>(320));
        if (rows.Count < 2048) rows.Add(value);
    }
    internal void Render(string surface, double paint, double commit, int width, int height)
    {
        Record(surface + ".paintMs", paint); Record(surface + ".commitMs", commit);
        Record(surface + ".pixels", (long)width * height);
    }
    internal void Flush(bool force = false)
    {
        var now = Environment.TickCount64;
        if (_samples.Count == 0 || (!force && now - _lastFlush < 10000)) return;
        var metrics = new SortedDictionary<string, object>(StringComparer.Ordinal);
        foreach (var (name, rows) in _samples)
        {
            if (rows.Count == 0) continue;
            var sorted = rows.OrderBy(x => x).ToArray();
            metrics.Add(name, new { count = sorted.Length, mean = sorted.Average(),
                p50 = sorted[(sorted.Length - 1) / 2], p95 = sorted[(int)Math.Floor((sorted.Length - 1) * 0.95)], max = sorted[^1] });
        }
        using var process = Process.GetCurrentProcess();
        LogManager.Log("[PlayerHudPerf] " + JsonConvert.SerializeObject(new {
            id = Id, source = "host", windowMs = now - _lastFlush, metrics,
            privateBytes = process.PrivateMemorySize64, gdiHandles = GetGuiResources(process.Handle, 0) }));
        _samples.Clear(); _lastFlush = now;
    }
    public void Dispose() => Flush(true);
    [DllImport("user32.dll")] private static extern uint GetGuiResources(IntPtr process, uint flags);
}
