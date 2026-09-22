using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;

namespace FlashCompositorProbe;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        string report = Path.Combine(AppContext.BaseDirectory, "..", "startup-error.json");
        int reportIndex = Array.IndexOf(args, "--report");
        if (reportIndex >= 0 && reportIndex+1 < args.Length) report = Path.GetFullPath(args[reportIndex+1]);
        try
        {
            var options = Options.Parse(args);
            report = options.Report;
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using var form = new ProbeForm(options);
            Application.Run(form);
            return form.ExitCode;
        }
        catch (Exception error)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(report)!);
            File.WriteAllText(report, JsonSerializer.Serialize(new { success = false, error = error.ToString() }, JsonOptions));
            return 1;
        }
    }
    internal static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, IncludeFields = true };
}

internal sealed record Options(string Adapter, string Report, bool Auto, int PhaseSeconds, int Duration,
    string? FlashExe, string? Swf, nint Hwnd, int Pid)
{
    internal static Options Parse(string[] args)
    {
        var values = new Dictionary<string,string>(StringComparer.Ordinal);
        for (int i = 0; i < args.Length; ++i)
        {
            if (args[i] == "--auto") { values.Add(args[i], "true"); continue; }
            if (!new[] { "--adapter", "--report", "--phase-seconds", "--duration", "--flash-exe", "--swf", "--hwnd", "--pid" }.Contains(args[i]))
                throw new ArgumentException("Unknown option: " + args[i]);
            if (++i == args.Length) throw new ArgumentException("Missing option value");
            values.Add(args[i-1], args[i]);
        }
        string adapter = values.GetValueOrDefault("--adapter", "auto");
        if (!new[] { "auto", "intel", "nvidia" }.Contains(adapter)) throw new ArgumentException("adapter must be auto/intel/nvidia");
        int seconds = int.Parse(values.GetValueOrDefault("--phase-seconds", "5"));
        int duration = int.Parse(values.GetValueOrDefault("--duration", "0"));
        if (seconds < 3 || seconds > 60 || duration < 0 || duration > 3600) throw new ArgumentException("Duration out of range");
        string? exe = values.GetValueOrDefault("--flash-exe"), swf = values.GetValueOrDefault("--swf");
        if ((exe == null) != (swf == null)) throw new ArgumentException("flash-exe and swf must be supplied together");
        nint hwnd = new(long.Parse(values.GetValueOrDefault("--hwnd", "0")));
        int pid = int.Parse(values.GetValueOrDefault("--pid", "0"));
        if ((hwnd == 0) != (pid == 0) || pid < 0 || (exe != null && hwnd != 0)) throw new ArgumentException("Invalid source selection");
        if (hwnd != 0 && values.ContainsKey("--auto")) throw new ArgumentException("Automatic window transitions only apply to a source owned by this probe");
        if (exe != null && (!File.Exists(exe) || !File.Exists(swf))) throw new ArgumentException("Flash executable/SWF missing");
        return new(adapter, Path.GetFullPath(values.GetValueOrDefault("--report", "flash-compositor-report.json")),
            values.ContainsKey("--auto"), seconds, duration, exe == null ? null : Path.GetFullPath(exe),
            swf == null ? null : Path.GetFullPath(swf), hwnd, pid);
    }
}

internal sealed class ProbeForm : Form
{
    private readonly Options options;
    private readonly Panel surface = new() { Dock = DockStyle.Fill, BackColor = Color.Black };
    private readonly Label status = new() { AutoSize = true, ForeColor = Color.White, Padding = new Padding(6) };
    private readonly System.Windows.Forms.Timer poll = new() { Interval = 250 };
    private readonly Stopwatch clock = new();
    private readonly List<object> samples = [];
    private readonly List<PhaseResult> phases = [];
    private readonly string[] plan = ["raw", "night", "nightvision", "occluded", "offscreen", "restored", "minimized", "restore-minimized", "hidden", "restore-hidden", "resized", "viewport-held", "viewport-resumed"];
    private FixtureForm? fixture;
    private Form? occluder;
    private Process? ownedFlash;
    private Process? targetProcess;
    private nint source, native;
    private Rectangle sourceBounds;
    private int phaseIndex, mode;
    private double phaseStart;
    private ulong phaseStartFrames;
    private ulong phaseStartReceived;
    private bool requestedProof;
    private ulong heldPresented;
    private bool heldImageStable=true, resumedGeometry;
    private Native.Stats latest;
    private object? sourceIdentity;
    private string? failure;
    internal int ExitCode { get; private set; } = 1;

    internal ProbeForm(Options options)
    {
        this.options = options;
        Text = "CF7 Flash compositor prototype — NOT DEPLOYED";
        StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(760, 90, 1050, 720);
        BackColor = Color.FromArgb(25,25,25);
        var controls = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 74, AutoSize = false };
        foreach (var item in new[] { ("原画",0), ("夜间",1), ("夜视",2) })
        {
            int selected = item.Item2;
            var button = new Button { Text = item.Item1, AutoSize = true, Enabled = !options.Auto };
            button.Click += (_,_) => SetMode(selected);
            controls.Controls.Add(button);
        }
        controls.Controls.Add(status);
        Controls.Add(surface); Controls.Add(controls);
        poll.Tick += (_,_) => TickProbe();
        Shown += async (_,_) =>
        {
            try { await StartProbe(); }
            catch (Exception e) { failure = e.ToString(); Close(); }
        };
    }

    private async Task StartProbe()
    {
        if (options.FlashExe != null)
        {
            var start = new ProcessStartInfo(options.FlashExe) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(options.Swf)! };
            start.ArgumentList.Add(options.Swf!);
            ownedFlash = Process.Start(start) ?? throw new InvalidOperationException("Flash launch failed");
            for (int i = 0; i < 100 && !IsDisposed; ++i)
            {
                ownedFlash.Refresh();
                if (ownedFlash.HasExited) throw new InvalidOperationException("Owned Flash exited before exposing a window");
                if (ownedFlash.MainWindowHandle != 0) break;
                await Task.Delay(100);
            }
            if (IsDisposed) return;
            source = ownedFlash.MainWindowHandle;
            targetProcess = ownedFlash;
            if (source == 0) throw new InvalidOperationException("No owned Flash HWND after 10 seconds");
            // Only the explicitly launched disposable source may be repositioned.
            Native.SetWindowPos(source, 0, 50, 140, 640, 460, 0x0014);
        }
        else if (options.Hwnd != 0)
        {
            source = options.Hwnd;
            targetProcess = Process.GetProcessById(options.Pid);
        }
        else
        {
            fixture = new FixtureForm(); fixture.Show(); source = fixture.Handle;
            targetProcess = Process.GetCurrentProcess();
        }
        Native.GetWindowThreadProcessId(source, out uint actualPid);
        if (actualPid != targetProcess.Id || targetProcess.HasExited) throw new InvalidOperationException("Source HWND/PID mismatch");
        Native.GetWindowRect(source, out var rect); sourceBounds = rect.Rectangle;
        sourceIdentity = new {
            kind = fixture != null ? "winforms-animation-fixture" : ownedFlash != null ? "owned-flash-asset" : "attached-window",
            pid = targetProcess.Id, hwnd = source.ToInt64(), path = targetProcess.MainModule?.FileName,
            startUtc = targetProcess.StartTime.ToUniversalTime(), swf = options.Swf,
            swfSha256 = options.Swf == null ? null : Hash(options.Swf), initialBounds = sourceBounds
        };
        uint vendor = options.Adapter switch { "intel" => 0x8086, "nvidia" => 0x10de, _ => 0 };
        native = Native.ProbeStart(source, actualPid, surface.Handle, vendor);
        if (native == 0) throw new InvalidOperationException("Native capture initialization failed");
        clock.Start(); poll.Start();
    }

    private void SetMode(int value)
    {
        mode = value;
        if (native != 0) Native.ProbeSetMode(native, value);
    }

    private void TickProbe()
    {
        try
        {
            latest = Native.Read(native);
            double elapsed = clock.Elapsed.TotalSeconds;
            string phase = options.Auto ? plan[phaseIndex] : "interactive";
            double frameAge = latest.LastFrameQpcMs > 0 ? Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency-latest.LastFrameQpcMs : 0;
            samples.Add(new { seconds = elapsed, phase, mode, frameAgeMs = frameAge, stats = latest });
            status.Text = $"{options.Adapter} / {phase}\n{latest.Presented} 帧 · 当前帧龄 {frameAge:F1} ms · {latest.Width}×{latest.Height}";
            if (latest.State == 3) { failure = $"0x{latest.Error:X8}: {latest.Message}"; Close(); return; }
            if (latest.State == 2) { failure = "Source closed before probe completed"; Close(); return; }
            if (options.Auto && phaseIndex < 3 && !requestedProof && elapsed-phaseStart >= 1 && latest.Received > 0)
            {
                Native.ProbeRequestProof(native); requestedProof = true;
            }
            if (options.Auto && elapsed - phaseStart >= options.PhaseSeconds)
            {
                phases.Add(new(phase, latest.Presented - phaseStartFrames, latest.Received-phaseStartReceived,
                    elapsed-phaseStart, latest.ProofCount, latest.ProofMode, latest.ProofMaxError, latest.ProofDistinct));
                if (++phaseIndex == plan.Length) { phaseIndex--; ExitCode = CorePassed() ? 0 : 2; Close(); return; }
                phaseStart = elapsed; phaseStartFrames = latest.Presented; phaseStartReceived = latest.Received; requestedProof = false;
                Transition(plan[phaseIndex]);
            }
            if (phase=="viewport-held" && latest.Presented!=heldPresented) heldImageStable=false;
            if (phase=="viewport-resumed" && latest.Width==320 && latest.Height==180) resumedGeometry=true;
            if (options.Duration > 0 && elapsed >= options.Duration) { ExitCode = latest.Presented > 5 ? 0 : 2; Close(); }
        }
        catch (Exception e) { failure = e.ToString(); Close(); }
    }

    private bool CorePassed() => failure == null && phases.Count == plan.Length
        && phases.Take(3).Sum(p => (long)p.CapturedFrames) >= 30
        && phases.Take(3).Select((p,i) => (fixture == null || p.CapturedFrames >= 10) && p.ProofCount == i+1 && p.ProofMode == i
            && p.ProofMaxError <= 2 && (fixture == null || p.ProofDistinct == 1)).All(p => p)
        && phases.Where(p => p.Name.StartsWith("restore") || p.Name == "resized").All(p => p.CapturedFrames >= (fixture == null ? 1UL : 10UL))
        && latest.CpuReadbacks == latest.ProofCount*6
        && heldImageStable && resumedGeometry
        && phases.Single(p => p.Name=="viewport-resumed").CapturedFrames>0;

    private void Transition(string phase)
    {
        if (fixture == null && ownedFlash == null) throw new InvalidOperationException("Cannot mutate attached source");
        switch (phase)
        {
            case "night": SetMode(1); break;
            case "nightvision": SetMode(2); break;
            case "occluded":
                SetMode(0);
                occluder = new Form { Text = "Probe-owned occluder", BackColor = Color.DarkSlateGray, StartPosition = FormStartPosition.Manual, Bounds = sourceBounds };
                occluder.Show(); break;
            case "offscreen":
                occluder?.Close(); occluder = null;
                Native.SetWindowPos(source, 0, -10000, -10000, 0, 0, 0x0015); break;
            case "restored": RestoreSource(); break;
            case "minimized": Native.ShowWindow(source, 6); break;
            case "restore-minimized": Native.ShowWindow(source, 9); RestoreSource(); break;
            case "hidden": Native.ShowWindow(source, 0); break;
            case "restore-hidden": Native.ShowWindow(source, 4); RestoreSource(); break;
            case "resized":
                Native.SetWindowPos(source, 0, sourceBounds.X, sourceBounds.Y, sourceBounds.Width+120, sourceBounds.Height+80, 0x0014); break;
            case "viewport-held":
                Native.ProbeHoldViewport(native);
                heldPresented=Native.Read(native).Presented;
                Native.SetWindowPos(source,0,sourceBounds.X,sourceBounds.Y,sourceBounds.Width-120,sourceBounds.Height-80,0x0014);
                Native.ProbeSetMode(native,1);
                break;
            case "viewport-resumed":
                if(Native.ProbeSetViewport(native,0,0,320,180,Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency)!=1)
                    throw new InvalidOperationException("Viewport handoff rejected");
                break;
        }
    }
    private void RestoreSource() => Native.SetWindowPos(source, 0, sourceBounds.X, sourceBounds.Y, sourceBounds.Width, sourceBounds.Height, 0x0014);
    private static string Hash(string file) { using var stream = File.OpenRead(file); return Convert.ToHexString(SHA256.HashData(stream)); }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        poll.Stop();
        if (native != 0) { latest = Native.Read(native); Native.ProbeStop(native); native = 0; }
        occluder?.Close(); fixture?.Close();
        bool flashExited = true;
        if (ownedFlash is { HasExited: false })
        {
            ownedFlash.CloseMainWindow(); flashExited = ownedFlash.WaitForExit(3000);
            // Only this probe's child asset player can be terminated on cleanup failure.
            if (!flashExited) { ownedFlash.Kill(); ownedFlash.WaitForExit(3000); }
        }
        if (!options.Auto && failure == null && latest.Presented > 5) ExitCode = 0;
        Directory.CreateDirectory(Path.GetDirectoryName(options.Report)!);
        var report = new {
            schemaVersion = 1, scope = "capture-postprocess-prototype", deployed = false,
            success = ExitCode == 0 && failure == null, automatedCorePassed = options.Auto && CorePassed(),
            humanAcceptance = "NOT_PERFORMED", inputForwarding = "NOT_IMPLEMENTED", performanceBenefit = "NOT_ESTABLISHED",
            failure, source = sourceIdentity,
            options = new { options.Adapter, options.Auto, options.PhaseSeconds, options.Duration }, os = Environment.OSVersion.ToString(),
            binarySha256 = Hash(Environment.ProcessPath!), nativeSha256 = Hash(Path.Combine(AppContext.BaseDirectory, "FlashCompositorNative.dll")),
            managedSha256 = Hash(typeof(Program).Assembly.Location),
            metricsNote = "AgeMs is WGC timestamp-to-dequeue age, not input-to-photon latency; SubmitMs is CPU submission, not GPU execution. Auto mode requests 3 diagnostic proofs, 6 one-pixel CPU readbacks each. Interactive mode performs none.",
            ownedFlashExitedNormally = flashExited, finalStats = latest, phases, samples
        };
        File.WriteAllText(options.Report, JsonSerializer.Serialize(report, Program.JsonOptions));
        base.OnFormClosing(e);
    }
    private sealed record PhaseResult(string Name, ulong PresentedFrames, ulong CapturedFrames, double Seconds,
        uint ProofCount, uint ProofMode, uint ProofMaxError, uint ProofDistinct);
}

internal sealed class FixtureForm : Form
{
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 33 };
    private int frame;
    internal FixtureForm()
    {
        Text = "CF7 capture source fixture"; StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(50,140,640,460); DoubleBuffered = true;
        timer.Tick += (_,_) => { frame++; Invalidate(); }; timer.Start();
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics; int w = ClientSize.Width, h = ClientSize.Height;
        g.Clear(Color.FromArgb(32,48,64));
        g.FillRectangle(Brushes.Red, 0,0,w/3,h/2);
        g.FillRectangle(Brushes.Lime, w/3,0,w/3,h/2);
        g.FillRectangle(Brushes.Blue, 2*w/3,0,w-2*w/3,h/2);
        g.FillEllipse(Brushes.White, (frame*7)%Math.Max(1,w-70),h/2+20,64,64);
        using var font = new Font("Segoe UI", 22);
        g.DrawString($"LIVE FRAME {frame}\n{w} × {h}", font, Brushes.White, 15,h-100);
    }
    protected override void Dispose(bool disposing) { if (disposing) timer.Dispose(); base.Dispose(disposing); }
}

internal static class Native
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct Stats
    {
        public uint Size, State;
        public int Error;
        public uint Vendor, Device, FeatureLevel, Width, Height;
        public ulong Received, Presented, Superseded, Resizes, CpuReadbacks;
        public double AgeMs, MaxAgeMs, SubmitMs, PresentMs, LastFrameQpcMs;
        public uint ProofCount, ProofMode, ProofMaxError, ProofDistinct;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)] public uint[] InputPixels;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)] public uint[] OutputPixels;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Adapter;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Message;
    }
    internal static Stats Read(nint handle)
    {
        var stats = new Stats { Size = (uint)Marshal.SizeOf<Stats>() };
        if (ProbeGetStats(handle, ref stats) != 1) throw new InvalidOperationException("Native stats ABI mismatch");
        return stats;
    }
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern nint ProbeStart(nint source, uint sourcePid, nint output, uint vendor);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern void ProbeSetMode(nint handle, int mode);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern void ProbeRequestProof(nint handle);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] private static extern int ProbeGetStats(nint handle, ref Stats stats);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern void ProbeStop(nint handle);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern void ProbeHoldViewport(nint handle);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeSetViewport(nint handle,int x,int y,int width,int height,double notBefore);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint window, out uint pid);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetWindowRect(nint window, out Rect rect);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool SetWindowPos(nint window,nint after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool ShowWindow(nint window,int command);
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left,Top,Right,Bottom; public readonly Rectangle Rectangle => Rectangle.FromLTRB(Left,Top,Right,Bottom); }
}
